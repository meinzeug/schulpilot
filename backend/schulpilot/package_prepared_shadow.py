"""A source-bound comparison of shadow size, not a general optics solver."""
import copy
import re

from . import package_prepared_graphics as prepared
from .subject_content import PROFILES, Graphic, validate_question

REFERENCE = 'physics.shadow.size'
REVISION = 'shadow-size-1'
_SOURCE = re.compile(
    r'Ein\s+undurchsichtiger\s+(Gegenstand)\s+wirft\s+einen\s+(Schatten)\s*\.\s+'
    r'(Lampe)\s+und\s+(Wand)\s+bleiben\s+am\s+selben\s+Platz\s*\.\s+'
    r'Näher\s+an\s+der\s+Lampe\s+wird\s+der\s+Schatten\s+größer\s*\.', re.IGNORECASE)
QUESTION_PATTERN = r'^[^?؟？\n]{0,200}(?:^|[^\w])(?:[Ss]chatten|[Ll]icht|[Ll]ampe|[Ww]and|[Gg]egenstand)(?:$|[^\w])'
SCHEMA_PATTERN = r'[Ss]chatten|[Ll]icht|[Ll]ampe|[Ww]and|[Gg]egenstand'


def bases(content):
    for match in _SOURCE.finditer(content):
        obj, shadow, lamp, wall = match.groups()
        yield {'kind': 'shadow_size', 'title': 'Licht und Schatten', 'source_excerpt': match.group(),
               'labels': [lamp, obj, wall, shadow], 'numbers': [], 'connections': [], 'marks': [],
               'unit': '', 'variant': '', 'scene': None, 'text_probe': None, 'lab': None}


def validate(block, sources):
    actual = block.model_dump(mode='json')
    actual.pop('disclosure')
    if not any(actual == candidate for candidate in bases(block.source_excerpt)):
        raise ValueError('Das Schattenmodell benötigt den vollständigen belegten Zusammenhang.')
    if sources is not None and not any(block.source_excerpt in source for source in sources):
        raise ValueError('Das Schattenmodell benötigt eine bestätigte Originalquelle.')


def compile_candidates(payload):
    groups, context = payload.get('selected_groups') or [], payload.get('visual_context') or {}
    if (payload.get('package_partition') is None or not context.get('required') or len(groups) != 1
            or groups[0].get('subject') != 'Physik'):
        return []
    group = groups[0]['id']
    refs = [r for r in context.get('references', []) if r.get('id') == REFERENCE
            and r.get('subject') == 'Physik' and type(r.get('version')) is int and r.get('digest')]
    rows = []
    for source in context.get('sources', []):
        if (source.get('subject') != 'Physik' or source.get('group_id') != group
                or not isinstance(source.get('content'), str)):
            continue
        for base in list(bases(source['content']))[:1]:
            for ref in refs:
                for stage in ('given', 'solution'):
                    block = Graphic.model_validate({**base, 'disclosure': stage})
                    validate(block, [source['content']])
                    validate_question({'version': 1, 'evidence_kind': 'knowledge', 'blocks': [block.model_dump()]},
                        {'prompt': '', 'type': 'short', 'answer': '', 'accepted': []},
                        [source['content']], PROFILES['Physik'], structured=True, subject='Physik')
                    row = {'subject': 'Physik', 'group_id': group,
                           'reference': {'id': REFERENCE, 'version': ref['version']}, 'disclosure': stage,
                           'source_refs': [source['ref']], 'text': ' '.join(base['source_excerpt'].split()),
                           'kind': 'shadow_size', 'block': block.model_dump(mode='json')}
                    row['id'] = 'sh_' + prepared._digest({'revision': REVISION, 'plan': payload.get('package_plan_digest'),
                        'partition': payload['package_partition'], 'source': source,
                        'reference_digest': ref['digest'], 'candidate': row})[:24]
                    rows.append(row)
    return rows


class Binding(prepared.Binding):
    @property
    def rules(self):
        return ('\nshadow-size-1: Das Schema vergleicht zwei Gegenstandspositionen bei feststehender '
                'Lampe und Wand. Nur den belegten Zusammenhang zum Schatten verwenden; keine Zahlen, '
                'Abstände oder weiteren Lichtgesetze erfinden. Jede Frage behandelt Licht, Schatten, '
                'Lampe, Gegenstand oder Wand und ist ohne unsichtbare Grafik verständlich. Ein '
                'passender Begriff gehört natürlich in den eigentlichen Fragesatz vor das erste Fragezeichen. Keine angehängten Schlüsselwörter '
                'oder unsichtbaren Zeichen. Wähle die gebundene Quellen- und Aufdeckstufen-ID.')

    def offered(self, candidate):
        return candidate['reference']['id'] == REFERENCE

    def question_bound(self, candidate, question):
        prompt = question.get('prompt', '')
        return isinstance(prompt, str) and bool(re.search(QUESTION_PATTERN, prompt))


def bind_schema(schema, payload):
    candidates = compile_candidates(payload)
    if not candidates:
        return None
    return prepared.bind_candidates(schema, Binding(tuple(candidates)), question_kinds=('shadow_size',),
                                    prompt_pattern=lambda _: SCHEMA_PATTERN)


class UnitBinding(Binding):
    def hydrate(self, data):
        return super().hydrate({'units': [data]})['units'][0]


def bind_followup(schema, payload):
    is_followup = payload.get('review') is True and payload.get('practice_kind') in ('repair', 'check')
    is_notebook = (payload.get('function') == 'unit' and bool(payload.get('notebook_practice'))
                   and not payload.get('review'))
    if (not (is_followup or is_notebook) or payload.get('required_subject') != 'Physik'
            or payload.get('selected_groups') or any(payload.get(key) for key in
                ('study_block', 'homework_practice', 'exam_preparation', 'exam_review_practice'))):
        return None
    unit_payload = {**payload, 'package_partition': 0, 'selected_groups': [{'id': None, 'subject': 'Physik'}]}
    candidates = compile_candidates(unit_payload)
    if not candidates:
        return None
    binding = UnitBinding(tuple(candidates))
    wrapper = {'$defs': schema['$defs'], 'properties': {'units': {'items': copy.deepcopy(
        {key: value for key, value in schema.items() if key != '$defs'})}}}

    def question_binding(node, candidate):
        props, pattern = node['properties'], SCHEMA_PATTERN
        prompt = props['prompt']
        if prompt.get('pattern') and prompt['pattern'] != pattern:
            return None
        if prompt.get('enum') and not all(re.search(pattern, value) for value in prompt['enum']):
            return None
        prompt['pattern'] = pattern
        props['presentation'] = {'type': 'null'}
        return node

    prepared.bind_candidates(wrapper, binding, question_kinds=('shadow_size',), question_binding=question_binding)
    body = wrapper['properties']['units']['items']
    schema.clear()
    schema.update(body, **{'$defs': wrapper['$defs']})
    return binding
