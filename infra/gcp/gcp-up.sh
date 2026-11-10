#!/usr/bin/env bash
# Bật cụm: controller trước, rồi 2 compute. Sau đó chờ ~5 phút để dịch vụ Kolla lên.
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"
gcloud compute instances start os-controller --zone="$ZONE_A"
gcloud compute instances start os-compute-1 --zone="$ZONE_A"
gcloud compute instances start os-compute-2 --zone="$ZONE_B"
"$(dirname "$0")/update-ssh-ip.sh"
echo "Cụm đang khởi động (~5 phút). Sau đó kiểm LB: ssh cj-ctl 'openstack loadbalancer show cj-lb -c provisioning_status'; nếu ERROR chạy bash ~/cloudjudge/infra/bootstrap/lb-recover.sh (hoặc đợi cj-post-boot.service tự làm, ~8 phút)."
