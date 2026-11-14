"""Sinh test cho slow-sum: python gen.py [n]

Mặc định n = 300000000 (~1,5 giây/test với ok.cpp trên worker cj.medium). Đo lại trên cụm rồi chỉnh n,
chạy lại script này và seed lại (cj-cli seed sẽ cập nhật tests.zip trên Swift).
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent / "solutions"))
from fast import jump  # noqa: E402

N = int(sys.argv[1]) if len(sys.argv) > 1 else 300_000_000
CASES = [(N, 1, 2, 3), (N, 12345, 987654321, 1), (N, 0, 31337, 7), (N, 999999999, 48271, 11)]

out = Path(__file__).parent / "tests"
out.mkdir(exist_ok=True)
for i, (n, x0, a, b) in enumerate(CASES, 1):
    (out / f"{i}.in").write_text(f"{n} {x0} {a} {b}\n", newline="\n")
    (out / f"{i}.out").write_text(f"{jump(n, x0, a, b)}\n", newline="\n")
print(f"đã ghi {len(CASES)} test vào {out} (n = {N})")
