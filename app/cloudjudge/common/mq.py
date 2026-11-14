"""RabbitMQ (CONTRACT mục 8.2): queue `submissions` durable, message {"submission_id": <int>}, persistent."""
from __future__ import annotations

import json

import pika

from .config import Config


def connection_params(cfg: Config, heartbeat: int = 60) -> pika.ConnectionParameters:
    return pika.ConnectionParameters(
        host=cfg.mq_host,
        port=cfg.mq_port,
        virtual_host="/",
        credentials=pika.PlainCredentials(cfg.mq_user, cfg.mq_password),
        heartbeat=heartbeat,
        blocked_connection_timeout=30,
        connection_attempts=2,
        retry_delay=1,
        socket_timeout=5,
    )


def declare_queue(channel, cfg: Config) -> None:
    channel.queue_declare(queue=cfg.mq_queue, durable=True)


class Publisher:
    """Mỗi lần publish mở một kết nối ngắn.

    Kết nối BlockingConnection để lâu trong tiến trình gunicorn không xử lý heartbeat, broker sẽ cắt;
    mở kết nối mới tốn ~10 ms nhưng không bao giờ gặp kết nối chết. Bật publisher confirm để biết chắc
    broker đã nhận thông điệp trước khi trả lời người dùng.
    """

    def __init__(self, cfg: Config):
        self.cfg = cfg

    def publish(self, submission_id: int) -> None:
        conn = pika.BlockingConnection(connection_params(self.cfg))
        try:
            ch = conn.channel()
            declare_queue(ch, self.cfg)
            ch.confirm_delivery()
            ch.basic_publish(
                exchange="",
                routing_key=self.cfg.mq_queue,
                body=json.dumps({"submission_id": int(submission_id)}),
                properties=pika.BasicProperties(delivery_mode=2, content_type="application/json"),
                mandatory=True,
            )
        finally:
            conn.close()
