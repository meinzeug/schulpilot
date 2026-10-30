"""Literal OCR transport and durable processing, with artificial local pages."""

import base64
import io
import json

import httpx
import pytest
from PIL import Image, ImageDraw, ImageFont
from pydantic import ValidationError
from schulpilot import providers, worker
from schulpilot.config import settings
from schulpilot.db import DB, Material, ProviderConfig, Usage
from schulpilot.extraction import (
    IncompleteTranscription,
    TranscriptionOutput,
    request_payload,
    text_like_bands,
    validate_material,
)
from schulpilot.providers import ProviderError, request_provider
from sqlalchemy import select
from test_providers import configured

BODY = (
    "Beim Kürzen teilen wir Zähler und Nenner durch dieselbe Zahl.\n"
    "12/18 = 6/9 = 2/3. Der Wert des Bruchs bleibt gleich."
)
BLOCKS = [
    {"kind": "heading", "text": "KÜNSTLICHER FUNKTIONSTEST - KEINE KINDERDATEN"},
    {"kind": "heading", "text": "Brüche kürzen"},
    {"kind": "paragraph", "text": BODY},
    {"kind": "formula", "text": "3/9 = 1/3\n6/12 = 1/2"},
]


def transcription(**changes):
    return {
        "blocks": BLOCKS,
        "legibility": "readable",
        "subject": "Mathematik",
        "topic": "Brüche kürzen",
        "uncertainties": [],
        "homework": [],
        **changes,
    }


def material(**changes):
    return {
        "source_blocks": [],
        "legibility": "readable",
        "subject": "Mathematik",
        "topic": "Brüche kürzen",
        "content": "\n\n".join(block["text"] for block in BLOCKS),
        "uncertainties": [],
        "homework": [],
        **changes,
    }


def image_bytes(kind="text"):
    image = Image.new("RGB", (1200, 1600), "white")
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype("DejaVuSans.ttf", 25)
    if kind == "text":
        for line in range(26):
            draw.text(
                (55, 80 + line * 48),
                "Künstliche lange Textzeile: Zähler und Nenner durch dieselbe Zahl teilen.",
                font=font,
                fill="black",
            )
    elif kind == "ruled":
        for line in range(28):
            draw.line((40, 60 + line * 48, 1160, 60 + line * 48), fill="#9ca3af", width=2)
    elif kind == "grid":
        for x in range(40, 1161, 70):
            draw.line((x, 60, x, 1520), fill="#64748b", width=2)
        for y in range(60, 1521, 70):
            draw.line((40, y, 1160, y), fill="#64748b", width=2)
    elif kind == "formulas":
        for line in range(24):
            draw.text((65, 65 + line * 48), "1/2 = 2/4", font=font, fill="black")
    elif kind == "diagram":
        for line in range(18):
            x, y = 130 + line * 40, 130 + line * 35
            draw.ellipse((x, y, x + 420, y + 420), outline="black", width=3)
        draw.text((60, 1250), "Kreis", font=font, fill="black")
    elif kind == "drawing":
        draw.polygon([(110, 1150), (380, 330), (1010, 1230)], outline="black", width=5)
        draw.ellipse((320, 620, 880, 1180), outline="black", width=4)
        draw.text((55, 1300), "A", font=font, fill="black")
    elif kind == "short":
        draw.text((60, 80), "1/2 = 2/4", font=font, fill="black")
    elif kind != "blank":
        raise AssertionError("Unknown artificial image kind")
    output = io.BytesIO()
    image.save(output, "JPEG", quality=93)
    return output.getvalue()


def test_blocks_preserve_every_word_order_equation_and_original_mistake():
    data = transcription(blocks=[*BLOCKS, {"kind": "formula", "text": "Sichtbarer Fehler: 1 + 1 = 3"}])
    result = TranscriptionOutput.model_validate(data).as_material()
    assert result["content"] == "\n\n".join(block["text"] for block in data["blocks"])
    assert BODY in result["content"] and "3/9 = 1/3\n6/12 = 1/2" in result["content"]
    assert result["content"].endswith("Sichtbarer Fehler: 1 + 1 = 3")
    assert set(result) == set(material())
    assert result["source_blocks"] == [{**b, "purpose": "unknown"} for b in data["blocks"]]


def test_known_ocr_subject_alias_uses_catalogue_without_changing_page_contents():
    original = material(subject="English", topic="Simple past", content="English\nI played yesterday.")
    result = validate_material(original)
    assert result["subject"] == "Englisch"
    assert result["content"] == original["content"]
    assert result["topic"] == original["topic"]
    assert validate_material(material(subject="English club"))["subject"] == "English club"


@pytest.mark.parametrize(
    "changes",
    [
        {"blocks": []},
        {"legibility": "partial", "uncertainties": []},
        {"legibility": "unreadable"},
        {"uncertainties": ["x" * 501]},
        {"homework": ["x" * 501]},
        {"blocks": [{"kind": "paragraph", "text": "x" * 12001}]},
    ],
)
def test_block_schema_keeps_existing_content_and_uncertainty_limits(changes):
    with pytest.raises(ValidationError):
        TranscriptionOutput.model_validate(transcription(**changes))


def test_sparse_formulas_partial_and_blank_do_not_need_minimum_word_count():
    assert validate_material(material(content="1/2"), image_bytes("short"))["content"] == "1/2"
    assert (
        validate_material(
            material(legibility="partial", content="12/18", uncertainties=["Unterer Absatz unleserlich."]),
            image_bytes(),
        )["legibility"]
        == "partial"
    )
    blank = transcription(
        blocks=[], legibility="unreadable", subject="", topic="", uncertainties=["Kein lesbarer Text."]
    )
    assert TranscriptionOutput.model_validate(blank).as_material()["content"] == ""


@pytest.mark.parametrize("kind", ["blank", "short", "formulas", "ruled", "grid", "diagram", "drawing"])
def test_layout_guard_does_not_mistake_sparse_or_graphical_pages_for_dense_text(kind):
    photo = image_bytes(kind)
    assert text_like_bands(photo) < 12
    assert validate_material(material(content="1/2"), photo)["content"] == "1/2"


def test_dense_page_caption_is_rejected_without_inventing_or_replacing_text():
    photo = image_bytes()
    assert text_like_bands(photo) >= 18
    with pytest.raises(IncompleteTranscription, match="deutlich mehr Text"):
        validate_material(material(content="KÜNSTLICHER FUNKTIONSTEST - KEINE KINDERDATEN"), photo)
    full = material(content="\n".join([BODY] * 13))
    assert validate_material(full, photo) == full


def test_bad_or_oversized_images_never_allocate_an_unbounded_analysis():
    assert text_like_bands(b"not-an-image") == 0
    assert text_like_bands(b"x" * (10 * 1024 * 1024 + 1)) == 0
    image = Image.new("1", (4100, 4100), 1)
    output = io.BytesIO()
    image.save(output, "PNG")
    assert text_like_bands(output.getvalue()) == 0


def config_for_test(household, provider="openrouter"):
    user, _ = household
    configured(user["families"][0]["id"])
    if provider == "codex":
        object.__setattr__(settings, "codex_approved", True)
        object.__setattr__(settings, "codex_socket", "/tmp/artificial-isolated-worker.sock")
    with DB.begin() as db:
        config = db.get(ProviderConfig, 1)
        config.provider = provider
        config.model = "artificial-vision-fixture:free"
        config.capability_evidence = "artificial vision evidence upstream=explicit-test-upstream"
        config.input_per_million_micros = 0
        config.output_per_million_micros = 0
    with DB() as db:
        return db.get(ProviderConfig, 1)


def fake_transport(monkeypatch, data, *, finish_reason="stop", provider="openrouter"):
    captured = []

    class Client:
        def __init__(self, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def post(self, url, headers=None, json=None):
            captured.append(json)
            if provider == "codex":
                return httpx.Response(200, json={"data": data, "usage": {"input_tokens": 100, "output_tokens": 300}})
            if provider == "openai":
                return httpx.Response(
                    200,
                    json={
                        "status": "completed",
                        "output": [
                            {
                                "type": "message",
                                "content": [{"type": "output_text", "text": __import__("json").dumps(data)}],
                            }
                        ],
                        "usage": {"input_tokens": 100, "output_tokens": 300},
                    },
                )
            return httpx.Response(
                200,
                json={
                    "choices": [
                        {"finish_reason": finish_reason, "message": {"content": __import__("json").dumps(data)}}
                    ],
                    "usage": {"prompt_tokens": 100, "completion_tokens": 300, "cost": 0},
                },
            )

    monkeypatch.setattr(providers.httpx, "Client", Client)
    monkeypatch.setattr(providers, "verify_free_endpoint", lambda *args, **kwargs: None)
    return captured


@pytest.mark.parametrize("provider", ["openrouter", "openai", "codex"])
def test_actual_request_is_ocr_only_and_returns_all_literal_blocks(api, household, monkeypatch, provider):
    config = config_for_test(household, provider)
    captured = fake_transport(monkeypatch, transcription(), provider=provider)
    photo = image_bytes("short")
    result = request_provider(
        config, "extract", {"grade": 6, "recent_outcomes": ["private previous answer"], "material": None}, photo
    )
    assert {k:v for k,v in result.data.items() if k != "source_blocks"} == {k:v for k,v in material().items() if k != "source_blocks"}
    assert len(captured) == 1
    body = captured[0]
    instructions = (
        body["messages"][0]["content"]
        if provider == "openrouter"
        else body["system"]
        if provider == "codex"
        else body["instructions"]
    )
    assert "vollständige WÖRTLICHE TRANSKRIPTION" in instructions
    assert "Nicht zusammenfassen, umformulieren" in instructions
    assert "Kopfzeile" in instructions and "darunter" in instructions
    assert "Typ choice" not in instructions and "recent_outcomes" not in instructions
    if provider == "codex":
        assert body["payload"] == request_payload()
        assert base64.b64decode(body["image"]) == photo
    else:
        content = body["messages"][1]["content"] if provider == "openrouter" else body["input"][0]["content"]
        assert json.loads(content[0]["text"]) == request_payload()
        image_url = content[1]["image_url"]
        assert (image_url["detail"] if isinstance(image_url, dict) else content[1]["detail"]) == "high"
        encoded = image_url["url"] if isinstance(image_url, dict) else image_url
        assert base64.b64decode(encoded.split(",", 1)[1]) == photo
    schema = (
        body["response_format"]["json_schema"]["schema"]
        if provider == "openrouter"
        else body["schema"]
        if provider == "codex"
        else body["text"]["format"]["schema"]
    )
    assert list(schema["properties"])[0] == "blocks"
    assert "content" not in schema["properties"]
    assert schema["$defs"]["TranscriptionBlock"]["additionalProperties"] is False
    if provider == "openrouter":
        assert body["provider"]["only"] == ["explicit-test-upstream"]
        assert body["provider"]["allow_fallbacks"] is False
        assert body["provider"]["max_price"] == {"prompt": 0, "completion": 0, "request": 0}
        assert body["provider"]["data_collection"] == "deny"


def test_fixed_demo_fixture_keeps_its_server_image_and_discards_free_inputs(api, household, monkeypatch):
    from schulpilot.fixtures import worksheet

    config = config_for_test(household)
    object.__setattr__(settings, "synthetic_ai_enabled", True)
    calls = fake_transport(monkeypatch, transcription())
    result = request_provider(
        config, "extract", {"content": "untrusted caller replacement"}, b"untrusted-image", synthetic_fixture=True
    )
    assert {k:v for k,v in result.data.items() if k != "source_blocks"} == {k:v for k,v in material().items() if k != "source_blocks"} and len(calls) == 1
    content = calls[0]["messages"][1]["content"]
    assert json.loads(content[0]["text"]) == request_payload()
    assert base64.b64decode(content[1]["image_url"]["url"].split(",", 1)[1]) == worksheet()
    assert "untrusted caller replacement" not in json.dumps(calls[0])


def test_truncated_json_even_if_well_formed_is_never_accepted_or_retried(api, household, monkeypatch):
    config = config_for_test(household)
    captured = fake_transport(monkeypatch, transcription(), finish_reason="length")
    with pytest.raises(ProviderError, match="begrenzte Ausgabelänge"):
        request_provider(config, "extract", {}, image_bytes())
    assert len(captured) == 1


def test_old_caption_shape_cannot_bypass_new_transcription_schema(api, household, monkeypatch):
    config = config_for_test(household)
    captured = fake_transport(monkeypatch, material(content="Only a caption"))
    with pytest.raises(ProviderError, match="Ausgabe erfüllt"):
        request_provider(config, "extract", {}, image_bytes())
    assert len(captured) == 1


def test_worker_saves_whole_transcript_and_explicit_retry_preserves_old_material_on_failure(
    api, household, monkeypatch
):
    _, child = household
    config_for_test(household)
    photo = image_bytes()
    uploaded = api.post(
        f"/api/children/{child['id']}/materials", files={"file": ("artificial.jpg", photo, "image/jpeg")}
    )
    assert uploaded.status_code == 201
    mid = uploaded.json()["id"]
    full = material(content="\n\n".join([BODY] * 14))
    actual_response = transcription(blocks=[{"kind": "paragraph", "text": BODY} for _ in range(14)])
    calls = fake_transport(monkeypatch, actual_response)
    first = api.post(f"/api/materials/{mid}/extract", headers={"Idempotency-Key": "first-artificial-ocr"})
    assert first.status_code == 202
    with DB() as db:
        assert worker.claim(db) == first.json()["id"]
    worker.process(first.json()["id"])
    saved = api.get(f"/api/materials/{mid}").json()
    assert saved["content"] == full["content"] and saved["status"] == "review"
    assert saved["confirmed"] is False
    with DB() as db:
        saved_revision = db.get(Material, mid).revision

    actual_response["blocks"] = [{"kind": "heading", "text": "Only a caption"}]
    second = api.post(f"/api/materials/{mid}/extract", headers={"Idempotency-Key": "explicit-second-artificial-ocr"})
    assert second.status_code == 202
    with DB() as db:
        assert worker.claim(db) == second.json()["id"]
    worker.process(second.json()["id"])
    failed = api.get("/api/jobs/" + second.json()["id"]).json()
    assert failed["status"] == "failed" and "deutlich mehr Text" in failed["error"]
    saved_again = api.get(f"/api/materials/{mid}").json()
    assert saved_again["content"] == full["content"] and saved_again["status"] == "review"
    assert saved_again["confirmed"] is False
    assert len(calls) == 2
    with DB() as db:
        assert db.get(Material, mid).content == full["content"]
        assert db.get(Material, mid).revision == saved_revision
        usages = list(db.scalars(select(Usage)))
        assert len(usages) == 2 and all(u.cost_micros == 0 for u in usages)
        assert any(u.status.startswith("failed") for u in usages)


def test_compact_transcription_wire_keeps_literal_symbols_marks_regions_and_whitespace():
    from schulpilot.extraction import TranscriptionBlock

    literal = '    5⅔ = 17/3\n3 ∤ 25\nkgV(8,12)=96\n'
    block = TranscriptionBlock.model_validate({
        'k':'formula','t':literal,'p':'example','l':'student_work',
        'r':{'l':10,'t':20,'r':900,'b':800},
        'a':[{'k':'correction','q':'96','c':'red','a':'unknown','e':'','r':None}],
        'u':['Die rote Markierung ist keine geprüfte richtige Lösung.']})
    wire = block.model_dump(by_alias=True, exclude_none=True)
    assert 't' in wire and 'text' not in wire
    data = transcription(blocks=[wire])
    result = TranscriptionOutput.model_validate(data).as_material()
    assert result['content'] == literal
    saved = result['source_blocks'][0]
    assert saved['text'] == literal and saved['annotations'][0]['quote'] == '96'
    assert saved['annotations'][0]['color'] == 'red' and saved['annotations'][0]['author'] == 'unknown'
    assert saved['image_region'] == {'left':10,'top':20,'right':900,'bottom':800}
    assert 't' not in saved and 'r' not in saved
    with pytest.raises(ValidationError):
        TranscriptionBlock.model_validate({**wire, 'r':{'l':900,'t':20,'r':10,'b':800}})
    quarantined = TranscriptionBlock.model_validate({**wire, 'a':[{'k':'comment','q':'erfunden'}]})
    assert quarantined.text == literal and not quarantined.annotations
    assert quarantined.reading_uncertainties



def test_compact_wire_saves_repeated_metadata_without_shortening_original_text():
    from schulpilot.extraction import TranscriptionBlock
    from schulpilot.subject_content import SourceBlock

    original = SourceBlock(kind='formula', text='2/3 min = 40 s', literal_role='student_work',
        annotations=[{'kind':'highlight','quote':'40','color':'red'}],
        image_region={'left':0,'top':100,'right':1000,'bottom':200})
    block = TranscriptionBlock.model_validate(original.model_dump())
    full = json.dumps(original.model_dump(exclude_none=True), ensure_ascii=False, separators=(',',':'))
    compact = json.dumps(block.model_dump(by_alias=True, exclude_none=True), ensure_ascii=False, separators=(',',':'))
    assert len(compact) < len(full) * 0.75
    assert TranscriptionBlock.model_validate_json(compact).text == original.text
