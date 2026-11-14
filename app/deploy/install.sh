#!/bin/bash
# Cài app đã giải nén ở /opt/cj/app thành dịch vụ systemd. User-data của Heat gọi:
#   /opt/cj/fetch-release.sh <ver> && bash /opt/cj/app/deploy/install.sh web|worker
# Chạy lại được (vd sau khi tải release mới bằng tay để thử).
set -euo pipefail
ROLE=${1:?usage: install.sh web|worker}
APP=/opt/cj/app
VENV=/opt/cj/venv
ENV_FILE=/etc/cloudjudge/cloudjudge.env

case "$ROLE" in web|worker) ;; *) echo "vai trò không hợp lệ: $ROLE" >&2; exit 2 ;; esac
[ -f "$ENV_FILE" ] || { echo "thiếu $ENV_FILE" >&2; exit 1; }
chmod 600 "$ENV_FILE"

# release đóng gói sai quyền (thư mục 700) thì cjsvc không đọc được code
chmod -R u=rwX,go=rX "$APP"

id cjsvc >/dev/null 2>&1 || useradd --system --home-dir /var/lib/cj --shell /usr/sbin/nologin cjsvc
install -d -o cjsvc -g cjsvc -m 755 /var/lib/cj

# venv có sẵn trong cj-base-v1; nếu chạy trên ubuntu-24.04 trơn thì tự cài (chậm hơn, cần Internet)
if ! "$VENV/bin/python" -c "import flask, gunicorn, sqlalchemy, pymysql, pika, swiftclient, keystoneauth1, prometheus_client" 2>/dev/null; then
  echo "venv thiếu gói, cài từ requirements.txt"
  python3 -m venv --help >/dev/null 2>&1 || { apt-get update && apt-get install -y python3-venv; }
  [ -x "$VENV/bin/python" ] || python3 -m venv "$VENV"
  "$VENV/bin/pip" install -q -r "$APP/requirements.txt"
fi

install -m 755 "$APP/deploy/cj-cli" /usr/local/bin/cj-cli

if [ "$ROLE" = worker ]; then
  command -v docker >/dev/null || { apt-get update && apt-get install -y docker.io; }
  systemctl enable --now docker
  usermod -aG docker cjsvc
  install -d -o cjsvc -g cjsvc -m 755 /var/lib/cj/work
  IMG=$(sed -n 's/^SANDBOX_IMAGE = "\(.*\)"/\1/p' "$APP/cloudjudge/worker/sandbox.py")
  if ! docker image inspect "$IMG" >/dev/null 2>&1; then
    echo "chưa có image $IMG, build từ $APP/deploy/sandbox"
    docker build --network host -t "$IMG" "$APP/deploy/sandbox"
  fi
fi

install -m 644 "$APP/deploy/systemd/cj-$ROLE.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable "cj-$ROLE"
systemctl restart "cj-$ROLE"
systemctl enable --now prometheus-node-exporter 2>/dev/null || true

# chờ dịch vụ lên để log cloud-init cho biết kết quả
for _ in $(seq 1 30); do
  if [ "$ROLE" = web ]; then curl -fsS -m 2 http://127.0.0.1:8000/healthz && break
  else curl -fsS -m 2 http://127.0.0.1:9200/metrics >/dev/null && echo "worker metrics OK" && break; fi
  sleep 2
done
echo "CJ_INSTALL_DONE role=$ROLE release=$(cat "$APP/VERSION" 2>/dev/null || echo '?')"
