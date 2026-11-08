# CloudJudge: hệ thống nộp bài và chấm code tự động trên OpenStack tự dựng

> **Khung báo cáo chính** (C ghép, KE_HOACH 14.4). Mỗi mục ghi nguồn lấy nội dung; người viết từng phần sửa file của mình
> (`A-ha-tang.md`, `B-ung-dung.md`, `C-du-lieu-giam-sat.md`), C chép vào đây khi ghép rồi xuất PDF.
> Hạn nộp: **22/11/2026** (báo cáo + mã nguồn + video). Trạng thái: ☐ chưa ghép · ◐ đang ghép · ☑ xong.

Lớp INT3319 3 – Điện toán đám mây. Nhóm: Hoàng Nghĩa Tuấn (23020877, A), Nguyễn Minh Trọng (23020893, C), Trần Văn Phường (23020859, B).
Repo: `https://github.com/tuanhoangnghia/btl-dtdm` · Video: … (⏳)

| # | Mục | Nguồn | Trạng thái |
|---|---|---|---|
| 1 | Bài toán | bản đề xuất mục 2 | ☐ |
| 2 | Kiến trúc (sơ đồ đúng thực tế: 3 subnet, 2 AZ, luồng 1 bài nộp, lớp dữ liệu và giám sát) | đề xuất mục 3 + A §2–3 + B §1 + C §1 | ☐ |
| 3 | Dựng OpenStack trên GCP (nested virt, mạng external giả, MTU, Kolla 2025.2 và vì sao) | A §1, §5 | ☐ |
| 4 | Đối chiếu 8 hạng mục, kèm ảnh minh chứng | HM 1, 2, 5: A · HM 6: B · HM 3, 4, 7, 8: C · ảnh trong `docs/evidence/` | ☐ |
| 5 | Lý giải lựa chọn công nghệ, có các điểm **≠ đề xuất** (KE_HOACH mục 2: D1 Kolla 2025.2 + Swift cài tay, D2 OVS, D3, D10 4 danh tính) | đề xuất mục 5 + A §1 + B + C §6 | ☐ |
| 6 | Kết quả đo: thời gian chấm lúc thường và cao điểm; thời gian scale out/in | B (loadtest, Heat) + C §8 | ☐ |
| 7 | Chi phí (thật + 3 phương án) | `docs/cost/chi-phi.md`, ảnh Billing | ☐ |
| 8 | Giới hạn: controller là điểm lỗi đơn, CPU vật lý cố định, secret chưa dùng Barbican/Vault, amphora là image tự build, MySQL không tự failover | A §6 + B + C §7 | ☐ |
| 9 | Phân công thực tế, link repo, link video | 3 file `docs/tasks/*` | ☐ |

## Việc trước khi xuất PDF
- [ ] Sơ đồ kiến trúc cập nhật (hình đề xuất + lớp dữ liệu/giám sát), xuất PNG vào `docs/report/img/`
- [ ] Ảnh minh chứng đủ 8 hạng mục, đặt tên `docs/evidence/<A|B|C>-hm<n>-*.png`
- [ ] Số liệu đo thật thay mọi ô ⏳ và `…`
- [ ] Ảnh Billing GCP + bảng chi phí đã kiểm lại bằng Pricing Calculator
- [ ] Kiểm lại link repo (repo private: thêm thầy vào collaborator hoặc chuyển public lúc nộp) và link video
- [ ] Xuất PDF (vd. `pandoc bao-cao.md -o bao-cao.pdf` hoặc chép sang Google Docs/Word), kiểm tiếng Việt và bảng
