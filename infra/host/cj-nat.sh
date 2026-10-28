#!/bin/bash
# NAT/DNAT cho mạng external giả trên controller. Cài tại /usr/local/sbin/cj-nat.sh, chạy bởi cj-nat.service.
# Cổng 80 public (Internet) -> floating IP của LB (ghi vào /etc/cloudjudge/lb_fip sau khi có stack cj-app).
set -u
sysctl -w net.ipv4.ip_forward=1 >/dev/null
iptables -P FORWARD ACCEPT
ip link set veth-host up 2>/dev/null || true
ip link set veth-ex up 2>/dev/null || true

# Tenant (đã SNAT qua router -> 172.24.4.x) ra Internet
iptables -t nat -C POSTROUTING -s 172.24.4.0/24 ! -d 172.24.4.0/24 -o ens4 -j MASQUERADE 2>/dev/null \
  || iptables -t nat -A POSTROUTING -s 172.24.4.0/24 ! -d 172.24.4.0/24 -o ens4 -j MASQUERADE

# Cổng 80 vào từ Internet (ens4) -> floating IP của LB
if [ -s /etc/cloudjudge/lb_fip ]; then
  FIP=$(cat /etc/cloudjudge/lb_fip)
  iptables -t nat -C PREROUTING -i ens4 -p tcp --dport 80 -j DNAT --to-destination "$FIP:80" 2>/dev/null \
    || iptables -t nat -A PREROUTING -i ens4 -p tcp --dport 80 -j DNAT --to-destination "$FIP:80"
fi
