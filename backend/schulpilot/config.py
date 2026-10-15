import json
import os
from dataclasses import dataclass, replace
from pathlib import Path


@dataclass(frozen=True)
class Settings:
    database_url: str = os.getenv("DATABASE_URL", "sqlite:///./data/schulpilot.sqlite")
    data_dir: Path = Path(os.getenv("DATA_DIR", "./data"))
    public_url: str = os.getenv("PUBLIC_URL", "http://localhost:8080").rstrip("/")
    environment: str = os.getenv("ENVIRONMENT", "development")
    web_dir: str = os.getenv("WEB_DIR", "")
    smtp_host: str = os.getenv("SMTP_HOST", "")
    smtp_port: int = int(os.getenv("SMTP_PORT", "587"))
    smtp_user: str = os.getenv("SMTP_USER", "")
    smtp_password: str = os.getenv("SMTP_PASSWORD", "")
    smtp_from: str = os.getenv("SMTP_FROM", "")
    smtp_mode: str = os.getenv("SMTP_MODE", "starttls")
    master_key: str = os.getenv("MASTER_KEY", "")
    real_data_approved: bool = os.getenv("REAL_DATA_APPROVED", "false") == "true"
    privacy_evidence: str = os.getenv("PRIVACY_EVIDENCE", "")
    synthetic_demo: bool = os.getenv("SYNTHETIC_DEMO", "true") == "true"
    synthetic_ai_enabled: bool = os.getenv("SYNTHETIC_AI_ENABLED", "false") == "true"
    synthetic_ai_daily_limit: int = int(os.getenv("SYNTHETIC_AI_DAILY_LIMIT", "40"))
    fcm_service_account_file: str = os.getenv("FCM_SERVICE_ACCOUNT_FILE", "")
    fcm_service_account_json: str = ""
    fcm_public_config: str = os.getenv("FCM_PUBLIC_CONFIG", "")
    push_approved: bool = os.getenv("PUSH_APPROVED", "false") == "true"
    push_privacy_evidence: str = os.getenv("PUSH_PRIVACY_EVIDENCE", "")
    fcm_config_verification: str = os.getenv("FCM_CONFIG_VERIFICATION", "")
    google_oauth_client_file: str = os.getenv("GOOGLE_OAUTH_CLIENT_FILE", "")
    google_oauth_client_json: str = ""
    google_login_enabled: bool = os.getenv("GOOGLE_LOGIN_ENABLED", "false") == "true"
    operator_name: str = os.getenv("OPERATOR_NAME", "")
    operator_address: str = os.getenv("OPERATOR_ADDRESS", "")
    operator_support_email: str = os.getenv("OPERATOR_SUPPORT_EMAIL", "")
    codex_socket: str = os.getenv("CODEX_SOCKET", "")
    codex_approved: bool = os.getenv("CODEX_APPROVED", "false") == "true"
    codex_auth_mode: str = os.getenv("CODEX_AUTH_MODE", "api_key")
    codex_web_search: bool = os.getenv(
        "CODEX_WEB_SEARCH", "false" if os.getenv("CODEX_AUTH_MODE", "api_key") == "account" else "true"
    ) == "true"
    default_plan: str = "Pilot"
    default_child_limit: int = 4
    default_call_limit: int = 100
    default_budget_micros: int = 2_000_000

    @property
    def mail_ready(self):
        return bool(self.smtp_host and self.smtp_from)


settings = Settings()

# Paths, database credentials, encryption key and worker privileges stay local.
RUNTIME_FIELDS = frozenset(
    {
        "smtp_host",
        "smtp_port",
        "smtp_user",
        "smtp_password",
        "smtp_from",
        "smtp_mode",
        "real_data_approved",
        "privacy_evidence",
        "synthetic_demo",
        "synthetic_ai_enabled",
        "synthetic_ai_daily_limit",
        "operator_name",
        "operator_address",
        "operator_support_email",
        "fcm_public_config",
        "fcm_service_account_json",
        "push_approved",
        "push_privacy_evidence",
        "fcm_config_verification",
        "google_oauth_client_json",
        "google_login_enabled",
        "default_plan",
        "default_child_limit",
        "default_call_limit",
        "default_budget_micros",
    }
)


def runtime_settings(db=None):
    """Read persisted operator settings in every process; no restart or secret echo."""
    from .db import DB, Installation
    from .security import decrypt

    if db is None:
        with DB() as session:
            return runtime_settings(session)
    row = db.get(Installation, 1)
    if not row or not row.encrypted_settings:
        return settings
    values = json.loads(decrypt(row.encrypted_settings))
    return replace(settings, **{k: v for k, v in values.items() if k in RUNTIME_FIELDS})
