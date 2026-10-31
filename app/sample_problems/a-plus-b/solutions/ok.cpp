// Lời giải đúng (ACCEPTED). Dùng __int128 vì a + b có thể vượt long long.
#include <bits/stdc++.h>
using namespace std;

int main() {
    long long a, b;
    cin >> a >> b;
    __int128 s = (__int128)a + b;
    if (s == 0) { puts("0"); return 0; }
    bool neg = s < 0;
    if (neg) s = -s;
    string out;
    while (s > 0) { out += char('0' + (int)(s % 10)); s /= 10; }
    if (neg) out += '-';
    reverse(out.begin(), out.end());
    puts(out.c_str());
}
