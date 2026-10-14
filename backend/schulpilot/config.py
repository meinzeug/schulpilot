import os
from dataclasses import dataclass
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
    fcm_public_config: str = os.getenv("FCM_PUBLIC_CONFIG", "")
    push_approved: bool = os.getenv("PUSH_APPROVED", "false") == "true"
    push_privacy_evidence: str = os.getenv("PUSH_PRIVACY_EVIDENCE", "")
    operator_name: str = os.getenv("OPERATOR_NAME", "")
    operator_address: str = os.getenv("OPERATOR_ADDRESS", "")
    operator_support_email: str = os.getenv("OPERATOR_SUPPORT_EMAIL", "")
    codex_socket: str = os.getenv("CODEX_SOCKET", "")
    codex_approved: bool = os.getenv("CODEX_APPROVED", "false") == "true"

    @property
    def mail_ready(self):
        return bool(self.smtp_host and self.smtp_from)


settings = Settings()
