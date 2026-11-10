"""Hostname và AZ của máy đang chạy (hiển thị ở footer và /healthz để demo LB chia tải sang 2 AZ)."""
from __future__ import annotations

import json
import socket
import time
import urllib.request

META_URL = "http://169.254.169.254/openstack/latest/meta_data.json"
RETRY_S = 30

_az: str | None = None
_retry_at = 0.0


def instance_info() -> tuple[str, str]:
    # Không nhớ kết quả lỗi: khi cả cụm vừa bật lại, gunicorn có thể lên trước metadata service (đã gặp trên cụm).
    global _az, _retry_at
    if _az is None and time.monotonic() >= _retry_at:
        try:
            with urllib.request.urlopen(META_URL, timeout=1) as r:
                _az = json.load(r).get("availability_zone") or "unknown"
        except Exception:
            _retry_at = time.monotonic() + RETRY_S
    return socket.gethostname(), _az or "local"
