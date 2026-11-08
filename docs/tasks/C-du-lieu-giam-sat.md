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
- [ ] Replication local: đã viết `db/docker-compose.repl.yml` + `local-up.sh`, **chưa chạy** (laptop chưa có Docker)
- [ ] Backup/restore local: đã viết `backup-mysql.sh` / `restore-mysql.sh` (local ghi ra thư mục), **chưa chạy**
- [ ] Monitoring local + email thật: đã viết `monitoring/` + `local-up.sh` + `send-test-alert.sh`, **chưa chạy** (cần Docker + Gmail App Password)
- [ ] Rules + dashboard: 6 luật kế hoạch + 3 luật dữ liệu, unit test promtool, dashboard 20 panel; **chưa chạy `check.sh`** (cần Docker)
- [ ] Bảng chi phí: bản nháp `docs/cost/chi-phi.md` (3 phương án tính lại: 14,9 / 6,7 / 5,9 triệu đ/tháng); còn kiểm lại bằng Pricing Calculator + số thật từ Billing
- [ ] `scripts/cj-health.sh`: đã viết, chưa chạy trên cụm
- [ ] Báo cáo: nháp phần C `docs/report/C-du-lieu-giam-sat.md` + khung báo cáo chính `docs/report/bao-cao.md`; còn số liệu đo, ảnh
- [ ] Stack `cj-data` trên cụm → báo B: bản nháp `heat/cj-data.yaml` + `deploy-cj-data.sh` xong, chưa deploy
- [ ] Cron backup lên Swift (có trong `db/vm-bootstrap.sh`, chưa chạy thật)
- [ ] Stack `cj-mon` với alarm_url thật: bản nháp `heat/cj-mon.yaml` + `deploy-cj-mon.sh` xong, chưa deploy
- [ ] Minh chứng HM 3, 4, 7, 8
- [ ] Báo cáo ghép + PDF

## Nhật ký
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
