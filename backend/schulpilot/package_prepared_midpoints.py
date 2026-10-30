"""Literal, arithmetically checked decimal midpoints on a number line.

Only the immutable source-backed scene is requested; no free model geometry,
new numerical fact, automatic retry or modified provider answer is involved.
"""
import copy
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


def support_cores(labels):
    left,middle,right=labels
    return [
        {'prompt':f'Zur Zahl {middle} zwischen {left} und {right}: Liegt sie in der Mitte oder am Rand?',
         'answer':'Mitte','alternatives':('mitte','rand')},
        {'prompt':f'Vergleiche die Wege von {left} bis {middle} und von {middle} bis {right}: Sind sie gleich oder verschieden lang?',
         'answer':'gleich','alternatives':('gleich','verschieden')},
    ]


def question_core(candidate):
    if candidate.get("question_core"):
        return candidate["question_core"]
    left,middle,right = candidate["block"]["labels"]
    return {"prompt":f"Welche Zahl liegt genau zwischen {left} und {right}?", "answer":middle}


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
                and question.get('answer') == question_core(candidate)['answer']
                and question.get('prompt') == question_core(candidate)['prompt'])


def bind_schema(schema,payload):
    return _bind(schema, compile_candidates(payload), Binding)


def _bind(schema,candidates,binding_type):
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
    originals = list(dict.fromkeys(question_core(row)['prompt'] for row in candidates))
    if not ids:
        ids = [f'q{i+1}' for i in range(count)]  # New request-only IDs; never rewrite a saved task.
    # Every requested task needs a different documented example. Insufficient
    # original examples leave the existing general path unchanged.
    if len(ids) != count or len(ids) > len(originals):
        return None
    permitted={identifier:set() for identifier in ids}
    for node in reachable:
        fields=node.get('properties',{})
        if not {'id','prompt','answer','type'} <= fields.keys():
            continue
        for identifier in fields['id'].get('enum',ids):
            if identifier in permitted:
                permitted[identifier].update(fields.get('learning_goal_id',{}).get('enum',[]))
    assignment={}
    used=set()
    for identifier in ids:
        available=[question_core(row)['prompt'] for row in candidates
                   if question_core(row)['prompt'] not in used
                   and (row.get('goal_id') is None or row['goal_id'] in permitted[identifier])]
        if not available:
            return None
        assignment[identifier]=available[0]
        used.add(available[0])

    def question_binding(node,candidate):
        props = node['properties']
        if 'short' not in props['type'].get('enum',[]):
            return None
        choices = [identifier for identifier in props['id'].get('enum',ids)
                   if assignment[identifier] == question_core(candidate)['prompt']]
        if not choices:
            return None
        fixed_prompt = props['prompt'].get('enum')
        core = question_core(candidate)
        if fixed_prompt and fixed_prompt != [core['prompt']]:
            return None
        if props['answer'].get('enum') and core['answer'] not in props['answer']['enum']:
            return None
        props['id']['enum'] = choices
        props['type']['enum'] = ['short']
        props['prompt']['enum'] = [core['prompt']]
        props['answer'] = {'type':'string','enum':[core['answer']]}
        props['options']['maxItems'] = props['options']['minItems'] = 0
        props['accepted']['maxItems'] = props['accepted']['minItems'] = 0
        props['presentation'] = {'type':'null'}
        return node

    return prepared.bind_candidates(schema,binding_type(tuple(candidates)),question_kinds=('scene',),
                                    question_binding=question_binding)



class UnitBinding(Binding):
    @property
    def rules(self):
        return ('\nFür diese Anschlussrunde gelten ausschließlich die festen question_core-Fragen. '
                'Prüfe die Mitte und ihre gleichen Abstände auf demselben geprüften Zahlenstrahl; alle Kernfelder und Lernziel-IDs '
                'unverändert übernehmen. Keine Wiederholung der früheren Mittelpunktfragen. Wähle genau '
                'die zur Frage gehörende Quellen-/Stufen-ID. Zahlenstrahl und Text erklären denselben belegten Zusammenhang.')

    def hydrate(self,data):
        return super().hydrate({'units':[data]})['units'][0]


def bind_unit(schema,payload):
    if (payload.get('selected_groups') or payload.get('required_subject') != 'Mathematik'
            or any(payload.get(key) for key in ('homework_practice','exam_preparation','exam_review_practice'))
            or not (payload.get('notebook_practice') or payload.get('review') or payload.get('study_block'))):
        return None
    value={**payload,'package_partition':0,'selected_groups':[{'id':None,'subject':'Mathematik'}]}
    original=compile_candidates(value)
    if not original:
        return None
    previous={' '.join(prompt.casefold().split()) for prompt in payload.get('previous_prompts',[]) if isinstance(prompt,str)}
    goals={goal['id']:goal for goal in payload.get('learning_goals',[])}
    focus=payload.get('focus_goal_ids') or list(goals)
    rows=[]
    for candidate in original:
        quote=' '.join(candidate['block']['source_excerpt'].split())
        eligible=[identifier for identifier in focus if identifier in goals
                  and quote in ' '.join(goals[identifier].get('source_excerpt','').split())]
        if payload.get('review') and not eligible:
            continue
        for core in support_cores(candidate['block']['labels']):
            if ' '.join(core['prompt'].casefold().split()) in previous:
                continue
            for identifier in eligible or [None]:
                row=copy.deepcopy(candidate)
                row['question_core']={key:core[key] for key in ('prompt','answer')}
                row['goal_id']=identifier
                row['id']='nl_' + prepared._digest({'revision':REVISION,'original':candidate['id'],'core':core,'goal':identifier})[:24]
                rows.append(row)
    wrapper={'$defs':schema['$defs'],'properties':{'units':{'items':copy.deepcopy(
        {key:item for key,item in schema.items() if key!='$defs'})}}}
    binding=_bind(wrapper,rows,UnitBinding)
    if binding is None:
        from .providers import ProviderError, Result

        raise ProviderError('Für neue Zahlenstrahlfragen fehlen hier weitere bestätigte Beispiele. Deine bisherigen Antworten bleiben gespeichert.',
            code='invalid_output',billing_result=Result({},0,0,0,telemetry={'pre_dispatch':True},cost_source='cancelled'))
    body=wrapper['properties']['units']['items']
    schema.clear()
    schema.update(body,**{'$defs':wrapper['$defs']})
    return binding


def evaluate_answer(question, answer):
    """Exact numeric grading only for the fully checked source/scene contract."""
    if question.get('type') != 'short' or question.get('language'):
        return None
    from fractions import Fraction

    from .answer_evaluation import result

    match = re.fullmatch(r'Welche Zahl liegt genau zwischen ([0-9]{1,3}) und ([0-9]{1,3})\?',
                         question.get('prompt',''))
    order = re.fullmatch(r'Welche Zahl liegt weiter (rechts|links): ([0-9]{1,3}(?:[.,][0-9]{1,2})?) oder ([0-9]{1,3}(?:[.,][0-9]{1,2})?)\?',
                         question.get('prompt',''))
    support_prompt = question.get('prompt','').startswith(('Zur Zahl ', 'Vergleiche die Wege '))
    if not match and not order and not support_prompt:
        return None
    method = 'decimal_midpoint_v1' if match else 'decimal_position_v1' if order else 'decimal_midpoint_support_v1'
    invalid = result('uncertain','Die gespeicherte Zahlenstrahlaufgabe muss noch geprüft werden.',method=method)
    referenced = False
    for step in question.get('explanation_steps') or []:
        if not isinstance(step,dict) or step.get('reference') != {'id':REFERENCE,'version':1}:
            continue
        referenced = True
        for raw in (step.get('presentation') or {}).get('blocks',[]):
            try:
                block = Graphic.model_validate(raw)
                validate(block)
                left,middle,right = block.labels
                if support_prompt:
                    core=next((core for core in support_cores(block.labels) if core['prompt']==question['prompt']),None)
                    if core is None or question.get('answer') != core['answer']:
                        continue
                    value=' '.join(str(answer).casefold().split()).rstrip('.')
                    if value not in core['alternatives']:
                        return result('uncertain',f"Schreib {core['alternatives'][0]} oder {core['alternatives'][1]} als Antwort.",method=method)
                    correct=value == core['answer'].casefold()
                    return result('correct' if correct else 'incorrect',
                        'Genau, die beiden Abstände zur Mitte sind gleich.' if correct else
                        'Vergleiche die beiden Abstände zur Zahl in der Mitte noch einmal.',method=method)
                if match:
                    if match.groups() != (left,right):
                        continue
                    expected = Fraction(middle.replace(',','.'))
                else:
                    direction,a,b = order.groups()
                    if a == b or a not in block.labels or b not in block.labels:
                        continue
                    operation = max if direction == 'rechts' else min
                    expected = operation(Fraction(value.replace(',','.')) for value in (a,b))
                if Fraction(str(question['answer']).replace(',','.')) != expected:
                    continue
            except (ValueError,TypeError,KeyError,ZeroDivisionError):
                continue
            value = re.sub(r'\s+','',str(answer))
            if not re.fullmatch(r'[+-]?[0-9]{1,6}(?:[.,][0-9]{1,6})?|[+-]?[0-9]{1,4}/[1-9][0-9]{0,3}',value):
                return result('uncertain','Schreib eine einzelne Zahl oder einen Bruch als Antwort.',method=method)
            supplied = Fraction(value.replace(',','.'))
            correct = supplied == expected
            if order:
                return result('correct' if correct else 'incorrect',
                    f'Genau, diese Zahl liegt weiter {order[1]}.' if correct else
                    f'Vergleiche die beiden Positionen auf dem Zahlenstrahl. Welche liegt weiter {order[1]}?',method=method)
            return result('correct' if correct else 'incorrect',
                f'Genau, diese Zahl liegt gleich weit von {left} und {right} entfernt.' if correct else
                f'Diese Zahl liegt noch nicht genau in der Mitte. Vergleiche die Abstände zu {left} und {right}.',method=method)
    return invalid if referenced else None
