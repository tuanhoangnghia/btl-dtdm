#!/usr/bin/env bash
# Đóng gói và upload release lên Swift container `releases` (KE_HOACH 10.5, CONTRACT 8.1).
#   bash scripts/release.sh 0.1.0              # trên controller: đóng gói + upload
#   NO_UPLOAD=1 bash scripts/release.sh 0.1.0  # chỉ đóng gói ra dist/ (chạy được trên laptop)
# Tarball giải nén ở /opt/cj/app trên VM: cloudjudge/, deploy/ (install.sh, systemd, sandbox/), sample_problems/,
# requirements.txt, VERSION. Đổi code = tăng version → upload → bash heat/deploy-cj-app.sh <ver> (ASG thay máy).
# Version đã có trên Swift thì dừng (tránh 2 máy cùng version chạy code khác nhau), trừ khi FORCE=1.
set -euo pipefail
VER=${1:?usage: release.sh <version>  (vd 0.1.0)}
[[ "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9]+)?$ ]] || { echo "version không hợp lệ: $VER"; exit 2; }
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME="cloudjudge-$VER.tar.gz"
OUT_DIR=${OUT_DIR:-$ROOT/dist}
mkdir -p "$OUT_DIR"

STAGE=$(mktemp -d); trap 'rm -rf "$STAGE"' EXIT
cp -r "$ROOT/app/cloudjudge" "$ROOT/app/deploy" "$ROOT/app/sample_problems" "$ROOT/app/requirements.txt" "$STAGE/"
cp -r "$ROOT/image/sandbox" "$STAGE/deploy/sandbox"     # install.sh tự build cj-sandbox nếu image chưa có
echo "$VER" > "$STAGE/VERSION"
(cd "$ROOT" && git rev-parse --short HEAD 2>/dev/null || echo unknown) > "$STAGE/GIT_COMMIT"
find "$STAGE" -name __pycache__ -type d -prune -exec rm -rf {} +
find "$STAGE" -name '*.env' -delete
# mktemp -d tạo thư mục 700 và umask trên controller là 027: không sửa thì /opt/cj/app trên VM thuộc root 700,
# user dịch vụ cjsvc không đọc được code (cj-web/cj-worker không khởi động).
chmod -R u=rwX,go=rX "$STAGE"
chmod 755 "$STAGE/deploy/install.sh" "$STAGE/deploy/cj-cli" "$STAGE/deploy/sandbox/cj-run"
(cd "$OUT_DIR" && tar czf "$NAME" --owner=0 --group=0 -C "$STAGE" .)
echo "đã tạo $OUT_DIR/$NAME ($(du -h "$OUT_DIR/$NAME" | cut -f1), commit $(cat "$STAGE/GIT_COMMIT"))"

[ "${NO_UPLOAD:-0}" = 1 ] && exit 0
command -v openstack >/dev/null 2>&1 || source /home/cj/kolla-venv/bin/activate
export OS_CLOUD=${OS_CLOUD:-cloudjudge}
if openstack object show releases "$NAME" >/dev/null 2>&1 && [ "${FORCE:-0}" != 1 ]; then
  echo "releases/$NAME đã có trên Swift. Tăng version, hoặc FORCE=1 để ghi đè."; exit 1
fi
(cd "$OUT_DIR" && openstack object create releases "$NAME" -f value -c object)
openstack object show releases "$NAME" -c object -c content-length -c etag
echo "đã upload releases/$NAME"
