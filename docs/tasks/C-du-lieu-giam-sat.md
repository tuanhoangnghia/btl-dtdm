# Nhiệm vụ C – Lưu trữ, CSDL, giám sát, chi phí, ghép báo cáo (HM 3, 4, 7, 8)

**Người phụ trách:** ______  · **Bắt đầu ngay, không cần chờ cụm:** 28–30/10 làm trên laptop bằng Docker.

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
- [ ] Schema chốt với B
- [ ] Replication local
- [ ] Backup/restore local
- [ ] Monitoring local + email thật
- [ ] Rules + dashboard
- [ ] Bảng chi phí
- [ ] Stack `cj-data` trên cụm → báo B
- [ ] Cron backup lên Swift
- [ ] Stack `cj-mon` với alarm_url thật
- [ ] Minh chứng HM 3, 4, 7, 8
- [ ] Báo cáo ghép + PDF

## Nhật ký
- 
