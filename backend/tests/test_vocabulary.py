from datetime import datetime, timezone

import pytest
from conftest import create_child, register
from schulpilot import language_evaluation, vocabulary, vocabulary_review
from schulpilot.db import DB, Attempt, Child, LearningUnit, VocabularyItem, VocabularyReview, VocabularyReviewEvent
from schulpilot.language_tasks import EvaluationPolicy, LanguageTask, RoundRequest
from sqlalchemy import func, select

CAPS = {"X-Schulpilot-Capabilities": "language-v1"}


def test_source_proof_does_not_confuse_word_fragments_with_confirmed_forms():
    assert not vocabulary.literal_present("He goes to school.", "go")
    assert vocabulary.literal_present("He goes to school.", "goes")
    assert not vocabulary.literal_present("apple = Apfel", "app")
    assert vocabulary.literal_present("école = Schule", "école")


def child_login(api, username="test-child"):
    login = api.post("/api/auth/login", json={"username": username, "password": "secure-child-pass-123"})
    assert login.status_code == 200, login.text
    api.headers["Authorization"] = "Bearer " + login.json()["token"]
    api.headers.update(CAPS)


def import_words(api, child, key="vocabulary-import-0001", pairs=None):
    pairs = pairs if pairs is not None else [
        {"word": "apple", "meaning": "Apfel"},
        {"word": "dog", "meaning": "Hund"},
        {"word": "school", "meaning": "Schule"},
    ]
    data = {"target_locale": "en-GB", "title": "Unsere Schulwörter", "pairs": pairs, "language_confirmed": True}
    response = api.post(f"/api/children/{child['id']}/vocabulary/imports", json=data, headers={"Idempotency-Key": key})
    assert response.status_code == 201, response.text
    row = response.json()
    confirmed = api.post(
        f"/api/children/{child['id']}/vocabulary/imports/{row['id']}/confirm",
        json={"pairs": row["pairs"], "target_locale": "en-GB", "language_confirmed": True},
    )
    assert confirmed.status_code == 200, confirmed.text
    return row, data, confirmed.json()


def round_(api, child, *, key="vocabulary-round-00001", skill="spelling", direction="de_to_target", voluntary=False):
    response = api.post(
        f"/api/children/{child['id']}/vocabulary/rounds",
        headers={"Idempotency-Key": key},
        json={"target_locale": "en-GB", "count": 3, "skill": skill, "direction": direction, "voluntary": voluntary},
    )
    assert response.status_code == 201, response.text
    unit_id = response.json()["unit_id"]
    response = api.post(f"/api/units/{unit_id}/start")
    assert response.status_code == 200, response.text
    return response.json()


def correct_answer(unit_id, question_id):
    with DB() as db:
        return next(q["answer"] for q in db.get(LearningUnit, unit_id).questions if q["id"] == question_id)


@pytest.mark.parametrize("available,count,expected", [(16, None, 10), (16, 15, 15), (9, 10, 9)])
def test_larger_local_word_rounds_are_bounded_idempotent_and_preserve_resume(api, household, available, count, expected):
    from schulpilot.db import Usage

    _, child = household
    import_words(api, child, pairs=[{"word": f"term{i}", "meaning": f"Wort{i}"} for i in range(available)])
    child_login(api)
    data = {"target_locale": "en-GB", "skill": "spelling"}
    if count is not None:
        data["count"] = count
    url = f"/api/children/{child['id']}/vocabulary/rounds"
    headers = {"Idempotency-Key": "larger-round-00000001"}
    response = api.post(url, json=data, headers=headers)
    assert response.status_code == 201, response.text
    unit_id = response.json()["unit_id"]
    unit = api.get(f"/api/units/{unit_id}").json()
    assert len(unit["questions"]) == expected
    assert len({q["language"]["vocabulary_item_id"] for q in unit["questions"]}) == expected
    assert all("answer" not in q for q in unit["questions"])
    assert api.post(url, json=data, headers=headers).json()["unit_id"] == unit_id
    assert api.post(url, json={**data, "count": 2}, headers=headers).status_code == 409
    resumed = api.post(url, json={**data, "count": 5}, headers={"Idempotency-Key": "resume-larger-round"})
    assert resumed.json() == {"unit_id": unit_id, "resumed": True}
    assert api.post(url, json={**data, "count": 16}, headers={"Idempotency-Key": "oversized-word-round"}).status_code == 422
    with DB() as db:
        assert len(db.get(LearningUnit, unit_id).questions) == expected
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 1
        assert db.scalar(select(func.count()).select_from(Usage)) == 0
        assert db.scalar(select(func.count()).select_from(VocabularyReviewEvent)) == 0
    if expected == 15:
        assert api.post(f"/api/units/{unit_id}/start").status_code == 200
        for question in unit["questions"]:
            answer = api.post(f"/api/units/{unit_id}/questions/{question['id']}/answer", json={
                "answer": correct_answer(unit_id, question["id"]),
                "request_id": "large-word-answer-" + question["id"],
            })
            assert answer.status_code == 200, answer.text
        result = api.get(f"/api/units/{unit_id}").json()
        assert result["status"] == "completed" and result["vocabulary_result"]["answered_tasks"] == 15
        assert result["coaching"]["status"] == "not_needed"
        with DB() as db:
            assert db.scalar(select(func.count()).select_from(Attempt)) == 15
            assert db.scalar(select(func.count()).select_from(VocabularyReviewEvent)) == 15
            assert db.scalar(select(func.count()).select_from(Usage)) == 0


def test_manual_to_round_plan_parent_and_idempotent_attempts(api, household):
    parent, child = household
    draft, data, confirmed = import_words(api, child)
    repeated = api.post(
        f"/api/children/{child['id']}/vocabulary/imports",
        json=data,
        headers={"Idempotency-Key": "vocabulary-import-0001"},
    )
    assert repeated.json()["id"] == draft["id"]
    assert repeated.json()["collection_id"] == confirmed["collection_id"]
    changed = dict(data, title="Andere Wörter")
    assert (
        api.post(
            f"/api/children/{child['id']}/vocabulary/imports",
            json=changed,
            headers={"Idempotency-Key": "vocabulary-import-0001"},
        ).status_code
        == 409
    )
    child_login(api)
    unit = round_(api, child)
    for q in unit["questions"]:
        assert not {"answer", "accepted", "evaluation_policy"}.intersection(q)
        assert "evaluation_policy" not in q["language"]
        payload = {"answer": correct_answer(unit["id"], q["id"]), "request_id": "answer-vocabulary-" + q["id"]}
        response = api.post(f"/api/units/{unit['id']}/questions/{q['id']}/answer", json=payload)
        assert response.status_code == 200, response.text
        assert response.json()["outcome"] == "correct"
        replay = api.post(f"/api/units/{unit['id']}/questions/{q['id']}/answer", json=payload)
        assert replay.status_code == 200, replay.text
        assert replay.json()["attempt_id"] == response.json()["attempt_id"]
        assert (
            api.post(
                f"/api/units/{unit['id']}/questions/{q['id']}/answer", json={**payload, "answer": "wrong"}
            ).status_code
            == 409
        )
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Attempt)) == 3
        assert db.scalar(select(func.count()).select_from(VocabularyReviewEvent)) == 3
        assert {r.skill for r in db.scalars(select(VocabularyReview))} == {"spelling"}
        assert all(r.stage == 1 for r in db.scalars(select(VocabularyReview)))
    assert api.get(f"/api/children/{child['id']}/learning-progress").json()["totals"]["practiced_tasks"] == 3
    login = api.post("/api/auth/login", json={"username": "parent@example.org", "password": "secure-parent-pass-123"})
    api.headers["Authorization"] = "Bearer " + login.json()["token"]
    response = api.get(f"/api/children/{child['id']}/vocabulary")
    assert response.status_code == 200, response.text
    listed = response.json()
    assert listed["summary"]["confirmed_words"] == 3
    assert listed["summary"]["skills"][0]["skill"] == "spelling"
    assert listed["pagination"]["total"] == 3


def test_capability_recognition_not_spelling_and_help(api, household):
    _, child = household
    import_words(api, child)
    child_login(api)
    unit = round_(api, child, skill="recognition", direction="target_to_de")
    api.headers.pop("X-Schulpilot-Capabilities")
    assert api.get(f"/api/units/{unit['id']}").status_code == 426
    api.headers.update(CAPS)
    for q in unit["questions"]:
        answer = correct_answer(unit["id"], q["id"])
        assert (
            api.post(
                f"/api/units/{unit['id']}/questions/{q['id']}/answer",
                json={"answer": answer, "request_id": "recognition-answer-" + q["id"]},
            ).status_code
            == 200
        )
    with DB() as db:
        assert {r.skill for r in db.scalars(select(VocabularyReview))} == {"recognition"}
    unit = round_(api, child, key="vocabulary-spelling-002")
    q = unit["questions"][0]
    assert (
        api.post(
            f"/api/units/{unit['id']}/questions/{q['id']}/language-stimulus", json={"kind": "solution"}
        ).status_code
        == 200
    )
    result = api.post(
        f"/api/units/{unit['id']}/questions/{q['id']}/answer",
        json={"answer": correct_answer(unit["id"], q["id"]), "request_id": "spelling-answer-" + q["id"]},
    ).json()
    assert result["assisted"] is True
    with DB() as db:
        state = db.scalar(
            select(VocabularyReview).where(
                VocabularyReview.item_id == q["language"]["vocabulary_item_id"], VocabularyReview.skill == "spelling"
            )
        )
        assert state.stage == 0


@pytest.mark.parametrize(
    "answer,expected,case,variants,closed,outcome",
    [
        ("were", "where", True, [], True, "incorrect"),
        ("your", "you're", True, [], True, "incorrect"),
        ("He go to school", "He goes to school", True, [], True, "incorrect"),
        ("I do not like tea", "I don't like tea", True, ["I do not like tea"], True, "correct"),
        ("I do not like tea", "I don't like tea", True, [], False, "uncertain"),
        ("ecole", "école", True, [], True, "incorrect"),
        ("london", "London", True, [], True, "incorrect"),
        ("Hund", "hund", False, [], True, "correct"),
        ("I don’t like tea", "I don't like tea", True, [], True, "correct"),
        ("dog", "the dog", True, [], True, "incorrect"),
        ("color", "colour", True, [], True, "incorrect"),
        ("color", "colour", True, ["color"], True, "correct"),
        ("e\u0301cole", "école", True, [], True, "correct"),
    ],
)
def test_exact_language_evaluation(answer, expected, case, variants, closed, outcome):
    meta = LanguageTask(
        target_locale="en-GB",
        answer_locale="en-GB",
        task_kind="spelling",
        skill="spelling",
        direction="de_to_target",
        vocabulary_item_id="a" * 32,
        vocabulary_revision=1,
        evaluation_policy=EvaluationPolicy(
            criterion="spelling", case_sensitive=case, apostrophe_equivalent=True, closed_answers=closed
        ),
    )
    q = {"answer": expected, "accepted": variants, "language": meta.model_dump()}
    result = language_evaluation.evaluate(q, answer)
    assert result["outcome"] == outcome


def test_ambiguous_missing_and_revisions(api, household):
    _, child = household
    draft, _, _ = import_words(api, child)
    items = api.get(f"/api/children/{child['id']}/vocabulary").json()["items"]
    item = items[0]
    bad = {"word": "bank", "meaning": "Bank", "context": "", "revision": item["revision"], "confirmed": True}
    assert api.put(f"/api/children/{child['id']}/vocabulary/{item['id']}", json=bad).status_code == 422
    good = {**bad, "context": "sitting in the park"}
    result = api.put(f"/api/children/{child['id']}/vocabulary/{item['id']}", json=good)
    assert result.status_code == 200, result.text
    assert result.json()["revision"] == 2
    assert api.put(f"/api/children/{child['id']}/vocabulary/{item['id']}", json=good).status_code == 409
    child_login(api)
    assert api.get(f"/api/children/{child['id']}/vocabulary?page_size=1").json()["pagination"]["total"] == 3


def test_other_family_admin_and_list_reads(api, mailbox, household):
    _, child = household
    import_words(api, child)
    other = register(api, mailbox, "other@example.org")
    create_child(api, other, "other-child")
    assert api.get(f"/api/children/{child['id']}/vocabulary").status_code in (403, 404)


def test_legacy_lists_withhold_new_language_rounds_but_time_and_attempts_remain(api, household):
    _, child = household
    import_words(api, child)
    child_login(api)
    unit = round_(api, child)
    q = unit["questions"][0]
    assert (
        api.post(
            f"/api/units/{unit['id']}/questions/{q['id']}/answer",
            json={
                "answer": correct_answer(unit["id"], q["id"]),
                "guided_feedback": True,
                "request_id": "language-cap-answer-0001",
            },
        ).status_code
        == 200
    )
    api.headers.pop("X-Schulpilot-Capabilities")
    overview = api.get(f"/api/children/{child['id']}/overview").json()
    assert not overview["units"]
    assert overview["feedback_resume"] is None
    assert "vocabulary" not in {row["kind"] for row in overview["plan"]["voluntary"]}
    assert api.get(f"/api/children/{child['id']}/learning").json()["items"] == []
    api.headers.update(CAPS)
    assert api.get(f"/api/children/{child['id']}/overview").json()["feedback_resume"]["id"] == unit["id"]
    assert api.get(f"/api/children/{child['id']}/learning-progress").json()["totals"]["practiced_tasks"] == 1


def test_timezone_dst_and_once_per_local_day(api, household):
    _, child_data = household
    import_words(api, child_data)
    with DB.begin() as db:
        child = db.get(Child, child_data["id"])
        child.preferences = {**child.preferences, "timezone": "Europe/Berlin"}
        item = db.scalar(select(VocabularyItem))
        task = vocabulary.task_for(item, RoundRequest(target_locale="en-GB"), 0, [item])
        unit = LearningUnit(
            child_id=child.id,
            subject="Englisch",
            topic="Wörter",
            explanation="",
            questions=[task],
            provider="vocabulary",
        )
        db.add(unit)
        db.flush()
        for index, instant in enumerate(
            [
                datetime(2026, 10, 24, 22, 30, tzinfo=timezone.utc),
                datetime(2026, 10, 25, 1, 30, tzinfo=timezone.utc),
                datetime(2026, 10, 25, 23, 1, tzinfo=timezone.utc),
            ]
        ):
            attempt = Attempt(unit_id=unit.id, question_id="v1", answer=item.word, outcome="correct", assisted=False)
            db.add(attempt)
            db.flush()
            vocabulary_review.record_review(db, unit, task, attempt, at=instant)
            vocabulary_review.record_review(db, unit, task, attempt, at=instant)
            state = db.scalar(select(VocabularyReview))
            assert state.stage == (1 if index < 2 else 2)
        assert db.scalar(select(func.count()).select_from(VocabularyReviewEvent)) == 3


def test_possible_prior_solution_keeps_existing_word_review_stage(api, household):
    _, child_data = household
    import_words(api, child_data)
    with DB.begin() as db:
        child = db.get(Child, child_data["id"])
        item = db.scalar(select(VocabularyItem))
        task = vocabulary.task_for(item, RoundRequest(target_locale="en-GB"), 0, [item])
        unit = LearningUnit(child_id=child.id, subject="Englisch", topic="Wörter", explanation="",
                            questions=[task], provider="vocabulary")
        db.add(unit)
        db.flush()
        first = Attempt(unit_id=unit.id, question_id="first", answer=item.word, outcome="correct", assisted=False)
        db.add(first)
        db.flush()
        vocabulary_review.record_review(db, unit, task, first)
        state = db.scalar(select(VocabularyReview))
        previous = (state.stage, state.due, state.last_promoted)
        pending = Attempt(unit_id=unit.id, question_id="next", answer=item.word, outcome="correct", assisted=True,
                          evaluation={"independence_uncertain": True})
        db.add(pending)
        db.flush()
        vocabulary_review.record_review(db, unit, task, pending)
        vocabulary_review.record_review(db, unit, task, pending)
        assert (state.stage, state.due, state.last_promoted) == previous
        assert db.scalar(select(func.count()).select_from(VocabularyReviewEvent)) == 2
        values = vocabulary_review.states(db, item)
        assert values[0]["independent_correct"] == 1
        assert values[0]["assisted_correct"] == 0
        assert values[0]["uncertain"] == 1
