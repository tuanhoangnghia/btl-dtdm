#!/usr/bin/env bash
# Trên controller. Tạo/cập nhật stack cj-mon (chủ: C). Dùng cloud "cloudjudge" trong ~/.config/openstack/clouds.yaml.
#   bash heat/deploy-cj-mon.sh       # create hoặc update, rồi chờ máy monitor báo CJ_MON_READY
# Đọc: output cj-net; ~/secrets/infra.env (CJ_MONITOR_AC_*, SSH key); ~/secrets/data.env (SMTP_USER, SMTP_APP_PASSWORD, ALERT_EMAIL_TO);
#      ~/secrets/app-alarms.env (4 alarm_url, do heat/deploy-cj-app.sh của B ghi). Chưa có app-alarms.env thì dùng URL giả
#      (Alertmanager gọi không tới đâu, chỉ email chạy), có rồi thì chạy lại script này.
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
if p=$(find_secret app-alarms.env); then
  set -a; . "$p"; set +a; echo "đọc $p"
else
  echo "CẢNH BÁO: chưa có app-alarms.env (B chưa deploy cj-app), dùng alarm_url giả"
  for v in WEB_UP_URL WEB_DOWN_URL WORKER_UP_URL WORKER_DOWN_URL; do export "$v=http://127.0.0.1:9/chua-co-$v"; done
fi
export SMTP_APP_PASSWORD=${SMTP_APP_PASSWORD// /}   # Gmail hiển thị App Password theo 4 nhóm, bỏ khoảng trắng

missing=()
for v in CJ_MONITOR_AC_ID CJ_MONITOR_AC_SECRET SMTP_USER SMTP_APP_PASSWORD ALERT_EMAIL_TO \
         WEB_UP_URL WEB_DOWN_URL WORKER_UP_URL WORKER_DOWN_URL; do
  [ -n "${!v:-}" ] || missing+=("$v")
done
[ ${#missing[@]} -eq 0 ] || { echo "Thiếu biến: ${missing[*]} (SMTP_* và ALERT_EMAIL_TO: C điền vào data.env)"; exit 1; }

if [ -n "${ADMIN_SSH_PUBKEYS:-}" ]; then KEYS_B64=$(printf '%s\n' "$ADMIN_SSH_PUBKEYS" | base64 -w0)
elif KF=$(find_secret admin_ssh_pubkeys.txt); then KEYS_B64=$(base64 -w0 < "$KF")
else echo "Thiếu SSH key quản trị (ADMIN_SSH_PUBKEYS hoặc admin_ssh_pubkeys.txt)"; exit 1; fi

out() { openstack stack output show "$1" "$2" -f value -c output_value; }
export NET_APP=$(out cj-net net_app_id) SUBNET_APP=$(out cj-net subnet_app_id) SG_MONITOR=$(out cj-net sg_monitor_id) KEYS_B64

PARAMS=$(mktemp); chmod 600 "$PARAMS"; trap 'rm -f "$PARAMS"' EXIT
python3 - "$PARAMS" <<'EOF'
import json, os, sys
e = os.environ
p = {
    "image": e.get("CJ_IMAGE", "cj-base-v1"),
    "net_app": e["NET_APP"], "subnet_app": e["SUBNET_APP"], "sg_monitor": e["SG_MONITOR"],
    "admin_ssh_pubkeys_b64": e["KEYS_B64"],
    "mon_ac_id": e["CJ_MONITOR_AC_ID"], "mon_ac_secret": e["CJ_MONITOR_AC_SECRET"],
    "smtp_user": e["SMTP_USER"], "smtp_app_password": e["SMTP_APP_PASSWORD"], "alert_email_to": e["ALERT_EMAIL_TO"],
    "web_up_url": e["WEB_UP_URL"], "web_down_url": e["WEB_DOWN_URL"],
    "worker_up_url": e["WORKER_UP_URL"], "worker_down_url": e["WORKER_DOWN_URL"],
}
# đi vào mon.env (bash source, URL trong nháy đơn): cấm xuống dòng, nháy, $, \, backtick; khoảng trắng chỉ cấm ngoài URL
bad = [k for k, v in p.items() if isinstance(v, str) and any(c in v for c in "\n\r\"'\\$` ")]
if bad:
    sys.exit(f"Giá trị có ký tự không dùng được: {bad}")
with open(sys.argv[1], "w") as f:
    json.dump({"parameters": p}, f)
EOF

ACTION=create; openstack stack show cj-mon >/dev/null 2>&1 && ACTION=update
echo "openstack stack $ACTION cj-mon"
openstack stack $ACTION cj-mon -t cj-mon.yaml -e "$PARAMS" --wait

echo "chờ cloud-init của cj-monitor (tối đa 10 phút)..."
deadline=$(( $(date +%s) + 600 ))
while :; do
  log=$(openstack console log show --lines 500 cj-monitor 2>/dev/null || true)
  if grep -q "CJ_MON_FAILED" <<<"$log"; then grep "CJ_MON_FAILED" <<<"$log"; echo "lỗi, xem: openstack console log show cj-monitor"; exit 1; fi
  grep -q "CJ_MON_READY" <<<"$log" && break
  [ "$(date +%s)" -lt "$deadline" ] || { echo "quá 10 phút chưa xong, xem: openstack console log show cj-monitor"; exit 1; }
  sleep 10
done
echo "cj-monitor sẵn sàng: Prometheus http://10.0.2.11:9090 · Alertmanager :9093 · Grafana :3000 (qua bastion/Tailscale)"
echo "Mật khẩu admin Grafana: ssh vào cj-monitor rồi: sudo cat /etc/cj-mon/grafana/admin.pw"
