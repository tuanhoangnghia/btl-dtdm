#!/usr/bin/env bash
# SMOKE TEST Octavia (kế hoạch 8.4 bước 5): LB ACTIVE_STANDBY, 2 amphora MASTER/BACKUP nằm ở 2 compute khác nhau.
# Chạy trên controller với quyền admin (nên chạy trong tmux). Tự dọn xong (KEEP=1 để giữ lại).
set -uo pipefail
source ~/kolla-venv/bin/activate
source /etc/kolla/admin-openrc.sh
P=lbt; FAIL=0; res() { printf '%-64s %s\n' "$1" "$2"; [ "$2" = OK ] || FAIL=1; }
cleanup() {
  [ "${KEEP:-0}" = 1 ] && { echo "(KEEP=1: không dọn)"; return; }
  echo "== Dọn"
  openstack loadbalancer delete --cascade --wait ${P}-lb >/dev/null 2>&1
  openstack router remove subnet ${P}-rt ${P}-sub >/dev/null 2>&1; openstack router delete ${P}-rt >/dev/null 2>&1
  openstack network delete ${P}-net >/dev/null 2>&1
}
trap cleanup EXIT

echo "== Chuẩn bị mạng"
openstack network create ${P}-net >/dev/null
openstack subnet create ${P}-sub --network ${P}-net --subnet-range 10.98.0.0/24 >/dev/null
openstack router create ${P}-rt >/dev/null; openstack router set --external-gateway ext-net ${P}-rt; openstack router add subnet ${P}-rt ${P}-sub

echo "== Tạo LB (provider amphora, topology ACTIVE_STANDBY theo octavia.conf)"
t0=$(date +%s)
openstack loadbalancer create --name ${P}-lb --vip-subnet-id ${P}-sub --wait -f value -c provisioning_status 2>&1 | tail -1
dt=$(( $(date +%s) - t0 ))
st=$(openstack loadbalancer show ${P}-lb -f value -c provisioning_status)
[ "$st" = ACTIVE ] && res "LB provisioning_status=ACTIVE sau ${dt}s" OK || res "LB provisioning_status=$st sau ${dt}s" FAIL
openstack loadbalancer listener create --name ${P}-ls --protocol HTTP --protocol-port 80 --wait ${P}-lb >/dev/null 2>&1
openstack loadbalancer pool create --name ${P}-pool --lb-algorithm ROUND_ROBIN --listener ${P}-ls --protocol HTTP --wait >/dev/null 2>&1
echo "-- topology: $(openstack loadbalancer show ${P}-lb -f value -c flavor_id) | vip: $(openstack loadbalancer show ${P}-lb -f value -c vip_address)"
echo "-- amphora:"
openstack loadbalancer amphora list --loadbalancer ${P}-lb -c id -c role -c status -c lb_network_ip -f value
ROLES=$(openstack loadbalancer amphora list --loadbalancer ${P}-lb -f value -c role | sort | tr '\n' ' ')
[ "$ROLES" = "BACKUP MASTER " ] && res "2 amphora: MASTER + BACKUP (ACTIVE_STANDBY)" OK || res "vai trò amphora = [$ROLES]" FAIL
echo "-- amphora nằm ở host nào (server list project service):"
HOSTS=$(openstack server list --all-projects --name amphora -f value -c Name -c Host 2>/dev/null | sed 's/\.asia-southeast1.*internal//')
echo "$HOSTS"
N=$(echo "$HOSTS" | awk '{print $NF}' | sort -u | wc -l)
[ "$N" -ge 2 ] && res "2 amphora nằm ở 2 host khác nhau (anti-affinity)" OK || res "amphora cùng 1 host ($N host)" FAIL
echo
[ $FAIL = 0 ] && echo "SMOKE_LB_PASS" || echo "SMOKE_LB_FAIL"
exit $FAIL
