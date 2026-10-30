"""Literal, arithmetically checked decimal midpoints on a number line.

Only the immutable source-backed scene is requested; no free model geometry,
new numerical fact, automatic retry or modified provider answer is involved.
"""
import re
from decimal import Decimal

from . import package_prepared_graphics as prepared
from .subject_content import PROFILES, Graphic, validate_question

REFERENCE = "math.decimal.number_line_midpoint"
REVISION = "decimal-midpoint-1"
_LINE = re.compile(r"(?m)^[ \t]*([0-9]{1,3}[,.][0-9]{1,2})[ \t]+liegt[ \t]+genau[ \t]+zwischen[ \t]+([0-9]{1,3})[ \t]+und[ \t]+([0-9]{1,3})\.[ \t]*$")


def bases(content):
    for match in _LINE.finditer(content):
        middle, left, right = match.groups()
        lo, mid, hi = Decimal(left), Decimal(middle.replace(',', '.')), Decimal(right)
        if not lo < mid < hi or lo + hi != 2 * mid or hi - lo > 10:
            continue
        labels = [left, middle, right]
        objects = [{'id':f'p{i}', 'label':label, 'shape':'circle', 'tone':'neutral'}
                   for i,label in enumerate(labels)]
        quote = match.group().strip()
        placements = [{'object_id':obj['id'], 'slot':i} for i,obj in enumerate(objects)]
        yield {'kind':'scene', 'title':middle, 'source_excerpt':quote,
               'labels':labels, 'numbers':[], 'connections':[], 'marks':[], 'unit':'', 'variant':'',
               'scene':{'version':1, 'layout':'row', 'transition_ms':0, 'objects':objects,
                        'steps':[{'caption':quote, 'source_excerpt':quote, 'placements':placements,
                                  'highlight':highlight, 'edges':[]} for highlight in (['p1'],['p0','p2'])]},
               'text_probe':None, 'lab':None}


def is_midpoint(block):
    actual = block.model_dump(mode='json')
    actual.pop('disclosure')
    return any(actual == base for base in bases(block.source_excerpt))


def validate(block, sources=None):
    if not is_midpoint(block):
        raise ValueError('Der Zahlenstrahl benötigt eine wörtlich belegte und rechnerisch richtige Mitte.')
    if sources is not None and not any(block.source_excerpt in source for source in sources):
        raise ValueError('Der Zahlenstrahl benötigt seinen bestätigten Originalsatz.')


def compile_candidates(payload):
    groups, context = payload.get('selected_groups') or [], payload.get('visual_context') or {}
    if (payload.get('package_partition') is None or not context.get('required') or len(groups) != 1
            or groups[0].get('subject') != 'Mathematik'):
        return []
    group = groups[0]['id']
    refs = [row for row in context.get('references',[]) if row.get('id') == REFERENCE
            and row.get('subject') == 'Mathematik' and type(row.get('version')) is int and row.get('digest')]
    rows = []
    for source in context.get('sources',[]):
        if (source.get('subject') != 'Mathematik' or source.get('group_id') != group
                or not isinstance(source.get('content'),str)):
            continue
        for base in list(bases(source['content']))[:4]:
            for ref in refs:
                for stage in ('given','solution'):
                    block = Graphic.model_validate({**base,'disclosure':stage})
                    validate(block,[source['content']])
                    validate_question({'version':1,'evidence_kind':'knowledge','blocks':[block.model_dump()]},
                                      {'prompt':base['source_excerpt'],'type':'short','answer':'','accepted':[]},
                                      [source['content']],PROFILES['Mathematik'],structured=True,subject='Mathematik')
                    row = {'subject':'Mathematik','group_id':group,
                           'reference':{'id':REFERENCE,'version':ref['version']},'disclosure':stage,
                           'source_refs':[source['ref']],
                           'text':(f"{base['labels'][1]} ist die Mitte. Von {base['labels'][0]} bis {base['labels'][1]} "
                                   f"ist es genauso weit wie von {base['labels'][1]} bis {base['labels'][2]}."),
                           'kind':'scene','block':block.model_dump(mode='json')}
                    row['id'] = 'nl_' + prepared._digest({'revision':REVISION,'plan':payload.get('package_plan_digest'),
                        'partition':payload['package_partition'],'source':source,'reference_digest':ref['digest'],
                        'candidate':row})[:24]
                    rows.append(row)
    return rows


def _prompt(candidate):
    left, _, right = candidate['block']['labels']
    return r'zwischen\s+' + re.escape(left) + r'\s+und\s+' + re.escape(right) + r'(?:\D|$)'


class Binding(prepared.Binding):
    @property
    def rules(self):
        return ('\ndecimal-midpoint-1: Die angebotene Grafik stellt exakt die belegte Mitte zwischen zwei Zahlen dar. '
                'Links und rechts sind gleich weit von der Mitte entfernt. Stelle pro Originalsatz eine andere '
                'kurze Aufgabe: Welche Zahl liegt genau zwischen den beiden Randzahlen? Randzahlen ausdrücklich '
                'in der Frage nennen; nur belegte Dezimalwerte, keine neuen Abstände oder Rechnungen. '
                'Die Grafik erst als solution zur beantworteten Frage zeigen, vorab in der Einführung gegeben. '
                'Nutze unterschiedliche belegte Sätze für unterschiedliche Fragen; die private Antwort bleibt exakt.')

    def offered(self,candidate):
        return candidate['reference']['id'] == REFERENCE

    def question_bound(self,candidate,question):
        return (question.get('type') == 'short'
                and question.get('answer') == candidate['block']['labels'][1]
                and bool(re.search(_prompt(candidate),question.get('prompt',''))))


def bind_schema(schema,payload):
    candidates = compile_candidates(payload)
    if not candidates:
        return None
    from .presentation_capabilities import _nodes

    reachable = list(_nodes(schema['properties']['units'], schema.get('$defs',{})))
    counts = {node['properties']['questions'].get('maxItems') for node in reachable
              if 'questions' in node.get('properties',{})}
    if len(counts) != 1 or type(count := next(iter(counts))) is not int or not 2 <= count <= 5:
        return None
    ids = sorted({identifier for node in reachable
                  if {'id','prompt','answer','type'} <= node.get('properties',{}).keys()
                  for identifier in node['properties']['id'].get('enum',[])})
    originals = list(dict.fromkeys(row['block']['source_excerpt'] for row in candidates))
    if not ids:
        ids = [f'q{i+1}' for i in range(count)]  # New request-only IDs; never rewrite a saved task.
    # Every requested task needs a different documented example. Insufficient
    # original examples leave the existing general path unchanged.
    if len(ids) != count or len(ids) > len(originals):
        return None
    assignment = {identifier:originals[index] for index,identifier in enumerate(ids)}

    def question_binding(node,candidate):
        props = node['properties']
        if 'short' not in props['type'].get('enum',[]):
            return None
        choices = [identifier for identifier in props['id'].get('enum',ids)
                   if assignment[identifier] == candidate['block']['source_excerpt']]
        if not choices:
            return None
        fixed_prompt = props['prompt'].get('enum')
        if fixed_prompt and not all(re.search(_prompt(candidate), value) for value in fixed_prompt):
            return None
        if props['answer'].get('enum') and candidate['block']['labels'][1] not in props['answer']['enum']:
            return None
        props['id']['enum'] = choices
        props['type']['enum'] = ['short']
        props['prompt']['pattern'] = _prompt(candidate)
        props['answer'] = {'type':'string','enum':[candidate['block']['labels'][1]]}
        props['options']['maxItems'] = props['options']['minItems'] = 0
        props['accepted']['maxItems'] = props['accepted']['minItems'] = 0
        return node

    return prepared.bind_candidates(schema,Binding(tuple(candidates)),question_kinds=('scene',),
                                    question_binding=question_binding)
