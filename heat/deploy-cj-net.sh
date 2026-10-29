#!/usr/bin/env bash
# Trên controller. Tạo/cập nhật stack cj-net (chủ: A). Dùng cloud "cloudjudge" trong ~/.config/openstack/clouds.yaml.
#   bash heat/deploy-cj-net.sh            # create hoặc update tùy stack đã có chưa
# Cần: ~/secrets/admin_ssh_pubkeys.txt (mỗi dòng 1 SSH public key quản trị); tùy chọn TS_BASTION_KEY trong ~/secrets/infra.env.
set -euo pipefail
cd "$(dirname "$0")"
source ~/kolla-venv/bin/activate
export OS_CLOUD=cloudjudge
[ -f ~/secrets/infra.env ] && { set -a; source ~/secrets/infra.env; set +a; }
KEYS=~/secrets/admin_ssh_pubkeys.txt
[ -s "$KEYS" ] || { echo "Thiếu $KEYS"; exit 1; }
KEYS_B64=$(base64 -w0 < "$KEYS")

ACTION=create; openstack stack show cj-net >/dev/null 2>&1 && ACTION=update
openstack stack $ACTION cj-net -t cj-net.yaml --wait \
  --parameter "admin_ssh_pubkeys_b64=$KEYS_B64" \
  --parameter "ts_authkey=${TS_BASTION_KEY:-}"
openstack stack output show cj-net --all -f json | python3 -c '
import sys,json
d=json.load(sys.stdin)
items=d if isinstance(d,list) else [dict(output_key=k,output_value=(v["output_value"] if isinstance(v,dict) else v)) for k,v in d.items()]
for o in sorted(items,key=lambda o:o["output_key"]): print("%-18s %s"%(o["output_key"],o["output_value"]))'
