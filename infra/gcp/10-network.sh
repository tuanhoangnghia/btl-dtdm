#!/usr/bin/env bash
# Tạo VPC, subnet, firewall, IP tĩnh cho controller. Chạy lại nhiều lần được (bỏ qua cái đã có).
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"

exists() { "$@" >/dev/null 2>&1; }

exists gcloud compute networks describe "$VPC" \
  || gcloud compute networks create "$VPC" --subnet-mode=custom --mtu=1500

exists gcloud compute networks subnets describe "$SUBNET" --region="$REGION" \
  || gcloud compute networks subnets create "$SUBNET" --network="$VPC" --region="$REGION" --range="$SUBNET_RANGE"

MY_IP=$(curl -s -4 --max-time 8 https://ifconfig.me)
[ -n "$MY_IP" ] || { echo "Không lấy được IP public của máy"; exit 1; }

exists gcloud compute firewall-rules describe cj-allow-internal \
  || gcloud compute firewall-rules create cj-allow-internal --network="$VPC" \
       --allow=tcp,udp,icmp --source-ranges="$SUBNET_RANGE"

if exists gcloud compute firewall-rules describe cj-allow-ssh-admin; then
  gcloud compute firewall-rules update cj-allow-ssh-admin --source-ranges="${MY_IP}/32"
else
  gcloud compute firewall-rules create cj-allow-ssh-admin --network="$VPC" \
    --allow=tcp:22 --source-ranges="${MY_IP}/32" --target-tags=os-controller
fi

exists gcloud compute firewall-rules describe cj-allow-http \
  || gcloud compute firewall-rules create cj-allow-http --network="$VPC" \
       --allow=tcp:80 --source-ranges=0.0.0.0/0 --target-tags=os-controller

exists gcloud compute firewall-rules describe cj-allow-tailscale \
  || gcloud compute firewall-rules create cj-allow-tailscale --network="$VPC" \
       --allow=udp:41641 --source-ranges=0.0.0.0/0 --target-tags=os-controller

exists gcloud compute addresses describe "$CTL_ADDR_NAME" --region="$REGION" \
  || gcloud compute addresses create "$CTL_ADDR_NAME" --region="$REGION"

echo "CTL_IP=$(gcloud compute addresses describe "$CTL_ADDR_NAME" --region="$REGION" --format='value(address)')"
