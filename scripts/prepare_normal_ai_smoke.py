"""Prepare a regular verified family for the real child/browser AI workflow.

No /demo or synthetic-fixture API; only original artificial school pages.
Credentials stay in a private ignored file. qa/school_day.mjs deletes the family
on success; --cleanup can remove this same test family after a failed run.
"""

import argparse
import email
import hashlib
import imaplib
import json
import re
import secrets
import ssl
import sys
import time
from email import policy
from pathlib import Path

import httpx
from PIL import Image, ImageDraw, ImageFont
from public_live_ai_smoke import BASE, HEADERS, expect

ROOT = Path(__file__).resolve().parents[1]
PRIVATE = ROOT / "artifacts/.school-day-qa-account.json"


def mail_config():
    sys.path.insert(0, str(ROOT / "deploy"))
    from monitor import environment

    config = environment(Path.home() / ".local/share/schulpilot-operations/monitor.env")
    if config.get("SMTP_HOST") != "smtp.gmail.com":
        raise RuntimeError("The authorized Gmail test mailbox is required")
    return config


def verification(alias):
    config = mail_config()
    deadline = time.monotonic() + 55
    while time.monotonic() < deadline:
        with imaplib.IMAP4_SSL("imap.gmail.com", 993, ssl_context=ssl.create_default_context(), timeout=15) as mailbox:
            mailbox.login(config["SMTP_USER"], config["SMTP_PASSWORD"])
            mailbox.select("INBOX", readonly=True)
            status, data = mailbox.uid("search", None, "HEADER", "To", '"' + alias + '"')
            if status == "OK":
                for uid in data[0].split()[-5:]:
                    _, items = mailbox.uid("fetch", uid, "(BODY.PEEK[])")
                    raw = next((p[1] for p in items if isinstance(p, tuple)), b"")
                    message = email.message_from_bytes(raw, policy=policy.default)
                    if alias.lower() not in str(message.get("To", "")).lower():
                        continue
                    text = "\n".join(p.get_content() for p in message.walk() if p.get_content_type() == "text/plain")
                    match = re.search(
                        re.escape(BASE.removesuffix("/api") + "/verify#token=") + r"([A-Za-z0-9_-]{32,128})", text
                    )
                    if match:
                        return match[1]
        time.sleep(2)
    raise RuntimeError("The verification test mail did not arrive")


def save(data):
    PRIVATE.write_text(json.dumps(data) + "\n")
    PRIVATE.chmod(0o600)


def images():
    font = ImageFont.truetype("DejaVuSans.ttf", 33)
    titles = ImageFont.truetype("DejaVuSans.ttf", 42)
    pages = [
        ["Brüche kürzen", "Zähler und Nenner durch dieselbe Zahl teilen.", "3/9 = 1/3", "6/12 = 1/2"],
        [
            "Brüche erweitern",
            "Zähler und Nenner mit derselben Zahl multiplizieren.",
            "2/3 = 4/6",
            "Der Wert des Bruchs bleibt gleich.",
        ],
    ]
    paths = []
    for index, lines in enumerate(pages, 1):
        image = Image.new("RGB", (1400, 900), "white")
        draw = ImageDraw.Draw(image)
        draw.text((60, 45), "KÜNSTLICHER FUNKTIONSTEST · KEINE KINDERDATEN", font=font, fill="#175b51")
        draw.text((60, 130), "Mathematik · Klasse 6", font=titles, fill="black")
        for number, line in enumerate(lines):
            draw.text((60, 260 + number * 105), line, font=font, fill="black")
        path = ROOT / f"artifacts/normal-school-page-{index}.jpg"
        image.save(path, "JPEG", quality=91)
        paths.append(str(path))
    return paths


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cleanup", action="store_true")
    parser.add_argument("--resume", action="store_true", help="Resume this script's own partially created account")
    parser.add_argument("--paid-synthetic-approved", action="store_true", help="Use only artificial material on the explicitly approved paid OpenRouter route")
    parser.add_argument("--generated-photographs", action="store_true", help="Use the locally inspected artificial notebook photographs")
    args = parser.parse_args()
    photo_paths = [ROOT / "artifacts/everyday-qa/math-addition.png", ROOT / "artifacts/everyday-qa/math-equivalence.png"]
    if args.generated_photographs:
        expected = ["88d93c263fa3e45390932fbe33d4484163b9fb8e8a863b1b07f9d7efe24557ae",
                    "f674b1c53c997f5e50f0d6e2ccc2cf82c89e4255825372909d727f6b67affed2"]
        if any(not path.is_file() or hashlib.file_digest(path.open("rb"), "sha256").hexdigest() != digest
               for path, digest in zip(photo_paths, expected)):
            raise RuntimeError("The two inspected synthetic photographs must match before starting")
    with httpx.Client(base_url=BASE, headers=HEADERS, timeout=30) as parent:
        if args.cleanup:
            data = json.loads(PRIVATE.read_text())
            address = data["credentials"]["parent_username"]
            if not data.get("normal_account") or not re.search(r"\+schulpilot-normal-qa-[a-f0-9]{12}@", address):
                raise RuntimeError("Only this script's own test family may be removed")
            if not data.get("verified"):
                token = verification(address)
                reply = parent.post("/auth/verify", json={"token": token})
                if reply.status_code not in (200, 400):
                    raise RuntimeError("Test-account verification cleanup failed")
            login = expect(
                parent.post(
                    "/auth/login", json={"username": address, "password": data["credentials"]["parent_password"]}
                )
            )
            parent.headers["Authorization"] = "Bearer " + login["token"]
            expect(parent.request("DELETE", "/account", json={"password": data["credentials"]["parent_password"]}))
            PRIVATE.unlink()
            print('{"own_regular_test_family_deleted":true}')
            return
        if args.resume:
            if not PRIVATE.is_file():
                raise RuntimeError("No private QA account to resume")
            data = json.loads(PRIVATE.read_text())
            credentials = data["credentials"]
            if not data.get("normal_account") or not re.search(r"\+schulpilot-normal-qa-[a-f0-9]{12}@", credentials["parent_username"]):
                raise RuntimeError("Only the script's own artificial account may be resumed")
            if not data.get("verified"):
                token_path = PRIVATE.parent / ".qa-verification-token"
                if not token_path.is_file():
                    raise RuntimeError("The test mailbox verification token is not available")
                expect(parent.post("/auth/verify", json={"token": token_path.read_text().strip()}))
                data["verified"] = True
                save(data)
                token_path.unlink()
            login = expect(parent.post("/auth/login", json={"username": credentials["parent_username"], "password": credentials["parent_password"]}))
            parent.headers["Authorization"] = "Bearer " + login["token"]
            user = login["user"]
            if not data.get("child_id"):
                child = expect(parent.post(f"/families/{user['families'][0]['id']}/children", json={
                    "display_name": "Künstliches Testkind", "username": credentials["child_username"],
                    "password": credentials["child_password"], "grade": 6, "subjects": ["Mathematik"]}), 201)
                data["child_id"] = child["id"]
                save(data)
            data["user"] = user
            data["image_paths"] = [str(path) for path in photo_paths] if args.generated_photographs else images()
            save(data)
            print('{"regular_parent_verified_via_real_email":true,"independent_child_created":true,"original_artificial_images":2,"demo_api_used":false}')
            return
        if PRIVATE.exists():
            raise RuntimeError("Resume or clean up the existing private QA account first")
        status = expect(parent.get("/status"))
        if not status["real_data_enabled"] or not status["ai_available"]:
            raise RuntimeError("The approved AI route must have passed its actual operator probe")
        if status["ai_provider"] == "openrouter":
            if status["ai_data_collection"] != "deny" or (not status["ai_free_only"] and not args.paid_synthetic_approved):
                raise RuntimeError("OpenRouter requires data-collection deny and an explicit paid synthetic-test approval")
        elif status["ai_provider"] != "codex":
            raise RuntimeError("Only the explicitly configured Codex or OpenRouter Free route may be tested")
        config = mail_config()
        local, domain = config["SMTP_USER"].split("@", 1)
        if domain.lower() not in ("gmail.com", "googlemail.com"):
            raise RuntimeError("Only the authorized Gmail plus-addresses may be used")
        nonce = secrets.token_hex(6)
        address = local.split("+")[0] + "+schulpilot-normal-qa-" + nonce + "@" + domain
        credentials = {
            "parent_username": address,
            "parent_password": secrets.token_urlsafe(28),
            "child_username": "normal-child-" + nonce,
            "child_password": secrets.token_urlsafe(28),
        }
        expect(
            parent.post(
                "/auth/register",
                json={
                    "email": address,
                    "password": credentials["parent_password"],
                    "display_name": "Synthetischer regulärer KI-Test",
                    "family_name": "Regulärer KI-Test mit künstlichem Schulstoff",
                    "adult_consent": True,
                },
            ),
            201,
        )
        data = {"normal_account": True, "credentials": credentials, "verified": False}
        save(data)
        expect(parent.post("/auth/verify", json={"token": verification(address)}))
        data["verified"] = True
        save(data)
        login = expect(
            parent.post("/auth/login", json={"username": address, "password": credentials["parent_password"]})
        )
        parent.headers["Authorization"] = "Bearer " + login["token"]
        user = login["user"]
        assert len(user["families"]) == 1 and user["families"][0]["synthetic"] is False
        child = expect(
            parent.post(
                f"/families/{user['families'][0]['id']}/children",
                json={
                    "display_name": "Künstliches Testkind",
                    "username": credentials["child_username"],
                    "password": credentials["child_password"],
                    "grade": 6,
                    "subjects": ["Mathematik"],
                },
            ),
            201,
        )
        if args.generated_photographs:
            image_paths = [str(path) for path in photo_paths]
        else:
            image_paths = images()
        data.update({"user": user, "child_id": child["id"], "image_paths": image_paths})
        save(data)
        print(
            '{"regular_parent_verified_via_real_email":true,"independent_child_created":true,"original_artificial_images":2,"demo_api_used":false}'
        )


if __name__ == "__main__":
    main()
