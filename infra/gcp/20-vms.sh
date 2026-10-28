#!/usr/bin/env bash
# Tạo 3 máy GCE (bật nested virtualization). Chạy 10-network.sh trước.
# Quota SSD vùng asia-southeast1 chỉ 250 GB: SSD = ctl 100 + cinder 50 + 2 compute x 48 = 246. Đĩa Swift dùng pd-standard.
# Tạo máy là hành động tốn tiền (~0,66 USD/giờ khi chạy): chạy có chủ đích.
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"

CTL_IP=$(gcloud compute addresses describe "$CTL_ADDR_NAME" --region="$REGION" --format='value(address)')
COMMON=(--image-family=ubuntu-2404-lts-amd64 --image-project=ubuntu-os-cloud
        --boot-disk-type=pd-balanced --enable-nested-virtualization
        --metadata=enable-oslogin=FALSE)

exists() { "$@" >/dev/null 2>&1; }

exists gcloud compute instances describe os-controller --zone="$ZONE_A" || \
gcloud compute instances create os-controller --zone="$ZONE_A" --machine-type=n2-highmem-4 "${COMMON[@]}" \
  --boot-disk-size=100GB \
  --network-interface="subnet=$SUBNET,private-network-ip=$CTL_PRIVATE_IP,address=$CTL_IP" \
  --create-disk=name=os-controller-cinder,size=50GB,type=pd-balanced,device-name=cinder,auto-delete=yes \
  --create-disk=name=os-controller-swift,size=30GB,type=pd-standard,device-name=swift,auto-delete=yes \
  --tags=os-controller

exists gcloud compute instances describe os-compute-1 --zone="$ZONE_A" || \
gcloud compute instances create os-compute-1 --zone="$ZONE_A" --machine-type=n2-highmem-2 "${COMMON[@]}" \
  --boot-disk-size=48GB \
  --network-interface="subnet=$SUBNET,private-network-ip=$C1_PRIVATE_IP" --tags=os-compute

exists gcloud compute instances describe os-compute-2 --zone="$ZONE_B" || \
gcloud compute instances create os-compute-2 --zone="$ZONE_B" --machine-type=n2-highmem-2 "${COMMON[@]}" \
  --boot-disk-size=48GB \
  --network-interface="subnet=$SUBNET,private-network-ip=$C2_PRIVATE_IP" --tags=os-compute

gcloud compute instances list --filter="name~^os-" \
  --format="table(name,zone.basename(),machineType.basename(),status,networkInterfaces[0].networkIP,networkInterfaces[0].accessConfigs[0].natIP)"
