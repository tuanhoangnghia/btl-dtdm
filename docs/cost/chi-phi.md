# Chi phí CloudJudge (hạng mục 8)

> Chủ: C. Tỷ giá **1 USD ≈ 26.000 đ**. Giá **ước tính** theo bảng giá công khai và trang tổng hợp giá (tra ngày 09/11/2026, xem mục 5),
> phải **kiểm lại bằng [GCP Pricing Calculator](https://cloud.google.com/products/calculator) và [AWS Pricing Calculator](https://calculator.aws/)** trước khi chốt báo cáo.
> Chi phí **thật** lấy từ Billing của project `omega-dahlia-468315-f6` (mục 2), cần A chụp nếu C không có quyền xem billing.

## 1. Đơn giá dùng trong bảng

| Thứ (vùng) | Đơn giá | Ghi chú |
|---|---|---|
| GCE n2-highmem-4 (asia-southeast1) | **0,323 USD/giờ** | controller |
| GCE n2-highmem-2 (asia-southeast1) | **≈ 0,1615 USD/giờ** | 2 compute; bằng một nửa n2-highmem-4 (giá N2 tính theo vCPU + GB RAM) |
| Giảm giá dùng liên tục (SUD) N2 | tối đa **20 %** khi chạy đủ tháng | tự động, không cần cam kết |
| Cam kết 1 năm (CUD) N2 | ≈ 37 % | chỉ dùng cho kịch bản tham khảo |
| IP ngoài đang gắn VM | 0,005 USD/giờ/IP | controller (static) + 2 compute (ephemeral) |
| IP static để không (máy tắt) | 0,010 USD/giờ | `cj-ctl-ip` vẫn tính khi cụm tắt |
| pd-balanced | ≈ 0,11 USD/GB-tháng | tính **cả khi máy tắt** |
| pd-standard | ≈ 0,048 USD/GB-tháng | đĩa Swift |
| Snapshot (standard) | ≈ 0,029 USD/GB-tháng | |
| Egress Internet (châu Á) | ≈ 0,12 USD/GB | demo chỉ vài GB |
| AWS EC2 t3.small (ap-southeast-1) | 0,0264 USD/giờ | 2 vCPU, 2 GB |
| AWS NAT Gateway | 0,059 USD/giờ + 0,059 USD/GB | |
| AWS ALB | ≈ 0,0252 USD/giờ + ≈ 0,008 USD/LCU-giờ | |
| AWS RDS MySQL db.t3.micro Multi-AZ | ≈ 0,056 USD/giờ | gấp đôi Single-AZ (0,028) |

## 2. Chi phí thật của dự án (trên tín dụng dùng thử GCP)

Đĩa thật của cụm (theo `docs/tasks/A-ha-tang.md`): pd-balanced 246 GB (controller 100 + cinder 50, 2 compute × 48), pd-standard 30 GB (swift), snapshot mốc `m2` ~18 GiB.

| Khoản | Cách tính | Ước tính |
|---|---|---|
| Cụm **đang chạy** | 0,323 + 2 × 0,1615 + 3 × 0,005 (IP) | **≈ 0,66 USD/giờ ≈ 17.200 đ/giờ** |
| Cụm **đang tắt** (vẫn tính) | đĩa 246 × 0,11 + 30 × 0,048 = 28,5 USD/tháng; IP static 0,01 USD/giờ; snapshot 18 × 0,029 | **≈ 1,2 USD/ngày ≈ 31.000 đ/ngày** |
| Dự kiến 28/10 → 22/11 (26 ngày), ~150 giờ chạy | 150 × 0,66 + 26 × 1,2 | **≈ 130 USD ≈ 3,4 triệu đ** |

Theo dõi số thật (điền từ Billing → Reports, lọc project `omega-dahlia-468315-f6`):

| Đến ngày | Tổng giờ chạy cụm | Tín dụng đã dùng (đ) | Ghi chú |
|---|---|---|---|
| 29/10 | ~10,5 (nhật ký A) | … | Kolla deploy, smoke test |
| … | … | … | |
| Ngày nộp | … | … | ảnh chụp Billing để vào báo cáo |

Tín dụng ban đầu ₫7.730.577 (≈ 297 USD), hết hạn ~23/12/2026. Quy tắc: tổng giờ chạy ≤ 300, tắt bằng `infra/gcp/gcp-down.sh` (KE_HOACH mục 1).

## 3. Ba phương án chạy thật 24/7 (mỗi tháng, ~730 giờ)

Quy mô như demo: 2–3 web, 1–3 worker (trung bình ~1,2), MySQL primary + replica, hàng đợi, giám sát. Nhân lực tính theo kỹ sư 20 triệu đ/tháng.

### 3.1. OpenStack trên 3 VM GCP (như demo)

| Khoản | Cách tính | USD/tháng |
|---|---|---|
| 3 VM (giá niêm yết) | 0,646 × 730 = 471,6 | |
| 3 VM sau SUD 20 % | 471,6 × 0,8 | **377,3** |
| Đĩa | 246 × 0,11 + 30 × 0,048 | 28,5 |
| 3 IP ngoài | 3 × 0,005 × 730 | 11,0 |
| Snapshot + egress | 18 × 0,029 + 20 GB × 0,12 | 2,9 |
| **Hạ tầng** | | **≈ 420 USD ≈ 10,9 triệu đ** |
| Nhân lực | 20 % kỹ sư (vận hành cả lớp OpenStack) | 4,0 triệu đ |
| **Tổng** | | **≈ 14,9 triệu đ** |

Nếu cam kết 1 năm (CUD ~37 %): VM ≈ 297 USD → tổng ≈ 12,8 triệu đ.

### 3.2. OpenStack trên 3 máy chủ cũ của trường

| Khoản | Giả định | triệu đ/tháng |
|---|---|---|
| Khấu hao | 3 máy chủ đã qua sử dụng ≈ 45 triệu, khấu hao 36 tháng | 1,25 |
| Điện | 3 máy trung bình ~450 W → 450 W × 730 giờ ≈ 329 kWh × ~2.450 đ/kWh | 0,80 |
| Internet + IP tĩnh | gói doanh nghiệp nhỏ | 0,50 |
| Linh kiện thay thế | ổ đĩa, quạt (dự phòng ~2,2 triệu/năm) | 0,18 |
| Nhân lực | 20 % kỹ sư | 4,00 |
| **Tổng** | | **≈ 6,7 triệu đ** |

Chưa tính: chỗ đặt máy, điều hòa, UPS; rủi ro phần cứng cũ (không có AZ thật nếu 3 máy cùng phòng).

### 3.3. Dùng thẳng AWS (Singapore), thiết kế đổi 1–1

| Thành phần CloudJudge | Dịch vụ AWS | Cách tính | USD/tháng |
|---|---|---|---|
| 2 web (ASG) | EC2 t3.small × 2 | 2 × 0,0264 × 730 | 38,5 |
| Worker trung bình 1,2 máy (ASG theo hàng đợi) | EC2 t3.small | 1,2 × 0,0264 × 730 | 23,1 |
| Đĩa EC2 | EBS gp3 8 GB × 3 | | 2,3 |
| Octavia | ALB | 0,0252 × 730 + ~1 LCU | 24,2 |
| Router SNAT | NAT Gateway (1 cái) | 0,059 × 730 + 10 GB | 43,7 |
| MySQL primary + replica | RDS MySQL db.t3.micro **Multi-AZ** + 20 GB | 0,056 × 730 + lưu trữ | 46,4 |
| RabbitMQ | SQS | < 1 triệu request/tháng: gần như miễn phí | ~0 |
| Swift | S3 | ~10 GB + request | 0,4 |
| Prometheus/Alertmanager/Grafana | CloudWatch (metric, alarm, log) | ~10 alarm, ~10 custom metric, 5 GB log | 7,5 |
| Egress | | 20 GB × 0,12 | 2,4 |
| **Hạ tầng** | | | **≈ 189 USD ≈ 4,9 triệu đ** |
| Nhân lực | 5 % kỹ sư (dịch vụ có quản lý) | | 1,0 triệu đ |
| **Tổng** | | | **≈ 5,9 triệu đ** |

Nếu dùng Amazon MQ (RabbitMQ) thay SQS: +~25 USD; NAT Gateway ở cả 2 AZ: +~43 USD → tổng ≈ 7,7 triệu đ.

### 3.4. So sánh

| Phương án | triệu đ/tháng | Nhận xét |
|---|---|---|
| AWS (Singapore) | **≈ 5,9** | Rẻ nhất khi tính cả nhân lực; có Multi-AZ thật, không phải vận hành lớp ảo hóa |
| OpenStack trên máy chủ trường | ≈ 6,7 | Rẻ phần hạ tầng nhưng nhân lực và rủi ro phần cứng cao |
| OpenStack trên VM GCP | ≈ 14,9 | Đắt nhất: trả tiền cho cả lớp ảo hóa lồng (VM trong VM); chỉ hợp lý để học |

**Đối chiếu với bản đề xuất:** đề xuất ghi 14,8 / 6,7 / 5,4–6,2 triệu. Số mới: 14,9 / 6,7 / ≈ 5,9 (nằm trong khoảng đã đề xuất). Phần AWS tăng nhẹ vì giá RDS Multi-AZ ≈ 0,056 USD/giờ và tính worker trung bình 1,2 máy. Kết luận giữ nguyên.

## 4. Vì sao GCP-OpenStack đắt (dùng khi vấn đáp)
- Trả tiền cho **3 máy cố định chạy 24/7** bất kể tải; còn AWS ASG chỉ trả cho số máy đang chạy.
- **Ảo hóa lồng**: một phần CPU/RAM của VM GCP dùng cho Nova, Neutron, Octavia, Kolla chứ không chạy ứng dụng.
- Thiết kế này tối ưu cho **học** (tự dựng IaaS), không tối ưu chi phí. Ở quy mô một môn học, dịch vụ có quản lý (PaaS: RDS, SQS, ALB) có **TCO** thấp hơn vì nhân lực chiếm phần lớn.

## 5. Nguồn giá (tra 09/11/2026, cần kiểm lại)
- GCP n2-highmem-4, asia-southeast1 ≈ 0,323 USD/giờ: [devzero.io](https://www.devzero.io/instances/gcp/n2-highmem-4), [cloud-mercato](https://pcr.cloud-mercato.com/providers/google/flavors/n2-highmem-4.cascadelake)
- GCP IP, đĩa, snapshot: [VPC network pricing](https://cloud.google.com/vpc/network-pricing), [Disk and image pricing](https://cloud.google.com/compute/disks-image-pricing) (số trong bảng là ước tính, chưa đọc được bảng theo vùng)
- AWS t3.small ap-southeast-1: [doit.com](https://www.doit.com/compute/spot/ap-southeast-1/t3.small); NAT Gateway: [egresscost.com](https://egresscost.com/aws/ap-southeast-1); RDS db.t3.micro: [bytebase.com](https://www.bytebase.com/dbcost/rds/instance/db.t3.micro/)
