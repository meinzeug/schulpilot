"""Own artificial photo album: normal uploads, two reserved OCR jobs, no attempts.

Needs the regular verified household from prepare_normal_ai_smoke.py. Never
changes provider limits or writes directly to the production database.
"""

import io
import json
import re
import subprocess
import sys
import time
from pathlib import Path

import httpx
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
PRIVATE = ROOT / "artifacts/.school-day-qa-account.json"
BASE = "https://schulpilot.dorfspy.de/api"


def save(account):
    PRIVATE.write_text(json.dumps(account) + "\n")
    PRIVATE.chmod(0o600)


def expect(response, status=200):
    if response.status_code != status:
        raise RuntimeError(f"Owned album preparation HTTP{response.status_code}, expected{status}")
    return response.json()


def main():
    if not PRIVATE.exists():
        subprocess.run([sys.executable, str(ROOT / "scripts/prepare_normal_ai_smoke.py")], cwd=ROOT, check=True)
    account = json.loads(PRIVATE.read_text())
    if not (account.get("normal_account") and account.get("verified") and
            re.search(r"\+schulpilot-normal-qa-[a-f0-9]{12}@", account["credentials"]["parent_username"])):
        raise RuntimeError("Only the own artificial verified household is allowed")
    state = account.setdefault("notebook_qa", {"materials": [], "jobs": {}, "confirmed": [], "phase": "preparing"})
    headers = {"X-Schulpilot-Request": "1", "X-Client-Platform": "native"}
    with httpx.Client(base_url=BASE, headers=headers, timeout=45) as api:
        signed = expect(api.post("/auth/login", json={"username": account["credentials"]["parent_username"],
                                                       "password": account["credentials"]["parent_password"]}))
        if signed["user"]["id"] != account["user"]["id"]:
            raise RuntimeError("Owned parent identity mismatch")
        api.headers["Authorization"] = "Bearer " + signed["token"]
        for n in range(len(state["materials"]), 26):
            if n < 2:
                raw = Path(account["image_paths"][n]).read_bytes()
            else:
                image = Image.new("RGB", (900, 1250), "white")
                draw = ImageDraw.Draw(image)
                font = ImageFont.truetype("DejaVuSans.ttf", 30)
                draw.text((45, 80), "KÜNSTLICHER ALBUMTEST", font=font, fill="#14243d")
                draw.text((45, 170), f"Ablageblatt {n + 1}", font=font, fill="black")
                draw.text((45, 260), "Keine echten Kinderdaten.", font=font, fill="black")
                output = io.BytesIO()
                image.save(output, "JPEG", quality=88)
                raw = output.getvalue()
            result = expect(api.post(f"/children/{account['child_id']}/materials",
                files={"file": ("artificial-album-page.jpg", raw, "image/jpeg")},
                headers={"Idempotency-Key": f"owned-album-photo-{n:04}-v1"}), 201)
            state["materials"].append(result["id"])
            save(account)
        for material_id in state["materials"][:2]:
            if material_id in state["confirmed"]:
                continue
            if material_id not in state["jobs"]:
                job = expect(api.post(f"/materials/{material_id}/extract",
                    headers={"Idempotency-Key": f"owned-album-ocr-{material_id}"}), 202)
                state["jobs"][material_id] = job["id"]
                save(account)
            deadline = time.monotonic() + 210
            while time.monotonic() < deadline:
                job = expect(api.get('/jobs/' + state["jobs"][material_id]))
                if job["status"] == "failed":
                    raise RuntimeError("Owned OCR failed; checkpoint retained, no automatic retry")
                if job["status"] == "completed":
                    break
                time.sleep(2)
            else:
                raise RuntimeError("Owned OCR still pending; checkpoint retained")
            material = expect(api.get('/materials/' + material_id))
            if material["status"] != "review" or not material["content"].strip():
                raise RuntimeError("Owned actual OCR review required")
            expect(api.put(f"/materials/{material_id}/confirm", json={
                "revision": material["revision"], "subject": "Mathematik", "topic": material["topic"],
                "content": material["content"], "homework": material["homework"], "uncertainties_resolved": True,
            }))
            state["confirmed"].append(material_id)
            save(account)
        state["phase"] = "prepared"
        save(account)
        expect(api.post('/auth/logout'))
    print(json.dumps({"own_artificial_family": True, "actual_uploaded_photos": 26,
        "normal_reserved_ocr_jobs": 2, "confirmed_math_pages": 2, "unassigned_pages": 24,
        "database_injection": False, "invented_attempts": 0}), flush=True)


if __name__ == "__main__":
    main()
