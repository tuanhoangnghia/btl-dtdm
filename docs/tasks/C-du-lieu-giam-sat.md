# Nhiệm vụ C – Lưu trữ, CSDL, giám sát, chi phí, ghép báo cáo (HM 3, 4, 7, 8)

**Người phụ trách:** Trọng (OpenStack user `trong`, GitHub `trongjismeeee`)  · **Bắt đầu ngay, không cần chờ cụm:** 28–30/10 làm trên laptop bằng Docker.

Đọc trước: `docs/CONTRACT.md` (bắt buộc), `KE_HOACH_TRIEN_KHAI.md` mục 1, 3, 10.2, 11.2, 11.4, 12, 13, 14.4.

## Phạm vi
- **Được sửa:** `db/**`, `monitoring/**`, `heat/cj-data.yaml`, `heat/cj-mon.yaml`, `heat/deploy-cj-data.sh`, `heat/deploy-cj-mon.sh`, `scripts/cj-health.sh`, `docs/cost/**`, file báo cáo ghép chính trong `docs/report/`, `docs/report/C-*.md`, `docs/evidence/C-*`, file này.
- **Không sửa:** `app/**` (B), `heat/cj-net.yaml` (A). Đổi `db/schema.sql` thì báo B và ghi nhật ký vào CONTRACT.

## Giai đoạn 1 – Local (28–30/10)

Cấu trúc gợi ý:
```
db/
├─ schema.sql                 # đã có bản v1
├─ users.sql.tpl              # tạo user/grant theo CONTRACT 8.3, dùng envsubst
├─ primary.cnf, replica.cnf   # server-id, GTID, binlog, read_only
├─ setup-replica.sh           # CHANGE REPLICATION SOURCE … SOURCE_AUTO_POSITION=1
├─ backup-mysql.sh            # mysqldump | gzip | swift upload backups (X-Delete-After)
├─ restore-mysql.sh
└─ docker-compose.repl.yml    # primary + replica + mysqld-exporter để thử ở local
monitoring/
├─ docker-compose.yml         # prometheus, alertmanager, grafana (version theo CONTRACT 6)
├─ prometheus.yml.tpl         # openstack_sd (kế hoạch 12.1)
├─ prometheus.local.yml       # bản static cho local: trỏ vào compose của B
├─ rules.yml                  # kế hoạch 12.2
├─ alertmanager.yml.tpl       # kế hoạch 12.3
├─ rabbitmq/{enabled_plugins, rabbitmq.conf}   # bật prometheus + per-object metrics
└─ grafana/{datasource.yml, dashboards.yml, cloudjudge.json}
docs/cost/
└─ chi-phi.xlsx (hoặc .md) # 3 phương án + chi phí thật
```

| Ngày | Việc |
|---|---|
| 28/10 | Rà `db/schema.sql` cùng B (chốt trong ngày); `users.sql.tpl`; `docker-compose.repl.yml`: primary → replica GTID chạy, ghi primary đọc replica |
| 29/10 | `backup-mysql.sh` / `restore-mysql.sh` (local: lưu file thay cho Swift); bộ `monitoring/` chạy local; tạo Gmail App Password; **email cảnh báo thử gửi được** |
| 30/10 | `rules.yml` đủ 6 luật (test bằng metric giả hoặc app local của B); dashboard Grafana; bảng chi phí 3 phương án (Pricing Calculator, kiểm lại số trong đề xuất); bản nháp `cj-data.yaml`, `cj-mon.yaml` |

✅ Xong giai đoạn 1 khi trên laptop: replication chạy; backup ra file và restore được; Prometheus + Alertmanager gửi được email thật; dashboard hiển thị.

## Giai đoạn 2 – Lên cụm (31/10–3/11), cần A bàn giao
| Ngày | Việc | Phụ thuộc |
|---|---|---|
| 31/10 | Điền `~/secrets/data.env`; deploy **`cj-data`** (MySQL primary az1 + replica az2 trên Cinder, RabbitMQ trên Cinder, mysqld-exporter). Nếu chưa có `cj-base-v1` thì dùng `ubuntu-24.04` và cài Docker trong cloud-init | `cj-net` (A), image (B) |
| 1/11 | Kiểm replication, chạy schema + users; cron backup lên Swift `backups` bằng credential `cj-backup` → **báo B "cj-data xong"** | |
| 2/11 | Deploy **`cj-mon`** (lúc đầu để alarm_url giả nếu B chưa xong); Prometheus thấy target qua `openstack_sd` | |
| 3/11 | Cập nhật `cj-mon` với 4 alarm_url thật từ `cj-app`; email thật tới hộp thư | `cj-app` (B) |

## Giai đoạn 3 – Hoàn thiện, báo cáo (4–9/11)
| Ngày | Việc |
|---|---|
| 4/11 | Cùng B thử autoscale qua Alertmanager; dashboard hoàn chỉnh; `scripts/cj-health.sh` |
| 5/11 | Thử backup → restore trên cụm; minh chứng HM 3, 4, 7 vào `docs/evidence/C-*` |
| 6/11 | Tập demo lần 1 (C nói phút 1:20–2:45, 4:00–6:00, 7:00–7:45, 9:00–10:00) |
| 7/11 | Lấy chi phí thật từ Billing (nhờ A chụp nếu C không có quyền billing); viết `docs/report/C-*.md`; **ghép báo cáo chính** (cấu trúc kế hoạch 14.4) |
| 9/11 | Xuất PDF, kiểm link repo/video, nộp |

## Tiến độ
- [x] Schema chốt với B (B viết app khớp `db/schema.sql` v1, không cần đổi)
- [x] Replication local: `db/local-up.sh` chạy OK 10/11 (replica thấy bản ghi sau ~1 s, từ chối ghi) → `docs/evidence/C-local-replication.txt`
- [x] Backup/restore local: chạy OK 10/11 trong `db/local-up.sh` (backup → restore vào primary, replication vẫn chạy); bản Swift chưa thử
- [x] Monitoring local + email thật: 10/11 thư thử tới Gmail OK, alarm_url (webhook) OK, ReplicationBroken firing sau ~72 s rồi tự hết → `docs/evidence/C-local-monitoring.txt`, `C-local-replication-broken.txt`
- [x] Rules + dashboard: 6 luật kế hoạch + 3 luật dữ liệu, unit test promtool, dashboard 20 panel; `check.sh` TẤT CẢ OK 10/11; tên metric replication đã xác minh (khớp)
- [ ] Bảng chi phí: `docs/cost/chi-phi.md`, giá GCP đã kiểm bằng Cloud Billing Catalog API 10/11 (3 phương án: 14,9 / 6,7 / 5,9 triệu đ/tháng); còn số thật + ảnh Billing (C tự xem được), giá AWS
- [ ] `scripts/cj-health.sh`: đã viết, chưa chạy trên cụm
- [ ] Báo cáo: phần C `docs/report/C-du-lieu-giam-sat.md`; **báo cáo chính `docs/report/bao-cao.md` đã ghép đủ 9 mục** (10/11), còn số đo cụm, ảnh, hình kiến trúc PNG, link video; lời thoại demo + vấn đáp `docs/report/C-demo-loi-thoai.md`
- [ ] Stack `cj-data` trên cụm → báo B: deploy 10/11 được **Primary + RabbitMQ (CJ_DATA_READY)**, **Replica lỗi "No valid host"** (DISK_GB 2 compute đầy 45/45), chờ A tăng `disk_allocation_ratio` rồi chạy lại `deploy-cj-data.sh` (stack đang CREATE_FAILED, lần sau tự update)
- [ ] Cron backup lên Swift (có trong `db/vm-bootstrap.sh`, chưa chạy thật)
- [ ] Stack `cj-mon` với alarm_url thật: bản nháp `heat/cj-mon.yaml` + `deploy-cj-mon.sh` xong, chưa deploy
- [ ] Minh chứng HM 3, 4, 7, 8: script `db/cluster-evidence.sh` sẵn sàng (đã thử phần SQL với MySQL local), chờ Replica để chạy → `docs/evidence/C-cluster-evidence.txt`
- [ ] Báo cáo ghép + PDF

## Nhật ký
- 10/11 (C, offline, đợt 3, trong lúc A sửa `disk_allocation_ratio`; A giữ khóa cụm, C không đụng cụm):
  - **Chi phí**: lấy giá GCP từ **Cloud Billing Catalog API** (`cloudbilling.googleapis.com/v1/services/6F81-5844-456A/skus`, token gcloud, không cần bật API trong project). Khớp: N2 0,038999 USD/vCPU-giờ + 0,005226 USD/GiB-giờ (n2-highmem-4 = 0,3232), pd-balanced 0,110, egress APAC 0,12, CUD 1 năm 37 %. **Khác ước tính cũ**: snapshot vùng Singapore 0,061 (cũ 0,029), pd-standard 0,044 (cũ 0,048), IP tĩnh để không 0,011 (cũ 0,010). Thêm 2 đĩa 30 GiB của VM cũ vào chi phí lúc tắt → ≈ 1,32 USD/ngày (cũ 1,2); dự kiến cả dự án ≈ 133 USD ≈ 3,5 triệu. 3 phương án không đổi. `gcloud billing projects describe` cho thấy tài khoản C xem được billing account `01BE00-008CAB-253DE8` → C tự lấy số thật ở Console → Billing → Reports.
  - **`db/cluster-evidence.sh`**: 1 lệnh trên controller (`ssh -A`) ra đủ minh chứng HM 3 (volume, container), HM 4 (`test-replication.sh` qua bastion), độ trễ nhân bản 20 lần (`performance_schema`, kèm `WAIT_FOR_EXECUTED_GTID_SET`), kích thước CSDL, backup thật lên Swift; tùy chọn `RESTORE=1` (ghi đè CSDL) và `ALERT=1` (cắt nhân bản, đo pending/firing/thư, tự START lại). SSH qua bastion dùng ControlMaster; tham số mysql được `printf %q` trước khi qua ssh (đã thử bằng ssh giả). Phần SQL chạy thử với MySQL 8.4 local: trễ 4–8 ms, restore-wait OK.
  - **Báo cáo chính** `bao-cao.md`: ghép đủ 9 mục từ đề xuất + A + B (đọc `origin/b/app-phase1`, không merge) + C; bảng điểm khác đề xuất (D1, D2, D3, D10, web 2 ASG, 3 luật dữ liệu). **Lời thoại demo** + câu hỏi vấn đáp: `docs/report/C-demo-loi-thoai.md`.
- 10/11 (C, local, đợt 2, chờ A): **Đối chiếu metric**: `cj_submissions_total`, `cj_pending_submissions`, `cj_oldest_pending_seconds` (web), `cj_graded_total`, `cj_grade_duration_seconds` (worker) trong `origin/b/app-phase1` khớp CONTRACT 9 + luật + dashboard. RabbitMQ 4.1 + `monitoring/rabbitmq/` chạy thử: `rabbitmq_queue_messages_ready / _unacked / rabbitmq_queue_messages{queue="submissions"}` đúng tên (12 tin → ready=12, QueueHigh sẽ firing). Không phải sửa gì.
  - **Số đo local** (`docs/evidence/C-local-timings.txt`, CSDL mẫu 200 user / 5 bài / 50 000 bài nộp ~14,6 MB): độ trễ nhân bản đo trong MySQL (`performance_schema`, END_APPLY − ORIGINAL_COMMIT) trung vị 6,4 ms, max 11,2 ms; backup 1,0 s / 0,6 MB; restore 3,2 s, replica khớp thêm 0,9 s; cảnh báo → Gmail 10,5 s (gồm group_wait 10 s). Đo từ ngoài qua `docker exec` ra ~300 ms là do chi phí gọi lệnh trên Windows, không dùng. Đã điền vào `docs/report/C-du-lieu-giam-sat.md` mục 8 (cột cụm để trống).
  - **Sức chứa sau khi A đặt `disk_allocation_ratio = 2.0`**: mỗi compute 90 GB sổ sách. compute-1 (az1) = 45 + cj-mon 20 = 65; compute-2 (az2) = 45 + replica 20 = 65. Còn 25 + 25 GB cho scale out: 2 worker (2×20) + 1 web (10) là vừa khít; demo scale tối đa mà thiếu thì đề nghị A nâng lên 3.0.
  - 2 VM GCP cũ `compute` (custom-4-8192) và `controller` (custom-2-6144), zone b: tạo 23/09, tắt từ 28/09, đĩa 30 GB pd-standard mỗi cái (~3 USD/tháng). Không có trong script nào của repo. Chờ nhóm xác nhận rồi mới xóa.
  - Tắt container local (giữ image 2,8 GB + volume MySQL 0,5 GB trên D).
- 10/11 (C, local): Docker Desktop 29.9.3 cài ở ổ D (`--installation-dir=D:\Docker\App --wsl-default-data-root=D:\Docker\Data`).
  - `monitoring/check.sh`: promtool check config (cụm + local), check rules (9), test rules, amtool, dashboard JSON (20 panel): **TẤT CẢ OK**.
  - `db/local-up.sh`: primary + replica + 2 exporter, schema + user, replication (GTID, auto position), backup → restore OK. Replica có GTID riêng `…:1-5` (giao dịch của entrypoint lúc khởi tạo, trước khi bật super_read_only); vô hại khi chỉ đọc, ghi lại để biết nếu có lúc phải đổi vai.
  - **Tên metric đã xác minh** (mysqld-exporter v0.16.0 + MySQL 8.4): `mysql_slave_status_replica_io_running`, `…_replica_sql_running`, `…_seconds_behind_source`, khớp luật + dashboard, không phải sửa.
  - `monitoring/local-up.sh` sửa 2 lỗi gặp khi chạy thật: (1) `local.env` lưu CRLF + App Password có khoảng trắng làm `source` hỏng → đọc từng dòng KEY=giá trị; (2) **Avast Mail Shield ký lại TLS của smtp.gmail.com** → Alertmanager `x509: certificate signed by unknown authority` → local-up ghép CA của Avast (hoặc `EXTRA_CA_FILE`) vào bundle của container qua `docker-compose.local-ca.yml` (không tắt kiểm TLS; cụm không bị ảnh hưởng).
  - Email thật: `send-test-alert.sh` → Gmail (mail phụ của C), `alertmanager_notifications_total{integration="email"}` tăng, 0 lỗi. `ACTION=worker_up` → webhook-echo nhận `POST /worker_up`.
  - ReplicationBroken: `STOP REPLICA SQL_THREAD` → pending ~10 s, firing ~72 s (for 1m), Alertmanager gửi thư; `START` lại → hết sau ~11 s.
  - InstanceDown kêu cho web/worker/rabbitmq vì app của B không chạy local (đúng).
- 10/11 (C): Tuấn đã cài key; `ssh cj-controller` OK (user `trong`, group `cj`, sudo, có `clouds.yaml`). Host key controller chưa có trong known_hosts, GCP không có guest attribute `hostkeys/` → đối chiếu ED25519 qua 2 đường (Tailscale 100.98.68.95 và IP công khai 34.124.240.64) cùng `SHA256:1g8edsO7vsbfi+EntIHqhtkcr7NW4EuBSZGe300VZYI` rồi mới nhận. Clone `c/data-mon` vào `~/cloudjudge` của `trong`. `data.env`/`infra.env` đủ biến cho cj-data (chưa có SMTP_*).
  - `deploy-cj-data.sh` (log `~/logs/deploy-cj-data.log` trên controller): `cj-mysql-primary` (az1) và `cj-rabbitmq` (az2) ACTIVE + **CJ_DATA_READY**; `cj-mysql-replica` (az2, cj.medium 20 GB) **ERROR "No valid host"** 6 lần → stack `cj-data` CREATE_FAILED. Scheduler: "Got no allocation candidates from the Placement API". Placement: mỗi compute VCPU 4/16, RAM ~5/14 GB, **DISK_GB 45/45** (compute-2 = rabbitmq 10 + amphora 5 + worker 20 + web 10; compute-1 = primary 20 + amphora 5 + web 10 + bastion 10). `nova.conf` của A không đặt `disk_allocation_ratio` (mặc định 1.0). Cinder LVM chỉ còn 2,4 GB nên boot từ volume không phải lối thoát. cj-mon (máy monitor) sẽ vướng y hệt.
  - Đã nhắn A: thêm `disk_allocation_ratio = 2.0` vào `infra/kolla/config/nova.conf` + `kolla-ansible reconfigure -t nova`. Sau đó C chạy lại `deploy-cj-data.sh` (update stack), rồi `test-replication.sh`. B dùng được Primary + MQ ngay; chỉ `/scoreboard` (đọc Replica) chưa chạy.
  - Phát hiện thêm: GCP còn 2 đĩa `compute`/`controller` 30 GB pd-standard của 2 VM cũ TERMINATED, vẫn tính tiền (đã hỏi A). Cần đưa vào `docs/cost/chi-phi.md` nếu giữ.
  - Cụm bật ~00:45–01:20 (giờ VN), nhả khóa C, tắt bằng `gcp-down.sh`.
- 09/11 (C): **Hạn nộp lùi sang 22/11/2026** (KE_HOACH/CLAUDE.md còn ghi 09/11, cần PR chung sửa). Phiên đầu của C, làm trên nhánh `c/data-mon` (từ `main`, chỉ đọc tham khảo `origin/b/app-phase1`).
  - **Máy C**: tạo cấu hình gcloud `cloudjudge` (Owner). Avast quét HTTPS làm gcloud lỗi `CERTIFICATE_VERIFY_FAILED` → ghép CA của Avast (`C:\ProgramData\Avast Software\Avast\wscert.pem`) với bộ CA của gcloud vào `%APPDATA%\gcloud\cj-ca-bundle.pem`, đặt `core/custom_ca_certs_file` **chỉ cho cấu hình cloudjudge**. SSH key `~/.ssh/cloudjudge` (ed25519, `SHA256:OjqGKYjFa+G3O9uEAU1c2F8akdmZ05k6US+wfQbHLS0`) + `Host cj-controller` trong `~/.ssh/config`; **chờ A cài key** (`05-add-user.sh trong trong "<pubkey>"` + `admin_ssh_pubkeys.txt`). Laptop chưa có Docker.
  - **`db/`**: `primary.cnf`/`replica.cnf` (GTID, `skip_name_resolve`, UTC); `users.sql.tpl` (5 user CONTRACT 8.3, host theo mạng: app `10.0.2.%`, repl `10.0.3.%`, exporter/backup `127.0.0.1`); `setup-primary.sh` (schema + user, chạy lại được); `setup-replica.sh` (`SOURCE_AUTO_POSITION=1`, `GET_SOURCE_PUBLIC_KEY=1`, bật `super_read_only` bằng `SET PERSIST` sau khi khởi tạo, vì đặt trong cnf thì entrypoint lần đầu không ghi được user root). Replica nhận cả schema lẫn user qua binlog nên không chạy schema trên replica. `backup-mysql.sh` (`--single-transaction --set-gtid-purged=OFF` để restore vào primary sinh GTID mới và tự sang replica; Swift `--skip-container-put` + `X-Delete-After: 604800`; ghi `cj_backup_last_success_timestamp_seconds` qua textfile collector). `restore-mysql.sh` (latest / object / file, bắt gõ YES). `test-replication.sh` (minh chứng HM 4, ghi vào CSDL riêng `cj_check`, không đụng bảng app). Root MySQL chỉ đăng nhập qua socket (`MYSQL_ROOT_HOST=localhost`), trên VM đọc mật khẩu từ file `/run/cj/root.pw`, lệnh tắt `sudo cj-mysql`.
  - **`monitoring/`**: `prometheus.yml.tpl` (openstack_sd + relabel theo `cj_role`, job node/web/worker/rabbitmq/mysql, `refresh_interval: 15s` để máy bị scale in biến nhanh khỏi danh sách); `rules.yml` (QueueHigh, QueueIdle, WebCPUHigh, WebCPULow, SubmissionStuck, InstanceDown + MySQLDown, ReplicationBroken, BackupStale); `tests/rules.test.yml`; `alertmanager.yml.tpl` (4 route `action` → alarm_url, `continue` để QueueHigh/WebCPUHigh vẫn gửi thư); Grafana provisioning + `make-dashboard.py` → `cloudjudge.json` (JSON gọn vì nhúng vào user_data, Nova giới hạn 64 KB: hiện ~50 KB sau base64); `rabbitmq/` (per-object metrics) + `dev-override.yml` dùng kèm compose của B mà không sửa file của B; bộ chạy local (`local-up.sh`, webhook-echo đóng vai Heat).
  - **Heat (nháp, chưa deploy)**: `cj-data.yaml`: 3 volume Cinder (không đặt AZ cho volume vì Cinder chỉ có zone mặc định), port IP cố định, `OS::Heat::CloudConfig` nhúng file `db/` bằng `get_file`, mỗi máy chỉ nhận secret nó cần, `user_data_update_policy: IGNORE` để stack update không thay máy CSDL. `cj-mon.yaml`: máy 10.0.2.11, render cấu hình trong VM bằng `monitoring/render.sh`. 2 script deploy theo mẫu `deploy-cj-app.sh` của B (secret qua file tham số 600, chờ `CJ_DATA_READY`/`CJ_MON_READY` trên console log).
  - **Đã kiểm**: `bash -n` mọi script, mọi file YAML parse được, render template bằng giá trị giả. **Chưa kiểm**: `promtool`/`amtool` (cần Docker; tải binary bị chặn), chạy thật MySQL/RabbitMQ.
  - **Cần xác minh khi có Docker**: tên metric replication của `mysqld-exporter v0.16.0` với MySQL 8.4 (`mysql_slave_status_replica_io_running` hay tên khác; luật và dashboard đã dùng `or` cho cả 2 kiểu tên).
  - **Mở**: mật khẩu admin Grafana trên cụm hiện sinh ngẫu nhiên trong VM (`/etc/cj-mon/grafana/admin.pw`), không thêm biến vào `data.env` để khỏi đổi CONTRACT.
  - **Chi phí** (`docs/cost/chi-phi.md`): đơn giá kiểm lại một phần (n2-highmem-4 Singapore ≈ 0,323 USD/giờ, khớp đề xuất; t3.small, NAT, RDS từ trang tổng hợp giá). Cụm chạy ≈ 0,66 USD/giờ; cụm tắt vẫn ≈ 1,2 USD/ngày (đĩa 246 GB pd-balanced + IP static). 3 phương án 24/7: GCP-OpenStack ≈ 14,9 · máy chủ trường ≈ 6,7 · AWS ≈ 5,9 triệu đ/tháng (đề xuất ghi 14,8 / 6,7 / 5,4–6,2, kết luận giữ nguyên). Đĩa/IP/snapshot GCP theo vùng chưa đọc được bảng chính thức, cần Pricing Calculator.
  - **`scripts/cj-health.sh`**: kiểm container Kolla, `o-hm0`, nova/neutron, 4 stack, máy ACTIVE + số web/worker + AZ, volume in-use, container Swift, LB + amphora + `/healthz` qua `lb_fip`; qua bastion (cần `ssh -A`): replication, hàng đợi, mục tiêu Prometheus, cảnh báo đang bật. Chỉ đọc.
  - **Báo cáo**: nháp phần C (HM 3, 4, 7, 8, RPO/RTO, lý giải, giới hạn) và khung báo cáo chính (9 mục theo KE_HOACH 14.4, ghi nguồn từng mục).
