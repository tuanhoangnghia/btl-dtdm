#!/usr/bin/env bash
# Chụp snapshot 5 đĩa của cụm (nên TẮT cụm trước để nhất quán). Dùng: bash infra/gcp/snapshot.sh <nhãn mốc>   vd: m2-20261029
# Chỉ giữ 2 bộ gần nhất (xóa bộ cũ bằng tay SAU KHI hỏi nhóm: gcloud compute snapshots delete ...).
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"
L=${1:?cần nhãn mốc, vd m2-20261029}
gcloud compute disks snapshot os-controller os-controller-cinder os-controller-swift os-compute-1 \
  --zone="$ZONE_A" --storage-location="$REGION" --snapshot-names="ctl-boot-$L,ctl-cinder-$L,ctl-swift-$L,c1-boot-$L"
gcloud compute disks snapshot os-compute-2 --zone="$ZONE_B" --storage-location="$REGION" --snapshot-names="c2-boot-$L"
gcloud compute snapshots list --filter="name~-$L\$" --format="table(name,diskSizeGb,storageBytes.size(),status)"
