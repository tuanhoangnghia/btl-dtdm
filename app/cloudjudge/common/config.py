"""Đọc cấu hình từ biến môi trường (CONTRACT mục 7).

Trên VM, systemd nạp /etc/cloudjudge/cloudjudge.env qua EnvironmentFile. Khi chạy tay (CLI, dev local),
file env được đọc trực tiếp: đường dẫn lấy từ CJ_ENV_FILE, mặc định /etc/cloudjudge/cloudjudge.env.
Biến đã có trong môi trường luôn được ưu tiên hơn giá trị trong file.
"""
from __future__ import annotations

import os
from dataclasses import dataclass

DEFAULT_ENV_FILE = "/etc/cloudjudge/cloudjudge.env"


def parse_env_file(path: str) -> dict[str, str]:
    """Đọc file dạng KEY=value. Bỏ dòng trống, dòng chú thích và chú thích cuối dòng sau ' #'."""
    out: dict[str, str] = {}
    with open(path, encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, val = line.split("=", 1)
            val = val.split(" #", 1)[0].strip()
            if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
                val = val[1:-1]
            out[key.strip()] = val
    return out


def load_environ() -> dict[str, str]:
    env: dict[str, str] = {}
    path = os.environ.get("CJ_ENV_FILE", DEFAULT_ENV_FILE)
    if os.path.isfile(path) and os.access(path, os.R_OK):
        env.update(parse_env_file(path))
    env.update(os.environ)
    return env


@dataclass(frozen=True)
class Config:
    role: str = "web"
    release: str = "dev"
    db_primary_host: str = "127.0.0.1"
    db_replica_host: str = "127.0.0.1"
    db_port: int = 3306
    db_name: str = "cloudjudge"
    db_user: str = "cj_app"
    db_password: str = ""
    db_ro_user: str = "cj_ro"
    db_ro_password: str = ""
    mq_host: str = "127.0.0.1"
    mq_port: int = 5672
    mq_user: str = "cj"
    mq_password: str = ""
    mq_queue: str = "submissions"
    storage_auth: str = "appcred"
    os_auth_url: str = "http://10.10.0.10:5000/v3"
    os_region_name: str = "RegionOne"
    os_ac_id: str = ""
    os_ac_secret: str = ""
    st_auth: str = ""
    st_user: str = ""
    st_key: str = ""
    swift_submissions: str = "submissions"
    swift_testcases: str = "testcases"
    secret_key: str = ""

    @classmethod
    def from_env(cls, env: dict[str, str] | None = None) -> "Config":
        e = load_environ() if env is None else env
        g = lambda k, d="": e.get(k, d)  # noqa: E731
        return cls(
            role=g("CJ_ROLE", "web"),
            release=g("CJ_RELEASE", "dev"),
            db_primary_host=g("DB_PRIMARY_HOST", "127.0.0.1"),
            db_replica_host=g("DB_REPLICA_HOST") or g("DB_PRIMARY_HOST", "127.0.0.1"),
            db_port=int(g("DB_PORT", "3306")),
            db_name=g("DB_NAME", "cloudjudge"),
            db_user=g("DB_USER", "cj_app"),
            db_password=g("DB_PASSWORD"),
            db_ro_user=g("DB_RO_USER", "cj_ro"),
            db_ro_password=g("DB_RO_PASSWORD"),
            mq_host=g("MQ_HOST", "127.0.0.1"),
            mq_port=int(g("MQ_PORT", "5672")),
            mq_user=g("MQ_USER", "cj"),
            mq_password=g("MQ_PASSWORD"),
            mq_queue=g("MQ_QUEUE", "submissions"),
            storage_auth=g("STORAGE_AUTH", "appcred"),
            os_auth_url=g("OS_AUTH_URL", "http://10.10.0.10:5000/v3"),
            os_region_name=g("OS_REGION_NAME", "RegionOne"),
            os_ac_id=g("OS_AC_ID"),
            os_ac_secret=g("OS_AC_SECRET"),
            st_auth=g("ST_AUTH"),
            st_user=g("ST_USER"),
            st_key=g("ST_KEY"),
            swift_submissions=g("SWIFT_SUBMISSIONS", "submissions"),
            swift_testcases=g("SWIFT_TESTCASES", "testcases"),
            secret_key=g("SECRET_KEY"),
        )
