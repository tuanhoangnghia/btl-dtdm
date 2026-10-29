# Nhiệm vụ A – Hạ tầng, mạng, phân quyền (HM 1, 2, 5)

**Người phụ trách:** ______  · **Đường găng của cả nhóm:** B và C chỉ lên cụm được khi A bàn giao (31/10).

Đọc trước: `docs/CONTRACT.md` (bắt buộc), `KE_HOACH_TRIEN_KHAI.md` mục 1–8, 11.1, 13, 15.

## Phạm vi
- **Được sửa:** `infra/**`, `heat/cj-net.yaml`, `heat/deploy-cj-net.sh`, `scripts/demo-checks.sh`, `docs/report/A-*.md`, `docs/evidence/A-*`, file này.
- **Không sửa:** mọi thứ khác (xem CONTRACT mục 1). Thấy lỗi ở phần B/C thì nhắn họ.
- **Độc quyền:** chạy `kolla-ansible`, sửa cấu hình host/GCP, tạo user OpenStack, application credential.

## Việc theo ngày

| Ngày | Việc | Tham chiếu kế hoạch |
|---|---|---|
| 28/10 | Repo GitHub private (đẩy khung hiện có lên), bảo vệ `main`, mời B, C. Tạo tailnet Tailscale, mời B, C. Phase 0 + Phase 1 (project, budget, VPC, 3 VM, kiểm `/dev/kvm`). Viết `gcp-up.sh` / `gcp-down.sh` | 4, 5 |
| 28/10 | Cấp IAM cho B, C để họ tự bật/tắt máy: `gcloud projects add-iam-policy-binding $PROJECT_ID --member=user:<gmail> --role=roles/compute.instanceAdmin.v1` | |
| 29/10 | Phase 2 (veth, NAT, LVM, Swift disk, Tailscale controller) + Phase 3 (Kolla 2024.2 deploy) | 6, 7 |
| 30/10 | Phase 4.1–4.4: AZ, flavor, image, ext-net, amphora, **smoke test** | 8.1–8.4 |
| 31/10 | 4.5–4.7: project `cloudjudge`, user OpenStack `tuan`/`trong`/`phuong` (admin) + 4 service user + app credential → `~/secrets/infra.env`; container Swift + ACL; user Linux `trong`, `phuong` trên controller (sudo, group `cj`, SSH key của họ); stack **`cj-net`** + bastion Tailscale. **Bàn giao "cụm sẵn sàng"** | 8.5–8.7, 11.1 |
| 1/11 | Hỗ trợ B/C debug mạng/LB/SG. Kiểm `curl` từ VM tới Keystone/Swift/heat-cfn | 15.3 |
| 2/11 | Nhận `lb_fip` từ B → ghi `/etc/cloudjudge/lb_fip`, chạy lại `cj-nat.sh` (DNAT 80) | 6.2b |
| 3–4/11 | Kiểm thử bảo mật + minh chứng HM 1, 2, 5; `scripts/demo-checks.sh` | 13 |
| 5/11 | Thử failover amphora (MASTER chết → BACKUP); snapshot đĩa mốc "m2" | 13, 15.2 |
| 6/11 | Tập demo lần 1 (A nói phút 0:00–1:00 và 2:45–4:00) | 14.1 |
| 7/11 | Viết `docs/report/A-ha-tang.md`: dựng OpenStack trên GCP (nested virt, mạng external giả, MTU, vì sao Kolla 2024.2 + OVS), mạng/SG, IAM | 14.4 |
| 8–9/11 | Quay video; `README.md` hướng dẫn dựng lại từ đầu (đề xuất PR chung); snapshot "final" | |
| 10–16/11 | Ôn vấn đáp phần A (kế hoạch 14.5) | |

## Bàn giao cho B, C ngày 31/10 (gửi vào nhóm chat)
- Hostname Tailscale `cj-controller`, user Linux của từng người, đường dẫn `~/secrets/infra.env`.
- `clouds.yaml` mẫu cho user OpenStack của họ (mật khẩu gửi riêng).
- Output `cj-net` đúng tên trong CONTRACT mục 5.
- Kết quả smoke test: thời gian boot VM, VM ra được Internet, gọi được Swift.

## Nếu kẹt
- Đến **31/10** chưa qua smoke test 8.4 (bước 1–4): báo cả nhóm và thầy, chuyển sang AWS (đổi 1–1). B và C vẫn tiếp tục phần của họ.
- Octavia lỗi: topology SINGLE → HAProxy VM (kế hoạch D3). Báo B vì ảnh hưởng `cj-app`.

## Thông tin cụm (A cập nhật, B/C đọc)
- PROJECT_ID: `omega-dahlia-468315-f6` · BILLING_ID: `01BE00-008CAB-253DE8` (không có quyền xem/tạo budget bằng CLI) · CTL_IP: `34.124.240.64` (static `cj-ctl-ip`)
- gcloud: dùng cấu hình riêng `cloudjudge` (`source infra/gcp/00-vars.sh` đặt sẵn `CLOUDSDK_ACTIVE_CONFIG_NAME`); tài khoản `hoangnghiatuan297@gmail.com`. **Không** dùng cấu hình `default` (trỏ project khác).
- Đĩa: quota SSD vùng chỉ **250 GB** (không phải 340 như kế hoạch). Hiện tại: controller boot 100 + cinder 50 (pd-balanced), swift 30 (pd-standard), 2 compute boot **48 GB** mỗi máy (pd-balanced) → SSD 246 GB. Không còn dư để thêm đĩa SSD.
- Project còn 2 máy cũ `compute`, `controller` (asia-southeast1-b, tắt, tạo 23/9) không thuộc dự án này, đừng xóa nếu chưa hỏi chủ.
- Tailscale controller: `cj-controller` = `100.98.68.95` · bastion: chưa vào Tailscale (qua controller: floating IP `172.24.4.131`)
- **SSH của người dùng A đi qua Tailscale** (`ssh cj-ctl` = 100.98.68.95), không dùng IP public: IP nhà đổi thất thường và GCP thấy IP nguồn khác `ifconfig.me`, nên firewall theo IP không ổn định. `ssh cj-ctl-pub` còn dùng được khi đúng IP.
- Phiên bản Kolla-Ansible thực tế: **21.3.0 (2025.2)**, ansible-core 2.18.19, Swift 2.33.0 cài tay
- Tổng giờ chạy cụm: `~10,5` / 300 (cập nhật 29/10 buổi chiều)

## Tiến độ
- [ ] Repo + Tailscale + IAM cho B, C  (chưa: repo chưa push, Tailscale chưa tạo, B/C chưa có quyền GCP)
- [x] Phase 1 GCP (`/dev/kvm` OK trên 3 máy, 28/10) — budget alert chưa đặt (xem Nhật ký)
- [x] Phase 2 host (28/10): veth, NAT, LVM, đĩa Swift, Tailscale controller, SSH key Kolla. **Còn việc tay:** duyệt 2 subnet route trong Tailscale admin
- [x] Phase 3 Kolla deploy 2025.2 (29/10): keystone, nova (2 compute, 2 zone), neutron OVS, cinder-lvm, heat, octavia (provider amphora), glance, horizon đều up. **Swift cài tay xong (xem dòng sau)**
- [x] Phase 4 smoke test qua (29/10): VM 2 AZ boot 18s, ra Internet, gọi Keystone/Swift, MTU 1450, ping chéo AZ; Octavia ACTIVE_STANDBY MASTER+BACKUP ở 2 host. Minh chứng: `docs/evidence/A-smoke-test-*.txt`
- [x] User/app cred/Swift ACL/`infra.env` (29/10): project `cloudjudge`, 4 user `cj-*` + `tuan`/`trong`/`phuong`, 4 application credential, 4 container + ACL, `55-test-acl.sh` qua (worker xóa object bị 403). User Linux `trong`, `phuong` đã tạo nhưng **chưa có SSH key**
- [x] Stack `cj-net` CREATE_COMPLETE (3 mạng, router, 6 SG, bastion FIP 172.24.4.131; đủ 14 output theo CONTRACT mục 5)
- [ ] Bastion vào Tailscale (cần **auth key mới**, chạy `TS_BASTION_KEY=... ` vào `~/secrets/infra.env` rồi `bash heat/deploy-cj-net.sh`) và **bàn giao** cho B, C (cần SSH key của họ)
- [ ] DNAT cổng 80
- [x] Minh chứng HM 1, 2, 5 ở mức hạ tầng: `docs/evidence/A-demo-checks.txt`, `A-acl-test.txt`
- [ ] Còn: curl worker→web bị chặn (cần `cj-app`), failover amphora (cần LB của B), chụp màn hình Horizon
- [x] Nháp báo cáo `docs/report/A-ha-tang.md` và `infra/README.md` (dựng lại từ đầu); còn bổ sung số liệu/ảnh sau khi tập demo

## Nhật ký
- 28/10 tối (A): Phase 1 xong. VPC `cj-vpc` MTU 1500, subnet 10.10.0.0/24, 4 firewall rule, IP tĩnh `34.124.240.64`. 3 máy tạo xong, đều có `/dev/kvm` (vmx > 0), `ens4`, ra Internet được; controller có `/dev/disk/by-id/google-cinder` (50G) và `google-swift` (30G). SSH vào qua `ssh cj-ctl` / `cj-c1` / `cj-c2` (key `~/.ssh/cloudjudge`). Đã **tắt cả 3 máy**; bật lại bằng `bash infra/gcp/gcp-up.sh`.
- 28/10 tối (A): quota SSD vùng chỉ 250 GB → đổi đĩa Swift sang pd-standard, boot compute 48 GB (xem mục Thông tin cụm).
- 28/10 tối (A): **chưa đặt budget alert**: tài khoản `hoangnghiatuan297@gmail.com` không liệt kê được billing account và Billing Budgets API chưa bật. Việc cần làm tay trong Console → Billing → Budgets: cảnh báo 50/75/90% của ~₫7,7 triệu.
- 28/10 tối (A): Phase 2 xong, đã kiểm: `veth-host` 172.24.4.1/24 UP, `cj-nat.service` active (MASQUERADE 172.24.4.0/24), `vgs` có `cinder-volumes` 50G, đĩa Swift có partition `KOLLA_SWIFT_DATA` + XFS label `d0`, controller SSH được sang cả 3 IP bằng key riêng (`cj@os-controller`, đã thêm vào metadata project). Tailscale controller vào tailnet (hostname `cj-controller`, `100.98.68.95`), đang quảng bá 10.10.0.0/24 và 172.24.4.0/24 (**chờ duyệt route ở admin console**). Script: `infra/host/`. Đã tắt cụm sau khi xong.
- 28/10 tối (A): thêm cơ chế khóa dùng cụm để tránh bị tắt giữa chừng: `infra/gcp/cj-lock.sh acquire|release|status|check` (khóa lưu ở metadata project, tự hết hạn sau 4 giờ, lý do tự bỏ dấu). `gcp-down.sh` từ chối tắt nếu người KHÁC đang giữ khóa (đặt `CJ_ME=A|B|C`; `FORCE=1` để tắt cưỡng bức sau khi đã hỏi nhóm). **Đề xuất sửa CONTRACT mục 3.2** (cần cả 3 đồng ý): bắt buộc giữ khóa khi làm việc và chỉ tắt cụm bằng `gcp-down.sh`, không chạy `gcloud compute instances stop` trực tiếp.
- 29/10 (A): **ĐỔI QUYẾT ĐỊNH D1 (Kolla 2024.2 -> 2025.2).** Đã cài thử 19.8.0 (2024.2) thành công nhưng **image Kolla 2024.2 đã bị gỡ khỏi quay.io** (API chỉ còn tag 2025.1+), nên không deploy được. Kiểm tra wheel: 19.8.0 có role Swift (44 file), **từ 20.0.0 trở đi không còn role Swift**. Chọn **Kolla-Ansible 21.3.0 = 2025.2 (Flamingo)**, `ansible-core` 2.18; đã xác nhận image `2025.2-ubuntu-noble` có đủ keystone/nova/neutron-ovs/cinder/heat/octavia/horizon; `neutron_plugin_agent` mặc định vẫn `openvswitch`, `octavia_network_type` vẫn có `tenant`. Script: `infra/kolla/install-kolla.sh`.
- 29/10 (A): **Swift phải cài tay** (Kolla không còn): gói Ubuntu `swift`, `swift-proxy`, `swift-account`, `swift-container`, `swift-object` trên controller, dùng XFS `d0` đã chuẩn bị, tích hợp Keystone bằng `keystonemiddleware`, đăng ký endpoint `http://10.10.0.10:8080/v1/AUTH_%(project_id)s`. Giao diện với B/C **không đổi** (cùng container `submissions`, `testcases`, `releases`, `backups`, cùng ACL Keystone). Cần ghi lại lý do này trong báo cáo, mục "Lý giải lựa chọn công nghệ". KE_HOACH_TRIEN_KHAI.md (D1, mục 7.5) chưa sửa vì là file chung.
- 29/10 (A): **Phase 3 xong**, deploy mất 4 lần chạy. Các lỗi gặp và cách sửa (đã ghi vào `infra/`): (1) `install-deps` lỗi nhánh `stable/2024.2` -> bỏ 2024.2 (xem mục đổi D1); (2) 2025.2 thay Redis bằng Valkey -> `enable_redis: no`, `enable_valkey: yes`; (3) inventory phải sinh từ mẫu của đúng bản đang cài (`infra/kolla/make-inventory.sh`), mẫu 19.x thiếu nhóm `nova-metadata`; (4) Octavia cần chứng chỉ: `kolla-ansible octavia-certificates`; (5) `enable_proxysql` mặc định = enable_mariadb, ProxySQL chiếm `VIP:3306` (VIP = IP controller) làm MariaDB không lên -> `enable_proxysql: no` + xóa container `proxysql`/`haproxy` thừa; (6) Ubuntu 24.04 thiếu `/sbin/dhclient` cho `octavia-interface.service` -> cài `isc-dhcp-client` (đã thêm vào `prepare-all.sh`); (7) lần chạy sau lỗi `o-hm0` chưa có IPv4 chỉ do chạy sớm hơn lúc DHCP cấp xong, chạy lại là qua. Script: `infra/kolla/{globals.yml,install-kolla.sh,make-inventory.sh,deploy.sh,config/}`.
- 29/10 (A): **Swift cài tay xong và đã kiểm chứng** (`infra/swift/install-swift.sh`, chạy lại được). Swift 2.33.0 từ gói Ubuntu, 1 node/1 đĩa (`/srv/node/d0`, XFS label `d0`, mount bằng fstab), **replicas=1** (không chịu được lỗi đĩa, ghi rõ trong báo cáo mục Giới hạn), xác thực bằng Keystone (`keystonemiddleware` + `keystoneauth`, `operator_roles = admin, member, swiftoperator`), cache dùng memcached của Kolla (`10.10.0.10:11211`). Endpoint trong catalog: `http://10.10.0.10:8080/v1/AUTH_%(project_id)s` (public/internal/admin). User dịch vụ `swift` (project `service`, role admin), mật khẩu ở `~/secrets/infra.env` (`SWIFT_SERVICE_PASSWORD`). Đã thử: tạo container, upload, tải về (khớp), `swift stat`, xóa; 13 unit `active`. Ghi chú: log proxy có cảnh báo vô hại `urllib3 ... expected httplib.Message` khi authtoken gọi Keystone (eventlet + urllib3 2.x), request vẫn thành công, bỏ qua. **Chưa thử:** ACL theo user + application credential (cần project `cloudjudge`, user `cj-*` ở Phase 4.5–4.7). Dữ liệu và cấu hình (`/etc/swift`, rings, hash suffix) nằm trên controller, đã nằm trong snapshot đĩa khi chụp.
- 29/10 07:35 (A): **Đã tắt cụm** bằng `CJ_ME=A bash infra/gcp/gcp-down.sh`, sau khi kiểm tra không ai dùng (không phiên SSH/tmux/ansible, Tailscale: máy `desktop-gv0ftqh` của tranphuong070605 online nhưng 0 byte, `media` của minhtrongc31120 offline; không có VM/LB/volume nào; chưa có user OpenStack của B, C). Cụm đã chạy thừa ~6 giờ (khóa A tự hết hạn lúc 04:00, không có gì nhắc tắt) -> **lần sau xong việc phải tắt ngay hoặc nói rõ lúc nào tắt**. IP nhà đổi (171.229.208.148 -> 123.31.18.242) làm SSH bị timeout; `update-ssh-ip.sh` đã cập nhật firewall. **Nếu SSH timeout: chạy `bash infra/gcp/update-ssh-ip.sh` trước.** B/C vẫn cần user Linux + user OpenStack trên controller (việc 31/10) mới SSH/đăng nhập được.
- 29/10 chiều (A): **Phase 4 và 4.5–4.7 xong.** Smoke test qua. Lỗi gặp và sửa: (1) smoke-test thêm rule vào SG `default` bị lỗi im lặng vì admin thấy nhiều SG cùng tên `default` -> tra theo ID của project; (2) `swift upload` luôn thử `PUT container` trước nên user chỉ có ACL bị 403 -> dùng `--skip-container-put` (app của B nên dùng `put_object`, không dùng lệnh upload của CLI); (3) JSON của `application credential create` có khóa viết hoa (`ID`, `Secret`) nên lần đầu `infra.env` ghi giá trị rỗng, đã sửa; **mình in lộ secret của credential thử `dbg-ac` khi debug, đã xóa ngay**; (4) **`octavia-interface.service` chạy quá sớm sau reboot** (OVS chưa tạo cổng `o-hm0`) -> systemd bỏ cuộc -> `o-hm0` không có IP -> Octavia không nói chuyện được với amphora (LB kẹt `PENDING_CREATE` 440s). Đã thêm drop-in `Restart=on-failure`, `RestartSec=10`, `StartLimitIntervalSec=0` (`infra/kolla/post-deploy-fixes.sh`). **Sau mỗi lần bật cụm kiểm `ip -br a show o-hm0` có IP 10.1.0.x.**
- 29/10 chiều (A): ảnh amphora build từ stable/2025.2 (`60-build-amphora.sh`, ~10 phút, AMP_EXIT=0). Stack `cj-net`: floating IP bastion `172.24.4.131`; vào bastion bằng `ssh -J cj-ctl cj@172.24.4.131` (key `~/.ssh/cloudjudge`), `ip_forward=1`, ra Internet, Tailscale đã cài (chưa auth).
- 29/10 chiều (A): kiểm từ laptop qua Tailscale route: Horizon `http://10.10.0.10` (302), Keystone, Swift `healthcheck`, SSH bastion qua `172.24.4.131` đều thông. B, C chỉ cần vào Tailscale là truy cập được.
- **Bàn giao cho B, C (khi có SSH key của họ):** `sudo bash ~/cloudjudge/infra/bootstrap/05-add-user.sh trong trong "<pubkey>"` và `... phuong phuong "<pubkey>"` trên controller. Sau đó họ `ssh cj-controller`, thấy `~/.config/openstack/clouds.yaml` (cloud `cloudjudge`), đọc `~/secrets/*.env` qua group `cj`. Dùng: `OS_CLOUD=cloudjudge openstack stack list`.
- 29/10 chiều (A): **Đã tắt cụm** (`CJ_ME=A gcp-down.sh`, đã kiểm không ai dùng) và chụp **snapshot mốc `m2-20261029`** (5 đĩa, `infra/gcp/snapshot.sh`): `ctl-boot` 7,4 GiB, `ctl-cinder` ~0, `ctl-swift` ~0, `c1-boot` 5,7 GiB, `c2-boot` 4,8 GiB, tổng ~18 GiB (~1,2 USD/tháng). Trạng thái tại mốc này: OpenStack 2025.2 + Swift cài tay + project/user/app cred/ACL + stack `cj-net`. Khôi phục: tạo đĩa từ snapshot rồi gắn lại (hoặc tạo lại VM từ đĩa), xem `infra/README.md`.
