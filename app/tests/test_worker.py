"""Worker: grader + Judge.handle với sandbox chạy thẳng bằng Python cục bộ (không Docker), qua cj-run thật."""
import contextlib
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest
from sqlalchemy import select

from cloudjudge.common import db
from cloudjudge.worker import grader
from cloudjudge.worker.main import Judge
from cloudjudge.worker.sandbox import RESULT_MARK, DockerSandbox, RunResult

CJ_RUN = Path(__file__).resolve().parents[2] / "image" / "sandbox" / "cj-run"
SAMPLES = Path(__file__).resolve().parents[1] / "sample_problems"


class LocalPythonSandbox:
    """Chạy main.py bằng python cục bộ qua cj-run (chỉ để test, KHÔNG cách ly). C++ coi như không có g++."""

    @contextlib.contextmanager
    def workspace(self):
        d = tempfile.mkdtemp()
        try:
            yield d
        finally:
            shutil.rmtree(d, ignore_errors=True)

    def compile(self, ws, language, source):
        if language != "python":
            return False, "g++ không có trong môi trường test"
        Path(ws, "main.py").write_bytes(source)
        import ast
        try:
            ast.parse(source)
        except SyntaxError as e:
            return False, f"SyntaxError: {e}"
        return True, ""

    def run(self, ws, language, stdin, time_limit_ms, memory_mb):
        p = subprocess.run([sys.executable, str(CJ_RUN), str(time_limit_ms), sys.executable, str(Path(ws, "main.py"))],
                           input=stdin, capture_output=True, timeout=30)
        idx = p.stderr.rfind(RESULT_MARK)
        res = json.loads(p.stderr[idx + len(RESULT_MARK):].split(b"\n", 1)[0])
        return RunResult(res["status"], p.stdout, p.stderr[:idx].decode(), res["time_ms"], res["exit"])


def test_normalize_ignores_trailing_whitespace():
    assert grader.outputs_match(b"8\n", b"8")
    assert grader.outputs_match(b"1 2\n3\n", b"1 2   \r\n3\r\n\r\n")
    assert not grader.outputs_match(b"1 2\n3\n", b"1  2\n3\n")
    assert not grader.outputs_match(b"8\n", b"\n8\n")


def _tests(slug):
    d = SAMPLES / slug / "tests"
    n = len(list(d.glob("*.in")))
    return [((d / f"{i}.in").read_bytes(), (d / f"{i}.out").read_bytes()) for i in range(1, n + 1)]


@pytest.mark.parametrize("solution,status,score", [
    ("ok.py", "ACCEPTED", 100),
    ("wrong.py", "WRONG_ANSWER", 17),   # chỉ test 0 0 đúng
])
def test_grade_sample_solutions(solution, status, score):
    src = (SAMPLES / "a-plus-b" / "solutions" / solution).read_bytes()
    r = grader.grade(LocalPythonSandbox(), "python", src, _tests("a-plus-b"), 2000, 128)
    assert (r.status, r.score) == (status, score), r
    assert r.total == 6


def test_grade_tle():
    src = (SAMPLES / "a-plus-b" / "solutions" / "tle.py").read_bytes()
    r = grader.grade(LocalPythonSandbox(), "python", src, _tests("a-plus-b")[:1], 300, 128)
    assert r.status == "TIME_LIMIT" and r.score == 0


def test_grade_runtime_error_and_compile_error():
    r = grader.grade(LocalPythonSandbox(), "python", b"raise SystemExit(3)", _tests("a-plus-b")[:2], 2000, 128)
    assert r.status == "RUNTIME_ERROR" and r.message.startswith("Test 1: RUNTIME_ERROR")
    r = grader.grade(LocalPythonSandbox(), "python", b"def f(:\n", _tests("a-plus-b"), 2000, 128)
    assert r.status == "COMPILE_ERROR" and "SyntaxError" in r.message and r.total == 6


def test_slow_sum_fast_solution_accepted():
    src = (SAMPLES / "slow-sum" / "solutions" / "fast.py").read_bytes()
    r = grader.grade(LocalPythonSandbox(), "python", src, _tests("slow-sum"), 5000, 128)
    assert r.status == "ACCEPTED", r


def test_docker_command_has_isolation_flags():
    cmd = DockerSandbox(work_root=tempfile.gettempdir()).docker_cmd(
        "/w", ["cj-run", "1000", "/work/main"], memory_mb=256, rw=False, tmpfs_mb=16, name="cj-x")
    s = " ".join(cmd)
    for flag in ("--network none", "--read-only", "--tmpfs /tmp:rw,size=16m", "--memory 256m", "--memory-swap 256m",
                 "--cpus 1", "--pids-limit 64", "--cap-drop ALL", "--security-opt no-new-privileges",
                 "--user 10001:10001", "-v /w:/work:ro", "cj-sandbox:1 cj-run 1000 /work/main"):
        assert flag in s, flag


def _make_submission(engine, storage, cfg, source: bytes, language="python", slug="a-plus-b", status="PENDING"):
    with engine.begin() as conn:
        uid = conn.execute(select(db.users.c.id).where(db.users.c.username == "sv01")).scalar()
        pid = conn.execute(select(db.problems.c.id).where(db.problems.c.slug == slug)).scalar()
        import uuid
        u = str(uuid.uuid4())
        obj = f"{u}/main.py"
        storage.put(cfg.swift_submissions, obj, source)
        res = conn.execute(db.submissions.insert().values(uuid=u, user_id=uid, problem_id=pid, language=language,
                                                          source_object=obj, status=status, created_at=db.utcnow()))
        return int(res.inserted_primary_key[0])


def test_judge_handle_updates_db_and_is_idempotent(cfg, seeded, storage):
    judge = Judge(cfg, seeded, storage, LocalPythonSandbox())
    sid = _make_submission(seeded, storage, cfg, (SAMPLES / "a-plus-b/solutions/ok.py").read_bytes())
    assert judge.handle(sid) == "ACCEPTED"
    with seeded.connect() as conn:
        row = conn.execute(select(db.submissions).where(db.submissions.c.id == sid)).first()
    assert (row.status, row.score, row.passed, row.total) == ("ACCEPTED", 100, 6, 6)
    assert row.worker_host and row.started_at and row.finished_at
    assert judge.handle(sid) is None          # thông điệp lặp: bỏ qua
    assert judge.handle(999999) is None       # không có trong DB


def test_judge_regrades_running_submission(cfg, seeded, storage):
    """Worker trước chết khi đang chấm (RUNNING) → thông điệp được giao lại → chấm lại."""
    judge = Judge(cfg, seeded, storage, LocalPythonSandbox())
    sid = _make_submission(seeded, storage, cfg, b"a,b=map(int,input().split());print(a-b)", status="RUNNING")
    assert judge.handle(sid) == "WRONG_ANSWER"


def test_judge_system_error_when_swift_missing(cfg, seeded, storage):
    judge = Judge(cfg, seeded, storage, LocalPythonSandbox())
    sid = _make_submission(seeded, storage, cfg, b"print(1)")
    storage.objects.clear()
    assert judge.handle(sid) == "SYSTEM_ERROR"


def test_cj_run_reports_ok_tle_re():
    def run(tl, code):
        p = subprocess.run([sys.executable, str(CJ_RUN), str(tl), sys.executable, "-c", code],
                           capture_output=True, input=b"", timeout=30)
        line = p.stderr.strip().splitlines()[-1]
        assert line.startswith(RESULT_MARK)
        return json.loads(line[len(RESULT_MARK):]), p.stdout

    # giới hạn rộng cho case OK/RE: tạo tiến trình Python trên laptop Windows đang bận có thể mất vài giây
    res, out = run(15000, "print('hi')")
    assert res["status"] == "OK" and out.strip() == b"hi"
    res, _ = run(300, "while True: pass")
    assert res["status"] == "TLE" and res["time_ms"] >= 300
    res, _ = run(15000, "import sys; sys.exit(5)")
    assert res["status"] == "RE" and res["exit"] == 5
