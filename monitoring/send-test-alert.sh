#!/usr/bin/env bash
# Bắn một cảnh báo thử vào Alertmanager để kiểm đường gửi email (hạng mục 7). Thư tới sau ~10 giây (group_wait).
#   bash monitoring/send-test-alert.sh                       # local: http://127.0.0.1:9093
#   AM_URL=http://10.0.2.11:9093 bash monitoring/send-test-alert.sh    # máy monitor (từ bastion / Tailscale)
#   ACTION=worker_up bash monitoring/send-test-alert.sh      # thử luôn đường gọi alarm_url (CÓ THẬT trên cụm: thêm 1 worker)
set -euo pipefail
AM_URL=${AM_URL:-http://127.0.0.1:9093}
NAME=${NAME:-CloudJudgeTestAlert}
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
end=$(date -u -d '+5 minutes' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v+5M +%Y-%m-%dT%H:%M:%SZ)
labels="\"alertname\":\"$NAME\",\"severity\":\"warning\",\"instance\":\"send-test-alert\""
[ -n "${ACTION:-}" ] && labels="$labels,\"action\":\"$ACTION\""
curl -fsS -X POST "$AM_URL/api/v2/alerts" -H 'Content-Type: application/json' -d "[{
  \"labels\": {$labels},
  \"annotations\": {\"summary\": \"Cảnh báo thử từ send-test-alert.sh lúc $now\"},
  \"startsAt\": \"$now\", \"endsAt\": \"$end\"}]"
echo "đã gửi $NAME tới $AM_URL (tự hết hạn sau 5 phút, sẽ có thư RESOLVED)"
