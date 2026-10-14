import smtplib
import ssl
from email.message import EmailMessage

from fastapi import HTTPException

from .config import runtime_settings


def require_mail(site=None):
    site = site or runtime_settings()
    if not site.mail_ready:
        raise HTTPException(
            503,
            "E-Mail-Versand ist noch nicht eingerichtet. Registrierung, Einladungen und Wiederherstellung sind daher derzeit nicht verfügbar.",
        )
    if site.smtp_mode not in ("starttls", "tls"):
        raise HTTPException(503, "E-Mail-Versand erfordert TLS mit Zertifikatsprüfung.")


def send_link(email, subject, text, route, token):
    site = runtime_settings()
    send_message(
        email,
        subject,
        f"{text}\n\n{site.public_url}/{route}#token={token}\n\nWenn du dies nicht angefordert hast, ignoriere diese Nachricht.",
    )


def send_message(email, subject, text):
    site = runtime_settings()
    require_mail(site)
    message = EmailMessage()
    message["From"] = site.smtp_from
    message["To"] = email
    message["Subject"] = subject
    message.set_content(text)
    try:
        connection = (
            smtplib.SMTP_SSL(site.smtp_host, site.smtp_port, timeout=15, context=ssl.create_default_context())
            if site.smtp_mode == "tls"
            else smtplib.SMTP(site.smtp_host, site.smtp_port, timeout=15)
        )
        with connection as smtp:
            if site.smtp_mode == "starttls":
                smtp.starttls(context=ssl.create_default_context())
            if site.smtp_user:
                smtp.login(site.smtp_user, site.smtp_password)
            smtp.send_message(message)
    except (OSError, smtplib.SMTPException):
        raise HTTPException(503, "E-Mail konnte nicht versendet werden. Bitte später erneut versuchen.") from None
