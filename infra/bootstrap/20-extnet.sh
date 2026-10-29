#!/usr/bin/env bash
# Mạng external giả: flat physnet1 -> br-ex -> veth-ex <-> veth-host (172.24.4.1) trên controller. Chạy lại được.
set -euo pipefail
source ~/kolla-venv/bin/activate
source /etc/kolla/admin-openrc.sh

openstack network show ext-net >/dev/null 2>&1 || \
  openstack network create --external --share --provider-network-type flat --provider-physical-network physnet1 ext-net
openstack subnet show ext-subnet >/dev/null 2>&1 || \
  openstack subnet create ext-subnet --network ext-net --subnet-range 172.24.4.0/24 \
    --gateway 172.24.4.1 --no-dhcp --allocation-pool start=172.24.4.10,end=172.24.4.250
openstack network list --external -c Name -c Subnets
echo EXTNET_DONE
