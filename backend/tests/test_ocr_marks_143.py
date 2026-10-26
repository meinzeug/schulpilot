"""Artificial corrected worksheet: literal OCR survives advisory metadata errors."""
import pytest
from pydantic import ValidationError
from schulpilot.db import Material
from schulpilot.extraction import TranscriptionOutput
from schulpilot.source_lineage import learning_source
from schulpilot.subject_content import SourceBlock


def transcript(annotation):
    return {'blocks': [{'k': 'heading', 't': 'Einheiten', 'a': [], 'u': []},
                       {'k': 'formula', 't': '2/3 Minute = 60 Sekunden\n40 Sekunden',
                        'a': [annotation], 'u': []}],
            'legibility': 'readable', 'subject': 'Mathematik', 'topic': 'Bruchteile',
            'uncertainties': [], 'homework': []}


def test_unanchored_mark_keeps_literal_text_but_never_learning_groundtruth():
    value = TranscriptionOutput.model_validate(transcript({'k': 'crossout', 'q': '6O', 'c': 'red'})).as_material()
    assert value['content'] == 'Einheiten\n\n2/3 Minute = 60 Sekunden\n40 Sekunden'
    assert value['legibility'] == 'partial' and value['uncertainties']
    assert value['source_blocks'][1]['reading_uncertainties']
    assert not value['source_blocks'][1].get('annotations')
    m = Material(id='artificial', revision=1, purpose='notebook', confirmed=True,
                 **{k: value[k] for k in ('content', 'legibility', 'uncertainties', 'source_blocks')})
    safe = learning_source(None, m)
    assert safe['content'] == 'Einheiten'
    assert any(x['reason'] == 'reading_uncertain' for x in safe['exclusions'])
    with pytest.raises(ValidationError):
        SourceBlock(kind='formula', text='60', annotations=[{'kind': 'crossout', 'quote': '6O'}])


@pytest.mark.parametrize('evidence', ['', 'rote Schrift', '40 Sekunden'])
def test_colour_never_proves_teacher_while_literal_correction_is_preserved(evidence):
    mark = {'k': 'correction', 'q': '40 Sekunden', 'c': 'red', 'a': 'teacher', 'e': evidence}
    value = TranscriptionOutput.model_validate(transcript(mark)).as_material()
    saved = value['source_blocks'][1]['annotations'][0]
    assert saved['author'] == 'unknown' and saved['author_evidence'] == ''
    assert saved['quote'] == '40 Sekunden' and saved['color'] == 'red'
    assert value['content'].endswith('60 Sekunden\n40 Sekunden')
