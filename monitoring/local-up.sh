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
# Đọc KEY=giá trị từng dòng thay vì source: App Password có khoảng trắng, file sửa trên Windows hay có \r
while IFS= read -r line || [ -n "$line" ]; do
  line=${line%$'\r'}
  [[ $line =~ ^[[:space:]]*(#|$) ]] && continue
  [[ $line =~ ^([A-Z_][A-Z0-9_]*)=(.*)$ ]] || { echo "local.env: bỏ qua dòng không đúng dạng KEY=giá trị" >&2; continue; }
  k=${BASH_REMATCH[1]}; v=${BASH_REMATCH[2]}
  [[ $v =~ ^\"(.*)\"$ || $v =~ ^\'(.*)\'$ ]] && v=${BASH_REMATCH[1]}
  export "$k=$v"
done < local.env

bash check.sh
# local: alarm_url là webhook-echo (in ra thay vì gọi Heat)
WEB_UP_URL=http://webhook-echo:9999/web_up WEB_DOWN_URL=http://webhook-echo:9999/web_down \
WORKER_UP_URL=http://webhook-echo:9999/worker_up WORKER_DOWN_URL=http://webhook-echo:9999/worker_down \
SKIP_PROMETHEUS=1 bash render.sh .local

# Phần mềm diệt virus quét thư (vd Avast Mail Shield) ký lại TLS của smtp.gmail.com bằng CA riêng → Alertmanager báo
# "x509: certificate signed by unknown authority". Chỉ ở local: ghép CA đó vào bundle của container (không tắt kiểm TLS).
#   EXTRA_CA_FILE=<đường dẫn .pem> trong local.env để chỉ định; mặc định tự dùng CA của Avast nếu có.
COMPOSE=(-f docker-compose.local.yml)
AVAST_CA="/c/ProgramData/Avast Software/Avast/wscert.pem"
[ -z "${EXTRA_CA_FILE:-}" ] && [ -f "$AVAST_CA" ] && EXTRA_CA_FILE=$AVAST_CA
if [ -n "${EXTRA_CA_FILE:-}" ]; then
  [ -f "$EXTRA_CA_FILE" ] || { echo "Không thấy EXTRA_CA_FILE=$EXTRA_CA_FILE" >&2; exit 1; }
  { MSYS_NO_PATHCONV=1 docker run --rm --entrypoint cat prom/alertmanager:v0.27.0 /etc/ssl/certs/ca-certificates.crt
    echo; tr -d '\r' < "$EXTRA_CA_FILE"; } > .local/ca-bundle.crt
  COMPOSE+=(-f docker-compose.local-ca.yml)
  echo "Alertmanager tin thêm CA: $EXTRA_CA_FILE"
fi
docker compose "${COMPOSE[@]}" up -d
docker compose "${COMPOSE[@]}" restart alertmanager >/dev/null   # nạp lại nếu local.env vừa đổi

echo
echo "Prometheus   http://127.0.0.1:9090/targets"
echo "Alertmanager http://127.0.0.1:9093"
echo "Grafana      http://127.0.0.1:3000  (admin / admin, đổi khi được hỏi)"
echo "Gọi alarm_url giả: docker logs -f cj-webhook-echo"
