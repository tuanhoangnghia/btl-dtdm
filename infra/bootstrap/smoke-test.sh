#!/usr/bin/env bash
# SMOKE TEST (mốc quyết định, kế hoạch 8.4 bước 1-4). Chạy trên controller với quyền admin; tự dọn sau khi xong (KEEP=1 để giữ lại).
# Kiểm: 2 VM ở 2 AZ boot nhanh, ra Internet (SNAT -> veth -> MASQUERADE), gọi được Keystone/Swift, ping chéo AZ, MTU.
set -uo pipefail
source ~/kolla-venv/bin/activate
source /etc/kolla/admin-openrc.sh
P=smoke; KEY=/tmp/${P}_key; SSHO="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=6 -o LogLevel=ERROR -i $KEY"
FAIL=0; res() { printf '%-62s %s\n' "$1" "$2"; [ "$2" = "OK" ] || FAIL=1; }

cleanup() {
  [ "${KEEP:-0}" = 1 ] && { echo "(KEEP=1: không dọn)"; return; }
  echo "== Dọn"
  for az in az1 az2; do openstack server delete --wait ${P}-$az >/dev/null 2>&1; done
  for f in $(openstack floating ip list -f value -c "Floating IP Address" 2>/dev/null); do openstack floating ip delete "$f" >/dev/null 2>&1; done
  openstack router remove subnet ${P}-rt ${P}-sub >/dev/null 2>&1
  openstack router delete ${P}-rt >/dev/null 2>&1
  openstack network delete ${P}-net >/dev/null 2>&1
  openstack keypair delete ${P}-key >/dev/null 2>&1
}
trap cleanup EXIT

echo "== Chuẩn bị mạng, router, keypair, SG"
openstack network create ${P}-net >/dev/null
openstack subnet create ${P}-sub --network ${P}-net --subnet-range 10.99.0.0/24 --dns-nameserver 8.8.8.8 >/dev/null
openstack router create ${P}-rt >/dev/null
openstack router set --external-gateway ext-net ${P}-rt
openstack router add subnet ${P}-rt ${P}-sub
[ -f $KEY ] || ssh-keygen -t ed25519 -N "" -f $KEY -q
openstack keypair create --public-key ${KEY}.pub ${P}-key >/dev/null
# admin thấy nhiều SG tên "default" (mỗi project một cái) -> phải tra theo ID của project admin, không dùng tên
ADMIN_PID=$(openstack project show admin -f value -c id)
SG=$(openstack security group list --project "$ADMIN_PID" -f value -c ID -c Name | awk '$2=="default"{print $1}')
[ -n "$SG" ] || { echo "Không tìm thấy SG default của project admin"; exit 1; }
openstack security group rule create --proto icmp "$SG" >/dev/null 2>&1 || true
openstack security group rule create --proto tcp --dst-port 22 "$SG" >/dev/null 2>&1 || true

echo "== 1) Tạo VM ở az1 và az2 (đo thời gian boot)"
for az in az1 az2; do
  t0=$(date +%s)
  openstack server create --image cirros --flavor cj.tiny --network ${P}-net --key-name ${P}-key \
    --availability-zone $az --wait ${P}-$az >/dev/null 2>&1
  dt=$(( $(date +%s) - t0 ))
  st=$(openstack server show ${P}-$az -f value -c status 2>/dev/null)
  [ "$st" = ACTIVE ] && [ $dt -lt 90 ] && res "VM $az ACTIVE trong ${dt}s (yêu cầu < 90s)" OK || res "VM $az trạng thái=$st sau ${dt}s" FAIL
done
openstack server list --long -c Name -c Status -c "Availability Zone" -c Host -f value 2>/dev/null | grep "^${P}"

echo "== Floating IP và SSH vào VM"
declare -A FIP IP
for az in az1 az2; do
  FIP[$az]=$(openstack floating ip create ext-net -f value -c floating_ip_address)
  openstack server add floating ip ${P}-$az ${FIP[$az]}
  IP[$az]=$(openstack server show ${P}-$az -f value -c addresses | grep -oE "10\.99\.0\.[0-9]+" | head -1)
done
for az in az1 az2; do
  ok=0; for i in $(seq 1 30); do ssh $SSHO cirros@${FIP[$az]} true 2>/dev/null && { ok=1; break; }; sleep 4; done
  [ $ok = 1 ] && res "SSH vào VM $az qua floating IP ${FIP[$az]}" OK || res "SSH vào VM $az (floating IP ${FIP[$az]})" FAIL
done

echo "== 2) Từ trong VM az1: Internet, Keystone, Swift, MTU"
run() { ssh $SSHO cirros@${FIP[az1]} "$@" 2>/dev/null; }
run "ping -c2 -W3 8.8.8.8" >/dev/null && res "ping 8.8.8.8 (SNAT qua router + MASQUERADE trên controller)" OK || res "ping 8.8.8.8" FAIL
run "wget -qO- -T6 http://archive.ubuntu.com >/dev/null" && res "phân giải DNS + HTTP ra Internet (archive.ubuntu.com)" OK || res "DNS/HTTP ra Internet" FAIL
run "wget -qO- -T6 http://10.10.0.10:5000/v3" | grep -q '"version"' && res "gọi Keystone http://10.10.0.10:5000/v3" OK || res "gọi Keystone" FAIL
run "wget -qO- -T6 http://10.10.0.10:8080/healthcheck" | grep -q OK && res "gọi Swift http://10.10.0.10:8080/healthcheck" OK || res "gọi Swift" FAIL
run "ip link show eth0" | grep -q "mtu 1450" && res "MTU tenant = 1450 (GCE 1500 trừ overhead overlay)" OK || res "MTU tenant" FAIL
run "ping -c2 -W3 -s 1400 ${IP[az2]}" >/dev/null && res "ping chéo AZ az1->az2 (${IP[az2]}) gói 1400B" OK || res "ping chéo AZ" FAIL

echo
[ $FAIL = 0 ] && echo "SMOKE_TEST_PASS" || echo "SMOKE_TEST_FAIL"
exit $FAIL
