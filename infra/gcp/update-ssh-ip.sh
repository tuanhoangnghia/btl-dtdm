#!/usr/bin/env bash
# Cập nhật firewall SSH theo IP public hiện tại của máy (IP nhà/quán cà phê thay đổi).
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"
MY_IP=$(curl -s -4 --max-time 8 https://ifconfig.me)
[ -n "$MY_IP" ] || { echo "Không lấy được IP public"; exit 1; }
gcloud compute firewall-rules update cj-allow-ssh-admin --source-ranges="${MY_IP}/32"
echo "SSH cho phép từ ${MY_IP}/32"
