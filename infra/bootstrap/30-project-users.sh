#!/usr/bin/env bash
# Trên controller (user cj). Tạo project cloudjudge, 4 user dịch vụ (cj-*), 3 user thành viên (tuan, trong, phuong), quota.
# Mật khẩu sinh ngẫu nhiên, lưu ~/secrets/pw-<user> (chmod 600, chỉ chủ đọc). KHÔNG vào Git. Chạy lại được.
set -euo pipefail
source ~/kolla-venv/bin/activate
source /etc/kolla/admin-openrc.sh

mkdir -p ~/secrets && chmod 750 ~/secrets
getent group cj >/dev/null && chgrp cj ~/secrets || true

openstack project show cloudjudge >/dev/null 2>&1 || openstack project create --domain Default cloudjudge
# user admin của cloud có quyền admin trên cloudjudge (để tạo container Swift, chạy Heat khi cần)
openstack role add --project cloudjudge --user admin admin 2>/dev/null || true

mkuser() {  # <tên> <role...>
  local u=$1; shift
  if ! openstack user show "$u" --domain Default >/dev/null 2>&1; then
    local pw; pw=$(openssl rand -hex 16)
    ( umask 077; echo "$pw" > ~/secrets/pw-$u )
    openstack user create --domain Default --project cloudjudge --password "$pw" "$u" >/dev/null
    echo "tạo user $u"
  fi
  for r in "$@"; do openstack role add --project cloudjudge --user "$u" "$r" 2>/dev/null || true; done
}

# Danh tính ứng dụng (tương đương IAM role): quyền tối thiểu
mkuser cj-web     member
mkuser cj-worker  reader
mkuser cj-monitor reader
mkuser cj-backup  reader
# Thành viên nhóm (đăng nhập Horizon/CLI, chạy Heat)
for u in tuan trong phuong; do mkuser $u admin member heat_stack_owner; done

openstack quota set --instances 20 --cores 30 --ram 40960 --volumes 10 --gigabytes 100 --secgroups 20 --floating-ips 20 cloudjudge
chmod 600 ~/secrets/pw-* 2>/dev/null || true   # mật khẩu cá nhân/dịch vụ: CHỈ chủ (cj) đọc; nhóm chỉ đọc infra.env/app.env/data.env

echo "== Role assignment trong project cloudjudge"
openstack role assignment list --project cloudjudge --names -f value -c Role -c User | sort | sed 's/@Default//'
echo PROJECT_USERS_DONE
