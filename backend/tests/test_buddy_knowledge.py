"""Only synthetic stored evidence is used for the assistant's prior knowledge."""

import copy

import pytest
from schulpilot.db import DB, Attempt, Child, Job, LearningUnit, Material, UnitCoaching, UnitSource, now
from schulpilot.learning_knowledge import buddy_context, evidence
from sqlalchemy import func, select
from test_adaptive_plan import fraction_profile as original_profile


@pytest.fixture
def profile(api, household):
    yield from original_profile.__wrapped__(api, household)


def test_buddy_reads_exact_stored_goals_without_creating_learning_or_jobs(profile):
    _, uid, mid, _, _, child = profile
    with DB.begin() as db:
        db.add(Attempt(unit_id=uid, question_id="sum", answer="private answer body",
            outcome="incorrect", assisted=False, evaluation={"attempt_number": 1}))
    with DB() as db:
        before = db.scalar(select(func.count()).select_from(Job))
        snapshot = buddy_context(db, db.get(Child, child["id"]), unit=db.get(LearningUnit, uid))
        matching = buddy_context(db, db.get(Child, child["id"]), material_ids=[mid])
        goal = next(g for g in snapshot["goals"] if g["label"] == "Brüche addieren")
        assert snapshot["scope"] == "confirmed_source_goals"
        assert goal["needs_practice"] == 1 and goal["independent"] == 0
        assert goal["confidence"] == "support_needed" and goal["evidence_refs"]
        assert matching["goals"] == snapshot["goals"]
        assert "private answer body" not in str(snapshot)
        assert db.scalar(select(func.count()).select_from(Job)) == before == 0
        assert snapshot["prerequisites"]
        assert db.scalar(select(func.count()).select_from(Attempt)) == 1


def test_unknown_is_distinct_from_incorrect_and_stale_source_has_no_current_claim(profile):
    _, uid, mid, _, _, child = profile
    with DB() as db:
        snapshot = buddy_context(db, db.get(Child, child["id"]), unit=db.get(LearningUnit, uid))
        assert snapshot["goals"]
        assert all(g["confidence"] == "unverified" and g["tasks"] == 0 for g in snapshot["goals"])
    with DB.begin() as db:
        db.get(Material, mid).revision += 1
    with DB() as db:
        snapshot = buddy_context(db, db.get(Child, child["id"]), unit=db.get(LearningUnit, uid))
        assert not snapshot["source_valid"] and not snapshot["goals"]
        assert snapshot["scope"] == "practice_summary_only"


def test_tied_attempt_timestamps_use_saved_attempt_order_and_keep_supported_success(profile):
    _, uid, mid, _, _, child = profile
    with DB.begin() as db:
        db.add_all([
            Attempt(id="f" * 32, unit_id=uid, question_id="sum", answer="wrong", outcome="incorrect",
                assisted=False, created=100, evaluation={"attempt_number": 1}),
            Attempt(id="0" * 32, unit_id=uid, question_id="sum", answer="right", outcome="correct",
                assisted=False, created=100, evaluation={"attempt_number": 2}),
        ])
    with DB() as db:
        rows = evidence(db, db.get(LearningUnit, uid), [db.get(Material, mid)])
        goal = next(g for g in rows if g["label"] == "Brüche addieren")
        assert goal["supported"] == 1 and goal["independent"] == 0
        assert goal["needs_practice"] == 0 and goal["attempts"] == 2
        assert goal["successful_check_dates"] == []
        assert buddy_context(db, db.get(Child, child["id"]), unit=db.get(LearningUnit, uid))["goals"]


def test_followup_without_new_report_retains_nonfraction_confirmed_goal_mapping(profile):
    _, uid, mid, _, _, child = profile
    with DB.begin() as db:
        source = db.get(Material, mid)
        source.subject, source.topic = "Biologie", "Pflanzen"
        source.content = "Eine Pflanze hat Wurzeln und Blätter."
        source.source_blocks = []
        root = db.get(LearningUnit, uid)
        root.subject = "Biologie"
        root.topic = "Pflanzen"
        root.questions = [{**copy.deepcopy(root.questions[0]), "learning_goal_id": "root-parts",
            "prompt": "Benenne einen Teil der Pflanze."}]
        db.add(UnitCoaching(unit_id=uid, status="ready", report={"learning_goals": [
            {"id": "root-parts", "label": "Pflanzenteile benennen", "source_excerpt": "Wurzeln und Blätter"}]}))
        new = LearningUnit(child_id=child["id"], material_id=mid, subject="Biologie", topic="Pflanzen",
            explanation="Synthetische Wiederholung", questions=copy.deepcopy(root.questions),
            learning_root_id=uid, followup_of=uid, round_kind="spaced_review", provider="openai", model="fixture")
        db.add(new)
        db.flush()
        db.add(UnitSource(unit_id=new.id, material_id=mid, revision=db.get(Material, mid).revision))
        db.add(Attempt(unit_id=new.id, question_id=new.questions[0]["id"], answer="Blatt",
            outcome="correct", assisted=False))
    with DB() as db:
        snapshot = buddy_context(db, db.get(Child, child["id"]), unit=db.get(LearningUnit, uid))
        goal = next(g for g in snapshot["goals"] if g["label"] == "Pflanzenteile benennen")
        assert goal["independent"] == 1 and goal["tasks"] == 1
        assert goal["confidence"] == "initial_evidence"
        assert len(goal["successful_check_dates"]) == 1
        assert not snapshot["prerequisites"]  # no invented biology curriculum


def test_general_subject_observations_do_not_expose_answers_or_claim_goal_mastery(profile):
    _, uid, _, _, _, child = profile
    with DB.begin() as db:
        db.add(Attempt(unit_id=uid, question_id="sum", answer="private draft",
            outcome="uncertain", assisted=False))
    with DB() as db:
        snapshot = buddy_context(db, db.get(Child, child["id"]), limit=1)
        assert not snapshot["goals"] and snapshot["scope"] == "practice_summary_only"
        assert snapshot["subjects"][0]["uncertain_tasks"] == 1
        assert snapshot["subjects"][0]["needs_practice_tasks"] == 0
        assert len(snapshot["subjects"]) == 1 and "private draft" not in str(snapshot)
        other = Child(id="another-child", user_id="another-user", family_id=child["family_id"] if "family_id" in child else "other")
        with pytest.raises(ValueError, match="another child"):
            buddy_context(db, other, unit=db.get(LearningUnit, uid))


def test_reflection_keeps_secure_recall_and_never_moves_the_review_anchor(profile):
    _, uid, mid, _, _, child = profile
    with DB.begin() as db:
        root, source = db.get(LearningUnit, uid), db.get(Material, mid)
        template = copy.deepcopy(root.questions[0])
        for days, prompt, answer in ((9, "Berechne 2/5 + 1/10.", "1/2"),
                (5, "Berechne 1/4 + 1/6.", "5/12"), (1, "Berechne 1/3 + 1/12.", "5/12")):
            old = LearningUnit(child_id=child["id"], material_id=mid,
                subject=root.subject, topic=root.topic, explanation="Künstliche Abrufprüfung",
                questions=[{**template, "id": "recall", "prompt": prompt, "answer": answer}],
                learning_root_id=uid, followup_of=uid, round_kind="spaced_review",
                status="completed", provider="openai", model="fixture")
            db.add(old)
            db.flush()
            db.add(UnitSource(unit_id=old.id, material_id=mid, revision=source.revision))
            db.add(Attempt(unit_id=old.id, question_id="recall", answer=answer,
                outcome="correct", assisted=False, created=int(now()) - days * 86400))
    with DB() as db:
        before = next(g for g in evidence(db, db.get(LearningUnit, uid), [db.get(Material, mid)])
            if g["label"] == "Brüche addieren")
        assert before["confidence"] == "repeated_recall" and before["independent"] == 3
    with DB.begin() as db:
        db.add(Attempt(unit_id=uid, question_id="sum", answer="Mein eigener Lernrückblick",
            outcome="uncertain", assisted=False, evaluation={"method": "open_learning_v1"}, created=int(now())))
    with DB() as db:
        snapshot = buddy_context(db, db.get(Child, child["id"]), unit=db.get(LearningUnit, uid))
        goal = next(g for g in snapshot["goals"] if g["label"] == "Brüche addieren")
        assert goal["confidence"] == "repeated_recall"
        assert goal["successful_check_dates"] == before["successful_check_dates"]
        assert goal["review_due"] == before["review_due"]
        assert goal["independent"] == 3 and goal["reflection_tasks"] == 1
        assert goal["uncertain"] == goal["needs_practice"] == goal["supported"] == 0
        assert goal["last_difficulty"] is None
        assert goal["tasks"] == goal["attempts"] == 4
        assert db.scalar(select(func.count()).select_from(Attempt)) == 4


def test_reflection_alone_is_not_a_difficulty_or_a_reviewable_competence(profile):
    _, uid, _, _, _, child = profile
    with DB.begin() as db:
        db.add(Attempt(unit_id=uid, question_id="sum", answer="Eigener Beitrag",
            outcome="uncertain", assisted=False, evaluation={"method": "open_learning_v1"}))
    with DB() as db:
        goal = next(g for g in buddy_context(db, db.get(Child, child["id"]),
            unit=db.get(LearningUnit, uid))["goals"] if g["label"] == "Brüche addieren")
        assert goal["reflection_tasks"] == goal["tasks"] == goal["attempts"] == 1
        assert goal["uncertain"] == goal["independent"] == goal["supported"] == goal["needs_practice"] == 0
        assert goal["confidence"] == "unverified" and goal["review_due"] is None
        assert goal["last_difficulty"] is None
