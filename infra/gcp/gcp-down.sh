#!/usr/bin/env bash
# Tắt cụm khi hết buổi làm (tiết kiệm tín dụng).
# Từ chối tắt nếu người KHÁC đang giữ khóa (xem cj-lock.sh). Đặt CJ_ME=A|B|C để khóa của chính mình không chặn mình.
# Tắt cưỡng bức (chỉ khi đã hỏi nhóm): FORCE=1 bash infra/gcp/gcp-down.sh
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"

if [ "${FORCE:-0}" != "1" ]; then
  "$(dirname "$0")/cj-lock.sh" check || { echo "Không tắt. Nhắn người đang dùng, hoặc FORCE=1 nếu thực sự cần."; exit 1; }
fi
gcloud compute instances stop os-controller os-compute-1 --zone="$ZONE_A"
gcloud compute instances stop os-compute-2 --zone="$ZONE_B"
