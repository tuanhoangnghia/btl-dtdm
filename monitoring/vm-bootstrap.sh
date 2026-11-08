#!/usr/bin/env bash
# Chạy MỘT LẦN khi VM monitor của stack cj-mon boot (cloud-init runcmd, quyền root). Không chạy tay trên laptop.
#   bash /opt/cj-mon/vm-bootstrap.sh
# Đầu vào (cloud-init ghi sẵn): /opt/cj-mon/* (các file của monitoring/), /etc/cloudjudge/mon.env (600).
# Việc: SSH key cho user cj → render cấu hình vào /etc/cj-mon → docker compose up (Prometheus, Alertmanager, Grafana).
# Xong in CJ_MON_READY ra console (deploy-cj-mon.sh chờ dòng này); lỗi in CJ_MON_FAILED.
set -euo pipefail
trap 'echo "CJ_MON_FAILED line $LINENO" | tee /dev/console' ERR
D=/opt/cj-mon
set -a; . /etc/cloudjudge/mon.env; set +a

install -d -m 700 -o cj -g cj /home/cj/.ssh
echo "$ADMIN_SSH_PUBKEYS_B64" | base64 -d > /home/cj/.ssh/authorized_keys
chown cj:cj /home/cj/.ssh/authorized_keys; chmod 600 /home/cj/.ssh/authorized_keys

bash $D/render.sh /etc/cj-mon
CJ_MON_CONF=/etc/cj-mon docker compose -f $D/docker-compose.yml up -d

for i in $(seq 1 60); do
  curl -fs localhost:9090/-/ready >/dev/null && curl -fs localhost:9093/-/ready >/dev/null && curl -fs localhost:3000/api/health >/dev/null && break
  sleep 5
done
curl -fs localhost:9090/-/ready >/dev/null && curl -fs localhost:9093/-/ready >/dev/null && curl -fs localhost:3000/api/health >/dev/null
echo "CJ_MON_READY" | tee /dev/console
