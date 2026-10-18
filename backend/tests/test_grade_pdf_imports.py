"""Synthetic PDFs only; exercise local extraction and the ordinary parent API."""

import io
import json
import uuid
import zipfile
from concurrent.futures import ThreadPoolExecutor
from datetime import date

import httpx
import pytest
from conftest import HEADERS, create_child, register
from fastapi.testclient import TestClient
from pdf_fixture import pdf
from schulpilot.db import DB, Child, GradeImport, GradeSourceSlot, Membership, SchoolGrade, Session, Usage, User
from schulpilot.grade_imports import school_year
from schulpilot.grade_pdf import isolated_extract
from schulpilot.learning import local_day
from schulpilot.main import app
from sqlalchemy import func, select


def today_year(child_id):
    with DB() as db:
        return school_year(local_day(db.get(Child, child_id)))


def upload(client, child, raw=None, key=None):
    response = client.post(
        f"/api/children/{child['id']}/grade-imports",
        files={"file": ("grades.pdf", raw or pdf(today_year(child["id"])), "application/pdf")},
        headers={"Idempotency-Key": key or uuid.uuid4().hex},
    )
    return response


def confirmation(preview, actions=None):
    actions = actions or {}
    return {
        "school_year_start": preview["school_year_start"],
        "context_revision": preview["context_revision"],
        "choices": [
            {
                "slot_key": r["slot_key"],
                "action": actions.get(
                    r["slot_key"], "add" if r["status"] == "new" else "skip" if r["status"] == "ignored" else "keep"
                ),
            }
            for r in preview["items"]
        ],
    }


def confirm(client, child, preview, body=None):
    return client.post(
        f"/api/children/{child['id']}/grade-imports/{preview['id']}/confirm", json=body or confirmation(preview)
    )


def test_real_pdf_reader_with_synthetic_a1_excludes_averages_and_keeps_both_halves():
    entries = [("Mathematik", 1, "other", 1, "4"), ("Englisch", 2, "classwork", 2, "2")]
    result = isolated_extract(pdf(2026, entries))
    assert result["school_year_start"] == 2026
    assert result["entries"] == [
        {"subject": s, "semester": h, "kind": k, "slot": n, "value": v} for s, h, k, n, v in entries
    ]


@pytest.mark.parametrize(
    "raw",
    [
        b"not a pdf",
        pdf(2026, encrypted=True),
        pdf(2026, corrupt_header=True),
        pdf(2026, [("Englisch", 1, "other", 1, "unklar")]),
        pdf(2026, bad_subject=True),
    ],
)
def test_untrusted_or_ambiguous_pdf_fails_without_partial_import(raw):
    with pytest.raises(ValueError):
        isolated_extract(raw)


def test_import_preview_confirmation_repeat_export_delete_and_no_ai(api, household):
    parent, child = household
    key = "synthetic-grade-upload-0001"
    first = upload(api, child, key=key)
    assert first.status_code == 201, first.text
    preview = first.json()
    assert preview["counts"]["new"] == 3
    assert upload(api, child, key=key).json()["id"] == preview["id"]
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(SchoolGrade)) == 0
        assert db.scalar(select(func.count()).select_from(Usage)) == 0
    result = confirm(api, child, preview)
    assert result.status_code == 200, result.text
    assert result.json()["added"] == 3
    assert confirm(api, child, preview).json() == result.json()
    next_preview = upload(api, child).json()
    assert next_preview["counts"]["existing"] == 3 and next_preview["counts"]["new"] == 0
    assert confirm(api, child, next_preview).json()["unchanged"] == 3
    grades = api.get(f"/api/children/{child['id']}/grades").json()
    assert len(grades["items"]) == 3 and all(
        g["assessed_on"] is None and g["date_precision"] == "semester" for g in grades["items"]
    )
    assert grades["focus"][0]["subject"] == "Mathematik" and grades["focus"][0]["priority"] >= 1
    assert all(g["trend"] == "not_enough_data" for g in grades["focus"])
    response = api.get(f"/api/families/{parent['families'][0]['id']}/export")
    with zipfile.ZipFile(io.BytesIO(response.content)) as archive:
        data = json.loads(archive.read("family.json"))["children"][0]
    assert len(data["school_grades"]) == 3 and len(data["grade_source_slots"]) == 3 and len(data["grade_imports"]) == 2
    assert (
        api.request("DELETE", f"/api/children/{child['id']}", json={"password": "secure-parent-pass-123"}).status_code
        == 200
    )
    with DB() as db:
        for model in (SchoolGrade, GradeImport, GradeSourceSlot):
            assert db.scalar(select(func.count()).select_from(model)) == 0


@pytest.mark.parametrize("chunked", [False, True])
def test_print_sized_pdf_passes_header_and_stream_limits_and_imports_once(api, household, chunked):
    _, child = household
    raw = pdf(today_year(child["id"]), padding_bytes=240 * 1024)
    assert 234_106 < len(raw) < 6 * 1024 * 1024
    if chunked:
        multipart = httpx.Request("POST", "http://testserver", files={"file": ("synthetic.pdf", raw, "application/pdf")})
        body = multipart.read()
        response = api.post(
            f"/api/children/{child['id']}/grade-imports",
            content=(body[n:n + 16_384] for n in range(0, len(body), 16_384)),
            headers={"Content-Type": multipart.headers["Content-Type"], "Idempotency-Key": "print-sized-grade-upload-0001"},
        )
    else:
        response = upload(api, child, raw, "print-sized-grade-upload-0001")
    assert response.status_code == 201, response.text
    preview = response.json()
    assert preview["counts"]["new"] == 3
    assert confirm(api, child, preview).json()["added"] == 3
    repeated = upload(api, child, raw, "print-sized-grade-upload-0002").json()
    assert repeated["counts"]["existing"] == 3
    assert confirm(api, child, repeated).json()["unchanged"] == 3
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(SchoolGrade)) == 3
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


def test_large_confirmation_uses_its_own_limit_without_relaxing_json_endpoints(api, household):
    _, child = household
    body = {
        "school_year_start": today_year(child["id"]),
        "context_revision": "a" * 64,
        "choices": [{"slot_key": "b" * 64, "action": "add"} for _ in range(1000)],
    }
    assert 64 * 1024 < len(json.dumps(body).encode()) < 512 * 1024
    response = api.post(f"/api/children/{child['id']}/grade-imports/{'c' * 32}/confirm", json=body)
    assert response.status_code == 404, response.text
    response = api.post("/api/auth/login", json={"username": "S" * (70 * 1024), "password": "synthetic"})
    assert response.status_code == 413
    assert "S" * 100 not in response.text


def test_changed_upload_and_manual_edits_never_silently_overwrite(api, household):
    _, child = household
    year = today_year(child["id"])
    preview = upload(api, child, pdf(year, [("Mathematik", 1, "other", 1, "2")])).json()
    assert confirm(api, child, preview).status_code == 200
    changed = upload(api, child, pdf(year, [("Mathematik", 1, "other", 1, "4")])).json()
    assert changed["counts"]["changed"] == 1
    with DB() as db:
        assert float(db.scalar(select(SchoolGrade.value))) == 2
    result = confirm(api, child, changed, confirmation(changed, {changed["items"][0]["slot_key"]: "update"}))
    assert result.status_code == 200 and result.json()["updated"] == 1
    grade = api.get(f"/api/children/{child['id']}/grades").json()["items"][0]
    body = {
        k: grade[k]
        for k in (
            "subject",
            "topic",
            "kind",
            "scale",
            "weight",
            "assessed_on",
            "school_year_start",
            "semester",
            "note",
            "revision",
        )
    }
    body["value"] = 3
    route = f"/api/children/{child['id']}/grades/{grade['id']}"
    assert api.put(route, json=body).status_code == 409  # Old client must not invent a date.
    assert api.put(route, json=body, headers={"X-Schulpilot-Capabilities": "grade-pdf-v1"}).status_code == 200
    repeat = upload(api, child, pdf(year, [("Mathematik", 1, "other", 1, "4")])).json()
    assert repeat["items"][0]["status"] == "existing"
    assert confirm(api, child, repeat).status_code == 200
    with DB() as db:
        assert float(db.scalar(select(SchoolGrade.value))) == 3


def test_parallel_confirm_and_parallel_repeat_upload_do_not_duplicate(api, household):
    _, child = household
    preview = upload(api, child).json()
    headers = dict(api.headers)

    def save(_):
        with TestClient(app, headers=headers) as client:
            return confirm(client, child, preview)

    with ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(save, range(4)))
    assert {r.status_code for r in results} == {200}, [r.text for r in results]
    assert len({json.dumps(r.json(), sort_keys=True) for r in results}) == 1
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(SchoolGrade)) == 3
        assert db.scalar(select(func.count()).select_from(GradeSourceSlot)) == 3


def test_manual_match_requires_choice_and_one_grade_cannot_fill_two_slots(api, household):
    _, child = household
    with DB.begin() as db:
        day = local_day(db.get(Child, child["id"])).isoformat()
        grade = SchoolGrade(
            child_id=child["id"],
            subject="Mathe",
            topic="Brüche",
            kind="test",
            scale="grade_1_6",
            weight=1,
            value=2,
            assessed_on=day,
            note="",
        )
        db.add(grade)
        db.flush()
        grade_id = grade.id
    preview = upload(
        api,
        child,
        pdf(today_year(child["id"]), [("Mathematik", 1, "other", 1, "2"), ("Mathematik", 1, "other", 2, "2")]),
    ).json()
    assert preview["counts"]["possible_match"] == 2
    assert confirm(api, child, preview).status_code == 422
    body = confirmation(preview)
    for choice in body["choices"]:
        choice.update(action="link", grade_id=grade_id)
    assert confirm(api, child, preview, body).status_code == 409
    body["choices"][1] = {"slot_key": preview["items"][1]["slot_key"], "action": "add"}
    saved = confirm(api, child, preview, body)
    assert saved.status_code == 200, saved.text
    assert saved.json()["added"] == saved.json()["linked"] == 1
    with DB() as db:
        assert db.get(SchoolGrade, grade_id).assessed_on == day
        assert db.scalar(select(func.count()).select_from(SchoolGrade)) == 2


def test_stale_preview_different_file_same_key_and_deleted_grade_protected(api, household):
    _, child = household
    raw = pdf(today_year(child["id"]))
    preview = upload(api, child, raw, "same-upload-key-0001").json()
    assert upload(api, child, pdf(today_year(child["id"]), []), "same-upload-key-0001").status_code == 409
    assert confirm(api, child, preview).status_code == 200
    repeated = upload(api, child).json()
    grade_id = repeated["items"][0]["grade_id"]
    assert api.delete(f"/api/children/{child['id']}/grades/{grade_id}").status_code == 200
    assert confirm(api, child, repeated).status_code == 409
    fresh = api.get(f"/api/children/{child['id']}/grade-imports/{repeated['id']}").json()
    assert fresh["counts"]["ignored"] == 1
    assert confirm(api, child, fresh).status_code == 200
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(SchoolGrade)) == 2


@pytest.mark.parametrize("raw", [pdf(2001), b"%PDF-" + b"x" * (6 * 1024 * 1024), b"PRIVATE invalid document"])
def test_invalid_year_size_or_file_leave_no_grades_and_no_document_echo(api, household, raw):
    _, child = household
    response = upload(api, child, raw)
    assert response.status_code in (413, 422)
    assert "PRIVATE" not in response.text
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(GradeImport)) == 0


def test_child_and_other_family_cannot_read_or_import(api, household, mailbox):
    _, child = household
    preview = upload(api, child).json()
    route = f"/api/children/{child['id']}/grade-imports/{preview['id']}"
    with TestClient(app, headers=HEADERS) as kid:
        login = kid.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"}).json()
        kid.headers["Authorization"] = "Bearer " + login["token"]
        assert kid.get(route).status_code == 403
        assert upload(kid, child).status_code == 403
        assert confirm(kid, child, preview).status_code == 403
    foreign = register(api, mailbox, "foreign@example.org")
    create_child(api, foreign, "foreign-child")
    assert api.get(route).status_code == 404
    assert upload(api, child).status_code == 404
    assert confirm(api, child, preview).status_code == 404


def test_view_permission_and_operator_role_cannot_write_private_imports(api, household):
    parent, child = household
    preview = upload(api, child).json()
    route = f"/api/children/{child['id']}/grade-imports/{preview['id']}"
    with DB.begin() as db:
        db.scalar(select(Membership).where(Membership.user_id == parent["id"])).permission = "view"
    assert api.get(route).status_code == 200
    assert upload(api, child).status_code == 403
    assert confirm(api, child, preview).status_code == 403
    with DB.begin() as db:
        db.get(User, parent["id"]).role = "admin"
    assert api.get(route).status_code == 403
    assert upload(api, child).status_code == 403
    assert confirm(api, child, preview).status_code == 403


@pytest.mark.parametrize("change", ["logout", "permission"])
def test_authority_rechecked_after_pdf_parsing(api, household, monkeypatch, change):
    from schulpilot import grade_imports

    parent, child = household
    original = grade_imports.isolated_extract

    def read(raw):
        parsed = original(raw)
        with DB.begin() as db:
            if change == "logout":
                for session in db.scalars(select(Session).where(Session.user_id == parent["id"])):
                    session.revoked = True
            else:
                db.scalar(select(Membership).where(Membership.user_id == parent["id"])).permission = "view"
        return parsed

    monkeypatch.setattr(grade_imports, "isolated_extract", read)
    response = upload(api, child)
    assert response.status_code == (401 if change == "logout" else 403)
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(GradeImport)) == 0


@pytest.mark.parametrize(
    "today, expected", [(date(2026, 7, 31), 2025), (date(2026, 8, 1), 2026), (date(2027, 1, 1), 2026)]
)
def test_explicit_school_year_boundary(today, expected):
    assert school_year(today) == expected
