"""Local operator approval record, separate from technical endpoint readiness."""

import json
import sys

from sqlalchemy import update

from .db import DB, ProviderConfig
from .security import audit


def run():
    data = json.loads(sys.stdin.read(4096))
    evidence = data["evidence"]
    block = data["technical_block"]
    if (
        not isinstance(evidence, str)
        or not 20 <= len(evidence) <= 500
        or not isinstance(block, str)
        or len(block) > 500
    ):
        raise SystemExit("Invalid operator evidence")
    with DB.begin() as db:
        config = db.get(ProviderConfig, 1)
        config.privacy_approved = True
        config.privacy_evidence = evidence
        config.production_block_reason = block
        config.status = block or "Betreiberfreigabe dokumentiert. Konkrete Verbindung separat prüfen."
        db.execute(update(ProviderConfig).where(ProviderConfig.id == 1).values(revision=ProviderConfig.revision + 1))
        audit(db, "local-cli", "operator.approval_recorded", "provider")
    print("Operator approval recorded; technical routing restriction preserved.")


if __name__ == "__main__":
    run()
