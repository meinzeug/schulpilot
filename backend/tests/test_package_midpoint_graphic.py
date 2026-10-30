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
