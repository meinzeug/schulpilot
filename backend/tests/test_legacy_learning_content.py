"""Saved bad model prose is preserved, but cannot become a new assessment."""
import copy

import pytest
from schulpilot.db import DB, Activity, Attempt, Job, LearningUnit, Usage
from schulpilot.legacy_learning_content import issue
from sqlalchemy import func, select
from test_coaching import normal_unit as _normal_unit


@pytest.fixture
def normal_unit(api, household):
    yield from _normal_unit.__wrapped__(api, household)


def test_saved_artifact_is_read_only_and_blocks_start_and_answers(normal_unit):
    client, identifier, *_ = normal_unit
    with DB.begin() as db:
        unit = db.get(LearningUnit, identifier)
        questions = copy.deepcopy(unit.questions)
        questions[0]['prompt'] += '؟؟وoops bad character Need fix.'
        unit.questions = questions
        unit.status = 'active'
    with DB() as db:
        before = {model: db.scalar(select(func.count()).select_from(model))
                  for model in (Activity, Attempt, Job, Usage)}
    for _ in range(2):
        data = client.get(f'/api/units/{identifier}').json()
        assert data['content_issue']['code'] == 'generated_correction_artifact'
        assert data['questions'][0]['prompt'] == questions[0]['prompt']
    assert client.post(f'/api/units/{identifier}/start').status_code == 409
    response = client.post(f'/api/units/{identifier}/questions/{questions[0]["id"]}/answer', json={'answer': 'x'})
    assert response.status_code == 409
    with DB() as db:
        assert db.get(LearningUnit, identifier).questions == questions
        for model, count in before.items():
            assert db.scalar(select(func.count()).select_from(model)) == count


def test_only_proven_generated_marker_is_flagged_and_completed_history_is_preserved():
    from types import SimpleNamespace

    unit = SimpleNamespace(status='active', explanation='Eine normale Erklärung.', questions=[{
        'prompt': 'Welche Zahl ist größer?', 'source_excerpt': 'oops bad character Need fix.'}])
    assert issue(unit) is None  # A quoted source is not generated model prose.
    unit.questions[0]['prompt'] = 'Oops bad character Need fix.'
    assert issue(unit)
    unit.status = 'completed'
    assert issue(unit) is None
