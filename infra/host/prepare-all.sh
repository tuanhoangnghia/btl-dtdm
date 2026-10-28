#!/usr/bin/env bash
# Chạy trên CẢ 3 máy, quyền root:  ssh <host> 'sudo bash -s' < infra/host/prepare-all.sh
set -eux
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -y upgrade
apt-get install -y python3-venv python3-dev python3-pip git gcc libffi-dev libssl-dev libdbus-glib-1-dev tmux jq xfsprogs lvm2 parted
systemctl disable --now unattended-upgrades || true     # tránh tự cập nhật/khởi động lại giữa buổi demo
timedatectl set-timezone Asia/Ho_Chi_Minh
