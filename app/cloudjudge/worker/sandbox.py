"""Chạy mã của sinh viên trong container Docker cách ly (KE_HOACH 10.4).

Mỗi lần biên dịch / mỗi test là một `docker run --rm` riêng:
  --network none --read-only --tmpfs /tmp --memory = --memory-swap --cpus 1 --pids-limit 64
  --cap-drop ALL --security-opt no-new-privileges --user 10001:10001 -v <workdir>:/work:ro
Biên dịch C++ cần ghi file chạy ra /work nên chỉ bước đó mount rw. Thời gian đo bởi cj-run bên trong container
(không tính thời gian docker khởi động container).
"""
from __future__ import annotations

import ast
import contextlib
import json
import logging
import os
import shutil
import subprocess
import tempfile
import threading
import uuid
from dataclasses import dataclass

log = logging.getLogger(__name__)

SANDBOX_IMAGE = "cj-sandbox:1"
RESULT_MARK = b"__CJ_RESULT__ "
OUTPUT_LIMIT = 8 * 1024 * 1024
STDERR_KEEP = 64 * 1024
COMPILE_TIMEOUT_MS = 30000
COMPILE_MEMORY_MB = 512
DOCKER_OVERHEAD_S = 20      # thời gian dự phòng cho docker tạo/xóa container


class SandboxError(RuntimeError):
    """Lỗi của hệ thống chấm (Docker hỏng, thiếu image...), không phải lỗi của bài làm."""


@dataclass
class RunResult:
    status: str          # OK | TLE | RE | OLE
    stdout: bytes
    stderr: str
    time_ms: int
    exit_code: int | None = None


def default_work_root() -> str:
    root = "/var/lib/cj/work"
    if os.path.isdir(root) and os.access(root, os.W_OK):
        return root
    path = os.path.join(tempfile.gettempdir(), "cj-work")
    os.makedirs(path, exist_ok=True)
    return path


SOURCE_FILES = {"cpp": "main.cpp", "python": "main.py"}


class DockerSandbox:
    def __init__(self, image: str = SANDBOX_IMAGE, work_root: str | None = None, docker: str = "docker"):
        self.image = image
        self.work_root = work_root or default_work_root()
        self.docker = docker

    @contextlib.contextmanager
    def workspace(self):
        path = tempfile.mkdtemp(prefix="sub-", dir=self.work_root)
        os.chmod(path, 0o777)  # bước biên dịch chạy bằng uid 10001 cần ghi file chạy vào đây
        try:
            yield path
        finally:
            shutil.rmtree(path, ignore_errors=True)

    def docker_cmd(self, ws: str, argv: list[str], *, memory_mb: int, rw: bool, tmpfs_mb: int, name: str) -> list[str]:
        return [
            self.docker, "run", "--rm", "-i", "--name", name,
            "--network", "none",
            "--read-only", "--tmpfs", f"/tmp:rw,size={tmpfs_mb}m",
            "--memory", f"{memory_mb}m", "--memory-swap", f"{memory_mb}m",
            "--cpus", "1", "--pids-limit", "64",
            "--cap-drop", "ALL", "--security-opt", "no-new-privileges",
            "--user", "10001:10001",
            "-v", f"{ws}:/work:{'rw' if rw else 'ro'}", "-w", "/work",
            self.image, *argv,
        ]

    # ---------- API dùng bởi grader ----------
    def compile(self, ws: str, language: str, source: bytes) -> tuple[bool, str]:
        path = os.path.join(ws, SOURCE_FILES[language])
        with open(path, "wb") as f:
            f.write(source)
        os.chmod(path, 0o644)
        if language == "python":
            # chỉ phân tích cú pháp (không thực thi), an toàn khi làm ngay trên worker
            try:
                ast.parse(source, filename="main.py")
            except (SyntaxError, ValueError, MemoryError, RecursionError) as e:
                return False, f"{type(e).__name__}: {e}"
            return True, ""
        r = self._exec(ws, ["cj-run", str(COMPILE_TIMEOUT_MS), "g++", "-O2", "-std=c++17", "-pipe",
                            "-o", "/work/main", "/work/main.cpp"],
                       b"", memory_mb=COMPILE_MEMORY_MB, rw=True, tmpfs_mb=64, timeout_ms=COMPILE_TIMEOUT_MS)
        if r.status == "OK":
            return True, ""
        if r.status == "TLE":
            return False, "Biên dịch quá 30 giây"
        return False, r.stderr.strip() or "Biên dịch thất bại"

    def run(self, ws: str, language: str, stdin: bytes, time_limit_ms: int, memory_mb: int) -> RunResult:
        prog = ["/work/main"] if language == "cpp" else ["python3", "/work/main.py"]
        return self._exec(ws, ["cj-run", str(time_limit_ms), *prog], stdin,
                          memory_mb=memory_mb, rw=False, tmpfs_mb=16, timeout_ms=time_limit_ms)

    # ---------- nội bộ ----------
    def _kill(self, name: str) -> None:
        subprocess.run([self.docker, "kill", name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)

    def _exec(self, ws, argv, stdin: bytes, *, memory_mb, rw, tmpfs_mb, timeout_ms) -> RunResult:
        name = f"cj-{uuid.uuid4().hex[:12]}"
        cmd = self.docker_cmd(ws, argv, memory_mb=memory_mb, rw=rw, tmpfs_mb=tmpfs_mb, name=name)
        try:
            proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        except OSError as e:
            raise SandboxError(f"không chạy được docker: {e}") from e

        out = bytearray()
        err = bytearray()
        state = {"ole": False}

        def feed():
            try:
                proc.stdin.write(stdin)
            except (BrokenPipeError, OSError):
                pass
            finally:
                with contextlib.suppress(OSError):
                    proc.stdin.close()

        def read_out():
            while chunk := proc.stdout.read(65536):
                if len(out) + len(chunk) > OUTPUT_LIMIT:
                    if not state["ole"]:
                        state["ole"] = True
                        self._kill(name)
                    continue
                out.extend(chunk)

        def read_err():
            while chunk := proc.stderr.read(65536):
                err.extend(chunk)
                if len(err) > 2 * STDERR_KEEP:
                    del err[:-STDERR_KEEP]

        threads = [threading.Thread(target=t, daemon=True) for t in (feed, read_out, read_err)]
        for t in threads:
            t.start()
        hard_timeout = False
        try:
            proc.wait(timeout=timeout_ms / 1000 + DOCKER_OVERHEAD_S)
        except subprocess.TimeoutExpired:
            hard_timeout = True
            self._kill(name)
            proc.kill()
            proc.wait()
        for t in threads:
            t.join(timeout=5)

        idx = err.rfind(RESULT_MARK)
        result = None
        if idx >= 0:
            with contextlib.suppress(ValueError):
                result = json.loads(err[idx + len(RESULT_MARK):].split(b"\n", 1)[0])
            stderr_text = err[:idx].decode("utf-8", "replace")
        else:
            stderr_text = err.decode("utf-8", "replace")

        if state["ole"]:
            return RunResult("OLE", bytes(out), stderr_text, (result or {}).get("time_ms", 0))
        if result is None:
            if proc.returncode in (125, 126, 127) and not hard_timeout:
                raise SandboxError(f"docker run lỗi (exit {proc.returncode}): {stderr_text.strip()[-500:]}")
            status = "TLE" if hard_timeout else "RE"   # vd 137: container bị giết vì hết bộ nhớ
            return RunResult(status, bytes(out), stderr_text, timeout_ms if hard_timeout else 0, proc.returncode)
        return RunResult(result["status"], bytes(out), stderr_text, int(result.get("time_ms", 0)), result.get("exit"))
