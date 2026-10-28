# Nhiệm vụ B – Ứng dụng, image, cân bằng tải, tự mở rộng (HM 6)

**Người phụ trách:** ______  · **Bắt đầu ngay, không cần chờ cụm:** 28–30/10 làm hoàn toàn trên laptop.

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
- [ ] Compose dev chạy được
- [ ] Web đủ route
- [ ] Worker + sandbox
- [ ] Seed, bài mẫu, loadtest, release, install.sh
- [ ] `image/build-cj-base.sh`
- [ ] Image `cj-base-v1` trên cụm → báo C
- [ ] Release 0.1.0 trên Swift
- [ ] Stack `cj-app` → báo A, C
- [ ] Nộp bài qua IP public ra điểm
- [ ] Scale worker 1→3→1, số liệu đo
- [ ] Failover web
- [ ] Báo cáo phần B

## Nhật ký
- 
