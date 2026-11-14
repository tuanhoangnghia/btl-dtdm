"""Nhận bài nộp: lưu mã lên Swift → INSERT PENDING vào Primary → publish vào queue `submissions`."""
from __future__ import annotations

import logging
import uuid

from sqlalchemy import insert, update

from ..common import db
from .metrics import SUBMISSIONS

log = logging.getLogger(__name__)
MAX_SOURCE_BYTES = 64 * 1024
FILENAMES = {"cpp": "main.cpp", "python": "main.py"}


class SubmitError(ValueError):
    pass


class QueueUnavailable(RuntimeError):
    pass


def create_submission(svc, user_id: int, problem_id: int, language: str, source: bytes) -> int:
    if language not in FILENAMES:
        raise SubmitError("Ngôn ngữ phải là cpp hoặc python")
    if not source.strip():
        raise SubmitError("Mã nguồn trống")
    if len(source) > MAX_SOURCE_BYTES:
        raise SubmitError("Mã nguồn tối đa 64 KB")

    sub_uuid = str(uuid.uuid4())
    obj = f"{sub_uuid}/{FILENAMES[language]}"
    svc.storage.put(svc.cfg.swift_submissions, obj, source, content_type="text/plain; charset=utf-8")
    with svc.primary.begin() as conn:
        res = conn.execute(insert(db.submissions).values(
            uuid=sub_uuid, user_id=user_id, problem_id=problem_id, language=language,
            source_object=obj, status="PENDING", created_at=db.utcnow(),
        ))
        sub_id = int(res.inserted_primary_key[0])
    SUBMISSIONS.labels(language=language).inc()

    try:
        svc.publisher.publish(sub_id)
    except Exception as e:
        log.exception("publish submission %s thất bại", sub_id)
        with svc.primary.begin() as conn:
            conn.execute(update(db.submissions).where(db.submissions.c.id == sub_id).values(
                status="SYSTEM_ERROR", message="Không gửi được vào hàng đợi chấm", finished_at=db.utcnow(),
            ))
        raise QueueUnavailable("Hàng đợi chấm đang lỗi, hãy thử lại sau") from e
    log.info("submission %s (%s, %s) đã vào hàng đợi", sub_id, language, obj)
    return sub_id
