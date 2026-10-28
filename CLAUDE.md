# CloudJudge – BTL Điện toán đám mây (INT3319 3)

Nhóm 3 người, mỗi người một phiên Claude, làm song song trên cùng repo.

## Đầu mỗi phiên
1. Hỏi người dùng họ là **A** (hạ tầng), **B** (ứng dụng) hay **C** (dữ liệu, giám sát), nếu họ chưa nói.
2. Đọc `docs/CONTRACT.md`, rồi đọc file nhiệm vụ của vai trò đó:
   A → `docs/tasks/A-ha-tang.md` · B → `docs/tasks/B-ung-dung.md` · C → `docs/tasks/C-du-lieu-giam-sat.md`.
3. Đọc các mục của `KE_HOACH_TRIEN_KHAI.md` mà file nhiệm vụ trỏ tới (không cần đọc hết).

## Luật
- **Chỉ sửa file thuộc vai trò đang làm** (CONTRACT mục 1). Cần thay đổi ở phần người khác thì soạn sẵn nội dung nhắn cho họ, không tự sửa.
- Tên biến env, queue, container Swift, metric, output Heat, IP, cổng phải khớp CONTRACT. Muốn đổi thì đề xuất PR riêng sửa CONTRACT.
- Cuối phiên: cập nhật mục "Tiến độ" và "Nhật ký" trong file nhiệm vụ của mình.
- Không commit secret. Hỏi trước các thao tác tốn tiền hoặc khó hoàn tác (tạo/xóa VM GCP, xóa stack, xóa disk/snapshot).

## Dùng cụm GCP chung (QUAN TRỌNG: cả 3 người dùng chung 1 cụm, tắt nhầm là chết việc của người khác)
- Cả 3 người đều là Owner nên ai cũng tắt được cụm. Vì vậy **không bao giờ** chạy `gcloud compute instances stop` hay bấm Stop trong Console để tắt cụm. Chỉ tắt bằng `infra/gcp/gcp-down.sh`.
- Trước khi làm việc trên cụm: `source infra/gcp/00-vars.sh`, rồi `bash infra/gcp/cj-lock.sh status` để xem ai đang dùng. Sau đó giữ khóa: `bash infra/gcp/cj-lock.sh acquire <A|B|C> "lý do" [số giờ]` (mặc định 4 giờ, tự hết hạn; việc dài hơn thì acquire lại).
- Xong việc: `bash infra/gcp/cj-lock.sh release <A|B|C>`. Muốn tắt cụm: `CJ_ME=<A|B|C> bash infra/gcp/gcp-down.sh`. Script từ chối nếu người KHÁC đang giữ khóa.
- Bị từ chối thì **dừng lại và báo người dùng** (nói ai đang giữ khóa, còn bao lâu). Không tự dùng `FORCE=1`, không tự tắt bằng cách khác; chỉ dùng khi người dùng nói rõ đã hỏi nhóm.
- Bật cụm: `bash infra/gcp/gcp-up.sh` (ai cũng được; nếu cụm đã bật thì bỏ qua). Hết buổi mà không còn ai giữ khóa thì nhớ tắt để khỏi tốn tín dụng (~17.000 đ/giờ).
- Lệnh `gcloud` luôn chạy với cấu hình `cloudjudge` (đã nạp bởi `00-vars.sh`), vì cấu hình mặc định trên máy có thể trỏ project khác.

## Tài liệu gốc
- Yêu cầu của thầy: `Bài tập lớn cuối kỳ - Hướng dẫn đề xuất dự án - Student-1.pdf`
- Đề xuất đã nộp: `De_xuat_CloudJudge_ban_nop (2) (1).docx`
- Hạn: nộp báo cáo + mã nguồn + video **09/11/2026**; bảo vệ **16/11/2026**.
