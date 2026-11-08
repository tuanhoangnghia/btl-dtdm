#!/usr/bin/env bash
# Local (cần Docker): kiểm cấu hình, render alertmanager.yml từ monitoring/local.env, dựng Prometheus + Alertmanager + Grafana.
#   cp monitoring/local.env.example monitoring/local.env    # điền Gmail + App Password (chỉ ở máy bạn)
#   bash monitoring/local-up.sh
#   bash monitoring/send-test-alert.sh                      # thư thử tới ALERT_EMAIL_TO
# Muốn có số liệu thật: chạy thêm db/local-up.sh (MySQL + exporter) và app của B
#   (docker compose -f app/docker-compose.dev.yml -f monitoring/rabbitmq/dev-override.yml up -d, rồi web + worker theo app/README.md).
set -euo pipefail
cd "$(dirname "$0")"
[ -f local.env ] || { echo "Chưa có monitoring/local.env (chép từ local.env.example rồi điền)" >&2; exit 1; }
set -a; . ./local.env; set +a

bash check.sh
# local: alarm_url là webhook-echo (in ra thay vì gọi Heat)
WEB_UP_URL=http://webhook-echo:9999/web_up WEB_DOWN_URL=http://webhook-echo:9999/web_down \
WORKER_UP_URL=http://webhook-echo:9999/worker_up WORKER_DOWN_URL=http://webhook-echo:9999/worker_down \
SKIP_PROMETHEUS=1 bash render.sh .local
docker compose -f docker-compose.local.yml up -d
docker compose -f docker-compose.local.yml restart alertmanager >/dev/null   # nạp lại nếu local.env vừa đổi

echo
echo "Prometheus   http://127.0.0.1:9090/targets"
echo "Alertmanager http://127.0.0.1:9093"
echo "Grafana      http://127.0.0.1:3000  (admin / admin, đổi khi được hỏi)"
echo "Gọi alarm_url giả: docker logs -f cj-webhook-echo"
