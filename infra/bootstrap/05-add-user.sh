#!/usr/bin/env bash
# Trên controller, chạy với sudo (root). Tạo user Linux cho thành viên nhóm, cấp sudo, group cj (đọc ~/secrets), SSH key,
# và clouds.yaml (cloud "cloudjudge") với mật khẩu OpenStack của chính người đó (đọc từ ~/secrets/pw-<openstack_user>).
#   sudo bash 05-add-user.sh <linux_user> <openstack_user> "<ssh public key hoặc rỗng>"
#   vd: sudo bash 05-add-user.sh trong trong "ssh-ed25519 AAAA... trong@laptop"
# Chạy lại được; chạy lại với key mới sẽ THÊM key (không xóa key cũ).
set -euo pipefail
LU=${1:?linux_user}; OU=${2:?openstack_user}; KEY=${3:-}
AUTH_URL=http://10.10.0.10:5000
getent group cj >/dev/null || groupadd cj
id "$LU" >/dev/null 2>&1 || useradd -m -s /bin/bash -G cj,google-sudoers,docker "$LU" 2>/dev/null || useradd -m -s /bin/bash -G cj "$LU"
usermod -aG cj "$LU"
usermod -aG sudo "$LU"
echo "$LU ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-cj-$LU && chmod 440 /etc/sudoers.d/90-cj-$LU

H=$(getent passwd "$LU" | cut -d: -f6)
install -d -m 700 -o "$LU" -g "$LU" "$H/.ssh"
touch "$H/.ssh/authorized_keys"; chown "$LU:$LU" "$H/.ssh/authorized_keys"; chmod 600 "$H/.ssh/authorized_keys"
if [ -n "$KEY" ]; then
  grep -qF "$KEY" "$H/.ssh/authorized_keys" || echo "$KEY" >> "$H/.ssh/authorized_keys"
  echo "$LU: đã thêm SSH key"
else
  echo "$LU: CHƯA có SSH key (chạy lại với key để họ đăng nhập được)"
fi

# clouds.yaml của người đó (chỉ họ đọc được)
PWF=/home/cj/secrets/pw-$OU
if [ -r "$PWF" ]; then
  install -d -m 700 -o "$LU" -g "$LU" "$H/.config" "$H/.config/openstack"
  cat > "$H/.config/openstack/clouds.yaml" <<EOF
clouds:
  cloudjudge:
    auth:
      auth_url: $AUTH_URL
      username: $OU
      password: $(cat "$PWF")
      project_name: cloudjudge
      user_domain_name: Default
      project_domain_name: Default
    region_name: RegionOne
    interface: internal
    identity_api_version: 3
EOF
  chown "$LU:$LU" "$H/.config/openstack/clouds.yaml"; chmod 600 "$H/.config/openstack/clouds.yaml"
  echo "$LU: đã ghi ~/.config/openstack/clouds.yaml (cloud 'cloudjudge', user $OU)"
else
  echo "$LU: không đọc được $PWF, bỏ qua clouds.yaml"
fi
# thư mục secrets chung: group cj đọc được
chgrp cj /home/cj/secrets; chmod 750 /home/cj/secrets; chmod 750 /home/cj   # để group cj đi vào được ~/secrets
echo ADD_USER_DONE
