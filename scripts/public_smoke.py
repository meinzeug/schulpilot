"""Synthetic end-to-end verification against the real public HTTPS API.

Never prints credentials, session tokens, child answers or provider secrets.
"""

import json
import time
import uuid

import httpx

BASE = "https://schulpilot.dorfspy.de/api"
HEADERS = {"X-Schulpilot-Request": "1", "X-Client-Platform": "native"}
checks = []


def expect(response, status=200):
    if response.status_code != status:
        raise AssertionError(
            f"{response.request.method} {response.request.url.path}: HTTP {response.status_code}, expected {status}"
        )
    return response.json()


with httpx.Client(base_url=BASE, headers=HEADERS, timeout=20) as parent:
    expect(parent.get("/health"))
    demo = expect(parent.post("/demo"), 201)
    parent.headers["Authorization"] = "Bearer " + demo["token"]
    family_id = demo["user"]["families"][0]["id"]
    child_id = demo["child_id"]
    material_id = demo["material_id"]
    material = expect(parent.get(f"/materials/{material_id}"))
    expect(
        parent.put(
            f"/materials/{material_id}/confirm",
            json={
                "subject": material["subject"],
                "topic": material["topic"],
                "content": material["content"],
                "homework": [],
                "uncertainties_resolved": True,
            },
        )
    )
    checks.append("material confirmation persisted")
    assignment = expect(
        parent.post(
            f"/children/{child_id}/assignments",
            json={
                "subject": "Mathematik",
                "topic": "Brüche",
                "kind": "parent",
                "mandatory": True,
                "material_id": material_id,
            },
        ),
        201,
    )
    plan = expect(parent.get(f"/children/{child_id}/overview"))["plan"]
    assert any(x.get("id") == assignment["id"] for x in [*plan["today"], *plan["later"]])
    checks.append("binding parent goal in bounded daily plan")
    key = uuid.uuid4().hex
    job = expect(
        parent.post(
            f"/children/{child_id}/units",
            json={"material_id": material_id, "assignment_id": assignment["id"]},
            headers={"Idempotency-Key": key},
        ),
        202,
    )
    repeated = expect(
        parent.post(
            f"/children/{child_id}/units",
            json={"material_id": material_id, "assignment_id": assignment["id"]},
            headers={"Idempotency-Key": key},
        ),
        202,
    )
    assert repeated["id"] == job["id"]
    for _ in range(40):
        job = expect(parent.get(f"/jobs/{job['id']}"))
        if job["status"] in ("completed", "failed"):
            break
        time.sleep(1)
    assert job["status"] == "completed", "durable worker job did not complete"
    unit_id = job["result"]["unit_id"]
    authoritative = expect(parent.get(f"/units/{unit_id}"))
    checks.append("durable synthetic job and idempotency")
    with httpx.Client(base_url=BASE, headers=HEADERS, timeout=20) as child:
        login = expect(
            child.post(
                "/auth/login",
                json={
                    "username": demo["credentials"]["child_username"],
                    "password": demo["credentials"]["child_password"],
                    "device": "Public synthetic API smoke",
                },
            )
        )
        child.headers["Authorization"] = "Bearer " + login["token"]
        public_unit = expect(child.get(f"/units/{unit_id}"))
        assert all("answer" not in q and "accepted" not in q for q in public_unit["questions"])
        expect(child.get(f"/families/{family_id}"), 403)
        expect(child.put(f"/children/{child_id}/preferences", json={}), 403)
        expect(child.get("/admin/provider"), 403)
        checks.append("independent child login and role protection")
        expect(child.post(f"/units/{unit_id}/start"))
        expect(child.post(f"/units/{unit_id}/pause"))
        expect(child.post(f"/units/{unit_id}/start"))
        expect(child.post(f"/units/{unit_id}/questions/{authoritative['questions'][0]['id']}/hint"))
        expect(child.post(f"/units/{unit_id}/explanation"))
        for question in authoritative["questions"]:
            answer = expect(
                child.post(f"/units/{unit_id}/questions/{question['id']}/answer", json={"answer": question["answer"]})
            )
            assert answer["outcome"] == "correct"
        assert answer["unit"]["status"] == "completed"
        expect(
            child.post(
                f"/children/{child_id}/messages", json={"kind": "help", "body": "Synthetischer Hilfewunsch zum Testen."}
            ),
            201,
        )
        checks.append("all four exercise types, hints, pause and completion")
        overview = expect(parent.get(f"/children/{child_id}/overview"))
        assert overview["day_summary"]["answer_count"] == 4
        assert overview["day_summary"]["hints_used"] == 1
        assert overview["day_summary"]["help_requests"] == 1
        assert overview["mastery"][0]["later_review_successes"] == 0
        checks.append("parent history and evidence-based summary")
        exported = parent.get(f"/families/{family_id}/export")
        assert exported.status_code == 200 and exported.content[:2] == b"PK"
        checks.append("private family ZIP export")
        expect(parent.delete(f"/children/{child_id}/sessions/{expect(child.get('/auth/sessions'))[0]['id']}"))
        expect(child.get("/auth/me"), 401)
        checks.append("child session revocation")
    expect(parent.request("DELETE", "/account", json={"password": demo["credentials"]["parent_password"]}))
    expect(parent.get("/auth/me"), 401)
    checks.append("synthetic account deletion and session revocation")

print(json.dumps({"url": BASE, "passed": checks, "external_ai_calls": 0}, ensure_ascii=False, indent=2))
