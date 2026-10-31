#!/usr/bin/env python3
"""Tạo tải cho demo tự mở rộng (KE_HOACH 12.5). Chỉ dùng thư viện chuẩn, chạy được trên laptop.

  python scripts/loadtest.py --base http://<CTL_IP> --token <api_token> --problem slow-sum --n 60 --concurrency 10

Gửi n bài qua /api/submit, rồi theo dõi /api/submissions/<id> đến khi tất cả có kết quả cuối. In thời gian chờ
trong hàng đợi (started - created) và tổng thời gian (finished - created): trung bình, p50, p95, max; số bài
theo kết quả; số bài theo máy chấm (thấy worker mới nhận bài sau khi scale out).
Token đọc từ --token hoặc biến môi trường LOADTEST_TOKEN.
"""
from __future__ import annotations

import argparse
import collections
import concurrent.futures as cf
import json
import os
import statistics
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path

FINAL = {"ACCEPTED", "WRONG_ANSWER", "TIME_LIMIT", "RUNTIME_ERROR", "COMPILE_ERROR", "SYSTEM_ERROR"}
SAMPLES = Path(__file__).resolve().parent.parent / "app" / "sample_problems"


def request(base, token, method, path, body=None, timeout=15):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(base.rstrip("/") + path, data=data, method=method,
                                 headers={"X-API-Token": token, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def parse_ts(s):
    return datetime.fromisoformat(s.rstrip("Z")) if s else None


def pct(values, p):
    if not values:
        return float("nan")
    v = sorted(values)
    k = max(0, min(len(v) - 1, round(p / 100 * len(v) + 0.5) - 1))
    return v[k]


def summary(name, values):
    if not values:
        return f"{name:<22} (không có dữ liệu)"
    return (f"{name:<22} tb {statistics.mean(values):6.1f}s  p50 {pct(values, 50):6.1f}s  "
            f"p95 {pct(values, 95):6.1f}s  max {max(values):6.1f}s")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--base", required=True, help="vd http://34.124.240.64")
    ap.add_argument("--token", default=os.environ.get("LOADTEST_TOKEN"))
    ap.add_argument("--problem", default="slow-sum")
    ap.add_argument("--language", default="cpp", choices=["cpp", "python"])
    ap.add_argument("--source", help="file mã nguồn (mặc định: sample_problems/<problem>/solutions/ok.<ext>)")
    ap.add_argument("--n", type=int, default=60)
    ap.add_argument("--concurrency", type=int, default=10)
    ap.add_argument("--poll", type=float, default=3.0, help="giây giữa 2 lần kiểm tra kết quả")
    ap.add_argument("--timeout", type=float, default=1200, help="giây tối đa chờ chấm xong")
    ap.add_argument("--no-wait", action="store_true", help="chỉ gửi bài, không chờ kết quả")
    args = ap.parse_args()
    if not args.token:
        ap.error("thiếu --token (hoặc biến LOADTEST_TOKEN)")

    src_path = Path(args.source) if args.source else \
        SAMPLES / args.problem / "solutions" / ("ok.cpp" if args.language == "cpp" else "ok.py")
    source = src_path.read_text(encoding="utf-8")
    payload = {"problem": args.problem, "language": args.language, "source": source}

    print(f"gửi {args.n} bài {args.problem} ({args.language}, {src_path.name}) tới {args.base}, "
          f"{args.concurrency} luồng", flush=True)
    t0 = time.time()
    ids, errors = [], collections.Counter()

    def submit(_):
        for attempt in range(3):
            try:
                return request(args.base, args.token, "POST", "/api/submit", payload)["id"]
            except urllib.error.HTTPError as e:
                if e.code < 500:
                    raise
                errors[f"HTTP {e.code}"] += 1
            except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
                errors[type(e).__name__] += 1
            time.sleep(1 + attempt)
        return None

    with cf.ThreadPoolExecutor(args.concurrency) as ex:
        for sid in ex.map(submit, range(args.n)):
            if sid is not None:
                ids.append(sid)
    print(f"đã gửi {len(ids)}/{args.n} bài trong {time.time() - t0:.1f}s"
          + (f", lỗi tạm thời: {dict(errors)}" if errors else ""), flush=True)
    if args.no_wait or not ids:
        print("id:", ids[:5], "..." if len(ids) > 5 else "")
        return 0 if ids else 1

    results: dict[int, dict] = {}
    deadline = time.time() + args.timeout
    while len(results) < len(ids) and time.time() < deadline:
        pending = [i for i in ids if i not in results]
        with cf.ThreadPoolExecutor(args.concurrency) as ex:
            for sid, r in zip(pending, ex.map(lambda i: _status(args, i), pending)):
                if r and r["status"] in FINAL:
                    results[sid] = r
        hosts = collections.Counter(r["worker_host"] for r in results.values())
        print(f"[{time.time() - t0:6.0f}s] xong {len(results)}/{len(ids)}  máy chấm: {dict(hosts)}", flush=True)
        if len(results) < len(ids):
            time.sleep(args.poll)

    wait = [(parse_ts(r["started_at"]) - parse_ts(r["created_at"])).total_seconds()
            for r in results.values() if r["started_at"]]
    total = [(parse_ts(r["finished_at"]) - parse_ts(r["created_at"])).total_seconds()
             for r in results.values() if r["finished_at"]]
    print("\n===== KẾT QUẢ =====")
    print(f"tổng thời gian chạy     {time.time() - t0:.0f}s, xong {len(results)}/{len(ids)} bài")
    print("theo kết quả           ", dict(collections.Counter(r["status"] for r in results.values())))
    print("theo máy chấm          ", dict(collections.Counter(r["worker_host"] for r in results.values())))
    print(summary("chờ trong hàng đợi", wait))
    print(summary("nộp → có kết quả", total))
    return 0 if len(results) == len(ids) else 1


def _status(args, sid):
    try:
        return request(args.base, args.token, "GET", f"/api/submissions/{sid}")
    except (urllib.error.URLError, TimeoutError, ConnectionError):
        return None


if __name__ == "__main__":
    sys.exit(main())
