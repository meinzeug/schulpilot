"""One neutral operator-mailbox alarm test, verified via read-only Gmail IMAP.

Reads only the explicitly authorized project SMTP settings, searches the unique
test subject, and never prints credentials, mailbox addresses or message bodies.
"""

import argparse
import imaplib
import secrets
import ssl
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "deploy"))
from monitor import environment, notify  # noqa: E402


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--config-file", type=Path, default=Path.home() / ".local/share/schulpilot-operations/monitor.env"
    )
    args = parser.parse_args()
    config = environment(args.config_file)
    if config.get("SMTP_HOST") != "smtp.gmail.com" or not config.get("SMTP_USER"):
        raise RuntimeError("The authorized Gmail transport is required")
    token = secrets.token_hex(12)
    config["OPERATIONS_ALERT_EMAIL"] = config["SMTP_USER"]
    config["ALERT_TEST_TOKEN"] = token
    with tempfile.TemporaryDirectory(prefix="schulpilot-alert-test-") as directory:
        result = notify(config, ["explicit_synthetic_alarm_test"], {}, Path(directory) / "state.json")
        if not result.get("sent") or result.get("alert_error"):
            raise RuntimeError("Alarm transport did not acknowledge the message")
    found = False
    with imaplib.IMAP4_SSL("imap.gmail.com", 993, ssl_context=ssl.create_default_context(), timeout=15) as mailbox:
        mailbox.login(config["SMTP_USER"], config["SMTP_PASSWORD"])
        mailbox.select("INBOX", readonly=True)
        for _ in range(10):
            status, data = mailbox.search(None, "HEADER", "Subject", '"TEST SCHULPILOT Alarmtest ' + token + '"')
            if status == "OK" and data[0].split():
                status, body = mailbox.fetch(data[0].split()[-1], "(BODY.PEEK[])")
                found = status == "OK" and any(isinstance(item, tuple) and token.encode() in item[1] for item in body)
                if found:
                    break
            time.sleep(2)
    if not found:
        raise RuntimeError("No matching alarm test message received")
    print('{"operator_alarm_test_delivered":true,"read_only_imap":true,"child_data_used":false}')


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        raise SystemExit("Operator alarm test failed: " + type(error).__name__) from None
