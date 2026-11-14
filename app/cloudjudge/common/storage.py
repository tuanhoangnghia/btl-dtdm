"""Swift object storage (CONTRACT mục 8.1).

STORAGE_AUTH=appcred : application credential Keystone (trên cụm; web = cj-web, worker = cj-worker).
STORAGE_AUTH=tempauth: ST_AUTH/ST_USER/ST_KEY (local dev với openstackswift/saio).

Worker chỉ có quyền đọc qua ACL; user có quyền qua ACL không được PUT container (bị 403),
nên chỉ dùng put_object/get_object/head_object, không dùng lệnh upload kiểu CLI.
"""
from __future__ import annotations

import threading

from .config import Config


class Storage:
    def __init__(self, cfg: Config):
        self.cfg = cfg
        self._conn = None
        self._lock = threading.Lock()

    def _connection(self):
        import swiftclient

        with self._lock:
            if self._conn is None:
                if self.cfg.storage_auth == "appcred":
                    from keystoneauth1 import session
                    from keystoneauth1.identity import v3

                    auth = v3.ApplicationCredential(
                        auth_url=self.cfg.os_auth_url,
                        application_credential_id=self.cfg.os_ac_id,
                        application_credential_secret=self.cfg.os_ac_secret,
                    )
                    sess = session.Session(auth=auth, timeout=30)
                    self._conn = swiftclient.Connection(
                        session=sess, retries=2, os_options={"region_name": self.cfg.os_region_name},
                    )
                elif self.cfg.storage_auth == "tempauth":
                    self._conn = swiftclient.Connection(
                        authurl=self.cfg.st_auth, user=self.cfg.st_user, key=self.cfg.st_key,
                        auth_version="1", retries=2, timeout=30,
                    )
                else:
                    raise ValueError(f"STORAGE_AUTH không hợp lệ: {self.cfg.storage_auth!r}")
            return self._conn

    def put(self, container: str, name: str, data: bytes, content_type: str = "application/octet-stream") -> str:
        return self._connection().put_object(container, name, contents=data, content_type=content_type)

    def get(self, container: str, name: str) -> bytes:
        _headers, body = self._connection().get_object(container, name)
        return body

    def etag(self, container: str, name: str) -> str:
        return self._connection().head_object(container, name).get("etag", "")

    def ensure_container(self, container: str) -> None:
        """Chỉ dùng ở local dev (tempauth). Trên cụm, A đã tạo container và ACL."""
        self._connection().put_container(container)
