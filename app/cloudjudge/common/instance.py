"""Hostname và AZ của máy đang chạy (hiển thị ở footer và /healthz để demo LB chia tải sang 2 AZ)."""
from __future__ import annotations

import functools
import json
import socket
import urllib.request

META_URL = "http://169.254.169.254/openstack/latest/meta_data.json"


@functools.lru_cache(maxsize=1)
def instance_info() -> tuple[str, str]:
    host = socket.gethostname()
    try:
        with urllib.request.urlopen(META_URL, timeout=1) as r:
            az = json.load(r).get("availability_zone") or "unknown"
    except Exception:
        az = "local"
    return host, az
