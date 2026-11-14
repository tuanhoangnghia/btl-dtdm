# CloudJudge app (phần B)

Web/API Flask + worker chấm bài + CLI. Hợp đồng tên biến/queue/container/metric: [`docs/CONTRACT.md`](../docs/CONTRACT.md).

```
cloudjudge/
  common/  config.py (đọc env) · db.py (bảng, engine primary/replica) · storage.py (Swift appcred|tempauth)
           mq.py (RabbitMQ) · problems.py (tests.zip, tạo bài) · instance.py (hostname + AZ)
  web/     __init__.py (create_app) · routes.py (HTML) · api.py (/api/*) · submit.py · metrics.py · templates/
  worker/  main.py (consumer) · grader.py · sandbox.py (docker run) · metrics.py (:9200)
  cli.py   seed · create-problem · set-password
sample_problems/   a-plus-b (bài nhanh, có lời giải đúng/sai/lỗi), slow-sum (~1,5 s/test, dùng cho loadtest)
deploy/            install.sh <web|worker> · systemd/ · gunicorn.conf.py · cj-cli
tests/             pytest, không cần MySQL/RabbitMQ/Swift/Docker
```

## Kiểm thử nhanh (không cần Docker)
```bash
cd app
python -m venv .venv && . .venv/bin/activate     # Windows: .venv\Scripts\activate
pip install -r requirements.txt pytest
python -m pytest -q tests
```
Test dùng SQLite trong RAM và các bản giả cho Swift/MQ. Sandbox giả chạy thật `image/sandbox/cj-run`
(không cách ly), và `test_e2e.py` chạy `scripts/loadtest.py --n 20` qua HTTP.

## Chạy local đầy đủ (cần Docker)
```bash
cd app
docker compose -f docker-compose.dev.yml up -d          # mysql:8.4 (nạp ../db/schema.sql), rabbitmq, swift saio
cp dev.env.example dev.env
export CJ_ENV_FILE=dev.env
python -m cloudjudge.cli seed                            # gv01, sv01..sv05 (mật khẩu CJ_SEED_PASSWORD), loadtest + token
flask --app "cloudjudge.web:create_app()" run -p 8000    # http://127.0.0.1:8000
docker build -t cj-sandbox:1 ../image/sandbox            # worker cần image sandbox
python -m cloudjudge.worker.main                         # Linux/WSL: worker gọi docker run
python ../scripts/loadtest.py --base http://127.0.0.1:8000 --token <token in ra khi seed> --n 20
```

## Trên cụm (B làm trên controller, sau khi A bàn giao)
```bash
git clone <repo> ~/cloudjudge && cd ~/cloudjudge
bash image/build-image.sh                 # 1) golden image cj-base-v1 (~15–20 phút) → báo C
bash scripts/release.sh 0.1.0             # 2) upload releases/cloudjudge-0.1.0.tar.gz
bash heat/deploy-cj-app.sh 0.1.0          # 3) stack cj-app → báo A lb_fip, báo C app-alarms.env
# 4) seed trên 1 máy web (qua bastion): ssh -J cj@<bastion> cj@<web-ip> 'sudo cj-cli seed'
```
Đổi code: sửa → `bash scripts/release.sh 0.1.1` → `bash heat/deploy-cj-app.sh 0.1.1` (ASG thay từng máy web).

Xem log trên VM: `journalctl -u cj-web -f`, `journalctl -u cj-worker -f`, `sudo cat /var/log/cloud-init-output.log`.

## Ghi chú thiết kế
- **Web không lưu trạng thái**: session là cookie ký bằng `SECRET_KEY` chung, mã nguồn ở Swift, dữ liệu ở MySQL.
- **Ghi Primary, đọc Replica**: chỉ `/scoreboard` đọc replica (`cj_ro`); replica lỗi thì đọc tạm primary và ghi rõ trên trang.
- **Hàng đợi at-least-once**: worker `prefetch_count=1`, ack sau khi ghi DB; cập nhật idempotent theo `submission_id`
  (đã có kết quả cuối thì bỏ qua, đang `RUNNING` thì chấm lại). SIGTERM khi scale in: bài chưa ack quay lại hàng đợi.
- **Sandbox**: mỗi lần biên dịch / mỗi test là 1 `docker run --rm` với `--network none --read-only --memory
  --pids-limit 64 --cap-drop ALL --security-opt no-new-privileges --user 10001`. Thời gian đo bởi `cj-run` trong container.
- **Metric**: `cj_pending_submissions` và `cj_oldest_pending_seconds` là giá trị toàn cục (truy vấn DB), mọi máy web
  báo cùng số → gộp bằng `max()`. `cj_submissions_total` gộp qua nhiều tiến trình gunicorn bằng `PROMETHEUS_MULTIPROC_DIR`.
