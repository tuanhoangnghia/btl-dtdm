# Gunicorn cho cj-web (KE_HOACH 10.3: -w 3 -b 0.0.0.0:8000)
bind = "0.0.0.0:8000"
workers = 3
timeout = 30
graceful_timeout = 10
accesslog = "-"
errorlog = "-"
access_log_format = '%(h)s "%(r)s" %(s)s %(b)s %(M)sms'


def child_exit(server, worker):
    # prometheus_client multiprocess: dọn file metric của tiến trình con đã chết
    from prometheus_client import multiprocess
    multiprocess.mark_process_dead(worker.pid)
