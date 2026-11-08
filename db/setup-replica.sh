#!/usr/bin/env bash
# Trên máy mysql-replica (cloud-init của cj-data gọi) hoặc local (local-up.sh gọi).
# Nối replica vào primary bằng GTID (SOURCE_AUTO_POSITION=1), bật super_read_only, chờ 2 luồng replication chạy. Chạy lại được.
#   REPL_PASSWORD=... bash db/setup-replica.sh
# Tùy chọn: SOURCE_HOST (10.0.3.10), MYSQL_CONTAINER (cj-mysql), MYSQL_ROOT_PASSWORD (không có thì đọc /run/cj/root.pw).
# Replica nhận toàn bộ schema và user từ binlog của primary, nên không chạy setup-primary.sh ở đây.
set -euo pipefail
cd "$(dirname "$0")"
. ./lib.sh
require REPL_PASSWORD
SOURCE_HOST=${SOURCE_HOST:-10.0.3.10}

wait_mysql

echo "chờ primary $SOURCE_HOST nhận đăng nhập của user repl..."
for i in $(seq 1 120); do
  docker exec -e MYSQL_PWD="$REPL_PASSWORD" "$MYSQL_CONTAINER" \
    mysql -h"$SOURCE_HOST" -urepl --get-server-public-key -N -e 'SELECT 1' >/dev/null 2>&1 && break
  [ "$i" = 120 ] && { echo "primary chưa sẵn sàng sau 10 phút" >&2; exit 1; }
  sleep 5
done

state=$(mysql_root -N -e "SELECT SERVICE_STATE FROM performance_schema.replication_connection_status" 2>/dev/null || true)
if [ "$state" = "ON" ]; then
  echo "replication đã chạy, giữ nguyên"
else
  # CHANGE REPLICATION SOURCE chỉ chạy được khi replica dừng; mật khẩu đi qua stdin, không lộ trên dòng lệnh
  mysql_root <<SQL
STOP REPLICA;
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST='$SOURCE_HOST', SOURCE_PORT=3306,
  SOURCE_USER='repl', SOURCE_PASSWORD='$REPL_PASSWORD',
  SOURCE_AUTO_POSITION=1, GET_SOURCE_PUBLIC_KEY=1, SOURCE_CONNECT_RETRY=10;
START REPLICA;
SQL
fi
mysql_root -e "SET PERSIST read_only = ON; SET PERSIST super_read_only = ON;"

for i in $(seq 1 30); do
  st=$(mysql_root -N -e "SELECT
      (SELECT SERVICE_STATE FROM performance_schema.replication_connection_status),
      (SELECT GROUP_CONCAT(SERVICE_STATE) FROM performance_schema.replication_applier_status_by_worker)")
  case "$st" in ON$'\t'ON*) ok=1; break ;; esac
  ok=0; sleep 2
done
mysql_root -e "SHOW REPLICA STATUS\G" | grep -E 'Source_Host|Replica_IO_Running|Replica_SQL_Running|Seconds_Behind_Source|Last_(IO|SQL)_Error:|Executed_Gtid_Set' || true
[ "$ok" = 1 ] || { echo "replication CHƯA chạy (xem Last_IO_Error / Last_SQL_Error ở trên)" >&2; exit 1; }
echo "replica: replication chạy, super_read_only = ON"
