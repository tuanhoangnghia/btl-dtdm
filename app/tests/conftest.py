"""Test chạy không cần MySQL/RabbitMQ/Swift/Docker: SQLite trong RAM + các bản giả."""
from __future__ import annotations

import sys
from pathlib import Path

import pytest
from sqlalchemy import create_engine, event
from sqlalchemy.pool import StaticPool

APP_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(APP_DIR))

from cloudjudge.common import db  # noqa: E402
from cloudjudge.common.config import Config  # noqa: E402


class FakeStorage:
    def __init__(self):
        self.objects: dict[tuple[str, str], bytes] = {}

    def put(self, container, name, data, content_type="application/octet-stream"):
        self.objects[(container, name)] = bytes(data)
        return "etag"

    def get(self, container, name):
        return self.objects[(container, name)]

    def etag(self, container, name):
        return str(hash(self.objects[(container, name)]))

    def ensure_container(self, container):
        pass


class FakePublisher:
    def __init__(self):
        self.sent: list[int] = []
        self.fail = False

    def publish(self, submission_id):
        if self.fail:
            raise ConnectionError("broker down")
        self.sent.append(submission_id)


@pytest.fixture
def cfg():
    return Config(secret_key="test-secret", release="test", storage_auth="tempauth")


@pytest.fixture
def engine():
    eng = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)

    @event.listens_for(eng, "connect")
    def _fk(dbapi_conn, _rec):
        dbapi_conn.execute("PRAGMA foreign_keys=ON")

    db.metadata.create_all(eng)
    return eng


@pytest.fixture
def storage():
    return FakeStorage()


@pytest.fixture
def publisher():
    return FakePublisher()


@pytest.fixture
def seeded(cfg, engine, storage):
    from cloudjudge import cli
    cli.main(["seed", "--password", "pass123456", "--loadtest-token", "t" * 64], cfg=cfg, engine=engine, storage=storage)
    return engine


@pytest.fixture
def app(cfg, seeded, storage, publisher):
    from cloudjudge.web import create_app
    a = create_app(cfg, engines=(seeded, seeded), storage=storage, publisher=publisher,
                   instance=("web-test-1", "az1"))
    a.config["TESTING"] = True
    return a


@pytest.fixture
def client(app):
    return app.test_client()


def csrf(client) -> str:
    client.get("/login")
    with client.session_transaction() as s:
        return s["csrf"]


def login(client, username="sv01", password="pass123456"):
    token = csrf(client)
    r = client.post("/login", data={"username": username, "password": password, "csrf_token": token})
    assert r.status_code == 302, r.data
    return token
