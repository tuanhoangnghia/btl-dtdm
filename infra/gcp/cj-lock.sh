#!/usr/bin/env bash
# Khóa "đang dùng cụm" để người khác không tắt cụm giữa chừng. Khóa lưu ở metadata project (key cj-lock-<A|B|C>),
# tự hết hạn (mặc định 4 giờ) nên quên nhả cũng không kẹt mãi.
#   cj-lock.sh acquire <A|B|C> "<lý do>" [số giờ]   # báo "tôi đang dùng cụm"
#   cj-lock.sh release <A|B|C>                      # xong việc thì nhả
#   cj-lock.sh status                               # xem ai đang giữ khóa
#   CJ_ME=<A|B|C> cj-lock.sh check                  # exit 1 nếu có khóa còn hạn của người KHÁC (gcp-down.sh dùng)
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"

active_locks() {   # in ra: <người>\t<còn lại phút>\t<lý do>, chỉ các khóa còn hạn
  gcloud compute project-info describe --format=json | python -I -c '
import json,sys,time
sys.stdout.reconfigure(encoding="utf-8")
items=(json.load(sys.stdin).get("commonInstanceMetadata") or {}).get("items") or []
now=int(time.time())
for it in items:
    k=it.get("key","")
    if not k.startswith("cj-lock-"): continue
    exp,_,why=it["value"].partition("|")
    left=(int(exp)-now)//60
    if left>0: print("%s\t%d\t%s"%(k[len("cj-lock-"):],left,why))
'
}

cmd="${1:-status}"
case "$cmd" in
  acquire)
    who="${2:?cần <A|B|C>}"; why="${3:-đang dùng cụm}"; hours="${4:-4}"
    exp=$(( $(date +%s) + hours*3600 ))
    # gcloud trên Windows làm hỏng ký tự có dấu khi truyền tham số -> bỏ dấu trước khi lưu
    why=$(python -I -c 'import sys,unicodedata as u; t=sys.argv[1].replace("đ","d").replace("Đ","D"); print("".join(c for c in u.normalize("NFD",t) if not u.combining(c)))' "$why")
    gcloud compute project-info add-metadata --metadata="cj-lock-${who}=${exp}|${why}" >/dev/null
    echo "Đã giữ khóa ${who} trong ${hours} giờ: ${why}" ;;
  release)
    who="${2:?cần <A|B|C>}"
    gcloud compute project-info remove-metadata --keys="cj-lock-${who}" >/dev/null 2>&1 || true
    echo "Đã nhả khóa ${who}" ;;
  status)
    out=$(active_locks)
    if [ -z "$out" ]; then echo "Không ai đang giữ khóa."; else printf '%s\n' "$out" | awk -F'\t' '{printf "%s đang dùng cụm (còn %s phút): %s\n",$1,$2,$3}'; fi ;;
  check)
    me="${CJ_ME:-}"; busy=$(active_locks | awk -F'\t' -v me="$me" '$1!=me{printf "  - %s (còn %s phút): %s\n",$1,$2,$3}')
    if [ -n "$busy" ]; then echo "Có người đang dùng cụm:"; echo "$busy"; exit 1; fi ;;
  *) echo "Dùng: $0 acquire <A|B|C> \"lý do\" [giờ] | release <A|B|C> | status | check"; exit 2 ;;
esac
