#!/usr/bin/env bash
# Cài Kolla-Ansible 21.x (2025.2) trên controller, user cj. Chạy lại được (tạo lại venv + passwords).
# Lý do chọn 2025.2: image Kolla 2024.2 đã bị gỡ khỏi quay.io, 2025.1+ có image nhưng không còn role Swift.
set -euo pipefail
rm -rf ~/kolla-venv
python3 -m venv ~/kolla-venv
source ~/kolla-venv/bin/activate
pip install -q -U pip
pip install -q "ansible-core>=2.18,<2.19" "kolla-ansible==21.3.0"
sudo mkdir -p /etc/kolla && sudo chown cj:cj /etc/kolla
cp -f ~/kolla-venv/share/kolla-ansible/etc_examples/kolla/passwords.yml /etc/kolla/passwords.yml
kolla-genpwd
kolla-ansible install-deps
pip list 2>/dev/null | grep -iE "^(ansible-core|kolla-ansible) "
echo INSTALL_DONE
