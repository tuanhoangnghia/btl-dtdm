#!/usr/bin/env bash
# Trên controller (user cj). Tạo ~/secrets/data.env (quyền 640, owner cj, group cj) với mật khẩu NGẪU NHIÊN cho CSDL và RabbitMQ.
# CONTRACT mục 10 coi data.env là của C, nhưng thư mục ~/secrets chỉ cho group cj ĐỌC nên B/C không tự tạo được file mới;
# A tạo sẵn để B chạy được heat/deploy-cj-app.sh. C dùng ĐÚNG các giá trị này khi dựng stack cj-data (KHÔNG sinh lại: MySQL và RabbitMQ
# sẽ được khởi tạo với các mật khẩu này, đổi sau phải ALTER USER).
# Chạy lại được: chỉ THÊM biến còn thiếu, không bao giờ ghi đè biến đã có. Giá trị là hex (an toàn khi truyền qua Heat/env, không có $, nháy, khoảng trắng).
set -euo pipefail
F=${1:-$HOME/secrets/data.env}
mkdir -p "$(dirname "$F")"
( umask 037; touch "$F" )
chgrp cj "$F" 2>/dev/null || true
chmod 640 "$F"

have() { grep -qE "^$1=." "$F"; }
add() { have "$1" || { sed -i "/^$1=\$/d" "$F"; echo "$1=$(openssl rand -hex 16)" >> "$F"; echo "đã tạo $1"; }; }
for v in MYSQL_ROOT_PASSWORD DB_PASSWORD DB_RO_PASSWORD REPL_PASSWORD EXPORTER_PASSWORD BACKUP_DB_PASSWORD MQ_PASSWORD; do add "$v"; done

# Các biến cần người thật cung cấp (A không biết): để C điền (cj-mon, Alertmanager gửi email qua Gmail cổng 587).
for v in SMTP_USER SMTP_APP_PASSWORD ALERT_EMAIL_TO; do
  grep -qE "^#?\s*$v=" "$F" || echo "# $v=   <-- C điền (Gmail + App Password), xem docs/tasks/C-du-lieu-giam-sat.md" >> "$F"
done
chgrp cj "$F" 2>/dev/null || true; chmod 640 "$F"

echo "-- $F: $(stat -c '%a %U:%G' "$F"); biến đã có (không in giá trị):"
awk -F= '/^[A-Z_]+=./{printf "  %s (độ dài %d)\n",$1,length($2)}' "$F"
