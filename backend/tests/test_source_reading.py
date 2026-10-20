"""A read-only display projection of the exact saved artificial transcript."""

from schulpilot.db import Material
from schulpilot.extraction import TranscriptionOutput
from schulpilot.learning import material_data


def page(blocks, content=None):
    return Material(
        id="synthetic-reading-page",
        child_id="synthetic-reader",
        subject="Physik",
        topic="Weg und Zeit",
        content=content if content is not None else "\n\n".join(b["text"] for b in blocks),
        source_blocks=blocks,
        homework=[],
        uncertainties=[],
        quality_warnings=[],
        task_decisions=[],
        synthetic=False,
    )


def test_exact_source_structure_survives_the_detail_projection_without_changing_text():
    blocks = [
        {"kind": "heading", "text": "Künstliche Testseite"},
        {"kind": "formula", "text": r"\[v=\frac{s}{t}\]"},
        {"kind": "table", "text": "Weg | Zeit\n6 m | 2 s"},
        {"kind": "code", "text": "for x in range(3):\n    print(x)"},
        {"kind": "diagram_text", "text": "Achsen: t in s, s in m"},
    ]
    m = page(blocks)
    data = material_data(m)
    assert data["content"] == m.content
    assert [b["text"] for b in data["source_blocks"]] == [b["text"] for b in blocks]
    assert data["source_blocks"][-2]["kind"] == "code"
    assert m.source_blocks == blocks


def test_corrected_or_malformed_blocks_do_not_replace_the_saved_revision():
    for blocks, content in [
        ([{"kind": "paragraph", "text": "Alt"}], "Neu"),
        ([{"kind": "untrusted", "text": "Neu"}], "Neu"),
        ([{"kind": "code", "text": 42}], "Neu"),
    ]:
        m = page(blocks, content)
        assert material_data(m)["source_blocks"] == []
        assert material_data(m)["content"] == "Neu"


def test_literal_code_and_math_ocr_keeps_indentation_and_no_extra_source():
    blocks = [{"kind": "formula", "text": r"\[E=mc^2\]"}, {"kind": "code", "text": "for n in range(3):\n    print(n)"}]
    result = TranscriptionOutput(
        blocks=blocks,
        legibility="readable",
        subject="Physik",
        topic="Künstliche Notation",
        uncertainties=[],
        homework=[],
    ).as_material()
    assert result["content"] == "\n\n".join(b["text"] for b in blocks)
    assert result["source_blocks"][1]["text"].splitlines()[1].startswith("    ")


def test_an_indented_code_excerpt_keeps_its_first_line_through_confirmation():
    import pytest
    from pydantic import ValidationError
    from schulpilot.schemas import MaterialConfirm, MaterialVocabularyPreview

    code = "    summe += zahl\n    print(summe)\n"
    result = TranscriptionOutput(
        blocks=[{"kind": "code", "text": code}],
        legibility="readable",
        subject="Informatik",
        topic="Künstlicher Codeausschnitt",
        uncertainties=[],
        homework=[],
    ).as_material()
    assert result["content"] == code
    assert result["source_blocks"][0]["text"] == code
    data = MaterialConfirm(subject="Informatik", topic="Code", content=code, uncertainties_resolved=True)
    assert data.content == code
    assert MaterialVocabularyPreview(subject="Informatik", topic="Code", content=code).content == code
    with pytest.raises(ValidationError):
        MaterialConfirm(subject="Informatik", topic="Code", content="  \n  ", uncertainties_resolved=True)


def test_source_region_is_bounded_and_never_a_generated_lesson_graphic():
    import pytest
    from pydantic import ValidationError
    from schulpilot.subject_content import SourceBlock

    valid = {"left": 100, "top": 200, "right": 900, "bottom": 700}
    assert SourceBlock(kind="diagram_text", text="Künstliche Zeichnung", image_region=valid).image_region.right == 900
    for region in [dict(valid, left=-1), dict(valid, right=1001), dict(valid, left=900), dict(valid, left=100.1)]:
        with pytest.raises(ValidationError):
            SourceBlock(kind="diagram_text", text="Zeichnung", image_region=region)
    with pytest.raises(ValidationError):
        SourceBlock(kind="formula", text="x=1", image_region=valid)


def test_private_original_crop_checks_owner_revision_and_causes_no_writes(api, household):
    import io

    from conftest import HEADERS, create_child
    from fastapi.testclient import TestClient
    from PIL import Image
    from schulpilot.config import settings
    from schulpilot.db import DB, Activity, Job, Usage
    from schulpilot.main import app
    from sqlalchemy import func, select

    parent, child = household
    sibling = create_child(api, parent, "synthetic-crop-sibling")
    folder = settings.data_dir / "uploads"
    folder.mkdir(exist_ok=True)
    image = Image.new("RGB", (1000, 600), "white")
    image.paste((0, 80, 160), (200, 120, 800, 480))
    image.save(folder / "synthetic-crop.jpg")
    block = {
        "kind": "diagram_text",
        "text": "Künstliche blaue Fläche",
        "image_region": {"left": 200, "top": 200, "right": 800, "bottom": 800},
    }
    with DB.begin() as db:
        m = Material(
            child_id=child["id"],
            title="Künstlicher Ausschnitt",
            path="synthetic-crop.jpg",
            content=block["text"],
            source_blocks=[block],
        )
        db.add(m)
        db.flush()
        mid = m.id
        private = Material(
            child_id=sibling["id"],
            title="Andere künstliche Quelle",
            path=m.path,
            content=block["text"],
            source_blocks=[block],
        )
        db.add(private)
        db.flush()
        other = private.id
        before = [db.scalar(select(func.count()).select_from(t)) for t in (Job, Usage, Activity)]
    route = f"/api/materials/{mid}/figures/0"
    response = api.get(route, params={"revision": 1})
    assert response.status_code == 200, response.text
    assert response.headers["cache-control"] == "no-store"
    assert response.headers["content-type"] == "image/jpeg"
    with Image.open(io.BytesIO(response.content)) as crop:
        assert crop.size == (624, 376)
        assert crop.getpixel((300, 180))[2] > 140
    assert api.get(route, params={"revision": 2}).status_code == 409
    assert api.get(f"/api/materials/{mid}/figures/1", params={"revision": 1}).status_code == 404
    with TestClient(app, headers=HEADERS) as own:
        assert own.get(route, params={"revision": 1}).status_code == 401
        login = own.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"}).json()
        own.headers["Authorization"] = "Bearer " + login["token"]
        assert own.get(route, params={"revision": 1}).status_code == 200
        assert own.get(f"/api/materials/{other}/figures/0", params={"revision": 1}).status_code == 404
    with DB.begin() as db:
        assert [db.scalar(select(func.count()).select_from(t)) for t in (Job, Usage, Activity)] == before
        db.get(Material, mid).content = "Korrigierter Text"
    assert api.get(route, params={"revision": 1}).status_code == 404
    (folder / "synthetic-crop.jpg").unlink()


def test_operating_admin_cannot_read_a_private_source_figure(api, household):
    from schulpilot.db import DB, User
    from schulpilot.security import password_hash

    _, child = household
    with DB.begin() as db:
        db.add(
            User(
                username="synthetic-figure-admin",
                display_name="Künstlicher Betrieb",
                role="admin",
                verified=True,
                password_hash=password_hash("synthetic-figure-password"),
            )
        )
        m = Material(child_id=child["id"], title="Künstliche private Abbildung", path="synthetic.jpg")
        db.add(m)
        db.flush()
        mid = m.id
    signed = api.post(
        "/api/auth/login", json={"username": "synthetic-figure-admin", "password": "synthetic-figure-password"}
    )
    assert signed.status_code == 200
    api.headers["Authorization"] = "Bearer " + signed.json()["token"]
    assert api.get(f"/api/materials/{mid}/figures/0", params={"revision": 1}).status_code == 403
