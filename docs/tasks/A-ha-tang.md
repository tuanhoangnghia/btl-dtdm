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
- PROJECT_ID: `…` · BILLING_ID: `…` · CTL_IP: `…`
- Tailscale controller: `…` · bastion: `…`
- Phiên bản Kolla-Ansible thực tế: `…`
- Tổng giờ chạy cụm: `…` / 300

## Tiến độ
- [ ] Repo + Tailscale + IAM cho B, C
- [ ] Phase 1 GCP (`/dev/kvm` OK trên 3 máy)
- [ ] Phase 2 host
- [ ] Phase 3 Kolla deploy, service đều up
- [ ] Phase 4 smoke test qua
- [ ] User/app cred/Swift ACL/`infra.env`
- [ ] Stack `cj-net` + bastion Tailscale → **bàn giao**
- [ ] DNAT cổng 80
- [ ] Minh chứng HM 1, 2, 5 + failover amphora
- [ ] Báo cáo phần A, README

## Nhật ký
- 
