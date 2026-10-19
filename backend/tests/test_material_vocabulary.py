from concurrent.futures import ThreadPoolExecutor

import pytest
from conftest import register
from fastapi.testclient import TestClient
from schulpilot.db import (
    DB,
    Activity,
    Child,
    Job,
    Material,
    Membership,
    Usage,
    User,
    VocabularyCollection,
    VocabularyImport,
    VocabularyItem,
)
from schulpilot.families import export_child
from schulpilot.main import app
from schulpilot.material_vocabulary import preview
from schulpilot.security import password_hash
from sqlalchemy import func, select


@pytest.mark.parametrize("text,expected", [
    ("apple = Apfel\nschool = Schule", [("apple", "Apfel"), ("school", "Schule")]),
    ("English\tDeutsch\napple\tApfel\nbook\tBuch", [("apple", "Apfel"), ("book", "Buch")]),
    ("| Deutsch | Englisch |\n|---|---|\n| Hund | dog |\n| Buch | book |", [("dog", "Hund"), ("book", "Buch")]),
    ("1. apple – Apfel\n2. school — Schule", [("apple", "Apfel"), ("school", "Schule")]),
    ("apple: Apfel\nbook: Buch", [("apple", "Apfel"), ("book", "Buch")]),
])
def test_literal_pairs_preserve_layout_and_direction(text, expected):
    result = preview("Englisch", "Vokabeln", text)
    assert [(pair["word"], pair["meaning"]) for pair in result["pairs"]] == expected


def source(child, content="apple = Apfel\nschool = Schule\nbank = Bank\nlamp = Lampe"):
    with DB() as db:
        item = Material(child_id=child["id"], title="Eigene künstliche Vokabelseite", status="review", subject="Englisch",
                        topic="Vokabeln", content=content, path="artificial-page.jpg", uncertainties=[], homework=[], synthetic=False)
        db.add(item)
        db.commit()
        return item.id, item.revision


def counts():
    with DB() as db:
        return tuple(db.scalar(select(func.count()).select_from(model)) for model in
                     (VocabularyItem, VocabularyImport, VocabularyCollection, Job, Usage, Activity))


def confirm_payload(content, revision):
    return {"subject": "Englisch", "topic": "Vokabeln", "content": content, "homework": [],
            "uncertainties_resolved": True, "revision": revision,
            "vocabulary": {"target_locale": "en-GB", "language_confirmed": True, "revision": revision,
                "selections": [{**{k: pair.get(k, "") for k in ("key", "word", "meaning", "context", "part_of_speech")},
                                "confirmed": True} for pair in preview("Englisch", "Vokabeln", content)["pairs"]
                               if not pair["uncertainty"]]}}


def test_photo_confirmation_saves_words_and_open_meaning_in_one_transaction(api, household):
    _, child = household
    content = "apple = Apfel\nschool = Schule\nbank = Bank\nlamp = Lampe"
    material, revision = source(child, content)
    before = counts()
    for _ in range(3):
        data = api.get(f"/api/materials/{material}").json()
        assert len(data["vocabulary_preview"]["pairs"]) == 4 and data["revision"] == revision
        assert api.get(f"/api/materials/{material}/vocabulary").json()["confirmed_words"] == 0
    assert counts() == before  # GET never imports, schedules, reserves or records progress.
    body = confirm_payload(content, revision)
    response = api.put(f"/api/materials/{material}/confirm", json=body)
    assert response.status_code == 200, response.text
    result = response.json()
    assert result["vocabulary_transfer"]["confirmed_words"] == 3
    assert result["vocabulary_transfer"]["review_words"] == 0  # Unselected ambiguity stays on the source, never becomes a word.
    with DB() as db:
        words = list(db.scalars(select(VocabularyItem).where(VocabularyItem.child_id == child["id"])))
        assert {word.word for word in words} == {"apple", "school", "lamp"}
        assert all(word.confirmed and word.origin == "material" and word.target_locale == "en-GB" for word in words)
        assert all(word.source_revisions == [{"id": material, "revision": revision + 1}] for word in words)
    saved_counts = counts()
    assert saved_counts[3:5] == before[3:5]  # No extra AI job or usage.
    repeated = api.put(f"/api/materials/{material}/confirm", json=body)
    assert repeated.status_code == 200 and repeated.json()["revision"] == revision + 1
    assert counts() == saved_counts
    again = api.post(f"/api/materials/{material}/vocabulary", json={
        "target_locale": "en-GB", "language_confirmed": True, "revision": revision + 1})
    assert again.status_code == 200 and counts() == saved_counts
    overview = api.get(f"/api/children/{child['id']}/vocabulary?locale=en-GB").json()
    assert overview["summary"]["confirmed_words"] == 3
    assert all(skill["practiced_words"] == 0 for skill in overview["summary"]["skills"])


def test_child_can_transfer_checked_source_but_other_family_and_admin_cannot(api, household, mailbox):
    _, child = household
    material, revision = source(child, "apple = Apfel\nbook = Buch")
    assert api.put(f"/api/materials/{material}/confirm", json=confirm_payload("apple = Apfel\nbook = Buch", revision)).status_code == 200
    login = api.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"}).json()
    api.headers["Authorization"] = "Bearer " + login["token"]
    assert api.get(f"/api/materials/{material}/vocabulary").json()["confirmed_words"] == 2
    data = {"target_locale": "en-GB", "language_confirmed": True, "revision": revision + 1}
    assert api.post(f"/api/materials/{material}/vocabulary", json=data).status_code == 200
    assert api.put(f"/api/materials/{material}/confirm", json=confirm_payload("apple = Apfel\nbook = Buch", revision)).status_code == 200
    api.post("/api/auth/logout")
    assert api.post(f"/api/materials/{material}/vocabulary", json=data).status_code == 401
    api.headers.pop("Authorization", None)
    register(api, mailbox, "other-vocabulary@example.org")
    assert api.get(f"/api/materials/{material}/vocabulary").status_code in (403, 404)
    assert api.post(f"/api/materials/{material}/vocabulary", json=data).status_code in (403, 404)
    with DB() as db:
        db.add(User(username="word-test-admin", role="admin", display_name="Betrieb", verified=True,
                    password_hash=password_hash("secure-admin-pass-123")))
        db.commit()
    admin = api.post("/api/auth/login", json={"username": "word-test-admin", "password": "secure-admin-pass-123"}).json()
    api.headers["Authorization"] = "Bearer " + admin["token"]
    assert api.get(f"/api/materials/{material}/vocabulary").status_code == 403
    assert api.post(f"/api/materials/{material}/vocabulary", json=data).status_code == 403


def test_old_client_confirmation_and_later_takeover_missing_translation_and_revision(api, household):
    _, child = household
    content = "apple = Apfel\nbook = Buch\nfriend ="
    material, revision = source(child, content)
    body = confirm_payload(content, revision)
    body.pop("vocabulary")
    body.pop("revision")
    assert api.put(f"/api/materials/{material}/confirm", json=body).status_code == 200
    assert counts()[0] == 0
    data = {"target_locale": "en-US", "language_confirmed": True, "revision": revision + 1}
    assert api.post(f"/api/materials/{material}/vocabulary", json={**data, "revision": revision}).status_code == 409
    assert api.post(f"/api/materials/{material}/vocabulary", json={**data, "target_locale": "fr-FR"}).status_code == 422
    result = api.post(f"/api/materials/{material}/vocabulary", json=data)
    assert result.status_code == 200, result.text
    assert result.json()["confirmed_words"] == 0 and result.json()["review_words"] == 3
    selected = confirm_payload(content, revision)["vocabulary"]["selections"]
    checked = api.post(f"/api/materials/{material}/vocabulary", json={**data, "selections": selected})
    assert checked.status_code == 200 and checked.json()["confirmed_words"] == 2
    pending = next(row for row in result.json()["imports"] if row["status"] == "review")
    assert any(not pair["meaning"] and pair["uncertainty"] for pair in pending["pairs"])


def test_large_checked_page_is_batched_without_losing_words(api, household):
    _, child = household
    content = "\n".join(f"word{i} = Bedeutung{i}" for i in range(105))
    material, revision = source(child, content)
    result = api.put(f"/api/materials/{material}/confirm", json=confirm_payload(content, revision))
    assert result.status_code == 200, result.text
    assert result.json()["vocabulary_transfer"]["confirmed_words"] == 105
    assert counts()[:3] == (105, 2, 2)


def test_non_language_and_unsupported_or_unconfirmed_locale_do_not_import(api, household):
    _, child = household
    assert preview("Mathematik", "Geometrie", "a = Fläche\nb = Breite") is None
    material, revision = source(child)
    body = confirm_payload("apple = Apfel\nschool = Schule", revision)
    body["vocabulary"]["language_confirmed"] = False
    assert api.put(f"/api/materials/{material}/confirm", json=body).status_code == 422
    assert counts()[0] == 0


def test_extra_table_columns_require_explicit_headers_and_preserve_their_meaning():
    proposal = preview("Englisch", "Vokabeln", "| Word | Wortart | Deutsch | Kontext |\n"
                       "| bank | noun | Bank | a place to save money |\n| dog | noun | Hund | a pet |")
    assert proposal["pairs"][0]["meaning"] == "Bank"
    assert proposal["pairs"][0]["part_of_speech"] == "noun"
    assert proposal["pairs"][0]["context"] == "a place to save money"
    assert not proposal["pairs"][0]["uncertainty"]
    reversed_table = preview("Englisch", "Vokabeln", "Deutsch | Kontext | Englisch\nHund | Haustier | dog\nBuch | Schule | book")
    assert [(p["word"], p["meaning"]) for p in reversed_table["pairs"]] == [("dog", "Hund"), ("book", "Buch")]
    # Unknown phonetics/POS columns must not become the German meaning.
    assert preview("Englisch", "Vokabeln", "dog | dawg | Hund\nbook | buk | Buch") is None
    single = preview("Englisch", "Unit 1", "English | Deutsch\ndog | Hund")
    assert len(single["pairs"]) == 1
    assert preview(None, None, None) is None


def test_mixed_vocabulary_and_grammar_page_never_turns_a_rule_into_a_word_pair():
    result = preview("Englisch", "Meine Vokabelseite", "apple = Apfel\nschool = Schule\ndog = Hund\nbook = Buch\nfriend = Freund\n"
                     "Simple Present\nhe, she, it: -s am Verb\nHe goes to school.\nI go to school.")
    assert len(result["pairs"]) == 5
    assert {p["word"] for p in result["pairs"]} == {"apple", "school", "dog", "book", "friend"}
    assert result["unpaired_lines"] == 4
    second_section = preview("Englisch", "Vokabeln", "apple = Apfel\nGrammar\nPresent: etwas anderes\n"
                             "Vocabulary\nbook = Buch")
    assert [(p["word"], p["meaning"]) for p in second_section["pairs"]] == [("apple", "Apfel"), ("book", "Buch")]


def test_edited_pair_preview_is_stateless_and_view_parent_cannot_commit(api, household):
    _, child = household
    material, revision = source(child)
    before = counts()
    for _ in range(2):
        response = api.post(f"/api/materials/{material}/vocabulary-preview", json={
            "subject": "Englisch", "topic": "Vokabeln", "content": "dog = Hund\nbook = Buch\nZusatznotiz"})
        assert response.status_code == 200
        assert len(response.json()["preview"]["pairs"]) == 2
        assert response.json()["preview"]["unpaired_lines"] == 1
    with DB.begin() as db:
        assert db.get(Material, material).revision == revision
        db.scalar(select(Membership)).permission = "view"
    assert counts() == before
    assert api.get(f"/api/materials/{material}/vocabulary").status_code == 200
    assert api.post(f"/api/materials/{material}/vocabulary", json={
        "target_locale": "en-GB", "language_confirmed": True, "revision": revision}).status_code == 403
    assert api.put(f"/api/materials/{material}/confirm", json=confirm_payload("dog = Hund\nbook = Buch", revision)).status_code == 403
    assert counts() == before


def test_parallel_photo_confirmation_and_takeover_are_exactly_once(api, household):
    _, child = household
    content = "apple = Apfel\nbook = Buch"
    material, revision = source(child, content)
    headers = dict(api.headers)

    def confirm(_):
        with TestClient(app, headers=headers) as other:
            return other.put(f"/api/materials/{material}/confirm", json=confirm_payload(content, revision))

    with ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(confirm, range(4)))
    assert {r.status_code for r in results} == {200}, [r.text for r in results]
    assert counts()[:3] == (2, 1, 1)

    def transfer(_):
        with TestClient(app, headers=headers) as other:
            return other.post(f"/api/materials/{material}/vocabulary", json={
                "target_locale": "en-GB", "language_confirmed": True, "revision": revision + 1})

    before = counts()
    with ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(transfer, range(4)))
    assert {r.status_code for r in results} == {200}, [r.text for r in results]
    assert counts() == before
    with DB() as db:
        assert db.get(Material, material).revision == revision + 1


def test_source_revision_rebind_export_and_erasure_keep_the_word_history(api, household):
    _, child = household
    content = "apple = Apfel\nbook = Buch"
    material, revision = source(child, content)
    assert api.put(f"/api/materials/{material}/confirm", json=confirm_payload(content, revision)).status_code == 200
    with DB() as db:
        original_ids = set(db.scalars(select(VocabularyItem.id)))
    # A new source revision reuses identity, but never overwrites its earlier snapshot.
    assert api.put(f"/api/materials/{material}/confirm", json=confirm_payload(content, revision + 1)).status_code == 200
    with DB() as db:
        words = list(db.scalars(select(VocabularyItem)))
        assert {w.id for w in words} == original_ids
        assert all(w.revision == 2 and len(w.history) == 1 for w in words)
        assert all(w.source_revisions == [{"id": material, "revision": revision + 2}] for w in words)
        exported = export_child(db, db.get(Child, child["id"]))
        assert len(exported["vocabulary_items"]) == 2
        assert len(exported["vocabulary_imports"]) == 2
    assert api.post(f"/api/materials/{material}/vocabulary", json={
        "target_locale": "en-GB", "language_confirmed": True, "revision": revision + 1}).status_code == 409
    assert api.delete(f"/api/materials/{material}").status_code == 200
    assert counts()[0:2] == (0, 0)
    assert api.get(f"/api/children/{child['id']}/vocabulary").json()["pagination"]["total"] == 0
