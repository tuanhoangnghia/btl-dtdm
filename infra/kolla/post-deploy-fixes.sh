#!/usr/bin/env bash
# Chạy trên controller SAU kolla-ansible deploy (và có thể chạy lại). Sửa các lỗi "sau khi bật lại cụm".
#
# 1) octavia-interface.service chạy quá sớm sau reboot (OVS chưa tạo xong cổng o-hm0) -> lỗi 5 lần trong 1 giây
#    -> systemd bỏ cuộc ("Start request repeated too quickly") -> o-hm0 không có IP -> Octavia không nói chuyện được với amphora.
#    Drop-in này cho nó tự thử lại mỗi 10 giây, không giới hạn số lần. Drop-in sống sót qua kolla-ansible deploy
#    (deploy chỉ ghi đè file unit gốc).
set -euo pipefail
sudo install -d /etc/systemd/system/octavia-interface.service.d
sudo tee /etc/systemd/system/octavia-interface.service.d/10-retry.conf >/dev/null <<'EOT'
[Unit]
StartLimitIntervalSec=0

[Service]
Restart=on-failure
RestartSec=10
EOT
sudo systemctl daemon-reload
sudo systemctl reset-failed octavia-interface || true
sudo systemctl restart octavia-interface
sleep 3
ip -br a show o-hm0
systemctl is-active octavia-interface
