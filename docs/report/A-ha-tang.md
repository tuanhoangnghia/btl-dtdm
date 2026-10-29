# Phần A – Hạ tầng đám mây, mạng, phân quyền (bản nháp 29/10/2026)

> Hạng mục phụ trách: **1** (mạng riêng 2 AZ), **2** (máy chủ ứng dụng trong subnet riêng), **5** (IAM, không nhúng khóa).
> Minh chứng chạy thật nằm trong `docs/evidence/A-*.txt`. Phần này sẽ được bổ sung số liệu và ảnh chụp màn hình ở bước tập demo.

## 1. Dựng OpenStack trên GCP: các quyết định kỹ thuật

| Vấn đề | Lựa chọn | Lý do |
|---|---|---|
| "Phần cứng" | 3 VM GCE (1 controller n2-highmem-4, 2 compute n2-highmem-2) | Laptop không chứa nổi cụm; GCE tính theo giây, tắt được, 2 zone → 2 AZ tách biệt thật |
| Chạy VM bên trong VM | Bật **nested virtualization** lúc tạo máy, Nova `virt_type=kvm` | Không có KVM thì VM chậm 5–10 phút; có KVM, VM OpenStack lên **ACTIVE sau 18–20 giây** (đo ở smoke test) |
| Công cụ cài | **Kolla-Ansible 21.3.0 (2025.2)** | Cấu hình lưu Git, cài lại được. Bản 2024.2 bị loại: image đã bị gỡ khỏi quay.io |
| Mạng ảo | Neutron ML2/**Open vSwitch** | Octavia kiểu `tenant` (không cần VLAN vật lý, cần trên GCE) chỉ hỗ trợ OVS |
| Mạng external | Cặp **veth** `veth-host` (172.24.4.1) ↔ `veth-ex` gắn `br-ex`; controller MASQUERADE ra Internet, DNAT cổng 80 vào floating IP của LB | GCE không cho L2/ARP tự do và không cấp được dải IP public cho floating IP |
| MTU | VPC 1500 → mạng tenant (VXLAN) **1450** | Tránh lỗi MTU ngầm; đã kiểm bằng ping gói 1400B chéo AZ |
| Object storage | **Swift cài tay** từ gói Ubuntu, xác thực Keystone | Kolla bỏ role Swift từ 2025.1. Giữ Swift để có ACL theo danh tính Keystone (hạng mục 5) |
| Cân bằng tải | Octavia ACTIVE_STANDBY, ảnh amphora **tự build từ stable/2025.2** | Ảnh dựng sẵn build từ master có thể lệch agent |
| AZ | Host aggregate `az1` = os-compute-1 (zone a), `az2` = os-compute-2 (zone b) | Mỗi AZ OpenStack ứng với 1 zone GCE thật |
| Truy cập quản trị | Tailscale (quảng bá 10.10.0.0/24 và 172.24.4.0/24) | IP nhà thay đổi thất thường nên firewall theo IP không ổn định; không mở cổng quản trị ra Internet |

## 2. Hạng mục 1 – Mạng riêng, subnet công khai/riêng tư, 2 AZ
- Stack Heat `cj-net`: `net-public` 10.0.1.0/24 (công khai: LB, bastion), `net-app` 10.0.2.0/24 và `net-data` 10.0.3.0/24 (riêng tư), 1 router `cj-router` có SNAT.
- 2 AZ: `az1` (os-compute-1, zone `asia-southeast1-a`) và `az2` (os-compute-2, zone `asia-southeast1-b`).
- Minh chứng: `docs/evidence/A-demo-checks.txt` (network list, subnet list, router, availability zone list), `A-smoke-test-vm.txt` (VM ở cả az1 và az2).

## 3. Hạng mục 2 – Máy chủ ứng dụng trong subnet riêng
- Chỉ **bastion** (và VIP của LB) có floating IP. Web, worker, RabbitMQ, MySQL nằm trong `net-app`/`net-data`, không có IP công khai.
- 6 security group theo nguyên tắc tối thiểu (xem `heat/cj-net.yaml`):
  - `sg-web`: 8000 chỉ từ dải amphora `10.0.1.0/24`. Amphora đi tới web **qua router**, nên máy chấm (10.0.2.x) gọi thẳng web bị chặn.
  - `sg-db`: 3306 chỉ từ `sg-web`, `sg-worker` và chính nó (replication). `sg-mq`: 5672 chỉ từ web và worker.
  - `sg-monitor`: Grafana/Prometheus/Alertmanager chỉ từ `sg-bastion`.
- Bastion: SSH chỉ từ 172.24.4.1/32 (controller); thường ngày vào bằng Tailscale.
- Minh chứng: `A-demo-checks.txt` (floating IP list, rule theo tên security group). Phần "từ máy chấm curl thẳng web bị chặn" chạy khi có stack `cj-app`.

## 4. Hạng mục 5 – Phân quyền bằng IAM, không nhúng khóa
- 4 danh tính Keystone, mỗi danh tính 1 **application credential** (tương đương IAM role / instance profile):

| Danh tính | Role | Quyền Swift |
|---|---|---|
| `cj-web` | member | ghi `submissions`, `testcases` |
| `cj-worker` | reader | **chỉ đọc** `submissions`, `testcases`, `releases` (qua ACL) |
| `cj-backup` | reader | đọc `releases`; đọc/ghi `backups` |
| `cj-monitor` | reader | không đọc được dữ liệu; dùng để liệt kê máy (service discovery) |

- Secret truyền vào VM qua tham số `hidden: true` của Heat; không có trong Git (đã quét `git grep`, không thấy khóa).
- Minh chứng (`docs/evidence/A-acl-test.txt`): worker đọc được, nhưng **xóa object và ghi vào `submissions`/`backups` đều bị 403**; monitor đọc dữ liệu bị 403.

## 5. Kết quả smoke test (mốc quyết định)
| Kiểm tra | Kết quả |
|---|---|
| 2 VM ở az1/az2 lên ACTIVE | 18 giây và 18 giây (yêu cầu < 90 giây) |
| VM ra Internet (ping, DNS, HTTP) | đạt |
| VM gọi Keystone và Swift | đạt |
| MTU tenant / ping chéo AZ gói 1400B | 1450 / đạt |
| LB Octavia ACTIVE_STANDBY | MASTER + BACKUP ở 2 host khác nhau |
| Cụm tự khởi động lại sau khi tắt/bật | đạt (sau khi sửa `octavia-interface`) |

## 6. Giới hạn và rủi ro đã biết (cho mục Giới hạn của báo cáo)
- **Controller là điểm lỗi đơn** (1 node chạy API, DB, Swift, router). Hỏng thì cả cụm dừng.
- **Swift chỉ 1 bản sao** (`replicas=1`) trên 1 đĩa: không chịu được lỗi đĩa. Dữ liệu quan trọng đã được backup lên Swift nhưng cùng 1 đĩa; bù bằng snapshot đĩa GCE.
- Compute là máy ảo lồng nên hiệu năng thấp hơn máy thật; số bài trong demo được chọn sau khi tập thử.
- CPU vật lý cố định (4 vCPU compute): thêm máy chấm tăng thông lượng khi bài chấm chủ yếu chờ I/O, không tăng vô hạn.
- Image Kolla 2024.2 bị gỡ khỏi registry: cụm chỉ dựng lại được trên bản còn image (hiện 2025.2). Nên lưu image đã kéo bằng snapshot đĩa.
- Quota SSD 250 GB của vùng giới hạn kích thước đĩa; không thể mở rộng đĩa compute.

## 7. Những lỗi gặp khi dựng và cách xử lý (bài học)
Xem Nhật ký 29/10 trong `docs/tasks/A-ha-tang.md`: image 2024.2 bị gỡ, Swift bị bỏ khỏi Kolla, ProxySQL chiếm cổng 3306, thiếu `dhclient` cho Octavia, `octavia-interface` chạy quá sớm sau reboot, IP nhà đổi làm SSH bị chặn.
