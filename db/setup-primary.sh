#!/usr/bin/env bash
# Trên máy mysql-primary (cloud-init của cj-data gọi) hoặc local (local-up.sh gọi).
# Nạp db/schema.sql và tạo user MySQL theo CONTRACT 8.3. Chạy lại được (schema dùng IF NOT EXISTS, user được đặt lại mật khẩu).
#   DB_PASSWORD=... DB_RO_PASSWORD=... REPL_PASSWORD=... EXPORTER_PASSWORD=... BACKUP_DB_PASSWORD=... bash db/setup-primary.sh
# Tùy chọn: MYSQL_CONTAINER (cj-mysql), MYSQL_ROOT_PASSWORD (không có thì đọc /run/cj/root.pw trong container),
#           APP_HOSTS / REPL_HOSTS / LOCAL_HOSTS (mặc định theo mạng cụm, local đặt '%').
set -euo pipefail
cd "$(dirname "$0")"
. ./lib.sh
require DB_PASSWORD DB_RO_PASSWORD REPL_PASSWORD EXPORTER_PASSWORD BACKUP_DB_PASSWORD
export APP_HOSTS=${APP_HOSTS:-10.0.2.%} REPL_HOSTS=${REPL_HOSTS:-10.0.3.%} LOCAL_HOSTS=${LOCAL_HOSTS:-127.0.0.1}

wait_mysql
[ "$(mysql_root -N -e 'SELECT @@read_only')" = "0" ] || { echo "$MYSQL_CONTAINER đang read_only, đây không phải primary" >&2; exit 1; }

mysql_root < schema.sql
render users.sql.tpl DB_PASSWORD DB_RO_PASSWORD REPL_PASSWORD EXPORTER_PASSWORD BACKUP_DB_PASSWORD \
  APP_HOSTS REPL_HOSTS LOCAL_HOSTS | mysql_root

echo "primary: schema + user xong"
mysql_root -t -e "SELECT user, host FROM mysql.user WHERE user IN ('cj_app','cj_ro','repl','exporter','backup') ORDER BY user;
                  SELECT @@server_id AS server_id, @@gtid_mode AS gtid_mode, @@gtid_executed AS gtid_executed\G"
