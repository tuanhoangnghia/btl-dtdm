// Lời giải mẫu duyệt từng bước (~1,5 giây/test trên worker cj.medium). loadtest.py nộp file này.
#include <cstdio>

int main() {
    long long n, x, a, b;
    if (scanf("%lld %lld %lld %lld", &n, &x, &a, &b) != 4) return 1;
    const long long M = 1000000007LL;
    for (long long i = 0; i < n; i++) x = (a * x + b) % M;
    printf("%lld\n", x);
}
