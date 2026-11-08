# Prometheus trên máy monitor (10.0.2.11, cj_role=monitor). KE_HOACH 12.1.
# Render bằng render.sh (envsubst chỉ thay ${MON_AC_ID}, ${MON_AC_SECRET} = application credential của cj-monitor, role reader).
# Máy web/worker do ASG tạo nên không có IP cố định: tìm qua openstack_sd, lọc theo metadata cj_role (CONTRACT 4).
global:
  scrape_interval: 5s
  evaluation_interval: 5s
  external_labels: {cluster: cloudjudge}

rule_files: [/etc/prometheus/rules.yml]

alerting:
  alertmanagers: [{static_configs: [{targets: ['localhost:9093']}]}]

scrape_configs:
  # node_exporter :9100 trên mọi VM có cj_role (bỏ bastion: sg-bastion không mở 9100; bỏ máy builder không có cj_role)
  - job_name: node
    openstack_sd_configs: &os_sd
      - role: instance
        region: RegionOne
        identity_endpoint: http://10.10.0.10:5000/v3
        application_credential_id: '${MON_AC_ID}'
        application_credential_secret: '${MON_AC_SECRET}'
        port: 9100
        refresh_interval: 15s     # máy scale in biến khỏi danh sách nhanh, tránh InstanceDown giả
    relabel_configs:
      - {source_labels: [__meta_openstack_instance_status], regex: ACTIVE, action: keep}
      - {source_labels: [__meta_openstack_tag_cj_role], regex: 'web|worker|mysql-primary|mysql-replica|rabbitmq|monitor', action: keep}
      - {source_labels: [__meta_openstack_tag_cj_role], target_label: role}
      - {source_labels: [__meta_openstack_instance_name], target_label: instance}

  # web :8000/metrics (cj_submissions_total, cj_pending_submissions, cj_oldest_pending_seconds)
  - job_name: web
    openstack_sd_configs: *os_sd
    relabel_configs:
      - {source_labels: [__meta_openstack_instance_status], regex: ACTIVE, action: keep}
      - {source_labels: [__meta_openstack_tag_cj_role], regex: web, action: keep}
      - {source_labels: [__meta_openstack_private_ip], target_label: __address__, replacement: '$1:8000'}
      - {source_labels: [__meta_openstack_tag_cj_role], target_label: role}
      - {source_labels: [__meta_openstack_instance_name], target_label: instance}

  # worker :9200/metrics (cj_graded_total, cj_grade_duration_seconds)
  - job_name: worker
    openstack_sd_configs: *os_sd
    relabel_configs:
      - {source_labels: [__meta_openstack_instance_status], regex: ACTIVE, action: keep}
      - {source_labels: [__meta_openstack_tag_cj_role], regex: worker, action: keep}
      - {source_labels: [__meta_openstack_private_ip], target_label: __address__, replacement: '$1:9200'}
      - {source_labels: [__meta_openstack_tag_cj_role], target_label: role}
      - {source_labels: [__meta_openstack_instance_name], target_label: instance}

  # RabbitMQ :15692 (plugin rabbitmq_prometheus, per-object metrics bật trong monitoring/rabbitmq/rabbitmq.conf)
  - job_name: rabbitmq
    static_configs:
      - {targets: ['10.0.2.10:15692'], labels: {role: rabbitmq, instance: cj-rabbitmq}}

  # mysqld_exporter :9104 trên 2 máy MySQL
  - job_name: mysql
    static_configs:
      - {targets: ['10.0.3.10:9104'], labels: {role: mysql-primary, instance: cj-mysql-primary}}
      - {targets: ['10.0.3.11:9104'], labels: {role: mysql-replica, instance: cj-mysql-replica}}

  - job_name: prometheus
    static_configs: [{targets: ['localhost:9090'], labels: {role: monitor, instance: cj-monitor}}]
  - job_name: alertmanager
    static_configs: [{targets: ['localhost:9093'], labels: {role: monitor, instance: cj-monitor}}]
