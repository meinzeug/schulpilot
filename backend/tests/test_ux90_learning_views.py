"""Read-only UX90 views use synthetic evidence and preserve all ledgers."""
import time

from schulpilot.db import DB, Attempt, VocabularyItem, VocabularyReview
from sqlalchemy import select
from test_practice_progress import stored_unit
from test_vocabulary import import_words


def test_rq009_words_clamp_a_deleted_last_page_and_keep_stable_order(api, household):
    _, child = household
    import_words(api, child)
    url = f"/api/children/{child['id']}/vocabulary"
    data = api.get(url, params={"page": 99, "page_size": 2, "sort": "word"}).json()
    assert data["pagination"] == {"page": 2, "page_size": 2, "total": 3}
    item = data["items"][0]
    assert api.delete(url + "/" + item["id"], params={"revision": item["revision"]}).status_code == 200
    after = api.get(url, params={"page": 2, "page_size": 2, "sort": "word"}).json()
    assert after["pagination"]["page"] == 1 and len(after["items"]) == 2


def test_rq010_word_sort_has_real_server_order(api, household):
    _, child = household
    import_words(api, child, pairs=[{"word": "zebra", "meaning": "Affe"}, {"word": "apple", "meaning": "Zebra"}])
    url = f"/api/children/{child['id']}/vocabulary"
    by_word = api.get(url, params={"sort": "word"}).json()
    by_meaning = api.get(url, params={"sort": "meaning"}).json()
    assert [r["word"] for r in by_word["items"]] == ["apple", "zebra"]
    assert [r["word"] for r in by_meaning["items"]] == ["zebra", "apple"]
    assert by_word["filters"]["sort"] == "word"
    assert api.get(url, params={"sort": "invented"}).status_code == 422


def test_rq011_word_origin_filter_is_not_a_local_page_filter(api, household):
    _, child = household
    import_words(api, child)
    with DB.begin() as db:
        item = db.scalar(select(VocabularyItem).where(VocabularyItem.child_id == child["id"]))
        item.origin = "text"
    data = api.get(f"/api/children/{child['id']}/vocabulary", params={"origin": "text", "page_size": 1}).json()
    assert data["pagination"]["total"] == 1 and data["items"][0]["origin"] == "text"


def test_rq012_only_current_revision_clarifications_are_in_the_word_filter(api, household):
    _, child = household
    import_words(api, child)
    with DB.begin() as db:
        rows = list(db.scalars(select(VocabularyItem).where(VocabularyItem.child_id == child["id"])))
        wanted = rows[0].id
        for i, row in enumerate(rows[:2]):
            db.add(VocabularyReview(child_id=child["id"], item_id=row.id, revision=row.revision + i,
                direction="de_to_target", skill="spelling", stage=0, due="2026-10-22", needs_clarification=True))
    data = api.get(f"/api/children/{child['id']}/vocabulary", params={"clarification": True}).json()
    assert [r["id"] for r in data["items"]] == [wanted]


def test_rq013_context_search_is_literal_and_does_not_search_hidden_answers(api, household):
    _, child = household
    import_words(api, child, pairs=[{"word": "apple", "meaning": "Apfel", "context": "Box_1 is ready"},
                                  {"word": "box", "meaning": "Kiste", "context": "Boxa1 is ready"}])
    url = f"/api/children/{child['id']}/vocabulary"
    data = api.get(url, params={"search_context": True, "search": "Box_1"}).json()
    assert data["pagination"]["total"] == 1 and data["items"][0]["word"] == "apple"
    assert api.get(url, params={"search_context": True, "search": "Apfel"}).json()["items"] == []


def test_rq014_selected_language_summary_does_not_mix_languages(api, household):
    _, child = household
    import_words(api, child)
    with DB.begin() as db:
        row = db.scalar(select(VocabularyItem).where(VocabularyItem.child_id == child["id"]))
        row.target_locale = "fr-FR"
    data = api.get(f"/api/children/{child['id']}/vocabulary", params={"locale": "en-GB"}).json()
    assert data["summary"]["confirmed_words"] == 3
    assert data["locale_summary"]["confirmed_words"] == 2
    assert data["pagination"]["total"] == 2


def test_rq007_changed_word_cannot_be_deleted_from_an_old_card(api, household):
    _, child = household
    import_words(api, child)
    url = f"/api/children/{child['id']}/vocabulary"
    row = api.get(url).json()["items"][0]
    with DB.begin() as db:
        db.get(VocabularyItem, row["id"]).revision += 1
    assert api.delete(url + "/" + row["id"], params={"revision": row["revision"]}).status_code == 409
    assert api.get(url).json()["pagination"]["total"] == 3


def test_rq026_old_word_revision_cannot_be_exposed_and_records_no_help(api, household):
    from schulpilot.db import Activity
    from sqlalchemy import func
    from test_vocabulary import child_login

    _, child = household
    import_words(api, child)
    child_login(api)
    url = f"/api/children/{child['id']}/vocabulary"
    word = api.get(url).json()["items"][0]
    with DB.begin() as db:
        db.get(VocabularyItem, word["id"]).revision += 1
        before = db.scalar(select(func.count()).select_from(Activity))
    assert api.post(url + "/" + word["id"] + "/reveal", params={"revision": word["revision"]}).status_code == 409
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Activity)) == before


def test_rq032_period_uses_latest_task_observation_and_preserves_all_history(api, household):
    _, child = household
    with DB.begin() as db:
        old = stored_unit(db, child["id"], topic="Alt", outcomes=("correct",))
        stored_unit(db, child["id"], topic="Neu", outcomes=("incorrect",))
        db.flush()
        db.scalar(select(Attempt).where(Attempt.unit_id == old.id)).created = time.time() - 15 * 86400
        original_ids = list(db.scalars(select(Attempt.id)))
    url = f"/api/children/{child['id']}/learning-progress"
    week = api.get(url, params={"period": "7"}).json()
    assert week["totals"]["practiced_tasks"] == 2 and week["selected_totals"]["practiced_tasks"] == 1
    assert week["selected_totals"]["needs_practice_tasks"] == 1
    month = api.get(url, params={"period": "30"}).json()
    assert month["selected_totals"]["practiced_tasks"] == 2
    with DB() as db:
        assert list(db.scalars(select(Attempt.id))) == original_ids


def test_rq033_progress_sorts_by_actual_practice_need(api, household):
    _, child = household
    with DB.begin() as db:
        stored_unit(db, child["id"], subject="Biologie", topic="Zellen", outcomes=("correct",))
        stored_unit(db, child["id"], subject="Mathematik", topic="Brüche", outcomes=("incorrect",))
    url = f"/api/children/{child['id']}/learning-progress"
    assert [r["subject"] for r in api.get(url, params={"sort": "practice"}).json()["items"]] == ["Mathematik", "Biologie"]
    assert [r["subject"] for r in api.get(url, params={"sort": "name"}).json()["items"]] == ["Biologie", "Mathematik"]


def test_rq034_progress_searches_real_subjects_and_topics(api, household):
    _, child = household
    with DB.begin() as db:
        stored_unit(db, child["id"], subject="Biologie", topic="Wirbeltiere")
        stored_unit(db, child["id"], subject="Mathematik", topic="Brüche")
    data = api.get(f"/api/children/{child['id']}/learning-progress", params={"search": "wirbel"}).json()
    assert data["selected_totals"]["practiced_tasks"] == 1 and data["items"][0]["subject"] == "Biologie"
    assert data["totals"]["practiced_tasks"] == 2


def test_rq035_progress_separates_paused_and_completed_rounds(api, household):
    _, child = household
    with DB.begin() as db:
        stored_unit(db, child["id"], status="paused")
        stored_unit(db, child["id"], status="completed")
    data = api.get(f"/api/children/{child['id']}/learning-progress", params={"status": "paused"}).json()
    assert data["selected_totals"]["practiced_rounds"] == data["selected_totals"]["ongoing_rounds"] == 1
    assert data["totals"]["practiced_rounds"] == 2


def test_rq036_progress_separates_vocabulary_without_changing_evidence(api, household):
    _, child = household
    with DB.begin() as db:
        a = stored_unit(db, child["id"])
        a.round_kind = "vocabulary"
        stored_unit(db, child["id"])
    data = api.get(f"/api/children/{child['id']}/learning-progress", params={"round_kind": "vocabulary"}).json()
    assert data["selected_totals"]["practiced_tasks"] == 1 and data["totals"]["practiced_tasks"] == 2


def test_rq027_retained_tutor_questions_are_reauthorized_in_exact_scope(api, household):
    from schulpilot.db import Child, Material, TutorTurn, uid
    _, child = household
    with DB.begin() as db:
        owner = db.get(Child, child["id"]).user_id
        first = Material(child_id=child["id"], title="Synthetisch", subject="Mathematik", topic="Brüche", content="Ein Drittel", confirmed=True)
        second = Material(child_id=child["id"], title="Andere künstliche Quelle", subject="Biologie", topic="Zellen", content="Zelle", confirmed=True)
        db.add_all([first, second])
        db.flush()
        material_id = first.id
        wanted, other = uid(), uid()
        for i in range(22):
            db.add(TutorTurn(id=wanted if i == 0 else uid(), child_id=child["id"], user_id=owner, material_id=first.id,
                question=f"Künstliche Frage{i}", status="ready", created=1000+i, source_revisions=[{"id": first.id, "revision": 1}],
                reply={"kind": "answer", "answer": "Vorhandene künstliche Erklärung", "sources": []}))
        db.add(TutorTurn(id=other, child_id=child["id"], user_id=owner, material_id=second.id,
            question="Anderer Bereich", status="ready", source_revisions=[], reply={"kind":"answer","answer":"Nicht in diesem Bereich","sources":[]}))
    url=f"/api/children/{child['id']}/tutor/questions"
    data=api.get(url, params={"material_id": material_id,"retain": wanted+","+other}).json()
    assert len(data["questions"]) == 20
    assert [r["id"] for r in data["retained_questions"]] == [wanted]
    assert data["retained_cursor"] == wanted
    with DB.begin() as db:
        db.get(Material, material_id).revision += 1
        db.get(TutorTurn,wanted).reply={"kind":"answer","answer":"Frisch erneut berechtigte Erklärung","sources":[]}
    fresh=api.get(url,params={"material_id":material_id,"retain":wanted}).json()["retained_questions"][0]
    assert fresh["source_changed"] is True and fresh["reply"]["answer"] == "Frisch erneut berechtigte Erklärung"
    assert api.get(url,params={"material_id":material_id,"retain":"wrong-id"}).status_code == 422
    assert api.get(url,params={"material_id":material_id,"retain":",".join(uid() for _ in range(81))}).status_code == 422


def test_rq110_unit_attempt_ties_keep_the_recorded_attempt_order(api, household):
    _, child = household
    with DB.begin() as db:
        unit=stored_unit(db,child["id"],outcomes=())
        unit.questions=[{"id":"q","type":"short","prompt":"Wie viel?","answer":"45","accepted":[],"hints":[],"explanation":"Künstlich"}]
        unit_id=unit.id
        db.add(Attempt(id="f"*32,unit_id=unit.id,question_id="q",answer="40",outcome="incorrect",assisted=False,created=100,evaluation={"attempt_number":1}))
        db.add(Attempt(id="0"*32,unit_id=unit.id,question_id="q",answer="45",outcome="correct",assisted=True,created=100,evaluation={"attempt_number":2}))
    data=api.get(f"/api/units/{unit_id}").json()
    assert [a["answer"] for a in data["questions"][0]["attempts"]] == ["40","45"]


def test_rq044_numeric_keyboard_metadata_never_exposes_the_answer(api, household):
    from test_vocabulary import child_login
    _, child=household
    with DB.begin() as db:
        unit=stored_unit(db,child["id"],subject="Mathematik",outcomes=())
        unit.questions=[{"id":f"q{i}","type":"short","prompt":"Künstliche Frage","answer":v,"accepted":[],"hints":[],"explanation":"Künstlich"} for i,v in enumerate(["45","-1,5","3/8","45 cm"])]
        unit_id=unit.id
    child_login(api)
    questions=api.get(f"/api/units/{unit_id}").json()["questions"]
    assert [q.get("input_kind") for q in questions]==["number","number",None,None]
    assert all("answer" not in q and "accepted" not in q for q in questions)


def test_rq051_message_retry_keeps_one_message_and_one_event(api, household):
    from schulpilot.db import Activity, Message
    from sqlalchemy import func
    from test_vocabulary import child_login
    _, child = household
    child_login(api)
    url = f"/api/children/{child['id']}/messages"
    body = {"kind": "help", "body": "Künstlicher Hilfewunsch ohne echte Personendaten", "request_key": "ux90-message-retry-01"}
    first = api.post(url, json=body)
    second = api.post(url, json=body)
    assert first.status_code == second.status_code == 201
    assert first.json() == second.json()
    assert api.post(url, json={**body, "body": "Anderer künstlicher Inhalt"}).status_code == 409
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Message)) == 1
        assert db.scalar(select(func.count()).select_from(Activity).where(Activity.kind == "message")) == 1


def test_rq051_concurrent_parent_message_retries_are_exactly_once(api, household):
    from concurrent.futures import ThreadPoolExecutor

    from conftest import HEADERS
    from fastapi.testclient import TestClient
    from schulpilot.db import Activity, Message
    from schulpilot.main import app
    from sqlalchemy import func
    _, child = household
    auth = api.headers["Authorization"]
    def send(_):
        with TestClient(app, headers={**HEADERS, "Authorization": auth}) as client:
            r = client.post(f"/api/children/{child['id']}/messages", json={"kind": "reply", "body": "Künstliche Antwort", "request_key": "ux90-parent-message-retry"})
            return r.status_code, r.json()
    with ThreadPoolExecutor(max_workers=2) as executor:
        results = list(executor.map(send, range(2)))
    assert results[0] == results[1] and results[0][0] == 201
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Message)) == 1
        assert db.scalar(select(func.count()).select_from(Activity).where(Activity.kind == "message")) == 1


def new_collection(api, child, title="Künstliche Gruppe", locale="en-GB", key="ux90-collection-new-01"):
    response = api.post(f"/api/children/{child['id']}/vocabulary/collections", json={"title": title, "target_locale": locale}, headers={"Idempotency-Key": key})
    assert response.status_code == 201, response.text
    return response.json()


def test_rq052_collection_creation_is_idempotent_and_has_actual_empty_count(api, household):
    from schulpilot.db import VocabularyCollection
    from sqlalchemy import func
    _, child = household
    first = new_collection(api, child)
    assert first == new_collection(api, child)
    assert first["word_count"] == 0 and len(first["snapshot"]) == 64
    assert api.post(f"/api/children/{child['id']}/vocabulary/collections", json={"title": "Anders", "target_locale": "en-GB"}, headers={"Idempotency-Key": "ux90-collection-new-01"}).status_code == 409
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(VocabularyCollection)) == 1


def test_rq053_collection_rename_preserves_membership_and_rejects_lost_update(api, household):
    _, child = household
    row = new_collection(api, child)
    url = f"/api/children/{child['id']}/vocabulary/collections/{row['id']}"
    body = {"title": "Umbenannt", "expected_title": row["title"]}
    changed = api.put(url, json=body)
    assert changed.status_code == 200 and changed.json()["title"] == "Umbenannt"
    assert api.put(url, json=body).status_code == 200
    assert api.put(url, json={"title": "Überschreiben", "expected_title": row["title"]}).status_code == 409


def test_rq054_removing_a_collection_preserves_words_reviews_and_old_answers(api, household):
    from schulpilot.db import VocabularyCollection
    _, child = household
    import_words(api, child)
    url = f"/api/children/{child['id']}/vocabulary"
    before = api.get(url).json()
    row = before["collections"][0]
    assert row["word_count"] == 3
    item_id = before["items"][0]["id"]
    with DB.begin() as db:
        db.add(VocabularyReview(child_id=child["id"], item_id=item_id, revision=1, direction="de_to_target", skill="spelling", due="2026-10-22", stage=2))
        stored_unit(db, child["id"], outcomes=("correct",))
    response = api.request("DELETE", url+"/collections/"+row["id"], json={"snapshot": row["snapshot"]})
    assert response.status_code == 200, response.text
    after = api.get(url).json()
    assert after["collections"] == [] and after["pagination"]["total"] == 3
    with DB() as db:
        assert db.get(VocabularyCollection, row["id"]) is None
        assert db.scalar(select(VocabularyReview).where(VocabularyReview.item_id == item_id)).stage == 2
        assert db.scalar(select(Attempt)) is not None


def test_rq054_changed_collection_snapshot_cannot_be_removed(api, household):
    _, child = household
    row = new_collection(api, child)
    url = f"/api/children/{child['id']}/vocabulary/collections/{row['id']}"
    assert api.put(url, json={"title": "Neu", "expected_title": row["title"]}).status_code == 200
    assert api.request("DELETE", url, json={"snapshot": row["snapshot"]}).status_code == 409


def test_rq055_word_can_belong_to_multiple_collections_without_new_revision(api, household):
    _, child = household
    import_words(api, child)
    url = f"/api/children/{child['id']}/vocabulary"
    before = api.get(url).json()
    word = before["items"][0]
    group = new_collection(api, child)
    selected = [*word["collection_ids"], group["id"]]
    body = {"revision": word["revision"], "collection_ids": selected, "expected_collection_ids": word["collection_ids"]}
    change = api.put(url+"/"+word["id"]+"/collections", json=body)
    assert change.status_code == 200, change.text
    assert api.put(url+"/"+word["id"]+"/collections", json=body).status_code == 200
    after = api.get(url, params={"collection": group["id"]}).json()
    assert after["pagination"]["total"] == 1 and after["items"][0]["revision"] == word["revision"]
    assert next(c for c in after["collections"] if c["id"] == group["id"])["word_count"] == 1


def test_rq055_membership_respects_revision_and_language(api, household):
    _, child = household
    import_words(api, child)
    url = f"/api/children/{child['id']}/vocabulary"
    word = api.get(url).json()["items"][0]
    other_language = new_collection(api, child, locale="fr-FR")
    body = {"revision": word["revision"], "collection_ids": [other_language["id"]], "expected_collection_ids": word["collection_ids"]}
    assert api.put(url+"/"+word["id"]+"/collections", json=body).status_code == 422
    assert api.put(url+"/"+word["id"]+"/collections", json={**body, "revision": word["revision"]+1}).status_code == 409
    assert api.put(url+"/"+word["id"]+"/collections", json={**body, "collection_ids": ["f"*32]}).status_code == 404


def test_rq056_manual_words_can_extend_an_existing_collection(api, household):
    _, child = household
    row = new_collection(api, child)
    url = f"/api/children/{child['id']}/vocabulary"
    response = api.post(url+"/imports", json={"target_locale": "en-GB", "collection_id": row["id"], "title": row["title"], "pairs": [{"word": "apple", "meaning": "Apfel"}], "language_confirmed": True}, headers={"Idempotency-Key": "ux90-existing-group-import"})
    assert response.status_code == 201, response.text
    data = response.json()
    done = api.post(url+"/imports/"+data["id"]+"/confirm", json={"pairs": data["pairs"], "target_locale": "en-GB", "language_confirmed": True})
    assert done.status_code == 200 and done.json()["collection_id"] == row["id"]
    listing = api.get(url).json()
    assert len(listing["collections"]) == 1 and listing["collections"][0]["word_count"] == 1


def test_rq056_open_import_keeps_its_target_collection_until_review_finished(api, household):
    _, child = household
    row = new_collection(api, child)
    url = f"/api/children/{child['id']}/vocabulary"
    response = api.post(url+"/imports", json={"target_locale": "en-GB", "collection_id": row["id"], "title": row["title"], "pairs": [{"word": "apple", "meaning": "Apfel"}], "language_confirmed": True}, headers={"Idempotency-Key": "ux90-open-group-import"})
    assert response.status_code == 201
    assert api.request("DELETE", url+"/collections/"+row["id"], json={"snapshot": row["snapshot"]}).status_code == 409


def test_rq056_import_does_not_accept_another_child_or_language_collection(api, household):
    from conftest import create_child
    from schulpilot.db import VocabularyCollection
    user, child = household
    second = create_child(api, user, username="synthetic-second-child")
    with DB.begin() as db:
        private = VocabularyCollection(child_id=second["id"], title="Andere eigene Zuordnung", target_locale="en-GB")
        db.add(private)
        db.flush()
        wrong_id = private.id
    url = f"/api/children/{child['id']}/vocabulary/imports"
    body = {"target_locale": "en-GB", "collection_id": wrong_id, "title": "Test", "pairs": [{"word": "apple", "meaning": "Apfel"}], "language_confirmed": True}
    assert api.post(url, json=body, headers={"Idempotency-Key": "ux90-foreign-group-import"}).status_code == 404


def test_rq069_existing_conversation_continuation_is_a_read_only_navigation_target(api, household):
    from schulpilot.db import Child, LanguageProject
    _, child = household
    with DB.begin() as db:
        owner = db.get(Child, child["id"]).user_id
        first = LanguageProject(child_id=child["id"], user_id=owner, request_key="ux90-dialog-first", request_digest="a"*64,
            target_locale="en-GB", mode="dialog", inputs={"item_ids": [], "goal": "Künstliches Gespräch", "draft": "Mein eigener Versuch"}, status="ready", result={"response":"Künstliche Erklärung"})
        db.add(first)
        db.flush()
        second = LanguageProject(child_id=child["id"], user_id=owner, request_key="ux90-dialog-second", request_digest="b"*64,
            target_locale="en-GB", mode="dialog", inputs={"item_ids": [], "goal": "Künstliches Gespräch", "draft": "Meine Fortsetzung"}, status="ready", result={"response":"Gespeicherte Fortsetzung"}, previous_id=first.id, step=2)
        db.add(second)
        db.flush()
        first_id, second_id = first.id, second.id
    url = f"/api/children/{child['id']}/language-projects/"
    first = api.get(url+first_id).json()
    second = api.get(url+second_id).json()
    assert first["next_id"] == second_id and first["can_continue"] is False
    assert second["previous_id"] == first_id and second["can_continue"] is True


def test_rq084_collection_previews_are_bounded_and_selected_old_collection_stays_reachable(api, household):
    from schulpilot.db import VocabularyCollection
    _, child = household
    with DB.begin() as db:
        rows = [VocabularyCollection(child_id=child["id"], target_locale="en-GB", title=f"Gruppe{i:03d}", created=i) for i in range(105)]
        db.add_all(rows)
        db.flush()
        oldest = rows[0].id
    url = f"/api/children/{child['id']}/vocabulary"
    data = api.get(url, params={"locale": "en-GB"}).json()
    assert data["collections_total"] == 105 and len(data["collections"]) == 80
    selected = api.get(url, params={"locale": "en-GB", "collection": oldest}).json()
    assert oldest in {row["id"] for row in selected["collections"]} and len(selected["collections"]) == 81
    page = api.get(url+"/collections", params={"locale": "en-GB", "page": 2}).json()
    assert len(page["items"]) == 20 and page["pagination"]["total"] == 105
    assert page["items"][0]["title"] == "Gruppe020"


def test_rq085_collection_search_is_literal_and_uses_real_server_sort(api, household):
    from schulpilot.db import VocabularyCollection
    _, child = household
    with DB.begin() as db:
        for title, made in [("Z_1", 1), ("A_1", 2), ("Ax1", 3)]:
            db.add(VocabularyCollection(child_id=child["id"], target_locale="en-GB", title=title, created=made))
        db.add(VocabularyCollection(child_id=child["id"], target_locale="fr-FR", title="Z_1", created=4))
    url = f"/api/children/{child['id']}/vocabulary/collections"
    data = api.get(url, params={"locale": "en-GB", "search": "_1", "sort": "name"}).json()
    assert [r["title"] for r in data["items"]] == ["A_1", "Z_1"]
    newest = api.get(url, params={"locale": "en-GB", "sort": "newest"}).json()
    assert [r["title"] for r in newest["items"]] == ["Ax1", "A_1", "Z_1"]
    assert api.get(url, params={"sort": "invented"}).status_code == 422


def test_rq092_discard_only_open_word_proposals_preserves_existing_words(api, household):
    from schulpilot.db import VocabularyImport
    _, child = household
    import_words(api, child)
    url=f"/api/children/{child['id']}/vocabulary"
    draft=api.post(url+"/imports",json={"target_locale":"en-GB","title":"Nicht gewünschte Vorschläge","pairs":[{"word":"cat","meaning":"Katze"}],"language_confirmed":True},headers={"Idempotency-Key":"ux90-discard-open-import"}).json()
    assert draft["supports_import_discard"] is True
    assert api.delete(url+"/imports/"+draft["id"]).status_code==200
    assert api.delete(url+"/imports/"+draft["id"]).status_code==200
    assert api.get(url).json()["pagination"]["total"]==3
    with DB() as db:
        assert db.get(VocabularyImport,draft["id"]) is None


def test_rq092_confirmed_and_processing_word_imports_are_protected(api, household):
    from schulpilot.db import Child, Job, VocabularyImport
    _, child=household
    _, _, done=import_words(api,child)
    url=f"/api/children/{child['id']}/vocabulary/imports/"
    assert api.delete(url+done["id"]).status_code==409
    with DB.begin() as db:
        user=db.get(Child,child["id"]).user_id
        job=Job(child_id=child["id"],kind="vocabulary_import",status="running",idempotency="ux90-protected-word-import",payload={})
        db.add(job)
        db.flush()
        row=VocabularyImport(child_id=child["id"],user_id=user,request_key="ux90-protected-word-list",request_digest="a"*64,target_locale="en-GB",title="Laufend",status="review",job_id=job.id)
        db.add(row)
        db.flush()
        row_id=row.id
    assert api.delete(url+row_id).status_code==409


def test_rq095_all_word_imports_are_searchable_past_the_old_thirty_row_preview(api, household):
    from schulpilot.db import Child, VocabularyImport
    _, child=household
    with DB.begin() as db:
        owner=db.get(Child,child["id"]).user_id
        for i in range(35):
            db.add(VocabularyImport(child_id=child["id"],user_id=owner,request_key=f"ux90-import-{i}",request_digest="a"*64,target_locale="en-GB",title=f"Liste{i:02d}",created=i,status="review" if i==0 else "confirmed",pairs=[{"word":"cat","meaning":"Katze"}]))
    url=f"/api/children/{child['id']}/vocabulary/imports"
    latest=api.get(url).json()
    assert len(latest["imports"])==30 and latest["open_total"]==1
    open_=api.get(url,params={"status":"open","page_size":20}).json()
    assert open_["pagination"]["total"]==1 and open_["imports"][0]["title"]=="Liste00"
    second=api.get(url,params={"status":"confirmed","page":2,"page_size":20}).json()
    assert len(second["imports"])==14 and second["pagination"]["total"]==34
    search=api.get(url,params={"search":"Liste00"}).json()
    assert search["pagination"]["total"]==1 and search["imports"][0]["status"]=="review"
    assert api.get(url,params={"status":"invented"}).status_code==422


def test_rq096_missing_job_is_visible_in_the_actual_failed_import_view(api, household):
    from schulpilot.db import Child, VocabularyImport
    _, child=household
    with DB.begin() as db:
        user=db.get(Child,child["id"]).user_id
        db.add(VocabularyImport(child_id=child["id"],user_id=user,request_key="ux90-missing-job-import",request_digest="a"*64,target_locale="en-GB",title="Unterbrochener künstlicher Import",status="queued"))
    data=api.get(f"/api/children/{child['id']}/vocabulary/imports",params={"status":"failed"}).json()
    assert data["pagination"]["total"]==1 and data["imports"][0]["status"]=="failed"


def test_rq098_import_metadata_preview_omits_pairs_until_explicit_detail_read(api, household):
    _, child=household
    _,_,done=import_words(api,child)
    url=f"/api/children/{child['id']}/vocabulary/imports"
    preview=api.get(url,params={"compact":True}).json()
    assert preview["compact"] is True and "pairs" not in preview["imports"][0]
    assert preview["imports"][0]["pair_count"]==3
    detail=api.get(url+"/"+done["id"]).json()
    assert len(detail["pairs"])==3
    assert len(api.get(url).json()["imports"][0]["pairs"])==3
