"""Metric web cho Prometheus (CONTRACT mục 9).

cj_submissions_total{language}: counter, tăng khi nhận bài.
cj_pending_submissions, cj_oldest_pending_seconds: gauge, truy vấn DB lúc bị scrape. Mọi máy web cùng
báo một giá trị toàn cục, nên ở Prometheus phải gộp bằng max(), không dùng sum().

Gunicorn chạy nhiều tiến trình: khi có PROMETHEUS_MULTIPROC_DIR (unit systemd đặt sẵn) thì counter được
gộp qua thư mục đó, nếu không thì dùng registry mặc định (dev local).
"""
from __future__ import annotations

import os

from prometheus_client import CONTENT_TYPE_LATEST, REGISTRY, CollectorRegistry, Counter, generate_latest
from prometheus_client.core import GaugeMetricFamily
from sqlalchemy import func, select

from ..common import db

SUBMISSIONS = Counter("cj_submissions", "Số bài đã nhận", ["language"])


class PendingCollector:
    def __init__(self, engine):
        self.engine = engine

    def collect(self):
        try:
            with self.engine.connect() as conn:
                pending = conn.execute(
                    select(func.count()).select_from(db.submissions)
                    .where(db.submissions.c.status.in_(("PENDING", "RUNNING")))
                ).scalar() or 0
                oldest = conn.execute(
                    select(func.min(db.submissions.c.created_at)).where(db.submissions.c.status == "PENDING")
                ).scalar()
        except Exception:
            return  # DB lỗi: không báo gauge (InstanceDown / healthz sẽ bắt lỗi này)
        age = max(0.0, (db.utcnow() - oldest).total_seconds()) if oldest else 0.0
        yield GaugeMetricFamily("cj_pending_submissions", "Số bài PENDING + RUNNING", value=pending)
        yield GaugeMetricFamily("cj_oldest_pending_seconds", "Tuổi bài PENDING lâu nhất (giây)", value=age)


def render(engine) -> tuple[bytes, str]:
    if os.environ.get("PROMETHEUS_MULTIPROC_DIR"):
        from prometheus_client import multiprocess
        base = CollectorRegistry()
        multiprocess.MultiProcessCollector(base)
    else:
        base = REGISTRY
    dbreg = CollectorRegistry()
    dbreg.register(PendingCollector(engine))
    return generate_latest(base) + generate_latest(dbreg), CONTENT_TYPE_LATEST
