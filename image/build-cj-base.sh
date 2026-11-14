#!/bin/bash
# User-data cho VM builder của golden image cj-base-v1 (KE_HOACH mục 9 + CONTRACT mục 6).
# KHÔNG chạy trực tiếp: image/build-image.sh thay 2 chỗ __..._B64__ bằng nội dung image/sandbox/ rồi mới
# truyền vào `openstack server create --user-data`. Xong việc VM tự tắt (SHUTOFF) để snapshot.
# Lỗi ở bất kỳ bước nào: in CJ_BUILD_FAILED ra console và KHÔNG tắt máy (build-image.sh sẽ báo lỗi).
set -euxo pipefail
trap 'echo "CJ_BUILD_FAILED line $LINENO" | tee /dev/console' ERR
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get -y -o Dpkg::Options::=--force-confold upgrade
apt-get install -y --no-install-recommends -o Dpkg::Options::=--force-confold \
  docker.io docker-compose-v2 prometheus-node-exporter mysql-client jq curl cron ca-certificates \
  python3-venv python3-pip gettext-base
systemctl enable docker prometheus-node-exporter cron
systemctl start docker

# ---- venv dùng chung cho web, worker, backup (lệnh swift có trong venv) ----
# giữ đồng bộ với app/requirements.txt
python3 -m venv /opt/cj/venv
/opt/cj/venv/bin/pip install -q --upgrade pip
/opt/cj/venv/bin/pip install -q \
  'flask>=3.0,<4' 'gunicorn>=22' 'sqlalchemy>=2.0,<2.2' 'pymysql>=1.1' 'cryptography>=42' 'pika>=1.3,<2' \
  'python-swiftclient>=4.4' 'keystoneauth1>=5.6' 'prometheus-client>=0.20' 'prometheus-flask-exporter>=0.23' \
  'python-openstackclient>=6.6'
/opt/cj/venv/bin/swift --version
/opt/cj/venv/bin/openstack --version

# ---- image Docker pull sẵn (★ = C cần) ----
for img in mysql:8.4 rabbitmq:4.1-management prom/prometheus:v2.55.1 prom/alertmanager:v0.27.0 \
           grafana/grafana-oss:11.3.0 prom/mysqld-exporter:v0.16.0; do
  docker pull "$img"
done

# ---- sandbox chấm bài cj-sandbox:1 ----
install -d /opt/cj/sandbox
echo '__SANDBOX_DOCKERFILE_B64__' | base64 -d > /opt/cj/sandbox/Dockerfile
echo '__SANDBOX_CJRUN_B64__' | base64 -d > /opt/cj/sandbox/cj-run
docker build --network host -t cj-sandbox:1 /opt/cj/sandbox
# tự kiểm tra: cách ly mạng, chạy được g++ và python
docker run --rm --network none --read-only --tmpfs /tmp:rw,size=16m --memory 256m --memory-swap 256m \
  --cpus 1 --pids-limit 64 --cap-drop ALL --security-opt no-new-privileges --user 10001:10001 \
  cj-sandbox:1 sh -c 'g++ --version | head -1 && python3 --version && cj-run 1000 true'

# ---- Tailscale: cài nhưng TẮT (chỉ bastion bật) ----
curl -fsSL https://tailscale.com/install.sh | sh
systemctl disable --now tailscaled

# ---- script tải release từ Swift khi boot ----
cat > /opt/cj/fetch-release.sh <<'EOF'
#!/bin/bash
# /opt/cj/fetch-release.sh <ver>: tải releases/cloudjudge-<ver>.tar.gz về /opt/cj/app/.
# Credential (application credential của chính máy) đọc từ /etc/cloudjudge/cloudjudge.env.
set -euo pipefail
VER=${1:?usage: fetch-release.sh <version>}
set -a; . /etc/cloudjudge/cloudjudge.env; set +a
cd /opt/cj
for i in 1 2 3 4 5; do
  if /opt/cj/venv/bin/swift --os-auth-type v3applicationcredential --os-auth-url "$OS_AUTH_URL" \
       --os-region-name "${OS_REGION_NAME:-RegionOne}" \
       --os-application-credential-id "$OS_AC_ID" --os-application-credential-secret "$OS_AC_SECRET" \
       download releases "cloudjudge-$VER.tar.gz" -o app.tar.gz; then
    break
  fi
  echo "tải release lần $i thất bại, thử lại"; sleep $((i * 5))
  [ "$i" = 5 ] && exit 1
done
rm -rf app.new && mkdir app.new && tar xzf app.tar.gz -C app.new
rm -rf app && mv app.new app && rm -f app.tar.gz
echo "release $VER -> /opt/cj/app"
EOF
chmod 755 /opt/cj/fetch-release.sh
install -d -m 755 /etc/cloudjudge

# ---- dọn dẹp để máy tạo từ image chạy lại cloud-init như máy mới ----
echo "cj-base-v1 built $(date -u +%FT%TZ)" > /opt/cj/IMAGE_INFO
apt-get clean
rm -rf /var/lib/apt/lists/*
journalctl --rotate && journalctl --vacuum-time=1s || true
cloud-init clean --logs --machine-id
echo "CJ_BUILD_OK" | tee /dev/console
sync
poweroff
