#!/usr/bin/env bash
# Minh chứng hạng mục 4: ghi ở Primary → đọc thấy ở Replica; Replica từ chối ghi; trạng thái replication.
# Ghi vào CSDL riêng cj_check (không đụng bảng của app).
#   bash db/test-replication.sh                      # local (container cj-mysql-primary / cj-mysql-replica)
#   PRIMARY_CMD="ssh <primary> sudo cj-mysql" REPLICA_CMD="ssh <replica> sudo cj-mysql" bash db/test-replication.sh   # trên cụm
# PRIMARY_CMD / REPLICA_CMD: lệnh chạy client mysql với quyền root, nhận thêm tham số mysql và SQL từ -e.
set -euo pipefail
export MSYS_NO_PATHCONV=1
PW=${MYSQL_ROOT_PASSWORD:-dev-root}
PRIMARY_CMD=${PRIMARY_CMD:-docker exec -i -e MYSQL_PWD=$PW cj-mysql-primary mysql -uroot}
REPLICA_CMD=${REPLICA_CMD:-docker exec -i -e MYSQL_PWD=$PW cj-mysql-replica mysql -uroot}
P() { $PRIMARY_CMD "$@"; }
R() { $REPLICA_CMD "$@"; }

MARK="check-$(date -u +%Y%m%dT%H%M%SZ)-$RANDOM"
echo "== 1. Ghi ở PRIMARY: $MARK"
P -e "CREATE DATABASE IF NOT EXISTS cj_check;
      CREATE TABLE IF NOT EXISTS cj_check.ping (id BIGINT AUTO_INCREMENT PRIMARY KEY, note VARCHAR(100) NOT NULL,
                                               at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3));
      INSERT INTO cj_check.ping (note) VALUES ('$MARK');"
P -t -e "SELECT @@hostname AS host, @@server_id AS server_id, @@read_only AS read_only, id, note, at
         FROM cj_check.ping WHERE note = '$MARK'"

echo "== 2. Đọc ở REPLICA"
t0=$(date +%s)
for i in $(seq 1 20); do
  n=$(R -N -e "SELECT COUNT(*) FROM cj_check.ping WHERE note = '$MARK'" 2>/dev/null || echo 0)
  [ "$n" = 1 ] && break
  sleep 0.5
done
[ "$n" = 1 ] || { echo "LỖI: replica chưa thấy bản ghi sau 10 giây" >&2; exit 1; }
R -t -e "SELECT @@hostname AS host, @@server_id AS server_id, @@super_read_only AS super_read_only, id, note, at
         FROM cj_check.ping WHERE note = '$MARK'"
echo "replica thấy bản ghi sau ~$(( $(date +%s) - t0 )) giây"

echo "== 3. Ghi thử ở REPLICA (phải bị từ chối)"
if out=$(R -e "INSERT INTO cj_check.ping (note) VALUES ('ghi-vao-replica')" 2>&1); then
  echo "LỖI: replica nhận ghi" >&2; exit 1
else
  echo "$out" | grep -v 'Using a password' || true
fi

echo "== 4. Trạng thái replication"
R -e "SHOW REPLICA STATUS\G" | grep -E ' (Source_Host|Source_User|Replica_IO_Running|Replica_SQL_Running|Seconds_Behind_Source|Auto_Position|Retrieved_Gtid_Set|Executed_Gtid_Set):'

echo "== 5. Số bản ghi app ở 2 phía"
for side in P R; do
  printf '%s: ' "$([ $side = P ] && echo PRIMARY || echo REPLICA)"
  $side -N -e "SELECT CONCAT('users=', (SELECT COUNT(*) FROM cloudjudge.users), ' problems=', (SELECT COUNT(*) FROM cloudjudge.problems),
                             ' submissions=', (SELECT COUNT(*) FROM cloudjudge.submissions))"
done
echo "OK"
