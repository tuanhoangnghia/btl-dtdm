# infra/ – dựng lại hạ tầng CloudJudge từ đầu (phần A)

Mọi thứ ở đây chạy được lại nhiều lần. Thứ tự dưới đây là thứ tự đã chạy thật (28–29/10/2026). Mật khẩu, secret, key **không** nằm trong repo
(chúng nằm ở `~/secrets/` trên controller, xem `docs/CONTRACT.md` mục 10).

## 0. Yêu cầu
- Một project GCP có billing, `gcloud` trên laptop, cấu hình riêng: `source infra/gcp/00-vars.sh` (đặt `CLOUDSDK_ACTIVE_CONFIG_NAME=cloudjudge`).
- Quota vùng `asia-southeast1`: **SSD ≤ 250 GB** (đĩa pd-balanced tính vào đây), CPU ≥ 8, IP in-use ≥ 3.
- Tailscale trên laptop (đăng nhập cùng tailnet với `cj-controller`). SSH `cj-ctl` đi qua Tailscale vì IP nhà thay đổi thất thường.

## 1. GCP (laptop) – `infra/gcp/`
| Script | Việc |
|---|---|
| `10-network.sh` | VPC `cj-vpc` (MTU 1500), subnet 10.10.0.0/24, 4 firewall, IP tĩnh `cj-ctl-ip` |
| `20-vms.sh` | 3 máy, **bật nested virtualization**. Controller n2-highmem-4 (boot 100 + cinder 50 SSD + swift 30 HDD), 2 compute n2-highmem-2 (boot 48 SSD) |
| `gcp-up.sh` / `gcp-down.sh` | Bật/tắt cụm. `gcp-down.sh` từ chối nếu người khác đang giữ khóa |
| `cj-lock.sh` | Khóa "đang dùng cụm" (metadata project, tự hết hạn 4 giờ) |
| `update-ssh-ip.sh` | Cập nhật firewall SSH theo IP hiện tại (chỉ cần khi không dùng Tailscale) |

## 2. Host (controller và 2 compute) – `infra/host/`
1. `prepare-all.sh` trên cả 3 máy (gói, múi giờ, `isc-dhcp-client` cho Octavia).
2. `prepare-controller.sh` trên controller: cặp **veth** `veth-host` (172.24.4.1/24) ↔ `veth-ex` làm mạng external giả, `cj-nat.service`
   (MASQUERADE 172.24.4.0/24 ra `ens4`; DNAT cổng 80 → floating IP của LB khi có `/etc/cloudjudge/lb_fip`), LVM `cinder-volumes`,
   đĩa Swift (partition `KOLLA_SWIFT_DATA`, XFS label `d0`), Tailscale (quảng bá 10.10.0.0/24 và 172.24.4.0/24; **duyệt route ở admin console**).
3. Controller cần SSH key vào cả 3 máy (Kolla chạy từ controller).

## 3. OpenStack – `infra/kolla/`
**Kolla-Ansible 21.3.0 = 2025.2**, `ansible-core` 2.18, Ubuntu 24.04. (2024.2 không dùng được: image đã bị gỡ khỏi quay.io; từ 2025.1 Kolla bỏ role Swift.)
```
bash install-kolla.sh           # venv, kolla-ansible, install-deps, passwords.yml
cp globals.yml /etc/kolla/ ; cp config/*.conf /etc/kolla/config/
bash make-inventory.sh          # sinh ~/multinode từ mẫu của đúng phiên bản đang cài
kolla-ansible bootstrap-servers -i ~/multinode
kolla-ansible octavia-certificates -i ~/multinode
kolla-ansible prechecks -i ~/multinode
bash deploy.sh                  # pull + deploy (tmux)
kolla-ansible post-deploy -i ~/multinode
bash post-deploy-fixes.sh       # drop-in cho octavia-interface (tự thử lại khi OVS chưa sẵn sàng sau reboot)
```
Các điểm khác mặc định đã xử lý trong `globals.yml`: `enable_proxysql: no` (ProxySQL chiếm `VIP:3306` trùng IP controller → MariaDB không lên),
`enable_haproxy: no`, Redis → Valkey, `neutron_plugin_agent: openvswitch` (Octavia kiểu `tenant` chỉ hỗ trợ OVS), `octavia_network_type: tenant`.

## 4. Swift cài tay – `infra/swift/install-swift.sh`
Swift 2.33 từ gói Ubuntu, 1 node/1 đĩa, **replicas=1**, xác thực Keystone. Đăng ký service `swift` (object-store) và 3 endpoint.

## 5. Khởi tạo OpenStack – `infra/bootstrap/` (chạy trên controller, theo thứ tự số)
| Script | Việc |
|---|---|
| `10-az-flavor-image.sh` | `az1`=os-compute-1, `az2`=os-compute-2 (host aggregate), flavor `cj.*`, image `ubuntu-24.04`, `cirros` |
| `20-extnet.sh` | `ext-net` (flat physnet1 → `br-ex` → `veth-ex`) |
| `60-build-amphora.sh` | Build ảnh amphora từ **stable/2025.2** (tmux, ~10 phút) và đưa vào Glance (project service, tag `amphora`) |
| `smoke-test.sh`, `smoke-lb.sh` | Smoke test: 2 VM ở 2 AZ, ra Internet, gọi Keystone/Swift, MTU, ping chéo AZ; LB ACTIVE_STANDBY ở 2 host |
| `30-project-users.sh` | Project `cloudjudge`, 4 user `cj-*` (quyền tối thiểu), 3 user `tuan`/`trong`/`phuong`, quota |
| `40-appcreds.sh` | Application credential của 4 user `cj-*` → `~/secrets/infra.env` |
| `50-swift-acl.sh` | 4 container + ACL theo CONTRACT 8.1 |
| `55-test-acl.sh` | Minh chứng hạng mục 5: worker xóa/ghi object bị 403 |
| `05-add-user.sh` | User Linux cho thành viên: `sudo bash 05-add-user.sh <linux> <openstack> "<ssh pubkey>"` |

## 6. Stack Heat mạng – `heat/cj-net.yaml`, `heat/deploy-cj-net.sh`
3 network + router (SNAT) + 6 security group + bastion (floating IP, Tailscale subnet router tùy chọn nếu có `TS_BASTION_KEY` trong `~/secrets/infra.env`).

## 7. Vận hành hằng ngày
- Bật: `bash infra/gcp/gcp-up.sh` (chờ ~5 phút; Kolla và VM OpenStack tự lên). Kiểm: `ssh cj-ctl`, `openstack compute service list`, `network agent list`.
- Tắt: `CJ_ME=A bash infra/gcp/gcp-down.sh` (sau khi `cj-lock.sh status` không có ai khác đang dùng).
- Snapshot đĩa sau mỗi mốc: xem `docs/tasks/A-ha-tang.md` mục Nhật ký.
- Lỗi thường gặp: `docs/tasks/A-ha-tang.md` (Nhật ký 29/10) và `KE_HOACH_TRIEN_KHAI.md` mục 15.3.
