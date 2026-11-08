# Alertmanager (KE_HOACH 12.3). Render bằng render.sh: envsubst chỉ thay các biến ${...} dưới đây.
#   SMTP_USER, SMTP_APP_PASSWORD, ALERT_EMAIL_TO: ~/secrets/data.env (Gmail + App Password, cổng 587 vì GCE chặn 25)
#   WEB_UP_URL ... WORKER_DOWN_URL: alarm_url của 4 ScalingPolicy trong cj-app (~/secrets/app-alarms.env, B ghi)
# File đã render có secret: render.sh đặt quyền 600, owner nobody (user chạy alertmanager trong container).
global:
  smtp_smarthost: 'smtp.gmail.com:587'
  smtp_from: 'CloudJudge <${SMTP_USER}>'
  smtp_auth_username: '${SMTP_USER}'
  smtp_auth_password: '${SMTP_APP_PASSWORD}'
  smtp_require_tls: true

route:
  receiver: email
  group_by: [alertname]
  group_wait: 10s
  group_interval: 30s
  repeat_interval: 1h
  routes:
    # Co giãn: gọi alarm_url, lặp lại khi cảnh báo còn firing (Heat có cooldown và chặn ở min/max của ASG).
    # continue: true để QueueHigh / WebCPUHigh (có severity) vẫn đi tiếp xuống route email.
    - {matchers: ['action="worker_up"'],   receiver: worker-up,   group_wait: 0s, group_interval: 1m, repeat_interval: 1m, continue: true}
    - {matchers: ['action="worker_down"'], receiver: worker-down, group_wait: 0s, group_interval: 1m, repeat_interval: 1m}
    - {matchers: ['action="web_up"'],      receiver: web-up,      group_wait: 0s, group_interval: 2m, repeat_interval: 2m, continue: true}
    - {matchers: ['action="web_down"'],    receiver: web-down,    group_wait: 0s, group_interval: 5m, repeat_interval: 5m}
    - {matchers: ['severity=~"warning|critical"'], receiver: email}

inhibit_rules:
  # máy MySQL chết thì không gửi thêm thư "replication dừng" của chính máy đó
  - source_matchers: ['alertname="MySQLDown"']
    target_matchers: ['alertname="ReplicationBroken"']
    equal: [instance]

receivers:
  - name: email
    email_configs:
      - to: '${ALERT_EMAIL_TO}'
        send_resolved: true
        headers:
          Subject: '[CloudJudge] {{ .Status | toUpper }}: {{ .CommonLabels.alertname }}{{ if .CommonLabels.severity }} ({{ .CommonLabels.severity }}){{ end }}'
  - name: worker-up
    webhook_configs: [{url: '${WORKER_UP_URL}', send_resolved: false}]
  - name: worker-down
    webhook_configs: [{url: '${WORKER_DOWN_URL}', send_resolved: false}]
  - name: web-up
    webhook_configs: [{url: '${WEB_UP_URL}', send_resolved: false}]
  - name: web-down
    webhook_configs: [{url: '${WEB_DOWN_URL}', send_resolved: false}]
