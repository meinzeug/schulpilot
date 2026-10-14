import smtplib
import ssl
from email.message import EmailMessage

from fastapi import HTTPException

from .config import settings


def require_mail():
    if not settings.mail_ready:
        raise HTTPException(
            503,
            "E-Mail-Versand ist noch nicht eingerichtet. Registrierung, Einladungen und Wiederherstellung sind daher derzeit nicht verfügbar.",
        )
    if settings.smtp_mode not in ("starttls", "tls"):
        raise HTTPException(503, "E-Mail-Versand erfordert TLS mit Zertifikatsprüfung.")


def send_link(email, subject, text, route, token):
    require_mail()
    message = EmailMessage()
    message["From"] = settings.smtp_from
    message["To"] = email
    message["Subject"] = subject
    # Fragment prevents tokens from entering HTTP access logs / Referer headers.
    message.set_content(
        f"{text}\n\n{settings.public_url}/{route}#token={token}\n\n"
        "Wenn du dies nicht angefordert hast, ignoriere diese Nachricht."
    )
    try:
        connection = (
            smtplib.SMTP_SSL(settings.smtp_host, settings.smtp_port, timeout=15, context=ssl.create_default_context())
            if settings.smtp_mode == "tls"
            else smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=15)
        )
        with connection as smtp:
            if settings.smtp_mode == "starttls":
                smtp.starttls(context=ssl.create_default_context())
            if settings.smtp_user:
                smtp.login(settings.smtp_user, settings.smtp_password)
            smtp.send_message(message)
    except (OSError, smtplib.SMTPException):
        raise HTTPException(503, "E-Mail konnte nicht versendet werden. Bitte später erneut versuchen.") from None
