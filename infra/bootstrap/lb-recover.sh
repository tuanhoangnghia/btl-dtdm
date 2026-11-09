#!/usr/bin/env bash
# Trên controller. Khôi phục LB Octavia ở trạng thái ERROR (sau khi bật cụm nguội hoặc sau khi một amphora hỏng/bị dừng).
# Vì sao cần: cụm chỉ có 2 compute và 2 amphora nằm trong server group anti-affinity CỨNG, nên amphora thay thế không có host để đặt
# nếu VM cũ còn tồn tại (ServerGroupAntiAffinityFilter returned 0 hosts). Cách chạy được: xóa VM của MỌI amphora rồi failover cả LB.
# LB chỉ nhận lưu lượng từ amphora còn sống trong lúc chạy; mất khoảng 3 phút. Usage: bash lb-recover.sh [tên_lb]   (mặc định cj-lb)
set -euo pipefail
source ~/kolla-venv/bin/activate; export OS_CLOUD=${OS_CLOUD:-cloudjudge}
LB=${1:-cj-lb}
st=$(openstack loadbalancer show "$LB" -c provisioning_status -f value)
echo "$LB: $st"; [ "$st" = ACTIVE ] && { echo "LB đang ACTIVE, không cần làm gì."; openstack loadbalancer amphora list -c id -c role -c status -f value; exit 0; }
LBID=$(openstack loadbalancer show "$LB" -c id -f value)
for a in $(openstack loadbalancer amphora list --loadbalancer "$LBID" -c id -f value 2>/dev/null || openstack loadbalancer amphora list -c id -f value); do
  for vm in $(openstack server list --all-projects --name "amphora-$a" -c ID -f value); do echo "xóa VM amphora $a ($vm)"; openstack server delete "$vm"; done
done
sleep 12
openstack loadbalancer failover "$LB"
t0=$(date +%s)
for _ in $(seq 1 60); do
  s=$(openstack loadbalancer show "$LB" -c provisioning_status -f value); echo "$(( $(date +%s)-t0 ))s $s"
  case $s in ACTIVE) break;; ERROR) [ $(( $(date +%s)-t0 )) -gt 20 ] && { echo "FAILOVER LỖI: xem /var/log/kolla/octavia/octavia-worker.log"; exit 1; };; esac
  sleep 12
done
openstack loadbalancer amphora list -c id -c role -c status -f value
