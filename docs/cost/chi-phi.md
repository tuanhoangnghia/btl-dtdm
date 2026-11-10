# Chi phí CloudJudge (hạng mục 8)

> Chủ: C. Tỷ giá **1 USD ≈ 26.000 đ**. Giá GCP **lấy thẳng từ Cloud Billing Catalog API** (bảng giá chính thức, USD, tra 10/11/2026, xem mục 5).
> Giá AWS theo trang tổng hợp giá, còn phải kiểm lại bằng [AWS Pricing Calculator](https://calculator.aws/) trước khi chốt báo cáo.
> Chi phí **thật** lấy từ Billing → Reports của project `omega-dahlia-468315-f6` (mục 2); tài khoản của C xem được billing account `01BE00-008CAB-253DE8`.

## 1. Đơn giá dùng trong bảng

| Thứ (vùng) | Đơn giá | Ghi chú |
|---|---|---|
| N2 vCPU / RAM (asia-southeast1) | 0,038999 USD/vCPU-giờ · 0,005226 USD/GiB-giờ | giá N2 tính theo vCPU + RAM |
| GCE n2-highmem-4 (4 vCPU, 32 GiB) | **0,3232 USD/giờ** | controller (4 × 0,038999 + 32 × 0,005226) |
| GCE n2-highmem-2 (2 vCPU, 16 GiB) | **0,1616 USD/giờ** | 2 compute |
| Giảm giá dùng liên tục (SUD) N2 | tối đa **20 %** khi chạy đủ tháng | tự động, không cần cam kết |
| Cam kết 1 năm (CUD) N2 | 37 % (0,024567 USD/vCPU-giờ · 0,003292 USD/GiB-giờ) | chỉ dùng cho kịch bản tham khảo |
| IP ngoài đang gắn VM | 0,005 USD/giờ/IP | controller (static) + 2 compute (ephemeral). Catalog ghi bậc 0–720 giờ/tháng giá 0 (có thể là ưu đãi theo billing account); bảng này vẫn tính 0,005 cho chắc |
| IP static để không (máy tắt) | 0,011 USD/giờ | `cj-ctl-ip` vẫn tính khi cụm tắt |
| pd-balanced | 0,110 USD/GiB-tháng | tính **cả khi máy tắt** |
| pd-standard | 0,044 USD/GiB-tháng | đĩa Swift + 2 đĩa của VM cũ |
| Snapshot standard, lưu ở vùng asia-southeast1 | 0,061 USD/GiB-tháng | tính theo dung lượng thật đã lưu (không theo cỡ đĩa); lưu đa vùng `asia` là 0,083 |
| Egress Internet Singapore → APAC (gồm VN) | 0,12 USD/GiB (1 TiB đầu) | demo chỉ vài GB |
| AWS EC2 t3.small (ap-southeast-1) | 0,0264 USD/giờ | 2 vCPU, 2 GB |
| AWS NAT Gateway | 0,059 USD/giờ + 0,059 USD/GB | |
| AWS ALB | ≈ 0,0252 USD/giờ + ≈ 0,008 USD/LCU-giờ | |
| AWS RDS MySQL db.t3.micro Multi-AZ | ≈ 0,056 USD/giờ | gấp đôi Single-AZ (0,028) |

## 2. Chi phí thật của dự án (trên tín dụng dùng thử GCP)

Tài nguyên thật trong project (đọc bằng `gcloud compute disks/snapshots/addresses list` ngày 10/11/2026):
- pd-balanced **246 GiB**: `os-controller` 100 + `os-controller-cinder` 50 + `os-compute-1` 48 + `os-compute-2` 48.
- pd-standard **90 GiB**: `os-controller-swift` 30 + **2 đĩa của 2 VM cũ** `compute`, `controller` (zone b, 30 GiB mỗi cái, máy TERMINATED từ 28/09 nhưng đĩa vẫn tính tiền).
- Snapshot mốc `m2` (29/10, 5 cái, lưu ở asia-southeast1): dung lượng thật **≈ 17,9 GiB** (ctl-boot 7,4 + c1-boot 5,7 + c2-boot 4,8; cinder và swift gần 0).
- 1 IP static `cj-ctl-ip`.

| Khoản | Cách tính | Ước tính |
|---|---|---|
| Cụm **đang chạy** | 0,3232 + 2 × 0,1616 + 3 × 0,005 (IP) | **≈ 0,66 USD/giờ ≈ 17.200 đ/giờ** |
| Cụm **đang tắt** (vẫn tính) | đĩa 246 × 0,11 + 90 × 0,044 = 31,0 USD/tháng; snapshot 17,9 × 0,061 = 1,1 USD/tháng; IP static 0,011 × 24 | **≈ 1,32 USD/ngày ≈ 34.000 đ/ngày** |
| Trong đó: 2 đĩa VM cũ | 60 × 0,044 = 2,64 USD/tháng | ≈ 0,09 USD/ngày ≈ 2.300 đ/ngày (≈ 69.000 đ/tháng): xóa được nếu nhóm không cần |
| Dự kiến 28/10 → 22/11 (26 ngày), ~150 giờ chạy | 150 × 0,66 + 26 × 1,32 | **≈ 133 USD ≈ 3,5 triệu đ** |

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
| 3 VM (giá niêm yết) | 0,6465 × 730 = 471,9 | |
| 3 VM sau SUD 20 % | 471,9 × 0,8 | **377,5** |
| Đĩa (không tính 2 đĩa VM cũ) | 246 × 0,11 + 30 × 0,044 | 28,4 |
| 3 IP ngoài | 3 × 0,005 × 730 | 11,0 |
| Snapshot + egress | 17,9 × 0,061 + 20 GB × 0,12 | 3,5 |
| **Hạ tầng** | | **≈ 420 USD ≈ 10,9 triệu đ** |
| Nhân lực | 20 % kỹ sư (vận hành cả lớp OpenStack) | 4,0 triệu đ |
| **Tổng** | | **≈ 14,9 triệu đ** |

Nếu cam kết 1 năm (CUD 37 %): VM ≈ 297 USD → tổng ≈ 12,8 triệu đ.

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

## 5. Nguồn giá
- **GCP (tra 10/11/2026)**: [Cloud Billing Catalog API](https://cloud.google.com/billing/docs/reference/rest/v1/services.skus/list), dịch vụ Compute Engine `6F81-5844-456A`, `currencyCode=USD`. Đây là bảng giá chính thức mà Pricing Calculator cũng dùng. Các SKU đã dùng: `N2 Instance Core/Ram running in Singapore`, `Commitment v1: N2 Cpu/Ram in Singapore for 1 Year`, `Balanced PD Capacity in Singapore`, `Storage PD Capacity in Singapore`, `Storage PD Snapshot in Singapore`, `Static Ip Charge in Singapore`, `External IP Charge on a Standard VM`, `Network Internet Data Transfer Out from Singapore to Apac(Excluding Korea and Indonesia)`.
  Lệnh lấy lại: `curl -H "Authorization: Bearer $(gcloud auth print-access-token)" "https://cloudbilling.googleapis.com/v1/services/6F81-5844-456A/skus?currencyCode=USD&pageSize=5000"` (lặp theo `nextPageToken`).
- Bản đề xuất tính snapshot ≈ 0,029 USD/GB-tháng và pd-standard ≈ 0,048; giá thật ở Singapore là 0,061 và 0,044. Tổng gần như không đổi vì snapshot chỉ ~18 GiB.
- SUD N2 tối đa 20 %: [Sustained use discounts](https://cloud.google.com/compute/docs/sustained-use-discounts).
- AWS t3.small ap-southeast-1: [doit.com](https://www.doit.com/compute/spot/ap-southeast-1/t3.small); NAT Gateway: [egresscost.com](https://egresscost.com/aws/ap-southeast-1); RDS db.t3.micro: [bytebase.com](https://www.bytebase.com/dbcost/rds/instance/db.t3.micro/)
