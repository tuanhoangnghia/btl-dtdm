# Lời thoại demo của C (Trọng) – video + buổi bảo vệ

> Theo kịch bản 10 phút của KE_HOACH 14.1. C nói ở 1:20–2:45 (cùng B), 4:00–6:00 (cùng B), **7:00–7:45**, 7:45–9:00 (cùng B), **9:00–10:00**.
> Lời nói viết để đọc thành tiếng, mỗi đoạn ngắn hơn thời lượng một chút để còn chỗ chờ lệnh chạy. Lệnh gõ được copy nguyên.
> **Phải tập trên cụm ít nhất 1 lần** (đường SSH, mật khẩu Grafana, tab Gmail) trước khi quay.

## 0. Chuẩn bị (trước giờ quay ≥ 1,5 giờ, KE_HOACH 14.2)

1. Bật cụm, giữ khóa, chạy kiểm tra sức khỏe:
   ```bash
   ssh -A cj-controller 'bash ~/cloudjudge/scripts/cj-health.sh'
   ```
   Phải ra `TẤT CẢ OK` (replication chạy, hàng đợi rỗng, mọi mục tiêu Prometheus up).
2. Mở sẵn các tab:
   - **Grafana** `http://10.0.2.11:3000` (qua Tailscale của bastion), dashboard **CloudJudge**, khoảng thời gian "Last 15 minutes", tự làm mới 5 s. Mật khẩu admin nằm trong máy monitor: `sudo cat /etc/cj-mon/grafana/admin.pw`.
     Nếu Tailscale của bastion chưa chạy thì mở đường hầm: `ssh -N -L 3000:10.0.2.11:3000 -J cj-controller cj@172.24.4.131`, rồi mở `http://localhost:3000`.
   - **Gmail** của `nmtronguet@gmail.com`, lọc `from:(cloudjudge) OR subject:[CloudJudge]`.
   - **Bảng chi phí** `docs/cost/chi-phi.md` (xem trên GitHub cho đẹp) và **GCP Console → Billing → Reports**, lọc project `omega-dahlia-468315-f6`.
3. Mở sẵn 3 cửa sổ terminal, đặt tên cho dễ nhìn:
   - **T1 (controller):** `ssh -A cj-controller`, rồi `source /home/cj/kolla-venv/bin/activate; export OS_CLOUD=cloudjudge`
   - **T2 (Primary):** `ssh -A -J cj-controller,cj@172.24.4.131 cj@10.0.3.10`, rồi `sudo cj-mysql`
   - **T3 (Replica):** `ssh -A -J cj-controller,cj@172.24.4.131 cj@10.0.3.11`, rồi `sudo cj-mysql`
   (172.24.4.131 là floating IP của bastion; kiểm lại bằng `openstack stack output show cj-net bastion_fip`.)
4. Phóng to chữ terminal (Ctrl + `+`) để người xem đọc được.

---

## 1:20–2:45 · Lưu trữ: Swift và Cinder (HM 3) — B nộp bài trước, C nói phần lưu trữ

**Mở:** T1.

**Nói:** "Bài vừa nộp được lưu ở hai loại lưu trữ khác nhau. Mã nguồn là **object storage**: Swift. Máy web và máy chấm bị tạo ra rồi xóa đi liên tục, nên mọi thứ cần dùng chung phải nằm ngoài máy ảo."

**Gõ:**
```bash
openstack object list submissions --long -c Name -c "Last Modified" | tail -n 4
```

**Mong đợi:** dòng mới nhất là `<uuid>/main.cpp` vừa nộp (giờ khớp lúc nộp).

**Nói:** "Còn cơ sở dữ liệu thì cần đĩa ghi ngẫu nhiên và phải sống lâu hơn máy ảo, nên dùng **block storage**: Cinder. Ba volume này gắn vào máy MySQL chính, máy MySQL bản sao và RabbitMQ. Nếu máy ảo bị tạo lại, volume cũ được gắn lại và dữ liệu vẫn còn."

**Gõ:**
```bash
openstack volume list --long -c Name -c Status -c Size -c "Attached to"
```

**Mong đợi:** 3 volume `in-use`, gắn vào `cj-mysql-primary`, `cj-mysql-replica`, `cj-rabbitmq`.

**Nếu lỗi:** cột "Attached to" chỉ hiện ID máy → nói "đây là ID của máy MySQL", rồi gõ `openstack server list -c ID -c Name` để đối chiếu.

---

## 4:00–6:00 · Giám sát và cảnh báo (HM 7) — C nói Grafana + hộp thư, B nói phần Heat thêm máy

**Mở:** tab Grafana (lúc này loadtest 60 bài của B đã chạy được ~3 phút).

**Nói:** "Đây là Prometheus và Grafana chạy trên máy monitor trong mạng riêng. Máy chấm do Heat tạo ra không có IP cố định, nên Prometheus hỏi OpenStack danh sách máy theo nhãn `cj_role` mỗi 15 giây. Máy mới vừa tạo là được theo dõi ngay."

**Chỉ vào:** hàng đầu của dashboard: **bài đang chờ** tăng vọt, **số máy chấm** tăng từ 1 lên 2.

**Nói:** "Khi hàng đợi quá 10 bài trong 30 giây, luật **QueueHigh** chuyển sang firing. Alertmanager làm hai việc: gửi email cho nhóm, và gọi URL đã ký sẵn của Heat để thêm một máy chấm. Máy monitor không giữ mật khẩu nào có quyền Heat, chỉ biết bốn URL đó."

**Mở:** tab Gmail → thư `[CloudJudge] FIRING: QueueHigh`.

**Nói:** "Đây là thư cảnh báo vừa tới, gửi qua Gmail cổng 587 vì Google Cloud chặn cổng 25." → (B nói tiếp phần `openstack stack resource list` của Heat.)

**Nếu thư chưa tới:** nói "thư được gom trong 10 giây rồi mới gửi", chuyển sang B, quay lại hộp thư ở đoạn 7:45.

---

## 7:00–7:45 · Ghi ở Primary, đọc ở Replica (HM 4) — 45 giây, chỉ C

**Mở:** T2 (Primary) và T3 (Replica) đặt cạnh nhau.

**Nói (trong lúc gõ):** "Cơ sở dữ liệu là MySQL tự dựng: máy chính ở AZ-1, bản sao ở AZ-2, nhân bản theo GTID. Em ghi một dòng ở máy chính…"

**Gõ ở T2:**
```sql
INSERT INTO cj_check.ping (note) VALUES ('demo video'); SELECT @@hostname, id, note, at FROM cj_check.ping ORDER BY id DESC LIMIT 1;
```

**Gõ ở T3:**
```sql
SELECT @@hostname, id, note, at FROM cj_check.ping ORDER BY id DESC LIMIT 1;
```

**Nói:** "…và bản sao đã có ngay, độ trễ đo được vài mili giây. Bản sao chỉ cho đọc, kể cả tài khoản root cũng không ghi được:"

**Gõ ở T3:**
```sql
INSERT INTO cj_check.ping (note) VALUES ('ghi vao replica');
```

**Mong đợi:** `ERROR 1290 … --super-read-only option`.

**Nói:** "Trang bảng điểm của ứng dụng đọc từ bản sao này, nên việc đọc không làm chậm việc ghi bài nộp."

**Nếu lỗi** (bảng `cj_check.ping` chưa có): ở T1 chạy `bash ~/cloudjudge/db/test-replication.sh` với lệnh trong mục 2 của `db/cluster-evidence.sh`, hoặc chỉ cho xem `docs/evidence/C-cluster-evidence.txt`.

---

## 7:45–9:00 · Chấm xong, thu máy về (HM 6, 7) — B nói số bài, C nói Grafana

**Mở:** tab Grafana.

**Nói:** "Hàng đợi đã về 0. Sau 1 phút không còn bài, luật **QueueIdle** gọi Heat bớt máy chấm, nên số máy chấm về lại 1. Cạnh đó là thời gian chấm p50 và p95, và hàng dưới là trạng thái nhân bản và tuổi của bản backup gần nhất."

**Chỉ vào:** panel **số máy chấm** (đường đi 1 → 2 → 3 → 1), panel **replication** (IO/SQL đều chạy), panel **tuổi backup**.

**Nói (nếu còn thời gian):** "Backup chạy mỗi đêm lúc 2 giờ: `mysqldump` không khóa bảng, nén, đẩy lên Swift bằng một danh tính chỉ ghi được thư mục backups, và Swift tự xóa bản cũ sau 7 ngày. Quá 26 giờ không có bản mới thì có cảnh báo BackupStale."

---

## 9:00–10:00 · Chi phí (HM 8) — chỉ C

**Mở:** `docs/cost/chi-phi.md` mục 3.4, rồi tab Billing.

**Nói:** "Tiền thật của dự án là tiền chạy ba máy ảo Google Cloud: khoảng 17 nghìn đồng mỗi giờ khi bật, và khoảng 34 nghìn đồng mỗi ngày khi tắt, vì đĩa và IP tĩnh vẫn bị tính. Nhóm có script bật tắt và khóa dùng chung để không ai tắt nhầm cụm của người khác. Đây là số thật trên Billing: … (đọc số trên màn hình)."

**Nói:** "Nếu chạy thật 24/7 thì so ba phương án: AWS khoảng 5,9 triệu một tháng, máy chủ cũ của trường khoảng 6,7 triệu, còn OpenStack trên máy ảo Google như demo đắt nhất, khoảng 14,9 triệu. Đắt nhất vì phải trả cho ba máy chạy cả ngày bất kể tải, lại thêm một lớp ảo hóa lồng. Khi tính cả tiền nhân lực vận hành, dịch vụ có quản lý như AWS rẻ nhất. Cách dựng của nhóm phù hợp để học cách một đám mây hoạt động, không phải để tiết kiệm."

**Nếu Billing chưa có số:** dùng mục 2 của `chi-phi.md` (ước tính ≈ 132 USD ≈ 3,4 triệu đ cho cả dự án, trong tín dụng dùng thử ≈ 297 USD).

---

## Chuẩn bị vấn đáp phần C (KE_HOACH 14.5)

**Object, block, file storage khác nhau thế nào?**
Object (Swift, S3): lưu cả "đối tượng" qua HTTP, có metadata, không sửa giữa chừng được, mở rộng gần như vô hạn; hợp với file nộp, backup. Block (Cinder, EBS): một ổ đĩa thô gắn vào một máy, hệ điều hành tự định dạng; hợp với CSDL vì ghi ngẫu nhiên nhanh. File (NFS, Manila, EFS): thư mục dùng chung cho nhiều máy cùng lúc; nhóm không cần vì đã dùng Swift cho dữ liệu chung.

**Nhân bản đồng bộ và bất đồng bộ?**
Đồng bộ: primary chỉ báo "xong" khi replica đã ghi, nên không mất dữ liệu nhưng ghi chậm theo mạng giữa 2 AZ. Bất đồng bộ (nhóm dùng): primary ghi xong là trả lời, replica đuổi theo sau vài mili giây; nhanh hơn nhưng nếu primary chết ngay sau khi commit thì có thể mất vài giao dịch cuối. Bán đồng bộ (semi-sync) nằm giữa: chờ ít nhất 1 replica nhận (chưa cần áp dụng).

**GTID là gì, lợi gì?**
Mỗi giao dịch có một mã toàn cục `uuid-máy-chủ:số thứ tự`. Replica nhớ đã chạy những mã nào, nên khi nối lại (hoặc đổi primary) nó tự biết đọc tiếp từ đâu (`SOURCE_AUTO_POSITION=1`), không phải ghi tay tên file binlog và vị trí.

**RPO, RTO của hệ thống?**
RPO = lượng dữ liệu tối đa có thể mất; RTO = thời gian để chạy lại. Mất replica: RPO 0, RTO vài phút. Mất VM primary nhưng volume còn: RPO 0, RTO ~5 phút (Heat tạo lại máy, gắn lại volume). Mất cả primary lẫn volume: RPO = độ trễ nhân bản (vài ms), RTO ~10–15 phút làm tay (nâng replica lên). Xóa nhầm dữ liệu: RPO ≤ 24 giờ, khôi phục từ backup đêm trước (replica cũng nhận lệnh xóa nên không cứu được).

**Vì sao không dùng Trove?**
Trove cần thêm image guest riêng, guest agent và message bus; rủi ro cao khi còn phải tự dựng cả OpenStack trong 3 tuần. Tự dựng MySQL bằng Heat cũng cho thấy rõ cơ chế nhân bản, phân quyền và backup.

**Prometheus "pull" là gì? Làm sao theo dõi máy do autoscale tạo?**
Prometheus tự đi lấy số liệu từ từng máy (pull) theo chu kỳ, thay vì máy đẩy về. Ưu điểm: biết ngay máy nào chết (lấy không được = `up == 0`). Máy autoscale không có IP cố định, nên dùng service discovery `openstack_sd`: hỏi Nova danh sách máy đang chạy bằng một danh tính chỉ đọc (`cj-monitor`), lọc theo metadata `cj_role` do Heat gắn.

**Vì sao co giãn máy chấm theo hàng đợi, không theo CPU?**
Máy chấm luôn chạy 100 % CPU khi đang chấm, dù còn 1 bài hay 100 bài. Độ dài hàng đợi mới cho biết còn bao nhiêu việc; chia cho tốc độ ~7 bài/phút/máy là ra thời gian chờ.

**TCO là gì, sao AWS rẻ hơn dù giá máy không rẻ?**
TCO (tổng chi phí sở hữu) gồm cả tiền hạ tầng lẫn tiền người vận hành, điện, phần cứng hỏng. Với hệ thống nhỏ, tiền nhân lực chiếm phần lớn; dịch vụ có quản lý (RDS, SQS, ALB) bớt việc vận hành nên tổng rẻ hơn, dù đơn giá từng máy không thấp.
