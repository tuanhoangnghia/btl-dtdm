import io

from sqlalchemy import select

from cloudjudge.common import db
from cloudjudge.common.problems import build_tests_zip
from conftest import csrf, login

TOKEN = "t" * 64


def test_healthz_ok(client):
    r = client.get("/healthz")
    assert r.status_code == 200
    assert r.get_json() == {"status": "ok", "host": "web-test-1", "az": "az1"}


def test_healthz_503_when_db_down(cfg, storage, publisher):
    from sqlalchemy import create_engine

    from cloudjudge.web import create_app
    broken = create_engine("sqlite:////nonexistent-dir/x.db")
    app = create_app(cfg, engines=(broken, broken), storage=storage, publisher=publisher, instance=("h", "az2"))
    r = app.test_client().get("/healthz")
    assert r.status_code == 503
    assert r.get_json()["status"] == "db_error"


def test_footer_shows_host_and_az(client):
    html = client.get("/problems").get_data(as_text=True)
    assert "web-test-1" in html and "az1" in html
    assert "a-plus-b" in html and "slow-sum" in html


def test_login_wrong_password(client):
    token = csrf(client)
    r = client.post("/login", data={"username": "sv01", "password": "nope", "csrf_token": token})
    assert r.status_code == 200
    assert "Sai tên đăng nhập" in r.get_data(as_text=True)


def test_post_without_csrf_rejected(client):
    r = client.post("/login", data={"username": "sv01", "password": "pass123456"})
    assert r.status_code == 400


def test_submit_flow(client, seeded, storage, publisher, cfg):
    token = login(client)
    r = client.post("/problems/a-plus-b/submit",
                    data={"language": "python", "source": "print(1)", "csrf_token": token})
    assert r.status_code == 302
    sub_id = int(r.headers["Location"].rsplit("/", 1)[1])
    assert publisher.sent == [sub_id]
    with seeded.connect() as conn:
        row = conn.execute(select(db.submissions).where(db.submissions.c.id == sub_id)).first()
    assert row.status == "PENDING" and row.language == "python"
    assert row.source_object.endswith("/main.py")
    assert storage.get(cfg.swift_submissions, row.source_object) == b"print(1)"

    page = client.get(f"/submissions/{sub_id}").get_data(as_text=True)
    assert "PENDING" in page and 'http-equiv="refresh"' in page and "print(1)" in page


def test_submit_requires_login(client):
    token = csrf(client)
    r = client.post("/problems/a-plus-b/submit", data={"language": "cpp", "source": "x", "csrf_token": token})
    assert r.status_code == 302 and "/login" in r.headers["Location"]


def test_submit_queue_down_marks_system_error(client, seeded, publisher):
    publisher.fail = True
    token = login(client)
    r = client.post("/problems/a-plus-b/submit", data={"language": "cpp", "source": "int main(){}", "csrf_token": token})
    assert r.status_code == 302
    with seeded.connect() as conn:
        status = conn.execute(select(db.submissions.c.status)).scalar()
    assert status == "SYSTEM_ERROR"


def test_other_student_cannot_view_submission(app, client):
    token = login(client, "sv01")
    r = client.post("/problems/a-plus-b/submit", data={"language": "python", "source": "x=1", "csrf_token": token})
    sub_path = r.headers["Location"]
    other = app.test_client()
    login(other, "sv02")
    assert other.get(sub_path).status_code == 403
    teacher = app.test_client()
    login(teacher, "gv01")
    assert teacher.get(sub_path).status_code == 200


def test_api_submit_and_status(client, publisher):
    r = client.post("/api/submit", json={"problem": "slow-sum", "language": "cpp", "source": "int main(){}"},
                    headers={"X-API-Token": TOKEN})
    assert r.status_code == 201, r.data
    sub_id = r.get_json()["id"]
    assert publisher.sent == [sub_id]
    s = client.get(f"/api/submissions/{sub_id}", headers={"X-API-Token": TOKEN}).get_json()
    assert s["status"] == "PENDING" and s["created_at"].endswith("Z")


def test_api_rejects_bad_token(client):
    r = client.post("/api/submit", json={}, headers={"X-API-Token": "x" * 64})
    assert r.status_code == 401
    assert client.post("/api/submit", json={}).status_code == 401


def test_api_validation(client):
    h = {"X-API-Token": TOKEN}
    assert client.post("/api/submit", json={"problem": "nope", "language": "cpp", "source": "x"}, headers=h).status_code == 404
    assert client.post("/api/submit", json={"problem": "a-plus-b", "language": "java", "source": "x"}, headers=h).status_code == 400
    assert client.post("/api/submit", json={"problem": "a-plus-b", "language": "cpp", "source": "  "}, headers=h).status_code == 400


def test_metrics(client, seeded):
    client.post("/api/submit", json={"problem": "a-plus-b", "language": "cpp", "source": "int main(){}"},
                headers={"X-API-Token": TOKEN})
    body = client.get("/metrics").get_data(as_text=True)
    assert 'cj_submissions_total{language="cpp"}' in body
    assert "cj_pending_submissions 1.0" in body
    assert "cj_oldest_pending_seconds" in body


def test_scoreboard_reads_replica(client, seeded):
    with seeded.begin() as conn:
        uid = conn.execute(select(db.users.c.id).where(db.users.c.username == "sv03")).scalar()
        pid = conn.execute(select(db.problems.c.id).where(db.problems.c.slug == "a-plus-b")).scalar()
        for score in (40, 100):
            conn.execute(db.submissions.insert().values(
                uuid=f"u-{score}", user_id=uid, problem_id=pid, language="cpp", source_object="x",
                status="ACCEPTED", score=score, created_at=db.utcnow()))
    html = client.get("/scoreboard").get_data(as_text=True)
    assert "replica" in html and "sv03" in html and "<strong>100</strong>" in html


def test_teacher_creates_problem(app, storage, cfg):
    c = app.test_client()
    token = login(c, "gv01")
    z = build_tests_zip([(b"1\n", b"2\n"), (b"5\n", b"10\n")])
    r = c.post("/teacher/problems/new", data={
        "slug": "double-it", "title": "Nhân đôi", "statement_md": "In ra 2*n", "time_limit_ms": "1000",
        "memory_mb": "64", "csrf_token": token, "tests_zip": (io.BytesIO(z), "tests.zip"),
    }, content_type="multipart/form-data")
    assert r.status_code == 302, r.data
    assert storage.get(cfg.swift_testcases, "double-it/tests.zip") == z
    assert "Nhân đôi" in c.get("/problems/double-it").get_data(as_text=True)


def test_teacher_page_forbidden_for_students(client):
    login(client, "sv01")
    assert client.get("/teacher/problems/new").status_code == 403


def test_statement_markdown_escapes_html(client, seeded):
    with seeded.begin() as conn:
        conn.execute(db.problems.update().where(db.problems.c.slug == "a-plus-b")
                     .values(statement_md="# Đề\n<script>alert(1)</script>\n```\ncode<b>\n```"))
    html = client.get("/problems/a-plus-b").get_data(as_text=True)
    assert "<script>alert(1)</script>" not in html
    assert "&lt;script&gt;" in html and "<h2>Đề</h2>" in html and "code&lt;b&gt;" in html
