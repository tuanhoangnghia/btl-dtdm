#!/usr/bin/env bash
# Kiểm tra cấu hình giám sát trước khi deploy (không cần cụm):
#   promtool check config (bản cụm + bản local), promtool check rules, promtool test rules, amtool check-config.
#   bash monitoring/check.sh
# Dùng promtool/amtool trên PATH nếu có, không thì chạy bằng image Docker (CONTRACT 6).
set -euo pipefail
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")"
TMP=$(mktemp -d ./.check.XXXXXX); trap 'rm -rf "$TMP"' EXIT

# render bằng giá trị giả để kiểm cú pháp
MON_AC_ID=dummy MON_AC_SECRET=dummy SMTP_USER=test@example.com SMTP_APP_PASSWORD='abcd efgh' ALERT_EMAIL_TO=test@example.com \
WEB_UP_URL=http://127.0.0.1:9999/web_up WEB_DOWN_URL=http://127.0.0.1:9999/web_down \
WORKER_UP_URL=http://127.0.0.1:9999/worker_up WORKER_DOWN_URL=http://127.0.0.1:9999/worker_down \
GRAFANA_ADMIN_PASSWORD=dummy bash render.sh "$TMP/out" >/dev/null
# bản local trỏ rules.yml theo đường dẫn trong container; chép ra cạnh file để promtool tìm thấy
sed 's#/etc/prometheus/rules.yml#rules.yml#' "$TMP/out/prometheus.yml" > "$TMP/out/prometheus.check.yml"
sed 's#/etc/prometheus/rules.yml#rules.yml#' prometheus.local.yml > "$TMP/out/prometheus.local.check.yml"
mkdir -p "$TMP/tests"; cp tests/rules.test.yml "$TMP/tests/"; cp rules.yml "$TMP/"

HERE=$(pwd -W 2>/dev/null || pwd)   # Git Bash: D:/..., Docker Desktop cần dạng này khi mount
tool() {  # tool <promtool|amtool> <tham số...>; chạy trong thư mục $TMP
  local t=$1; shift
  if command -v "$t" >/dev/null 2>&1; then (cd "$TMP" && "$t" "$@")
  else
    local img=prom/prometheus:v2.55.1; [ "$t" = amtool ] && img=prom/alertmanager:v0.27.0
    docker run --rm -v "$HERE/${TMP#./}:/w" -w /w --entrypoint "$t" "$img" "$@"
  fi
}

echo "== promtool check config (cụm)";  tool promtool check config out/prometheus.check.yml
echo "== promtool check config (local)"; tool promtool check config out/prometheus.local.check.yml
echo "== promtool check rules";          tool promtool check rules rules.yml
echo "== promtool test rules";           tool promtool test rules tests/rules.test.yml
echo "== amtool check-config";           tool amtool check-config out/alertmanager.yml
echo "== dashboard JSON";                python -c "import json,sys; d=json.load(open('grafana/cloudjudge.json',encoding='utf-8')); print('OK', len(d['panels']), 'panel')"
echo "TẤT CẢ OK"
