#!/usr/bin/env bash
# Local (cần Docker): dựng primary + replica, nạp schema + user, nối replica, kiểm tra replication, thử backup → restore.
#   bash db/local-up.sh
# Mật khẩu dev giống app/dev/02-users.sql của B (cj_app = dev-app, cj_ro = dev-ro); không phải secret của cụm.
set -euo pipefail
cd "$(dirname "$0")"
export MYSQL_ROOT_PASSWORD=dev-root DB_PASSWORD=dev-app DB_RO_PASSWORD=dev-ro REPL_PASSWORD=dev-repl \
       EXPORTER_PASSWORD=dev-exporter BACKUP_DB_PASSWORD=dev-backup
# local: các container nói chuyện qua mạng bridge của compose, không có IP cố định như trên cụm
export APP_HOSTS=% REPL_HOSTS=% LOCAL_HOSTS=%

docker compose -f docker-compose.repl.yml up -d
MYSQL_CONTAINER=cj-mysql-primary bash setup-primary.sh
MYSQL_CONTAINER=cj-mysql-replica SOURCE_HOST=mysql-primary bash setup-replica.sh
bash test-replication.sh

echo "== backup ra thư mục db/backups-local (thay cho Swift)"
MYSQL_CONTAINER=cj-mysql-primary BACKUP_DIR=./backups-local BACKUP_ENV=/dev/null bash backup-mysql.sh
LAST=$(ls -1 backups-local/mysql/*.sql.gz | sort | tail -n 1)
echo "== restore từ $LAST vào primary (replica tự nhận)"
MYSQL_CONTAINER=cj-mysql-primary BACKUP_ENV=/dev/null CONFIRM=YES bash restore-mysql.sh "$LAST"
bash test-replication.sh >/dev/null && echo "replication vẫn chạy sau restore"

echo
echo "Xong. MySQL: primary 127.0.0.1:13306, replica 127.0.0.1:13307 · exporter: http://127.0.0.1:9104/metrics, :9105/metrics"
