"""Lệnh quản trị.

  python -m cloudjudge.cli seed [--problems-dir DIR]        tài khoản demo + bài mẫu (chạy lại được)
  python -m cloudjudge.cli create-problem DIR [--update]    thêm 1 bài từ thư mục
  python -m cloudjudge.cli set-password USER                đổi mật khẩu (đọc từ stdin)

Mật khẩu tài khoản demo: biến CJ_SEED_PASSWORD hoặc --password; không có thì sinh ngẫu nhiên và in ra MỘT lần.
Token loadtest: biến LOADTEST_TOKEN (~/secrets/app.env) hoặc --loadtest-token; không có thì sinh và in ra.
Tài khoản đã tồn tại thì giữ nguyên mật khẩu (trừ khi --reset-passwords).
Trên VM web: sudo cj-cli seed  (wrapper nạp /etc/cloudjudge/cloudjudge.env)
"""
from __future__ import annotations

import argparse
import getpass
import json
import secrets
import sys
from pathlib import Path

from sqlalchemy import insert, select, update
from werkzeug.security import generate_password_hash

from .common import db
from .common.config import Config, load_environ
from .common.problems import build_tests_zip, save_problem

DEFAULT_PROBLEMS = Path(__file__).resolve().parent.parent / "sample_problems"
TEACHER = "gv01"
STUDENTS = [f"sv{i:02d}" for i in range(1, 6)]
LOADTEST = "loadtest"


def _upsert_user(conn, username: str, role: str, password: str | None, token: str | None, reset: bool) -> str:
    row = conn.execute(select(db.users.c.id).where(db.users.c.username == username)).first()
    if row is None:
        conn.execute(insert(db.users).values(
            username=username, role=role, api_token=token, created_at=db.utcnow(),
            password_hash=generate_password_hash(password or secrets.token_urlsafe(24)),
        ))
        return "tạo mới"
    values = {"role": role}
    if token:
        values["api_token"] = token
    if reset and password:
        values["password_hash"] = generate_password_hash(password)
    conn.execute(update(db.users).where(db.users.c.id == row.id).values(**values))
    return "đã có, cập nhật" if reset else "đã có"


def load_problem_dir(path: Path) -> dict:
    meta = json.loads((path / "problem.json").read_text(encoding="utf-8"))
    tests = []
    i = 1
    while (path / "tests" / f"{i}.in").exists():
        tests.append(((path / "tests" / f"{i}.in").read_bytes(), (path / "tests" / f"{i}.out").read_bytes()))
        i += 1
    return dict(
        slug=meta["slug"], title=meta["title"],
        time_limit_ms=int(meta.get("time_limit_ms", 2000)), memory_mb=int(meta.get("memory_mb", 256)),
        statement_md=(path / "statement.md").read_text(encoding="utf-8"), tests_zip=build_tests_zip(tests),
    )


def _teacher_id(engine) -> int:
    with engine.connect() as conn:
        tid = conn.execute(select(db.users.c.id).where(db.users.c.role == "teacher").order_by(db.users.c.id)).scalar()
    if tid is None:
        raise SystemExit("Chưa có tài khoản giảng viên, hãy chạy seed trước")
    return int(tid)


def cmd_seed(args, cfg, engine, storage) -> None:
    if cfg.storage_auth == "tempauth":
        for c in (cfg.swift_submissions, cfg.swift_testcases):
            storage.ensure_container(c)

    env = load_environ()
    password = args.password or env.get("CJ_SEED_PASSWORD")
    generated = password is None
    if generated:
        password = secrets.token_urlsafe(9)
    token = args.loadtest_token or env.get("LOADTEST_TOKEN")
    if token and len(token) != 64:
        raise SystemExit("LOADTEST_TOKEN phải dài đúng 64 ký tự (vd: openssl rand -hex 32)")
    token_generated = token is None
    if token_generated:
        with engine.connect() as conn:
            token = conn.execute(select(db.users.c.api_token).where(db.users.c.username == LOADTEST)).scalar()
        token_generated = token is None
        token = token or secrets.token_hex(32)

    with engine.begin() as conn:
        print(f"{TEACHER}: {_upsert_user(conn, TEACHER, 'teacher', password, None, args.reset_passwords)}")
        for u in STUDENTS:
            print(f"{u}: {_upsert_user(conn, u, 'student', password, None, args.reset_passwords)}")
        print(f"{LOADTEST}: {_upsert_user(conn, LOADTEST, 'student', None, token, False)}")

    tid = _teacher_id(engine)
    for d in sorted(p for p in Path(args.problems_dir).iterdir() if (p / "problem.json").exists()):
        pid = save_problem(engine, storage, cfg.swift_testcases, created_by=tid, allow_update=True,
                           **load_problem_dir(d))
        print(f"bài {d.name}: id={pid}")

    if generated:
        print(f"\nMật khẩu chung của {TEACHER}, {', '.join(STUDENTS)} (chỉ in lần này): {password}")
    if token_generated:
        print(f"Token API của {LOADTEST} (lưu vào ~/secrets/app.env, biến LOADTEST_TOKEN): {token}")


def cmd_create_problem(args, cfg, engine, storage) -> None:
    pid = save_problem(engine, storage, cfg.swift_testcases, created_by=_teacher_id(engine),
                       allow_update=args.update, **load_problem_dir(Path(args.dir)))
    print(f"id={pid}")


def cmd_set_password(args, cfg, engine, storage) -> None:
    pw = sys.stdin.readline().rstrip("\n") if not sys.stdin.isatty() else getpass.getpass("Mật khẩu mới: ")
    if len(pw) < 6:
        raise SystemExit("Mật khẩu tối thiểu 6 ký tự")
    with engine.begin() as conn:
        n = conn.execute(update(db.users).where(db.users.c.username == args.username)
                         .values(password_hash=generate_password_hash(pw))).rowcount
    print("đã đổi" if n else "không có user này")


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(prog="cloudjudge.cli")
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("seed", help="tài khoản demo + bài mẫu")
    s.add_argument("--problems-dir", default=str(DEFAULT_PROBLEMS))
    s.add_argument("--password")
    s.add_argument("--loadtest-token")
    s.add_argument("--reset-passwords", action="store_true")
    s.set_defaults(func=cmd_seed)
    c = sub.add_parser("create-problem", help="thêm bài từ thư mục (problem.json, statement.md, tests/)")
    c.add_argument("dir")
    c.add_argument("--update", action="store_true")
    c.set_defaults(func=cmd_create_problem)
    p = sub.add_parser("set-password")
    p.add_argument("username")
    p.set_defaults(func=cmd_set_password)
    return ap


def main(argv=None, *, cfg=None, engine=None, storage=None) -> int:
    args = build_parser().parse_args(argv)
    cfg = cfg or Config.from_env()
    if engine is None:
        engine = db.make_engines(cfg)[0]
    if storage is None:
        from .common.storage import Storage
        storage = Storage(cfg)
    args.func(args, cfg, engine, storage)
    return 0


if __name__ == "__main__":
    sys.exit(main())
