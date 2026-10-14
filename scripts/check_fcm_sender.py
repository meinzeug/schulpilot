"""Authenticate the dedicated sender and validate a fixed artificial target.

Never delivers a message, accepts no device token and prints no credentials.
Run on the server if the development machine's clock is inaccurate.
"""

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

import httpx
from google.auth.transport.requests import Request
from google.oauth2 import service_account

PROJECT = "schulpilot-f6bf3"
SENDER = f"schulpilot-fcm-sender@{PROJECT}.iam.gserviceaccount.com"


class TimedRequest(Request):
    def __call__(self, *args, **kwargs):
        kwargs["timeout"] = 20
        return super().__call__(*args, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--credential-file",
        type=Path,
        default=Path.home() / ".local/share/schulpilot-firebase/fcm-service-account.json",
    )
    args = parser.parse_args()
    result = {
        "checked_at_utc": datetime.now(timezone.utc).isoformat(),
        "project_id": PROJECT,
        "service_account_oauth": False,
        "validate_only": "not_performed",
        "visible_delivery": "not_observed",
    }
    try:
        raw = json.loads(args.credential_file.read_text())
        if (
            raw.get("type") != "service_account"
            or raw.get("project_id") != PROJECT
            or raw.get("client_email") != SENDER
            or raw.get("token_uri") != "https://oauth2.googleapis.com/token"
        ):
            raise ValueError("UNEXPECTED_SENDER_IDENTITY")
        credentials = service_account.Credentials.from_service_account_info(
            raw, scopes=["https://www.googleapis.com/auth/firebase.messaging"]
        )
        credentials.refresh(TimedRequest())
        result["service_account_oauth"] = bool(credentials.valid)
        response = httpx.post(
            f"https://fcm.googleapis.com/v1/projects/{PROJECT}/messages:send",
            timeout=20,
            follow_redirects=False,
            headers={"Authorization": "Bearer " + credentials.token},
            json={
                "validate_only": True,
                "message": {
                    "topic": "schulpilot-synthetic-validation",
                    "notification": {"title": "SCHULPILOT", "body": "Synthetische Validierung"},
                },
            },
        )
        result["validate_only_http"] = response.status_code
        result["validation_target"] = "fixed_synthetic_topic_validate_only"
        result["validate_only"] = "validated" if response.status_code == 200 else "rejected"
        if response.status_code != 200:
            value = response.json().get("error", {}).get("status", "UNKNOWN")
            result["error"] = (
                value
                if value in ("INVALID_ARGUMENT", "UNAUTHENTICATED", "PERMISSION_DENIED", "NOT_FOUND", "UNAVAILABLE")
                else "FCM_ERROR"
            )
    except Exception as error:
        message = str(error).lower()
        result["error"] = (
            "LOCAL_CLOCK_SKEW"
            if any(text in message for text in ("iat", "short-lived", "timeframe"))
            else type(error).__name__
        )
    print(json.dumps(result))
    return 0 if result["service_account_oauth"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
