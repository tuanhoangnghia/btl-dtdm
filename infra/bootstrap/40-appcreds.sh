#!/usr/bin/env bash
# Trên controller. Tạo application credential cho 4 user cj-* (đăng nhập bằng CHÍNH user đó) -> ~/secrets/infra.env.
# Secret chỉ hiện 1 lần lúc tạo, nên chỉ tạo nếu chưa có trong infra.env (muốn tạo lại: xóa dòng *_AC_* của user đó và credential cũ).
set -euo pipefail
source ~/kolla-venv/bin/activate
source /etc/kolla/admin-openrc.sh
AUTH_URL=$OS_AUTH_URL
ENVF=$HOME/secrets/infra.env
touch "$ENVF"; chmod 640 "$ENVF"; getent group cj >/dev/null && chgrp cj "$ENVF" || true

as_user() {  # as_user <user> <lệnh openstack...>: chạy với danh tính của user, scope project cloudjudge
  local u=$1; shift
  ( unset $(env | grep -o '^OS_[A-Z_]*')
    openstack --os-auth-type password --os-auth-url "$AUTH_URL" --os-username "$u" --os-password "$(cat ~/secrets/pw-$u)" \
      --os-project-name cloudjudge --os-user-domain-name Default --os-project-domain-name Default --os-identity-api-version 3 "$@" )
}

# dọn các dòng rỗng do lần chạy lỗi trước
sed -i '/_AC_\(ID\|SECRET\)=$/d' "$ENVF"

field() {  # field <tên> : đọc JSON từ stdin, tên khóa không phân biệt hoa thường; lỗi nếu rỗng
  python3 -c 'import sys,json; d={k.lower():v for k,v in json.load(sys.stdin).items()}; v=d.get(sys.argv[1]); assert v, "thiếu "+sys.argv[1]; print(v)' "$1"
}

for u in cj-web cj-worker cj-monitor cj-backup; do
  V=$(echo "${u^^}" | tr - _)
  if grep -q "^${V}_AC_ID=." "$ENVF"; then echo "$u: đã có trong infra.env, bỏ qua"; continue; fi
  as_user $u application credential delete ${u}-ac >/dev/null 2>&1 || true
  OUT=$(as_user $u application credential create ${u}-ac -f json)
  ID=$(echo "$OUT" | field id); SECRET=$(echo "$OUT" | field secret)
  { echo "${V}_AC_ID=$ID"; echo "${V}_AC_SECRET=$SECRET"; } >> "$ENVF"
  echo "$u: đã tạo application credential"
done
echo "-- biến có trong infra.env (không in giá trị):"; cut -d= -f1 "$ENVF" | sort | tr '\n' ' '; echo
echo APPCREDS_DONE
