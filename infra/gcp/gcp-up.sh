#!/usr/bin/env bash
# Bật cụm: controller trước, rồi 2 compute. Sau đó chờ ~5 phút để dịch vụ Kolla lên.
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"
gcloud compute instances start os-controller --zone="$ZONE_A"
gcloud compute instances start os-compute-1 --zone="$ZONE_A"
gcloud compute instances start os-compute-2 --zone="$ZONE_B"
"$(dirname "$0")/update-ssh-ip.sh"
