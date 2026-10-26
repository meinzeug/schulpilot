"""Exact original words, without inferred sentence roles or replacement text."""
import re

from . import package_prepared_graphics as prepared
from .package_prepared_scenes import Binding as SourceBinding
from .subject_content import Graphic, validate_question
from .visual_references import _meaningful

REFERENCE = "language.sentence.roles"
REVISION = "package-original-sentence-1"
RULES = """
package-original-sentence-1: Die angebotenen Grafiken zeigen ausschließlich die
Originalwörter eines vollständigen belegten Satzes in ursprünglicher Reihenfolge.
Ein Wortkasten ist KEIN automatisch bestimmtes Satzglied. Keine erfundenen Rollen,
Farbbedeutungen oder Subjekt-/Prädikatmarkierungen ergänzen. Wähle presentation.blocks=[ID]
mit exakt derselben Referenz, Quelle und Aufdeckstufe. Jede Frage nennt den vollständigen
original_sentence ihrer Grafik wortgetreu einschließlich Satzzeichen im Prompt.
Frage nach dem bestätigten Unterrichtsziel, nicht bloß nach einem Listenplatz.
Schreibe eine kurze verständliche Erklärung, wie das Kind den Satz untersuchen kann;
maximal350Zeichen. Keine ungeprüfte Schülerkorrektur als Regel verwenden.
"""


def sentence_bases(content):
    for line in content.splitlines():
        sentence = line.strip()
        if not 8 <= len(sentence) <= 180 or not re.fullmatch(r"[A-ZÄÖÜ][^.!?:;|=0-9]+[.!?]", sentence):
            continue
        words = sentence[:-1].split()
        if not 3 <= len(words) <= 12 or any(not re.fullmatch(r"[A-Za-zÄÖÜäöüß]+(?:['’\-][A-Za-zÄÖÜäöüß]+)*", word) for word in words):
            continue
        yield {"kind": "sentence", "title": words[0], "source_excerpt": sentence,
            "labels": words, "numbers": [], "connections": [], "marks": [], "unit": "", "variant": "",
            "scene": None, "text_probe": None, "lab": None}


def compile_candidates(payload):
    context, groups = payload.get("visual_context") or {}, payload.get("selected_groups") or []
    if payload.get("package_partition") is None or not context.get("required") or len(groups) != 1 or groups[0].get("subject") != "Deutsch":
        return []
    group = groups[0].get("id")
    references = [row for row in context.get("references", []) if row.get("id") == REFERENCE
        and row.get("subject") == "Deutsch" and type(row.get("version")) is int and row.get("digest")]
    result, count = [], 0
    for source in context.get("sources", []):
        if (source.get("subject") != "Deutsch" or source.get("group_id") != group or source.get("source_type")
                or not isinstance(source.get("content"), str)
                or not re.search(r"\b(?:Satzglieder?|Subjekt|Prädikat)\b", source.get("topic", "") + "\n" + source["content"], re.I)):
            continue
        for base in sentence_bases(source["content"]):
            if count >= 6:
                break
            added = False
            for reference in references:
                for stage in prepared.STAGES:
                    try:
                        block = Graphic.model_validate({**base, "disclosure": stage})
                        _meaningful(block, reference, sources=[source["content"]])
                        validate_question({"version": 1, "evidence_kind": "knowledge", "blocks": [block.model_dump()]},
                            {"prompt": "", "type": "short", "answer": "", "accepted": []},
                            [source["content"]], ("sentence",), structured=True, subject="Deutsch")
                    except ValueError:
                        continue
                    row = {"subject": "Deutsch", "group_id": group, "kind": "sentence", "disclosure": stage,
                        "reference": {"id": REFERENCE, "version": reference["version"]}, "source_refs": [source["ref"]],
                        "text": "Lies die Originalwörter in ihrer Reihenfolge. Ein Wortkasten ist noch kein bestimmtes Satzglied.",
                        "block": block.model_dump(mode="json")}
                    row["id"] = "psg_" + prepared._digest({"revision": REVISION, "source": source, "candidate": row,
                        "reference_digest": reference["digest"], "plan": payload.get("package_plan_digest"),
                        "partition": payload["package_partition"]})[:24]
                    result.append(row)
                    added = True
            count += added
    return result


def prompt_pattern(candidate):
    return r"(^|[^\w])" + re.escape(candidate["block"]["source_excerpt"]) + r"($|[^\w])"


class Binding(SourceBinding):
    @property
    def rules(self):
        return RULES

    def offered(self, candidate):
        return candidate["kind"] == "sentence" and candidate["reference"]["id"] == REFERENCE

    def question_bound(self, candidate, question):
        return bool(re.search(prompt_pattern(candidate), question.get("prompt", "")))

    @property
    def context(self):
        value = super().context
        for row, candidate in zip(value["candidates"], self.candidates, strict=True):
            row["original_sentence"] = candidate["block"]["source_excerpt"]
        return {**value, "revision": REVISION}


def bind_schema(schema, payload):
    candidates = compile_candidates(payload)
    if not candidates:
        return None
    return prepared.bind_candidates(schema, Binding(tuple(candidates)), question_kinds=("sentence",), prompt_pattern=prompt_pattern)
