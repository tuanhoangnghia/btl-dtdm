#!/usr/bin/env bash
# MINH CHỨNG + SỐ ĐO phần C trên cụm (HM 3, 4, 7; báo cáo C mục 8, cột "Cụm"). Chạy trên controller khi stack cj-data đủ 3 máy:
#   ssh -A cj-controller 'bash ~/cloudjudge/db/cluster-evidence.sh' | tee docs/evidence/C-cluster-evidence.txt
# -A: chuyển tiếp SSH agent để vào VM qua bastion (key của laptop nằm trong admin_ssh_pubkeys.txt).
# Bước tùy chọn (mặc định TẮT):
#   RESTORE=1  khôi phục bản backup vừa tạo vào primary (GHI ĐÈ CSDL cloudjudge: chỉ chạy khi không ai đang nộp bài)
#   ALERT=1    cắt luồng nhân bản (STOP REPLICA SQL_THREAD) để đo ReplicationBroken → firing → thư; cần stack cj-mon
# Biến khác: N (số lần đo độ trễ, mặc định 20), PRIMARY/REPLICA/MONITOR (IP theo CONTRACT).
# Ghi dữ liệu thử vào CSDL riêng cj_check (không đụng bảng của app) và 1 object vào container backups. Không in secret.
set -uo pipefail
command -v openstack >/dev/null 2>&1 || source /home/cj/kolla-venv/bin/activate
export OS_CLOUD=${OS_CLOUD:-cloudjudge}
HERE=$(cd "$(dirname "$0")" && pwd)
N=${N:-20}
PRIMARY=${PRIMARY:-10.0.3.10} REPLICA=${REPLICA:-10.0.3.11} MONITOR=${MONITOR:-10.0.2.11}
h() { printf '\n## %s\n' "$*"; }
die() { echo "LỖI: $*" >&2; exit 1; }
ms() { echo $(( ($2 - $1) / 1000000 )); }   # ms <t0 ns> <t1 ns>

echo "# Số đo trên cụm (OpenStack trên GCP, MySQL 8.4 primary az1 + replica az2) $(date -u +%FT%TZ)"

# ---- SSH qua bastion, dùng chung 1 kết nối cho mỗi máy (ControlMaster) để vòng đo không mở hàng chục phiên ----
BASTION=$(openstack stack output show cj-net bastion_fip -f value -c output_value 2>/dev/null)
[ -n "$BASTION" ] || die "không đọc được output bastion_fip của stack cj-net"
TMP=$(mktemp -d); trap 'for s in "$TMP"/cm-*; do [ -S "$s" ] && ssh -o ControlPath="$s" -O exit x 2>/dev/null; done; rm -rf "$TMP"' EXIT
# VM do Heat tạo lại thường xuyên (host key đổi), nằm trong mạng riêng: không lưu/kiểm host key (giống cj-health.sh)
BASE=(-o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
SSHO=("${BASE[@]}" -o ControlMaster=auto -o "ControlPath=$TMP/cm-%h" -o ControlPersist=120)
ssh "${SSHO[@]}" "cj@$BASTION" true 2>/dev/null || die "không SSH được bastion $BASTION (quên ssh -A?)"
# Không dùng -J: ssh tới bastion do -J mở KHÔNG nhận các -o ở trên (host key bastion chưa có trong known_hosts → bị từ chối)
JUMP=(-o "ProxyCommand=ssh ${BASE[*]} -W %h:%p cj@$BASTION")
on() { local ip=$1; shift; ssh "${SSHO[@]}" "${JUMP[@]}" "cj@$ip" "$@"; }
# Lệnh mysql root trên VM dạng 1 file thực thi, để test-replication.sh dùng làm PRIMARY_CMD/REPLICA_CMD:
# tham số được printf %q trước khi qua ssh, nên SQL có dấu cách, ngoặc, nháy vẫn nguyên vẹn
for side in P:$PRIMARY R:$REPLICA; do
  cat > "$TMP/mysql-${side%%:*}" <<EOF
#!/usr/bin/env bash
exec ssh $(printf '%q ' "${SSHO[@]}" "${JUMP[@]}") cj@${side#*:} "sudo cj-mysql \$(printf '%q ' "\$@")"
EOF
  chmod 700 "$TMP/mysql-${side%%:*}"
done
P() { "$TMP/mysql-P" "$@"; }
R() { "$TMP/mysql-R" "$@"; }
SQLQ() { "$1" -N -e "$2" 2>/dev/null; }   # SQLQ <P|R> "<sql>": 1 giá trị, không tiêu đề

h "0. Máy và phiên bản"
openstack server list --name '^cj-(mysql|rabbitmq)' -c Name -c Status -c Networks -c Flavor -f table 2>/dev/null
for s in cj-mysql-primary cj-mysql-replica; do
  printf '%s: AZ=%s\n' "$s" "$(openstack server show "$s" -f value -c OS-EXT-AZ:availability_zone 2>/dev/null)"
done
for side in P R; do
  printf '%s: ' "$([ $side = P ] && echo PRIMARY || echo REPLICA)"
  SQLQ $side "SELECT CONCAT(@@hostname, ' MySQL ', VERSION(), ' server_id=', @@server_id, ' read_only=', @@read_only,
              ' super_read_only=', @@super_read_only, ' replica_parallel_workers=', @@replica_parallel_workers)"
done
for ip in $PRIMARY $REPLICA; do
  printf '%s đồng bộ NTP: %s\n' "$ip" "$(on $ip 'timedatectl show -p NTPSynchronized --value' 2>/dev/null || echo '?')"
done

h "1. HM 3 – Block storage: volume Cinder gắn vào máy dữ liệu"
python3 - <<'PY'
import json, subprocess
def osc(*a): return json.loads(subprocess.check_output(["openstack", *a, "-f", "json"]))
names = {s["ID"]: s["Name"] for s in osc("server", "list")}
print("%-24s %-8s %5s  %s" % ("volume", "status", "GB", "gắn vào"))
for v in osc("volume", "list", "--long"):
    att = v.get("Attached to") or []
    where = ", ".join("%s:%s" % (names.get(a.get("server_id"), a.get("server_id")), a.get("device")) for a in att) or "-"
    print("%-24s %-8s %5s  %s" % (v["Name"], v["Status"], v["Size"], where))
PY

h "1b. HM 3 – Object storage: container Swift"
openstack container list -f value -c Name 2>/dev/null | while read -r c; do
  printf '%-12s %s object\n' "$c" "$(openstack container show "$c" -f value -c object_count 2>/dev/null || echo '?')"
done
echo "-- 5 object mới nhất trong submissions:"
openstack object list submissions --long -f value -c Name -c Bytes -c "Last Modified" 2>/dev/null | sort -k3 | tail -n 5

h "2. HM 4 – Ghi ở Primary, đọc ở Replica, Replica từ chối ghi (db/test-replication.sh)"
PRIMARY_CMD="$TMP/mysql-P" REPLICA_CMD="$TMP/mysql-R" bash "$HERE/test-replication.sh" || echo "!! test-replication.sh lỗi"

h "3. Độ trễ nhân bản đo trong MySQL ($N giao dịch 1 dòng vào cj_check.ping)"
echo "   = LAST_APPLIED_TRANSACTION_END_APPLY_TIMESTAMP (replica) - ORIGINAL_COMMIT_TIMESTAMP (primary)"
echo "   2 VM khác đồng hồ (đều đồng bộ NTP, xem mục 0): sai số cỡ vài ms; cột 'chờ' là thời gian WAIT_FOR_EXECUTED_GTID_SET đo trên replica"
lags=()
SQLQ P "CREATE DATABASE IF NOT EXISTS cj_check;
        CREATE TABLE IF NOT EXISTS cj_check.ping (id BIGINT AUTO_INCREMENT PRIMARY KEY, note VARCHAR(100) NOT NULL,
                                                 at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3))" >/dev/null
for i in $(seq 1 "$N"); do
  # gtid_executed có thể xuống dòng giữa các UUID: bỏ ký tự xuống dòng để truyền lại cho replica
  g=$(SQLQ P "INSERT INTO cj_check.ping (note) VALUES ('lag-$i');
              SELECT REPLACE(@@GLOBAL.gtid_executed, '\n', '')")
  [ -n "$g" ] || { echo "  lần $i: không ghi được ở primary"; continue; }
  r=$(SQLQ R "SET @t = NOW(6);
              SELECT CONCAT(WAIT_FOR_EXECUTED_GTID_SET('$g', 10), ' ', TIMESTAMPDIFF(MICROSECOND, @t, NOW(6)));
              SELECT TIMESTAMPDIFF(MICROSECOND, LAST_APPLIED_TRANSACTION_ORIGINAL_COMMIT_TIMESTAMP, LAST_APPLIED_TRANSACTION_END_APPLY_TIMESTAMP)
                FROM performance_schema.replication_applier_status_by_worker
               ORDER BY LAST_APPLIED_TRANSACTION_END_APPLY_TIMESTAMP DESC LIMIT 1" | tr '\n' ' ')
  set -- $r   # $1 = 0 nếu đã áp dụng (1 = hết 10 s), $2 = µs chờ, $3 = µs trễ
  if [ "${1:-1}" = 0 ] && [ -n "${3:-}" ]; then
    lags+=("$3"); printf '  lần %2d: trễ %s ms (chờ %s ms)\n' "$i" "$(awk "BEGIN{printf \"%.1f\", $3/1000}")" "$(awk "BEGIN{printf \"%.1f\", $2/1000}")"
  else
    echo "  lần $i: replica chưa áp dụng sau 10 s ($r)"
  fi
done
[ ${#lags[@]} -gt 0 ] && printf '%s\n' "${lags[@]}" | python3 -c '
import sys, statistics as st
v = [int(x) / 1000 for x in sys.stdin.read().split()]
print("   min %.1f ms · trung vị %.1f ms · TB %.1f ms · max %.1f ms (n=%d)" % (min(v), st.median(v), st.mean(v), max(v), len(v)))
if min(v) < 0: print("   !! có giá trị âm: đồng hồ 2 VM lệch nhau, chỉ dùng trung vị làm số tham khảo")'

h "4. Kích thước CSDL cloudjudge"
P -t -e "SELECT table_name AS bang, table_rows AS so_dong, ROUND((data_length + index_length) / 1048576, 2) AS MB
         FROM information_schema.tables WHERE table_schema = 'cloudjudge' ORDER BY table_name" 2>/dev/null

h "5. Backup thật lên Swift (db/backup-mysql.sh, đúng như cron 02:00 trên primary, credential cj-backup)"
on "$PRIMARY" 'sudo bash -s' <<'EOF'
s=$(date +%s%N)
bash /opt/cj-db/backup-mysql.sh; rc=$?
echo "thời gian backup (đo trên VM primary): $(( ($(date +%s%N) - s) / 1000000 )) ms, mã thoát $rc"
echo "metric cho Prometheus:"; cat /var/lib/prometheus/node-exporter/cj_backup.prom 2>/dev/null | grep -v '^#' || echo "  (chưa có file textfile)"
EOF
echo "-- object trong backups/mysql/ (mới nhất cuối):"
openstack object list backups --prefix mysql/ --long -f value -c Name -c Bytes -c "Last Modified" 2>/dev/null | sort | tail -n 5

if [ "${RESTORE:-0}" = 1 ]; then
  h "6. Restore bản mới nhất vào PRIMARY (db/restore-mysql.sh latest), replica tự nhận qua binlog"
  on "$PRIMARY" 'sudo bash -s' <<'EOF'
s=$(date +%s%N)
CONFIRM=YES bash /opt/cj-db/restore-mysql.sh latest; rc=$?
echo "thời gian restore (gồm tải từ Swift, đo trên VM primary): $(( ($(date +%s%N) - s) / 1000000 )) ms, mã thoát $rc"
EOF
  g=$(SQLQ P "SELECT REPLACE(@@GLOBAL.gtid_executed, '\n', '')")
  r=$(SQLQ R "SET @t = NOW(6);
              SELECT CONCAT(WAIT_FOR_EXECUTED_GTID_SET('$g', 120), ' ', TIMESTAMPDIFF(MICROSECOND, @t, NOW(6)));
              SELECT TIMESTAMPDIFF(MICROSECOND, LAST_APPLIED_TRANSACTION_ORIGINAL_COMMIT_TIMESTAMP, LAST_APPLIED_TRANSACTION_END_APPLY_TIMESTAMP)
                FROM performance_schema.replication_applier_status_by_worker
               ORDER BY LAST_APPLIED_TRANSACTION_END_APPLY_TIMESTAMP DESC LIMIT 1" | tr '\n' ' ')
  set -- $r
  echo "replica khớp lại: $([ "${1:-1}" = 0 ] && echo có || echo 'CHƯA sau 120 s'); giao dịch cuối trễ $(awk "BEGIN{printf \"%.1f\", ${3:-0}/1000}") ms; chờ thêm $(awk "BEGIN{printf \"%.1f\", ${2:-0}/1000}") ms"
  for side in P R; do
    printf '%s: ' "$([ $side = P ] && echo PRIMARY || echo REPLICA)"
    SQLQ $side "SELECT CONCAT('users=', (SELECT COUNT(*) FROM cloudjudge.users), ' problems=', (SELECT COUNT(*) FROM cloudjudge.problems),
                ' submissions=', (SELECT COUNT(*) FROM cloudjudge.submissions))"
  done
else
  h "6. Restore: bỏ qua (chạy lại với RESTORE=1 khi không ai đang nộp bài)"
fi

# Hỏi Prometheus/Alertmanager trên máy monitor qua bastion (sg-monitor mở 9090/9093 cho sg-bastion)
promq() { ssh "${SSHO[@]}" "cj@$BASTION" "curl -s -m 5 --data-urlencode 'query=$1' http://$MONITOR:9090/api/v1/query" 2>/dev/null \
            | python3 -c 'import sys,json; r=json.load(sys.stdin)["data"]["result"]; print(r[0]["value"][1] if r else "")' 2>/dev/null; }
mails() { ssh "${SSHO[@]}" "cj@$BASTION" "curl -s -m 5 http://$MONITOR:9093/metrics" 2>/dev/null \
            | awk '/^alertmanager_notifications_total\{.*integration="email"/{print $2}'; }

if [ "${ALERT:-0}" = 1 ]; then
  h "7. HM 7 – Cắt luồng nhân bản → ReplicationBroken firing → thư (cần cj-mon)"
  [ -n "$(promq 'up')" ] || die "không hỏi được Prometheus ở $MONITOR:9090 (stack cj-mon chưa chạy?)"
  trap 'R -e "START REPLICA SQL_THREAD" 2>/dev/null; for s in "$TMP"/cm-*; do [ -S "$s" ] && ssh -o ControlPath="$s" -O exit x 2>/dev/null; done; rm -rf "$TMP"' EXIT
  m0=$(mails); echo "thư đã gửi trước khi thử: ${m0:-?}"
  R -e "STOP REPLICA SQL_THREAD" 2>/dev/null; t0=$(date +%s%N); echo "$(date -u +%T) STOP REPLICA SQL_THREAD"
  tp=""; tf=""
  for i in $(seq 1 90); do
    n=$(promq 'count(ALERTS{alertname="ReplicationBroken"}) or vector(0)')
    f=$(promq 'count(ALERTS{alertname="ReplicationBroken",alertstate="firing"}) or vector(0)')
    if [ -z "$tp" ] && [ "${n:-0}" != 0 ]; then tp=$(date +%s%N); echo "$(date -u +%T) pending sau $(ms $t0 $tp) ms"; fi
    if [ "${f:-0}" != 0 ]; then tf=$(date +%s%N); echo "$(date -u +%T) firing sau $(ms $t0 $tf) ms (luật có for: 1m)"; break; fi
    sleep 2
  done
  [ -n "$tf" ] || echo "!! chưa firing sau 180 s"
  if [ -n "$tf" ]; then
    for i in $(seq 1 30); do m1=$(mails); [ "${m1:-0}" != "${m0:-0}" ] && break; sleep 1; done
    echo "thư đã gửi sau khi firing: ${m1:-?} (tăng = Alertmanager đã gửi tới Gmail; xem hộp thư để chụp ảnh)"
  fi
  R -e "START REPLICA SQL_THREAD" 2>/dev/null; t2=$(date +%s%N); echo "$(date -u +%T) START REPLICA SQL_THREAD"
  for i in $(seq 1 60); do
    [ "$(promq 'count(ALERTS{alertname="ReplicationBroken"}) or vector(0)')" = 0 ] && { echo "$(date -u +%T) hết cảnh báo sau $(ms $t2 $(date +%s%N)) ms"; break; }
    sleep 2
  done
else
  h "7. Cảnh báo ReplicationBroken: bỏ qua (chạy lại với ALERT=1 khi đã có cj-mon)"
fi

h "8. Trạng thái cuối"
R -e "SHOW REPLICA STATUS\G" 2>/dev/null | grep -E ' (Source_Host|Replica_IO_Running|Replica_SQL_Running|Seconds_Behind_Source|Last_IO_Error|Last_SQL_Error|Auto_Position):'
b=$(promq 'max(cj_backup_last_success_timestamp_seconds)')
[ -n "$b" ] && echo "Prometheus thấy backup gần nhất: $(date -u -d "@${b%.*}" +%FT%TZ)" || echo "(Prometheus chưa thấy cj_backup_last_success_timestamp_seconds hoặc chưa có cj-mon)"
echo "XONG"
