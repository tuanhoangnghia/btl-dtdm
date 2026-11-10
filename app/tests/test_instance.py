import io
import json

from cloudjudge.common import instance


def test_metadata_failure_is_retried_not_cached(monkeypatch):
    monkeypatch.setattr(instance, "_az", None)
    monkeypatch.setattr(instance, "_retry_at", 0.0)
    now = [100.0]
    monkeypatch.setattr(instance.time, "monotonic", lambda: now[0])
    up = [False]

    def urlopen(url, timeout):
        if not up[0]:
            raise OSError("metadata chưa lên")
        return io.BytesIO(json.dumps({"availability_zone": "az1"}).encode())

    monkeypatch.setattr(instance.urllib.request, "urlopen", urlopen)
    assert instance.instance_info()[1] == "local"
    up[0] = True
    assert instance.instance_info()[1] == "local"      # chưa hết thời gian chờ thử lại
    now[0] += instance.RETRY_S
    assert instance.instance_info()[1] == "az1"
    up[0] = False
    assert instance.instance_info()[1] == "az1"        # đã biết AZ thì không hỏi lại
