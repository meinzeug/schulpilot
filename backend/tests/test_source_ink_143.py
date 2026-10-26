"""Ordinary notebook handwriting is not itself a correction or student answer."""
import pytest
from schulpilot.db import Material
from schulpilot.extraction import OCR_SYSTEM, TranscriptionOutput
from schulpilot.source_lineage import learning_source


@pytest.mark.parametrize('subject,text', [
    ('Mathematik', 'Der Nenner sagt, in wie viele gleich große Teile ein Ganzes geteilt wird.'),
    ('Deutsch', 'Mila | Wer liest?\nliest | Was tut Mila?'),
    ('Englisch', 'Bei Fragen und Verneinungen: did + Grundform.'),
])
def test_ordinary_ink_is_literal_but_not_a_reason_to_exclude_whole_lessons(subject, text):
    raw = {'blocks': [{'k': 'paragraph', 't': text, 'a': [{'k': 'ink', 'q': text, 'c': 'blue'}]}],
           'legibility': 'readable', 'subject': subject, 'topic': 'Artificial notebook', 'uncertainties': [], 'homework': []}
    value = TranscriptionOutput.model_validate(raw).as_material()
    m = Material(id='artificial', revision=1, purpose='notebook', confirmed=True,
                 **{k: value[k] for k in ('content', 'legibility', 'uncertainties', 'source_blocks')})
    assert learning_source(None, m)['content'] == text
    assert value['source_blocks'][0]['annotations'][0]['author'] == 'unknown'
    assert 'kind=ink' in OCR_SYSTEM and 'niemals für normale Tinte' in OCR_SYSTEM


@pytest.mark.parametrize('kind', ['unknown', 'crossout', 'correction', 'comment', 'insertion'])
def test_real_marks_remain_excluded_and_legacy_unknown_is_never_relabelled(kind):
    text = 'Mila ist das Prädikat.'
    m = Material(id='artificial', revision=1, purpose='notebook', confirmed=True, legibility='readable', uncertainties=[],
                 content=text, source_blocks=[{'kind': 'paragraph', 'text': text,
                    'annotations': [{'kind': kind, 'quote': text, 'color': 'blue'}]}])
    value = learning_source(None, m)
    assert not value['content'] and value['exclusions'][0]['reason'] == 'visible_annotation'
    assert m.source_blocks[0]['annotations'][0]['kind'] == kind


def test_ink_does_not_remove_factual_or_student_answer_guards():
    for text, role, reason in [('1+1=3', 'example', 'false_equality'), ('40 Sekunden', 'student_work', 'student_work')]:
        m = Material(id='artificial', revision=1, purpose='notebook', confirmed=True, legibility='readable', uncertainties=[],
                     content=text, source_blocks=[{'kind': 'paragraph', 'text': text, 'literal_role': role,
                        'annotations': [{'kind': 'ink', 'quote': text, 'color': 'red'}]}])
        assert learning_source(None, m)['exclusions'][0]['reason'] == reason
