#!/usr/bin/env bash
# Trên controller. Tạo/cập nhật stack cj-app (chủ: B). Dùng cloud "cloudjudge" trong ~/.config/openstack/clouds.yaml.
#   bash heat/deploy-cj-app.sh [release_version]      # mặc định 0.1.0; create hoặc update tùy stack đã có chưa
# Đọc: output stack cj-net (bắt buộc) và cj-data (nếu có), 3 file secret infra.env / app.env / data.env
# (tìm trong $SECRETS_DIR, ~/secrets, /home/cj/secrets). Secret truyền qua file tham số tạm (quyền 600),
# không nằm trên dòng lệnh. 4 alarm_url ghi vào <thư mục secret>/app-alarms.env cho C (Alertmanager).
set -euo pipefail
cd "$(dirname "$0")"
VER=${1:-0.1.0}
command -v openstack >/dev/null 2>&1 || source /home/cj/kolla-venv/bin/activate
export OS_CLOUD=${OS_CLOUD:-cloudjudge}

find_secret() {
  for d in ${SECRETS_DIR:-} "$HOME/secrets" /home/cj/secrets; do
    [ -r "$d/$1" ] && { echo "$d/$1"; return 0; }
  done
  return 1
}
for f in infra.env app.env data.env; do
  p=$(find_secret "$f") || { echo "Không đọc được $f (đã ở group cj chưa?)"; exit 1; }
  set -a; . "$p"; set +a
  echo "đọc $p"
done
APP_ENV=$(find_secret app.env); SECRETS_OUT=$(dirname "$APP_ENV")

missing=()
for v in CJ_WEB_AC_ID CJ_WEB_AC_SECRET CJ_WORKER_AC_ID CJ_WORKER_AC_SECRET SECRET_KEY DB_PASSWORD DB_RO_PASSWORD MQ_PASSWORD; do
  [ -n "${!v:-}" ] || missing+=("$v")
done
[ ${#missing[@]} -eq 0 ] || { echo "Thiếu biến: ${missing[*]}"; exit 1; }

# SSH key quản trị: ADMIN_SSH_PUBKEYS (infra.env) hoặc file admin_ssh_pubkeys.txt cạnh infra.env
if [ -n "${ADMIN_SSH_PUBKEYS:-}" ]; then KEYS_B64=$(printf '%s\n' "$ADMIN_SSH_PUBKEYS" | base64 -w0)
elif KF=$(find_secret admin_ssh_pubkeys.txt); then KEYS_B64=$(base64 -w0 < "$KF")
else echo "Thiếu SSH key quản trị (ADMIN_SSH_PUBKEYS hoặc admin_ssh_pubkeys.txt)"; exit 1; fi

out() { openstack stack output show "$1" "$2" -f value -c output_value; }
PUBLIC_SUBNET=$(out cj-net subnet_public_id); APP_NET=$(out cj-net net_app_id)
SG_WEB=$(out cj-net sg_web_id); SG_WORKER=$(out cj-net sg_worker_id)
DB_PRIMARY=10.0.3.10; DB_REPLICA=10.0.3.11; MQ=10.0.2.10
if openstack stack show cj-data >/dev/null 2>&1; then
  DB_PRIMARY=$(out cj-data db_primary_ip); DB_REPLICA=$(out cj-data db_replica_ip); MQ=$(out cj-data mq_ip)
else
  echo "CẢNH BÁO: chưa có stack cj-data, dùng IP mặc định trong CONTRACT (web sẽ báo 503 tới khi có DB)"
fi

openstack object show releases "cloudjudge-$VER.tar.gz" >/dev/null 2>&1 \
  || { echo "Chưa có releases/cloudjudge-$VER.tar.gz trên Swift. Chạy: bash scripts/release.sh $VER"; exit 1; }
openstack image show "${CJ_IMAGE:-cj-base-v1}" >/dev/null 2>&1 \
  || { echo "Chưa có image ${CJ_IMAGE:-cj-base-v1}. Chạy: bash image/build-image.sh"; exit 1; }

PARAMS=$(mktemp); chmod 600 "$PARAMS"; trap 'rm -f "$PARAMS"' EXIT
export VER PUBLIC_SUBNET APP_NET SG_WEB SG_WORKER DB_PRIMARY DB_REPLICA MQ KEYS_B64
python3 - "$PARAMS" <<'EOF'
import json, os, sys
e = os.environ
p = {
    "image": e.get("CJ_IMAGE", "cj-base-v1"),
    "release_version": e["VER"],
    "public_subnet": e["PUBLIC_SUBNET"], "app_net": e["APP_NET"],
    "sg_web": e["SG_WEB"], "sg_worker": e["SG_WORKER"],
    "db_primary_host": e["DB_PRIMARY"], "db_replica_host": e["DB_REPLICA"], "mq_host": e["MQ"],
    "admin_ssh_pubkeys_b64": e["KEYS_B64"],
    "db_password": e["DB_PASSWORD"], "db_ro_password": e["DB_RO_PASSWORD"], "mq_password": e["MQ_PASSWORD"],
    "secret_key": e["SECRET_KEY"],
    "web_ac_id": e["CJ_WEB_AC_ID"], "web_ac_secret": e["CJ_WEB_AC_SECRET"],
    "worker_ac_id": e["CJ_WORKER_AC_ID"], "worker_ac_secret": e["CJ_WORKER_AC_SECRET"],
}
for k in ("WEB_AZ1_MIN", "WEB_AZ1_MAX", "WORKER_MIN", "WORKER_MAX"):
    if e.get(k):
        p[k.lower()] = int(e[k])
bad = [k for k, v in p.items() if isinstance(v, str) and any(c in v for c in "\n\r \"'\\$`")]
if bad:
    sys.exit(f"Giá trị có ký tự không dùng được trong file env (khoảng trắng, nháy, $, \\): {bad}")
with open(sys.argv[1], "w") as f:
    json.dump({"parameters": p}, f)   # JSON cũng là YAML hợp lệ
EOF

ACTION=create; openstack stack show cj-app >/dev/null 2>&1 && ACTION=update
echo "openstack stack $ACTION cj-app (release $VER)"
openstack stack $ACTION cj-app -t cj-app.yaml -e env/cj-app.env.yaml -e "$PARAMS" --wait

openstack stack output show cj-app --all -f json | python3 -c '
import sys, json
d = json.load(sys.stdin)
items = d if isinstance(d, list) else [dict(output_key=k, output_value=(v["output_value"] if isinstance(v, dict) else v)) for k, v in d.items()]
for o in sorted(items, key=lambda o: o["output_key"]):
    v = o["output_value"]
    print("%-16s %s" % (o["output_key"], "(bí mật, xem app-alarms.env)" if o["output_key"].endswith("_url") else v))'

ALARMS="$SECRETS_OUT/app-alarms.env"
umask 027
{
  echo "# Sinh bởi heat/deploy-cj-app.sh $(date -u +%FT%TZ). alarm_url của ScalingPolicy, dùng trong Alertmanager (C)."
  echo "# Giá trị trong nháy đơn vì URL có ký tự & (source file này bằng bash: set -a; . app-alarms.env; set +a)"
  echo "WEB_UP_URL='$(out cj-app web_up_url)'"
  echo "WEB_DOWN_URL='$(out cj-app web_down_url)'"
  echo "WORKER_UP_URL='$(out cj-app worker_up_url)'"
  echo "WORKER_DOWN_URL='$(out cj-app worker_down_url)'"
} > "$ALARMS"
chgrp cj "$ALARMS" 2>/dev/null || true; chmod 640 "$ALARMS"
echo "đã ghi 4 alarm_url vào $ALARMS"
echo "Việc tiếp: báo A lb_fip=$(out cj-app lb_fip) (DNAT cổng 80), báo C file $ALARMS"
