#!/usr/bin/env bash
# Sinh ~/multinode từ mẫu inventory của CHÍNH phiên bản kolla-ansible đang cài (tránh lệch nhóm giữa các bản).
# Chỉ thay phần đầu (control/network/compute/monitoring/storage/deployment), giữ nguyên các nhóm :children.
set -euo pipefail
source ~/kolla-venv/bin/activate
python3 - <<'PY'
import os
src=os.path.expanduser("~/kolla-venv/share/kolla-ansible/ansible/inventory/multinode")
lines=open(src).read().split("\n")
i=next(n for n,l in enumerate(lines) if l.startswith("[baremetal:children]"))
head="""[control]
os-controller ansible_host=10.10.0.10 ansible_user=cj ansible_become=true

[network]
os-controller

[compute]
os-compute-1 ansible_host=10.10.0.11 ansible_user=cj ansible_become=true
os-compute-2 ansible_host=10.10.0.12 ansible_user=cj ansible_become=true

[monitoring]
os-controller

[storage]
os-controller

[deployment]
localhost ansible_connection=local
"""
open(os.path.expanduser("~/multinode"),"w").write(head+"\n"+"\n".join(lines[i:]))
print("multinode generated from", src)
PY
