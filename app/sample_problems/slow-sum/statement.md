Cho dãy số xác định bởi `x(0) = x0` và `x(i+1) = (a · x(i) + b) mod 1000000007`.
Hãy tính **x(n)**.

Bài này được thiết kế để lời giải duyệt từng bước chạy khoảng 1,5 giây mỗi test: hệ thống dùng nó
để tạo tải khi demo tự mở rộng máy chấm.

## Dữ liệu vào
Một dòng gồm bốn số nguyên `n x0 a b` (1 ≤ n ≤ 10^9; 0 ≤ x0, a, b < 1000000007).

## Kết quả
Giá trị `x(n)`.

## Ví dụ
```
Vào:  3 1 2 3
Ra:   29
```
(1 → 5 → 13 → 29)
