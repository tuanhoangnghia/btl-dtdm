#!/usr/bin/env bash
# Build ảnh amphora KHỚP phiên bản Octavia (stable/2025.2) bằng diskimage-builder rồi đưa vào Glance (project service, tag amphora).
# Lý do tự build: ảnh test dựng sẵn trên tarballs.opendev.org build từ master, có thể lệch agent với Octavia 2025.2.
# Chạy trên controller, trong tmux (mất ~10-20 phút):  tmux new -d -s amp "bash 60-build-amphora.sh 2>&1 | tee ~/logs/06-amphora.log"
set -euo pipefail
OUT=$HOME/amphora-x64-haproxy.qcow2
if [ ! -s "$OUT" ]; then
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q debootstrap qemu-utils kpartx git e2fsprogs squashfs-tools curl python3-venv
  python3 -m venv ~/dib-venv
  source ~/dib-venv/bin/activate
  pip install -q -U pip diskimage-builder
  [ -d ~/octavia-src ] || git clone -q --depth 1 -b stable/2025.2 https://opendev.org/openstack/octavia ~/octavia-src
  cd ~/octavia-src/diskimage-create
  ./diskimage-create.sh -i ubuntu-minimal -d noble -s 3 -o "${OUT%.qcow2}"
  deactivate
fi
ls -lh "$OUT"

source ~/kolla-venv/bin/activate
source /etc/kolla/octavia-openrc.sh
if ! openstack image list --tag amphora -f value -c Name | grep -q .; then
  openstack image create amphora-x64-haproxy --container-format bare --disk-format qcow2 --private \
    --tag amphora --property hw_architecture=x86_64 --property hw_rng_model=virtio --file "$OUT"
fi
openstack image list --tag amphora -c Name -c Status
echo AMPHORA_DONE
