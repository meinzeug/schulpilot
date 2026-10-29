"""Only synthetic feedback; no model calls or real child records."""

from schulpilot.db import DB, Activity, LearningUnit, Mastery
from sqlalchemy import func, select
from test_learning import child_client, prepared


def setup_questions(api):
    demo, unit_id = prepared(api)
    with DB.begin() as db:
        unit = db.get(LearningUnit, unit_id)
        unit.questions = [
            {"id": "q1", "type": "short", "prompt": "Was bilden Pflanzen?", "answer": "Zucker",
             "accepted": [], "options": [], "hints": [],
             "explanation": "Pflanzen bilden Zucker und geben Sauerstoff ab."},
            {"id": "q2", "type": "short", "prompt": "Welches Gas geben Pflanzen ab?", "answer": "Sauerstoff",
             "accepted": [], "options": [], "hints": [], "explanation": "Pflanzen geben Sauerstoff ab."},
        ]
    return demo, unit_id


def test_opened_feedback_text_is_recorded_once_and_earlier_answer_is_unchanged(api):
    demo, unit_id = setup_questions(api)
    with child_client(demo) as kid:
        assert kid.post(f"/api/units/{unit_id}/start").status_code == 200
        first = kid.post(f"/api/units/{unit_id}/questions/q1/answer",
                         json={"answer": "Zucker", "guided_feedback": True}).json()
        attempt_id = first["attempt_id"]
        url = f"/api/units/{unit_id}/questions/q1/feedback-exposure"
        assert api.post(url, json={"attempt_id": attempt_id}).status_code == 403
        assert kid.post(url, json={"attempt_id": "0" * 32}).status_code == 404
        assert kid.post(url, json={"attempt_id": attempt_id}).json()["recorded"] is True
        assert kid.post(url, json={"attempt_id": attempt_id}).json()["recorded"] is True
        assert kid.post(f"/api/units/{unit_id}/feedback/acknowledge", json={"attempt_id": attempt_id}).status_code == 200
        assert kid.post(url, json={"attempt_id": attempt_id}).status_code == 409
        second = kid.post(f"/api/units/{unit_id}/questions/q2/answer", json={"answer": "Sauerstoff"}).json()
        assert second["outcome"] == "correct" and second["assisted"] is True
        assert second["evaluation"]["support_reasons"] == ["recent_solution"]
        first_saved = second["unit"]["questions"][0]["attempts"][0]
        assert first_saved["assisted"] is False and first_saved["outcome"] == "correct"
        visible_activity = kid.get(f"/api/children/{demo['child_id']}/activity").json()
        assert not any(row["kind"] == "feedback_exposure" for row in visible_activity)
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Activity).where(Activity.unit_id == unit_id,
            Activity.kind == "feedback_exposure")) == 1


def test_displayed_solution_graphic_makes_independence_open_without_claiming_text(api, monkeypatch):
    from schulpilot import subject_content

    demo, unit_id = setup_questions(api)
    monkeypatch.setattr(subject_content, "public_presentation", lambda *_args, **_kwargs:
        {"version": 1, "evidence_kind": "knowledge", "blocks": [{"disclosure": "solution"}]})
    with child_client(demo) as kid:
        assert kid.post(f"/api/units/{unit_id}/start").status_code == 200
        first = kid.post(f"/api/units/{unit_id}/questions/q1/answer",
                         json={"answer": "Zucker", "guided_feedback": True}).json()
        assert kid.post(f"/api/units/{unit_id}/feedback/acknowledge", json={"attempt_id": first["attempt_id"]}).status_code == 200
        second = kid.post(f"/api/units/{unit_id}/questions/q2/answer", json={"answer": "Sauerstoff"}).json()
        assert second["outcome"] == "correct" and second["evaluation"]["independence_uncertain"] is True
        assert second["evaluation"]["support_reasons"] == ["possible_prior_solution"]
    with DB() as db:
        mastery = db.scalar(select(Mastery).where(Mastery.child_id == demo["child_id"]))
        assert mastery.uncertain_units == 1 and mastery.assisted == 0


def test_only_first_opened_introduction_step_is_literal_evidence(monkeypatch):
    from types import SimpleNamespace

    from schulpilot import visual_references
    from schulpilot.learning import introduction_reveals_answer

    monkeypatch.setattr(visual_references, 'projection', lambda *_args: {'explanation_steps': [
        {'text': 'Bei der Fotosynthese entsteht Zucker.'}, {'text': 'Dabei entsteht auch Sauerstoff.'}]})
    q = {'type': 'short', 'answer': 'Zucker', 'accepted': []}
    unit = SimpleNamespace()
    assert not introduction_reveals_answer(None, unit, q, [])
    read = [SimpleNamespace(kind='introduction_read')]
    assert introduction_reveals_answer(None, unit, q, read)
    assert not introduction_reveals_answer(None, unit, {**q, 'answer': 'Sauerstoff'}, read)
    assert not introduction_reveals_answer(None, unit, {**q, 'language': {'skill': 'writing'}}, read)


def test_open_wrong_attempt_does_not_register_an_unshown_solution(api, monkeypatch):
    from schulpilot import subject_content

    demo, unit_id = setup_questions(api)
    with DB.begin() as db:
        unit = db.get(LearningUnit, unit_id)
        questions = list(unit.questions)
        questions[0] = {**questions[0], 'type': 'choice', 'options': ['Zucker', 'Salz']}
        unit.questions = questions
    monkeypatch.setattr(subject_content, 'public_presentation', lambda *_args, closed=False, **_kwargs:
        {'version': 1, 'evidence_kind': 'knowledge', 'blocks': [{'disclosure': 'solution'}] if closed else []})
    with child_client(demo) as kid:
        assert kid.post(f'/api/units/{unit_id}/start').status_code == 200
        first = kid.post(f'/api/units/{unit_id}/questions/q1/answer',
                         json={'answer': 'Salz', 'guided_feedback': True}).json()
        assert first['outcome'] == 'incorrect'
        assert kid.post(f'/api/units/{unit_id}/feedback/acknowledge', json={'attempt_id': first['attempt_id']}).status_code == 200
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Activity).where(Activity.unit_id == unit_id,
            Activity.kind == 'feedback_exposure')) == 0
