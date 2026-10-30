"""Finite source-bound choices for existing non-maths package recipes.

Whole literal arrow lines are scenes. Explicit German word-part plus lines use
one dedicated existing-renderer recipe; a plus never becomes a directed edge.
No DB writes, invented relations, provider call, answer or source repair.
"""
import re
import unicodedata

from . import package_prepared_graphics as prepared
from .subject_content import PROFILES, Graphic, validate_question
from .visual_reference_schemas import ExplanationStep
from .visual_references import _meaningful

REVISION = "package-source-graphics-3"
WORD_PARTS_REFERENCE = "german.word_formation.parts"
LANGUAGE_COMPARISON_REFERENCE = "language.forms.original_comparison"
# Four full four-label scenes keep large original sources inside the existing
# conservative request envelope. The complete source and topic plan stay intact.
MAX_SOURCE_BASE_CANDIDATES = 4
RULES = """
package-source-graphics-3: Wähle ausschließlich eine bereitgestellte Grafik-ID zum selben
Fach, Quellenbeleg und Lernziel. presentation.blocks=[ID]. reference, source_refs und
disclosure bleiben exakt bei derselben ID; keine neuen Titel, Beschriftungen oder
Pfeile erfinden. source_caption benennt nur den unveränderten Originalbeleg und ist
KEINE fertige Erklärung. Schreibe den tatsächlich sichtbaren explanation_steps.text
wie explanation-guidance-1: kurz verständlich erklären, was die Grafik zeigt, wie das
Kind sie liest und warum das beim belegten Lernziel hilft. Höchstens350 Zeichen und
passend zur Offenlegungsstufe; keine verdeckte Antwort vorwegnehmen. Eine Frage mit einer Szene nennt mindestens zwei vollständige Original-
Objektlabels. Ein Wortbausteinvergleich nennt mindestens einen vollständigen Original-
Baustein. Ein Sprachvergleich nennt mindestens einen vollständigen Originalsatz der
gewählten Grafik im eigentlichen Fragesatz vor dem ersten Fragezeichen. Kein fremdes
Beispiel als Fülltext anhängen. Verwende die Beschriftungen wortgetreu. Antworten,
Aufgabenanzahl und alle fachlichen Prüfungen bleiben unverändert. Pluszeichen belegen
nur die sichtbare Bausteinfolge, keine Pfeilrichtung oder erfundene Wortzerlegung.
Bei einem Sprachvergleich mit short ist die Antwort genau ein vollständiges Wort aus
dem dargestellten Beispiel, keine daraus abgeleitete Endung. Stelle die Frage passend
zu diesem Wort; frage nicht nach einer Endung, die im Beispiel nur Teil eines Wortes ist.
"""


def word_part_bases(content):
    """Only a complete visible 2..4-piece plus line with actual part-role words."""
    for line in content.splitlines():
        quote = line.strip()
        if not quote or len(quote) > 300 or "+" not in quote or re.search(r"→|->|=", quote):
            continue
        labels = [part.strip().strip("|").strip() for part in quote.split("+")]
        roles = re.findall(r"(?<!\w)(?:Vorsilbe|Präfix|Wortstamm|Nachsilbe|Suffix|Endung)(?!\w)", quote, re.I)
        if (not 2 <= len(labels) <= 4 or len(set(labels)) != len(labels) or len(set(value.casefold() for value in roles)) < 2
                or any(not label or len(label) > 60 or re.search(r"[|.!?;\n]", label) for label in labels)):
            continue
        yield ({"kind": "sentence", "title": labels[0], "source_excerpt": quote, "labels": labels,
                "numbers": [], "connections": [], "marks": [], "unit": "", "variant": "",
                "scene": None, "text_probe": None, "lab": None}, "Original-Wortbausteine: " + quote)


def language_comparison_bases(content):
    """Use only two complete visible examples explicitly separated by an arrow."""
    for line in content.splitlines():
        quote = line.strip()
        if not quote or len(quote) > 300 or len(re.findall(r"→|->", quote)) != 1:
            continue
        labels = [part.strip() for part in re.split(r"→|->", quote)]
        if (len(labels) != 2 or len(set(labels)) != 2
                or any(not label or len(label) > 160 or re.search(r"[?؟？]", label) for label in labels)):
            continue
        yield ({"kind": "forms", "title": "Beispiele vergleichen", "source_excerpt": quote,
                "labels": labels, "numbers": [], "connections": [], "marks": [], "unit": "",
                "variant": "classification", "scene": None, "text_probe": None, "lab": None},
               "Schau dir an, was in den beiden Beispielen gleich ist und was sich verändert.")


def reference_supported(reference, contents):
    from .package_prepared_focus import REFERENCE, SENTENCE_REFERENCE, focus_bases, sentence_bases

    if reference.get("id") == "biology.heart.pump":
        from .package_prepared_heart import bases

        return any(next(bases(content), None) is not None for content in contents)
    if reference.get("id") == REFERENCE:
        return any(next(focus_bases(content), None) is not None for content in contents)
    if reference.get("id") == SENTENCE_REFERENCE:
        return any(next(sentence_bases(content), None) is not None for content in contents)
    if reference.get("id") == "general.source_relation.phases":
        return any(next(prepared._scene_bases(content), None) is not None for content in contents)
    if reference.get("id") == WORD_PARTS_REFERENCE:
        return any(next(word_part_bases(content), None) is not None for content in contents)
    if reference.get("id") == "biology.photosynthesis.exchange":
        from .package_prepared_photosynthesis import bases

        return any(next(bases(content), None) is not None for content in contents)
    if reference.get("id") == "geography.atlantic.between":
        from .package_prepared_geography import bases

        return any(next(bases(content), None) is not None for content in contents)
    if reference.get("id") == "physics.circuit.confirmed_states":
        from .package_prepared_circuit import bases

        return any(next(bases(content), None) is not None for content in contents)
    return True


def _bounded(rows):
    bases, result = set(), []
    for row in rows:
        # All disclosure variants of an offered base remain available.
        key = prepared._digest({key: value for key, value in row.items() if key not in ("id", "disclosure", "block")}
            | {"block": {key: value for key, value in row["block"].items() if key != "disclosure"}})
        if key not in bases and len(bases) >= MAX_SOURCE_BASE_CANDIDATES:
            continue
        bases.add(key)
        result.append(row)
    return result


def compile_candidates(payload):
    groups = payload.get("selected_groups") or []
    context = payload.get("visual_context") or {}
    if payload.get("package_partition") is None or not context.get("required") or len(groups) != 1:
        return []
    subject, group = groups[0].get("subject"), groups[0].get("id")
    if subject == "Mathematik":
        return []  # The established fractional-question contract stays separate.
    result = [row for row in prepared.compile_candidates(payload) if row["kind"] == "scene"]
    if subject != "Deutsch" and subject not in ("Englisch", "Französisch", "Spanisch", "Latein", "Deutsch als Zweitsprache"):
        return _bounded(result)
    reference_id = WORD_PARTS_REFERENCE if subject == "Deutsch" else LANGUAGE_COMPARISON_REFERENCE
    bases = word_part_bases if subject == "Deutsch" else language_comparison_bases
    references = [row for row in context.get("references", []) if row.get("id") == reference_id
                  and row.get("subject") == subject and type(row.get("version")) is int and row.get("digest")]
    count = len({row["block"]["source_excerpt"] for row in result})
    for source in context.get("sources", []):
        if source.get("subject") != subject or source.get("group_id") != group or not isinstance(source.get("content"), str):
            continue
        for base, text in bases(source["content"]):
            if count >= prepared.MAX_BASE_CANDIDATES:
                break
            added = False
            for reference in references:
                for stage in prepared.STAGES:
                    try:
                        block = Graphic.model_validate({**base, "disclosure": stage})
                        _meaningful(block, reference, sources=[source["content"]])
                        validate_question({"version": 1, "evidence_kind": "knowledge", "blocks": [block.model_dump()]},
                            {"prompt": "", "type": "short", "answer": "", "accepted": []},
                            [source["content"]], PROFILES[subject], structured=True, subject=subject)
                        step = ExplanationStep.model_validate({"id": "prepared", "text": text, "competence_id": None,
                            "disclosure": stage, "presentation": {"version": 1, "evidence_kind": "knowledge", "blocks": [block]},
                            "reference": {"id": reference["id"], "version": reference["version"]}, "source_refs": [source["ref"]]})
                    except ValueError:
                        continue
                    row = {"subject": subject, "group_id": group, "reference": step.reference.model_dump(),
                        "disclosure": stage, "source_refs": step.source_refs, "text": step.text,
                        "kind": block.kind, "block": block.model_dump(mode="json")}
                    identity = {"revision": REVISION, "plan_digest": payload.get("package_plan_digest"),
                        "partition": payload["package_partition"], "source_digest": prepared._digest(source),
                        "reference_digest": reference["digest"], "candidate": row}
                    row["id"] = "ps_" + prepared._digest(identity)[:24]
                    result.append(row)
                    added = True
            count += added
    return _bounded(result)


def _labels(candidate):
    return candidate["block"]["labels"]


def prompt_pattern(candidate):
    labels = _labels(candidate)
    if candidate["kind"] == "forms":
        # The anchor must occur in the actual question, not in unrelated
        # filler appended after it. Never rewrite a model's question to fit.
        return r"^[^?؟？\n]{0,159}(?:^|[^\w])(?:" + "|".join(re.escape(label) for label in labels) + r")($|[^\w])"
    if candidate["kind"] == "sentence":
        return r"(^|[^\w])(?:" + "|".join(re.escape(label) for label in labels) + r")($|[^\w])"
    gap = r"(?:[^\w]|[^\w][\s\S]*[^\w])"
    alternatives = [re.escape(left) + gap + re.escape(right) for left in labels for right in labels if left != right]
    return r"(^|[^\w])(?:" + "|".join(alternatives) + r")($|[^\w])"


class Binding(prepared.Binding):
    @property
    def rules(self):
        return RULES

    @property
    def fixed_text(self):
        return False

    def offered(self, candidate):
        return candidate["kind"] in ("scene", "sentence", "forms")

    def question_bound(self, candidate, question):
        prompt = question.get("prompt")
        if not isinstance(prompt, str):
            return False
        text = " ".join(unicodedata.normalize("NFC", prompt).split())
        labels = [" ".join(unicodedata.normalize("NFC", value).split()) for value in _labels(candidate)]
        if candidate["kind"] == "forms":
            text = re.split(r"[?؟？]", text, maxsplit=1)[0]
        matches = sum(bool(re.search(r"(?<!\w)" + re.escape(label) + r"(?!\w)", text)) for label in labels)
        return matches >= (2 if candidate["kind"] == "scene" else 1) and bool(re.search(prompt_pattern(candidate), prompt))

    @property
    def context(self):
        context = super().context
        for row in context["candidates"]:
            row["source_caption"] = row.pop("text")
        return {**context, "revision": REVISION}


def bind_schema(schema, payload):
    from .package_prepared_circuit import bind_schema as bind_circuit
    from .package_prepared_focus import bind_schema as bind_focus
    from .package_prepared_geography import bind_schema as bind_geography
    from .package_prepared_heart import bind_schema as bind_heart
    from .package_prepared_photosynthesis import bind_schema as bind_photosynthesis
    from .package_prepared_sentences import bind_schema as bind_sentences

    candidates = compile_candidates(payload)
    if candidates:
        def question_binding(node, candidate):
            prompt = node["properties"]["prompt"]
            pattern = prompt_pattern(candidate)
            if prompt.get("pattern") and prompt["pattern"] != pattern:
                return None
            fixed = prompt.get("enum", [prompt["const"]] if "const" in prompt else [])
            if fixed and not any(isinstance(value, str) and re.search(pattern, value) for value in fixed):
                return None
            prompt["pattern"] = pattern
            props = node["properties"]
            if candidate["kind"] == "forms" and "short" in props["type"].get("enum", []):
                # Complete literal words only; suffixes like "ed" within
                # "played" are not independent source evidence.
                words = list(dict.fromkeys(re.findall(r"[^\W_]+(?:['’][^\W_]+)*", candidate["block"]["source_excerpt"])))
                words = [word for word in words if 1 <= len(word) <= 80][:100]
                if not words:
                    return None
                answer = props["answer"]
                if answer.get("enum"):
                    words = [word for word in words if word in answer["enum"]]
                if not words:
                    return None
                answer["enum"] = words
            return node

        return prepared.bind_candidates(schema, Binding(tuple(candidates)),
            question_kinds=("scene", "sentence", "forms"), question_binding=question_binding)
    binding = bind_heart(schema, payload)
    if binding is not None:
        return binding
    binding = bind_photosynthesis(schema, payload)
    if binding is not None:
        return binding
    binding = bind_circuit(schema, payload)
    if binding is not None:
        return binding
    binding = bind_geography(schema, payload)
    if binding is not None:
        return binding
    binding = bind_sentences(schema, payload)
    if binding is not None:
        return binding
    return bind_focus(schema, payload)
