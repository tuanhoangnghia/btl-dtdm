#!/usr/bin/env bash
# Trên controller. Tạo/cập nhật stack cj-data (chủ: C). Dùng cloud "cloudjudge" trong ~/.config/openstack/clouds.yaml.
#   bash heat/deploy-cj-data.sh          # create hoặc update tùy stack đã có chưa, rồi chờ 3 máy báo CJ_DATA_READY
# Đọc: output stack cj-net, ~/secrets/infra.env (CJ_BACKUP_AC_*, SSH key quản trị) và ~/secrets/data.env (mật khẩu do A sinh,
# KHÔNG sinh lại: MySQL/RabbitMQ khởi tạo bằng đúng các giá trị này, B cũng dùng chúng trong cj-app).
# Secret truyền qua file tham số tạm (quyền 600), không nằm trên dòng lệnh.
set -euo pipefail
cd "$(dirname "$0")"
command -v openstack >/dev/null 2>&1 || source /home/cj/kolla-venv/bin/activate
export OS_CLOUD=${OS_CLOUD:-cloudjudge}

find_secret() {
  for d in ${SECRETS_DIR:-} "$HOME/secrets" /home/cj/secrets; do
    [ -r "$d/$1" ] && { echo "$d/$1"; return 0; }
  done
  return 1
}
for f in infra.env data.env; do
  p=$(find_secret "$f") || { echo "Không đọc được $f (đã ở group cj chưa?)"; exit 1; }
  set -a; . "$p"; set +a
  echo "đọc $p"
done

missing=()
for v in MYSQL_ROOT_PASSWORD DB_PASSWORD DB_RO_PASSWORD REPL_PASSWORD EXPORTER_PASSWORD BACKUP_DB_PASSWORD MQ_PASSWORD \
         CJ_BACKUP_AC_ID CJ_BACKUP_AC_SECRET; do
  [ -n "${!v:-}" ] || missing+=("$v")
done
[ ${#missing[@]} -eq 0 ] || { echo "Thiếu biến: ${missing[*]}"; exit 1; }

if [ -n "${ADMIN_SSH_PUBKEYS:-}" ]; then KEYS_B64=$(printf '%s\n' "$ADMIN_SSH_PUBKEYS" | base64 -w0)
elif KF=$(find_secret admin_ssh_pubkeys.txt); then KEYS_B64=$(base64 -w0 < "$KF")
else echo "Thiếu SSH key quản trị (ADMIN_SSH_PUBKEYS hoặc admin_ssh_pubkeys.txt)"; exit 1; fi

out() { openstack stack output show "$1" "$2" -f value -c output_value; }
export NET_DATA=$(out cj-net net_data_id) SUBNET_DATA=$(out cj-net subnet_data_id)
export NET_APP=$(out cj-net net_app_id) SUBNET_APP=$(out cj-net subnet_app_id)
export SG_DB=$(out cj-net sg_db_id) SG_MQ=$(out cj-net sg_mq_id) KEYS_B64
openstack image show "${CJ_IMAGE:-cj-base-v1}" >/dev/null 2>&1 \
  || { echo "Chưa có image ${CJ_IMAGE:-cj-base-v1} (B build bằng image/build-image.sh)"; exit 1; }

PARAMS=$(mktemp); chmod 600 "$PARAMS"; trap 'rm -f "$PARAMS"' EXIT
python3 - "$PARAMS" <<'EOF'
import json, os, sys
e = os.environ
p = {
    "image": e.get("CJ_IMAGE", "cj-base-v1"),
    "net_data": e["NET_DATA"], "subnet_data": e["SUBNET_DATA"], "net_app": e["NET_APP"], "subnet_app": e["SUBNET_APP"],
    "sg_db": e["SG_DB"], "sg_mq": e["SG_MQ"],
    "admin_ssh_pubkeys_b64": e["KEYS_B64"],
    "mysql_root_password": e["MYSQL_ROOT_PASSWORD"], "db_password": e["DB_PASSWORD"], "db_ro_password": e["DB_RO_PASSWORD"],
    "repl_password": e["REPL_PASSWORD"], "exporter_password": e["EXPORTER_PASSWORD"],
    "backup_db_password": e["BACKUP_DB_PASSWORD"], "mq_password": e["MQ_PASSWORD"],
    "backup_ac_id": e["CJ_BACKUP_AC_ID"], "backup_ac_secret": e["CJ_BACKUP_AC_SECRET"],
}
if e.get("MQ_AZ"):
    p["mq_az"] = e["MQ_AZ"]
# Giá trị đi vào file env trong VM (dạng KEY=value, bash source): không được có khoảng trắng, nháy, $, \
bad = [k for k, v in p.items() if isinstance(v, str) and any(c in v for c in "\n\r \"'\\$`")]
if bad:
    sys.exit(f"Giá trị có ký tự không dùng được: {bad}")
with open(sys.argv[1], "w") as f:
    json.dump({"parameters": p}, f)   # JSON cũng là YAML hợp lệ
EOF

ACTION=create; openstack stack show cj-data >/dev/null 2>&1 && ACTION=update
echo "openstack stack $ACTION cj-data"
openstack stack $ACTION cj-data -t cj-data.yaml -e "$PARAMS" --wait

# Stack COMPLETE chỉ nghĩa là máy ACTIVE và volume đã gắn; cloud-init (MySQL, replication, RabbitMQ) còn chạy thêm vài phút
echo "chờ cloud-init của 3 máy (tối đa 15 phút)..."
deadline=$(( $(date +%s) + 900 ))
for s in cj-mysql-primary cj-rabbitmq cj-mysql-replica; do
  while :; do
    log=$(openstack console log show --lines 500 "$s" 2>/dev/null || true)
    if grep -q "CJ_DATA_FAILED" <<<"$log"; then grep "CJ_DATA_FAILED" <<<"$log"; echo "$s lỗi, xem: openstack console log show $s"; exit 1; fi
    grep -q "CJ_DATA_READY" <<<"$log" && { echo "  $s sẵn sàng"; break; }
    # Máy cũ đã khởi động lại (bật/tắt cụm): user_data chỉ chạy ở lần boot đầu nên log mới không có READY
    grep -qE "Cloud-init v\. .* finished at" <<<"$log" && { echo "  $s đã khởi tạo từ trước (boot lại), bỏ qua"; break; }
    [ "$(date +%s)" -lt "$deadline" ] || { echo "$s quá 15 phút chưa xong, xem: openstack console log show $s"; exit 1; }
    sleep 10
  done
done

openstack stack output show cj-data --all -f json | python3 -c '
import sys, json
d = json.load(sys.stdin)
items = d if isinstance(d, list) else [dict(output_key=k, output_value=(v["output_value"] if isinstance(v, dict) else v)) for k, v in d.items()]
for o in sorted(items, key=lambda o: o["output_key"]):
    print("%-14s %s" % (o["output_key"], o["output_value"]))'
echo "Việc tiếp: báo B \"cj-data xong\" (B chạy lại heat/deploy-cj-app.sh nếu web đang 503)."
