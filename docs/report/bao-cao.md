# CloudJudge: hệ thống nộp bài và chấm code tự động trên OpenStack tự dựng

> **Báo cáo chính** (C ghép, KE_HOACH 14.4). Nội dung lấy từ phần của từng người (`A-ha-tang.md`, `B-ung-dung.md` trên nhánh `b/app-phase1`,
> `C-du-lieu-giam-sat.md`) và bản đề xuất. Ai sửa phần mình thì sửa file của mình, C chép lại vào đây trước khi xuất PDF.
> Hạn nộp: **22/11/2026** (báo cáo + mã nguồn + video). Ô **⏳** = chờ số liệu/ảnh chạy trên cụm. Khối trích dẫn (`>`) là ghi chú nội bộ, xóa khi xuất PDF.

| # | Mục | Nguồn | Trạng thái (10/11) |
|---|---|---|---|
| 1 | Bài toán | đề xuất mục 2 | ☑ |
| 2 | Kiến trúc | đề xuất mục 3 + A §2–3 + B §1 + C §1 | ◐ thiếu hình PNG cập nhật |
| 3 | Dựng OpenStack trên GCP | A §1, §5, §7 | ☑ |
| 4 | Đối chiếu 8 hạng mục | A, B, C + `docs/evidence/` | ◐ thiếu ảnh, minh chứng cụm của HM 3, 4, 6, 7 |
| 5 | Lý giải lựa chọn công nghệ | đề xuất mục 5 + KE_HOACH mục 2 + A §1 + B §6 + C §6 | ☑ |
| 6 | Kết quả đo | B §7 + C §8 | ◐ thiếu loadtest, số đo cụm |
| 7 | Chi phí | `docs/cost/chi-phi.md` | ◐ thiếu ảnh Billing |
| 8 | Giới hạn | A §6 + B §4 + C §7 | ☑ |
| 9 | Phân công, link | 3 file `docs/tasks/*` | ◐ thiếu link video |

---

Lớp INT3319 3 – Điện toán đám mây · Trường Đại học Công nghệ, ĐHQGHN.

| Họ và tên | Mã sinh viên | Vai trò |
|---|---|---|
| Hoàng Nghĩa Tuấn | 23020877 | A: hạ tầng, mạng, phân quyền (HM 1, 2, 5) |
| Trần Văn Phường | 23020859 | B: ứng dụng, cân bằng tải, tự mở rộng (HM 6) |
| Nguyễn Minh Trọng | 23020893 | C: lưu trữ, CSDL, giám sát, chi phí (HM 3, 4, 7, 8) |

Repo: `https://github.com/tuanhoangnghia/btl-dtdm` · Video demo: ⏳

Nền tảng: **OpenStack** (mức +2 điểm). Nhóm tự cài OpenStack bằng Kolla-Ansible trên 3 máy ảo trống của Google Compute Engine, dùng như 3 máy chủ vật lý; không dùng dịch vụ quản trị sẵn nào của GCP.

## 1. Bài toán

**CloudJudge** cho phép sinh viên các học phần lập trình nộp mã nguồn qua trình duyệt; hệ thống tự biên dịch, chạy bộ test trong môi trường cách ly và trả điểm (mục tiêu dưới 10 giây lúc bình thường, dưới 2 phút lúc cao điểm). Giảng viên, trợ giảng dùng để tạo bài, tải bộ test và xem bảng điểm thay vì chấm tay.

**Vì sao cần đám mây:** tải rất lệch. Bình thường chỉ vài bài mỗi giờ, nhưng 30 phút trước hạn nộp có thể tới khoảng 300 bài (10 bài/phút). Một máy chấm xử lý khoảng 7 bài/phút (đo trên cụm với bài `slow-sum`), nên hệ thống tự thêm máy chấm khi hàng đợi dài (tối đa 3) và thu về 1 máy khi vắng. Web/API và bộ cân bằng tải đặt ở hai AZ trên hai zone vật lý khác nhau, nên một máy hỏng không làm dừng dịch vụ.

## 2. Kiến trúc

> ⏳ Hình 1 (PNG) cần vẽ lại từ hình của bản đề xuất, thêm lớp dữ liệu và giám sát, lưu `docs/report/img/kien-truc.png`. Sơ đồ chữ dưới đây là nội dung của hình.

```
                                   Internet
                                       │ HTTP :80 (IP tĩnh của controller, DNAT vào floating IP của LB)
┌─ project cloudjudge ─────────────────┼────────────────────────────────────────────────────────────────────┐
│ net-public 10.0.1.0/24 (công khai)   ▼                                                                    │
│   Octavia LB ACTIVE_STANDBY (2 amphora, 2 host)          bastion (floating IP, vào bằng Tailscale)        │
│        │ health check GET /healthz                                                                        │
│ ───────┼──────────────── cj-router (SNAT ra Internet) ────────────────────────────────────────────────── │
│ net-app 10.0.2.0/24 (riêng tư)                                                                            │
│   web az1 (1–2 máy) + web az2 (1 máy)   ──5672──►  RabbitMQ 10.0.2.10 (az2, Cinder)                       │
│   worker ×1–3 (ASG, rải 2 host)         ◄─────────┘ queue submissions (durable)                           │
│   monitor 10.0.2.11 (az1): Prometheus ─ openstack_sd ─► mọi VM; Alertmanager ─► Gmail + alarm_url của Heat │
│ net-data 10.0.3.0/24 (riêng tư)                                                                           │
│   MySQL Primary 10.0.3.10 (az1, Cinder) ──binlog GTID──► MySQL Replica 10.0.3.11 (az2, Cinder)            │
│   Swift: submissions, testcases, releases, backups (object)                                               │
└───────────────────────────────────────────────────────────────────────────────────────────────────────────┘
 Hạ tầng bên dưới: os-controller (n2-highmem-4, zone a) · os-compute-1 = az1 (zone a) · os-compute-2 = az2 (zone b)
```

**Luồng một bài nộp:**
1. Người dùng gửi bài qua LB. LB chia tải sang web ở az1 hoặc az2 (ROUND_ROBIN), loại máy web hỏng sau 2 lần health check lỗi.
2. Web lưu mã nguồn lên Swift `submissions/<uuid>/`, ghi bản ghi `PENDING` vào MySQL Primary, đẩy `{"submission_id"}` vào RabbitMQ (publisher confirm, message persistent).
3. Một worker nhận bài (`prefetch_count=1`), tải mã và bộ test từ Swift, chấm từng test trong container sandbox không mạng, ghi kết quả vào Primary rồi mới ack (at-least-once, cập nhật idempotent).
4. Trang `/scoreboard` đọc từ **Replica** bằng user chỉ đọc `cj_ro`.
5. Prometheus đọc độ dài hàng đợi. Hàng đợi dài thì Alertmanager gọi `alarm_url` của Heat để thêm worker và gửi email; hàng đợi rỗng thì bớt worker.

**Hạ tầng bên dưới:** os-controller (n2-highmem-4: 4 vCPU, 32 GB, zone a) chạy các API, Swift, Cinder, Heat, Octavia và router; os-compute-1 (zone a) làm AZ-1, os-compute-2 (zone b) làm AZ-2, mỗi máy n2-highmem-2 (2 vCPU, 16 GB). Tổng 8 vCPU, vừa hạn mức tài khoản dùng thử. Toàn bộ tài nguyên trong OpenStack do 4 stack Heat dựng: `cj-net` (A), `cj-app` (B), `cj-data` và `cj-mon` (C).

| Thành phần | Công nghệ | Chạy ở |
|---|---|---|
| Web/API | Flask 3 + Gunicorn, SQLAlchemy Core | VM `cj.small`, 2–3 máy, systemd |
| Worker | Python, pika, Docker CLI; sandbox `cj-sandbox:1` | VM `cj.medium`, 1–3 máy |
| Hàng đợi | RabbitMQ 4.1 (container) | 1 VM, dữ liệu trên volume Cinder |
| CSDL | MySQL 8.4 (container), Primary → Replica GTID | 2 VM ở 2 AZ, mỗi máy 1 volume Cinder |
| Giám sát | Prometheus, Alertmanager, Grafana (container) | 1 VM monitor |
| Image | 1 golden image `cj-base-v1` cho mọi vai trò; mã app tải từ Swift `releases` khi boot | |

## 3. Dựng OpenStack trên GCP

| Vấn đề | Lựa chọn | Lý do |
|---|---|---|
| "Phần cứng" | 3 VM GCE (1 controller n2-highmem-4, 2 compute n2-highmem-2) | Laptop không chứa nổi cụm; GCE tính theo giây, tắt được; 2 zone → 2 AZ tách biệt thật |
| Chạy VM bên trong VM | Bật **nested virtualization** lúc tạo máy, Nova `virt_type=kvm` | Không có KVM thì VM boot 5–10 phút; có KVM, VM OpenStack lên **ACTIVE sau 18–20 giây** |
| Công cụ cài | **Kolla-Ansible 21.3.0 (2025.2)** | Cấu hình lưu Git, cài lại được. Bản 2024.2 dự định ban đầu bị loại vì image đã bị gỡ khỏi quay.io |
| Mạng ảo | Neutron ML2/**Open vSwitch** | Octavia kiểu `tenant` (không cần VLAN vật lý, mà GCE không có) chỉ hỗ trợ OVS |
| Mạng external | Cặp **veth** `veth-host` (172.24.4.1) ↔ `veth-ex` gắn `br-ex`; controller MASQUERADE ra Internet, DNAT cổng 80 vào floating IP của LB | GCE không cho L2/ARP tự do và không cấp được dải IP public cho floating IP |
| MTU | VPC 1500 → mạng tenant (VXLAN) **1450** | Tránh lỗi MTU ngầm; đã kiểm bằng ping gói 1400 B chéo AZ |
| Object storage | **Swift cài tay** từ gói Ubuntu, xác thực Keystone | Kolla bỏ role Swift từ 2025.1. Giữ Swift để có ACL theo danh tính Keystone (HM 5) |
| Cân bằng tải | Octavia ACTIVE_STANDBY, ảnh amphora tự build từ stable/2025.2 | Ảnh dựng sẵn build từ master có thể lệch agent |
| AZ | Host aggregate `az1` = os-compute-1 (zone a), `az2` = os-compute-2 (zone b) | Mỗi AZ OpenStack ứng với 1 zone GCE thật |
| Truy cập quản trị | Tailscale trên controller và bastion | Không mở cổng quản trị ra Internet; IP nhà thay đổi nên firewall theo IP không ổn định |

**Kết quả smoke test (mốc quyết định 29/10):** 2 VM ở az1/az2 lên ACTIVE sau 18 giây (yêu cầu < 90 giây); VM ra Internet, gọi được Keystone và Swift; MTU 1450, ping chéo AZ gói 1400 B đạt; LB Octavia ACTIVE_STANDBY với MASTER và BACKUP ở 2 host khác nhau; cụm tự chạy lại sau khi tắt/bật. Minh chứng: `docs/evidence/A-smoke-test-vm.txt`, `A-smoke-test-octavia.txt`.

**Lỗi gặp khi dựng và cách xử lý:** image Kolla 2024.2 bị gỡ (chuyển sang 2025.2); Swift bị bỏ khỏi Kolla (cài tay); ProxySQL chiếm cổng 3306 làm MariaDB không lên (tắt ProxySQL); Ubuntu 24.04 thiếu `dhclient` cho Octavia; `octavia-interface` chạy quá sớm sau khi khởi động lại (thêm `Restart=on-failure`); Placement hết chỗ đĩa (`DISK_GB`) khi tạo máy thứ 9, dù RAM và CPU còn dư (đặt `disk_allocation_ratio`, vì máy ảo dùng đĩa thin-provisioned).

## 4. Đối chiếu tám hạng mục bắt buộc

| # | Hạng mục | Cách làm trong CloudJudge | Minh chứng |
|---|---|---|---|
| 1 | Mạng riêng, subnet công khai/riêng tư, 2 AZ | Stack `cj-net`: `net-public` 10.0.1.0/24 (LB, bastion), `net-app` 10.0.2.0/24, `net-data` 10.0.3.0/24, 1 router có SNAT. `az1`/`az2` trên 2 zone GCE | `A-demo-checks.txt` (network, subnet, router, AZ); `A-smoke-test-vm.txt`; ảnh Network Topology ⏳ |
| 2 | Máy chủ ứng dụng trong subnet riêng | Chỉ bastion và VIP của LB có floating IP. 6 security group tối thiểu: `sg-web` chỉ nhận 8000 từ dải amphora, `sg-db` chỉ nhận 3306 từ web/worker/replica, `sg-monitor` chỉ từ bastion | `A-demo-checks.txt` (floating IP, rule theo tên SG); worker gọi thẳng web bị timeout ⏳ |
| 3 | Hai loại lưu trữ trở lên | **Swift** (object): mã nộp, bộ test, bản phát hành, bản backup (tự xóa sau 7 ngày). **Cinder** (block): dữ liệu MySQL primary, replica, RabbitMQ; tạo lại VM thì volume cũ được gắn lại | `openstack volume list --long`, `openstack object list` (`C-cluster-evidence.txt` mục 1, 1b) |
| 4 | Cơ sở dữ liệu | MySQL 8.4 tự dựng: Primary (az1) → Replica (az2) bằng GTID; replica `super_read_only`; user tối thiểu (`cj_app` không có DELETE/DDL, `cj_ro` chỉ đọc); backup hằng ngày lên Swift bằng danh tính `cj-backup` | Local: `C-local-replication.txt`, `C-local-timings.txt`. Cụm: `C-cluster-evidence.txt` (ghi primary → đọc replica, replica từ chối ghi, backup + restore qua Swift) |
| 5 | Phân quyền IAM, không nhúng khóa | 4 danh tính Keystone (`cj-web`, `cj-worker`, `cj-backup`, `cj-monitor`), mỗi danh tính 1 application credential giới hạn quyền. Secret truyền qua tham số ẩn của Heat, không có trong Git | `A-acl-test.txt` (worker xóa/ghi object bị 403; monitor đọc dữ liệu bị 403); `git grep` sạch (`A-demo-checks.txt`) |
| 6 | Cân bằng tải, tự mở rộng | Octavia ACTIVE_STANDBY + health check `/healthz`. Web 2–3 máy theo CPU (2 ASG ghim theo AZ), worker 1–3 máy theo độ dài hàng đợi; Alertmanager gọi `alarm_url` của `OS::Heat::ScalingPolicy` | `B-cum-31-10.txt` (alarm_url → thêm/bớt worker); loadtest 60 bài, worker 1→2→3→1, tắt web az1 ⏳ |
| 7 | Giám sát, có cảnh báo | Prometheus tìm VM bằng `openstack_sd` + metadata `cj_role`; 9 luật (QueueHigh, QueueIdle, WebCPUHigh, WebCPULow, SubmissionStuck, InstanceDown, MySQLDown, ReplicationBroken, BackupStale) có unit test; email qua Gmail; dashboard Grafana 20 panel | Local: `C-local-monitoring.txt`, `C-local-replication-broken.txt` (thư thật tới Gmail). Cụm: ảnh Grafana + hộp thư ⏳ |
| 8 | Ước tính chi phí | Chi phí thật trên tín dụng GCP + 3 phương án chạy 24/7, giá GCP lấy từ bảng giá chính thức (Cloud Billing Catalog API) | `docs/cost/chi-phi.md`; ảnh Billing ⏳ |

> Ảnh minh chứng đặt tên `docs/evidence/<A|B|C>-hm<n>-*.png`, chèn dưới bảng này khi xuất PDF.

## 5. Lý giải lựa chọn công nghệ

| Chọn | Thay vì | Lý do |
|---|---|---|
| 3 VM GCP làm phần cứng | Laptop; thuê máy chủ | Laptop 16 GB không chứa nổi cụm; thuê máy chủ tốn 2,5–4 triệu/tháng. GCP tính theo giây, tắt được khi không dùng, nằm trong tín dụng dùng thử; 2 zone cho 2 AZ tách biệt thật |
| Kolla-Ansible | DevStack | Chạy nhiều node, cấu hình lưu Git để cài lại được; DevStack hay hỏng sau khi khởi động lại |
| Octavia | HAProxy tự cài | Có health check HTTP, tự failover active/standby, Heat thêm bớt member trực tiếp |
| Swift + Cinder | Đĩa của VM | Web và worker bị tạo, xóa liên tục nên dữ liệu chung phải nằm ở Swift; CSDL cần đĩa block sống lâu hơn VM |
| MySQL tự dựng trong VM | Trove | Trove cần thêm image guest, guest agent, message bus riêng: rủi ro cao trong 3 tuần. Tự dựng còn cho thấy rõ cơ chế nhân bản, quyền và backup |
| Nhân bản GTID bất đồng bộ | Semi-sync, Group Replication | Đơn giản, đủ cho tách đọc/ghi; ghi không phải chờ replica ở AZ khác |
| RabbitMQ, co giãn theo hàng đợi | Gọi thẳng máy chấm; co giãn theo CPU | Hàng đợi giữ bài lúc cao điểm. Worker luôn 100 % CPU khi đang chấm dù còn 1 hay 100 bài; độ dài hàng đợi mới phản ánh đúng việc còn tồn |
| Alertmanager gọi `alarm_url` của Heat | Aodh, Ceilometer | Prometheus đã có sẵn cho giám sát, dùng luôn để co giãn thì bớt một hệ thống nặng; máy monitor không giữ credential có quyền Heat, chỉ biết 4 URL đã ký |
| `openstack_sd` + metadata `cj_role` | Danh sách IP tĩnh | ASG tạo, xóa máy liên tục |
| Docker sandbox (`--network none`, `--read-only`, cgroup, `--cap-drop ALL`, user thường) | nsjail, gVisor | Nhóm đã quen; đã thử thật: gọi mạng, ghi file hệ thống, fork bomb, vượt RAM, in vô hạn đều bị chặn |
| Một golden image + mã tải từ Swift khi boot | Image riêng cho từng vai trò | Build image 1 lần; sửa code chỉ cần upload bản mới, ASG thay từng máy một |

**Điểm khác so với bản đề xuất:**

| # | Đề xuất | Thực tế | Lý do |
|---|---|---|---|
| D1 | Kolla-Ansible (không ghi phiên bản), Swift cài cùng Kolla | **Kolla-Ansible 2025.2**, **Swift cài tay** | Image của 2024.2 (bản cuối còn Swift) đã bị gỡ khỏi registry; từ 2025.1 Kolla bỏ Swift. Giao diện với ứng dụng không đổi (cùng container, cùng ACL) |
| D2 | (ngầm định OVN) | **Neutron ML2/OVS** | Octavia kiểu `tenant` của Kolla chỉ hỗ trợ OVS, mà GCE không có VLAN vật lý |
| D3 | Octavia lỗi thì dùng OVN provider | Dự phòng: topology SINGLE, rồi 2 VM HAProxy + keepalived | Do D2, OVN provider không dùng được. Thực tế không cần dùng dự phòng |
| D10 | 3 danh tính Keystone | **4 danh tính** (thêm `cj-backup`) | Quyền tối thiểu: chỉ backup mới ghi được container `backups` |
| B | Web 1 ASG + soft-anti-affinity | **2 ASG web ghim theo AZ** (az2 luôn 1 máy, az1 1–2 máy) | Khi Heat tạo 2 máy song song, Nova có thể đặt cả 2 vào cùng host, không bảo đảm được kịch bản "tắt web ở AZ-1" |
| C | 3 luật cảnh báo chính | **Thêm 3 luật dữ liệu** (MySQLDown, ReplicationBroken, BackupStale) | Giám sát cả HM 3, 4 |

## 6. Kết quả đo

**Ứng dụng và co giãn** (B, đo trên cụm 31/10, `docs/evidence/B-cum-31-10.txt`):

| Đại lượng | Giá trị |
|---|---|
| Chấm 1 bài `a-plus-b` trên worker (gồm biên dịch, chưa gồm hàng đợi) | C++ 6,9 s / Python 3,2 s |
| Bài `slow-sum` trên worker `cj.medium` (1 vCPU) | ~1,47 s/test, 8,4 s/bài ≈ **7 bài/phút/worker** |
| POST `worker_up` alarm_url → server ACTIVE → cài xong, nhận bài được | 18 s → **70 s** |
| POST `worker_down` alarm_url → còn 1 worker | **14 s** |
| Loadtest 60 bài: thời gian chờ trung bình / p95 (1 worker cố định) | ⏳ |
| Loadtest 60 bài: thời gian chờ trung bình / p95 (có tự mở rộng) | ⏳ |
| Cảnh báo firing → worker mới nhận bài đầu tiên (qua Alertmanager) | ⏳ |
| Hàng đợi rỗng → thu về 1 worker (gồm `for: 1m`) | ⏳ |
| Tắt 1 web ở az1 → LB ngừng gửi request tới máy đó | ⏳ |

**Dữ liệu và giám sát** (C; local = Docker Desktop trên laptop, MySQL 8.4, CSDL mẫu 200 user / 5 bài / 50 000 bài nộp ≈ 14,6 MB; số gốc `docs/evidence/C-local-timings.txt`, số cụm từ `db/cluster-evidence.sh`):

| Đo | Local | Cụm |
|---|---|---|
| Độ trễ nhân bản (commit ở primary → áp dụng xong ở replica, `performance_schema`, 20 lần) | trung vị 6,4 ms, max 11,2 ms | trung vị 17,2 ms, max 30,9 ms |
| Backup (`mysqldump --single-transaction` + gzip) / kích thước | 1,0 s / 0,6 MB | 0,95 s / 1,4 KB (gồm upload Swift; CSDL còn trống) |
| Restore vào primary → replica khớp lại | 3,2 s → +0,9 s | 2,5 s (gồm tải từ Swift) → +0,34 s |
| Cảnh báo → Gmail nhận thư (gồm `group_wait` 10 s) | 10,5 s | ⏳ |
| ReplicationBroken: luồng nhân bản dừng → firing (`for: 1m`) | ~72 s | ⏳ |

## 7. Chi phí

Chi tiết, cách tính và nguồn giá: `docs/cost/chi-phi.md`. Tỷ giá 1 USD ≈ 26.000 đ. Giá GCP lấy từ Cloud Billing Catalog API (bảng giá chính thức, vùng asia-southeast1, tra 10/11/2026).

**Chi phí thật của dự án** (trên tín dụng dùng thử ₫7.730.577 ≈ 297 USD):

| Khoản | Ước tính |
|---|---|
| Cụm đang chạy (3 VM + 3 IP) | ≈ 0,66 USD/giờ ≈ 17.200 đ/giờ |
| Cụm đang tắt (đĩa 246 GiB pd-balanced + 90 GiB pd-standard, snapshot ≈ 18 GiB, IP tĩnh) | ≈ 1,32 USD/ngày ≈ 34.000 đ/ngày |
| Dự kiến 28/10 → 22/11 (~150 giờ chạy) | ≈ 133 USD ≈ 3,5 triệu đ |
| Số thật trên Billing | ⏳ (ảnh Billing → Reports) |

**Ba phương án chạy thật 24/7** (mỗi tháng, gồm nhân lực theo kỹ sư 20 triệu đ/tháng):

| Phương án | Thành phần chính | triệu đ/tháng |
|---|---|---|
| AWS Singapore, thiết kế đổi 1–1 | EC2 + ALB + NAT Gateway + RDS Multi-AZ + SQS + S3 + CloudWatch ≈ 189 USD; nhân lực 5 % kỹ sư | **≈ 5,9** |
| OpenStack trên 3 máy chủ cũ của trường | Khấu hao 1,25 + điện 0,8 + Internet 0,5 + linh kiện 0,18; nhân lực 20 % kỹ sư | ≈ 6,7 |
| OpenStack trên 3 VM GCP (như demo) | 3 VM sau giảm giá dùng liên tục 20 % ≈ 378 USD, đĩa + IP + snapshot ≈ 43 USD; nhân lực 20 % kỹ sư | ≈ 14,9 |

Bản đề xuất ghi 14,8 / 6,7 / 5,4–6,2 triệu; số mới nằm trong cùng khoảng, kết luận giữ nguyên: ở quy mô một môn học, dịch vụ có quản lý (AWS) rẻ nhất khi tính cả nhân lực; OpenStack trên VM thuê đắt nhất vì trả tiền cho 3 máy cố định chạy 24/7 và cho cả lớp ảo hóa lồng, chỉ hợp lý cho mục đích học.

## 8. Giới hạn

- **Controller là điểm lỗi đơn**: một node chạy toàn bộ API, CSDL của OpenStack, Swift, Cinder và router. Hỏng thì cả cụm dừng.
- **Swift 1 bản sao** trên 1 đĩa, Cinder dùng LVM trên chính controller: controller hỏng thì mất cả dữ liệu lẫn backup. Bù bằng snapshot đĩa GCE; thực tế nên đưa backup sang vùng hoặc nhà cung cấp khác.
- **CPU vật lý cố định** (2 compute × 2 vCPU): thêm máy chấm chỉ tăng thông lượng tới khi hết CPU thật; máy ảo lồng chậm hơn máy thật.
- **MySQL không tự failover**: mất primary thì nâng replica lên bằng tay (RTO ~10–15 phút). Nhân bản bất đồng bộ nên có thể mất vài giao dịch cuối (RPO > 0, đo local trung vị 6 ms).
- **Một RabbitMQ và một máy monitor**: chết thì mất hàng đợi hoặc mất giám sát và co giãn (bài đã lưu trong CSDL ở trạng thái PENDING, không mất bài nộp).
- **Secret** nằm trong file trên controller và trong user_data của VM, chưa dùng Barbican/Vault. Kết nối MySQL và nhân bản không mã hóa (chỉ đi trong `net-data`).
- **Ảnh amphora tự build**; image Kolla 2024.2 đã bị gỡ khỏi registry, nên cụm chỉ dựng lại được trên bản còn image.
- **Sandbox**: worker phải gọi được Docker daemon (tương đương root trên máy worker); có thể nâng cấp bằng gVisor hoặc rootless Docker.
- **Đĩa**: quota SSD 250 GB của vùng giới hạn kích thước đĩa compute, nên Placement nhanh hết `DISK_GB` dù RAM/CPU còn dư.

## 9. Phân công thực tế

| Người | Đã làm |
|---|---|
| A – Tuấn | 3 VM GCE (nested virt, VPC, IP tĩnh, script bật/tắt + khóa dùng chung cụm); Kolla-Ansible 2025.2, Swift cài tay, Octavia + ảnh amphora; mạng external giả, NAT/DNAT; project, user, 4 application credential, ACL Swift; stack `cj-net` (3 mạng, router, 6 SG, bastion); smoke test và minh chứng HM 1, 2, 5 |
| B – Phường | Web/API Flask, worker + sandbox Docker, `cj-run`, 32 unit test; golden image `cj-base-v1`, đóng gói release qua Swift; stack `cj-app` (LB Octavia, 2 ASG web theo AZ, ASG worker, 4 ScalingPolicy); loadtest; đo thời gian chấm và co giãn qua `alarm_url` |
| C – Trọng | Lược đồ CSDL, MySQL Primary/Replica GTID, user tối thiểu, backup/restore lên Swift; stack `cj-data`, `cj-mon`; Prometheus (`openstack_sd`), 9 luật cảnh báo + unit test, Alertmanager (email + `alarm_url`), dashboard Grafana; bảng chi phí; ghép báo cáo |

Link repo: `https://github.com/tuanhoangnghia/btl-dtdm` (repo private: thêm thầy làm collaborator hoặc chuyển public lúc nộp) · Link video: ⏳

---

## Việc trước khi xuất PDF
- [ ] Sơ đồ kiến trúc PNG (mục 2), xuất vào `docs/report/img/`
- [ ] Ảnh minh chứng đủ 8 hạng mục, đặt tên `docs/evidence/<A|B|C>-hm<n>-*.png`, chèn vào mục 4
- [ ] Thay mọi ô ⏳ bằng số đo thật; chép lại phần B khi B cập nhật `B-ung-dung.md`
- [ ] Ảnh Billing GCP + số thật vào mục 7; kiểm lại giá AWS bằng AWS Pricing Calculator
- [ ] Kiểm lại link repo (quyền truy cập của thầy) và link video
- [ ] Xóa các khối ghi chú `>` và bảng trạng thái đầu file; xuất PDF (`pandoc bao-cao.md -o bao-cao.pdf` hoặc chép sang Google Docs/Word), kiểm tiếng Việt và bảng
