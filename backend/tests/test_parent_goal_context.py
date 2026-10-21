"""Parent plans describe observed subskills, not broad topic assumptions."""

import pytest
from schulpilot import parent_insights
from schulpilot.db import DB, Attempt, Child, LearningUnit, ParentLearningReview, UnitCoaching, Usage, now
from sqlalchemy import func, select
from test_parent_insights import seed
from test_tutor import notebook as _notebook


@pytest.fixture
def book(api, household):
    yield from _notebook.__wrapped__(api, household)


def report(unit_id, *, missing=False, ambiguous=False):
    reviews = [{"question_id": f"q{i}", "learning_goal_id": "g1", "feedback": "PRIVATE-COACH-FEEDBACK"}
               for i in range(2 if missing else 3)]
    if ambiguous:
        reviews.append({"question_id": "q1", "learning_goal_id": "g2"})
    return UnitCoaching(unit_id=unit_id, status="ready", report={
        "learning_goals": [
            {"id": "g1", "label": "Brüche erweitern", "source_excerpt": "PRIVATE-SOURCE-QUOTE"},
            {"id": "g2", "label": "Brüche addieren", "source_excerpt": "PRIVATE-SOURCE-QUOTE"}],
        "question_reviews": [*reviews, {"question_id": "unanswered", "learning_goal_id": "g2"}]})


@pytest.mark.parametrize("missing,ambiguous,unmapped", [(False, False, 0), (True, False, 1), (False, True, 1)])
def test_only_uniquely_reviewed_answered_subskills_reach_parent_context(api, book, missing, ambiguous, unmapped):
    unit_id = seed(book)
    with DB.begin() as db:
        db.get(LearningUnit, unit_id).topic = "Brüche addieren"
        child = db.get(Child, book["child"]["id"])
        signature_before, before, _, _ = parent_insights.facts(db, child)
        assert before["topics"][0]["learning_goals"] == []
        assert before["topics"][0]["unmapped_tasks"] == 3
        assert before["topics"][0]["evidence_scope"] == "unmapped_topic_tasks"
        db.add(report(unit_id, missing=missing, ambiguous=ambiguous))
    with DB() as db:
        signature_after, payload, topics, _ = parent_insights.facts(db, db.get(Child, book["child"]["id"]))
        assert signature_after != signature_before and payload["strategy_version"] == "parent-review-3"
        observed = payload["topics"][0]
        assert observed["topic"] == "Brüche addieren"
        assert observed["evidence_scope"] == "reviewed_answered_goals"
        assert [g["label"] for g in observed["learning_goals"]] == ["Brüche erweitern"]
        assert observed["unmapped_tasks"] == unmapped
        goal = observed["learning_goals"][0]
        assert goal["practiced_tasks"] == 3 - unmapped
        assert goal["independent_tasks"] == 0 and goal["needs_practice_tasks"] == 1
        assert goal["assisted_tasks"] == (0 if ambiguous else 1)
        assert goal["uncertain_tasks"] == (0 if missing else 1)
        assert topics[0]["learning_goals"] == observed["learning_goals"]
        outbound = str(payload)
        for private in ("PRIVATE-SYNTHETIC-ANSWER", "PRIVATE-SOURCE-QUOTE", "PRIVATE-COACH-FEEDBACK", unit_id, book["child"]["id"]):
            assert private not in outbound
    # Reading the enriched scope does not reserve any review or mutate facts.
    response = api.get(f"/api/children/{book['child']['id']}/parent-insights")
    assert response.status_code == 200 and response.json()["eligible"]
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Attempt)) == 3
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


def test_goal_context_is_bounded_and_excluded_mappings_remain_explicitly_unknown(api, book):
    with DB.begin() as db:
        for index in range(6):
            unit = LearningUnit(child_id=book["child"]["id"], subject="Mathematik", topic="Breites Thema",
                explanation="Synthetic", questions=[], provider="synthetic", status="active")
            db.add(unit)
            db.flush()
            db.add(Attempt(unit_id=unit.id, question_id="q", answer="PRIVATE-ANSWER", outcome="correct", assisted=False))
            db.add(UnitCoaching(unit_id=unit.id, status="ready" if index != 5 else "failed", report={
                "learning_goals": [{"id": "g1", "label": f"Belegte Teilfertigkeit {index}", "source_excerpt": "PRIVATE-QUOTE"}],
                "question_reviews": [{"question_id": "q", "learning_goal_id": "g1", "feedback": "PRIVATE-FEEDBACK"}]}))
    with DB() as db:
        _, payload, _, _ = parent_insights.facts(db, db.get(Child, book["child"]["id"]))
        topic = payload["topics"][0]
        assert len(topic["learning_goals"]) == 4
        assert topic["unmapped_tasks"] == 2
        assert sum(g["practiced_tasks"] for g in topic["learning_goals"]) + topic["unmapped_tasks"] == 6
        assert all("Teilfertigkeit 5" not in g["label"] for g in topic["learning_goals"])


def test_prior_strategy_reports_stay_readable_without_driving_new_goal_context(api, book):
    seed(book)
    with DB.begin() as db:
        child = db.get(Child, book["child"]["id"])
        _, payload, _, _ = parent_insights.facts(db, child)
        old = ParentLearningReview(child_id=child.id, family_id=child.family_id, status="ready",
            signature="historical-parent-review-2", created=int(now()), finished=int(now()),
            observations={"basis": payload["_basis"], "provenance": {"strategy_version": "parent-review-2"}},
            report={"summary": "Historischer Bericht bleibt erhalten.", "findings": [], "plan": []})
        db.add(old)
        db.flush()
        old_id = old.id
    for _ in range(2):
        view = api.get(f"/api/children/{book['child']['id']}/parent-insights").json()
        assert view["latest"]["id"] == old_id and view["stale"]
        assert not view["plan_applies"] and view["pending"] is None
    with DB() as db:
        assert db.get(ParentLearningReview, old_id).report["summary"] == "Historischer Bericht bleibt erhalten."
        assert db.scalar(select(func.count()).select_from(Usage)) == 0
