"""Artificial source text/pixels only; no provider inference or real family data."""

import io
from types import SimpleNamespace

import pytest
from PIL import Image
from pydantic import ValidationError
from schulpilot.config import settings
from schulpilot.db import DB, Activity, Attempt, Job, LearningUnit, Material, UnitSource, Usage
from schulpilot.extraction import OCR_SYSTEM, TranscriptionOutput
from schulpilot.source_lineage import (
    block_data,
    export_sources,
    false_equality,
    learning_source,
    save_snapshot,
    unit_source_status,
    usable_source,
)
from schulpilot.source_lineage_models import SourceImageReceipt, SourceInvalidation, SourceRevision
from schulpilot.subject_content import SourceBlock
from schulpilot.synthetic import sample_unit
from sqlalchemy import func, select


def page(blocks, **changes):
    values = dict(
        id="a" * 32,
        revision=1,
        purpose="notebook",
        confirmed=True,
        legibility="readable",
        uncertainties=[],
        content="\n\n".join(block["text"] for block in blocks),
        source_blocks=blocks,
    )
    return SimpleNamespace(**(values | changes))


@pytest.mark.parametrize(
    "text,wrong",
    [
        ("1+1=3", True),
        ("2/4=1/2", False),
        (r"\[\frac{1}{2}=\frac{2}{3}\]", True),
        ("1/2=2/4=3/4", True),
        ("-2+1=-1", False),
        ("0,5=1/2", False),
        ("x=2", False),
        ("import os=1", False),
        ("1/0=0", False),
        ("CO=Co", False),
        ("1==2", False),
        ("2**100000=1", False),
    ],
)
def test_finite_rational_guard_does_not_guess_or_correct(text, wrong):
    assert false_equality(text) is wrong


def test_literal_annotations_are_not_correctness_or_authorship_and_require_quotes():
    block = dict(kind="formula", text="1+1=3\n2", annotations=[dict(kind="correction", quote="2", color="red")])
    parsed = SourceBlock.model_validate(block)
    assert parsed.annotations[0].author == "unknown"
    assert parsed.text == block["text"]
    for mark in (
        dict(kind="correction", quote="Erfunden"),
        dict(kind="correction", quote="2", color="red", author="teacher"),
    ):
        with pytest.raises(ValidationError):
            SourceBlock(kind="formula", text=block["text"], annotations=[mark])
    with pytest.raises(ValidationError):
        SourceBlock(kind="paragraph", text="Original", reading_uncertainties=["x" * 301])
    assert r"\mid" in OCR_SYSTEM and r"\nmid" in OCR_SYSTEM
    assert "Farbe ist kein Nachweis" in OCR_SYSTEM


def test_learning_groundtruth_excludes_bad_work_but_original_remains_exact():
    blocks = [
        dict(kind="paragraph", text="Zähler und Nenner mit derselben Zahl erweitern."),
        dict(kind="formula", text="1+1=3"),
        dict(kind="formula", text="2+2=4", literal_role="student_work"),
        dict(kind="paragraph", text="Wort heute", reading_uncertainties=["Letzter Buchstabe unklar"]),
        dict(kind="paragraph", text="alt neu", annotations=[dict(kind="crossout", quote="alt", color="red")]),
    ]
    material = page(blocks)
    before = material.content
    result = learning_source(None, material)
    assert result["content"] == blocks[0]["text"]
    assert {row["reason"] for row in result["exclusions"]} == {
        "false_equality",
        "student_work",
        "reading_uncertain",
        "visible_annotation",
    }
    assert material.content == before and material.source_blocks == blocks
    assert result["factual_status"] == "partly_excluded"
    assert all(ref["revision"] == 1 for ref in result["source_refs"])
    assert result["source_refs"][0]["block_id"] == block_data(material)[0]["block_id"]
    assert usable_source(None, material)
    assert not usable_source(None, material, revision=2)
    assert not usable_source(None, page(blocks, purpose="exam"))


def test_global_unknowns_and_detached_annotations_cannot_become_groundtruth():
    good = [dict(kind="paragraph", text="Längeneinheit Meter")]
    assert not usable_source(None, page(good, uncertainties=["Ziffer unklar"]))
    stale = good + [dict(kind="paragraph", text="Alt", literal_role="student_work")]
    assert not usable_source(None, page(stale, content="Korrigierter Text ohne aktuelle Zuordnung"))
    assert learning_source(None, page(good))["factual_status"] == "not_assessed"
    assert block_data(page(good, revision=2))[0]["block_id"] != block_data(page(good))[0]["block_id"]


def test_transcription_keeps_wrong_answer_red_correction_and_all_roles_separate():
    blocks = [
        dict(
            kind="formula",
            text="1+1=3\nKorrektur: 2",
            literal_role="student_work",
            image_region=dict(left=0, top=0, right=1000, bottom=500),
            annotations=[dict(kind="correction", quote="2", color="red")],
        )
    ]
    value = TranscriptionOutput(
        blocks=blocks,
        legibility="readable",
        subject="Mathematik",
        topic="Künstliches Beispiel",
        uncertainties=[],
        homework=[],
    ).as_material()
    assert value["content"] == blocks[0]["text"]
    assert value["source_blocks"][0]["annotations"][0]["color"] == "red"
    assert value["source_blocks"][0]["literal_role"] == "student_work"


def test_confirmation_preserves_history_attempts_and_marks_dependent_content(api, household):
    _, child = household
    with DB.begin() as db:
        material = Material(
            child_id=child["id"],
            title="Künstliche Quelle",
            subject="Mathematik",
            topic="Addition",
            content="1+1=3",
            source_blocks=[dict(kind="formula", text="1+1=3")],
            status="confirmed",
            confirmed=True,
        )
        db.add(material)
        db.flush()
        data = sample_unit()
        unit = LearningUnit(
            child_id=child["id"],
            material_id=material.id,
            subject=data["subject"],
            topic=data["topic"],
            explanation=data["explanation"],
            questions=data["questions"],
            provider="synthetic",
            active_seconds=17,
        )
        db.add(unit)
        db.flush()
        db.add(UnitSource(unit_id=unit.id, material_id=material.id, revision=1))
        attempt = Attempt(
            unit_id=unit.id, question_id=data["questions"][0]["id"], answer="Eigene Antwort", outcome="incorrect"
        )
        db.add(attempt)
        db.flush()
        mid, unit_id, aid = material.id, unit.id, attempt.id
    response = api.put(
        f"/api/materials/{mid}/confirm",
        json=dict(
            revision=1,
            subject="Mathematik",
            topic="Addition",
            content="1+1=2",
            homework=[],
            uncertainties_resolved=True,
        ),
    )
    assert response.status_code == 200, response.text
    assert response.json()["revision"] == 2
    history = api.get(f"/api/materials/{mid}/revisions")
    assert history.status_code == 200 and len(history.json()["items"]) == 2
    texts = [
        api.get(f"/api/materials/{mid}/revisions/{row['id']}").json()["literal"]["content"]
        for row in history.json()["items"]
    ]
    assert set(texts) == {"1+1=3", "1+1=2"}
    with DB() as db:
        assert db.get(Attempt, aid).answer == "Eigene Antwort"
        assert db.get(LearningUnit, unit_id).active_seconds == 17
        assert unit_source_status(db, db.get(LearningUnit, unit_id))["needs_source_review"]
        assert db.scalar(select(func.count()).select_from(SourceInvalidation)) == 1
        assert len(export_sources(db, child["id"])["source_revisions"]) == 2


def test_snapshot_retry_same_revision_is_immutable_and_cascades_on_erasure(api, household):
    _, child = household
    with DB.begin() as db:
        material = Material(child_id=child["id"], title="Künstlicher Retry", content="Wort A")
        db.add(material)
        db.flush()
        first = save_snapshot(db, material, "extraction", {"job_id": "a" * 32})
        material.content = "Wort B"
        second = save_snapshot(db, material, "extraction", {"job_id": "b" * 32})
        assert first.id != second.id and first.snapshot["content"] == "Wort A"
        assert save_snapshot(db, material, "extraction", {"job_id": "b" * 32}).id == second.id
        mid = material.id
    with DB.begin() as db:
        db.delete(db.get(Material, mid))
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(SourceRevision)) == 0


def test_new_photo_retains_3200_geometry_no_upscale_and_strips_metadata(api, household):
    from test_providers import configured

    user, child = household
    configured(user["families"][0]["id"])
    for size, expected in [((4000, 2000), (3200, 1600)), ((300, 200), (300, 200))]:
        image = Image.new("RGB", size, "white")
        exif = Image.Exif()
        exif[270] = "synthetic-private-marker"
        out = io.BytesIO()
        image.save(out, "JPEG", exif=exif)
        response = api.post(
            f"/api/children/{child['id']}/materials", files={"file": ("synthetic.jpg", out.getvalue(), "image/jpeg")}
        )
        assert response.status_code == 201, response.text
        with DB() as db:
            material = db.get(Material, response.json()["id"])
            receipt = db.get(SourceImageReceipt, material.id)
            assert (receipt.geometry["width"], receipt.geometry["height"]) == expected
            with Image.open(settings.data_dir / "uploads" / material.path) as saved:
                assert saved.size == expected and not saved.getexif()


def test_formula_crop_by_stable_block_id_is_private_revision_bound_get_only(api, household):
    _, child = household
    folder = settings.data_dir / "uploads"
    folder.mkdir(exist_ok=True)
    Image.new("RGB", (1000, 600), "purple").save(folder / "synthetic-formula.jpg")
    block = dict(kind="formula", text="1+1=3", image_region=dict(left=200, top=200, right=800, bottom=800))
    with DB.begin() as db:
        material = Material(
            child_id=child["id"],
            title="Künstliche Formel",
            content=block["text"],
            source_blocks=[block],
            path="synthetic-formula.jpg",
        )
        db.add(material)
        db.flush()
        mid = material.id
        bid = block_data(material)[0]["block_id"]
        counts = [
            db.scalar(select(func.count()).select_from(model)) for model in (Job, Usage, Activity, SourceRevision)
        ]
    response = api.get(f"/api/materials/{mid}/source-blocks/{bid}/image?revision=1")
    assert response.status_code == 200 and response.headers["cache-control"] == "no-store"
    assert api.get(f"/api/materials/{mid}/source-blocks/{bid}/image?revision=2").status_code == 409
    assert api.get(f"/api/materials/{mid}/source-blocks/{'f' * 32}/image?revision=1").status_code == 404
    with DB() as db:
        assert [
            db.scalar(select(func.count()).select_from(model)) for model in (Job, Usage, Activity, SourceRevision)
        ] == counts


def test_normalized_output_bound_is_checked_before_disk_or_material_write(api, household, monkeypatch):
    from test_providers import configured

    user, child = household
    configured(user["families"][0]["id"])
    out = io.BytesIO()
    Image.new("RGB", (20, 20), "white").save(out, "PNG")
    folder = settings.data_dir / "uploads"
    before_files = set(folder.iterdir()) if folder.exists() else set()

    def oversized(self, target, *args, **kwargs):
        target.write(b"x" * (10 * 1024 * 1024 + 1))

    monkeypatch.setattr(Image.Image, "save", oversized)
    response = api.post(
        f"/api/children/{child['id']}/materials", files={"file": ("synthetic.png", out.getvalue(), "image/png")}
    )
    assert response.status_code == 413, response.text
    assert (set(folder.iterdir()) if folder.exists() else set()) == before_files
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Material)) == 0
        assert db.scalar(select(func.count()).select_from(Job)) == 0
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


def test_saved_literal_receipts_cannot_be_rewritten_and_history_has_total_order(api, household):
    _, child = household
    with DB.begin() as db:
        material = Material(child_id=child["id"], title="Künstliche Historie", content="Erster Wortlaut")
        db.add(material)
        db.flush()
        first = save_snapshot(db, material, "extraction", {"job_id": "a" * 32})
        material.content = "Zweiter Wortlaut"
        second = save_snapshot(db, material, "extraction", {"job_id": "b" * 32})
        mid, first_id = material.id, first.id
        assert second.sequence == first.sequence + 1
    history = api.get(f"/api/materials/{mid}/revisions").json()["items"]
    assert [row["sequence"] for row in history] == [2, 1]
    with pytest.raises(ValueError, match="unveränderlich"):
        with DB.begin() as db:
            row = db.get(SourceRevision, first_id)
            row.snapshot = {**row.snapshot, "content": "Versuchte Änderung"}
    with DB() as db:
        assert db.get(SourceRevision, first_id).snapshot["content"] == "Erster Wortlaut"
