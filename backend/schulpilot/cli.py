import argparse
import getpass
import sys

import pyotp
from sqlalchemy import select, update

from .db import DB, Session, User, init_db
from .security import audit, encrypt, password_hash


def main():
    parser = argparse.ArgumentParser(description="Lokale SCHULPILOT-Betriebsverwaltung")
    parser.add_argument(
        "command",
        choices=[
            "init-db",
            "create-admin",
            "reset-admin",
            "configure-free-tests",
            "configure-free-standard",
            "probe-private-route",
        ],
    )
    parser.add_argument("--username", default="")
    args = parser.parse_args()
    if args.command == "configure-free-standard":
        from .free_standard_setup import configure

        configure()
        return
    if args.command == "probe-private-route":
        from .provider_probe import run

        if not run():
            raise SystemExit(1)
        return
    if args.command == "configure-free-tests":
        from .free_test_setup import configure

        configure()
        return
    if args.command == "init-db":
        from .migrate import upgrade

        upgrade()
    init_db()
    if args.command == "init-db":
        print("Datenbankschema initialisiert.")
        return
    if not sys.stdin.isatty():
        raise SystemExit(
            "Admin-Einrichtung benötigt ein lokales interaktives Terminal. Keine Passwörter per Kommandozeilenargument."
        )
    username = (args.username or input("Admin-Benutzername: ")).strip().lower()
    if not username or len(username) > 50 or "@" in username:
        raise SystemExit("Bitte einen separaten Admin-Benutzernamen mit maximal 50 Zeichen verwenden.")
    password = getpass.getpass("Neues sicheres Passwort (mindestens 12 Zeichen): ")
    if password != getpass.getpass("Passwort wiederholen: "):
        raise SystemExit("Passwörter stimmen nicht überein.")
    secret = pyotp.random_base32()
    encrypted = encrypt(secret)
    print("TOTP ausschließlich jetzt in deiner Authenticator-App hinterlegen:")
    print(pyotp.TOTP(secret).provisioning_uri(name=username, issuer_name="SCHULPILOT Admin"))
    code = getpass.getpass("Aktuellen sechsstelligen Code zum Bestätigen eingeben: ")
    if not pyotp.TOTP(secret).verify(code):
        raise SystemExit("TOTP-Bestätigung fehlgeschlagen. Es wurde kein Admin-Zugang geändert.")
    with DB.begin() as db:
        user = db.scalar(select(User).where(User.username == username))
        if args.command == "create-admin":
            if user:
                raise SystemExit("Benutzername existiert bereits. Kein Konto wird zum Administrator umgewandelt.")
            user = User(
                username=username,
                display_name="Administration",
                role="admin",
                verified=True,
                password_hash=password_hash(password),
                totp_secret=encrypted,
            )
            db.add(user)
            db.flush()
        else:
            if not user or user.role != "admin":
                raise SystemExit("Kein vorhandener Administrator mit diesem Benutzernamen.")
            user.password_hash = password_hash(password)
            user.totp_secret = encrypted
            user.totp_last_step = 0
            db.execute(update(Session).where(Session.user_id == user.id).values(revoked=True))
        audit(db, "local-cli", args.command, user.id)
    print("Admin-Zugang eingerichtet. Anmeldung erfordert Passwort und TOTP. Es gibt kein Standardpasswort.")


if __name__ == "__main__":
    main()
