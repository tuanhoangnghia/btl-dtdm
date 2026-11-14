# Hàm dùng chung cho các script trong db/ (source, không chạy trực tiếp).
# MySQL chạy trong container (mặc định tên cj-mysql); root chỉ đăng nhập được qua socket trong container (MYSQL_ROOT_HOST=localhost).
# Mật khẩu root: biến MYSQL_ROOT_PASSWORD, nếu không có thì đọc file /run/cj/root.pw trong container (cách làm trên cụm).
export MSYS_NO_PATHCONV=1   # Git Bash trên Windows: không đổi đường dẫn /... trong tham số docker

MYSQL_CONTAINER=${MYSQL_CONTAINER:-cj-mysql}

require() {
  local v miss=()
  for v in "$@"; do [ -n "${!v:-}" ] || miss+=("$v"); done
  [ ${#miss[@]} -eq 0 ] || { echo "Thiếu biến: ${miss[*]}" >&2; exit 1; }
}

# mysql_root [tham số mysql...]: chạy client mysql với quyền root trong container, SQL đọc từ stdin hoặc -e
mysql_root() {
  if [ -n "${MYSQL_ROOT_PASSWORD:-}" ]; then
    docker exec -i -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" "$MYSQL_CONTAINER" mysql -uroot "$@"
  else
    docker exec -i "$MYSQL_CONTAINER" sh -c 'MYSQL_PWD=$(cat /run/cj/root.pw) exec mysql -uroot "$@"' sh "$@"
  fi
}

# Chờ MySQL chạy thật (entrypoint lần đầu dựng một server tạm với skip_networking, không tính)
wait_mysql() {
  local i
  for i in $(seq 1 90); do
    [ "$(mysql_root -N -e 'SELECT @@skip_networking' 2>/dev/null)" = "0" ] && return 0
    sleep 2
  done
  echo "MySQL trong container $MYSQL_CONTAINER chưa sẵn sàng sau 3 phút" >&2
  return 1
}

# render <file.tpl> <BIẾN...>: thay đúng các biến được liệt kê (không đụng ký tự $ khác)
render() {
  local f=$1; shift
  envsubst "$(printf '${%s} ' "$@")" < "$f"
}
