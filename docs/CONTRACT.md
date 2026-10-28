# Hợp đồng giao tiếp giữa 3 mảng (A – B – C)

> Đây là **thỏa thuận chung** để 3 người (3 phiên Claude) làm song song mà không giẫm chân nhau.
> **Muốn sửa file này:** mở PR riêng chỉ sửa file này, ghi vào mục Nhật ký thay đổi ở cuối, và phải được **cả 3 người** đồng ý trước khi merge. Không sửa lén trong PR khác.
> Phiên bản: **v1 – 28/10/2026**

---

## 1. Ai sở hữu file nào

Chỉ chủ sở hữu được sửa. Cần thay đổi ở phần của người khác thì nhắn họ hoặc mở issue, **không tự sửa**.

| Đường dẫn | Chủ | Ghi chú |
|---|---|---|
| `infra/**` | **A** | GCP, host, Kolla, bootstrap OpenStack |
| `heat/cj-net.yaml`, `heat/deploy-cj-net.sh` | **A** | mạng, router, security group, bastion |
| `scripts/demo-checks.sh` | **A** | thu minh chứng 8 hạng mục |
| `app/**` | **B** | web, worker, CLI seed, bài mẫu, docker-compose dev |
| `image/**` | **B** | golden image `cj-base-v1`, sandbox Dockerfile |
| `heat/cj-app.yaml`, `heat/web_member.yaml`, `heat/worker.yaml`, `heat/env/cj-app.env.yaml`, `heat/deploy-cj-app.sh` | **B** | LB, 2 ASG, scaling policy |
| `scripts/release.sh`, `scripts/loadtest.py` | **B** | |
| `db/**` | **C** | schema, user/grant MySQL, replication, backup |
| `monitoring/**` | **C** | Prometheus, Alertmanager, Grafana |
| `heat/cj-data.yaml`, `heat/cj-mon.yaml`, `heat/deploy-cj-data.sh`, `heat/deploy-cj-mon.sh` | **C** | |
| `scripts/cj-health.sh` | **C** | kiểm tra sức khỏe trước demo |
| `docs/cost/**`, `docs/report/` (file ghép chính) | **C** | |
| `docs/report/A-*.md`, `docs/evidence/A-*` | A | mỗi người viết phần báo cáo và minh chứng của mình |
| `docs/report/B-*.md`, `docs/evidence/B-*` | B | |
| `docs/report/C-*.md`, `docs/evidence/C-*` | C | |
| `docs/tasks/A-ha-tang.md` / `B-ung-dung.md` / `C-du-lieu-giam-sat.md` | A / B / C | mỗi người tự cập nhật tiến độ của mình |
| `docs/CONTRACT.md`, `KE_HOACH_TRIEN_KHAI.md`, `CLAUDE.md`, `.gitignore`, `README.md` | **chung** | chỉ sửa qua PR có cả 3 đồng ý |

## 2. Quy trình Git

- Repo GitHub private. Nhánh `main` được bảo vệ (chỉ merge qua PR).
- Nhánh làm việc: `a/<việc>`, `b/<việc>`, `c/<việc>`. Mỗi PR chỉ chạm file của chủ nhánh. Khi đó **không thể có conflict**.
- Mỗi ngày `git pull --rebase origin main` trước khi làm.
- Pre-commit `gitleaks` bắt buộc. Không commit bất kỳ secret nào (mục 9).

## 3. Quy tắc dùng chung cụm OpenStack

Chỉ có **1 cụm**: 3 máy GCP, project GCP do A tạo.

1. **Chỉ A** được chạy `kolla-ansible` và sửa cấu hình host/GCP. B và C cần gì thì nhắn A.
2. Bật/tắt cụm: ai cũng được làm (A cấp quyền IAM), **chỉ bằng** `infra/gcp/gcp-up.sh` / `gcp-down.sh`, **không** chạy `gcloud compute instances stop` hay bấm Stop trong Console. Khi làm việc phải giữ khóa: `infra/gcp/cj-lock.sh acquire <A|B|C> "lý do" [giờ]` và nhả khi xong (`release`). `gcp-down.sh` từ chối tắt nếu người khác đang giữ khóa (khóa tự hết hạn sau 4 giờ). Xem cách dùng ở `CLAUDE.md`.
3. Mỗi người dùng **user OpenStack riêng** (`tuan`, `trong`, `phuong`), role `admin` trên project `cloudjudge`. Truy cập: SSH vào controller **qua Tailscale** (hostname `cj-controller`), user Linux riêng.
4. Chỉ thao tác stack của mình: A → `cj-net`, C → `cj-data` và `cj-mon`, B → `cj-app`. **Không xóa hoặc update stack của người khác.**
5. Thứ tự stack phụ thuộc nhau: `cj-net` → `cj-data` → `cj-app` → `cj-mon`. Xóa thì theo thứ tự ngược lại, và phải báo trước.
6. Ghi lại tổng giờ chạy cụm (giới hạn ≤ 300 giờ, xem kế hoạch mục 1).

## 4. Hằng số mạng và tên

| Thứ | Giá trị |
|---|---|
| Controller (API OpenStack) | `10.10.0.10`, Keystone `http://10.10.0.10:5000/v3`, region `RegionOne` |
| ext-net | `ext-net`, 172.24.4.0/24 |
| Network / subnet | `net-public`/`subnet-public` 10.0.1.0/24 · `net-app`/`subnet-app` 10.0.2.0/24 · `net-data`/`subnet-data` 10.0.3.0/24 (DHCP pool .50–.200) |
| IP cố định | rabbitmq **10.0.2.10** · monitor **10.0.2.11** · mysql-primary **10.0.3.10** (az1) · mysql-replica **10.0.3.11** (az2) |
| AZ | `az1` (os-compute-1), `az2` (os-compute-2) |
| Flavor | `cj.tiny`, `cj.small`, `cj.medium` |
| Image | `ubuntu-24.04`, `cj-base-v1` |
| Keypair | không dùng, truy cập qua bastion/Tailscale; cloud-init tự thêm public key của 3 người |
| Metadata server `cj_role` | `web`, `worker`, `bastion`, `mysql-primary`, `mysql-replica`, `rabbitmq`, `monitor` |

### Cổng

| Cổng | Dịch vụ |
|---|---|
| 8000 | web (gunicorn): `/`, `/healthz`, `/metrics` |
| 9200 | worker `/metrics` |
| 9100 | node_exporter (mọi VM) |
| 9104 | mysqld_exporter |
| 5672 / 15672 / 15692 | RabbitMQ AMQP / management / prometheus |
| 3306 | MySQL |
| 9090 / 9093 / 3000 | Prometheus / Alertmanager / Grafana |

## 5. Output của các Heat stack

Đọc bằng `openstack stack output show <stack> <key> -f value -c output_value`.

| Stack (chủ) | Output key | Ý nghĩa |
|---|---|---|
| `cj-net` (A) | `net_public_id`, `subnet_public_id`, `net_app_id`, `subnet_app_id`, `net_data_id`, `subnet_data_id` | |
| | `sg_bastion_id`, `sg_web_id`, `sg_worker_id`, `sg_mq_id`, `sg_db_id`, `sg_monitor_id` | rule đúng như KE_HOACH mục 3.3, thêm 9200 vào sg-worker từ sg-monitor |
| | `router_id`, `bastion_fip` | |
| `cj-data` (C) | `db_primary_ip`, `db_replica_ip`, `mq_ip` | luôn bằng IP cố định ở mục 4; để output cho tường minh |
| `cj-app` (B) | `lb_fip` | A ghi vào `/etc/cloudjudge/lb_fip` cho DNAT |
| | `web_up_url`, `web_down_url`, `worker_up_url`, `worker_down_url` | alarm_url (bí mật), C dùng trong Alertmanager |

## 6. Golden image `cj-base-v1` (B xây, cả nhóm dùng)

Nội dung **bắt buộc có** (C cần các mục đánh dấu ★):
- Ubuntu 24.04; `docker.io`, `docker-compose-v2`; `prometheus-node-exporter` (cổng 9100, bật sẵn); `mysql-client` ★; `jq`, `curl`, `cron`.
- Docker image pull sẵn: `mysql:8.4` ★, `rabbitmq:4.1-management` ★, `prom/prometheus:v2.55.1` ★, `prom/alertmanager:v0.27.0` ★, `grafana/grafana-oss:11.3.0` ★, `prom/mysqld-exporter:v0.16.0` ★, `cj-sandbox:1` (B).
- `/opt/cj/venv`: flask, gunicorn, sqlalchemy, pymysql, pika, python-swiftclient, keystoneauth1, prometheus-client, prometheus-flask-exporter, python-openstackclient (lệnh `swift` có trong venv ★ cho backup).
- `/opt/cj/fetch-release.sh <ver>`: tải `releases/cloudjudge-<ver>.tar.gz` về `/opt/cj/app/`, đọc credential từ `/etc/cloudjudge/cloudjudge.env`.
- Tailscale đã cài nhưng **tắt** (chỉ bastion bật).
- Đã chạy `cloud-init clean`.

Nếu image trễ: C và A có thể dùng tạm `ubuntu-24.04` và cài Docker trong cloud-init (chậm hơn nhưng không bị chặn việc).

## 7. File cấu hình trong VM: `/etc/cloudjudge/cloudjudge.env`

Do user-data của Heat ghi (chmod 600, dạng `KEY=value`, không có dấu nháy). App **chỉ** đọc các key sau:

```
CJ_ROLE=web|worker
CJ_RELEASE=0.1.0
DB_PRIMARY_HOST=10.0.3.10
DB_REPLICA_HOST=10.0.3.11
DB_PORT=3306
DB_NAME=cloudjudge
DB_USER=cj_app
DB_PASSWORD=...
DB_RO_USER=cj_ro
DB_RO_PASSWORD=...
MQ_HOST=10.0.2.10
MQ_PORT=5672
MQ_USER=cj
MQ_PASSWORD=...
MQ_QUEUE=submissions
STORAGE_AUTH=appcred            # local dev: tempauth (ST_AUTH, ST_USER, ST_KEY)
OS_AUTH_URL=http://10.10.0.10:5000/v3
OS_REGION_NAME=RegionOne
OS_AC_ID=...                    # app credential của cj-web hoặc cj-worker tùy vai trò
OS_AC_SECRET=...
SWIFT_SUBMISSIONS=submissions
SWIFT_TESTCASES=testcases
SECRET_KEY=...                  # chỉ web; giống nhau trên mọi máy web
```

## 8. Dữ liệu và thông điệp

### 8.1. Swift
| Container | Object | Ghi | Đọc |
|---|---|---|---|
| `submissions` | `<submission_uuid>/main.cpp` hoặc `main.py` | web | worker (ACL) |
| `testcases` | `<problem_slug>/tests.zip` (gồm `1.in, 1.out, 2.in, …`) | web (giảng viên) | worker (ACL) |
| `releases` | `cloudjudge-<ver>.tar.gz` | người deploy (admin) | web, worker, backup |
| `backups` | `mysql/<YYYYmmdd-HHMM>.sql.gz` (header `X-Delete-After: 604800`) | cj-backup (ACL) | cj-backup |

### 8.2. RabbitMQ
- Vhost `/`, queue **`submissions`** (durable). Message JSON `{"submission_id": <int>}`, `delivery_mode=2`, `content_type=application/json`.
- Worker: `prefetch_count=1`, ack sau khi ghi kết quả vào DB.

### 8.3. MySQL
- Schema chuẩn: [`db/schema.sql`](../db/schema.sql) (C sở hữu). B viết model/truy vấn **khớp đúng** file này. Muốn thêm cột thì nhờ C (sửa schema + ghi nhật ký).
- User:

| User | Quyền | Dùng ở |
|---|---|---|
| `cj_app` | SELECT, INSERT, UPDATE trên `cloudjudge.*` | web, worker, CLI seed (ghi vào **Primary**) |
| `cj_ro` | SELECT trên `cloudjudge.*` | web `/scoreboard` (đọc từ **Replica**) |
| `repl` | REPLICATION SLAVE | replica |
| `exporter` | PROCESS, REPLICATION CLIENT, SELECT | mysqld_exporter |
| `backup` | SELECT, LOCK TABLES, SHOW VIEW, EVENT, TRIGGER, RELOAD, PROCESS | backup |

- Seed tài khoản và bài mẫu: **B** viết lệnh `python -m cloudjudge.cli seed` (băm mật khẩu bằng werkzeug, upload test lên Swift).
- Tài khoản demo: giảng viên `gv01`; sinh viên `sv01`…`sv05`; `loadtest` có `api_token`. Bài mẫu: `a-plus-b`, `slow-sum` (~1,5 giây/test × 4 test).

## 9. Metric Prometheus (B xuất, C dùng)

| Metric | Loại | Ở đâu | Ý nghĩa |
|---|---|---|---|
| `cj_submissions_total{language}` | counter | web :8000/metrics | số bài đã nhận |
| `cj_pending_submissions` | gauge | web | số bài `PENDING` + `RUNNING` (truy vấn DB khi scrape) |
| `cj_oldest_pending_seconds` | gauge | web | tuổi của bài `PENDING` lâu nhất, 0 nếu không có |
| `cj_graded_total{status}` | counter | worker :9200/metrics | số bài đã chấm theo kết quả |
| `cj_grade_duration_seconds` | histogram | worker | thời gian chấm 1 bài |
| `rabbitmq_queue_messages_ready{queue="submissions"}` | gauge | rabbitmq :15692 (C bật per-object metrics) | độ dài hàng đợi |

`GET /healthz` của web trả `200 {"status":"ok","host":"<hostname>","az":"<az>"}`; trả 503 nếu không kết nối được DB.

## 10. Secret

Nằm **trên controller**, quyền 600, **không bao giờ vào Git**. Mỗi người chỉ ghi file của mình; script deploy được đọc cả 3 file.

| File | Chủ | Biến |
|---|---|---|
| `~/secrets/infra.env` | A | `CJ_WEB_AC_ID`, `CJ_WEB_AC_SECRET`, `CJ_WORKER_AC_ID`, `CJ_WORKER_AC_SECRET`, `CJ_MONITOR_AC_ID`, `CJ_MONITOR_AC_SECRET`, `CJ_BACKUP_AC_ID`, `CJ_BACKUP_AC_SECRET`, `TS_BASTION_KEY`, `ADMIN_SSH_PUBKEYS` |
| `~/secrets/app.env` | B | `SECRET_KEY`, `LOADTEST_TOKEN` |
| `~/secrets/data.env` | C | `MYSQL_ROOT_PASSWORD`, `DB_PASSWORD`, `DB_RO_PASSWORD`, `REPL_PASSWORD`, `EXPORTER_PASSWORD`, `BACKUP_DB_PASSWORD`, `MQ_PASSWORD`, `SMTP_USER`, `SMTP_APP_PASSWORD`, `ALERT_EMAIL_TO` |

Thư mục `/home/*/secrets` dùng chung: A tạo group `cj` để cả 3 user Linux đọc được (`chmod 640`, group `cj`).

## 11. Các mốc bàn giao (giao xong thì nhắn nhóm)

| Ngày | Ai → ai | Bàn giao |
|---|---|---|
| 28/10 | C → B | `db/schema.sql` đã chốt (bản v1 có sẵn trong repo) |
| 30/10 | B → C | Danh sách image dựng sẵn ở mục 6 được giữ nguyên, hoặc báo nếu đổi |
| 31/10 | A → B, C | **Cụm sẵn sàng**: Tailscale, user Linux + OpenStack, `infra.env`, container Swift + ACL, stack `cj-net` |
| 31/10 | B → C | Image `cj-base-v1`; release `0.1.0` trên Swift |
| 1/11 | C → B | Stack `cj-data` chạy (MySQL replication, RabbitMQ), `data.env` đủ biến |
| 2/11 | B → A, C | Stack `cj-app`: `lb_fip`, 4 alarm_url |
| 2/11 | A | DNAT cổng 80 → `lb_fip` |
| 3/11 | C | Stack `cj-mon` có alarm_url thật, email chạy |
| 6/11 | cả nhóm | Tập demo lần 1 |

## Nhật ký thay đổi
- v1 (28/10/2026): bản đầu.
