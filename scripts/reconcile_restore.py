"""Apply a current authenticated deletion journal to an isolated restore DB.

Production databases are deliberately refused. Reconcile and inspect an offline
restore first, then activate it through a separately planned recovery procedure.
"""

import argparse
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--database-url", required=True)
    parser.add_argument("--ledger", type=Path, required=True)
    parser.add_argument("--master-key-file", type=Path, required=True)
    parser.add_argument("--uploads", type=Path, required=True)
    args = parser.parse_args()
    if args.uploads.resolve() == Path("/var/lib/schulpilot/uploads") or args.uploads.is_symlink():
        parser.error("The live upload directory is not accepted; use a separate restore copy")
    from sqlalchemy.engine import make_url

    if not (make_url(args.database_url).database or "").endswith("_restore_test"):
        parser.error("Only a separate database ending in _restore_test is accepted")
    os.environ["DATABASE_URL"] = args.database_url
    from schulpilot.db import DB, ProviderConfig, Session, Token
    from schulpilot.erasure import reconcile, retained_image_names, valid_image_name, verify
    from sqlalchemy import update

    key = args.master_key_file.read_text().strip()
    records = [verify(line, key) for line in args.ledger.read_text().splitlines() if line]
    with DB.begin() as db:
        paths = reconcile(db, records)
        # A backup must never resurrect sessions or device push authorizations.
        db.execute(update(Session).values(revoked=True))
        db.execute(update(Token).values(used=True))
        db.execute(update(ProviderConfig).values(emergency_stop=True))
        retained = retained_image_names(db)
    for name in paths:
        if not valid_image_name(name):
            raise RuntimeError("Unexpected private image path")
        (args.uploads / name).unlink(missing_ok=True)
    for photo in args.uploads.glob("*.jpg"):
        if photo.name not in retained:
            photo.unlink()
    print("Authenticated deletion reconciliation completed; all restored sessions revoked.")


if __name__ == "__main__":
    main()
