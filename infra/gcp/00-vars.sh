#!/usr/bin/env bash
# Biến dùng chung cho các script GCP của CloudJudge. Dùng: source infra/gcp/00-vars.sh
# Dùng cấu hình gcloud riêng "cloudjudge" để không đụng project/tài khoản mặc định của máy.
export CLOUDSDK_ACTIVE_CONFIG_NAME=cloudjudge
export PROJECT_ID="omega-dahlia-468315-f6"
export REGION="asia-southeast1"
export ZONE_A="asia-southeast1-a"
export ZONE_B="asia-southeast1-b"
export VPC="cj-vpc"
export SUBNET="cj-subnet"
export SUBNET_RANGE="10.10.0.0/24"
export CTL_PRIVATE_IP="10.10.0.10"
export C1_PRIVATE_IP="10.10.0.11"
export C2_PRIVATE_IP="10.10.0.12"
export CTL_ADDR_NAME="cj-ctl-ip"
export SSH_KEYS_FILE="$HOME/.ssh/cj-ssh-keys.txt"
