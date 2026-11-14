"""Chỉ dùng ở local: đóng vai alarm_url của Heat, in ra mỗi lần Alertmanager gọi webhook (đường dẫn = tên hành động)."""
import json
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)) or 0)
        try:
            alerts = [a["labels"].get("alertname") for a in json.loads(body).get("alerts", [])]
        except ValueError:
            alerts = []
        print(f"{datetime.now(timezone.utc):%H:%M:%S} POST {self.path} alerts={alerts}")
        self.send_response(200)
        self.end_headers()

    def log_message(self, *args):
        pass


HTTPServer(("0.0.0.0", 9999), Handler).serve_forever()
