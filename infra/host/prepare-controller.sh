#!/usr/bin/env bash
# Chỉ chạy trên os-controller, quyền root. Sau prepare-all.sh.
# Cách chạy (auth key Tailscale truyền qua biến môi trường, KHÔNG ghi vào repo):
#   scp infra/host/cj-nat.sh infra/host/cj-nat.service infra/host/prepare-controller.sh cj-ctl:/tmp/
#   ssh cj-ctl 'sudo TS_AUTHKEY=tskey-... bash /tmp/prepare-controller.sh'
set -eux

# a) Cặp veth cho mạng external giả (bền qua reboot nhờ systemd-networkd)
cat > /etc/systemd/network/25-veth.netdev <<'EOF'
[NetDev]
Name=veth-host
Kind=veth
[Peer]
Name=veth-ex
EOF
cat > /etc/systemd/network/25-veth-host.network <<'EOF'
[Match]
Name=veth-host
[Network]
Address=172.24.4.1/24
ConfigureWithoutCarrier=yes
EOF
cat > /etc/systemd/network/25-veth-ex.network <<'EOF'
[Match]
Name=veth-ex
[Network]
LinkLocalAddressing=no
ConfigureWithoutCarrier=yes
EOF
systemctl enable systemd-networkd
networkctl reload || systemctl restart systemd-networkd
sleep 2
ip link set veth-host up || true
ip link set veth-ex up || true

# b) NAT/DNAT
mkdir -p /etc/cloudjudge
install -m 0755 /tmp/cj-nat.sh /usr/local/sbin/cj-nat.sh
install -m 0644 /tmp/cj-nat.service /etc/systemd/system/cj-nat.service
systemctl daemon-reload
systemctl enable --now cj-nat.service

# c) Đĩa Cinder (LVM)
if ! vgs cinder-volumes >/dev/null 2>&1; then
  pvcreate /dev/disk/by-id/google-cinder
  vgcreate cinder-volumes /dev/disk/by-id/google-cinder
fi

# d) Đĩa Swift: partition label KOLLA_SWIFT_DATA + XFS label d0
if ! blkid -L d0 >/dev/null 2>&1; then
  parted /dev/disk/by-id/google-swift -s -- mklabel gpt mkpart KOLLA_SWIFT_DATA 1 -1
  sleep 3
  mkfs.xfs -f -L d0 /dev/disk/by-id/google-swift-part1
fi

# e) Tailscale (auth key lấy từ biến môi trường TS_AUTHKEY, không lưu vào file)
if ! command -v tailscale >/dev/null; then curl -fsSL https://tailscale.com/install.sh | sh; fi
if [ -n "${TS_AUTHKEY:-}" ]; then
  tailscale up --authkey="$TS_AUTHKEY" --hostname=cj-controller \
    --advertise-routes=10.10.0.0/24,172.24.4.0/24 --accept-routes=false
fi
