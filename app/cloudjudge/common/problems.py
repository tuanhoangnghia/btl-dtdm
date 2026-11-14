"""Bài tập và bộ test: dùng chung cho web (giảng viên tạo bài) và CLI seed.

tests.zip gồm các cặp 1.in/1.out, 2.in/2.out, ... đánh số liên tục từ 1 (CONTRACT mục 8.1).
"""
from __future__ import annotations

import io
import re
import zipfile

from sqlalchemy import insert, select, update

from . import db

SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9-]{1,62}$")
MAX_TESTS = 50


class ProblemError(ValueError):
    pass


def read_tests_zip(data: bytes) -> list[tuple[bytes, bytes]]:
    """Trả về [(input, expected_output), ...] theo thứ tự test. Báo lỗi nếu zip sai định dạng."""
    try:
        zf = zipfile.ZipFile(io.BytesIO(data))
    except zipfile.BadZipFile as e:
        raise ProblemError("File không phải zip hợp lệ") from e
    files: dict[str, bytes] = {}
    for info in zf.infolist():
        if info.is_dir():
            continue
        name = info.filename.rsplit("/", 1)[-1]
        if re.fullmatch(r"\d+\.(in|out)", name):
            files[name] = zf.read(info)
    n = 0
    while f"{n + 1}.in" in files and f"{n + 1}.out" in files:
        n += 1
    if n == 0:
        raise ProblemError("tests.zip phải có 1.in và 1.out")
    if len(files) != 2 * n:
        raise ProblemError("Các test phải là cặp N.in/N.out đánh số liên tục từ 1")
    if n > MAX_TESTS:
        raise ProblemError(f"Tối đa {MAX_TESTS} test")
    return [(files[f"{i}.in"], files[f"{i}.out"]) for i in range(1, n + 1)]


def build_tests_zip(tests: list[tuple[bytes, bytes]]) -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for i, (inp, out) in enumerate(tests, 1):
            zf.writestr(f"{i}.in", inp)
            zf.writestr(f"{i}.out", out)
    return buf.getvalue()


def save_problem(engine, storage, container: str, *, slug: str, title: str, statement_md: str,
                 time_limit_ms: int, memory_mb: int, tests_zip: bytes, created_by: int,
                 allow_update: bool = False) -> int:
    """Upload tests.zip lên Swift rồi ghi bảng problems. Trả về id bài."""
    if not SLUG_RE.match(slug):
        raise ProblemError("Slug chỉ gồm chữ thường, số, dấu '-' (2–63 ký tự)")
    if not title.strip():
        raise ProblemError("Thiếu tiêu đề")
    if not 100 <= time_limit_ms <= 10000:
        raise ProblemError("Giới hạn thời gian phải trong 100–10000 ms")
    if not 32 <= memory_mb <= 1024:
        raise ProblemError("Giới hạn bộ nhớ phải trong 32–1024 MB")
    tests = read_tests_zip(tests_zip)

    with engine.connect() as conn:
        existing = conn.execute(select(db.problems.c.id).where(db.problems.c.slug == slug)).scalar()
    if existing is not None and not allow_update:
        raise ProblemError(f"Bài '{slug}' đã tồn tại")

    obj = f"{slug}/tests.zip"
    storage.put(container, obj, tests_zip, content_type="application/zip")
    values = dict(title=title.strip(), statement_md=statement_md, time_limit_ms=time_limit_ms,
                  memory_mb=memory_mb, testcases_object=obj, test_count=len(tests))
    with engine.begin() as conn:
        if existing is None:
            res = conn.execute(insert(db.problems).values(slug=slug, created_by=created_by,
                                                          created_at=db.utcnow(), **values))
            return int(res.inserted_primary_key[0])
        conn.execute(update(db.problems).where(db.problems.c.id == existing).values(**values))
        return int(existing)
