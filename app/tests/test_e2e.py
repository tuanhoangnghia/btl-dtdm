"""End-to-end trên một máy: web thật (HTTP) + hàng đợi trong RAM + worker (Judge) + scripts/loadtest.py."""
import queue
import subprocess
import sys
import threading
from pathlib import Path

from sqlalchemy import create_engine, func, select
from werkzeug.serving import make_server

from cloudjudge import cli
from cloudjudge.common import db
from cloudjudge.web import create_app
from cloudjudge.worker.main import Judge
from conftest import FakeStorage
from test_worker import LocalPythonSandbox

ROOT = Path(__file__).resolve().parents[2]
TOKEN = "e" * 64


class QueuePublisher:
    def __init__(self):
        self.q = queue.Queue()

    def publish(self, submission_id):
        self.q.put(submission_id)


def test_loadtest_end_to_end(tmp_path, cfg):
    engine = create_engine(f"sqlite:///{tmp_path / 'cj.db'}", connect_args={"check_same_thread": False, "timeout": 30})
    db.metadata.create_all(engine)
    storage = FakeStorage()
    cli.main(["seed", "--password", "pass123456", "--loadtest-token", TOKEN], cfg=cfg, engine=engine, storage=storage)

    pub = QueuePublisher()
    app = create_app(cfg, engines=(engine, engine), storage=storage, publisher=pub, instance=("web-e2e", "az1"))
    server = make_server("127.0.0.1", 0, app, threaded=True)
    threading.Thread(target=server.serve_forever, daemon=True).start()

    judge = Judge(cfg, engine, storage, LocalPythonSandbox())
    stop = threading.Event()

    def worker():
        while not stop.is_set():
            try:
                sid = pub.q.get(timeout=0.2)
            except queue.Empty:
                continue
            judge.handle(sid)

    t = threading.Thread(target=worker, daemon=True)
    t.start()
    try:
        p = subprocess.run(
            [sys.executable, str(ROOT / "scripts" / "loadtest.py"), "--base", f"http://127.0.0.1:{server.port}",
             "--token", TOKEN, "--problem", "slow-sum", "--language", "python",
             "--source", str(ROOT / "app/sample_problems/slow-sum/solutions/fast.py"),
             "--n", "20", "--concurrency", "5", "--poll", "0.5", "--timeout", "240"],
            capture_output=True, text=True, encoding="utf-8", timeout=300,
            env={**__import__("os").environ, "PYTHONIOENCODING": "utf-8"},
        )
    finally:
        stop.set()
        server.shutdown()
    print(p.stdout, p.stderr)
    assert p.returncode == 0, p.stdout + p.stderr
    assert "xong 20/20" in p.stdout and "'ACCEPTED': 20" in p.stdout
    with engine.connect() as conn:
        n = conn.execute(select(func.count()).select_from(db.submissions)
                         .where(db.submissions.c.status == "ACCEPTED")).scalar()
    assert n == 20
