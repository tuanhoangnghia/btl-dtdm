"""Bảng và engine CSDL.

Định nghĩa bảng ở đây phải KHỚP db/schema.sql (C sở hữu). App không tự tạo bảng trên MySQL;
metadata.create_all chỉ dùng trong test (SQLite).
Ghi vào Primary bằng cj_app; trang /scoreboard đọc Replica bằng cj_ro.
"""
from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import (
    BigInteger, Column, DateTime, Enum, ForeignKey, Integer, MetaData, SmallInteger, String, Table, Text,
    create_engine,
)
from sqlalchemy.dialects import mysql
from sqlalchemy.engine import URL, Engine

from .config import Config

metadata = MetaData()

# SQLite chỉ tự tăng với INTEGER PRIMARY KEY; MySQL dùng đúng kiểu trong schema.
_ID = Integer().with_variant(mysql.INTEGER(unsigned=True), "mysql")
_BIGID = BigInteger().with_variant(Integer, "sqlite")
_TS = DateTime().with_variant(mysql.DATETIME(fsp=3), "mysql")

FINAL_STATUSES = ("ACCEPTED", "WRONG_ANSWER", "TIME_LIMIT", "RUNTIME_ERROR", "COMPILE_ERROR", "SYSTEM_ERROR")
STATUSES = ("PENDING", "RUNNING") + FINAL_STATUSES
LANGUAGES = ("cpp", "python")


def utcnow() -> datetime:
    """Mọi mốc thời gian do app ghi đều là UTC (naive), để tuổi bài chờ tính đúng trên mọi máy."""
    return datetime.now(timezone.utc).replace(tzinfo=None)


users = Table(
    "users", metadata,
    Column("id", _ID, primary_key=True, autoincrement=True),
    Column("username", String(64), nullable=False, unique=True),
    Column("password_hash", String(255), nullable=False),
    Column("role", Enum("student", "teacher", name="user_role"), nullable=False, default="student"),
    Column("api_token", String(64), nullable=True, unique=True),
    Column("created_at", _TS, nullable=False, default=utcnow),
)

problems = Table(
    "problems", metadata,
    Column("id", _ID, primary_key=True, autoincrement=True),
    Column("slug", String(64), nullable=False, unique=True),
    Column("title", String(200), nullable=False),
    Column("statement_md", Text, nullable=False),
    Column("time_limit_ms", Integer, nullable=False, default=2000),
    Column("memory_mb", Integer, nullable=False, default=256),
    Column("testcases_object", String(255), nullable=False),
    Column("test_count", SmallInteger, nullable=False),
    Column("created_by", _ID, ForeignKey("users.id"), nullable=False),
    Column("created_at", _TS, nullable=False, default=utcnow),
)

submissions = Table(
    "submissions", metadata,
    Column("id", _BIGID, primary_key=True, autoincrement=True),
    Column("uuid", String(36), nullable=False, unique=True),
    Column("user_id", _ID, ForeignKey("users.id"), nullable=False),
    Column("problem_id", _ID, ForeignKey("problems.id"), nullable=False),
    Column("language", Enum(*LANGUAGES, name="sub_language"), nullable=False),
    Column("source_object", String(255), nullable=False),
    Column("status", Enum(*STATUSES, name="sub_status"), nullable=False, default="PENDING"),
    Column("score", SmallInteger, nullable=True),
    Column("passed", SmallInteger, nullable=True),
    Column("total", SmallInteger, nullable=True),
    Column("runtime_ms", Integer, nullable=True),
    Column("message", String(2000), nullable=True),
    Column("worker_host", String(64), nullable=True),
    Column("created_at", _TS, nullable=False, default=utcnow),
    Column("started_at", _TS, nullable=True),
    Column("finished_at", _TS, nullable=True),
)


def _url(cfg: Config, host: str, user: str, password: str) -> URL:
    return URL.create(
        "mysql+pymysql", username=user, password=password, host=host, port=cfg.db_port,
        database=cfg.db_name, query={"charset": "utf8mb4"},
    )


def _engine(url: URL) -> Engine:
    return create_engine(
        url,
        pool_pre_ping=True,      # máy DB khởi động lại / failover thì kết nối cũ bị bỏ
        pool_recycle=280,
        pool_size=5,
        max_overflow=5,
        connect_args={"connect_timeout": 3, "read_timeout": 10, "write_timeout": 10},
    )


def make_engines(cfg: Config) -> tuple[Engine, Engine]:
    """Trả về (primary, replica). Local dev: DB_REPLICA_HOST trỏ cùng MySQL với primary."""
    primary = _engine(_url(cfg, cfg.db_primary_host, cfg.db_user, cfg.db_password))
    replica = _engine(_url(cfg, cfg.db_replica_host, cfg.db_ro_user, cfg.db_ro_password or cfg.db_password))
    return primary, replica
