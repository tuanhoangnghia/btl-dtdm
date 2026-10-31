"""Trang HTML (KE_HOACH mục 10.3)."""
from __future__ import annotations

import functools
import logging

from flask import Blueprint, Response, abort, flash, jsonify, redirect, render_template, request, session, url_for
from sqlalchemy import func, select, text
from werkzeug.security import check_password_hash

from ..common import db
from ..common.problems import ProblemError, save_problem
from . import markdown, metrics, services
from .submit import QueueUnavailable, SubmitError, create_submission

log = logging.getLogger(__name__)
bp = Blueprint("web", __name__)

S, P, U = db.submissions, db.problems, db.users


def login_required(view):
    @functools.wraps(view)
    def wrapper(*a, **kw):
        if not session.get("user"):
            return redirect(url_for("web.login", next=request.path))
        return view(*a, **kw)
    return wrapper


def teacher_required(view):
    @functools.wraps(view)
    @login_required
    def wrapper(*a, **kw):
        if session["user"]["role"] != "teacher":
            abort(403)
        return view(*a, **kw)
    return wrapper


@bp.get("/")
def index():
    return redirect(url_for("web.problem_list"))


@bp.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        username = request.form.get("username", "").strip()
        with services().primary.connect() as conn:
            row = conn.execute(select(U.c.id, U.c.username, U.c.role, U.c.password_hash)
                               .where(U.c.username == username)).first()
        if row and check_password_hash(row.password_hash, request.form.get("password", "")):
            csrf = session.get("csrf")
            session.clear()
            session["csrf"] = csrf
            session["user"] = {"id": row.id, "username": row.username, "role": row.role}
            nxt = request.args.get("next", "")
            return redirect(nxt if nxt.startswith("/") and not nxt.startswith("//") else url_for("web.problem_list"))
        flash("Sai tên đăng nhập hoặc mật khẩu", "error")
    return render_template("login.html")


@bp.post("/logout")
def logout():
    session.pop("user", None)
    return redirect(url_for("web.login"))


@bp.get("/problems")
def problem_list():
    svc = services()
    me = session.get("user")
    with svc.primary.connect() as conn:
        rows = conn.execute(select(P.c.id, P.c.slug, P.c.title, P.c.time_limit_ms, P.c.test_count)
                            .order_by(P.c.id)).all()
        best = {}
        if me:
            best = dict(conn.execute(select(S.c.problem_id, func.max(S.c.score))
                                     .where(S.c.user_id == me["id"]).group_by(S.c.problem_id)).all())
    return render_template("problems.html", problems=rows, best=best)


def _load_problem(conn, slug):
    row = conn.execute(select(P).where(P.c.slug == slug)).first()
    if row is None:
        abort(404)
    return row


@bp.get("/problems/<slug>")
def problem_view(slug):
    svc = services()
    me = session.get("user")
    with svc.primary.connect() as conn:
        problem = _load_problem(conn, slug)
        mine = []
        if me:
            mine = conn.execute(select(S.c.id, S.c.language, S.c.status, S.c.score, S.c.created_at)
                                .where(S.c.user_id == me["id"], S.c.problem_id == problem.id)
                                .order_by(S.c.id.desc()).limit(10)).all()
    return render_template("problem.html", problem=problem, statement=markdown.render(problem.statement_md),
                           mine=mine)


@bp.post("/problems/<slug>/submit")
@login_required
def problem_submit(slug):
    svc = services()
    with svc.primary.connect() as conn:
        problem = _load_problem(conn, slug)
    upload = request.files.get("source_file")
    source = upload.read() if upload and upload.filename else request.form.get("source", "").encode("utf-8")
    try:
        sub_id = create_submission(svc, session["user"]["id"], problem.id, request.form.get("language", ""), source)
    except (SubmitError, QueueUnavailable) as e:
        flash(str(e), "error")
        return redirect(url_for("web.problem_view", slug=slug))
    return redirect(url_for("web.submission_view", sub_id=sub_id))


def _load_submission(conn, sub_id):
    row = conn.execute(
        select(S, P.c.slug, P.c.title, U.c.username)
        .join(P, P.c.id == S.c.problem_id).join(U, U.c.id == S.c.user_id)
        .where(S.c.id == sub_id)
    ).first()
    if row is None:
        abort(404)
    me = session["user"]
    if me["role"] != "teacher" and row.user_id != me["id"]:
        abort(403)
    return row


@bp.get("/submissions/<int:sub_id>")
@login_required
def submission_view(sub_id):
    svc = services()
    with svc.primary.connect() as conn:
        sub = _load_submission(conn, sub_id)
    try:
        source = svc.storage.get(svc.cfg.swift_submissions, sub.source_object).decode("utf-8", "replace")
    except Exception:
        log.exception("không đọc được %s từ Swift", sub.source_object)
        source = None
    return render_template("submission.html", sub=sub, source=source,
                           refresh=sub.status in ("PENDING", "RUNNING"))


@bp.get("/submissions")
@login_required
def submission_list():
    me = session["user"]
    q = (select(S.c.id, S.c.language, S.c.status, S.c.score, S.c.worker_host, S.c.created_at,
                P.c.slug, U.c.username)
         .join(P, P.c.id == S.c.problem_id).join(U, U.c.id == S.c.user_id)
         .order_by(S.c.id.desc()).limit(100))
    if me["role"] != "teacher":
        q = q.where(S.c.user_id == me["id"])
    with services().primary.connect() as conn:
        rows = conn.execute(q).all()
    return render_template("submissions.html", subs=rows)


@bp.get("/scoreboard")
def scoreboard():
    """Đọc từ Replica (minh chứng HM 4). Replica lỗi thì đọc tạm Primary và ghi rõ trên trang."""
    svc = services()
    q_best = (select(U.c.username, P.c.slug, func.max(S.c.score).label("best"))
              .join(U, U.c.id == S.c.user_id).join(P, P.c.id == S.c.problem_id)
              .where(U.c.role == "student").group_by(U.c.username, P.c.slug))
    source = "replica"
    try:
        with svc.replica.connect() as conn:
            best_rows = conn.execute(q_best).all()
            slugs = conn.execute(select(P.c.slug).order_by(P.c.id)).scalars().all()
    except Exception:
        log.exception("replica lỗi, đọc scoreboard từ primary")
        source = "primary (replica đang lỗi)"
        with svc.primary.connect() as conn:
            best_rows = conn.execute(q_best).all()
            slugs = conn.execute(select(P.c.slug).order_by(P.c.id)).scalars().all()
    table: dict[str, dict[str, int]] = {}
    for r in best_rows:
        table.setdefault(r.username, {})[r.slug] = int(r.best or 0)
    ranking = sorted(table.items(), key=lambda kv: (-sum(kv[1].values()), kv[0]))
    host = svc.cfg.db_replica_host if source == "replica" else svc.cfg.db_primary_host
    return render_template("scoreboard.html", ranking=ranking, slugs=slugs, source=source, db_host=host)


@bp.route("/teacher/problems/new", methods=["GET", "POST"])
@teacher_required
def teacher_new_problem():
    svc = services()
    if request.method == "POST":
        f = request.form
        upload = request.files.get("tests_zip")
        try:
            if not upload or not upload.filename:
                raise ProblemError("Hãy chọn file tests.zip")
            pid = save_problem(
                svc.primary, svc.storage, svc.cfg.swift_testcases,
                slug=f.get("slug", "").strip(), title=f.get("title", ""), statement_md=f.get("statement_md", ""),
                time_limit_ms=int(f.get("time_limit_ms") or 2000), memory_mb=int(f.get("memory_mb") or 256),
                tests_zip=upload.read(), created_by=session["user"]["id"],
            )
        except (ProblemError, ValueError) as e:
            flash(str(e), "error")
            return render_template("teacher_new.html", form=f), 400
        log.info("giảng viên %s tạo bài id=%s", session["user"]["username"], pid)
        flash("Đã tạo bài", "ok")
        return redirect(url_for("web.problem_view", slug=f.get("slug").strip()))
    return render_template("teacher_new.html", form={})


@bp.get("/healthz")
def healthz():
    svc = services()
    host, az = svc.instance
    try:
        with svc.primary.connect() as conn:
            conn.execute(text("SELECT 1"))
    except Exception as e:
        return jsonify(status="db_error", host=host, az=az, error=type(e).__name__), 503
    return jsonify(status="ok", host=host, az=az)


@bp.get("/metrics")
def prometheus_metrics():
    body, ctype = metrics.render(services().primary)
    return Response(body, content_type=ctype)
