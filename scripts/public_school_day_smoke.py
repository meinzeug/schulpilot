"""Public multi-page AI wizard smoke; only server-owned synthetic notebook pages.

Optional --keep-for-browser stores this test family's credentials in a private,
ignored local artifact so qa/school_day.mjs can inspect the very same package.
No automatic provider retry, fallback, real child data or secret output.
"""

import argparse
import json
from pathlib import Path

import httpx
from public_live_ai_smoke import BASE, HEADERS, expect, job

PRIVATE = Path(__file__).resolve().parents[1] / "artifacts/.school-day-qa-account.json"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--keep-for-browser", action="store_true")
    args = parser.parse_args()
    if PRIVATE.exists():
        raise RuntimeError(
            "A private wizard QA account already exists; resume its browser check before creating another"
        )
    retained = False
    with httpx.Client(base_url=BASE, headers=HEADERS, timeout=30) as parent:
        demo = expect(parent.post("/demo"), 201)
        parent.headers["Authorization"] = "Bearer " + demo["token"]
        child_id = demo["child_id"]
        try:
            with httpx.Client(base_url=BASE, headers=HEADERS, timeout=30) as kid:
                credentials = demo["credentials"]
                login = expect(
                    kid.post(
                        "/auth/login",
                        json={"username": credentials["child_username"], "password": credentials["child_password"]},
                    )
                )
                kid.headers["Authorization"] = "Bearer " + login["token"]
                day = expect(kid.post(f"/children/{child_id}/school-day/today"), 201)
                day = expect(kid.post(f"/school-days/{day['id']}/synthetic-pages"), 201)
                assert len(day["pages"]) == 2
                images = [kid.get(f"/materials/{m['id']}/image").content for m in day["pages"]]
                assert all(image.startswith(b"\xff\xd8") for image in images) and images[0] != images[1]
                expect(kid.put(f"/school-days/{day['id']}/stage", json={"stage": "review"}))
                for page in day["pages"]:
                    job(kid, f"/materials/{page['id']}/extract")
                    page = expect(kid.get(f"/materials/{page['id']}"))
                    assert page["extraction_provider"] == "openrouter" and page["extraction_model"].endswith(":free")
                    assert not page["homework"]
                    expect(
                        kid.put(
                            f"/materials/{page['id']}/confirm",
                            json={
                                **{k: page[k] for k in ("subject", "topic", "content", "homework")},
                                "uncertainties_resolved": True,
                            },
                        )
                    )
                result = job(kid, f"/school-days/{day['id']}/package")
                day = expect(kid.get(f"/children/{child_id}/school-day/today"))["day"]
                assert day["stage"] == "ready" and day["confirmed_count"] == 2
                assert len(day["units"]) == 1 and result["unit_ids"] == [day["units"][0]["id"]]
                unit = day["units"][0]
                assert unit["provider"] == "openrouter" and unit["model"].endswith(":free")
                assert len(unit["source_material_ids"]) == 2 and 2 <= len(unit["questions"]) <= 5
                assert all("answer" not in q for q in unit["questions"])
                pages_text = " ".join(p["content"] for p in day["pages"]).lower()
                assert "nenner" in pages_text and "2/4" in pages_text and "3/6" in pages_text
            overview = expect(parent.get(f"/children/{child_id}/overview"))
            assert overview["school_days"][0]["id"] == day["id"]
            parent_unit = expect(parent.get(f"/units/{unit['id']}"))
            assert all("answer" in q for q in parent_unit["questions"])
            usage = expect(parent.get(f"/families/{demo['user']['families'][0]['id']}/usage"))
            assert usage["calls_used"] == 3 and usage["unknown_cost_calls"] == 0
            assert all(u["cost_micros_usd"] == 0 for u in usage["records"])
            if args.keep_for_browser:
                PRIVATE.write_text(json.dumps({**demo, "school_day_id": day["id"], "package_unit_id": unit["id"]}))
                PRIVATE.chmod(0o600)
                retained = True
            print(
                json.dumps(
                    {
                        "checks": [
                            "own_child_login",
                            "two_distinct_private_synthetic_page_images",
                            "two_real_free_vision_calls",
                            "per_page_confirmation",
                            "one_real_multi_page_package_call",
                            "saved_unit_links_to_both_pages",
                            "parent_overview_and_answer_permissions",
                            "atomic_usage_accounting",
                        ],
                        "ai_calls": usage["calls_used"],
                        "reported_cost_micros_usd": usage["known_cost_micros_usd"],
                        "model": unit["model"],
                        "real_ai_available": expect(parent.get('/status'))['ai_available'],
                        "retained_for_browser": retained,
                    }
                )
            )
        finally:
            if not retained:
                expect(parent.request("DELETE", "/account", json={"password": demo["credentials"]["parent_password"]}))


if __name__ == "__main__":
    main()
