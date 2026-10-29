#!/usr/bin/env bash
# Chạy trên controller (user cj). Tạo 2 AZ (host aggregate), flavor, image nền. Chạy lại được.
set -euo pipefail
source ~/kolla-venv/bin/activate
source /etc/kolla/admin-openrc.sh

echo "== AZ: az1 = os-compute-1 (zone a), az2 = os-compute-2 (zone b)"
for n in 1 2; do
  openstack aggregate show agg-az$n >/dev/null 2>&1 || openstack aggregate create --zone az$n agg-az$n
  host=$(openstack compute service list --service nova-compute -f value -c Host | grep "^os-compute-$n\." | head -1)
  [ -n "$host" ] || { echo "Không thấy nova-compute của os-compute-$n"; exit 1; }
  openstack aggregate show agg-az$n -f value -c hosts | grep -q "$host" || openstack aggregate add host agg-az$n "$host"
done
openstack availability zone list --compute --long -f value -c "Zone Name" -c "Host Name" | sort -u | grep -E "^az|os-compute"

echo "== Flavor"
mk() { openstack flavor show "$1" >/dev/null 2>&1 || openstack flavor create "$1" --vcpus "$2" --ram "$3" --disk "$4" --public >/dev/null; }
mk cj.tiny   1 512  10
mk cj.small  1 1024 10
mk cj.medium 1 2048 20
openstack flavor list -c Name -c VCPUs -c RAM -c Disk

echo "== Image"
cd /tmp
if ! openstack image show ubuntu-24.04 >/dev/null 2>&1; then
  wget -q -nc https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
  openstack image create ubuntu-24.04 --disk-format qcow2 --container-format bare --public \
    --property os_distro=ubuntu --file noble-server-cloudimg-amd64.img >/dev/null
fi
if ! openstack image show cirros >/dev/null 2>&1; then
  wget -q -nc https://download.cirros-cloud.net/0.6.2/cirros-0.6.2-x86_64-disk.img
  openstack image create cirros --disk-format qcow2 --container-format bare --public \
    --file cirros-0.6.2-x86_64-disk.img >/dev/null
fi
openstack image list -c Name -c Status
echo AZ_FLAVOR_IMAGE_DONE
