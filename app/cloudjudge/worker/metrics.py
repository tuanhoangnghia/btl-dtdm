"""Metric worker trên cổng 9200 (CONTRACT mục 9)."""
from prometheus_client import Counter, Histogram, start_http_server

METRICS_PORT = 9200

GRADED = Counter("cj_graded", "Số bài đã chấm theo kết quả", ["status"])
GRADE_DURATION = Histogram(
    "cj_grade_duration_seconds", "Thời gian chấm 1 bài (tải mã + test, biên dịch, chạy)",
    buckets=(0.5, 1, 2, 3, 5, 8, 10, 15, 20, 30, 45, 60, 120),
)


def serve() -> None:
    start_http_server(METRICS_PORT, addr="0.0.0.0")
