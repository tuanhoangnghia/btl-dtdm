#!/usr/bin/env bash
# MINH CHỨNG HẠNG MỤC 5 (IAM): mỗi danh tính dùng application credential riêng, quyền tối thiểu, hành động vượt quyền bị 403.
# Trên controller. Không in secret. Mã thoát 0 = mọi kỳ vọng đúng.
set -uo pipefail
source ~/kolla-venv/bin/activate
set -a; source ~/secrets/infra.env; set +a
AUTH=http://10.10.0.10:5000/v3
FAIL=0
sw() {  # sw <web|worker|monitor|backup> <lệnh swift...>   (chạy bằng application credential của danh tính đó)
  local w=${1^^}; shift; local id=CJ_${w}_AC_ID sec=CJ_${w}_AC_SECRET
  ( unset $(env | grep -o '^OS_[A-Z_]*')
    swift --os-auth-type v3applicationcredential --os-auth-url "$AUTH" \
      --os-application-credential-id "${!id}" --os-application-credential-secret "${!sec}" "$@" 2>&1 )
}
expect() {  # expect <OK|403> "<mô tả>" <lệnh...>
  local want=$1 desc=$2; shift 2
  local out; out=$("$@"); local rc=$?
  local got=OK; echo "$out" | grep -q "403" && got=403
  [ $rc -ne 0 ] && [ "$got" = OK ] && got="LỖI($(echo "$out" | head -1 | cut -c1-60))"
  if [ "$got" = "$want" ]; then printf '%-72s %s\n' "$desc" "-> $got (đúng)"; else printf '%-72s %s\n' "$desc" "-> $got (SAI, mong đợi $want)"; FAIL=1; fi
}
# swift upload mặc định thử PUT container trước (user chỉ có ACL không có quyền tạo container) -> dùng --skip-container-put
echo hello-cloudjudge > /tmp/acl-test.txt

echo "== cj-web (role member): ghi được vào submissions/testcases"
expect OK  "web   upload  submissions/acl-test.txt"        sw web upload --skip-container-put submissions /tmp/acl-test.txt --object-name acl-test.txt
expect OK  "web   upload  testcases/acl-test.txt"          sw web upload --skip-container-put testcases /tmp/acl-test.txt --object-name acl-test.txt
echo "== cj-worker (role reader + ACL): chỉ ĐỌC; xóa/ghi bị 403"
expect OK  "worker list   submissions"                      sw worker list submissions
expect OK  "worker download submissions/acl-test.txt"       sw worker download submissions acl-test.txt -o /tmp/acl-dl.txt
expect 403 "worker DELETE submissions/acl-test.txt"         sw worker delete submissions acl-test.txt
expect 403 "worker upload submissions/evil.txt"             sw worker upload --skip-container-put submissions /tmp/acl-test.txt --object-name evil.txt
expect 403 "worker upload backups/evil.txt (không có ACL)"  sw worker upload --skip-container-put backups /tmp/acl-test.txt --object-name evil.txt
echo "== cj-backup: chỉ đọc releases, đọc/ghi backups; không đụng submissions"
expect OK  "backup upload backups/acl-test.txt"             sw backup upload --skip-container-put backups /tmp/acl-test.txt --object-name acl-test.txt
expect OK  "backup list   releases"                         sw backup list releases
expect 403 "backup DELETE submissions/acl-test.txt"         sw backup delete submissions acl-test.txt
echo "== cj-monitor (reader, không ACL nào): không đọc được dữ liệu"
expect 403 "monitor list  submissions"                      sw monitor list submissions
echo "== dọn bằng cj-web / cj-backup"
sw web delete submissions acl-test.txt >/dev/null; sw web delete testcases acl-test.txt >/dev/null; sw backup delete backups acl-test.txt >/dev/null
rm -f /tmp/acl-test.txt /tmp/acl-dl.txt
echo; [ $FAIL = 0 ] && echo "ACL_TEST_PASS" || echo "ACL_TEST_FAIL"
exit $FAIL
