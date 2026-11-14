"""API JSON cho script tạo tải (scripts/loadtest.py). Xác thực bằng header X-API-Token."""
from __future__ import annotations

import hmac

from flask import Blueprint, abort, g, jsonify, request
from sqlalchemy import select

from ..common import db
from . import services
from .submit import QueueUnavailable, SubmitError, create_submission

bp = Blueprint("api", __name__, url_prefix="/api")
S, P, U = db.submissions, db.problems, db.users


@bp.before_request
def _auth():
    token = request.headers.get("X-API-Token", "")
    if len(token) != 64:
        abort(401)
    with services().primary.connect() as conn:
        row = conn.execute(select(U.c.id, U.c.api_token).where(U.c.api_token == token)).first()
    if row is None or not hmac.compare_digest(row.api_token, token):
        abort(401)
    g.api_user_id = row.id


def _iso(dt):
    return dt.isoformat() + "Z" if dt else None


@bp.post("/submit")
def submit():
    data = request.get_json(silent=True) or {}
    with services().primary.connect() as conn:
        pid = conn.execute(select(P.c.id).where(P.c.slug == str(data.get("problem", "")))).scalar()
    if pid is None:
        return jsonify(error="unknown problem"), 404
    try:
        sub_id = create_submission(services(), g.api_user_id, pid, str(data.get("language", "")),
                                   str(data.get("source", "")).encode("utf-8"))
    except SubmitError as e:
        return jsonify(error=str(e)), 400
    except QueueUnavailable as e:
        return jsonify(error=str(e)), 503
    return jsonify(id=sub_id, status="PENDING"), 201


@bp.get("/submissions/<int:sub_id>")
def submission(sub_id):
    with services().primary.connect() as conn:
        r = conn.execute(select(S).where(S.c.id == sub_id, S.c.user_id == g.api_user_id)).first()
    if r is None:
        return jsonify(error="not found"), 404
    return jsonify(id=r.id, status=r.status, score=r.score, passed=r.passed, total=r.total,
                   runtime_ms=r.runtime_ms, worker_host=r.worker_host, created_at=_iso(r.created_at),
                   started_at=_iso(r.started_at), finished_at=_iso(r.finished_at))
