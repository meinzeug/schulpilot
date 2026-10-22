"""Offline citation replay and fake-provider persistence, never a live AI call."""

import copy

import pytest
from schulpilot.db import DB, Job, SchulbuddyTurn, Usage
from schulpilot.providers import ProviderError
from schulpilot.schulbuddy import checked_display_text, checked_reply
from sqlalchemy import select
from test_schulbuddy import ask, counts, finish
from test_schulbuddy import book as book_fixture
from test_schulbuddy import transport as transport_fixture

SOURCE = "Der Nenner steht unter dem Bruchstrich und nennt die Anzahl gleich großer Teile."
PAYLOAD = {"sources": [{"ref": "p1", "content": SOURCE}, {"ref": "p2", "content": "Ein zweiter Beleg."}]}
REFS = [{"ref": "p1", "id": "1" * 32, "revision": 2, "label": "Künstliches Testblatt"},
        {"ref": "p2", "id": "2" * 32, "revision": 1, "label": "Zweites künstliches Testblatt"}]
TOKEN = "\ue200cite\ue202p1\ue201"


def reply(answer="Ein Schritt."):
    return {"answer": answer, "next_question": None, "starters": [], "sources": [{"ref": "p1", "quote": SOURCE}]}


def test_captured_synthetic_luna_high_probe_replays_offline_without_visible_provider_marker():
    # Exact artificial reply captured by the operator's one live probe. Keeping
    # it here makes the regression independent of private/ignored log files.
    text = "Der Nenner steht unter dem Bruchstrich. Er sagt, in wie viele gleich große Teile das Ganze geteilt ist. "
    value = reply(text + TOKEN)
    before = copy.deepcopy(value)
    checked = checked_reply(value, PAYLOAD, REFS)
    assert checked["answer"] == text  # No rewriting, even the trailing space stays.
    assert checked["sources"] == [{"ref": "p1", "quote": SOURCE, "material_id": "1" * 32,
                                   "label": "Künstliches Testblatt"}]
    assert value == before and checked["next_question"] is None and checked["starters"] == []


def test_multi_reference_marker_requires_each_of_its_structured_verified_quotes():
    value = reply("Vorher.\ue200cite\ue202p1\ue202p2\ue201\nNachher.")
    value["sources"].append({"ref": "p2", "quote": "Ein zweiter Beleg."})
    checked = checked_reply(value, PAYLOAD, REFS)
    assert checked["answer"] == "Vorher.\nNachher." and len(checked["sources"]) == 2


@pytest.mark.parametrize("field", ["answer", "next_question", "starters"])
def test_only_verified_markers_are_removed_from_each_visible_generated_text_field(field):
    value = reply()
    text = "  Erkläre \\(\\frac{1}{4}\\).\n    code = 1\n" + TOKEN + "Weiter?"
    value[field] = [text] if field == "starters" else text
    checked = checked_reply(value, PAYLOAD, REFS)
    # The existing Strict schema already trims leading/trailing whitespace;
    # token removal must add no other normalization to that prior contract.
    expected = text.strip().replace(TOKEN, "")
    assert checked[field] == ([expected] if field == "starters" else expected)
    assert checked_display_text(text, {"p1"}) == text.replace(TOKEN, "")


@pytest.mark.parametrize("field", ["answer", "next_question", "starters"])
@pytest.mark.parametrize("marker", [
    "\ue200cite\ue202p9\ue201",  # not an authorized source
    "\ue200cite\ue202p2\ue201",  # authorized source, but no checked chip
    "\ue200cite\ue202p1",  # missing end delimiter
    "\ue200citep1\ue201",  # missing separator
    "\ue200cite\ue202\ue201",  # empty ref
    "\ue200image\ue202p1\ue201",  # unknown provider token
    "\ue202p1\ue201",  # detached suffix
    "\ue200cite\ue202p1\ue202p9\ue201",  # mixed known/unknown
])
def test_unknown_or_malformed_provider_marker_is_controlled_rejection_in_every_visible_field(field, marker):
    value = reply()
    value[field] = ["Text " + marker] if field == "starters" else "Text " + marker
    with pytest.raises(ProviderError) as error:
        checked_reply(value, PAYLOAD, REFS)
    assert marker not in str(error.value) and "Keine Antwort übernommen" in str(error.value)


def test_a_payload_reference_without_a_validated_structured_chip_is_not_a_license_to_strip():
    value = reply("Erklärung " + TOKEN)
    value["sources"] = []
    with pytest.raises(ProviderError):
        checked_reply(value, PAYLOAD, REFS)


@pytest.mark.parametrize("value", [TOKEN, " \n" + TOKEN])
def test_marker_only_reply_is_rejected_instead_of_saving_a_blank_answer(value):
    with pytest.raises(ProviderError):
        checked_reply(reply(value), PAYLOAD, REFS)


def test_invalid_quote_missing_metadata_and_duplicate_quotes_keep_the_original_strictness():
    value = reply("Erklärung " + TOKEN)
    value["sources"][0]["quote"] = "Unbelegte Behauptung"
    with pytest.raises(ProviderError):
        checked_reply(value, PAYLOAD, REFS)
    with pytest.raises(ProviderError):
        checked_reply(reply("Erklärung " + TOKEN), PAYLOAD, [])
    value = reply("Erklärung " + TOKEN)
    value["sources"] *= 2
    with pytest.raises(ProviderError):
        checked_reply(value, PAYLOAD, REFS)


def test_literal_quote_and_other_factual_text_are_never_rewritten():
    quote = "Ein Quelltext mit " + TOKEN + " als wörtlichem Zeichenbeispiel."
    value = reply("p1, [p1], <cite>, 1/4 und \\(x^2\\) bleiben wörtlich.")
    value["sources"][0]["quote"] = quote
    checked = checked_reply(value, {"sources": [{"ref": "p1", "content": quote}]}, REFS)
    assert checked["answer"] == value["answer"] and checked["sources"][0]["quote"] == quote


@pytest.fixture
def book(api, household, monkeypatch):
    yield from book_fixture.__wrapped__(api, household, monkeypatch)


@pytest.fixture
def transport(monkeypatch):
    return transport_fixture.__wrapped__(monkeypatch)


def test_normal_job_stores_clean_display_text_and_unchanged_checked_source_chips_once(api, book, transport):
    transport["output"]["answer"] = "Die Sonne ist ein Stern. " + TOKEN
    submitted = ask(book)
    assert submitted.status_code == 202
    finish()
    value = book["client"].get("/api/schulbuddy/questions/" + submitted.json()["id"]).json()
    assert value["status"] == "ready" and value["answer"] == "Die Sonne ist ein Stern. "
    assert value["sources"][0]["quote"] == "Die Sonne ist ein Stern."
    assert value["sources"][0]["material_id"] == book["material_id"]
    assert len(transport["calls"]) == 1 and counts() == (1, 1, 0, 0)


def test_invalid_marker_keeps_unknown_account_reservation_without_saved_reply_or_hidden_retry(api, book, transport):
    transport["output"]["answer"] = "Die Sonne. \ue200cite\ue202foreign\ue201"
    submitted = ask(book)
    assert submitted.status_code == 202
    finish()
    with DB() as db:
        turn = db.get(SchulbuddyTurn, submitted.json()["id"])
        assert turn.status == "failed" and not turn.reply
        assert db.get(Job, turn.job_id).status == "failed"
        usage = db.scalar(select(Usage).where(Usage.job_id == turn.job_id))
        assert usage.status == "failed_unknown" and usage.cost_micros is None and usage.reserved_micros > 0
    assert len(transport["calls"]) == 1 and counts() == (1, 1, 0, 0)
