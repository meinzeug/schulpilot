"""Local operator entry point. No HTTP credential import or arbitrary sender."""

import argparse
import json
import sys

from sqlalchemy import select

from .config import runtime_settings
from .db import DB, Child, Family, Membership, PushTestGrant, User, now
from .installation import SiteUpdate, save_site
from .security import audit


def run():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["configure-public", "grant-synthetic-test"])
    args = parser.parse_args()
    data = json.loads(sys.stdin.read(16000))
    with DB() as db:
        if args.command == "configure-public":
            public = data["public_config"]
            if public.get("projectId") != "schulpilot-f6bf3" or public.get("messagingSenderId") != "460657028995":
                raise SystemExit("Wrong Firebase project; no change.")
            # This operation NEVER approves production delivery, even if the
            # caller has successfully generated a private service-account key.
            save_site(
                SiteUpdate(
                    fcm_public_config=json.dumps(public),
                    push_approved=False,
                    push_privacy_evidence="",
                    fcm_config_verification=data.get("verification", ""),
                ),
                "local-firebase-cli",
                db,
            )
            site = runtime_settings(db)
            print(
                json.dumps(
                    {
                        "public_config_saved": True,
                        "production_push_approved": site.push_approved,
                        "key_restrictions_verified": bool(site.fcm_config_verification),
                    }
                )
            )
            return
        user = db.scalar(
            select(User).where(
                User.username == data["username"],
                User.role == "parent",
                User.verified.is_(True),
                User.disabled.is_(False),
            )
        )
        if not user:
            raise SystemExit("Synthetic parent test account not found.")
        memberships = list(db.scalars(select(Membership).where(Membership.user_id == user.id)))
        if len(memberships) != 1 or memberships[0].permission != "owner":
            raise SystemExit("Only an isolated synthetic owner account can receive this test grant.")
        family = db.get(Family, memberships[0].family_id)
        if not family or not family.synthetic:
            raise SystemExit("Real family accounts cannot receive experimental push-test access.")
        expiry = int(now()) + 7 * 86400
        family.expires = expiry
        users = [user.id]
        for child in db.scalars(select(Child).where(Child.family_id == family.id)):
            # Consent is given only for this operator-owned artificial family.
            child.preferences = {**child.preferences, "push_consent": True, "quiet_start": 0, "quiet_end": 0}
            users.append(child.user_id)
        for user_id in users:
            grant = db.get(PushTestGrant, user_id)
            if grant:
                grant.expires = expiry
            else:
                db.add(PushTestGrant(user_id=user_id, expires=expiry))
        audit(db, "local-firebase-cli", "push.synthetic_test_granted", family.id)
        db.commit()
        print(
            json.dumps(
                {
                    "synthetic_test_accounts_granted": len(users),
                    "expires": expiry,
                    "production_push_approval_changed": False,
                }
            )
        )


if __name__ == "__main__":
    run()
