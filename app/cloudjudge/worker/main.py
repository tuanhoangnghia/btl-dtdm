"""Worker chấm bài: consume queue `submissions`, prefetch_count=1, ack thủ công SAU KHI ghi kết quả vào DB.

Giao nhận at-least-once: một thông điệp có thể tới 2 lần (worker chết giữa chừng, scale in). Việc cập nhật
idempotent theo submission_id: bài đã có kết quả cuối thì bỏ qua; bài đang RUNNING (máy trước đã chết) thì
chấm lại. Lỗi hệ thống được ghi SYSTEM_ERROR rồi ack, để bài lỗi không quay vòng mãi trong hàng đợi.

Chạy: python -m cloudjudge.worker.main
"""
from __future__ import annotations

import collections
import json
import logging
import signal
import socket
import sys
import time

from sqlalchemy import select, update

from ..common import db
from ..common.config import Config
from ..common.problems import read_tests_zip
from . import metrics
from .grader import GradeResult, grade
from .sandbox import DockerSandbox

HOST = socket.gethostname()
log = logging.getLogger("cj-worker")
S, P = db.submissions, db.problems


class Stop(BaseException):
    """Nhận SIGTERM (systemd dừng dịch vụ, Heat xóa máy khi scale in)."""


class TestCache:
    """Giữ tests.zip đã giải nén trong RAM, khóa theo (object, etag) để giảng viên sửa test thì tải lại."""

    def __init__(self, storage, container: str, size: int = 8):
        self.storage, self.container, self.size = storage, container, size
        self._data: collections.OrderedDict = collections.OrderedDict()

    def get(self, obj: str) -> list[tuple[bytes, bytes]]:
        key = (obj, self.storage.etag(self.container, obj))
        if key in self._data:
            self._data.move_to_end(key)
            return self._data[key]
        tests = read_tests_zip(self.storage.get(self.container, obj))
        self._data[key] = tests
        while len(self._data) > self.size:
            self._data.popitem(last=False)
        return tests


class Judge:
    def __init__(self, cfg: Config, engine, storage, sandbox):
        self.cfg, self.engine, self.storage, self.sandbox = cfg, engine, storage, sandbox
        self.tests = TestCache(storage, cfg.swift_testcases)

    def handle(self, submission_id: int) -> str | None:
        """Chấm một bài. Trả về trạng thái cuối, hoặc None nếu bỏ qua. Lỗi DB thì ném ra (không ack)."""
        with self.engine.connect() as conn:
            row = conn.execute(
                select(S.c.id, S.c.status, S.c.language, S.c.source_object,
                       P.c.slug, P.c.testcases_object, P.c.time_limit_ms, P.c.memory_mb)
                .join(P, P.c.id == S.c.problem_id).where(S.c.id == submission_id)
            ).first()
        if row is None:
            log.warning("submission %s không có trong DB, bỏ qua", submission_id)
            return None
        if row.status in db.FINAL_STATUSES:
            log.info("submission %s đã có kết quả %s, bỏ qua (thông điệp lặp)", submission_id, row.status)
            return None

        with self.engine.begin() as conn:
            conn.execute(update(S).where(S.c.id == submission_id, S.c.status.in_(("PENDING", "RUNNING")))
                         .values(status="RUNNING", started_at=db.utcnow(), worker_host=HOST[:64]))
        log.info("bắt đầu chấm submission %s (%s, %s)", submission_id, row.slug, row.language)

        t0 = time.monotonic()
        try:
            source = self.storage.get(self.cfg.swift_submissions, row.source_object)
            tests = self.tests.get(row.testcases_object)
            result = grade(self.sandbox, row.language, source, tests, row.time_limit_ms, row.memory_mb)
        except Exception as e:
            log.exception("lỗi hệ thống khi chấm submission %s", submission_id)
            result = GradeResult("SYSTEM_ERROR", 0, 0, 0, 0, f"Lỗi hệ thống chấm: {type(e).__name__}: {e}"[:2000])
        elapsed = time.monotonic() - t0

        with self.engine.begin() as conn:
            conn.execute(update(S).where(S.c.id == submission_id, S.c.status.in_(("PENDING", "RUNNING")))
                         .values(status=result.status, score=result.score, passed=result.passed,
                                 total=result.total, runtime_ms=result.runtime_ms, message=result.message,
                                 worker_host=HOST[:64], finished_at=db.utcnow()))
        metrics.GRADED.labels(status=result.status).inc()
        metrics.GRADE_DURATION.observe(elapsed)
        log.info("submission %s → %s %s/%s điểm %s (%.1fs)", submission_id, result.status,
                 result.passed, result.total, result.score, elapsed)
        return result.status


def consume(cfg: Config, judge: Judge) -> None:
    import pika

    from ..common.mq import connection_params, declare_queue

    backoff = 1
    while True:
        conn = None
        try:
            # heartbeat dài: callback chấm bài chạy đồng bộ (tới ~1 phút), trong lúc đó pika không gửi heartbeat
            conn = pika.BlockingConnection(connection_params(cfg, heartbeat=300))
            ch = conn.channel()
            declare_queue(ch, cfg)
            ch.basic_qos(prefetch_count=1)

            def on_message(channel, method, _props, body):
                try:
                    sub_id = int(json.loads(body)["submission_id"])
                except (ValueError, KeyError, TypeError):
                    log.error("thông điệp sai định dạng, bỏ: %r", body[:200])
                    channel.basic_ack(method.delivery_tag)
                    return
                try:
                    judge.handle(sub_id)
                except Stop:
                    raise
                except Exception:
                    # thường là mất DB: trả thông điệp lại hàng đợi, nghỉ một chút để không quay vòng nhanh
                    log.exception("không xử lý được submission %s, trả lại hàng đợi", sub_id)
                    channel.basic_nack(method.delivery_tag, requeue=True)
                    time.sleep(5)
                    return
                channel.basic_ack(method.delivery_tag)

            ch.basic_consume(queue=cfg.mq_queue, on_message_callback=on_message)
            log.info("đang chờ bài ở queue %s trên %s:%s", cfg.mq_queue, cfg.mq_host, cfg.mq_port)
            backoff = 1
            ch.start_consuming()
        except Stop:
            log.info("nhận SIGTERM, dừng (bài đang chấm dở chưa ack sẽ được chuyển cho worker khác)")
            if conn is not None and conn.is_open:
                try:
                    conn.close()
                except Exception:
                    pass
            return
        except pika.exceptions.AMQPError as e:
            log.warning("mất kết nối RabbitMQ (%s), thử lại sau %ss", type(e).__name__, backoff)
        except OSError as e:
            log.warning("lỗi mạng tới RabbitMQ (%s), thử lại sau %ss", e, backoff)
        time.sleep(backoff)
        backoff = min(backoff * 2, 30)


def main() -> int:
    logging.basicConfig(level=logging.INFO, stream=sys.stdout,
                        format=f"%(asctime)s {HOST} %(name)s %(levelname)s %(message)s")
    logging.getLogger("pika").setLevel(logging.WARNING)

    def _stop(_sig, _frm):
        raise Stop()

    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)

    from ..common.db import make_engines
    from ..common.storage import Storage

    cfg = Config.from_env()
    primary, _replica = make_engines(cfg)
    judge = Judge(cfg, primary, Storage(cfg), DockerSandbox())
    metrics.serve()
    log.info("worker %s khởi động, release %s, metrics :%s", HOST, cfg.release, metrics.METRICS_PORT)
    consume(cfg, judge)
    return 0


if __name__ == "__main__":
    sys.exit(main())
