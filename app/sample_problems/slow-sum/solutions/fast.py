# Lời giải nhanh O(log n): ghép hàm affine x -> a*x + b bằng lũy thừa nhanh.
M = 1_000_000_007


def jump(n, x0, a, b):
    # (A, B) biểu diễn x -> A*x + B; ghép f∘f: (A*A, A*B + B)
    ra, rb = 1, 0
    while n:
        if n & 1:
            ra, rb = a * ra % M, (a * rb + b) % M
        a, b = a * a % M, (a * b + b) % M
        n >>= 1
    return (ra * x0 + rb) % M


if __name__ == "__main__":
    n, x0, a, b = map(int, input().split())
    print(jump(n, x0, a, b))
