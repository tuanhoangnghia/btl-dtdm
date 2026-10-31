"""Web/API CloudJudge (Flask + Gunicorn), không lưu trạng thái trên máy.

Phiên đăng nhập là cookie ký bằng SECRET_KEY (giống nhau trên mọi máy web), mã nguồn nằm trên Swift,
dữ liệu nằm trên MySQL, việc chấm đẩy qua RabbitMQ. Vì vậy LB gửi request tới máy web nào cũng được.

Chạy: gunicorn -c deploy/gunicorn.conf.py "cloudjudge.web:create_app()"
"""
from __future__ import annotations

import secrets
from dataclasses import dataclass, field

from flask import Flask, abort, request, session

from ..common.config import Config
from ..common.instance import instance_info


@dataclass
class Services:
    cfg: Config
    primary: object
    replica: object
    storage: object
    publisher: object
    instance: tuple[str, str] = field(default_factory=lambda: ("", ""))


def services() -> Services:
    from flask import current_app
    return current_app.extensions["cj"]


def create_app(cfg: Config | None = None, *, engines=None, storage=None, publisher=None,
               instance: tuple[str, str] | None = None) -> Flask:
    cfg = cfg or Config.from_env()
    if engines is None:
        from ..common.db import make_engines
        engines = make_engines(cfg)
    if storage is None:
        from ..common.storage import Storage
        storage = Storage(cfg)
    if publisher is None:
        from ..common.mq import Publisher
        publisher = Publisher(cfg)

    app = Flask(__name__)
    if not cfg.secret_key:
        raise RuntimeError("Thiếu SECRET_KEY (phải giống nhau trên mọi máy web)")
    app.config.update(
        SECRET_KEY=cfg.secret_key,
        SESSION_COOKIE_HTTPONLY=True,
        SESSION_COOKIE_SAMESITE="Lax",
        MAX_CONTENT_LENGTH=16 * 1024 * 1024,
    )
    app.extensions["cj"] = Services(cfg, engines[0], engines[1], storage, publisher,
                                    instance or instance_info())

    @app.before_request
    def _csrf():
        if request.method == "POST" and not request.path.startswith("/api/"):
            token = session.get("csrf")
            if not token or request.form.get("csrf_token") != token:
                abort(400, "CSRF token không hợp lệ, hãy tải lại trang")

    @app.context_processor
    def _ctx():
        if "csrf" not in session:
            session["csrf"] = secrets.token_hex(16)
        svc = services()
        return {
            "csrf_token": session["csrf"],
            "me": session.get("user"),
            "host": svc.instance[0],
            "az": svc.instance[1],
            "release": svc.cfg.release,
        }

    from . import api, routes
    app.register_blueprint(routes.bp)
    app.register_blueprint(api.bp)
    return app
