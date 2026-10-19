"""Synthetic regressions for the two local October 2026 audit documents."""

import io
import zipfile
from datetime import datetime
from zoneinfo import ZoneInfo

import pytest
from conftest import HEADERS
from fastapi.testclient import TestClient
from schulpilot.answer_evaluation import evaluate
from schulpilot.db import (
    DB,
    Activity,
    Assignment,
    Attempt,
    AttemptAssessment,
    Job,
    LearningUnit,
    Mastery,
    Material,
    UnitCoaching,
    Usage,
    now,
)
from schulpilot.main import app
from sqlalchemy import func, select


def question(prompt="Berechne 1/4 + 1/8. Gib den vollständigen Bruch an.", answer="3/8", **extra):
    return {"id": "fraction", "type": "short", "prompt": prompt, "answer": answer, "accepted": [], "options": [],
            "hints": ["Bringe beide Brüche auf dieselbe Einteilung."],
            "explanation": "1/4 entspricht 2/8. 2/8 + 1/8 = 3/8.", **extra}


@pytest.mark.parametrize("answer", ["3/8", "6/16", " 6 / 16 ", "9/24"])
def test_k45_equivalent_fraction_value_is_correct_without_reduction_instruction(answer):
    result = evaluate(question(), answer)
    assert result["outcome"] == result["dimensions"]["content"] == "correct"


@pytest.mark.parametrize("answer", ["2/12", "6/8", "3/16", "-3/8"])
def test_equivalence_never_accepts_a_different_fraction_value(answer):
    assert evaluate(question(), answer)["outcome"] == "incorrect"


def test_required_form_and_true_value_are_separate():
    q = question("Kürze 6/16 vollständig.")
    result = evaluate(q, "6/16")
    assert result["outcome"] == "incorrect" and result["dimensions"] == {"content": "correct", "form": "incorrect"}
    assert evaluate(q, "3/8")["outcome"] == "correct"
    assert evaluate(question("Berechne 1/4 + 1/8. Gib das Ergebnis als Bruch mit dem Nenner 8 an."), "6/16")["outcome"] == "incorrect"
    assert evaluate(question(answer="4/8"), "4/8")["outcome"] == "uncertain"  # bad stored key


def test_k10_closed_classification_accepts_an_inflected_reason_without_fuzzy_matching():
    q = question("Wie nennt man ein Tier ohne Wirbelsäule?", "Wirbellose Tiere")
    assert evaluate(q, "Es gehört zu den wirbellosen Tieren, weil es keine Wirbelsäule besitzt.")["outcome"] == "correct"
    for answer in ("Es gehört nicht zu den wirbellosen Tieren.", "Es ist ein Wirbeltier.",
                   "Es gehört zu den wirbellosen Tieren, weil es eine Wirbelsäule besitzt."):
        assert evaluate(q, answer)["outcome"] != "correct"
    assert evaluate(question("Erkläre die Ursache.", "Die untere Zahl"), "Eine ähnliche Idee.")["outcome"] == "uncertain"


def test_explicit_recheck_is_consistent_idempotent_private_and_does_not_count_practice(api, household):
    owner, child = household
    q = question()
    stamp = now() - 86400
    with DB.begin() as db:
        goal = Assignment(child_id=child["id"], kind="parent", subject="Mathematik", topic="Brüche", note="Künstlicher Lernauftrag.")
        db.add(goal)
        db.flush()
        unit = LearningUnit(child_id=child["id"], subject="Mathematik", topic="Brüche", explanation=q["explanation"],
                            questions=[q], status="completed", completed=int(stamp), provider="synthetic", synthetic=True,
                            assignment_id=goal.id)
        db.add(unit)
        db.flush()
        uid = unit.id
        attempt = Attempt(unit_id=uid, question_id=q["id"], answer="6/16", outcome="uncertain", assisted=False, created=stamp)
        db.add(attempt)
        db.flush()
        aid = attempt.id
        db.add(Mastery(child_id=child["id"], subject="Mathematik", topic="Brüche", independent=0, assisted=0,
                       difficulties=0, uncertain_units=1, review_successes=0, next_review="2026-10-20", last_practiced="2026-10-18"))
        db.add(UnitCoaching(unit_id=uid, status="ready", decision="parent_help", reason="Frühere offene Prüfung.",
                           report={"strengths":["Die Antwort wurde mit Hilfe gespeichert."], "question_reviews":[
            {"question_id":q["id"], "learning_goal_id":"g1", "outcome":"correct", "assessment_kind":"ai_opinion",
             "feedback":"Die Antwort ist als mit Hilfe gelöst gespeichert."}]}))
    route = f"/api/units/{uid}/questions/{q['id']}/recheck"
    before = api.get(f"/api/units/{uid}").json()
    assert before["learning_progress"]["state"] == "assessment_open"
    assert before["learning_progress"]["needs_parent"] is False
    assert before["learning_progress"]["practice"]["uncertain_tasks"] == 1
    assert before["learning_progress"]["practice"]["needs_practice_tasks"] == 0
    assert before["coaching"]["decision"] != "parent_help"
    assert api.post(route).status_code == 403
    with TestClient(app, headers=HEADERS) as kid:
        login = kid.post("/api/auth/login", json={"username":"test-child", "password":"secure-child-pass-123"}).json()
        kid.headers["Authorization"] = "Bearer " + login["token"]
        for _ in range(2):
            result = kid.post(route)
            assert result.status_code == 200, result.text
            assert result.json()["outcome"] == "correct" and not result.json()["assisted"]
        for client in (kid, api):
            ledger = client.get(f"/api/children/{child['id']}/learning-progress").json()["totals"]
            assert ledger["practiced_tasks"] == ledger["attempts"] == ledger["independent_tasks"] == 1
            assert ledger["uncertain_tasks"] == 0
            review = client.get(f"/api/units/{uid}").json()["coaching"]["report"]["question_reviews"][0]
            assert review["saved_outcome"] == "correct" and "mit Hilfe" not in review["feedback"]
        with TestClient(app, headers=HEADERS) as stranger:
            assert stranger.post(route).status_code == 401
        archive = api.get(f"/api/families/{owner['families'][0]['id']}/export").raise_for_status()
        with zipfile.ZipFile(io.BytesIO(archive.content)) as z:
            assert b'attempt_assessments' in z.read('family.json')
    with DB() as db:
        saved = db.get(Attempt, aid)
        assert saved.answer == "6/16" and saved.created == stamp and not saved.assisted
        history = list(db.scalars(select(AttemptAssessment)))
        assert len(history) == 1 and history[0].previous_outcome == "uncertain" and history[0].outcome == "correct"
        mastery = db.scalar(select(Mastery))
        assert mastery.uncertain_units == 0 and mastery.independent == 1
        assert mastery.last_practiced == datetime.fromtimestamp(stamp, ZoneInfo("Europe/Berlin")).date().isoformat()
        assert db.get(UnitCoaching, uid).decision == "check"
        assert history[0].evaluation["planning_before"]["decision"] == "parent_help"
        assert history[0].evaluation["planning_after"]["next_review"] == mastery.next_review
        for model in (Job, Usage, Activity):
            assert db.scalar(select(func.count()).select_from(model)) == 0


TASK_PAGE = "APP-TEST – keine echte Heftseite\nBrüche addieren\nProbeaufgabe:\n1/3 + 1/6 = ?\nDer Nenner beschreibt die Einteilung."


def task_source(child_id, *, stamp=None):
    with DB.begin() as db:
        material = Material(child_id=child_id, title="Künstliches Aufgabenblatt", subject="Mathematik", topic="Brüche",
                            content=TASK_PAGE, homework=["Probeaufgabe:", "1/3 + 1/6 = ?"], status="review", synthetic=False,
                            uncertainties=["Tabellenzeile unten ist unklar."], created=int(stamp or now()))
        db.add(material)
        db.flush()
        return material.id, material.revision


def task_body(revision):
    return {"subject":"Mathematik", "topic":"Brüche", "content":TASK_PAGE,
            "homework":["Probeaufgabe:", "1/3 + 1/6 = ?"], "revision":revision, "uncertainties_resolved":True}


def test_e07_bundles_header_and_formula_and_never_automatically_creates_binding_tasks(api, household):
    _, child = household
    mid, revision = task_source(child['id'])
    body = task_body(revision)
    for _ in range(2):
        response = api.post(f"/api/materials/{mid}/task-preview", json=body).json()
        assert len(response['items']) == 1
        assert response['items'][0]['classification'] == 'example'
        assert response['items'][0]['text'] == 'Probeaufgabe: 1/3 + 1/6 = ?'
    result = api.put(f"/api/materials/{mid}/confirm", json=body)
    assert result.status_code == 200, result.text
    assert result.json()['uncertainties']  # OCR confirmation does not certify the subject matter
    for _ in range(2):
        assert api.put(f"/api/materials/{mid}/confirm", json=body).json()['revision'] == revision+1
    with DB() as db:
        assert not list(db.scalars(select(Assignment)))
        assert db.scalar(select(func.count()).select_from(Activity).where(Activity.kind=='material_confirmed')) == 1
        assert db.scalar(select(func.count()).select_from(Job)) == db.scalar(select(func.count()).select_from(Usage)) == 0


def test_explicit_task_confirmation_deduplicates_variants_but_keeps_dates_and_provenance(api, household):
    _, child = household
    first, rev = task_source(child['id'])
    second, _ = task_source(child['id'])
    body = task_body(rev)
    candidate = api.post(f"/api/materials/{first}/task-preview", json=body).json()['items'][0]['key']
    body['task_decisions'] = [{'key':candidate, 'classification':'homework'}]
    assert api.put(f"/api/materials/{first}/confirm", json=body).json()['task_transfer']['added'] == 1
    assert api.put(f"/api/materials/{second}/confirm", json=body).json()['task_transfer']['duplicates'] == 1
    duplicate = api.get(f"/api/materials/{second}").json()['duplicate_candidates']
    assert any(row['id'] == first for row in duplicate)
    with DB() as db:
        rows = list(db.scalars(select(Assignment)))
        assert len(rows) == 1 and rows[0].mandatory and rows[0].origin_kind == 'homework'
        assert {r['id'] for r in rows[0].source_revisions} == {first, second}
        aid = rows[0].id
    tomorrow, _ = task_source(child['id'], stamp=now()+86400)
    assert api.put(f"/api/materials/{tomorrow}/confirm", json=body).json()['task_transfer']['added'] == 1
    # A correction preserves the original task and links, but withdraws it
    # from new automatic planning until a parent reviews the changed source.
    changed = task_body(rev+1) | {'content':TASK_PAGE+'\nGeänderter Rechenschritt.'}
    assert api.put(f"/api/materials/{first}/confirm", json=changed).status_code == 200
    with DB() as db:
        assert db.get(Assignment, aid).source_status == 'needs_review'
        assert db.get(Assignment, aid).origin_kind == 'homework'
    denied = api.post(f"/api/children/{child['id']}/units", json={'assignment_id':aid})
    assert denied.status_code == 409
    view = api.get(f"/api/children/{child['id']}/overview").json()
    assert aid not in {row['id'] for row in view['plan']['today']}


def test_parent_reading_cannot_create_child_time_answers_or_progress(api, household):
    _, child = household
    with DB.begin() as db:
        unit = LearningUnit(child_id=child['id'], subject='Mathematik', topic='Brüche', questions=[question()],
                            explanation='Künstliches Beispiel.', status='active', heartbeat=int(now())-10,
                            provider='synthetic', synthetic=True)
        db.add(unit)
        db.flush()
        uid = unit.id
    for _ in range(2):
        for route in (f"/api/children/{child['id']}/overview", f'/api/units/{uid}',
                      f"/api/children/{child['id']}/activity", f"/api/children/{child['id']}/learning-progress"):
            assert api.get(route).status_code == 200
    assert api.post(f'/api/units/{uid}/heartbeat', json={}).status_code == 403
    assert api.post(f'/api/units/{uid}/start').status_code == 403
    with DB() as db:
        assert db.get(LearningUnit, uid).active_seconds == 0 and db.get(LearningUnit, uid).status == 'active'
        for model in (Attempt, Activity, Mastery):
            assert db.scalar(select(func.count()).select_from(model)) == 0


def test_error_specific_match_hints_are_distinct_and_retry_is_idempotent(api, household):
    _, child = household
    q = question('Ordne die Tiere ihren Klassen zu.', 'Säugetiere;Amphibien;Fische;Vögel', type='match',
                 options=['Hund|Säugetiere', 'Frosch|Amphibien', 'Karpfen|Fische', 'Amsel|Vögel'],
                 hints=['Kröte und Frosch gehören zur gleichen Klasse.'])
    with DB.begin() as db:
        unit = LearningUnit(child_id=child['id'], subject='Biologie', topic='Tierklassen', questions=[q],
                            explanation='Künstliche Zuordnungsaufgabe.', status='active', provider='synthetic', synthetic=True)
        db.add(unit)
        db.flush()
        uid = unit.id
    with TestClient(app, headers=HEADERS) as kid:
        login = kid.post('/api/auth/login', json={'username':'test-child', 'password':'secure-child-pass-123'}).json()
        kid.headers['Authorization'] = 'Bearer '+login['token']
        result = kid.post(f'/api/units/{uid}/questions/fraction/answer', json={'answer':'Reptilien;Amphibien;Fische;Vögel', 'request_id':'same-artificial-answer-01'})
        assert result.status_code == 200, result.text
        assert [p['outcome'] for p in result.json()['evaluation']['parts']] == ['incorrect','correct','correct','correct']
        first = kid.post(f'/api/units/{uid}/questions/fraction/hint', headers={'Idempotency-Key':'same-artificial-hint-01'}).json()
        replay = kid.post(f'/api/units/{uid}/questions/fraction/hint', headers={'Idempotency-Key':'same-artificial-hint-01'}).json()
        second = kid.post(f'/api/units/{uid}/questions/fraction/hint', headers={'Idempotency-Key':'same-artificial-hint-02'}).json()
        assert first == replay and 'Hund' in first['hint'] and first['hint'] != second['hint']
        assert 'Frosch' not in second['hint']
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Activity).where(Activity.kind=='hint')) == 2
        assert db.scalar(select(func.count()).select_from(Attempt)) == 1
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


def test_free_day_has_no_achieved_daily_minimum_even_with_saved_time(api, household, monkeypatch):
    from datetime import date

    from schulpilot import learning
    from schulpilot.db import Child

    _, child = household
    monkeypatch.setattr(learning, 'local_day', lambda _: date(2026,10,18))  # Sunday, Europe/Berlin
    with DB.begin() as db:
        row = db.get(Child, child['id'])
        row.preferences = {'weekdays':[0,1,2,3,4], 'daily_minutes':20, 'timezone':'Europe/Berlin'}
        db.add(Activity(child_id=row.id, kind='active_time', detail={'seconds':1300}, created=1792321200))
        db.flush()
        time = learning.learning_time(db,row)
        assert time['daily_active_seconds'] >= 1200
        assert time['goal_required'] is False and time['daily_goal_met'] is False


def test_help_context_is_owned_and_notification_opens_the_exact_task(api, household):
    _, child = household
    with DB.begin() as db:
        unit = LearningUnit(child_id=child['id'], subject='Mathematik', topic='Brüche', questions=[question()],
                            explanation='Künstliche Aufgabe.', status='paused', provider='synthetic', synthetic=True)
        db.add(unit)
        db.flush()
        uid = unit.id
    with TestClient(app, headers=HEADERS) as kid:
        login = kid.post('/api/auth/login', json={'username':'test-child','password':'secure-child-pass-123'}).json()
        kid.headers['Authorization'] = 'Bearer '+login['token']
        path = f"/api/children/{child['id']}/messages"
        assert kid.post(path, json={'kind':'help','body':'Künstlicher Hilfewunsch.', 'unit_id':'f'*32}).status_code == 404
        assert kid.post(path, json={'kind':'help','body':'Künstlicher Hilfewunsch.', 'unit_id':uid}).status_code == 201
    inbox = api.get('/api/notifications/inbox').json()
    assert len(inbox['items']) == 1 and inbox['items'][0]['route'] == f'/unit/{uid}'


def test_explicit_homework_can_restore_a_dismissed_proposal_without_a_duplicate(api, household):
    _, child = household
    mid, rev = task_source(child['id'])
    body = task_body(rev)
    key = api.post(f'/api/materials/{mid}/task-preview', json=body).json()['items'][0]['key']
    for offset, classification in enumerate(('homework', 'example', 'homework')):
        request = body | {'revision': rev + offset, 'task_decisions':[{'key':key, 'classification':classification}]}
        response = api.put(f'/api/materials/{mid}/confirm', json=request)
        assert response.status_code == 200, response.text
        assert response.json()['task_preview'][0]['classification'] == classification
        assert bool(response.json()['confirmed_tasks']) is (classification == 'homework')
        preview = api.post(f'/api/materials/{mid}/task-preview', json=task_body(rev + offset + 1)).json()
        assert preview['items'][0]['classification'] == classification
        with DB() as db:
            rows = list(db.scalars(select(Assignment)))
            assert len(rows) == 1
            assert rows[0].mandatory is (classification == 'homework')
            assert rows[0].source_status == ('confirmed' if classification == 'homework' else 'dismissed')


@pytest.mark.parametrize('prompt', ['1/4 + 1/8 = ?', 'Ergänze die Summe 1/4 + 1/8 = ___'])
def test_fraction_equation_does_not_need_a_magic_calculate_word(prompt):
    assert evaluate(question(prompt), '6/16')['outcome'] == 'correct'
    assert evaluate(question(prompt), '3/16')['outcome'] == 'incorrect'
