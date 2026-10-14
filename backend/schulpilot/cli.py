import argparse
import getpass
import sys

from sqlalchemy import select, update

from .db import DB, Installation, Session, User, init_db, now
from .security import audit, password_hash


def main():
    parser = argparse.ArgumentParser(description="Lokale SCHULPILOT-Betriebsverwaltung")
    parser.add_argument(
        "command",
        choices=[
            "init-db",
            "create-admin",
            "reset-admin",
            "rotate-setup-code",
            "configure-free-tests",
            "configure-free-standard",
            "probe-private-route",
        ],
    )
    parser.add_argument("--username", default="")
    parser.add_argument(
        "--password-stdin",
        action="store_true",
        help="Passwort ausschließlich über Standard-Eingabe lesen (lokale Automation)",
    )
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
    if args.command == "rotate-setup-code":
        from .installation import code_path, initialize

        with DB.begin() as db:
            item = db.get(Installation, 1)
            if item.completed:
                raise SystemExit("Abgeschlossene Installationen können nicht erneut geöffnet werden.")
            item.bootstrap_digest = item.bootstrap_expires = None
            code_path().unlink(missing_ok=True)
        initialize()
        print("Neuer einmaliger Installationscode liegt in " + str(code_path()))
        return
    if not sys.stdin.isatty() and not (args.password_stdin and args.username):
        raise SystemExit(
            "Admin-Einrichtung benötigt ein lokales interaktives Terminal. Keine Passwörter per Kommandozeilenargument."
        )
    username = (args.username or input("Admin-Benutzername: ")).strip().lower()
    if not username or len(username) > 50 or "@" in username:
        raise SystemExit("Bitte einen separaten Admin-Benutzernamen mit maximal 50 Zeichen verwenden.")
    if args.password_stdin:
        password = sys.stdin.read(1025).rstrip("\r\n")
        if len(password) > 128:
            raise SystemExit("Passwort ist zu lang.")
    else:
        password = getpass.getpass("Neues sicheres Passwort (mindestens 12 Zeichen): ")
        if password != getpass.getpass("Passwort wiederholen: "):
            raise SystemExit("Passwörter stimmen nicht überein.")
    encoded = password_hash(password)
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
                password_hash=encoded,
            )
            db.add(user)
            db.flush()
        else:
            if not user or user.role != "admin":
                raise SystemExit("Kein vorhandener Administrator mit diesem Benutzernamen.")
            user.password_hash = encoded
            user.disabled = False
            db.execute(update(Session).where(Session.user_id == user.id).values(revoked=True))
        item = db.get(Installation, 1)
        item.completed, item.completed_at, item.bootstrap_digest, item.bootstrap_expires = True, int(now()), None, None
        audit(db, "local-cli", args.command, user.id)
    from .installation import code_path

    code_path().unlink(missing_ok=True)
    print("Admin-Zugang eingerichtet. Anmeldung mit Benutzername und Passwort.")


if __name__ == "__main__":
    main()
