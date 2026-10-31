# Nhiệm vụ B – Ứng dụng, image, cân bằng tải, tự mở rộng (HM 6)

**Người phụ trách:** Phương (OpenStack user `phuong`)  · **Bắt đầu ngay, không cần chờ cụm:** 28–30/10 làm hoàn toàn trên laptop.

Đọc trước: `docs/CONTRACT.md` (bắt buộc), `db/schema.sql`, `KE_HOACH_TRIEN_KHAI.md` mục 2 (D8, D9, D11), 9, 10, 11.3, 12.3, 12.5, 12.6, 14.1.

## Phạm vi
- **Được sửa:** `app/**`, `image/**`, `heat/cj-app.yaml`, `heat/web_member.yaml`, `heat/worker.yaml`, `heat/env/cj-app.env.yaml`, `heat/deploy-cj-app.sh`, `scripts/release.sh`, `scripts/loadtest.py`, `docs/report/B-*.md`, `docs/evidence/B-*`, file này.
- **Không sửa:** `db/schema.sql` (cần cột mới thì nhờ C), `heat/cj-net.yaml` (cần mở cổng thì nhờ A), `monitoring/**` (C).
- Code phải dùng **đúng** tên biến env, queue, container, metric trong CONTRACT mục 7–9.

## Giai đoạn 1 – Local (28–30/10)

Cấu trúc gợi ý:
```
app/
├─ cloudjudge/
│  ├─ common/   config.py (đọc env), db.py (engine primary + replica), storage.py (Swift: appcred | tempauth), mq.py
│  ├─ web/      __init__.py (create_app), routes.py, templates/, metrics.py
│  ├─ worker/   main.py (consumer), grader.py, sandbox.py, metrics.py (:9200)
│  └─ cli.py    seed, create-problem
├─ sample_problems/a-plus-b/{statement.md, tests/1.in,1.out,…, solutions/ok.cpp, wrong.py}
├─ sample_problems/slow-sum/…
├─ deploy/      install.sh <web|worker>, systemd/cj-web.service, systemd/cj-worker.service
├─ requirements.txt
└─ docker-compose.dev.yml   # mysql:8.4 (mount ../db/schema.sql vào /docker-entrypoint-initdb.d), rabbitmq:4.1-management, openstackswift/saio
image/
├─ build-cj-base.sh         # user-data cho VM builder (kế hoạch mục 9 + CONTRACT mục 6)
└─ sandbox/Dockerfile
```

| Ngày | Việc |
|---|---|
| 28/10 | Khung `app/`, `docker-compose.dev.yml` chạy được; `config.py`, `db.py`, `storage.py`, `mq.py` |
| 29/10 | Web: login, danh sách bài, nộp bài (Swift + DB + MQ), trang kết quả, `/scoreboard` đọc replica (local trỏ cùng MySQL), `/api/submit`, `/healthz`, `/metrics`, footer hostname + AZ |
| 30/10 | Worker + sandbox Docker (đủ cờ cách ly ở kế hoạch 10.4), `/metrics` :9200; CLI `seed`; 2 bài mẫu; `loadtest.py`; `release.sh`; `deploy/install.sh` + unit systemd; `image/build-cj-base.sh` |

✅ Xong giai đoạn 1 khi trên laptop: `docker compose up` → seed → nộp `a-plus-b` đúng ra 100, sai ra WRONG_ANSWER, lỗi cú pháp ra COMPILE_ERROR; `loadtest.py --n 20` chạy hết; `/metrics` có đủ metric ở CONTRACT mục 9.

## Giai đoạn 2 – Lên cụm (31/10–3/11), cần A bàn giao
| Ngày | Việc | Phụ thuộc |
|---|---|---|
| 31/10 | Build `cj-base-v1` (kế hoạch mục 9) trong `net-public`; upload release `0.1.0` lên `releases`. **Báo C khi image xong** | `cj-net` (A) |
| 1/11 | Viết `cj-app.yaml`, `web_member.yaml`, `worker.yaml`, `deploy-cj-app.sh` (đọc output `cj-net` và `cj-data`, 3 file secret). Tạo LB thử | `cj-data` (C) |
| 2/11 | `cj-app` đầy đủ: 2 web (2 AZ), 1 worker; output `lb_fip` + 4 alarm_url → **báo A (DNAT) và C (Alertmanager)** | |
| 3/11 | End-to-end qua `http://<CTL_IP>`; seed dữ liệu trên cụm | DNAT (A) |

## Giai đoạn 3 – Co giãn, demo (4–9/11)
| Ngày | Việc |
|---|---|
| 4/11 | Thử `curl -X POST <worker_up_url>` → thêm worker; cùng C nối Alertmanager; chạy loadtest 60 bài |
| 5/11 | Đo và chỉnh thời gian (kế hoạch 12.6): worker thứ 2 lên trước phút 4:00, về 1 trước phút 9:00. Thử tắt 1 web ở az1. Ghi số liệu đo vào `docs/evidence/B-*` |
| 6/11 | Tập demo lần 1 (B là người thao tác chính) |
| 7/11 | `docs/report/B-ung-dung.md`: kiến trúc app, stateless, hàng đợi, sandbox, LB, autoscale, kết quả đo |
| 8/11 | Quay video (B điều khiển) |

## Tiến độ
- [ ] Compose dev chạy được: đã viết `app/docker-compose.dev.yml` + `dev.env.example` + `dev/02-users.sql`, **chưa chạy thử** (laptop chưa có Docker). Thay bằng bộ pytest không cần Docker (32 test qua)
- [x] Web đủ route (login/logout, problems, submit, submissions, scoreboard đọc replica, teacher tạo bài, `/api/submit`, `/api/submissions/<id>`, `/healthz`, `/metrics`, footer hostname + AZ)
- [x] Worker + sandbox: đã chạy `docker run` thật (trên controller, 31/10): 7 lời giải mẫu đúng kết quả, 6 kiểu tấn công bị chặn (`docs/evidence/B-cum-31-10.txt`)
- [x] Seed, bài mẫu, loadtest, release, install.sh (+ unit systemd, `cj-cli`); `release.sh` đã đóng gói thử (NO_UPLOAD)
- [x] `image/build-cj-base.sh` + `image/build-image.sh` (tự tạo builder → chờ SHUTOFF → snapshot → xóa builder)
- [x] Heat `cj-app.yaml`, `web_member.yaml`, `worker.yaml`, `env/cj-app.env.yaml`, `deploy-cj-app.sh` (validate bằng Heat thật, stack chạy)
- [x] Image `cj-base-v1` trên cụm (min_disk 10 GB) → **cần báo C**
- [x] Release trên Swift: dùng **0.1.2** (0.1.0/0.1.1 đóng gói sai quyền, đừng dùng)
- [x] Stack `cj-app` CREATE/UPDATE_COMPLETE: `lb_fip` 172.24.4.64, web az1 + az2, 1 worker → **cần báo A (DNAT), C (`app-alarms.env`)**
- [ ] Nộp bài qua IP public ra điểm (**chờ C: `cj-data`**; chờ A: DNAT)
- [ ] Scale worker 1→3→1, số liệu đo: 1→2→1 qua API Heat đã đo (77 s / 15 s); **qua alarm_url bị 403, chờ A sửa heat-api-cfn**; theo hàng đợi chờ `cj-data` + `cj-mon`
- [ ] Failover web (chờ `cj-data`: chưa có DB thì /healthz 503, LB không có member khỏe)
- [ ] Báo cáo phần B (đã có nháp `docs/report/B-ung-dung.md`, còn thiếu số liệu đo)

## Nhật ký
- 31/10 tối (B): **Lên cụm.** Khóa B, SSH `cj-controller` (user `phuong`), repo đưa lên `~/cloudjudge` bằng git bundle. A đã tạo sẵn `app.env`, `data.env`, `chmod 1770 /home/cj/secrets`.
  - **Image**: `cj-base-v1` đầu tiên (một phiên trước build trên `cj.medium`) có `min_disk` 20 GB → Nova từ chối boot trên `cj.small` (web, và RabbitMQ của C). Build lại trên builder `cj.small` (325 s) → `min_disk` 10. Image cũ đổi tên `cj-base-v1-old-202610311751`, chưa xóa.
  - **Heat**: `description` không có nháy trong `{...}` chứa dấu phẩy làm hỏng tham số; Heat bản này không nhận `max_retries_down`. Đã sửa, validate bằng `openstack orchestration template validate`.
  - **Release**: 0.1.0/0.1.1 có thư mục gốc quyền 700 (mktemp + umask 027) → `cjsvc` không đọc được code, web/worker không chạy. `release.sh` đã `chmod -R go=rX`, `install.sh` cũng sửa quyền. Dùng **0.1.2**.
  - **AZ**: 1 ASG + soft-anti-affinity cho 2 web cùng rơi vào az1 (tạo song song, trọng số RAM). Tách 2 ASG ghim AZ: `web_asg_az2` luôn 1 máy, `web_asg_az1` 1–2 máy (đích của web_up/web_down). Tham số `web_min/web_max` đổi thành `web_az1_min/web_az1_max`.
  - **Scale**: qua API Heat (`openstack stack resource signal cj-app worker_up`): server mới ACTIVE sau 22 s, cài xong + `:9200` OK sau **77 s**; `worker_down` còn 1 máy sau **15 s**.
  - **alarm_url bị 403** (đường Alertmanager dùng): heat-api-cfn gọi Keystone `/v3/ec2tokens` không có xác thực, Keystone 2025.x từ chối (401). Cần A thêm credential vào `[ec2authtoken]` của Heat (xem tin nhắn cho A). Trong lúc chờ, phương án D11 (gọi `stack resource signal`) chạy được.
  - **`app-alarms.env`**: URL có `&` nên phải để trong nháy đơn mới `source` được; đã sửa `deploy-cj-app.sh`.
  - **Sandbox**: chạy `docker run` thật trên controller (Docker của Kolla tắt bridge nên build phải `--network host`). Phát hiện deadlock khi bài in vô hạn (luồng đọc gọi `docker kill` đồng bộ) → sửa (kill ở luồng riêng có timeout, vẫn đọc tiếp). Image thử đã xóa khỏi controller.
  - **Chưa vào được VM qua bastion**: bastion tạo trước khi A thêm key của `phuong` vào `admin_ssh_pubkeys.txt`. VM web/worker có key (tạo sau). Đang đọc kết quả qua `openstack console log show`.
- 31/10 (B): Làm toàn bộ phần không phụ thuộc A/C trên nhánh `b/app-phase1`.
  - **App** (`app/`): Flask + SQLAlchemy Core, bảng khớp `db/schema.sql`. Mọi mốc thời gian app ghi là UTC do app tự đặt (không dùng `CURRENT_TIMESTAMP` của DB) để `cj_oldest_pending_seconds` đúng trên mọi máy. CSRF token cho form, cookie ký `SECRET_KEY`. Bộ render markdown tự viết (venv trong image không có thư viện markdown), có escape HTML.
  - **Swift**: chỉ dùng `put_object/get_object/head_object` (user có quyền qua ACL bị 403 nếu PUT container, xem nhật ký A 29/10). Local dùng tempauth (`openstackswift/saio`).
  - **MQ**: web mở kết nối ngắn cho mỗi lần publish + publisher confirm (tránh kết nối chết do gunicorn không xử lý heartbeat). Worker heartbeat 300 s vì callback chấm chạy đồng bộ. Queue khai báo `durable=True`, **không có argument nào** (C khai báo queue thì phải giống hệt, nếu không sẽ lỗi PRECONDITION_FAILED).
  - **Worker**: at-least-once, idempotent (bài đã có kết quả cuối thì bỏ qua, đang `RUNNING` thì chấm lại). Mất DB → nack requeue + nghỉ 5 s. SIGTERM (scale in) → đóng kết nối, bài chưa ack về hàng đợi. Python: kiểm cú pháp bằng `ast.parse` trên worker → `COMPILE_ERROR`. C++: biên dịch trong sandbox (mount rw riêng bước này, 512 MB, 30 s).
  - **Sandbox**: `cj-run` (PID 1 trong container) đo thời gian chỉ của chương trình, không tính thời gian docker tạo container; kết quả in ở dòng cuối stderr. Output bị chặn ở 8 MB.
  - **Metric**: web dùng `PROMETHEUS_MULTIPROC_DIR` (gunicorn 3 tiến trình). `cj_pending_submissions`/`cj_oldest_pending_seconds` mọi máy web báo cùng giá trị toàn cục → C phải dùng `max()`.
  - **Bài mẫu**: `a-plus-b` 6 test (2 test ±9·10^18 làm tràn `long long` → `overflow.cpp` ra WRONG_ANSWER 67 điểm), lời giải `ok.cpp/ok.py/wrong.py/compile_error.cpp/tle.py`. `slow-sum` 4 test dãy LCG n = 3·10^8, đáp án tính bằng phép nhảy affine O(log n) (`gen.py`, đã đối chiếu với duyệt trực tiếp). **Cần đo trên worker thật** rồi chỉnh n bằng `python gen.py <n>` để đạt ~1,5 s/test.
  - **Seed**: `cj-cli seed` chạy lại được; mật khẩu demo từ `CJ_SEED_PASSWORD` hoặc sinh ngẫu nhiên in 1 lần; token loadtest từ `LOADTEST_TOKEN` (`~/secrets/app.env`), phải dài đúng 64 ký tự (`openssl rand -hex 32`).
  - **Image**: `build-image.sh` nhúng `image/sandbox/*` vào user-data (base64), builder lỗi thì in `CJ_BUILD_FAILED` và không tắt máy. Image Docker pull đúng tag cố định ở CONTRACT mục 6 (KE_HOACH mục 9 còn ghi `:latest`, đã theo CONTRACT).
  - **Heat**: tên máy `cj-web-<8 ký tự>` / `cj-worker-<8 ký tự>`; web ASG `rolling_updates` min_in_service 1. `deploy-cj-app.sh` truyền secret qua file tham số tạm (600), từ chối giá trị có khoảng trắng/nháy/`$`/`\`; ghi 4 alarm_url vào `<thư mục secret>/app-alarms.env` (640, group cj) cho C.
  - **Kiểm thử**: `app/tests/` 32 test qua (web, API, CSRF, phân quyền, metrics, scoreboard, seed idempotent, grader AC/WA/TLE/RE/CE, Judge idempotent/chấm lại, cờ cách ly docker, cj-run, end-to-end HTTP + loadtest 20 bài).
  - **Còn chờ**: A bàn giao user Linux `phuong` + SSH key + Tailscale (để chạy `build-image.sh`, `release.sh`); C xong `cj-data` (để `deploy-cj-app.sh`).
