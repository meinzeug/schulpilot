"""Project-locked Google preflight and optional minimal FCM sender setup.

Requires the operator's normal gcloud browser login. No ADC, token output,
second Firebase project, app creation, billing change or key restriction reset.
Reports contain metadata only; credentials stay in a private directory.
"""

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import time
from email.utils import parsedate_to_datetime
from pathlib import Path

import httpx

PROJECT = "schulpilot-f6bf3"
NUMBER = "460657028995"
ACCOUNT = "gvhindenburg@gmail.com"
SENDER = f"schulpilot-fcm-sender@{PROJECT}.iam.gserviceaccount.com"
ANDROID = "1:460657028995:android:9475b4497b0c9de08590b6"
WEB = "1:460657028995:web:67373b18092ab46f8590b6"
PERMISSION = "cloudmessaging.messages.create"
APIS = ("fcm.googleapis.com", "fcmregistrations.googleapis.com", "firebaseinstallations.googleapis.com")
ROOT = Path.home() / ".local/share/schulpilot-firebase"


class CloudError(Exception):
    def __init__(self, response):
        self.status = response.status_code
        try:
            raw = response.json().get("error", {})
        except ValueError:
            raw = {}
        self.reason = raw.get("status", "HTTP_ERROR")
        self.details = [
            {
                "reason": item.get("reason"),
                "metadata": {
                    k: v
                    for k, v in item.get("metadata", {}).items()
                    if k in ("service", "consumer", "permission", "resource")
                },
            }
            for item in raw.get("details", [])
            if item.get("@type", "").endswith("ErrorInfo")
        ]
        self.policies = sorted(
            set(re.findall(r"(?:constraints/)?(?:iam\.[A-Za-z.]+|iam\.managed\.[A-Za-z.]+)", json.dumps(raw)))
        )
        super().__init__(f"Google HTTP {self.status}: {self.reason} " + json.dumps(self.details))


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    path.parent.chmod(0o700)
    temporary = path.with_name(path.name + ".new")
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w") as output:
        json.dump(value, output, indent=2, ensure_ascii=False)
        output.write("\n")
    temporary.chmod(0o600)
    temporary.replace(path)


def credential_valid(raw):
    return all(
        (
            raw.get("type") == "service_account",
            raw.get("project_id") == PROJECT,
            raw.get("client_email") == SENDER,
            raw.get("token_uri") == "https://oauth2.googleapis.com/token",
            bool(raw.get("private_key")),
        )
    )


class Google:
    def __init__(self, gcloud):
        env = {**os.environ, "CLOUDSDK_CONFIG": str(ROOT / "gcloud"), "CLOUDSDK_CORE_DISABLE_USAGE_REPORTING": "true"}
        result = subprocess.run(
            [str(gcloud), "auth", "list", "--format=json"], env=env, capture_output=True, text=True, timeout=30
        )
        if result.returncode or not any(x.get("account") == ACCOUNT for x in json.loads(result.stdout or "[]")):
            raise RuntimeError("Google-Browseranmeldung für gvhindenburg@gmail.com fehlt.")
        result = subprocess.run(
            [str(gcloud), "auth", "print-access-token", "--account=" + ACCOUNT],
            env=env,
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode:
            raise RuntimeError("Google-Anmeldung muss im offiziellen Browserdialog erneuert werden.")
        self.client = httpx.Client(
            headers={"Authorization": "Bearer " + result.stdout.strip(), "X-Goog-User-Project": PROJECT},
            timeout=25,
            follow_redirects=False,
        )

    def call(self, method, url, body=None, absent=False):
        result = self.client.request(method, "https://" + url, json=body)
        if result.headers.get("date"):
            self.server_time = parsedate_to_datetime(result.headers["date"]).isoformat()
        if absent and result.status_code == 404:
            return None
        if result.status_code >= 400:
            raise CloudError(result)
        return result.json() if result.content else {}

    def wait(self, operation):
        name = operation.get("name")
        if not name:
            raise RuntimeError("Google lieferte keinen prüfbaren Operationsnamen.")
        for _ in range(20):
            result = self.call("GET", "serviceusage.googleapis.com/v1/" + name)
            if result.get("done"):
                if result.get("error"):
                    raise RuntimeError("Aktivieren einer erforderlichen Projekt-API wurde abgelehnt.")
                return
            time.sleep(1)
        raise RuntimeError(
            "API-Aktivierung läuft noch. Prüfung erneut ausführen; keine doppelte Ressource erforderlich."
        )


def inspect(google, report, configure):
    project = google.call("GET", f"cloudresourcemanager.googleapis.com/v3/projects/{PROJECT}")
    if project.get("projectId") != PROJECT or project.get("name") != "projects/" + NUMBER:
        raise RuntimeError("Projektidentität stimmt nicht. Keine Änderung vorgenommen.")
    report["project_verified"] = True
    firebase = google.call("GET", f"firebase.googleapis.com/v1beta1/projects/{PROJECT}")
    report["firebase_project_verified"] = (
        firebase.get("projectId") == PROJECT and str(firebase.get("projectNumber")) == NUMBER
    )
    apps = {}
    for platform, appid in (("android", ANDROID), ("web", WEB)):
        listing = google.call("GET", f"firebase.googleapis.com/v1beta1/projects/{PROJECT}/{platform}Apps")
        app = next((item for item in listing.get("apps", []) if item.get("appId") == appid), None)
        if not app or (platform == "android" and app.get("packageName") != "de.dorfspy.schulpilot"):
            raise RuntimeError("Die vorgegebene Firebase-App ist nicht bestätigt; es wird keine neue App angelegt.")
        apps[platform] = {"app_id": appid, "verified": True}
    report["apps"] = apps
    report["apis"] = {}
    for api in APIS:
        resource = f"serviceusage.googleapis.com/v1/projects/{NUMBER}/services/{api}"
        status = google.call("GET", resource)
        if status.get("state") != "ENABLED" and configure:
            google.wait(google.call("POST", resource + ":enable", {}))
            status = google.call("GET", resource)
        report["apis"][api] = status.get("state", "UNKNOWN")
    report["management_apis"] = {}
    for api in ("apikeys.googleapis.com", "iam.googleapis.com"):
        resource = f"serviceusage.googleapis.com/v1/projects/{NUMBER}/services/{api}"
        status = google.call("GET", resource)
        if status.get("state") != "ENABLED" and configure:
            google.wait(google.call("POST", resource + ":enable", {}))
            status = google.call("GET", resource)
        report["management_apis"][api] = status.get("state", "UNKNOWN")
    config_path = ROOT / "firebase-public-config.json"
    public = json.loads(config_path.read_text())
    web = google.call("GET", f"firebase.googleapis.com/v1beta1/projects/{PROJECT}/webApps/{WEB}/config")
    android = google.call("GET", f"firebase.googleapis.com/v1beta1/projects/{PROJECT}/androidApps/{ANDROID}/config")
    native = json.loads(base64.b64decode(android["configFileContents"]))
    native_client = next(item for item in native["client"] if item["client_info"]["mobilesdk_app_id"] == ANDROID)
    native_key = native_client["api_key"][0]["current_key"]
    if web.get("apiKey") != public.get("apiKey") or web.get("appId") != WEB or public.get("androidAppId") != ANDROID:
        raise RuntimeError("Öffentliche Vorgaben und aktuelle Firebase-Web-Konfiguration stimmen nicht überein.")
    public["androidApiKey"] = native_key
    keys, page = [], ""
    while True:
        response = google.call(
            "GET",
            f"apikeys.googleapis.com/v2/projects/{NUMBER}/locations/global/keys?pageSize=100"
            + ("&pageToken=" + page if page else ""),
        )
        keys.extend(response.get("keys", []))
        page = response.get("nextPageToken", "")
        if not page:
            break
    report["key_restrictions"] = {}
    for platform, value in (("web", public["apiKey"]), ("android", native_key)):
        matching = None
        for key in keys:
            key_value = google.call("GET", "apikeys.googleapis.com/v2/" + key["name"] + "/keyString").get("keyString")
            if key_value == value:
                matching = key
                break
        if not matching:
            raise RuntimeError("Die tatsächlichen API-Key-Einschränkungen konnten nicht zugeordnet werden.")
        restrictions = matching.get("restrictions", {})
        wrong_platform = (
            platform == "web" and ("androidKeyRestrictions" in restrictions or "iosKeyRestrictions" in restrictions)
        ) or (
            platform == "android" and ("browserKeyRestrictions" in restrictions or "iosKeyRestrictions" in restrictions)
        )
        targets = restrictions.get("apiTargets", [])
        services = {item.get("service") for item in targets}
        required = (
            {"firebaseinstallations.googleapis.com", "fcmregistrations.googleapis.com"}
            if platform == "web"
            else {"firebaseinstallations.googleapis.com"}
        )
        missing = sorted(required - services) if targets else []
        methods_limited = any(item.get("methods") for item in targets if item.get("service") in required)
        report["key_restrictions"][platform] = {
            "key_resource": matching["name"],
            "restrictions": restrictions,
            "wrong_platform": bool(wrong_platform),
            "missing_required_apis": missing,
            "methods_require_review": methods_limited,
            "application_restriction_review": "serverKeyRestrictions" in restrictions
            or (platform == "android" and "androidKeyRestrictions" in restrictions)
            or (platform == "web" and "browserKeyRestrictions" in restrictions),
        }
    save(config_path, public)
    report["separate_platform_keys"] = public["apiKey"] != native_key
    report["restrictions_changed"] = False


def sender(google, report, configure, authenticate=True):
    base = f"iam.googleapis.com/v1/projects/{PROJECT}"
    resource = base + "/serviceAccounts/" + SENDER
    account = google.call("GET", resource, absent=True)
    if not account and configure:
        account = google.call(
            "POST",
            base + "/serviceAccounts",
            {
                "accountId": "schulpilot-fcm-sender",
                "serviceAccount": {
                    "displayName": "SCHULPILOT FCM sender",
                    "description": "Only HTTP v1 push sending for SCHULPILOT; no Firebase Admin SDK privileges.",
                },
            },
        )
    report["sender_email"] = account.get("email") if account else None
    if not account:
        return
    if account.get("disabled"):
        raise RuntimeError("Das dedizierte Senderkonto ist deaktiviert.")
    role_name = f"projects/{PROJECT}/roles/schulpilotFcmSender"
    role = google.call("GET", "iam.googleapis.com/v1/" + role_name, absent=True)
    if not role and configure:
        role = google.call(
            "POST",
            base + "/roles",
            {
                "roleId": "schulpilotFcmSender",
                "role": {
                    "title": "SCHULPILOT FCM sender",
                    "description": "Send FCM HTTP v1 messages only",
                    "stage": "GA",
                    "includedPermissions": [PERMISSION],
                },
            },
        )
    if role and (set(role.get("includedPermissions", [])) != {PERMISSION} or role.get("deleted")):
        raise RuntimeError("Die vorhandene eigene Senderrolle hat andere Rechte. Keine fremde Rolle verändert.")
    policy_url = f"cloudresourcemanager.googleapis.com/v1/projects/{PROJECT}"
    policy = google.call("POST", policy_url + ":getIamPolicy", {"options": {"requestedPolicyVersion": 3}})
    member = "serviceAccount:" + SENDER
    bindings = policy.get("bindings", [])
    granted = [b["role"] for b in bindings if member in b.get("members", [])]
    if configure and role_name not in granted:
        binding = next((b for b in bindings if b["role"] == role_name and not b.get("condition")), None)
        if binding:
            binding["members"].append(member)
        else:
            bindings.append({"role": role_name, "members": [member]})
        policy["bindings"] = bindings
        google.call("POST", policy_url + ":setIamPolicy", {"policy": policy})
        policy = google.call("POST", policy_url + ":getIamPolicy", {"options": {"requestedPolicyVersion": 3}})
        granted = [b["role"] for b in policy.get("bindings", []) if member in b.get("members", [])]
    report["sender_roles"] = granted
    report["sender_permissions"] = role.get("includedPermissions", []) if role else []
    if set(granted) - {role_name, "roles/firebasecloudmessaging.admin"}:
        raise RuntimeError("Das dedizierte Senderkonto hat zusätzliche Projektrollen. Vor Nutzung gezielt prüfen.")
    key_path = ROOT / "fcm-service-account.json"
    remote_keys = google.call("GET", resource + "/keys?keyTypes=USER_MANAGED").get("keys", [])
    report["existing_user_managed_keys"] = len(remote_keys)
    if not key_path.exists() and configure:
        created = google.call(
            "POST",
            resource + "/keys",
            {"privateKeyType": "TYPE_GOOGLE_CREDENTIALS_FILE", "keyAlgorithm": "KEY_ALG_RSA_2048"},
        )
        raw = json.loads(base64.b64decode(created["privateKeyData"]))
        if not credential_valid(raw):
            raise RuntimeError("Unerwartete Dienstkontoidentität. Schlüssel wird nicht verwendet.")
        save(key_path, raw)
        report["key_created"] = True
    if key_path.exists():
        raw = json.loads(key_path.read_text())
        if not credential_valid(raw):
            raise RuntimeError("Die lokale private Datei gehört nicht zum dedizierten Senderkonto.")
        key_path.chmod(0o600)
        report["local_credential_validated"] = True
        if not authenticate:
            report["local_authentication_skipped"] = True
            return
        from google.auth.transport.requests import Request
        from google.oauth2 import service_account

        credentials = service_account.Credentials.from_service_account_info(
            raw, scopes=["https://www.googleapis.com/auth/firebase.messaging"]
        )

        class TimedRequest(Request):
            def __call__(self, *args, **kwargs):
                kwargs["timeout"] = 20
                return super().__call__(*args, **kwargs)

        try:
            credentials.refresh(TimedRequest())
            report["service_account_oauth"] = bool(credentials.valid)
        except Exception:
            report["service_account_oauth"] = False
            raise RuntimeError("Dienstkonto-OAuth fehlgeschlagen. Keine Tokens oder Schlüssel ausgegeben.") from None
        # This is deliberately not a registered real device. It can prove an
        # accepted validation or an explicit rejection, never visible delivery.
        response = httpx.post(
            f"https://fcm.googleapis.com/v1/projects/{PROJECT}/messages:send",
            headers={"Authorization": "Bearer " + credentials.token},
            json={
                "validate_only": True,
                "message": {
                    "token": "SCHULPILOT_SYNTHETIC_UNREGISTERED_TARGET_" + "x" * 128,
                    "notification": {"title": "SCHULPILOT", "body": "Synthetische Validierung"},
                },
            },
            timeout=20,
            follow_redirects=False,
        )
        report["fcm_validation_target"] = "synthetic_unregistered"
        report["fcm_validate_only_http"] = response.status_code
        report["fcm_validate_only"] = "validated" if response.status_code == 200 else "rejected"
        if response.status_code != 200:
            try:
                code = response.json().get("error", {}).get("status", "UNKNOWN")
            except ValueError:
                code = "UNKNOWN"
            report["fcm_validation_error"] = code if re.fullmatch(r"[A-Z_]{1,80}", code) else "UNKNOWN"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--configure",
        action="store_true",
        help="Enable only required APIs and create/reuse the minimal dedicated sender.",
    )
    parser.add_argument(
        "--gcloud",
        type=Path,
        default=Path.home() / ".local/share/schulpilot-google-cloud/589.0.0/google-cloud-sdk/bin/gcloud",
    )
    parser.add_argument(
        "--skip-local-auth",
        action="store_true",
        help="Check OAuth separately on the correctly synchronized application server.",
    )
    args = parser.parse_args()
    os.umask(0o077)
    report = {
        "project_id": PROJECT,
        "checked_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "production_push_approved": False,
        "service_account_oauth": False,
        "fcm_validate_only": "not_performed",
        "visible_delivery": "not_observed",
        "key_created": False,
    }
    try:
        google = Google(args.gcloud)
        inspect(google, report, args.configure)
        sender(google, report, args.configure, authenticate=not args.skip_local_auth)
        report["local_clock_utc"] = report["checked_at_utc"]
        report["checked_at_utc"] = google.server_time
    except CloudError as error:
        report["blocker"] = str(error)
        report["policy_constraints"] = error.policies
    except Exception as error:
        report["blocker"] = (
            str(error) if isinstance(error, RuntimeError) else "Prüfung fehlgeschlagen: " + type(error).__name__
        )
    save(ROOT / "firebase-project-report.json", report)
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 1 if report.get("blocker") else 0


if __name__ == "__main__":
    sys.exit(main())
