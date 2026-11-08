#!/usr/bin/env bash
# Kiểm tra sức khỏe cụm trước demo / quay video (KE_HOACH 14.2). Chạy trên controller, sau gcp-up.sh ~5 phút:
#   ssh -A cj-controller 'bash ~/cloudjudge/scripts/cj-health.sh'
# -A (chuyển tiếp SSH agent) để script vào được VM qua bastion, kiểm replication và Prometheus. Không có thì các mục đó SKIP.
# In OK / WARN / FAIL từng mục; mã thoát = số mục FAIL. Chỉ đọc, không sửa gì.
set -uo pipefail
command -v openstack >/dev/null 2>&1 || source /home/cj/kolla-venv/bin/activate
export OS_CLOUD=${OS_CLOUD:-cloudjudge}
EXPECT_WEB=${EXPECT_WEB:-2} EXPECT_WORKER=${EXPECT_WORKER:-1}
FAILS=0
ok()   { printf '  \e[32mOK\e[0m    %s\n' "$*"; }
warn() { printf '  \e[33mWARN\e[0m  %s\n' "$*"; }
fail() { printf '  \e[31mFAIL\e[0m  %s\n' "$*"; FAILS=$((FAILS + 1)); }
skip() { printf '  SKIP  %s\n' "$*"; }
out()  { openstack stack output show "$1" "$2" -f value -c output_value 2>/dev/null; }

echo "== Host controller"
if sudo -n true 2>/dev/null; then
  bad=$(sudo docker ps -a --format '{{.Names}} {{.Status}}' | grep -Ev ' Up ' || true)
  unhealthy=$(sudo docker ps --filter health=unhealthy --format '{{.Names}}')
  [ -z "$bad$unhealthy" ] && ok "container Kolla đều Up, không có unhealthy" || fail "container lỗi: $(echo $bad $unhealthy)"
else
  skip "không có sudo, bỏ qua kiểm container Kolla"
fi
ip -br -4 addr show o-hm0 2>/dev/null | grep -q '10\.1\.' && ok "o-hm0 có IP (Octavia nói chuyện được với amphora)" \
  || fail "o-hm0 chưa có IP 10.1.0.x: sudo systemctl restart octavia-interface (xem nhật ký A 29/10)"

echo "== Dịch vụ OpenStack"
down=$(openstack compute service list -f value -c Binary -c Host -c State 2>/dev/null | awk '$3 != "up"')
[ -z "$down" ] && ok "nova service đều up" || fail "nova service down: $down"
down=$(openstack network agent list -f value -c "Agent Type" -c Host -c Alive 2>/dev/null | grep -v 'True' || true)
[ -z "$down" ] && ok "neutron agent đều alive" || fail "neutron agent chết: $down"

echo "== Stack Heat"
for s in cj-net cj-data cj-app cj-mon; do
  st=$(openstack stack show "$s" -f value -c stack_status 2>/dev/null || echo "KHÔNG CÓ")
  case "$st" in *_COMPLETE) ok "$s $st" ;; *) fail "$s $st" ;; esac
done

echo "== Máy ảo"
servers=$(openstack server list -f value -c Name -c Status 2>/dev/null)
notactive=$(awk '$2 != "ACTIVE"' <<<"$servers")
[ -z "$notactive" ] && ok "$(wc -l <<<"$servers") máy đều ACTIVE" || fail "máy chưa ACTIVE: $(echo $notactive)"
nweb=$(grep -c '^cj-web-' <<<"$servers"); nworker=$(grep -c '^cj-worker-' <<<"$servers")
[ "$nweb" = "$EXPECT_WEB" ] && ok "web = $nweb" || warn "web = $nweb (mong đợi $EXPECT_WEB; vừa tắt web để demo failover thì openstack server start)"
[ "$nworker" = "$EXPECT_WORKER" ] && ok "worker = $nworker" || warn "worker = $nworker (mong đợi $EXPECT_WORKER, chờ QueueIdle thu về)"
for s in cj-mysql-primary cj-mysql-replica cj-rabbitmq cj-monitor cj-bastion; do
  grep -q "^$s ACTIVE" <<<"$servers" || fail "$s không ACTIVE"
done
azs=$(openstack server list --long -f value -c Name -c "Availability Zone" 2>/dev/null | awk '/^cj-web-/{print $2}' | sort -u | tr '\n' ' ')
case "$azs" in *az1*az2*) ok "web ở cả 2 AZ: $azs" ;; *) warn "web chỉ ở: $azs" ;; esac

echo "== Lưu trữ"
vols=$(openstack volume list -f value -c Name -c Status 2>/dev/null | grep '^cj-')
notinuse=$(awk '$2 != "in-use"' <<<"$vols")
[ -n "$vols" ] && [ -z "$notinuse" ] && ok "volume Cinder đều in-use: $(awk '{print $1}' <<<"$vols" | tr '\n' ' ')" || fail "volume: $(echo $vols)"
for c in submissions testcases releases backups; do
  openstack container show "$c" >/dev/null 2>&1 && ok "Swift container $c" || fail "thiếu Swift container $c"
done

echo "== Cân bằng tải"
lb=$(openstack loadbalancer list -f value -c name -c provisioning_status -c operating_status 2>/dev/null | grep '^cj-lb ')
grep -q 'ACTIVE ONLINE' <<<"$lb" && ok "LB $lb" || fail "LB: ${lb:-không có cj-lb}"
roles=$(openstack loadbalancer amphora list -f value -c role -c status 2>/dev/null | sort | tr '\n' ' ')
case "$roles" in *BACKUP*MASTER*) ok "amphora: $roles" ;; *) warn "amphora: $roles" ;; esac
LB_FIP=$(out cj-app lb_fip)
if [ -n "$LB_FIP" ]; then
  h=$(curl -s -m 5 "http://$LB_FIP/healthz")
  grep -q '"ok"' <<<"$h" && ok "http://$LB_FIP/healthz → $h" || fail "http://$LB_FIP/healthz → ${h:-không trả lời}"
fi

echo "== Bên trong VM (qua bastion)"
BASTION=$(out cj-net bastion_fip)
# VM do Heat tạo lại thường xuyên (host key đổi), nằm trong mạng riêng: không lưu/kiểm host key
SSHB=(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
if [ -n "$BASTION" ] && "${SSHB[@]}" "cj@$BASTION" true 2>/dev/null; then
  rs=$("${SSHB[@]}" -J "cj@$BASTION" cj@10.0.3.11 'sudo cj-mysql -e "SHOW REPLICA STATUS\G"' 2>/dev/null)
  io=$(awk -F': ' '/ Replica_IO_Running:/{print $2}' <<<"$rs"); sq=$(awk -F': ' '/ Replica_SQL_Running:/{print $2}' <<<"$rs")
  lag=$(awk -F': ' '/ Seconds_Behind_Source:/{print $2}' <<<"$rs")
  [ "$io$sq" = "YesYes" ] && ok "replication chạy, trễ ${lag}s" || fail "replication: IO=$io SQL=$sq"
  q() { "${SSHB[@]}" "cj@$BASTION" "curl -s -m 5 --data-urlencode 'query=$1' http://10.0.2.11:9090/api/v1/query" 2>/dev/null \
          | python3 -c 'import sys,json; r=json.load(sys.stdin)["data"]["result"]; print(r[0]["value"][1] if r else "")' 2>/dev/null; }
  qlen=$(q 'sum(rabbitmq_queue_messages{queue="submissions"})')
  [ "${qlen%.*}" = 0 ] && ok "hàng đợi submissions rỗng" || warn "hàng đợi submissions: ${qlen:-không đọc được}"
  ndown=$(q 'count(up == 0) or vector(0)')
  [ "${ndown%.*}" = 0 ] && ok "Prometheus: mọi mục tiêu up" || fail "Prometheus: ${ndown:-?} mục tiêu down (xem http://10.0.2.11:9090/targets)"
  firing=$(q 'count(ALERTS{alertstate="firing"}) or vector(0)')
  [ "${firing%.*}" = 0 ] && ok "không có cảnh báo đang bật" || warn "${firing:-?} cảnh báo đang bật (xem Alertmanager :9093)"
else
  skip "không SSH được bastion ${BASTION:-?} (chạy bằng ssh -A từ laptop đã có key trong admin_ssh_pubkeys.txt)"
fi

echo
[ "$FAILS" = 0 ] && echo "TẤT CẢ OK" || echo "$FAILS mục FAIL"
exit "$FAILS"
