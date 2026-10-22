"""Actual page inventories use artificial records and never run a provider."""

import json

import pytest
from conftest import create_child, register
from fastapi import HTTPException
from schulpilot.db import (
    DB,
    Activity,
    Assignment,
    Attempt,
    Child,
    Job,
    LearningUnit,
    Material,
    Membership,
    Session,
    Usage,
    User,
    VocabularyItem,
    engine,
)
from schulpilot.schulbuddy_pages import MAX_CHARS, page_context
from schulpilot.security import Principal
from sqlalchemy import event, func, select


def principal(db, user_id):
    # The API authenticates the real session before resolve/page_context. These
    # helper tests exercise only the subsequent existing family authorization.
    return Principal(db.get(User, user_id), Session(user_id=user_id))


def project(household, page):
    parent, child = household
    with DB() as db:
        result = page_context(db, principal(db, parent["id"]), db.get(Child, child["id"]), page)
        assert not db.new and not db.dirty and not db.deleted
        return result


@pytest.fixture
def inventory(household):
    _, child = household
    with DB.begin() as db:
        for i in range(7):
            db.add(Material(child_id=child["id"], title=f"Bestätigtes Heft {i}", subject="Biologie",
                topic=f"Pflanzenteile {i}", content="PRIVATE_CONFIRMED_OCR", confirmed=True,
                revision=i+1, status="confirmed", purpose="notebook", created=100+i))
            db.add(LearningUnit(child_id=child["id"], subject="Mathematik", topic=f"Brüche {i}",
                explanation="PRIVATE_EXPLANATION", questions=[{"prompt": "PRIVATE_PROMPT", "answer": "PRIVATE_SOLUTION"}],
                status="completed" if i == 0 else "active", round_kind="learning", goal_revision=i+1,
                provider="synthetic", created=100+i))
            db.add(Assignment(child_id=child["id"], subject="Mathematik", topic=f"Elternthema {i}",
                note="PRIVATE_PARENT_NOTE", kind="parent", revision=i+1, done=i == 0, mandatory=i != 1,
                due=f"2026-11-{i+1:02}", scheduled_for=f"2026-10-{i+1:02}", created=100+i))
        for i in range(3):
            db.add(Material(child_id=child["id"], title=f"Hausaufgabe {i}", subject="Deutsch",
                topic="Wortarten", content="PRIVATE_HOMEWORK_OCR", homework_state={"drafts": {"q": "PRIVATE_DRAFT"}},
                confirmed=True, status="confirmed", purpose="homework", created=200+i))
        db.add(Material(child_id=child["id"], title="PRIVATE_UNCONFIRMED_TITLE", subject="PRIVATE_SUBJECT",
            topic="PRIVATE_UNCONFIRMED_TOPIC", content="PRIVATE_UNCONFIRMED_OCR", confirmed=False,
            status="recognized", purpose="notebook", created=999))
        for i in range(15):
            db.add(VocabularyItem(child_id=child["id"], identity=str(i), target_locale="en-GB", word=f"word {i}",
                meaning=f"Bedeutung {i}", revision=i+1, confirmed=True, origin="manual", context="PRIVATE_WORD_CONTEXT",
                history=[{"value": "PRIVATE_WORD_HISTORY"}], created=100+i))
        db.add(VocabularyItem(child_id=child["id"], identity="unconfirmed", target_locale="fr-FR",
            word="PRIVATE_UNCONFIRMED_WORD", meaning="PRIVATE_UNCONFIRMED_MEANING", confirmed=False, origin="manual"))
        db.add(VocabularyItem(child_id=child["id"], identity="incomplete", target_locale="fr-FR",
            word="PRIVATE_INCOMPLETE_WORD", meaning="", confirmed=True, origin="manual"))
    return household


def test_learn_inventory_has_own_actual_rounds_and_no_question_or_answer_keys(inventory):
    result = project(inventory, "learn")
    section = result["rounds"]
    assert (section["total"], section["completed"], section["unfinished"]) == (7, 1, 6)
    assert len(section["items"]) == 5 and section["has_more"]
    assert [r["topic"] for r in section["items"]] == [f"Brüche {i}" for i in range(6, 1, -1)]
    assert section["items"][0]["goal_revision"] == 7 and result["is_excerpt"]
    assert "PRIVATE_" not in json.dumps(result)
    assert set(result) == {"version", "page", "is_excerpt", "notice", "rounds"}


@pytest.mark.parametrize("page,key,total", [("notebooks", "notebooks", 8), ("homework", "homework", 3)])
def test_material_inventory_counts_unconfirmed_but_shows_only_confirmed_metadata(inventory, page, key, total):
    section = project(inventory, page)[key]
    assert section["total"] == total
    assert section["unconfirmed"] == (1 if page == "notebooks" else 0)
    assert len(section["items"]) == min(5, section["confirmed"])
    assert "PRIVATE_" not in json.dumps(section)
    assert all(set(r) == {"id", "subject", "topic", "title", "revision", "status", "created"} for r in section["items"])


def test_words_inventory_has_only_complete_confirmed_pairs_with_exact_locale_and_revision(inventory):
    section = project(inventory, "words")["words"]
    assert (section["total"], section["confirmed_pairs"]) == (17, 15)
    assert len(section["items"]) == 12 and section["has_more"]
    assert section["items"][0]["word"] == "word 14" and section["items"][0]["meaning"] == "Bedeutung 14"
    assert section["items"][0]["target_locale"] == "en-GB" and section["items"][0]["revision"] == 15
    assert "PRIVATE_" not in json.dumps(section)


def test_plan_inventory_preserves_real_obligation_dates_and_saved_status_without_parent_notes(inventory):
    section = project(inventory, "plan")["assignments"]
    assert (section["total"], section["open"], section["completed"]) == (7, 6, 1)
    first = section["items"][0]
    assert first["topic"] == "Elternthema 2" and first["mandatory"] and not first["done"]
    assert (first["due"], first["scheduled_for"], first["revision"], first["source_status"]) == (
        "2026-11-03", "2026-10-03", 3, "confirmed")
    assert "PRIVATE_" not in json.dumps(section)


def test_today_inventory_is_explicitly_a_bounded_collection_excerpt_not_a_claim_of_today_only(inventory):
    value = project(inventory, "today")
    assert set(value) == {"version", "page", "is_excerpt", "notice", "rounds", "assignments", "notebooks"}
    assert all(value[key]["total"] == expected for key, expected in [("rounds", 7), ("assignments", 7), ("notebooks", 8)])
    assert len(json.dumps(value, ensure_ascii=False, separators=(",", ":"))) <= MAX_CHARS
    assert all(len(value[key]["items"]) <= 5 for key in ("rounds", "assignments", "notebooks"))


def test_large_text_retains_exact_pairs_and_hard_caps_the_whole_serialized_payload(inventory):
    with DB.begin() as db:
        for word in db.scalars(select(VocabularyItem)):
            if word.confirmed and word.meaning:
                word.word, word.meaning = "ä" * 200, "ß" * 200
    result = project(inventory, "words")
    section = result["words"]
    assert 0 < len(section["items"]) < 12 and section["confirmed_pairs"] == 15 and section["has_more"]
    assert all(row["word"] == "ä" * 200 and row["meaning"] == "ß" * 200 for row in section["items"])
    assert len(json.dumps(result, ensure_ascii=False, separators=(",", ":"))) <= MAX_CHARS


@pytest.mark.parametrize("page", ["account", "settings", "admin", "messages", "general", "progress"])
def test_other_page_kinds_do_not_query_or_return_learning_inventory(inventory, page):
    statements = []

    def record(*args):
        statements.append(args[2])

    with DB() as db:
        p, child = principal(db, inventory[0]["id"]), db.get(Child, inventory[1]["id"])
        event.listen(engine, "before_cursor_execute", record)
        try:
            assert page_context(db, p, child, page) == {}
        finally:
            event.remove(engine, "before_cursor_execute", record)
    assert statements == []


def test_projection_is_read_only_and_never_even_selects_private_content_columns(inventory):
    statements = []

    def record(*args):
        statements.append(args[2])

    with DB() as db:
        p, child = principal(db, inventory[0]["id"]), db.get(Child, inventory[1]["id"])
        before = [db.scalar(select(func.count()).select_from(model)) for model in (Job, Usage, Attempt, Activity)]
        event.listen(engine, "before_cursor_execute", record)
        try:
            for page in ("today", "learn", "words", "homework", "notebooks", "plan"):
                assert page_context(db, p, child, page)
        finally:
            event.remove(engine, "before_cursor_execute", record)
        assert not db.new and not db.dirty
        after = [db.scalar(select(func.count()).select_from(model)) for model in (Job, Usage, Attempt, Activity)]
        assert before == after == [0, 0, 0, 0]
    sql = "\n".join(statements).lower()
    assert not any(word in sql for word in ("insert ", "update ", "delete ", "for update"))
    assert not any(column in sql for column in (".questions", ".explanation", ".content", ".note", ".homework_state", ".history", ".context"))


def test_same_family_sibling_inventory_is_not_merged_and_child_cannot_choose_sibling(api, inventory):
    parent, child = inventory
    sibling = create_child(api, parent, username="synthetic-sibling")
    with DB.begin() as db:
        db.add(Assignment(child_id=sibling["id"], subject="Physik", topic="PRIVATE_SIBLING_TOPIC", kind="exam"))
    assert "PRIVATE_SIBLING_TOPIC" not in json.dumps(project(inventory, "plan"))
    with DB() as db:
        p = principal(db, db.get(Child, child["id"]).user_id)
        assert page_context(db, p, db.get(Child, child["id"]), "plan")["assignments"]["total"] == 7
        with pytest.raises(HTTPException) as error:
            page_context(db, p, db.get(Child, sibling["id"]), "plan")
        assert error.value.status_code == 404 and not db.new


def test_foreign_parent_and_removed_membership_are_denied_but_view_member_can_read(api, mailbox, inventory):
    parent, child = inventory
    outsider = register(api, mailbox, email="outside-inventory@example.org")
    with DB.begin() as db:
        member = db.scalar(select(Membership).where(Membership.user_id == parent["id"]))
        member.permission = "view"
    assert project(inventory, "plan")["assignments"]["total"] == 7
    with DB() as db:
        with pytest.raises(HTTPException) as error:
            page_context(db, principal(db, outsider["id"]), db.get(Child, child["id"]), "words")
        assert error.value.status_code == 404
    with DB.begin() as db:
        db.delete(db.scalar(select(Membership).where(Membership.user_id == parent["id"])))
    with pytest.raises(HTTPException) as error:
        project(inventory, "words")
    assert error.value.status_code == 404


def test_revision_and_status_changes_are_visible_in_exact_hashable_projection(inventory):
    before = {page: project(inventory, page) for page in ("words", "plan", "learn", "notebooks")}
    with DB.begin() as db:
        db.scalar(select(VocabularyItem).where(VocabularyItem.confirmed.is_(True), VocabularyItem.meaning != "").order_by(
            VocabularyItem.created.desc(), VocabularyItem.id)).revision += 1
        task = db.scalar(select(Assignment).where(Assignment.topic == "Elternthema 2"))
        task.source_status, task.revision, task.due = "needs_review", task.revision+1, "2026-11-04"
        db.scalar(select(LearningUnit).order_by(LearningUnit.created.desc(), LearningUnit.id)).status = "paused"
        db.scalar(select(Material).where(Material.confirmed.is_(True), Material.purpose == "notebook").order_by(
            Material.created.desc(), Material.id)).revision += 1
    assert all(project(inventory, page) != value for page, value in before.items())


def test_empty_inventory_is_honest_and_contains_no_invented_topics(household):
    for page, key in [("learn", "rounds"), ("notebooks", "notebooks"), ("homework", "homework"), ("words", "words"), ("plan", "assignments")]:
        value = project(household, page)[key]
        assert value["total"] == 0 and value["items"] == [] and value["has_more"] is False


def test_operator_and_missing_child_have_no_learning_inventory_even_on_learning_page(household):
    with DB() as db:
        assert page_context(db, Principal(User(role="admin"), None), db.get(Child, household[1]["id"]), "learn") == {}
        assert page_context(db, principal(db, household[0]["id"]), None, "learn") == {}
        assert not db.new and not db.dirty
