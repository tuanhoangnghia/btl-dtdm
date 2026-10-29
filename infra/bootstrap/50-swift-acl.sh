#!/usr/bin/env bash
# Trên controller. Tạo 4 container Swift trong project cloudjudge và đặt ACL theo CONTRACT mục 8.1. Chạy lại được.
#   submissions : web ghi, worker đọc | testcases : web ghi, worker đọc | releases : admin/deploy ghi, worker+backup đọc | backups : backup đọc/ghi
set -euo pipefail
source ~/kolla-venv/bin/activate
source /etc/kolla/admin-openrc.sh
export OS_PROJECT_NAME=cloudjudge OS_TENANT_NAME=cloudjudge OS_PROJECT_DOMAIN_NAME=Default
unset OS_PROJECT_ID OS_TENANT_ID

PID=$(openstack project show cloudjudge -f value -c id)
uid() { openstack user show "$1" --domain Default -f value -c id; }
W=$(uid cj-worker); B=$(uid cj-backup)

for c in submissions testcases releases backups; do openstack container create "$c" -f value -c container; done
swift post submissions --read-acl "$PID:$W"
swift post testcases   --read-acl "$PID:$W"
swift post releases    --read-acl "$PID:$W,$PID:$B"
swift post backups     --read-acl "$PID:$B" --write-acl "$PID:$B"

for c in submissions testcases releases backups; do
  printf '%-12s read=%s write=%s\n' "$c" "$(swift stat $c | awk '/Read ACL/{print $3}')" "$(swift stat $c | awk '/Write ACL/{print $3}')"
done
echo SWIFT_ACL_DONE
