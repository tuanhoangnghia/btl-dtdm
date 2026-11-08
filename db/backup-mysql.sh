#!/usr/bin/env bash
# Sao lưu CSDL cloudjudge: mysqldump --single-transaction (không khóa bảng) | gzip, rồi
#   - mặc định: upload Swift backups/mysql/<YYYYmmdd-HHMM>.sql.gz, header X-Delete-After: 604800 (tự xóa sau 7 ngày, CONTRACT 8.1)
#   - BACKUP_DIR=<thư mục>: ghi file vào thư mục (dùng ở local, không cần Swift)
# Trên cụm: cron 02:00 trên mysql-primary (cloud-init của cj-data cài), credential cj-backup.
#   bash db/backup-mysql.sh
# Biến (đọc thêm từ /etc/cloudjudge/backup.env nếu có, hoặc file ở BACKUP_ENV):
#   BACKUP_DB_PASSWORD (user MySQL backup), MYSQL_CONTAINER (cj-mysql)
#   Swift: OS_AUTH_URL, OS_REGION_NAME, OS_AC_ID, OS_AC_SECRET (application credential cj-backup), SWIFT_BIN
set -euo pipefail
export MSYS_NO_PATHCONV=1
ENV_FILE=${BACKUP_ENV:-/etc/cloudjudge/backup.env}
if [ -r "$ENV_FILE" ]; then set -a; . "$ENV_FILE"; set +a; fi
: "${BACKUP_DB_PASSWORD:?thiếu BACKUP_DB_PASSWORD}"
C=${MYSQL_CONTAINER:-cj-mysql}
TS=$(date -u +%Y%m%d-%H%M)
OBJ="mysql/$TS.sql.gz"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
F="$TMP/$TS.sql.gz"

# --set-gtid-purged=OFF: khôi phục vào primary đang chạy sẽ sinh GTID mới và tự sang replica
docker exec -e MYSQL_PWD="$BACKUP_DB_PASSWORD" "$C" mysqldump -h127.0.0.1 --protocol=TCP -ubackup \
  --single-transaction --quick --set-gtid-purged=OFF --no-tablespaces --triggers --events \
  --databases cloudjudge | gzip -9 > "$F"
gzip -t "$F"
gzip -dc "$F" | tail -n 1 | grep -q 'Dump completed' || { echo "bản dump không trọn vẹn" >&2; exit 1; }
SIZE=$(wc -c < "$F" | tr -d ' ')

if [ -n "${BACKUP_DIR:-}" ]; then
  mkdir -p "$BACKUP_DIR/mysql"
  cp "$F" "$BACKUP_DIR/$OBJ"
  echo "$(date -u +%FT%TZ) backup OK: $BACKUP_DIR/$OBJ ($SIZE byte)"
else
  : "${OS_AUTH_URL:?}" "${OS_AC_ID:?}" "${OS_AC_SECRET:?}"
  SWIFT=${SWIFT_BIN:-/opt/cj/venv/bin/swift}
  # credential qua biến môi trường của swiftclient, không đưa lên dòng lệnh (ps thấy được)
  export OS_AUTH_TYPE=v3applicationcredential OS_REGION_NAME=${OS_REGION_NAME:-RegionOne} \
         OS_APPLICATION_CREDENTIAL_ID="$OS_AC_ID" OS_APPLICATION_CREDENTIAL_SECRET="$OS_AC_SECRET"
  # cj-backup chỉ có quyền ghi object qua ACL, PUT container sẽ bị 403 nên phải --skip-container-put
  "$SWIFT" upload --skip-container-put --header "X-Delete-After: 604800" --object-name "$OBJ" backups "$F" >/dev/null
  echo "$(date -u +%FT%TZ) backup OK: swift backups/$OBJ ($SIZE byte, tự xóa sau 7 ngày)"
fi

# Metric cho Prometheus qua textfile collector của node_exporter (gói Ubuntu đọc thư mục này), có thì ghi
TXT=/var/lib/prometheus/node-exporter
if [ -d "$TXT" ] && [ -w "$TXT" ]; then
  printf '# HELP cj_backup_last_success_timestamp_seconds Lần backup MySQL thành công gần nhất\n# TYPE cj_backup_last_success_timestamp_seconds gauge\ncj_backup_last_success_timestamp_seconds %s\ncj_backup_last_size_bytes %s\n' \
    "$(date +%s)" "$SIZE" > "$TXT/cj_backup.prom.$$"
  mv "$TXT/cj_backup.prom.$$" "$TXT/cj_backup.prom"
fi
