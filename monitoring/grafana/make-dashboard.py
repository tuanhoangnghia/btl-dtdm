"""Sinh monitoring/grafana/cloudjudge.json (dashboard CloudJudge, KE_HOACH 12.4).

Sửa dashboard: sửa file này (bản gốc dễ đọc) rồi chạy `python monitoring/grafana/make-dashboard.py`, commit cả 2 file.
Sửa trên giao diện Grafana thì Export JSON rồi chép phần thay đổi về đây, không sửa tay cloudjudge.json.
Hàng 1 dùng khi demo co giãn (hàng đợi, số worker/web, bài/phút); hàng 2 là sức khỏe chấm bài; hàng 3 là hạ tầng và dữ liệu.
"""
import json
from pathlib import Path

DS = {"type": "prometheus", "uid": "prometheus"}
panels = []


def panel(kind, title, targets, x, y, w, h, unit=None, desc=None, **extra):
    p = {
        "id": len(panels) + 1,
        "type": kind,
        "title": title,
        "datasource": DS,
        "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "targets": [
            {"refId": chr(65 + i), "datasource": DS, "expr": expr, "legendFormat": legend}
            for i, (expr, legend) in enumerate(targets)
        ],
        "fieldConfig": {"defaults": {}, "overrides": []},
        "options": {},
    }
    if unit:
        p["fieldConfig"]["defaults"]["unit"] = unit
    if desc:
        p["description"] = desc
    if kind == "timeseries":
        p["fieldConfig"]["defaults"]["custom"] = {"lineWidth": 2, "fillOpacity": 10, "showPoints": "never"}
        p["options"] = {"legend": {"displayMode": "list", "placement": "bottom"}, "tooltip": {"mode": "multi"}}
    if kind == "stat":
        p["options"] = {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "background", "graphMode": "area"}
    for k, v in extra.items():
        if k == "thresholds":
            p["fieldConfig"]["defaults"]["thresholds"] = {
                "mode": "absolute",
                "steps": [{"color": c, "value": val} for val, c in v],
            }
        elif k == "mappings":
            p["fieldConfig"]["defaults"]["mappings"] = v
        else:
            p[k] = v
    panels.append(p)


def row(title, y):
    panels.append({"id": len(panels) + 1, "type": "row", "title": title, "collapsed": False,
                   "gridPos": {"x": 0, "y": y, "w": 24, "h": 1}, "panels": []})


GREEN_AT_ZERO = [(None, "green")]

# ---- Hàng 1: co giãn ----
row("Co giãn theo tải", 0)
panel("stat", "Bài đang chờ (queue)", [('sum(rabbitmq_queue_messages_ready{queue="submissions"})', "")], 0, 1, 4, 4,
      thresholds=[(None, "green"), (5, "orange"), (10, "red")],
      desc="rabbitmq_queue_messages_ready{queue=submissions}. Trên 10 bài trong 30 giây → QueueHigh → thêm worker.")
panel("stat", "Số worker", [('count(up{job="worker"} == 1) or vector(0)', "")], 4, 1, 4, 4,
      thresholds=[(None, "blue")])
panel("stat", "Số web", [('count(up{job="web"} == 1) or vector(0)', "")], 8, 1, 4, 4, thresholds=[(None, "blue")])
panel("stat", "Bài chờ lâu nhất", [("max(cj_oldest_pending_seconds)", "")], 12, 1, 4, 4, unit="s",
      thresholds=[(None, "green"), (60, "orange"), (120, "red")])
panel("stat", "Bài nhận / phút", [("sum(rate(cj_submissions_total[1m])) * 60", "")], 16, 1, 4, 4, unit="short",
      thresholds=[(None, "purple")])
panel("stat", "Bài chấm xong / phút", [("sum(rate(cj_graded_total[1m])) * 60", "")], 20, 1, 4, 4, unit="short",
      thresholds=[(None, "purple")])
panel("timeseries", "Hàng đợi và số worker", [
    ('sum(rabbitmq_queue_messages_ready{queue="submissions"})', "đang chờ (ready)"),
    ('sum(rabbitmq_queue_messages_unacked{queue="submissions"})', "đang chấm (unacked)"),
    ('count(up{job="worker"} == 1)', "số worker"),
], 0, 5, 12, 8)
panel("timeseries", "Bài nhận và chấm theo phút", [
    ("sum by (language) (rate(cj_submissions_total[1m])) * 60", "nhận {{language}}"),
    ("sum by (status) (rate(cj_graded_total[1m])) * 60", "chấm {{status}}"),
], 12, 5, 12, 8, unit="short")

# ---- Hàng 2: chấm bài ----
row("Chấm bài", 13)
panel("timeseries", "Thời gian chấm 1 bài (p50 / p95)", [
    ("histogram_quantile(0.5, sum by (le) (rate(cj_grade_duration_seconds_bucket[2m])))", "p50"),
    ("histogram_quantile(0.95, sum by (le) (rate(cj_grade_duration_seconds_bucket[2m])))", "p95"),
], 0, 14, 8, 8, unit="s")
panel("timeseries", "Bài PENDING + RUNNING, tuổi bài chờ lâu nhất", [
    ("max(cj_pending_submissions)", "PENDING + RUNNING"),
    ("max(cj_oldest_pending_seconds)", "chờ lâu nhất (s)"),
], 8, 14, 8, 8)
panel("table", "Cảnh báo đang bật", [('ALERTS{alertstate="firing"}', "")], 16, 14, 8, 8,
      transformations=[{"id": "labelsToFields", "options": {}},
                       {"id": "organize", "options": {"excludeByName": {"Time": True, "Value": True, "__name__": True,
                                                                        "alertstate": True, "cluster": True}}}])
panels[-1]["targets"][0].update({"instant": True, "format": "table"})

# ---- Hàng 3: hạ tầng và dữ liệu ----
row("Hạ tầng và dữ liệu", 22)
panel("timeseries", "CPU theo máy", [
    ('1 - avg by (instance, role) (rate(node_cpu_seconds_total{job="node",mode="idle"}[1m]))', "{{role}} {{instance}}"),
], 0, 23, 12, 8, unit="percentunit")
panel("timeseries", "RAM dùng theo máy", [
    ('1 - node_memory_MemAvailable_bytes{job="node"} / node_memory_MemTotal_bytes{job="node"}', "{{role}} {{instance}}"),
], 12, 23, 12, 8, unit="percentunit")
panel("stat", "Mục tiêu đang chạy", [("up", "{{job}} {{instance}}")], 0, 31, 12, 6,
      mappings=[{"type": "value", "options": {"0": {"text": "DOWN", "color": "red"}, "1": {"text": "UP", "color": "green"}}}],
      thresholds=[(None, "red"), (1, "green")])
panels[-1]["options"].update({"graphMode": "none", "textMode": "value_and_name"})
panel("stat", "Replication MySQL", [
    ('max(mysql_slave_status_replica_io_running or mysql_slave_status_slave_io_running)', "IO thread"),
    ('max(mysql_slave_status_replica_sql_running or mysql_slave_status_slave_sql_running)', "SQL thread"),
    ('max(mysql_slave_status_seconds_behind_source or mysql_slave_status_seconds_behind_master)', "trễ (s)"),
], 12, 31, 6, 6, thresholds=[(None, "green")])
panels[-1]["options"].update({"graphMode": "none", "textMode": "value_and_name"})
panel("stat", "Backup MySQL gần nhất", [("time() - max(cj_backup_last_success_timestamp_seconds)", "")], 18, 31, 6, 6,
      unit="s", thresholds=[(None, "green"), (26 * 3600, "red")],
      desc="backup-mysql.sh (cron 02:00 trên mysql-primary) ghi metric qua textfile collector của node_exporter.")
panel("timeseries", "MySQL: truy vấn / giây và kết nối", [
    ("sum by (role) (rate(mysql_global_status_queries[1m]))", "queries/s {{role}}"),
    ("sum by (role) (mysql_global_status_threads_connected)", "kết nối {{role}}"),
], 0, 37, 24, 7)

dashboard = {
    "uid": "cloudjudge",
    "title": "CloudJudge",
    "tags": ["cloudjudge"],
    "timezone": "browser",
    "refresh": "5s",
    "time": {"from": "now-30m", "to": "now"},
    "schemaVersion": 39,
    "version": 1,
    "editable": True,
    "panels": panels,
}

out = Path(__file__).with_name("cloudjudge.json")
# JSON gọn (không thụt lề): file được nhúng vào user_data của cj-mon, Nova giới hạn 64 KB sau base64
out.write_text(json.dumps(dashboard, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8", newline="\n")
print(f"wrote {out} ({len(panels)} panels)")   # ASCII: console Windows (cp1252) không in được tiếng Việt
