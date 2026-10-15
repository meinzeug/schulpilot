"""Own temporary Demo household + artificial corpus for list/UI verification.

Requires the operator's existing SSH access. Never reads a real household,
resets a quota or calls an external AI. Credentials stay in ignored0600 JSON.
"""

import argparse
import json
import os
import re
import subprocess
import tempfile
import time
import uuid
from pathlib import Path

import httpx

ROOT = Path(__file__).resolve().parents[1]
PRIVATE = ROOT / "artifacts/.library-qa-account.json"
BASE = "https://schulpilot.dorfspy.de/api"
HEADERS = {"X-Schulpilot-Request": "1", "X-Client-Platform": "native"}

SEED = r"""
import os,sys,json
from pathlib import Path
from datetime import timedelta
sys.path.insert(0,'/opt/schulpilot/current/deploy')
from monitor import environment
os.environ.update(environment(Path('/etc/schulpilot/environment')))
sys.path.insert(0,'/opt/schulpilot/current/backend')
from schulpilot.db import DB,Child,Family,Material,Membership,SchoolDay,User
from schulpilot.security import audit
from schulpilot.learning import local_day
from sqlalchemy import select,func
child_id,parent_id,family_id=sys.argv[1:]
with DB.begin() as db:
 child=db.get(Child,child_id);family=db.get(Family,family_id);parent=db.get(User,parent_id)
 assert child and child.family_id==family_id and family.synthetic and parent.role=='parent'
 assert parent.username.startswith('eltern-') and db.scalar(select(Membership).where(Membership.user_id==parent_id,Membership.family_id==family_id)).permission=='owner'
 assert db.scalar(select(func.count()).select_from(Child).where(Child.family_id==family_id))==1
 assert not db.scalar(select(Material.id).where(Material.child_id==child_id,Material.synthetic.is_(False)))
 existing=db.scalar(select(func.count()).select_from(Material).where(Material.child_id==child_id,Material.title.startswith('Künstliche Bibliotheksseite ')))
 assert existing in (0,600)
 if not existing:
  topics=[('Mathematik','Bruchrechnung','Zähler und Nenner gehören zu einem Bruch.'),('Deutsch','Wortarten','Ein Nomen kann mit einem Artikel verwendet werden.'),('Englisch','Present simple','I learn. You learn. We learn.'),('Sachunterricht','Wasserkreislauf','Wasser verdunstet und kann als Regen zurückkehren.')]
  today=local_day(child)
  for day_index in range(30):
   date=(today-timedelta(days=day_index+1)).isoformat()
   day=db.scalar(select(SchoolDay).where(SchoolDay.child_id==child_id,SchoolDay.school_date==date))
   if day is None:
    day=SchoolDay(child_id=child_id,school_date=date,stage='review');db.add(day);db.flush()
   for page in range(20):
    n=day_index*20+page;subject,topic,content=topics[n%len(topics)];confirmed=n%5!=0
    db.add(Material(child_id=child_id,school_day_id=day.id,page_number=page+1,title=f'Künstliche Bibliotheksseite {n+1:03}',subject=subject,topic=f'{topic} · Beispiel {n+1:03}',content=content,synthetic=True,confirmed=confirmed,status='confirmed' if confirmed else 'review'))
  audit(db,'local-operator','operator.synthetic_library_fixture',family_id)
 db.flush()
 total=db.scalar(select(func.count()).select_from(Material).where(Material.child_id==child_id))
 assert total==601
 print(json.dumps({'seeded_artificial_pages':600,'total_pages':total,'real_households_touched':0}))
"""


def save(data):
    with tempfile.NamedTemporaryFile(
        "w", dir=PRIVATE.parent, prefix=".library-qa-", suffix=".partial", delete=False
    ) as temporary:
        json.dump(data, temporary)
        temporary.write("\n")
        temporary.flush()
        os.fsync(temporary.fileno())
    os.replace(temporary.name, PRIVATE)


def expect(response, status=200):
    if response.status_code != status:
        raise RuntimeError(f"Own library QA: unexpected HTTP{response.status_code}")
    return response.json()


def main():
    parser = argparse.ArgumentParser()
    options = parser.add_mutually_exclusive_group(required=True)
    options.add_argument("--prepare", action="store_true")
    options.add_argument("--cleanup", action="store_true")
    args = parser.parse_args()
    with httpx.Client(base_url=BASE, headers=HEADERS, timeout=30) as parent:
        if args.cleanup:
            data = json.loads(PRIVATE.read_text())
            assert data["marker"] == "library-qa-v1" and re.fullmatch(
                r"eltern-[a-f0-9]{10}", data["credentials"]["parent_username"]
            )
            login = expect(
                parent.post(
                    "/auth/login",
                    json={
                        "username": data["credentials"]["parent_username"],
                        "password": data["credentials"]["parent_password"],
                    },
                )
            )
            assert login["user"]["id"] == data["user"]["id"] and len(login["user"]["families"]) == 1
            assert login["user"]["families"][0]["id"] == data["family_id"] and login["user"]["families"][0]["synthetic"]
            parent.headers["Authorization"] = "Bearer " + login["token"]
            with httpx.Client(base_url=BASE, headers=HEADERS, timeout=30) as child:
                child_login = expect(
                    child.post(
                        "/auth/login",
                        json={
                            "username": data["credentials"]["child_username"],
                            "password": data["credentials"]["child_password"],
                        },
                    )
                )
                assert child_login["user"]["role"] == "child" and child_login["user"]["child_id"] == data["child_id"]
                data["child_token"] = child_login["token"]
                child.headers["Authorization"] = "Bearer " + data["child_token"]
                assert child.get("/auth/me").status_code == 200
                save(data)
            expect(parent.request("DELETE", "/account", json={"password": data["credentials"]["parent_password"]}))
            assert parent.get("/auth/me").status_code == 401
            if data.get("child_token"):
                parent.headers["Authorization"] = "Bearer " + data["child_token"]
                assert parent.get("/auth/me").status_code == 401
            PRIVATE.unlink()
            print(
                json.dumps(
                    {
                        "own_synthetic_household_deleted": True,
                        "parent_and_child_sessions_revoked": True,
                        "real_households_touched": 0,
                    }
                )
            )
            return
        if PRIVATE.exists():
            raise RuntimeError("Resume the existing private UI fixture, or clean it up; do not create another family.")
        data = expect(parent.post("/demo"), 201)
        assert len(data["user"]["families"]) == 1 and data["user"]["families"][0]["synthetic"]
        data.update(marker="library-qa-v1", phase="created", family_id=data["user"]["families"][0]["id"])
        save(data)
        for value in [data["child_id"], data["user"]["id"], data["family_id"]]:
            assert re.fullmatch("[a-f0-9]{32}", value)
        parent.headers["Authorization"] = "Bearer " + data["token"]
        material = expect(parent.get("/materials/" + data["material_id"]))
        expect(
            parent.put(
                "/materials/" + data["material_id"] + "/confirm",
                json={key: material[key] for key in ("subject", "topic", "content", "homework")}
                | {"uncertainties_resolved": True},
            )
        )
        with httpx.Client(base_url=BASE, headers=HEADERS, timeout=30) as child:
            login = expect(
                child.post(
                    "/auth/login",
                    json={
                        "username": data["credentials"]["child_username"],
                        "password": data["credentials"]["child_password"],
                    },
                )
            )
            data["child_token"] = login["token"]
            save(data)
            child.headers["Authorization"] = "Bearer " + data["child_token"]
            job = expect(
                child.post(
                    f"/children/{data['child_id']}/units",
                    json={"material_id": data["material_id"]},
                    headers={"Idempotency-Key": uuid.uuid4().hex},
                ),
                202,
            )
            data["unit_job_id"] = job["id"]
            save(data)
            for _ in range(90):
                job = expect(child.get("/jobs/" + data["unit_job_id"]))
                if job["status"] == "completed":
                    break
                if job["status"] == "failed":
                    raise RuntimeError("Local Demo exercise job failed; no automatic retry.")
                time.sleep(0.5)
            assert job["status"] == "completed"
            data["unit_id"] = job["result"]["unit_id"]
            unit = expect(child.get("/units/" + data["unit_id"]))
            assert unit["synthetic"] and unit["provider"] == "synthetic" and len(unit["questions"]) == 4
            save(data)
        process = subprocess.run(
            [
                "ssh",
                "-o",
                "BatchMode=yes",
                "dorfspy",
                "runuser",
                "-u",
                "schulpilot",
                "--",
                "/opt/schulpilot/current/venv/bin/python",
                "-",
                data["child_id"],
                data["user"]["id"],
                data["family_id"],
            ],
            input=SEED,
            text=True,
            capture_output=True,
            timeout=45,
        )
        if process.returncode:
            raise RuntimeError("Isolated corpus setup failed; private account retained for cleanup.")
        seeded = json.loads(process.stdout)
        assert seeded["total_pages"] == 601
        data.update(phase="ready", corpus=seeded)
        save(data)
        print(
            json.dumps(
                {
                    "own_synthetic_fixture_ready": True,
                    "pages": 601,
                    "local_demo_unit_ready": True,
                    "external_ai_calls": 0,
                }
            )
        )


if __name__ == "__main__":
    main()
