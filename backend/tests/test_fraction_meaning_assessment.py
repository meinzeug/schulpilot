"""Only the literal curated parts-of-a-whole probe is automatically judged."""
import pytest
from schulpilot.answer_evaluation import FRACTION_MEANING_VERSION, evaluate


def question(n=5, d=11, *, key=None):
    selection = '1 Teil ist' if n == 1 else f'{n} Teile sind'
    return {'type': 'short', 'prompt': f'Ein Ganzes ist in {d} gleich große Teile geteilt. '
        f'{selection} ausgewählt. Welchen Bruch beschreibt das? Schreibe Zähler/Nenner.',
        'answer': key if key is not None else f'{n}/{d}', 'accepted': []}


@pytest.mark.parametrize('answer,outcome', [('5/11','correct'), (' 5 / 11 ','correct'),
    ('10/22','correct'), ('11/5','incorrect'), ('5/12','incorrect'), ('-5/11','incorrect'),
    ('fünf Elftel','uncertain'), ('1/0','uncertain'), ('A) 5/11','uncertain')])
def test_exact_parts_probe_checks_fraction_and_accepts_equal_values(answer, outcome):
    actual = evaluate(question(), answer)
    assert actual['outcome'] == outcome
    if outcome != 'uncertain':
        assert actual['method'] == FRACTION_MEANING_VERSION


def test_singular_and_legacy_singular_wording():
    value = question(1, 3)
    assert evaluate(value, '3/1')['outcome'] == 'incorrect'
    value['prompt'] = value['prompt'].replace('1 Teil ist', '1 Teile sind')
    assert evaluate(value, '3/1')['outcome'] == 'incorrect'


def test_wrong_stored_solution_does_not_create_false_verdict():
    assert evaluate(question(key='11/5'), '11/5')['outcome'] == 'uncertain'
    assert evaluate(question(key='10/22'), '5/11')['outcome'] == 'uncertain'


def test_unsupported_wording_and_impossible_counts_are_not_guessed():
    value = question()
    value['prompt'] = value['prompt'].replace('ausgewählt.', 'nicht ausgewählt.')
    assert evaluate(value, '11/5')['outcome'] == 'uncertain'
    impossible = question(12, 11)
    assert evaluate(impossible, '12/11')['outcome'] == 'uncertain'


def test_explicit_recheck_records_revision_and_preserves_original_answer(api, household):
    from conftest import HEADERS
    from fastapi.testclient import TestClient
    from schulpilot.db import DB, Attempt, AttemptAssessment, Job, LearningUnit, Usage
    from schulpilot.main import app
    from sqlalchemy import func, select

    _, child = household
    q = {**question(), 'id': 'prior_1', 'options': [], 'hints': ['Zähle die Teile.'],
         'explanation': 'Der Zähler zählt ausgewählte Teile.'}
    with DB.begin() as db:
        unit = LearningUnit(child_id=child['id'], subject='Mathematik', topic='Brüche', questions=[q],
            explanation=q['explanation'], provider='synthetic', synthetic=True, status='paused', active_seconds=23)
        db.add(unit)
        db.flush()
        uid = unit.id
        attempt = Attempt(unit_id=uid, question_id=q['id'], answer='11/5', outcome='uncertain', assisted=False,
            evaluation={'method': 'subject_rules_v5', 'outcome': 'uncertain', 'attempt_number': 1,
                        'independent_attempt': True, 'support_reasons': []})
        db.add(attempt)
        db.flush()
        aid = attempt.id
    route = f'/api/units/{uid}/questions/{q["id"]}/recheck'
    assert api.post(route).status_code == 403
    with TestClient(app, headers=HEADERS) as kid:
        login = kid.post('/api/auth/login', json={'username':'test-child','password':'secure-child-pass-123'}).json()
        kid.headers['Authorization'] = 'Bearer ' + login['token']
        for _ in range(2):
            response = kid.post(route)
            assert response.status_code == 200, response.text
            assert response.json()['outcome'] == 'incorrect'
    with DB() as db:
        saved = db.get(Attempt, aid)
        assert saved.answer == '11/5' and saved.outcome == 'incorrect' and not saved.assisted
        assert not saved.evaluation['independent_evidence']
        history = list(db.scalars(select(AttemptAssessment)))
        assert len(history) == 1 and history[0].previous_outcome == 'uncertain' and history[0].outcome == 'incorrect'
        assert db.get(LearningUnit, uid).active_seconds == 23
        assert db.scalar(select(func.count()).select_from(Attempt)) == 1
        for model in (Job, Usage):
            assert db.scalar(select(func.count()).select_from(model)) == 0
