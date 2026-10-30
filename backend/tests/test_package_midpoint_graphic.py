"""Synthetic photographed midpoint statements, actual schema and renderer data."""
import copy

import pytest
from schulpilot import package_output_transport, package_part_output, package_transport, visual_references
from schulpilot.db import DB
from schulpilot.package_prepared_midpoints import REFERENCE, bases
from schulpilot.schemas import PackageOutput
from schulpilot.subject_content import Graphic, public_presentation
from test_package_prepared_graphics import bind, payload_for, wire_step

SOURCE = 'Dezimalzahlen\n0,5 liegt genau zwischen 0 und 1.\n1,5 liegt genau zwischen 1 und 2.\n0 0,5 1 1,5 2 →'


@pytest.mark.parametrize('source',[
    '0,6 liegt genau zwischen 0 und 1.',
    '0,5 liegt nicht genau zwischen 0 und 1.',
    '0,5 liegt genau zwischen 1 und 0.',
    '0,? liegt genau zwischen 0 und 1.',
    '0,5 liegt vermutlich genau zwischen 0 und 1.',
    'Korrigiere: 0,5 liegt genau zwischen 0 und 1.',
    '0 0,5 1 1,5 2 →',
])
def test_do_not_infer_or_repair_midpoints(source):
    assert not list(bases(source))


def test_source_bound_midpoint_survives_actual_package_wire_and_keeps_private_quote():
    requested = payload_for(SOURCE, 'Mathematik')
    with DB() as db:
        requested['visual_context']['references'] = visual_references.candidates(db,'Mathematik',SOURCE,package_prepared=True)
    schema,binding = bind(requested)
    assert binding is not None and {row['reference']['id'] for row in binding.candidates} == {REFERENCE}
    intros = [row for row in binding.candidates if row['disclosure']=='given']
    solutions = [row for row in binding.candidates if row['disclosure']=='solution']
    assert len(solutions)==2
    questions=[]
    for index,solution in enumerate(solutions,1):
        lo,mid,hi = solution['block']['labels']
        questions.append({'id':f'q{index}','type':'short','prompt':f'Welche Zahl liegt genau zwischen {lo} und {hi}?',
            'answer':mid,'options':[],'accepted':[],'hints':['Vergleiche die Abstände links und rechts.'],
            'explanation':solution['text'],'presentation':None,'field_group':None,'explanation_steps':[wire_step(solution)]})
        assert binding.question_bound(solution,questions[-1])
        assert not binding.question_bound(solution,{**questions[-1],'answer':hi})
    wire={'units':[{'group_id':'g1','subject':'Mathematik','topic':'Dezimalzahlen',
                   'explanation':SOURCE,'explanation_steps':[wire_step(intros[0])],'questions':questions}]}
    original=copy.deepcopy(wire)
    codec=package_output_transport.bind(package_transport.schema_projection(schema))
    decoded=binding.hydrate(codec.decode(codec.encode(wire)))
    assert wire==original
    decoded=PackageOutput.model_validate(decoded).model_dump(mode='json')
    package_part_output.validate(decoded)
    with DB() as db:
        visual_references.validate_output(db,decoded,requested)
    block=solutions[0]['block']
    visible=public_presentation({'version':1,'evidence_kind':'knowledge','blocks':[block]},closed=True)['blocks'][0]
    assert visible['number_line_midpoint'] is True and 'source_excerpt' not in visible
    assert all('source_excerpt' not in step for step in visible['scene']['steps'])
    changed=copy.deepcopy(block)
    changed['scene']['objects'][1]['label']='0,6'
    with pytest.raises(ValueError):
        visual_references._meaningful(Graphic.model_validate(changed),{'id':REFERENCE,'kind':'scene'},sources=[SOURCE])
    foreign=copy.deepcopy(wire)
    foreign['units'][0]['questions'][0]['answer']='0,6'
    with pytest.raises(ValueError):
        codec.encode(foreign)


@pytest.mark.parametrize('answer,outcome', [('0,5','correct'),('0.50','correct'),('1/2','correct'),
    ('0,6','incorrect'),('0','incorrect'),('1','incorrect'),('-0.5','incorrect'),('0,5 oder 0,6','uncertain'),
    ('nicht 0,5','uncertain'),('1/0','uncertain')])
def test_checked_midpoint_has_numeric_verdict_instead_of_unknown_free_prose(answer,outcome):
    from schulpilot.answer_evaluation import evaluate

    block={**next(bases(SOURCE)),'disclosure':'solution'}
    question={'type':'short','prompt':'Welche Zahl liegt genau zwischen 0 und 1?', 'answer':'0,5',
              'explanation_steps':[{'reference':{'id':REFERENCE,'version':1},
                                    'presentation':{'version':1,'evidence_kind':'knowledge','blocks':[block]}}]}
    checked=evaluate(question,answer)
    assert checked['outcome']==outcome and checked['method']=='decimal_midpoint_v1'
    original=copy.deepcopy(question)
    question['answer']='0,6'
    assert evaluate(question,'0,6')['outcome']=='uncertain'
    question=original
    question['explanation_steps'][0]['presentation']['blocks'][0]['scene']['objects'][1]['label']='0,6'
    assert evaluate(question,'0,5')['outcome']=='uncertain'


def test_fresh_source_bound_unit_compares_positions_instead_of_repeating_midpoint_questions():
    from schulpilot import providers
    from schulpilot.answer_evaluation import evaluate
    from schulpilot.package_prepared_midpoints import bind_unit
    from schulpilot.schemas import PracticeUnitOutput
    from schulpilot.subject_content import bind_graphic_schema

    with DB() as db:
        refs=visual_references.candidates(db,'Mathematik',SOURCE,decimal_prepared=True)
    base=payload_for(SOURCE,'Mathematik')
    source={**base['visual_context']['sources'][0],'group_id':None}
    requested={'function':'unit','review':True,'practice_kind':'repair','required_subject':'Mathematik',
        'required_topic':'Dezimalzahlen','focus_goal_ids':['g1'],
        'learning_goals':[{'id':'g1','label':'Zahlen auf dem Zahlenstrahl verstehen','source_excerpt':SOURCE}],
        'previous_prompts':['Welche Zahl liegt genau zwischen 0 und 1?','Welche Zahl liegt genau zwischen 1 und 2?'],
        'visual_context':{'required':True,'references':refs,'sources':[source]}}
    schema=providers.strict_schema(PracticeUnitOutput,preserve_limits=True)
    providers.indexed_choice_schema(schema,bounded_matches=True)
    providers.bind_practice_tasks(schema,providers.practice_tasks(requested))
    bind_graphic_schema(schema,['Mathematik'])
    visual_references.bind_schema(schema,requested)
    template=copy.deepcopy(schema)
    binding=bind_unit(schema,requested)
    assert binding is not None
    candidates=[row for row in binding.candidates if row['disclosure']=='solution'][:2]
    intro=next(row for row in binding.candidates if row['disclosure']=='given')
    questions=[]
    for i,row in enumerate(candidates,1):
        core=row['question_core']
        question={'id':f'q{i}','learning_goal_id':'g1','type':'short','prompt':core['prompt'],'answer':core['answer'],
            'options':[],'accepted':[],'hints':['Vergleiche beide Positionen.'],'explanation':row['text'],
            'presentation':None,'field_group':None,'explanation_steps':[wire_step(row)]}
        questions.append(question)
        closed={**question,'explanation_steps':[{**wire_step(row),'presentation':{'version':1,'evidence_kind':'knowledge','blocks':[row['block']]}}]}
        assert evaluate(closed,core['answer'])['outcome']=='correct'
        assert evaluate(closed,'Rand' if core['answer']=='Mitte' else 'verschieden')['outcome']=='incorrect'
    value={'subject':'Mathematik','topic':'Dezimalzahlen','explanation':SOURCE,
           'explanation_steps':[wire_step(intro)],'questions':questions}
    result=PracticeUnitOutput.model_validate(binding.hydrate(value)).model_dump(mode='json')
    with DB() as db:
        visual_references.validate_output(db,result,requested)
    assert [q['learning_goal_id'] for q in result['questions']]==['g1','g1']
    assert all(q['prompt'] not in requested['previous_prompts'] for q in result['questions'])
    requested['previous_prompts'] += [q['prompt'] for q in result['questions']]
    fresh=bind_unit(template,requested)
    assert fresh is not None
    assert all(row['block']['labels'][1]=='1,5' for row in fresh.candidates)


def test_explicit_midpoint_recheck_keeps_original_answer_and_records_one_revision(api,household):
    from conftest import HEADERS
    from fastapi.testclient import TestClient
    from schulpilot.db import Attempt, AttemptAssessment, Job, LearningUnit, Usage
    from schulpilot.main import app
    from sqlalchemy import func, select

    _,child=household
    block={**next(bases(SOURCE)),'disclosure':'solution'}
    q={'id':'mid','type':'short','prompt':'Welche Zahl liegt genau zwischen 0 und 1?','answer':'0,5',
       'options':[],'accepted':[],'hints':['Vergleiche die Abstände.'],'explanation':'0,5 ist die Mitte.',
       'explanation_steps':[{'reference':{'id':REFERENCE,'version':1},
                            'presentation':{'version':1,'evidence_kind':'knowledge','blocks':[block]}}]}
    with DB.begin() as db:
        unit=LearningUnit(child_id=child['id'],subject='Mathematik',topic='Zahlenstrahl',questions=[q],
            explanation=q['explanation'],provider='synthetic',synthetic=True,status='paused',active_seconds=23)
        db.add(unit)
        db.flush()
        uid=unit.id
        attempt=Attempt(unit_id=uid,question_id='mid',answer='0,6',outcome='uncertain',assisted=True,
            evaluation={'method':'subject_rules_v7','outcome':'uncertain','attempt_number':1,
                        'independent_attempt':False,'support_reasons':['explanation']})
        db.add(attempt)
        db.flush()
        aid=attempt.id
    route=f'/api/units/{uid}/questions/mid/recheck'
    assert api.post(route).status_code==403
    with TestClient(app,headers=HEADERS) as kid:
        login=kid.post('/api/auth/login',json={'username':'test-child','password':'secure-child-pass-123'}).json()
        kid.headers['Authorization']='Bearer '+login['token']
        for _ in range(2):
            response=kid.post(route)
            assert response.status_code==200,response.text
            assert response.json()['outcome']=='incorrect'
    with DB() as db:
        saved=db.get(Attempt,aid)
        assert saved.answer=='0,6' and saved.outcome=='incorrect' and saved.assisted
        assert saved.evaluation['support_reasons']==['explanation']
        history=list(db.scalars(select(AttemptAssessment)))
        assert len(history)==1 and history[0].previous_outcome=='uncertain' and history[0].outcome=='incorrect'
        assert history[0].previous_evaluation['method']=='subject_rules_v7'
        assert db.get(LearningUnit,uid).active_seconds==23
        assert db.scalar(select(func.count()).select_from(Attempt))==1
        for model in (Job,Usage):
            assert db.scalar(select(func.count()).select_from(model))==0
