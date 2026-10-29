#!/usr/bin/env bash
# MINH CHỨNG hạng mục 1, 2, 5 (phần A). Chạy trên controller với user có clouds.yaml (cloud "cloudjudge").
#   bash scripts/demo-checks.sh [thư_mục_repo]  -> in ra màn hình; tee vào docs/evidence/A-demo-checks.txt để làm minh chứng
# Không in secret. Các lệnh dùng trong demo 10 phút (kịch bản: 0:00-1:00 và 2:45-4:00).
set -uo pipefail
REPO=${1:-$HOME/cloudjudge}
source ~/kolla-venv/bin/activate
export OS_CLOUD=cloudjudge
h() { printf '\n######## %s\n' "$*"; }

h "HM1 - Mạng riêng: 3 network, 1 router (SNAT), subnet công khai/riêng tư"
openstack network list -c Name -c Subnets -f table
openstack subnet list -c Name -c Subnet -f table
openstack router show cj-router -c name -c external_gateway_info -c status -f yaml 2>&1 | sed -E 's/network_id: .*/network_id: <ext-net>/'
h "HM1 - Hai Availability Zone: máy ảo nằm ở cả az1 và az2"
openstack availability zone list --compute -f table
openstack server list --long -c Name -c Status -c "Availability Zone" -c Networks -f table

h "HM2 - Chỉ net-public có floating IP; web/worker/mysql/rabbitmq KHÔNG có"
openstack floating ip list -c "Floating IP Address" -c "Fixed IP Address" -c Port -f table
h "HM2 - Security group: web chỉ nhận 8000 từ dải amphora (10.0.1.0/24); DB chỉ nhận từ web/worker/replica"
sg_rules() {  # in rule ingress của 1 SG, tham chiếu SG khác bằng TÊN (không phải ID)
  python3 - "$1" <<'PY'
import json,subprocess,sys
def osc(*a): return json.loads(subprocess.check_output(["openstack",*a,"-f","json"]))
names={g["ID"]:g["Name"] for g in osc("security","group","list")}
print("--- %s (ingress)"%sys.argv[1])
for r in osc("security","group","rule","list",sys.argv[1],"--ingress"):
    port=r.get("Port Range") or "all"
    src=names.get(r.get("Remote Security Group")) or r.get("IP Range") or "any"
    print("  %-5s %-12s <- %s"%(r["IP Protocol"],port,src))
PY
}
for sg in sg-bastion sg-web sg-worker sg-db sg-mq sg-monitor; do sg_rules $sg; done
h "HM2 - Từ máy chấm (net-app) gọi thẳng web:8000 phải BỊ CHẶN (timeout); qua LB thì được"
echo "Chạy tay khi đã có stack cj-app (qua bastion):"
echo '  ssh -J cj@<bastion> ubuntu@<ip-worker> "curl -m 5 http://<ip-web>:8000/healthz"   # mong đợi: timeout'
echo '  curl -m 5 http://<CTL_IP>/healthz                                                 # mong đợi: 200 + hostname'

h "HM5 - Mỗi danh tính 1 application credential (không dùng mật khẩu thật trong ứng dụng)"
echo "User dịch vụ và role trong project cloudjudge:"
openstack role assignment list --project cloudjudge --names -c Role -c User -f value | sort | sed 's/@Default//' | grep -E "cj-"
h "HM5 - Test phân quyền Swift: worker xóa/ghi object bị 403"
bash "$REPO/infra/bootstrap/55-test-acl.sh"
h "HM5 - Không có khóa trong Git"
if [ -d "$REPO/.git" ]; then
  cd "$REPO" && { git grep -nIE "(AC_SECRET|PASSWORD|password|secret)[A-Za-z_]*\s*[:=]\s*['\"]?[A-Za-z0-9_/+=-]{16,}" -- . ':!docs' ':!*.md' ':!scripts/demo-checks.sh' ':!infra/bootstrap/*.sh' && echo "!! CÓ KẾT QUẢ ở trên: kiểm tra" || echo "git grep: không thấy khóa/mật khẩu"; }
  command -v gitleaks >/dev/null && gitleaks detect --no-banner -s "$REPO" || echo "(gitleaks chưa cài trên máy này; chạy trên laptop: gitleaks detect)"
else
  echo "(thư mục $REPO không phải repo git; chạy phần này trên laptop: git grep ... / gitleaks detect)"
fi
