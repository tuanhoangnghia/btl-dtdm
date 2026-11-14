#!/usr/bin/env bash
# Chạy MỘT LẦN khi VM của stack cj-data boot (cloud-init runcmd, quyền root). Không chạy tay trên laptop.
#   bash /opt/cj-db/vm-bootstrap.sh <mysql-primary|mysql-replica|rabbitmq>
# Đầu vào (cloud-init ghi sẵn): /opt/cj-db/* (các file của db/ và monitoring/rabbitmq/), /etc/cloudjudge/data.env (600).
# Việc: SSH key cho user cj → định dạng + mount volume Cinder ở /data → chạy container theo vai trò.
# Volume giữ dữ liệu; nếu VM bị tạo lại thì script thấy filesystem + datadir cũ và dùng lại (không khởi tạo lại).
# Xong in CJ_DATA_READY <vai trò> ra console (deploy-cj-data.sh chờ dòng này); lỗi in CJ_DATA_FAILED.
set -euo pipefail
ROLE=${1:?usage: vm-bootstrap.sh <mysql-primary|mysql-replica|rabbitmq>}
trap 'echo "CJ_DATA_FAILED $ROLE line $LINENO" | tee /dev/console' ERR
D=/opt/cj-db
set -a; . /etc/cloudjudge/data.env; set +a

# ---- SSH key quản trị cho user cj (giống web/worker của B) ----
install -d -m 700 -o cj -g cj /home/cj/.ssh
echo "$ADMIN_SSH_PUBKEYS_B64" | base64 -d > /home/cj/.ssh/authorized_keys
chown cj:cj /home/cj/.ssh/authorized_keys; chmod 600 /home/cj/.ssh/authorized_keys

# ---- Volume Cinder → /data (serial virtio = 20 ký tự đầu của volume id) ----
DEV=/dev/disk/by-id/virtio-${DATA_VOLUME_ID:0:20}
for i in $(seq 1 90); do [ -b "$DEV" ] && break; sleep 2; done
[ -b "$DEV" ] || { echo "không thấy volume $DEV" >&2; false; }
blkid "$DEV" >/dev/null 2>&1 || mkfs.ext4 -q -L cjdata "$DEV"
mkdir -p /data
grep -q ' /data ' /etc/fstab || echo "LABEL=cjdata /data ext4 defaults,nofail 0 2" >> /etc/fstab
mountpoint -q /data || mount /data

case "$ROLE" in
mysql-primary|mysql-replica)
  install -d -m 755 /etc/cj-db /data/mysql
  if [ "$ROLE" = mysql-primary ]; then install -m 644 $D/primary.cnf /etc/cj-db/my.cnf
  else install -m 644 $D/replica.cnf /etc/cj-db/my.cnf; fi
  ( umask 077; printf '%s' "$MYSQL_ROOT_PASSWORD" > /etc/cj-db/root.pw )
  chown 999:999 /etc/cj-db/root.pw    # user mysql trong image mysql:8.4
  # root chỉ đăng nhập qua socket trong container; mật khẩu đọc từ file, không nằm trong biến môi trường
  docker inspect cj-mysql >/dev/null 2>&1 || docker run -d --name cj-mysql --restart unless-stopped --network host \
    -e MYSQL_ROOT_PASSWORD_FILE=/run/cj/root.pw -e MYSQL_ROOT_HOST=localhost \
    -v /etc/cj-db/root.pw:/run/cj/root.pw:ro -v /etc/cj-db/my.cnf:/etc/mysql/conf.d/cj.cnf:ro \
    -v /data/mysql:/var/lib/mysql mysql:8.4
  # lệnh tắt cho quản trị: sudo cj-mysql -e "SHOW REPLICA STATUS\G"
  cat > /usr/local/bin/cj-mysql <<'EOF'
#!/bin/sh
exec docker exec -i cj-mysql sh -c 'MYSQL_PWD=$(cat /run/cj/root.pw) exec mysql -uroot "$@"' sh "$@"
EOF
  chmod 755 /usr/local/bin/cj-mysql

  if [ "$ROLE" = mysql-primary ]; then
    bash $D/setup-primary.sh
  else
    SOURCE_HOST=$DB_PRIMARY_HOST bash $D/setup-replica.sh
  fi

  docker inspect cj-mysqld-exporter >/dev/null 2>&1 || docker run -d --name cj-mysqld-exporter --restart unless-stopped \
    --network host -e MYSQLD_EXPORTER_PASSWORD="$EXPORTER_PASSWORD" prom/mysqld-exporter:v0.16.0 \
    --mysqld.address=127.0.0.1:3306 --mysqld.username=exporter --web.listen-address=:9104

  if [ "$ROLE" = mysql-primary ]; then
    # backup hằng ngày lên Swift bằng application credential cj-backup (chỉ ghi được container backups)
    ( umask 077; cat > /etc/cloudjudge/backup.env <<EOF
BACKUP_DB_PASSWORD=$BACKUP_DB_PASSWORD
MYSQL_CONTAINER=cj-mysql
OS_AUTH_URL=http://10.10.0.10:5000/v3
OS_REGION_NAME=RegionOne
OS_AC_ID=$BACKUP_AC_ID
OS_AC_SECRET=$BACKUP_AC_SECRET
EOF
    )
    printf '# backup MySQL hằng ngày, 19:00 UTC = 02:00 giờ VN (db/backup-mysql.sh)\n0 19 * * * root bash %s/backup-mysql.sh >> /var/log/cj-backup.log 2>&1\n' "$D" > /etc/cron.d/cj-backup
    chmod 644 /etc/cron.d/cj-backup
  fi
  ;;

rabbitmq)
  install -d -m 755 /etc/cj-mq /data/rabbitmq
  install -m 644 $D/rabbitmq.conf /etc/cj-mq/90-cloudjudge.conf
  install -m 644 $D/enabled_plugins /etc/cj-mq/enabled_plugins
  # --network host: tên node là rabbit@<hostname VM> (cố định = tên server), dữ liệu theo tên node nằm trên volume
  docker inspect cj-rabbitmq >/dev/null 2>&1 || docker run -d --name cj-rabbitmq --restart unless-stopped --network host \
    -e RABBITMQ_DEFAULT_USER=cj -e RABBITMQ_DEFAULT_PASS="$MQ_PASSWORD" \
    -v /etc/cj-mq/90-cloudjudge.conf:/etc/rabbitmq/conf.d/90-cloudjudge.conf:ro \
    -v /etc/cj-mq/enabled_plugins:/etc/rabbitmq/enabled_plugins:ro \
    -v /data/rabbitmq:/var/lib/rabbitmq rabbitmq:4.1-management
  for i in $(seq 1 60); do docker exec cj-rabbitmq rabbitmq-diagnostics -q check_port_connectivity >/dev/null 2>&1 && break; sleep 5; done
  docker exec cj-rabbitmq rabbitmq-diagnostics -q check_port_connectivity
  # queue submissions do app tự khai báo (durable, không argument, CONTRACT 8.2); ở đây không khai báo để tránh lệch tham số
  ;;
*) echo "vai trò lạ: $ROLE" >&2; false ;;
esac

echo "CJ_DATA_READY $ROLE" | tee /dev/console
