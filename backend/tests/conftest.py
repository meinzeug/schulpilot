import os
import tempfile

from cryptography.fernet import Fernet

_directory = tempfile.mkdtemp(prefix="schulpilot-tests-")
test_url = os.getenv("TEST_DATABASE_URL", "")
if test_url:
    from sqlalchemy.engine import make_url

    if not (make_url(test_url).database or "").endswith("_test"):
        raise RuntimeError("Integration tests require a dedicated database ending in _test")
os.environ["DATABASE_URL"] = test_url or "sqlite:///" + _directory + "/test.sqlite"
os.environ["DATA_DIR"] = _directory
os.environ["MASTER_KEY"] = Fernet.generate_key().decode()
os.environ["ENVIRONMENT"] = "test"
os.environ["PUBLIC_URL"] = "http://testserver"

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from schulpilot import auth, families  # noqa: E402
from schulpilot.config import settings  # noqa: E402
from schulpilot.db import DB, Base, Installation, engine, init_db  # noqa: E402
from schulpilot.main import app  # noqa: E402

HEADERS = {"X-Schulpilot-Request": "1", "X-Client-Platform": "native"}


@pytest.fixture(autouse=True)
def clean_database():
    old = dict(settings.__dict__)
    Base.metadata.drop_all(engine)
    init_db()
    with DB.begin() as db:
        db.get(Installation, 1).completed = True
    yield
    for key, value in old.items():
        object.__setattr__(settings, key, value)


@pytest.fixture
def api():
    with TestClient(app, headers=HEADERS, raise_server_exceptions=True) as client:
        yield client


@pytest.fixture
def mailbox(monkeypatch):
    messages = []

    def send(email, subject, text, route, token):
        messages.append({"email": email, "route": route, "token": token})

    for module in (auth, families):
        monkeypatch.setattr(module, "require_mail", lambda: None)
        monkeypatch.setattr(module, "send_link", send)
    return messages


def register(api, mailbox, email="parent@example.org"):
    response = api.post(
        "/api/auth/register",
        json={
            "email": email,
            "password": "secure-parent-pass-123",
            "display_name": "Test-Eltern",
            "family_name": "Testfamilie",
            "adult_consent": True,
        },
    )
    assert response.status_code == 201, response.text
    token = mailbox[-1]["token"]
    assert api.post("/api/auth/verify", json={"token": token}).status_code == 200
    login = api.post("/api/auth/login", json={"username": email, "password": "secure-parent-pass-123"})
    assert login.status_code == 200, login.text
    data = login.json()
    api.headers["Authorization"] = "Bearer " + data["token"]
    return data["user"]


def create_child(api, user, username="test-child"):
    response = api.post(
        f"/api/families/{user['families'][0]['id']}/children",
        json={
            "display_name": "Testkind",
            "username": username,
            "password": "secure-child-pass-123",
            "grade": 6,
            "subjects": ["Mathematik"],
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


@pytest.fixture
def household(api, mailbox):
    user = register(api, mailbox)
    child = create_child(api, user)
    return user, child
