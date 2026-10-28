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
- Tailscale controller: `cj-controller` = `100.98.68.95` · bastion: `…`
- Phiên bản Kolla-Ansible thực tế: `…`
- Tổng giờ chạy cụm: `~1,2` / 300 (cập nhật 28/10 tối)

## Tiến độ
- [ ] Repo + Tailscale + IAM cho B, C  (chưa: repo chưa push, Tailscale chưa tạo, B/C chưa có quyền GCP)
- [x] Phase 1 GCP (`/dev/kvm` OK trên 3 máy, 28/10) — budget alert chưa đặt (xem Nhật ký)
- [x] Phase 2 host (28/10): veth, NAT, LVM, đĩa Swift, Tailscale controller, SSH key Kolla. **Còn việc tay:** duyệt 2 subnet route trong Tailscale admin
- [ ] Phase 3 Kolla deploy, service đều up
- [ ] Phase 4 smoke test qua
- [ ] User/app cred/Swift ACL/`infra.env`
- [ ] Stack `cj-net` + bastion Tailscale → **bàn giao**
- [ ] DNAT cổng 80
- [ ] Minh chứng HM 1, 2, 5 + failover amphora
- [ ] Báo cáo phần A, README

## Nhật ký
- 28/10 tối (A): Phase 1 xong. VPC `cj-vpc` MTU 1500, subnet 10.10.0.0/24, 4 firewall rule, IP tĩnh `34.124.240.64`. 3 máy tạo xong, đều có `/dev/kvm` (vmx > 0), `ens4`, ra Internet được; controller có `/dev/disk/by-id/google-cinder` (50G) và `google-swift` (30G). SSH vào qua `ssh cj-ctl` / `cj-c1` / `cj-c2` (key `~/.ssh/cloudjudge`). Đã **tắt cả 3 máy**; bật lại bằng `bash infra/gcp/gcp-up.sh`.
- 28/10 tối (A): quota SSD vùng chỉ 250 GB → đổi đĩa Swift sang pd-standard, boot compute 48 GB (xem mục Thông tin cụm).
- 28/10 tối (A): **chưa đặt budget alert**: tài khoản `hoangnghiatuan297@gmail.com` không liệt kê được billing account và Billing Budgets API chưa bật. Việc cần làm tay trong Console → Billing → Budgets: cảnh báo 50/75/90% của ~₫7,7 triệu.
- 28/10 tối (A): Phase 2 xong, đã kiểm: `veth-host` 172.24.4.1/24 UP, `cj-nat.service` active (MASQUERADE 172.24.4.0/24), `vgs` có `cinder-volumes` 50G, đĩa Swift có partition `KOLLA_SWIFT_DATA` + XFS label `d0`, controller SSH được sang cả 3 IP bằng key riêng (`cj@os-controller`, đã thêm vào metadata project). Tailscale controller vào tailnet (hostname `cj-controller`, `100.98.68.95`), đang quảng bá 10.10.0.0/24 và 172.24.4.0/24 (**chờ duyệt route ở admin console**). Script: `infra/host/`. Đã tắt cụm sau khi xong.
- 28/10 tối (A): thêm cơ chế khóa dùng cụm để tránh bị tắt giữa chừng: `infra/gcp/cj-lock.sh acquire|release|status|check` (khóa lưu ở metadata project, tự hết hạn sau 4 giờ, lý do tự bỏ dấu). `gcp-down.sh` từ chối tắt nếu người KHÁC đang giữ khóa (đặt `CJ_ME=A|B|C`; `FORCE=1` để tắt cưỡng bức sau khi đã hỏi nhóm). **Đề xuất sửa CONTRACT mục 3.2** (cần cả 3 đồng ý): bắt buộc giữ khóa khi làm việc và chỉ tắt cụm bằng `gcp-down.sh`, không chạy `gcloud compute instances stop` trực tiếp.
