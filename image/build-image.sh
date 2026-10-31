#!/usr/bin/env bash
# Trên controller. Build golden image cj-base-v1 (KE_HOACH mục 9), không cần SSH vào builder:
#   bash image/build-image.sh [tên-image]        # mặc định cj-base-v1
# Các bước: ghép user-data (nhúng image/sandbox/*) → tạo VM cj-builder trong net-public (stack cj-net)
# → chờ VM tự tắt (SHUTOFF, ~10–20 phút) → snapshot thành image → xóa builder.
# Image đã tồn tại thì dừng, trừ khi FORCE=1 (khi đó image cũ được đổi tên thành <tên>-old-<thời gian>).
set -euo pipefail
cd "$(dirname "$0")"
NAME=${1:-cj-base-v1}
BUILDER=cj-builder
command -v openstack >/dev/null 2>&1 || source /home/cj/kolla-venv/bin/activate
export OS_CLOUD=${OS_CLOUD:-cloudjudge}

if openstack image show "$NAME" >/dev/null 2>&1; then
  [ "${FORCE:-0}" = 1 ] || { echo "Image $NAME đã có. Dùng FORCE=1 để build lại."; exit 1; }
  OLD="$NAME-old-$(date +%Y%m%d%H%M)"; openstack image set --name "$OLD" "$NAME"; echo "đổi tên image cũ thành $OLD"
fi
if openstack server show "$BUILDER" >/dev/null 2>&1; then
  echo "Đang có VM $BUILDER (lần build trước?). Xóa trước: openstack server delete $BUILDER"; exit 1
fi

UD=$(mktemp); trap 'rm -f "$UD"' EXIT
sed -e "s|__SANDBOX_DOCKERFILE_B64__|$(base64 -w0 sandbox/Dockerfile)|" \
    -e "s|__SANDBOX_CJRUN_B64__|$(base64 -w0 sandbox/cj-run)|" build-cj-base.sh > "$UD"
grep -q '__SANDBOX_' "$UD" && { echo "ghép user-data lỗi"; exit 1; }

NET=$(openstack stack output show cj-net net_public_id -f value -c output_value)
echo "tạo $BUILDER (ubuntu-24.04, cj.medium, net-public $NET)"
openstack server create "$BUILDER" --image ubuntu-24.04 --flavor cj.medium --network "$NET" \
  --user-data "$UD" --wait -f value -c id

START=$(date +%s)
while :; do
  ST=$(openstack server show "$BUILDER" -f value -c status)
  LOG=$(openstack console log show --lines 40 "$BUILDER" 2>/dev/null || true)
  if grep -q CJ_BUILD_FAILED <<<"$LOG"; then
    echo "BUILD LỖI. 40 dòng cuối console:"; echo "$LOG"
    echo "VM $BUILDER được giữ lại để xem log: openstack console log show $BUILDER"; exit 1
  fi
  [ "$ST" = SHUTOFF ] && break
  [ "$ST" = ERROR ] && { openstack server show "$BUILDER" -c fault; exit 1; }
  if (( $(date +%s) - START > 2700 )); then echo "quá 45 phút chưa xong"; echo "$LOG"; exit 1; fi
  printf '\r%s  %ss  ' "$ST" $(( $(date +%s) - START )); sleep 20
done
echo; echo "builder SHUTOFF sau $(( $(date +%s) - START ))s"
openstack console log show "$BUILDER" | grep -q CJ_BUILD_OK || echo "CẢNH BÁO: không thấy CJ_BUILD_OK trong console log"

openstack server image create --name "$NAME" --wait "$BUILDER" -f value -c id
openstack image set --property cj_built_at="$(date -u +%FT%TZ)" --property os_distro=ubuntu --property os_version=24.04 "$NAME"
openstack server delete --wait "$BUILDER"
openstack image show "$NAME" -c name -c status -c size -c id
echo "XONG. Báo C: image $NAME sẵn sàng."
