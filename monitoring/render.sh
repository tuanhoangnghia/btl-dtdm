#!/usr/bin/env bash
# Sinh cấu hình giám sát vào <thư mục ra> từ các file trong monitoring/:
#   prometheus.yml (từ prometheus.yml.tpl), alertmanager.yml (từ alertmanager.yml.tpl), rules.yml, grafana/*.
#   bash monitoring/render.sh /etc/cj-mon                 # máy monitor (cloud-init của cj-mon, chạy bằng root)
#   SKIP_PROMETHEUS=1 bash monitoring/render.sh monitoring/.local    # local: chỉ cần alertmanager.yml
# Biến: MON_AC_ID MON_AC_SECRET · SMTP_USER SMTP_APP_PASSWORD ALERT_EMAIL_TO · WEB_UP_URL WEB_DOWN_URL WORKER_UP_URL WORKER_DOWN_URL
#       GRAFANA_ADMIN_PASSWORD (không có thì sinh ngẫu nhiên, lưu ở <ra>/grafana/admin.pw)
set -euo pipefail
OUT=${1:?usage: render.sh <thư mục ra>}
SRC=$(cd "$(dirname "$0")" && pwd)
render() { local f=$1; shift; envsubst "$(printf '${%s} ' "$@")" < "$f"; }

AM_VARS=(SMTP_USER SMTP_APP_PASSWORD ALERT_EMAIL_TO WEB_UP_URL WEB_DOWN_URL WORKER_UP_URL WORKER_DOWN_URL)
PROM_VARS=(MON_AC_ID MON_AC_SECRET)
need=("${AM_VARS[@]}"); [ -n "${SKIP_PROMETHEUS:-}" ] || need+=("${PROM_VARS[@]}")
miss=(); for v in "${need[@]}"; do [ -n "${!v:-}" ] || miss+=("$v"); done
[ ${#miss[@]} -eq 0 ] || { echo "Thiếu biến: ${miss[*]}" >&2; exit 1; }
# Gmail hiển thị App Password thành 4 nhóm cách nhau bằng khoảng trắng; SMTP nhận cả chuỗi liền
export SMTP_APP_PASSWORD=${SMTP_APP_PASSWORD// /}
for v in "${AM_VARS[@]}" "${PROM_VARS[@]}"; do
  case "${!v:-}" in *"'"*) echo "$v có dấu nháy đơn, không đưa vào YAML được" >&2; exit 1 ;; esac
done

mkdir -p "$OUT/grafana"
umask 077
render "$SRC/alertmanager.yml.tpl" "${AM_VARS[@]}" > "$OUT/alertmanager.yml"
[ -n "${SKIP_PROMETHEUS:-}" ] || render "$SRC/prometheus.yml.tpl" "${PROM_VARS[@]}" > "$OUT/prometheus.yml"
umask 022
cp "$SRC/rules.yml" "$OUT/rules.yml"
cp "$SRC/grafana/datasource.yml" "$SRC/grafana/dashboards.yml" "$SRC/grafana/cloudjudge.json" "$OUT/grafana/"
if [ ! -s "$OUT/grafana/admin.pw" ]; then
  ( umask 077; printf '%s' "${GRAFANA_ADMIN_PASSWORD:-$(head -c 18 /dev/urandom | base64 | tr -d '/+=')}" > "$OUT/grafana/admin.pw" )
fi

# Container prometheus / alertmanager / grafana chạy bằng user không phải root: cho đúng user đó đọc file có secret
if [ "$(id -u)" = 0 ]; then
  chown 65534:65534 "$OUT/alertmanager.yml"                                  # alertmanager: nobody
  [ -f "$OUT/prometheus.yml" ] && chown 65534:65534 "$OUT/prometheus.yml"    # prometheus: nobody
  chown 472:0 "$OUT/grafana/admin.pw"                                        # grafana: uid 472
fi
echo "đã render cấu hình giám sát vào $OUT"
