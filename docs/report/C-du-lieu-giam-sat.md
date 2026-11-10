# Phần C – Lưu trữ, cơ sở dữ liệu, giám sát, chi phí (bản nháp 09/11/2026)

> Hạng mục phụ trách: **3** (hai loại lưu trữ), **4** (cơ sở dữ liệu), **7** (giám sát có cảnh báo), **8** (chi phí).
> Mã: `db/`, `monitoring/`, `heat/cj-data.yaml`, `heat/cj-mon.yaml` + 2 script deploy, `docs/cost/chi-phi.md`.
> **Còn thiếu:** mọi số liệu chạy thật (đánh dấu ⏳), ảnh chụp màn hình, minh chứng `docs/evidence/C-*`. Bản này mô tả thiết kế đã viết xong.

## 1. Kiến trúc lớp dữ liệu và giám sát

```
                 net-app 10.0.2.0/24                                  net-data 10.0.3.0/24
 web ×2–3 ──5672──► RabbitMQ 10.0.2.10 (az2)                ┌──► MySQL Primary 10.0.3.10 (az1) ──binlog GTID──► MySQL Replica 10.0.3.11 (az2)
 worker ×1–3 ◄──────┘  queue submissions (durable)          │        │ Cinder 10 GB /data                         │ Cinder 10 GB /data
 web, worker ──3306 (cj_app: ghi) ──────────────────────────┘        │ cron 02:00: mysqldump | gzip ──► Swift backups/mysql/*.sql.gz (7 ngày)
 web /scoreboard ──3306 (cj_ro: chỉ đọc) ───────────────────────────────────────────────────────────►┘

 monitor 10.0.2.11 (az1): Prometheus ──openstack_sd (cj-monitor)──► tìm VM theo metadata cj_role, scrape :9100/:8000/:9200/:15692/:9104
                           │ rules.yml
                           ▼
                       Alertmanager ──► email (Gmail :587)
                                    └─► alarm_url của 4 ScalingPolicy (cj-app) → Heat thêm/bớt worker, web
                       Grafana (dashboard CloudJudge)
```

Mỗi máy dữ liệu là 1 VM `cj-base-v1` chạy container Docker (`--network host`, `--restart unless-stopped`), dữ liệu nằm trên **volume Cinder** gắn vào `/data`. Toàn bộ do 2 stack Heat dựng: `cj-data` (3 máy + 3 volume, IP cố định) và `cj-mon` (máy monitor).

## 2. Hạng mục 3 – Hai loại lưu trữ

| Loại | Dịch vụ OpenStack | Dùng cho | Vì sao loại này |
|---|---|---|---|
| **Object** | Swift (container `submissions`, `testcases`, `releases`, `backups`) | Mã nộp, bộ test, bản phát hành app, bản backup MySQL | Web/worker bị tạo và xóa liên tục (ASG), dữ liệu dùng chung phải nằm ngoài VM; truy cập qua HTTP với quyền theo danh tính Keystone (ACL) |
| **Block** | Cinder (LVM trên controller) | Dữ liệu MySQL primary, replica (10 GB mỗi máy), RabbitMQ (5 GB) | CSDL cần đĩa ghi ngẫu nhiên, độ trễ thấp và **sống lâu hơn VM** |

- Volume tạo riêng trong stack (`OS::Cinder::Volume`), gắn bằng `OS::Cinder::VolumeAttachment`. VM nhận diện đĩa qua `/dev/disk/by-id/virtio-<20 ký tự đầu của volume id>`, định dạng ext4 nhãn `cjdata` **chỉ khi đĩa trống**. Tạo lại VM thì volume cũ được gắn lại, MySQL thấy datadir cũ và chạy tiếp, không khởi tạo lại.
- Backup có hạn dùng: object `backups/mysql/<YYYYmmdd-HHMM>.sql.gz` mang header `X-Delete-After: 604800`, Swift tự xóa sau 7 ngày.
- Minh chứng ⏳: `openstack volume list --long` (3 volume `in-use`, gắn đúng máy); `openstack object list submissions` có object mới sau khi nộp bài; `openstack object list backups`.

## 3. Hạng mục 4 – Cơ sở dữ liệu

### 3.1. MySQL 8.4 tự dựng: Primary (az1) → Replica (az2)
- **Nhân bản bất đồng bộ dựa trên GTID** (`gtid_mode=ON`, `SOURCE_AUTO_POSITION=1`): replica tự biết cần đọc tiếp từ giao dịch nào, không phải ghi tay tên file binlog và vị trí.
- Replica bật `read_only` và `super_read_only` (kể cả root cũng không ghi được). Mọi thay đổi chỉ đến từ luồng nhân bản.
- Replica nhận **cả lược đồ lẫn user** qua binlog: `setup-primary.sh` chỉ chạy trên primary, replica chỉ cần `CHANGE REPLICATION SOURCE … START REPLICA`.
- App ghi vào primary (`cj_app`), trang `/scoreboard` đọc từ replica (`cj_ro`). Replica lỗi thì web tự đọc tạm primary (phần B).

### 3.2. Quyền tối thiểu (CONTRACT 8.3)

| User MySQL | Quyền | Chỉ đăng nhập từ |
|---|---|---|
| `cj_app` | SELECT, INSERT, UPDATE trên `cloudjudge.*` (không DELETE, không DDL) | `10.0.2.%` (web, worker) |
| `cj_ro` | SELECT trên `cloudjudge.*` | `10.0.2.%` |
| `repl` | REPLICATION SLAVE | `10.0.3.%` (replica) |
| `exporter` | PROCESS, REPLICATION CLIENT, SELECT; tối đa 3 kết nối | `127.0.0.1` (exporter cùng máy) |
| `backup` | SELECT, LOCK TABLES, SHOW VIEW, EVENT, TRIGGER trên `cloudjudge.*`; RELOAD, PROCESS | `127.0.0.1` |
| `root` | toàn quyền | **chỉ socket trong container** (`MYSQL_ROOT_HOST=localhost`), mật khẩu đọc từ file 600 |

Thêm lớp mạng: `sg-db` chỉ mở 3306 cho `sg-web`, `sg-worker`, `sg-db`. Mật khẩu sinh ngẫu nhiên (`~/secrets/data.env`), truyền qua tham số `hidden` của Heat, mỗi VM chỉ nhận mật khẩu nó cần (replica không có mật khẩu `cj_app`, RabbitMQ không có mật khẩu MySQL).

### 3.3. Sao lưu và khôi phục
- `db/backup-mysql.sh`: `mysqldump --single-transaction` (ảnh chụp nhất quán của InnoDB, **không khóa bảng**, app vẫn chạy) | gzip, kiểm `gzip -t` và dòng `Dump completed`, rồi upload lên Swift bằng application credential **`cj-backup`**, danh tính chỉ ghi được container `backups`.
- `db/restore-mysql.sh latest`: tải bản mới nhất, nạp vào **primary**. Bản dump dùng `--set-gtid-purged=OFF` nên khi khôi phục, primary sinh GTID mới và **replica tự nhận dữ liệu khôi phục**.
- Sau mỗi lần backup thành công, script ghi metric `cj_backup_last_success_timestamp_seconds`. Luật `BackupStale` báo nếu quá 26 giờ không có bản mới.

### 3.4. RPO / RTO (dùng khi vấn đáp)

| Sự cố | RPO (mất tối đa) | RTO (khôi phục trong) | Cách xử lý |
|---|---|---|---|
| Mất replica | 0 | vài phút | Tạo lại VM replica, nó tự bắt kịp nhờ GTID |
| Mất VM primary, volume còn | 0 (dữ liệu trên Cinder) | ~5 phút | Tạo lại VM (Heat), gắn lại volume |
| Mất primary cả volume | độ trễ nhân bản (đo local: trung vị 6 ms, max 11 ms) | ~10–15 phút, **làm tay** | Nâng replica lên primary (`STOP REPLICA; RESET REPLICA ALL; SET GLOBAL super_read_only=OFF`), đổi IP/cấu hình app |
| Lỗi logic (xóa nhầm dữ liệu) | ≤ 24 giờ | ~5 phút | `restore-mysql.sh` từ bản backup đêm trước (replica cũng nhận lệnh xóa nên không cứu được) |

Không có **tự động failover** (không Orchestrator/Group Replication), nêu ở mục Giới hạn.

### 3.5. Vì sao không dùng Trove
Trove (DBaaS của OpenStack) cần thêm image guest riêng, guest agent, message bus. Rủi ro cao trong 3 tuần mà phải dựng cả OpenStack. Tự dựng MySQL trong VM bằng Heat cũng cho thấy rõ cơ chế nhân bản, quyền và backup, đúng mục tiêu học.

Minh chứng (local, `docs/evidence/C-local-replication.txt`; cụm ⏳): `bash db/test-replication.sh` (ghi ở primary → đọc thấy ở replica sau ~1 giây theo đồng hồ của script, độ trễ thật đo trong MySQL ~6 ms; ghi vào replica bị từ chối `ERROR 1290 … super-read-only`; `SHOW REPLICA STATUS` có `Replica_IO_Running: Yes`, `Replica_SQL_Running: Yes`); `restore-mysql.sh latest` trên cụm.

## 4. Hạng mục 7 – Giám sát có cảnh báo

### 4.1. Thu thập (Prometheus, mô hình pull)
- Máy web/worker do ASG tạo nên **không có IP cố định**. Prometheus dùng `openstack_sd_configs`: hỏi Nova danh sách máy bằng application credential `cj-monitor` (role reader, không đọc được dữ liệu), giữ máy `ACTIVE`, lọc theo metadata `cj_role` mà Heat gắn cho từng máy. Làm mới mỗi 15 giây, nên máy mới scale out được scrape ngay, máy bị scale in biến mất khỏi danh sách.
- Nguồn metric: node_exporter `:9100` (mọi VM), web `:8000/metrics`, worker `:9200/metrics` (CONTRACT 9), RabbitMQ `:15692` (bật `return_per_object_metrics` để có độ dài **từng queue**), mysqld_exporter `:9104` (2 máy MySQL).

### 4.2. Luật cảnh báo (`monitoring/rules.yml`, có unit test `tests/rules.test.yml`)

| Luật | Điều kiện | Hành động |
|---|---|---|
| QueueHigh | `sum(rabbitmq_queue_messages_ready{queue="submissions"}) > 10` trong 30 giây | **thêm worker** + email |
| QueueIdle | hàng đợi (kể cả bài đang chấm) = 0 trong 1 phút và còn > 1 worker | **bớt worker** |
| WebCPUHigh | CPU trung bình các web > 70 % trong 1 phút | **thêm web** + email |
| WebCPULow | CPU web < 20 % trong 5 phút và đang > 2 web | **bớt web** |
| SubmissionStuck | `max(cj_oldest_pending_seconds) > 120` | email (critical) |
| InstanceDown | `up == 0` trong 1 phút | email (critical) |
| MySQLDown, ReplicationBroken, BackupStale | MySQL không kết nối được / luồng nhân bản dừng / quá 26 giờ không có backup | email |

- `cj_pending_submissions` và `cj_oldest_pending_seconds` là giá trị toàn cục, máy web nào cũng báo cùng số, nên dùng `max()`, không dùng `sum()`.
- Co giãn theo **hàng đợi** chứ không theo CPU worker: độ dài hàng đợi phản ánh đúng lượng việc còn tồn; CPU worker luôn cao khi đang chấm, kể cả khi chỉ còn 1 bài.

### 4.3. Từ cảnh báo đến co giãn (không cần Aodh/Ceilometer)
Alertmanager định tuyến theo nhãn `action`: `worker_up` → `POST` vào `alarm_url` (URL đã ký sẵn của `OS::Heat::ScalingPolicy` trong `cj-app`). Heat tăng ASG thêm 1 máy, có cooldown và chặn ở `max_size`. Khi còn firing, Alertmanager gửi lại mỗi phút (`repeat_interval: 1m`), nên hàng đợi càng lâu vơi thì càng thêm máy, tối đa 3. Máy monitor **không giữ credential có quyền Heat**, chỉ biết 4 URL đã ký.

### 4.4. Email và dashboard
- Email qua Gmail cổng **587** (GCE chặn cổng 25) bằng App Password; tiêu đề `[CloudJudge] FIRING: QueueHigh (warning)`, có thư `RESOLVED` khi hết.
- Grafana: hàng 1 cho phần demo co giãn (bài đang chờ, số worker, số web, bài chờ lâu nhất, bài nhận/chấm mỗi phút); hàng 2 chấm bài (p50/p95 thời gian chấm, cảnh báo đang bật); hàng 3 hạ tầng (CPU/RAM theo máy, trạng thái mục tiêu, replication, tuổi bản backup, truy vấn MySQL).
- Đã chạy thật ở local (`docs/evidence/C-local-monitoring.txt`): thư thử và thư `ReplicationBroken` tới Gmail; `ACTION=worker_up` gọi đúng URL. Khi thử cắt luồng nhân bản (`STOP REPLICA SQL_THREAD`): pending sau ~10 s, firing sau ~72 s (`for: 1m`), tự hết ~11 s sau khi nối lại (`docs/evidence/C-local-replication-broken.txt`).
- Gặp khi chạy local: phần mềm diệt virus quét thư (Avast Mail Shield) ký lại TLS của `smtp.gmail.com` → Alertmanager báo `x509: certificate signed by unknown authority`. Cách xử lý là cho container tin thêm CA đó (`monitoring/docker-compose.local-ca.yml`), **không tắt kiểm tra TLS**. Trên cụm không có lớp chặn này.
- Minh chứng cụm ⏳: ảnh Grafana lúc chạy loadtest 60 bài; ảnh hộp thư có `QueueHigh` / `SubmissionStuck`; `openstack stack resource list -n 2 cj-app` thấy worker 1 → 2 → 3 → 1.

## 5. Hạng mục 8 – Chi phí
Chi tiết, cách tính và nguồn giá: [`docs/cost/chi-phi.md`](../cost/chi-phi.md).

| Phương án (24/7, mỗi tháng, gồm nhân lực) | Chi phí |
|---|---|
| OpenStack trên 3 VM GCP (như demo) | ≈ 14,9 triệu đ |
| OpenStack trên 3 máy chủ cũ của trường | ≈ 6,7 triệu đ |
| AWS Singapore (EC2 + ALB + NAT + RDS Multi-AZ + SQS + S3 + CloudWatch) | ≈ 5,9 triệu đ |

Chi phí thật của dự án ⏳ (ảnh Billing): dự kiến ≈ 133 USD ≈ 3,5 triệu đ trên tín dụng dùng thử (~150 giờ chạy cụm × 0,66 USD + đĩa, snapshot, IP ≈ 1,32 USD/ngày cả khi tắt). Đơn giá GCP lấy từ Cloud Billing Catalog API (bảng giá chính thức).

## 6. Lý giải lựa chọn (bổ sung cho mục 5 của báo cáo)

| Chọn | Thay vì | Lý do |
|---|---|---|
| MySQL trong container trên VM + Cinder | Trove | Xem 3.5 |
| Nhân bản GTID bất đồng bộ | Semi-sync, Group Replication | Đơn giản, đủ cho minh chứng đọc/ghi tách biệt; ghi không phải chờ replica ở AZ khác |
| `mysqldump --single-transaction` | Percona XtraBackup | CSDL nhỏ (vài MB), dump logic khôi phục được ở mọi phiên bản, dễ kiểm |
| Prometheus + Alertmanager gọi `alarm_url` | Aodh + Ceilometer | Prometheus đã có cho giám sát; bớt một hệ thống nặng (D11) |
| `openstack_sd` + metadata `cj_role` | Danh sách IP tĩnh | ASG tạo/xóa máy liên tục |
| Cấu hình trong Git, nhúng vào VM bằng `get_file` của Heat | Tải từ Swift / sửa tay trong VM | Dựng lại từ đầu bằng 1 lệnh; `cj-monitor` không có quyền Swift |
| **Bổ sung so với đề xuất:** 3 luật dữ liệu (MySQLDown, ReplicationBroken, BackupStale), danh tính riêng `cj-backup` (D10) | | Giám sát cả hạng mục 3, 4; backup chỉ ghi được container `backups` |

## 7. Giới hạn
- **Không tự động failover MySQL**: mất primary thì nâng replica lên bằng tay (RTO ~10–15 phút).
- Nhân bản **bất đồng bộ**: primary chết ngay sau khi commit có thể mất vài giao dịch cuối (RPO > 0).
- Cinder dùng LVM trên **chính controller**, cũng là nơi chạy Swift với 1 bản sao: controller hỏng thì mất cả dữ liệu lẫn backup. Bù bằng snapshot đĩa GCE; thực tế nên đưa backup sang vùng hoặc nhà cung cấp khác.
- **Một máy monitor** và một RabbitMQ: chết thì mất giám sát/co giãn hoặc mất hàng đợi (bài đã lưu trong DB ở trạng thái PENDING, không mất bài nộp).
- Kết nối MySQL và nhân bản **không mã hóa** (chỉ trong `net-data`); mật khẩu nhân bản trao đổi qua RSA (`GET_SOURCE_PUBLIC_KEY`).
- Secret nằm trong file trên controller và trong user_data của VM (chưa dùng Barbican/Vault).

## 8. Kết quả đo
Local: Docker Desktop (WSL2) trên laptop, MySQL 8.4 primary + replica, CSDL mẫu 200 user, 5 bài, 50 000 bài nộp (submissions ~14,6 MB). Số liệu gốc: `docs/evidence/C-local-timings.txt`.

| Đo | Local | Cụm (10/11, CSDL còn trống) |
|---|---|---|
| Độ trễ nhân bản (commit ở primary → áp dụng xong ở replica, `performance_schema`, 20 lần) | trung vị 6,4 ms, max 11,2 ms | trung vị 17,2 ms, max 30,9 ms (az1 → az2, khác zone GCE); lần đo lại tối 10/11: trung vị 14,4 ms, max 20,8 ms |
| Nạp 50 000 dòng ở primary → replica bắt kịp | 1,3 s + 1,1 s | không đo (không nạp dữ liệu mẫu vào CSDL thật) |
| Thời gian backup / kích thước bản dump (gzip -9) | 1,0 s / 0,6 MB | 0,95 s / 1,4 KB, gồm upload Swift |
| Thời gian restore (primary) → replica khớp lại | 3,2 s → +0,9 s | 2,5 s (gồm tải từ Swift) → +0,34 s |
| Cảnh báo → Gmail nhận thư (gồm `group_wait` 10 s) | 10,5 s | ≤ 11 s sau firing (bộ đếm thư email của Alertmanager tăng 0 → 1, 0 lỗi; khi hết cảnh báo gửi thêm thư "resolved") |
| ReplicationBroken: luồng nhân bản dừng → firing (`for: 1m`) | ~72 s | pending 6,3 s → **firing 66,2 s**; START lại → hết cảnh báo 10,2 s (`C-cluster-alert.txt`, 10/11 tối, CSDL đã có dữ liệu của B) |
| QueueHigh firing → worker mới nhận bài | (cần app + Heat) | … (B đo phần Heat: alarm_url → worker sẵn sàng 70 s) |
| QueueIdle → còn 1 worker | (cần app + Heat) | … |
