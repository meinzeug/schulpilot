"""Prepare/clean our regular artificial family through normal verified signup.

Uses the existing authorized test mailbox and never makes a provider call.
The existing smoke setup verifies readiness; no quota or permission bypass.
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import prepare_normal_ai_smoke as setup  # noqa: E402

setup.PRIVATE = ROOT / "artifacts/.practice-normal-qa-account.json"

if __name__ == "__main__":
    setup.main()
