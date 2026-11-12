# Mô hình dữ liệu

## Người dùng và phiên

- Dùng UUID của Supabase Auth làm ID tài khoản thật; không tự lưu mật khẩu.
- Phiên lấy từ `auth.sessions`: `session_id` và `user_id` là UUID bắt buộc, phải khớp claims đã xác minh. Không cấp quyền đọc bảng này cho Flutter.
- Dữ liệu cục bộ tài khoản thật dùng namespace `auth:<user_uuid>`; email cũ và thư viện mẫu không được chuyển tự động.

## cloud_documents

| Trường | Ràng buộc |
| --- | --- |
| id | UUID bắt buộc, khóa chính, tạo trên máy chủ |
| owner_id | UUID bắt buộc, tham chiếu người dùng đã xác thực |
| upload_id | UUID bắt buộc; duy nhất theo cặp `(owner_id, upload_id)` |
| filename | Tên PDF hiển thị, 1–120 ký tự, không có dấu phân cách đường dẫn hoặc ký tự điều khiển |
| page_count | Số nguyên 1–500, khớp PDF đã kiểm tra |
| byte_size | Số nguyên 1–20.971.520 bytes, lấy từ tệp thực |
| sha256 | 64 ký tự hex thường, tính trên máy chủ từ PDF nhận được |
| object_key | Chuỗi duy nhất theo mẫu `<owner_id>/<id>.pdf`, do máy chủ tạo |
| status | `pending` hoặc `ready`; chỉ `ready` hiển thị và tải được |
| created_at | Mốc UTC bắt buộc do máy chủ gán |

Object nằm trong bucket riêng tư `scanpdf-documents`; không trả `object_key` cho client. Tạo bản ghi `pending` trước, ghi object với chính sách không ghi đè, rồi chuyển sang `ready` khi đối chiếu metadata thành công. Các yêu cầu đồng thời cùng khóa không tạo thêm bản ghi hoặc object.

## Trạng thái trong Flutter

- **Đã lưu trên máy** → **Đang tải lên** → **Đã lưu trực tuyến** hoặc **Tải lên thất bại**. Chỉ phản hồi tài liệu `ready` mới chuyển sang đã lưu trực tuyến.
- Lưu `upload_id`, ID PDF cục bộ và metadata lần tải lên theo namespace tài khoản để có thể thử lại sau khi đóng app; không tự gửi lại khi khởi động.
- Bản tải xuống được kiểm tra hash trước khi xuất hiện dưới dạng có thể mở. Lưu trong vùng riêng của app theo namespace tài khoản; tệp tải dở không được mở như PDF hoàn chỉnh.
