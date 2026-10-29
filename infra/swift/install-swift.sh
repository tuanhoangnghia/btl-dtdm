#!/usr/bin/env bash
# Cài Swift TAY trên os-controller (Kolla-Ansible >= 2025.1 không còn role Swift).
# 1 node, 1 đĩa (XFS label d0), 1 bản sao (replicas=1: không chịu lỗi đĩa, chỉ để học và demo), xác thực bằng Keystone.
# Chạy với user cj trên controller:  bash install-swift.sh
# Chạy lại được: không đổi hash path suffix / ring / mật khẩu nếu đã có. KHÔNG chứa secret trong repo.
set -euo pipefail

NODE_IP=10.10.0.10
KEYSTONE=http://10.10.0.10:5000
MEMCACHED=10.10.0.10:11211
SECRETS=$HOME/secrets/infra.env

source ~/kolla-venv/bin/activate
source /etc/kolla/admin-openrc.sh

echo "== 1. Gói"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q swift swift-proxy swift-account swift-container swift-object \
  python3-swiftclient python3-keystoneclient python3-keystonemiddleware xfsprogs rsync

echo "== 2. Mount đĩa d0"
sudo mkdir -p /srv/node/d0
grep -q "LABEL=d0" /etc/fstab || echo "LABEL=d0 /srv/node/d0 xfs noatime,nodiratime,logbufs=8,nofail 0 2" | sudo tee -a /etc/fstab >/dev/null
mountpoint -q /srv/node/d0 || sudo mount /srv/node/d0
sudo chown -R swift:swift /srv/node
sudo mkdir -p /var/cache/swift /var/run/swift && sudo chown -R swift:swift /var/cache/swift /var/run/swift
sudo chmod -R 775 /var/cache/swift

echo "== 3. Mật khẩu user dịch vụ swift (lưu ~/secrets/infra.env, không vào Git)"
mkdir -p ~/secrets && chmod 750 ~/secrets
touch "$SECRETS" && chmod 640 "$SECRETS"
if ! grep -q '^SWIFT_SERVICE_PASSWORD=' "$SECRETS"; then
  echo "SWIFT_SERVICE_PASSWORD=$(openssl rand -hex 16)" >> "$SECRETS"
fi
SWIFT_PW=$(grep '^SWIFT_SERVICE_PASSWORD=' "$SECRETS" | cut -d= -f2)

echo "== 4. Keystone: user, role, service, endpoint"
openstack user show swift --domain Default >/dev/null 2>&1 || \
  openstack user create --domain Default --password "$SWIFT_PW" swift
openstack user set --password "$SWIFT_PW" swift
openstack role assignment list --user swift --project service --role admin --names -f value 2>/dev/null | grep -q . || \
  openstack role add --project service --user swift admin
openstack service show object-store >/dev/null 2>&1 || \
  openstack service create --name swift --description "OpenStack Object Storage" object-store
for iface in public internal admin; do
  openstack endpoint list --service object-store --interface $iface -f value -c ID | grep -q . || \
    openstack endpoint create --region RegionOne object-store $iface "http://${NODE_IP}:8080/v1/AUTH_%(project_id)s"
done

echo "== 5. Cấu hình /etc/swift"
sudo mkdir -p /etc/swift && sudo chown -R swift:swift /etc/swift && sudo chmod 755 /etc/swift   # dir 755 để glob chạy được; file .conf vẫn 640
if [ ! -s /etc/swift/swift.conf ]; then
  sudo tee /etc/swift/swift.conf >/dev/null <<EOF
[swift-hash]
swift_hash_path_suffix = $(openssl rand -hex 16)
swift_hash_path_prefix = $(openssl rand -hex 16)

[storage-policy:0]
name = Policy-0
default = yes
EOF
fi

for spec in account:6202 container:6201 object:6200; do
  svc=${spec%%:*}; port=${spec##*:}
  extra=""
  case $svc in
    account)   extra=$'[account-replicator]\n\n[account-auditor]\n\n[account-reaper]\n' ;;
    container) extra=$'[container-replicator]\n\n[container-updater]\n\n[container-auditor]\n' ;;
    object)    extra=$'[object-replicator]\n\n[object-reconstructor]\n\n[object-updater]\n\n[object-auditor]\n' ;;
  esac
  sudo tee /etc/swift/${svc}-server.conf >/dev/null <<EOF
[DEFAULT]
bind_ip = ${NODE_IP}
bind_port = ${port}
user = swift
swift_dir = /etc/swift
devices = /srv/node
mount_check = True

[pipeline:main]
pipeline = healthcheck recon ${svc}-server

[app:${svc}-server]
use = egg:swift#${svc}

[filter:healthcheck]
use = egg:swift#healthcheck

[filter:recon]
use = egg:swift#recon
recon_cache_path = /var/cache/swift
$( [ $svc = object ] && echo "recon_lock_path = /var/lock" )

${extra}
EOF
done

sudo tee /etc/swift/proxy-server.conf >/dev/null <<EOF
[DEFAULT]
bind_ip = ${NODE_IP}
bind_port = 8080
user = swift
swift_dir = /etc/swift

[pipeline:main]
pipeline = catch_errors gatekeeper healthcheck proxy-logging cache listing_formats bulk ratelimit authtoken keystoneauth copy container-quotas account-quotas slo dlo versioned_writes proxy-logging proxy-server

[app:proxy-server]
use = egg:swift#proxy
account_autocreate = True

[filter:keystoneauth]
use = egg:swift#keystoneauth
operator_roles = admin, member, swiftoperator

[filter:authtoken]
paste.filter_factory = keystonemiddleware.auth_token:filter_factory
www_authenticate_uri = ${KEYSTONE}
auth_url = ${KEYSTONE}
memcached_servers = ${MEMCACHED}
auth_type = password
project_domain_id = default
user_domain_id = default
project_name = service
username = swift
password = ${SWIFT_PW}
delay_auth_decision = True

[filter:healthcheck]
use = egg:swift#healthcheck

[filter:cache]
use = egg:swift#memcache
memcache_servers = ${MEMCACHED}

[filter:ratelimit]
use = egg:swift#ratelimit

[filter:domain_remap]
use = egg:swift#domain_remap

[filter:catch_errors]
use = egg:swift#catch_errors

[filter:gatekeeper]
use = egg:swift#gatekeeper

[filter:proxy-logging]
use = egg:swift#proxy_logging

[filter:listing_formats]
use = egg:swift#listing_formats

[filter:bulk]
use = egg:swift#bulk

[filter:copy]
use = egg:swift#copy

[filter:container-quotas]
use = egg:swift#container_quotas

[filter:account-quotas]
use = egg:swift#account_quotas

[filter:slo]
use = egg:swift#slo

[filter:dlo]
use = egg:swift#dlo

[filter:versioned_writes]
use = egg:swift#versioned_writes
allow_versioned_writes = true
EOF
sudo chmod 640 /etc/swift/proxy-server.conf
sudo chown swift:swift /etc/swift/*.conf

echo "== 6. Ring (chỉ tạo nếu chưa có; replicas=1)"
cd /etc/swift
for spec in account:6202 container:6201 object:6200; do
  svc=${spec%%:*}; port=${spec##*:}
  if [ ! -f /etc/swift/${svc}.ring.gz ]; then
    sudo -u swift swift-ring-builder ${svc}.builder create 10 1 1
    sudo -u swift swift-ring-builder ${svc}.builder add --region 1 --zone 1 --ip ${NODE_IP} --port ${port} --device d0 --weight 100
    sudo -u swift swift-ring-builder ${svc}.builder rebalance
  fi
done
sudo chown swift:swift /etc/swift/*.ring.gz /etc/swift/*.builder 2>/dev/null || true
sudo chmod 640 /etc/swift/*.conf
sudo chmod 644 /etc/swift/*.ring.gz

echo "== 7. Khởi động dịch vụ"
UNITS="swift-proxy swift-account swift-account-auditor swift-account-reaper swift-account-replicator \
swift-container swift-container-auditor swift-container-replicator swift-container-updater \
swift-object swift-object-auditor swift-object-replicator swift-object-updater"
for u in $UNITS; do
  if systemctl list-unit-files "${u}.service" --no-legend 2>/dev/null | grep -q "${u}.service"; then
    sudo systemctl enable "$u" >/dev/null 2>&1 || true
    sudo systemctl restart "$u" || echo "!! $u không khởi động được"
  else
    echo "(bỏ qua: không có unit $u)"
  fi
done
sleep 5
systemctl is-active $UNITS 2>/dev/null | sort | uniq -c
echo SWIFT_INSTALL_DONE
