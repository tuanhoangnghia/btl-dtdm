# cj-sandbox:1: môi trường chạy bài của sinh viên (KE_HOACH 10.4).
# Worker gọi `docker run` với --network none, --read-only, giới hạn RAM/CPU/PID, --cap-drop ALL, user 10001.
# Đổi file này hoặc cj-run thì tăng tag (cj-sandbox:2) và sửa SANDBOX_IMAGE trong app/cloudjudge/worker/sandbox.py.
FROM python:3.12-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends g++ \
 && rm -rf /var/lib/apt/lists/*
RUN useradd -u 10001 -m runner
COPY cj-run /usr/local/bin/cj-run
RUN chmod 755 /usr/local/bin/cj-run
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=0
WORKDIR /work
USER 10001:10001
