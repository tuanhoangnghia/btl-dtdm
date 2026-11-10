#!/usr/bin/env bash
# Chạy trên controller MỖI LẦN bật cụm (cj-post-boot.service). Tự khôi phục LB Octavia nếu bị ERROR do bật cụm nguội.
# Vì sao: health manager phát hiện amphora "stale" ~60 giây sau khi lên, lúc nova-compute chưa up -> failover thất bại ("No valid host")
# -> LB ERROR, web_up và rolling update của web lỗi (không đổi được member). Cách xử lý: chờ đủ compute up, chờ health manager xong việc,
# rồi nếu còn ERROR thì chạy lb-recover.sh. Chạy lại tay được: bash post-boot.sh. Nhật ký: journalctl -u cj-post-boot
set -uo pipefail
source ~/kolla-venv/bin/activate; export OS_CLOUD=${OS_CLOUD:-cloudjudge}
HERE=$(cd "$(dirname "$0")" && pwd)
say() { echo "$(date +%T) post-boot: $*"; }
waitfor() { local max=$1 desc=$2; shift 2; local t0=$SECONDS; until "$@" >/dev/null 2>&1; do [ $((SECONDS-t0)) -gt "$max" ] && { say "HẾT GIỜ chờ: $desc"; return 1; }; sleep 10; done; say "$desc: OK ($((SECONDS-t0))s)"; }

keystone_ok() { openstack token issue -c id -f value; }
computes_up() { [ "$(openstack compute service list --service nova-compute -c State -f value | grep -c '^up')" = 2 ]; }
no_pending() { ! openstack loadbalancer list -c provisioning_status -f value | grep -q '^PENDING'; }

waitfor 900 "Keystone" keystone_ok || exit 1
waitfor 900 "2 nova-compute up" computes_up || exit 1
# health manager kiểm amphora định kỳ; cho nó 150 giây để tự thử failover trước (nếu thành công thì khỏi can thiệp)
say "chờ 150 giây cho health manager"; sleep 150
waitfor 900 "không còn LB PENDING_*" no_pending || true

for lb in $(openstack loadbalancer list -c id -c provisioning_status -f value | awk '$2=="ERROR"{print $1}'); do
  say "LB $lb ở ERROR -> lb-recover.sh"
  bash "$HERE/lb-recover.sh" "$lb" || say "lb-recover THẤT BẠI cho $lb (xem octavia-worker.log)"
done
openstack loadbalancer list -c name -c provisioning_status -c operating_status -f value | sed 's/^/post-boot: LB /'
say "xong"
