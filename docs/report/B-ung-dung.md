# Phần B – Ứng dụng, golden image, cân bằng tải, tự mở rộng (bản nháp 31/10/2026)

> Hạng mục phụ trách: **6** (cân bằng tải, tự mở rộng, chịu lỗi tầng ứng dụng); phần ứng dụng dùng cho HM 3, 4, 5, 7.
> Mã: `app/`, `image/`, `heat/cj-app.yaml` + 2 template con, `scripts/release.sh`, `scripts/loadtest.py`.
> **Còn thiếu:** số liệu đo trên cụm (mục 7) và ảnh chụp. Điền sau khi tập demo ngày 5–6/11.

## 1. Kiến trúc ứng dụng

```
Người dùng ──HTTP:80──► controller (DNAT) ──► floating IP ──► Octavia LB (ACTIVE_STANDBY, 2 amphora)
                                                              │ health check GET /healthz
                                     ┌────────────────────────┴───────────────────────┐
                                web (az1)                                         web (az2)          ASG web 2–3
                                  │  ① lưu mã → Swift submissions/<uuid>/main.cpp
                                  │  ② INSERT PENDING → MySQL Primary
                                  │  ③ publish {"submission_id"} → RabbitMQ queue submissions (durable)
                                  ▼
                       worker ×1..3 (ASG)  ── consume prefetch=1 ── tải mã + tests.zip từ Swift
                                  │          docker run sandbox (từng test) → UPDATE kết quả → ack
                                  ▼
                       /scoreboard đọc MySQL Replica (cj_ro)
Prometheus scrape web :8000/metrics, worker :9200/metrics, RabbitMQ → Alertmanager → alarm_url của Heat
```

| Thành phần | Công nghệ | Chạy ở |
|---|---|---|
| Web/API | Flask 3 + Gunicorn (3 tiến trình), SQLAlchemy Core, PyMySQL | VM `cj.small` từ `cj-base-v1`, systemd `cj-web` |
| Worker | Python, pika, Docker CLI | VM `cj.medium`, systemd `cj-worker` |
| Sandbox | image `cj-sandbox:1` (python:3.12-slim + g++), chương trình đo giờ `cj-run` | container ngắn hạn trên worker |
| Phân phối mã | tarball `releases/cloudjudge-<ver>.tar.gz` trên Swift, tải khi boot | mọi VM web/worker |

## 2. Web không lưu trạng thái
- Phiên đăng nhập là **cookie ký** bằng `SECRET_KEY`, giống nhau trên mọi máy web, nên LB gửi request tới máy nào cũng được (không cần sticky session).
- Mã nguồn bài nộp nằm trên **Swift**, dữ liệu trên **MySQL**, việc chấm đẩy qua **RabbitMQ**. Máy web không giữ gì trên đĩa, nên tắt hay thay máy web không mất dữ liệu.
- Footer mỗi trang và `/healthz` trả **hostname + AZ** (đọc metadata `169.254.169.254`), để demo thấy LB chia tải sang 2 AZ và thấy hostname đổi khi một máy chết.

## 3. Hàng đợi và đảm bảo giao nhận
- Queue `submissions` durable, message persistent (`delivery_mode=2`). Web bật **publisher confirm**, nên chỉ trả lời "đã nhận" khi broker đã ghi thông điệp. Publish lỗi thì bài được đánh dấu `SYSTEM_ERROR` và người dùng thấy lỗi ngay (không có bài "treo" PENDING mãi).
- Worker dùng `prefetch_count=1` và **ack sau khi ghi kết quả vào DB**, tức giao nhận **at-least-once**. Cập nhật là **idempotent** theo `submission_id`: bài đã có kết quả cuối thì bỏ qua; bài đang `RUNNING` (máy trước chết giữa chừng) thì chấm lại.
- Khi scale in, Heat xóa VM → systemd gửi SIGTERM → worker đóng kết nối mà không ack, nên bài đang chấm dở quay lại hàng đợi cho worker khác.
- Lỗi hệ thống khi chấm (thiếu object, Docker lỗi) → `SYSTEM_ERROR` rồi ack, để một bài lỗi không quay vòng mãi. Mất DB → trả thông điệp lại hàng đợi (nack requeue) và nghỉ 5 giây.

## 4. Sandbox chấm bài
Mỗi lần biên dịch và mỗi test chạy trong một container `docker run --rm` riêng:

| Cờ | Tác dụng |
|---|---|
| `--network none` | không có mạng (không gọi ra ngoài, không tấn công máy khác) |
| `--read-only`, `--tmpfs /tmp:size=16m` | không ghi được hệ thống file, chỉ có 16 MB tạm |
| `--memory M --memory-swap M` | giới hạn RAM theo đề (cgroup), không dùng swap |
| `--cpus 1`, `--pids-limit 64` | giới hạn CPU, chặn fork bomb |
| `--cap-drop ALL`, `--security-opt no-new-privileges`, `--user 10001` | không có quyền root, không leo thang quyền |
| `-v <workdir>:/work:ro` | chỉ đọc mã/file chạy; chỉ bước biên dịch C++ mount rw |

- `cj-run` (PID 1 trong container) đo **thời gian riêng của chương trình** (không tính thời gian Docker tạo container), giết chương trình khi quá giới hạn, đặt thêm `RLIMIT_CPU`. Kết quả in ở dòng cuối stderr sau khi chương trình đã kết thúc, nên bài làm không giả mạo được.
- Output bị chặn ở 8 MB. So sánh output bỏ khoảng trắng cuối dòng và các dòng trống cuối file.
- Python: kiểm cú pháp bằng `ast.parse` (không thực thi) → `COMPILE_ERROR`. C++: `g++ -O2 -std=c++17`.
- Giới hạn còn lại: worker phải có quyền gọi Docker daemon (tương đương root trên máy worker). Chấp nhận vì worker không giữ secret quan trọng ngoài credential chỉ-đọc `cj-worker`. Có thể nâng cấp bằng gVisor hoặc rootless Docker.

## 5. Golden image và phát hành
- `cj-base-v1` (KE_HOACH D8) build tự động bằng `image/build-image.sh`: VM builder chạy user-data `build-cj-base.sh` (cài Docker, node_exporter, venv `/opt/cj/venv`, pull sẵn image MySQL/RabbitMQ/Prometheus/Grafana, build `cj-sandbox:1`, cài Tailscale nhưng tắt), tự tắt máy, rồi script snapshot thành image và xóa builder. Một image dùng cho mọi vai trò; vai trò do cloud-init chọn.
- Mã ứng dụng **không nằm trong image**: `scripts/release.sh <ver>` đóng gói và upload lên Swift `releases`. Khi boot, máy tải đúng version bằng application credential của chính nó (`/opt/cj/fetch-release.sh`) rồi chạy `deploy/install.sh web|worker`. Đổi code = upload version mới + `heat/deploy-cj-app.sh <ver>`; ASG web thay **từng máy một** (`rolling_updates: min_in_service 1`), nên không gián đoạn.
- Lợi ích: máy scale out boot nhanh (không cài gói), image ít phải build lại.

## 6. Cân bằng tải và tự mở rộng (HM 6)
- **Octavia** ACTIVE_STANDBY (2 amphora ở 2 host, VRRP): listener HTTP :80 → pool ROUND_ROBIN → web :8000. Health monitor `GET /healthz` mỗi 5 s, timeout 3 s, 2 lần lỗi thì loại máy. `/healthz` trả 503 nếu web mất kết nối DB, nên LB cũng loại máy web "sống nhưng hỏng".
- Pool member **không khai báo subnet**: amphora đi tới web qua router từ 10.0.1.x, nên sg-web chỉ mở 8000 cho 10.0.1.0/24 và worker không gọi thẳng được web (HM 2).
- 2 `OS::Heat::AutoScalingGroup`: web 2–3 máy, worker 1–3 máy; mỗi nhóm có `ServerGroup soft-anti-affinity` để rải máy sang 2 host = 2 AZ.
- 4 `OS::Heat::ScalingPolicy` (`change_in_capacity` ±1). Alertmanager gọi thẳng `alarm_url` (URL đã ký của heat-api-cfn), không cần Aodh/Ceilometer:

| Chính sách | Kích hoạt bởi (C, `monitoring/rules.yml`) | Cooldown |
|---|---|---|
| worker_up | `QueueHigh`: hàng đợi > 10 trong 30 s | 60 s |
| worker_down | `QueueIdle`: hàng đợi = 0 trong 1 phút và > 1 worker | 60 s |
| web_up | `WebCPUHigh`: CPU web > 70% trong 1 phút | 120 s |
| web_down | `WebCPULow`: CPU web < 20% trong 5 phút và > 2 web | 300 s |

- **Vì sao co giãn worker theo độ dài hàng đợi, không theo CPU:** worker 1 vCPU luôn chạy 100% CPU khi đang chấm, dù hàng đợi có 1 bài hay 100 bài. Độ dài hàng đợi đo đúng "việc còn tồn", và cùng với tốc độ chấm (~8 bài/phút/worker) cho biết thời gian chờ.
- **Cooldown** chống dao động (flapping): sau mỗi lần scale phải chờ máy mới boot xong và nhận việc thì mới đánh giá lại.

## 7. Kết quả đo (điền sau khi chạy trên cụm)
| Đại lượng | Giá trị |
|---|---|
| Thời gian chấm 1 bài `a-plus-b` (lúc rảnh) | _ s |
| Thời gian 1 test `slow-sum` / 1 bài | _ s / _ s |
| Loadtest 60 bài: chờ trung bình / p95 (1 worker cố định) | _ / _ |
| Loadtest 60 bài: chờ trung bình / p95 (có autoscale) | _ / _ |
| Alert firing → worker mới ACTIVE → nhận bài đầu tiên | _ s → _ s |
| Hàng đợi rỗng → thu về 1 worker | _ s |
| Tắt 1 web ở az1 → LB ngừng gửi request tới máy đó | _ s |

## 8. Kiểm thử
`app/tests/` (pytest, 32 test, chạy không cần MySQL/RabbitMQ/Swift/Docker): route web và API, CSRF, phân quyền xem bài, `/metrics`, scoreboard đọc replica, giảng viên tạo bài, seed chạy lại được, grader (ACCEPTED, WRONG_ANSWER có điểm một phần, TIME_LIMIT, RUNTIME_ERROR, COMPILE_ERROR), worker idempotent và chấm lại bài `RUNNING`, đủ cờ cách ly của lệnh `docker run`, `cj-run`, và một bài end-to-end: web HTTP thật + worker + `scripts/loadtest.py` nộp 20 bài, chấm đủ 20.
