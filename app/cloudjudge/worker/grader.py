"""Chấm một bài: biên dịch → chạy từng test → so sánh output → tính điểm."""
from __future__ import annotations

from dataclasses import dataclass

VERDICT_STATUS = {"WA": "WRONG_ANSWER", "TLE": "TIME_LIMIT", "RE": "RUNTIME_ERROR", "OLE": "RUNTIME_ERROR"}
MESSAGE_MAX = 2000


@dataclass
class GradeResult:
    status: str
    score: int
    passed: int
    total: int
    runtime_ms: int
    message: str | None = None


def normalize(data: bytes) -> list[str]:
    """Bỏ khoảng trắng cuối mỗi dòng và các dòng trống ở cuối; chấp nhận cả \\r\\n."""
    lines = [ln.rstrip() for ln in data.decode("utf-8", "replace").replace("\r\n", "\n").split("\n")]
    while lines and not lines[-1]:
        lines.pop()
    return lines


def outputs_match(expected: bytes, actual: bytes) -> bool:
    return normalize(expected) == normalize(actual)


def _short(text: str) -> str:
    text = text.strip()
    return text if len(text) <= MESSAGE_MAX else text[: MESSAGE_MAX - 3] + "..."


def grade(sandbox, language: str, source: bytes, tests: list[tuple[bytes, bytes]],
          time_limit_ms: int, memory_mb: int) -> GradeResult:
    total = len(tests)
    with sandbox.workspace() as ws:
        ok, msg = sandbox.compile(ws, language, source)
        if not ok:
            return GradeResult("COMPILE_ERROR", 0, 0, total, 0, _short(msg))
        passed = 0
        runtime = 0
        first_fail: tuple[int, str, str] | None = None
        for i, (inp, expected) in enumerate(tests, 1):
            r = sandbox.run(ws, language, inp, time_limit_ms, memory_mb)
            runtime += r.time_ms
            if r.status == "OK":
                verdict = "OK" if outputs_match(expected, r.stdout) else "WA"
            else:
                verdict = r.status
            if verdict == "OK":
                passed += 1
            elif first_fail is None:
                detail = r.stderr.strip()[-500:] if verdict == "RE" else ""
                if verdict == "OLE":
                    detail = "Output vượt quá giới hạn 8 MB"
                first_fail = (i, verdict, detail)
    score = round(100 * passed / total) if total else 0
    if first_fail is None:
        return GradeResult("ACCEPTED", 100, passed, total, runtime)
    i, verdict, detail = first_fail
    status = VERDICT_STATUS[verdict]
    message = f"Test {i}: {status}" + (f"\n{detail}" if detail else "")
    return GradeResult(status, score, passed, total, runtime, _short(message))
