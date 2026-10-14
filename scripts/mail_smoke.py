"""End-to-end mail test using only new plus-addresses of the authorized inbox.

Never prints credentials, addresses, links or tokens. Read-only IMAP reads only
messages addressed to the cryptographically random test alias of this run.
"""

import argparse
import email
import imaplib
import json
import os
import re
import secrets
import ssl
import subprocess
import sys
import time
from email import policy
from pathlib import Path

import httpx


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--browser", action="store_true", help="Submit actual mail links through the Flutter web forms")
    args = parser.parse_args()
    public = os.getenv("PUBLIC_URL", "https://schulpilot.dorfspy.de").rstrip("/")
    inbox_user = os.getenv("TEST_IMAP_USER")
    inbox_password = os.getenv("TEST_IMAP_PASSWORD")
    if not inbox_user or not inbox_password:
        sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "deploy"))
        from monitor import environment

        config = environment(Path.home() / ".local/share/schulpilot-operations/monitor.env")
        inbox_user, inbox_password = config["SMTP_USER"], config["SMTP_PASSWORD"]
    local, domain = inbox_user.split("@", 1)
    if domain.lower() not in ("gmail.com", "googlemail.com"):
        raise SystemExit("This test is restricted to authorized Gmail plus-addresses")
    suffix = secrets.token_hex(6)
    parent_email = local.split("+")[0] + "+schulpilot-qa-" + suffix + "@" + domain
    guest_email = local.split("+")[0] + "+schulpilot-guest-" + suffix + "@" + domain
    password, recovered, guest_password = [secrets.token_urlsafe(25) for _ in range(3)]
    headers = {"X-Schulpilot-Request": "1", "X-Client-Platform": "native"}
    checks = []

    def browser_link(route, token, new_password=None):
        result = subprocess.run(
            ["node", "auth_link.mjs"],
            cwd=Path(__file__).resolve().parents[1] / "qa",
            input=json.dumps({"public_url": public, "route": route, "token": token, "password": new_password}),
            text=True,
            capture_output=True,
            timeout=100,
        )
        if result.returncode:
            try:
                step = json.loads(result.stderr).get("step")
            except (ValueError, AttributeError):
                step = None
            allowed = {"input", "launch", "open", "form", "prefill", "reload", "fields", "submit"}
            raise RuntimeError("Email-link browser check failed at " + (step if step in allowed else "unknown step"))
        report = json.loads(result.stdout)
        if not report.get("prefill") or not report.get("reload") or not report.get("form_submitted"):
            raise RuntimeError("Incomplete email-link browser check")
        checks.append(route + "_browser_prefill_reload_and_form_submission")

    def received(alias, route):
        deadline = time.monotonic() + 50
        while time.monotonic() < deadline:
            with imaplib.IMAP4_SSL("imap.gmail.com", 993, ssl_context=ssl.create_default_context(), timeout=15) as imap:
                imap.login(inbox_user, inbox_password)
                imap.select("INBOX", readonly=True)
                status, matches = imap.uid("search", None, "HEADER", "To", '"' + alias + '"')
                if status == "OK":
                    for uid in matches[0].split()[-8:]:
                        _, parts = imap.uid("fetch", uid, "(BODY.PEEK[])")
                        raw = next((p[1] for p in parts if isinstance(p, tuple)), b"")
                        message = email.message_from_bytes(raw, policy=policy.default)
                        if alias.lower() not in str(message.get("To", "")).lower():
                            continue
                        content = "\n".join(
                            p.get_content() for p in message.walk() if p.get_content_type() == "text/plain"
                        )
                        match = re.search(
                            re.escape(public + "/" + route + "#token=") + r"([A-Za-z0-9_-]{32,128})", content
                        )
                        if match:
                            return match[1]
            time.sleep(2)
        raise RuntimeError("Expected test email did not arrive in the authorized inbox within 50 seconds")

    def checked(client, method, path, body=None, expected=200):
        response = client.request(method, public + "/api" + path, json=body)
        if response.status_code != expected:
            raise RuntimeError("Unexpected status " + str(response.status_code) + " for " + path)
        return response.json()

    with (
        httpx.Client(headers=headers, timeout=30) as parent,
        httpx.Client(headers=headers, timeout=30) as guest,
        httpx.Client(headers=headers, timeout=30) as child,
    ):
        parent_created = guest_created = False
        verify_token = None
        try:
            checked(
                parent,
                "POST",
                "/auth/register",
                {
                    "email": parent_email,
                    "password": password,
                    "display_name": "Synthetischer SMTP-Test",
                    "family_name": "SMTP-Testfamilie",
                    "adult_consent": True,
                },
                201,
            )
            parent_created = True
            verify_token = received(parent_email, "verify")
            if args.browser:
                browser_link("verify", verify_token)
            else:
                checked(parent, "POST", "/auth/verify", {"token": verify_token})
            checked(parent, "POST", "/auth/verify", {"token": verify_token}, 400)
            logged = checked(parent, "POST", "/auth/login", {"username": parent_email, "password": password})
            parent.headers["Authorization"] = "Bearer " + logged["token"]
            fid = logged["user"]["families"][0]["id"]
            checks.append("registration_mail_received_and_one_time_verification")
            kid = checked(
                parent,
                "POST",
                "/families/" + fid + "/children",
                {
                    "display_name": "Synthetisches Testkind",
                    "username": "smtp-child-" + suffix,
                    "password": guest_password,
                    "grade": 6,
                    "subjects": ["Mathematik"],
                },
                201,
            )
            logged_child = checked(
                child, "POST", "/auth/login", {"username": "smtp-child-" + suffix, "password": guest_password}
            )
            child.headers["Authorization"] = "Bearer " + logged_child["token"]
            checked(child, "GET", "/families/" + fid, expected=403)
            checks.append("independent_child_login_and_parent_area_denied")
            checked(
                parent, "POST", "/families/" + fid + "/invitations", {"email": guest_email, "permission": "view"}, 201
            )
            token = received(guest_email, "invite")
            if args.browser:
                browser_link("invite", token, guest_password)
            else:
                checked(
                    guest,
                    "POST",
                    "/invitations/accept",
                    {
                        "token": token,
                        "password": guest_password,
                        "display_name": "Synthetischer eingeladener Elternteil",
                    },
                )
            guest_created = True
            logged_guest = checked(guest, "POST", "/auth/login", {"username": guest_email, "password": guest_password})
            guest.headers["Authorization"] = "Bearer " + logged_guest["token"]
            checked(guest, "GET", "/families/" + fid)
            checked(guest, "PUT", "/children/" + kid["id"] + "/preferences", {}, 403)
            members = checked(parent, "GET", "/families/" + fid + "/members")
            mid = next(m["id"] for m in members if not m["self"])
            checked(parent, "DELETE", "/families/" + fid + "/members/" + mid)
            checked(guest, "GET", "/families/" + fid, expected=401)
            checks.append("invitation_mail_received_view_rights_and_revocation")
            checked(parent, "POST", "/auth/recovery", {"email": parent_email})
            token = received(parent_email, "reset")
            if args.browser:
                browser_link("reset", token, recovered)
            else:
                checked(parent, "POST", "/auth/reset", {"token": token, "password": recovered})
            password = recovered
            checked(parent, "GET", "/auth/me", expected=401)
            logged = checked(parent, "POST", "/auth/login", {"username": parent_email, "password": password})
            parent.headers["Authorization"] = "Bearer " + logged["token"]
            checks.append("recovery_mail_received_password_changed_sessions_revoked")
        finally:
            if parent_created and verify_token:
                # A browser assertion can fail before submission. Verify only
                # this run's account so its cleanup remains possible.
                parent.post(public + "/api/auth/verify", json={"token": verify_token})
            # Delete only accounts whose unique aliases were created in this run.
            for client, address, secret, created in [
                (guest, guest_email, guest_password, guest_created),
                (parent, parent_email, password, parent_created),
            ]:
                if created:
                    login = checked(client, "POST", "/auth/login", {"username": address, "password": secret})
                    client.headers["Authorization"] = "Bearer " + login["token"]
                    checked(client, "DELETE", "/account", {"password": secret})
            checks.append("test_accounts_and_child_data_deleted")
    print(
        json.dumps(
            {"public_https": public, "checks": checks, "mail_inbox_receipt_verified": True, "synthetic_only": True}
        )
    )


if __name__ == "__main__":
    main()
