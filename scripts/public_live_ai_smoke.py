"""Real public HTTPS + free-only AI, fixed synthetic image to saved child work.

Creates and deletes only its own test family. No credentials/answers printed.
No automatic inference retries or model fallback.
"""

import json
import re
import time
import uuid

import httpx

BASE = "https://schulpilot.dorfspy.de/api"
HEADERS = {"X-Schulpilot-Request": "1", "X-Client-Platform": "native"}


def expect(response, status=200):
    if response.status_code != status:
        raise RuntimeError(f"{response.request.url.path}: HTTP {response.status_code}, expected {status}")
    return response.json()


def job(client, path, body=None):
    queued = expect(client.post(path, json=body, headers={"Idempotency-Key": uuid.uuid4().hex}), 202)
    for _ in range(150):
        state = expect(client.get("/jobs/" + queued["id"]))
        if state["status"] == "completed":
            return state["result"]
        if state["status"] == "failed":
            raise RuntimeError("Live fixture job failed: " + str(state["error"]))
        time.sleep(1)
    raise RuntimeError("Job timeout; no request was replayed")


def main():
    checks = []
    with httpx.Client(base_url=BASE, headers=HEADERS, timeout=30) as parent:
        status = expect(parent.get("/status"))
        assert status["synthetic_ai_available"] is True
        demo = expect(parent.post("/demo"), 201)
        parent.headers["Authorization"] = "Bearer " + demo["token"]
        child_id = demo["child_id"]
        family_id = demo["user"]["families"][0]["id"]
        try:
            material = expect(parent.post(f"/children/{child_id}/materials/synthetic-fixture"), 201)
            image = parent.get(f"/materials/{material['id']}/image")
            assert image.status_code == 200 and image.content.startswith(b"\xff\xd8")
            job(parent, f"/materials/{material['id']}/extract")
            material = expect(parent.get(f"/materials/{material['id']}"))
            assert material["extraction_provider"] == "openrouter" and material["extraction_model"].endswith(":free")
            content = material["content"].lower()
            assert "nenner" in content and re.search("z(?:ä|ae)hler", content) and "3/4" in content
            assert not material["homework"]
            checks.append("real_free_vision_extraction_of_server_owned_image")
            expect(
                parent.put(
                    f"/materials/{material['id']}/confirm",
                    json={
                        **{k: material[k] for k in ("subject", "topic", "content", "homework")},
                        "uncertainties_resolved": True,
                    },
                )
            )
            unit_id = job(parent, f"/children/{child_id}/units", {"material_id": material["id"]})["unit_id"]
            unit = expect(parent.get("/units/" + unit_id))
            assert unit["provider"] == "openrouter" and unit["model"].endswith(":free")
            assert 2 <= len(unit["questions"]) <= 5
            checks.append("confirmed_material_to_real_validated_ai_unit")
            with httpx.Client(base_url=BASE, headers=HEADERS, timeout=30) as child:
                credentials = demo["credentials"]
                login = expect(
                    child.post(
                        "/auth/login",
                        json={"username": credentials["child_username"], "password": credentials["child_password"]},
                    )
                )
                child.headers["Authorization"] = "Bearer " + login["token"]
                assert child.get("/families/" + family_id).status_code == 403
                child_unit = expect(child.get("/units/" + unit_id))
                assert all("answer" not in q and "accepted" not in q for q in child_unit["questions"])
                expect(child.post("/units/" + unit_id + "/start"))
                for index, question in enumerate(unit["questions"]):
                    path = f"/units/{unit_id}/questions/{question['id']}"
                    if index == 0:
                        expect(child.post(path + "/hint"))
                    result = expect(child.post(path + "/answer", json={"answer": question["answer"]}))
                    assert result["outcome"] == "correct"
                assert expect(child.get("/units/" + unit_id))["status"] == "completed"
            overview = expect(parent.get(f"/children/{child_id}/overview"))
            assert overview["day_summary"]["completed_units"] == 1
            assert overview["day_summary"]["answer_count"] == len(unit["questions"])
            assert overview["day_summary"]["hints_used"] == 1
            checks.append("independent_child_login_answers_hint_and_parent_history_persisted")
            usage = expect(parent.get(f"/families/{family_id}/usage"))
            assert usage["calls_used"] == 2 and usage["unknown_cost_calls"] == 0
            assert len(usage["records"]) == 2 and all(u["cost_micros_usd"] == 0 for u in usage["records"])
            assert {u["function"] for u in usage["records"]} == {"extract", "unit"}
            report = {
                "checks": checks,
                "models": {"extract": material["extraction_model"], "unit": unit["model"]},
                "ai_calls": usage["calls_used"],
                "reported_cost_micros_usd": usage["known_cost_micros_usd"],
                "real_child_data_gate": "closed",
                "synthetic_only": True,
            }
        finally:
            expect(parent.request("DELETE", "/account", json={"password": demo["credentials"]["parent_password"]}))
        checks.append("own_test_family_and_uploaded_fixture_deleted")
        print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
