"""One notation task and one mixed-number task with their real saved goal IDs.

The existing meaning template is supplemental, never a new entry diagnosis.
The model adds teaching prose only; both task cores and graphic proofs are fixed.
"""
import copy
import re
from dataclasses import dataclass
from fractions import Fraction

from . import competences, learning_entry
from . import unit_fraction_compositions as composition
from .fraction_practice_plan import ERROR, INVALID, _bases, history
from .package_prepared_graphics import _digest, _fraction_bases, bind_candidates
from .subject_content import Graphic

KEY = "review_fraction_plan"
HISTORY = "review_fraction_exclusions"
REVISION = "review-fraction-plan-1"
NOTATION = "Einen Bruch mit Zähler und Nenner notieren"
FOUNDATION = "math.fractions.meaning"
CORE = (*learning_entry.CORE, "learning_goal_id")


def supported(payload):
    if (payload.get("review") is not True or payload.get("practice_kind") != "check"
            or payload.get("required_subject") != "Mathematik" or payload.get("math_tasks")
            or (payload.get("visual_context") or {}).get("required") is not True):
        return False
    focus, goals = payload.get("focus_goal_ids"), payload.get("learning_goals")
    if (not isinstance(focus, list) or len(focus) != 2 or any(not isinstance(key, str) for key in focus)
            or len(set(focus)) != 2 or not isinstance(goals, list)
            or any(not isinstance(goal, dict) or goal.get("id") not in ("g1", "g2", "g3", "g4") for goal in goals)
            or len({goal["id"] for goal in goals}) != len(goals)):
        return False
    by_id = {goal["id"]: goal for goal in goals}
    if not set(focus) <= by_id.keys():
        return False
    from .learning_sources import exact_quote

    texts = [row["content"] for row in payload["visual_context"]["sources"] if composition.eligible(row)]
    labels = [" ".join(str(by_id[key].get("label", "")).split()).rstrip(".!?") for key in focus]
    return (bool(texts) and labels.count(NOTATION) == 1 and sum(bool(composition.MIXED_GOAL.fullmatch(label)) for label in labels) == 1
        and all(isinstance(by_id[key].get("source_excerpt"), str)
            and exact_quote(by_id[key]["source_excerpt"], texts) for key in focus))


def _foundation():
    actual = competences.resolve_reference(FOUNDATION, competences.VERSION)
    row = competences.catalogue().get(FOUNDATION)
    if actual is None or not row or row.get("probe") != "fraction_meaning" or actual["subject_key"] != "mathematik":
        raise ValueError(INVALID)
    return actual, row


def add_references(db, payload):
    from .visual_reference_models import VisualReference

    if not supported(payload):
        raise ValueError(INVALID)
    context = copy.deepcopy(payload["visual_context"])
    for identifier, versions in ((composition.RECIPE, (2, 1)), ("math.fraction.part_whole", (1,))):
        stored = next((db.get(VisualReference, (identifier, version)) for version in versions
            if db.get(VisualReference, (identifier, version)) is not None), None)
        if stored is None or stored.digest != _digest(stored.recipe):
            raise ValueError(INVALID)
        ref = {"id": stored.id, "version": stored.version, "digest": stored.digest,
            "kind": "fraction", "subject": "Mathematik"}
        existing = [r for r in context["references"] if r.get("id") == identifier]
        if existing:
            if (len(existing) != 1 or type(existing[0].get("version")) is not int
                    or any(existing[0].get(key) != value for key, value in ref.items())):
                raise ValueError(INVALID)
        else:
            context["references"].append(ref)
    _foundation()
    return {**payload, "visual_context": context}


def _notation_pool(seed):
    _, row = _foundation()
    used, result = set(), []
    for _ in range(256):
        probe = learning_entry._probe(row, seed, used, "notation")
        if probe is None:
            break
        result.append(probe)
        used.add(competences.normalized(probe["prompt"]))
    return result


def _values(prompts):
    """Only explicit fraction/part counts; never infer a historical answer."""
    values = set()
    words = {word: index for index, word in enumerate(
        ("eins", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun", "zehn", "elf", "zwölf"), 1)}
    words.update(ein=1, eine=1, einen=1)
    parts = {word: index for index, word in enumerate(
        ("halbe", "drittel", "viertel", "fünftel", "sechstel", "siebtel", "achtel", "neuntel", "zehntel", "elftel", "zwölftel"), 2)}
    word_fraction = re.compile(r"\b(" + "|".join(words) + r")\s+(" + "|".join(parts) + r")\b", re.I)
    for text in prompts:
        if not isinstance(text, str):
            raise ValueError(INVALID)
        for pattern in (r"(?<![\w/])([0-9]{1,3})\s*/\s*([1-9][0-9]{0,2})(?![\w/])",
                r"\\(?:d?frac)\{([0-9]{1,3})\}\{([1-9][0-9]{0,2})\}"):
            values.update(str(Fraction(*map(int, match.groups()))) for match in re.finditer(pattern, text))
        values.update(str(Fraction(words[match[1].casefold()], parts[match[2].casefold()]))
            for match in word_fraction.finditer(text))
        total = re.search(r"in ([1-9][0-9]?) gleich große Teile geteilt", text)
        selected = re.search(r"([1-9][0-9]?) Teil(?:e sind| ist) ausgewählt", text)
        if total and selected:
            values.add(str(Fraction(int(selected[1]), int(total[1]))))
    return values


def with_history(payload, prompts, seed):
    if not supported(payload):
        raise ValueError(INVALID)
    pool = _notation_pool(seed)
    normalized = {competences.normalized(prompt) for prompt in prompts}
    relevant = {competences.normalized(probe["prompt"]) for probe in pool} & normalized
    allowed_values = {str(Fraction(probe["answer"])) for probe in pool}
    exclusions = {"version": 1, "revision": REVISION, "seed": seed,
        "context_digest": _digest(_base_context(payload["visual_context"])),
        "mixed": history(composition.compile_candidates(payload["visual_context"]), prompts),
        "notation_values": sorted(_values(prompts) & allowed_values),
        "notation_prompts": sorted(_digest(prompt) for prompt in relevant)}
    return {**payload, HISTORY: exclusions}


def _base_context(context):
    return {**context, "sources": [row for row in context["sources"]
        if row.get("source_type") != "curated_foundation"]}


def _foundation_source(plan):
    task = next(task for task in plan["tasks"] if task["kind"] == "notation")
    core, actual = task["core"], plan["foundation"]
    return {"ref": "r1", "source_type": "curated_foundation", "reference_id": actual["reference_id"],
        "version": actual["version"], "digest": actual["digest"], "example_question_id": core["id"],
        "example_digest": _digest({key: core[key] for key in learning_entry.CORE}), "subject": "Mathematik",
        "group_id": None, "content": actual["content"] + "\n" + core["prompt"]
            + "\nGeprüfte Antwort des eigenen Grundlagenbeispiels: " + core["answer"],
        "factual_status": "curated_rule_and_server_example", "source_refs": []}


def _plan(payload):
    if not supported(payload):
        raise ValueError(INVALID)
    context, exclusion = _base_context(payload["visual_context"]), payload.get(HISTORY)
    if (not isinstance(exclusion, dict) or set(exclusion) != {"version", "revision", "seed", "context_digest", "mixed", "notation_values", "notation_prompts"}
            or type(exclusion.get("version")) is not int or exclusion["version"] != 1
            or exclusion.get("revision") != REVISION or not isinstance(exclusion.get("seed"), str)
            or not re.fullmatch(r"[a-f0-9]{64}", exclusion["seed"]) or exclusion.get("context_digest") != _digest(context)):
        raise ValueError(INVALID)
    from .providers import practice_tasks

    prescribed = practice_tasks(payload)
    candidates = composition.compile_candidates(context)
    # The same finite source pool/history proof selects one real mixed slot.
    mixed_history = exclusion["mixed"]
    empty = history(candidates, [])
    if (not isinstance(mixed_history, dict) or set(mixed_history) != set(empty)
            or mixed_history.get("version") != 1 or type(mixed_history.get("version")) is not int
            or mixed_history.get("revision") != empty["revision"] or mixed_history.get("pool_digest") != empty["pool_digest"]
            or type(mixed_history.get("unknown_conversion")) is not bool
            or not isinstance(mixed_history.get("used_values"), list)
            or any(not isinstance(value, str) for value in mixed_history["used_values"])):
        raise ValueError(INVALID)
    available = [row for row in _bases(candidates) if str(Fraction(*row["proof"]["input"])) not in mixed_history["used_values"]]
    allowed = {str(Fraction(*row["proof"]["input"])) for row in _bases(candidates)}
    if not set(mixed_history["used_values"]) <= allowed:
        raise ValueError(INVALID)
    if mixed_history["unknown_conversion"] or not available:
        raise ValueError(ERROR)
    # Validate the stored notation projection against its actual finite pool.
    pool = _notation_pool(exclusion["seed"])
    value_pool = {str(Fraction(probe["answer"])) for probe in pool}
    prompt_pool = {_digest(competences.normalized(probe["prompt"])) for probe in pool}
    for key, allowed_items in (("notation_values", value_pool), ("notation_prompts", prompt_pool)):
        if (not isinstance(exclusion[key], list) or any(not isinstance(value, str) for value in exclusion[key])
                or len(set(exclusion[key])) != len(exclusion[key]) or not set(exclusion[key]) <= allowed_items):
            raise ValueError(INVALID)
    probe = next((probe for probe in pool if str(Fraction(probe["answer"])) not in exclusion["notation_values"]
        and _digest(competences.normalized(probe["prompt"])) not in exclusion["notation_prompts"]), None)
    if probe is None:
        raise ValueError(ERROR)
    actual, _ = _foundation()
    tasks = []
    for task in prescribed:
        if " ".join(task["label"].split()).rstrip(".!?") == NOTATION:
            core = {**{key: copy.deepcopy(probe[key]) for key in learning_entry.CORE},
                "id": task["id"], "learning_goal_id": task["learning_goal_id"]}
            tasks.append({"kind": "notation", "core": core, "probe": copy.deepcopy(probe)})
        else:
            chosen = copy.deepcopy(available[0])
            n, d = chosen["proof"]["input"]
            core = {"id": task["id"], "learning_goal_id": task["learning_goal_id"], "type": "short",
                "prompt": f"Schreibe {n}/{d} als gemischte Zahl.", "answer": f'{chosen["proof"]["whole"]} {chosen["proof"]["remainder"]}/{d}',
                "options": [], "accepted": []}
            tasks.append({"kind": "mixed", "core": core, "candidate_id": chosen["id"]})
    return {"version": 1, "revision": REVISION, "context_digest": _digest(context),
        "history_digest": _digest(exclusion), "foundation": actual, "tasks": tasks}


def prepare(payload):
    plan = _plan(payload)
    if KEY in payload and payload[KEY] != plan:
        raise ValueError(INVALID)
    context = payload["visual_context"]
    curated = [source for source in context["sources"] if source.get("source_type") == "curated_foundation"]
    expected = _foundation_source(plan)
    if curated and curated != [expected]:
        raise ValueError(INVALID)
    if any(source.get("ref") == "r1" for source in context["sources"] if source not in curated):
        raise ValueError(INVALID)
    return {**payload, KEY: plan, "visual_context": {**context,
        "sources": [*_base_context(context)["sources"], expected]}}


def _candidates(payload):
    if prepare(payload) != payload:
        raise ValueError(INVALID)
    plan, context = payload[KEY], payload['visual_context']
    original = composition.compile_candidates(context)
    rows = [row for row in original if row['disclosure'] == 'given'][:1]
    if not rows:
        raise ValueError(INVALID)
    for task in plan['tasks']:
        if task['kind'] == 'mixed':
            row = copy.deepcopy(next(row for row in original if row['id'] == task['candidate_id']))
        else:
            source = _foundation_source(plan)
            n, d = map(int, task['core']['answer'].split('/'))
            base, text = next(_fraction_bases(f'{n}/{d}'))
            block = Graphic.model_validate({**base, 'disclosure': 'solution'}).model_dump(mode='json')
            row = {'subject': 'Mathematik', 'group_id': None, 'kind': 'fraction', 'disclosure': 'solution',
                'reference': {'id': 'math.fraction.part_whole', 'version': 1}, 'source_refs': [source['ref']],
                'text': text, 'block': block}
            row['id'] = 'rn_' + _digest({'revision': REVISION, 'source': source, 'row': row,
                'core': task['core']})[:24]
        row['question_core'] = copy.deepcopy(task['core'])
        rows.append(row)
    return rows


@dataclass(frozen=True)
class Binding(composition.Binding):
    @property
    def rules(self):
        return ('\n' + REVISION + ': Genau zwei Aufgaben mit ihren vorhandenen q-/Lernziel-IDs. '
            'Eine prüft Bruchnotation aus gleich großen und ausgewählten Teilen, die andere die Ganzes-Rest-Umwandlung. '
            'Übernimm alle question_core-Felder und jede vorbereitete Grafik-ID samt Text/Referenz/Quelle/Stufe exakt. '
            'Die Grundlagenquelle ist eigenes ergänzendes Wissen, kein Heftzitat und keine neue Diagnose. '
            'Keine Zahlen, Ziele, Fragen oder Antworten austauschen. Ergänze nur kurze Hinweise und verständliche Erklärung.')

    @property
    def context(self):
        return {**super().context, 'revision': REVISION}


def bind_schema(schema, payload):
    if KEY not in payload:
        return None
    binding = Binding(tuple(_candidates(payload)))
    bounds = schema['properties']['questions']
    if bounds.get('minItems') != 2 or bounds.get('maxItems') != 2:
        raise ValueError(INVALID)
    wrapper = {'$defs': schema['$defs'], 'properties': {'units': {'items': copy.deepcopy({
        key: value for key, value in schema.items() if key != '$defs'})}}}
    def question_binding(node, candidate):
        core, props = candidate['question_core'], node['properties']
        if (props['id'].get('enum') != [core['id']]
                or props['learning_goal_id'].get('enum') != [core['learning_goal_id']]
                or 'short' not in props['type'].get('enum', [])):
            return None
        for key in ('id', 'type', 'prompt', 'answer'):
            allowed = props[key].get('enum', [props[key]['const']] if 'const' in props[key] else [])
            if allowed and core[key] not in allowed:
                return None
            props[key].update(type='string', enum=[core[key]])
        props['options'].update(minItems=0, maxItems=0)
        props['accepted'].update(minItems=0, maxItems=0)
        props['presentation'] = {'type': 'null'}
        return node
    bind_candidates(wrapper, binding, question_binding=question_binding)
    choices = {row['id']: row for row in binding.candidates}
    for node in wrapper['$defs'].values():
        props = node.get('properties', {})
        ids = props.get('presentation', {}).get('properties', {}).get('blocks', {}).get('items', {}).get('enum', [])
        if len(ids) == 1 and ids[0] in choices:
            props['id'] = {'type': 'string', 'enum': ids}
            props['text'] = {'type': 'string', 'enum': [choices[ids[0]]['text']]}
            props['competence_id'] = {'type': 'null'}
    body = wrapper['properties']['units']['items']
    schema.clear()
    schema.update(body, **{'$defs': wrapper['$defs']})
    return binding


def validate_output(payload, data):
    if KEY not in payload:
        return
    if prepare(payload) != payload:
        raise ValueError(INVALID)
    cores = {task['core']['id']: task['core'] for task in payload[KEY]['tasks']}
    questions = data.get('questions')
    if (not isinstance(questions, list) or len(questions) != 2 or {q.get('id') for q in questions} != set(cores)
            or any(any(q.get(key) != value for key, value in cores[q['id']].items()) for q in questions)):
        raise ValueError(INVALID)


def validate_history(payload, data, prompts):
    from .fraction_practice_plan import CURRENT_ERROR

    try:
        validate_output(payload, data)
        current = prepare(with_history(payload, prompts, payload[HISTORY]['seed']))
        if current[KEY]['tasks'] != payload[KEY]['tasks']:
            raise ValueError(CURRENT_ERROR)
    except ValueError:
        raise ValueError(CURRENT_ERROR) from None
