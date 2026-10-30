"""Artificial receipts: only closed numeric examples can establish fresh work."""
from types import SimpleNamespace

import pytest
from schulpilot.learning_disclosures import independent_example, receipt


def question(identifier='old', prompt='Berechne 1/4 + 1/4.', answer='2/4'):
    return {'id':identifier, 'type':'short', 'prompt':prompt, 'answer':answer}


def setup(text='1/4 + 1/4 = 2/4.'):
    old = question()
    fresh = question('new', 'Berechne 1/4 + 1/8.', '3/8')
    unit = SimpleNamespace(subject='Mathematik', questions=[old, fresh])
    event = SimpleNamespace(kind='explanation', detail={'question_id':'old', 'arithmetic_disclosure':receipt(old,text)})
    return unit, fresh, event


def test_only_new_result_after_a_checked_numeric_disclosure_can_be_independent():
    unit, fresh, event = setup()
    assert independent_example(unit, fresh, [event])
    same_result = question('other', 'Berechne 1/6 + 2/6.', '3/6')
    assert not independent_example(unit, same_result, [event])
    assert receipt(unit.questions[0], '1/4 + 1/4 = 3/4.') is None
    assert receipt(unit.questions[0], '1/4 + 1/4 = 2/4. Die nächste Lösung lautet drei Achtel.') is None
    assert receipt(unit.questions[0], '1/4 + 1/4 = 2/4 = 3/8.') is None


@pytest.mark.parametrize('change', ['legacy', 'feedback', 'changed_question', 'unknown_version', 'language', 'other_subject', 'wrong_key', 'mixed'])
def test_unknown_or_changed_exposure_remains_conservative(change):
    unit, fresh, event = setup()
    events = [event]
    if change == 'legacy':
        event.detail.pop('arithmetic_disclosure')
    elif change == 'feedback':
        event.kind = 'feedback_exposure'
    elif change == 'changed_question':
        unit.questions[0]['answer'] = '1/2'
    elif change == 'unknown_version':
        event.detail['arithmetic_disclosure']['version'] = 'future'
    elif change == 'language':
        fresh['language'] = {'skill':'writing'}
    elif change == 'other_subject':
        unit.subject = 'Biologie'
    elif change == 'wrong_key':
        fresh['answer'] = '2/8'
    elif change == 'mixed':
        events.append(SimpleNamespace(kind='explanation', detail={'question_id':'unknown'}))
    assert not independent_example(unit, fresh, events)
