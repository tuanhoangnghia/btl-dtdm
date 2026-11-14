#!/usr/bin/env bash
# Khôi phục CSDL cloudjudge từ bản sao lưu của backup-mysql.sh. CHẠY TRÊN PRIMARY: dữ liệu khôi phục tự sang replica qua binlog.
# GHI ĐÈ các bảng hiện có (DROP TABLE + CREATE + INSERT). Phải gõ YES để xác nhận, hoặc đặt CONFIRM=YES.
#   bash db/restore-mysql.sh latest                        # bản mới nhất trên Swift backups/mysql/
#   bash db/restore-mysql.sh mysql/20261105-0200.sql.gz    # một object trên Swift
#   bash db/restore-mysql.sh ./backups/mysql/x.sql.gz      # file trên máy (local)
# Biến: như backup-mysql.sh (đọc /etc/cloudjudge/backup.env); quyền root MySQL qua MYSQL_ROOT_PASSWORD hoặc /run/cj/root.pw.
set -euo pipefail
SRC=${1:?usage: restore-mysql.sh latest|mysql/<ts>.sql.gz|<file.sql.gz>}
[ -f "$SRC" ] && SRC="$(cd "$(dirname "$SRC")" && pwd)/$(basename "$SRC")"
cd "$(dirname "$0")"
. ./lib.sh
ENV_FILE=${BACKUP_ENV:-/etc/cloudjudge/backup.env}
if [ -r "$ENV_FILE" ]; then set -a; . "$ENV_FILE"; set +a; fi
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

swift_cli() {
  : "${OS_AUTH_URL:?}" "${OS_AC_ID:?}" "${OS_AC_SECRET:?}"
  OS_AUTH_TYPE=v3applicationcredential OS_REGION_NAME=${OS_REGION_NAME:-RegionOne} \
  OS_APPLICATION_CREDENTIAL_ID="$OS_AC_ID" OS_APPLICATION_CREDENTIAL_SECRET="$OS_AC_SECRET" \
    "${SWIFT_BIN:-/opt/cj/venv/bin/swift}" "$@"
}

if [ -f "$SRC" ]; then
  F=$SRC
else
  OBJ=$SRC
  [ "$OBJ" = latest ] && OBJ=$(swift_cli list backups --prefix mysql/ | sort | tail -n 1)
  [ -n "$OBJ" ] || { echo "container backups chưa có bản nào" >&2; exit 1; }
  F="$TMP/restore.sql.gz"
  swift_cli download backups "$OBJ" -o "$F" >/dev/null
  echo "đã tải backups/$OBJ"
fi
gzip -t "$F"

wait_mysql
[ "$(mysql_root -N -e 'SELECT @@read_only')" = "0" ] || { echo "$MYSQL_CONTAINER đang read_only: chỉ khôi phục trên primary" >&2; exit 1; }
echo "Trước khi khôi phục:"
mysql_root -t -e "SELECT (SELECT COUNT(*) FROM cloudjudge.users) users, (SELECT COUNT(*) FROM cloudjudge.problems) problems,
                         (SELECT COUNT(*) FROM cloudjudge.submissions) submissions" || true
if [ "${CONFIRM:-}" != YES ]; then
  read -r -p "Ghi đè CSDL cloudjudge trên $MYSQL_CONTAINER bằng $SRC? Gõ YES: " ans
  [ "$ans" = YES ] || { echo "hủy"; exit 1; }
fi

gzip -dc "$F" | mysql_root
echo "Sau khi khôi phục:"
mysql_root -t -e "SELECT (SELECT COUNT(*) FROM cloudjudge.users) users, (SELECT COUNT(*) FROM cloudjudge.problems) problems,
                         (SELECT COUNT(*) FROM cloudjudge.submissions) submissions"
