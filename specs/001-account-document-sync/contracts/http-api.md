# Hợp đồng HTTP v1

Base path `/v1`. Ngoại trừ tạo tài khoản, đăng nhập và làm mới phiên, các điểm truy cập xác thực dùng `Authorization: Bearer <access_token>`. Bảo vệ phản hồi phiên và PDF bằng `Cache-Control: no-store`; không ghi log mật khẩu, token, bytes PDF hoặc khóa kho tệp.

| Endpoint | Input | Thành công |
| --- | --- | --- |
| POST /auth/register | JSON `email`, `password` | 202; hướng dẫn xác nhận email, không trả phiên |
| POST /auth/login | JSON `email`, `password` | 200; `user.id`, `user.email`, `access_token`, `refresh_token`, `expires_at` |
| POST /auth/refresh | JSON `refresh_token` | 200; trả lại cặp token và thời hạn mới |
| GET /auth/me | Bearer của thiết bị hiện tại | 200; `user.id`, `user.email`, kiểm tra phiên |
| POST /auth/logout | Bearer của thiết bị hiện tại | 204 khi máy chủ xác nhận phiên này đã thu hồi; không thu hồi thiết bị khác |
| GET /documents | Cursor tùy chọn | 200; tối đa 30 mục `ready` của tài khoản, mới nhất trước, kèm `next_cursor` |
| POST /documents | `multipart/form-data`: `file`, `filename`; header `Content-Length` và `Idempotency-Key` là UUID | 201 lần đầu, 200 khi thử lại cùng payload; trả cùng metadata và ID |
| GET /documents/{id}/content | ID UUID | 200; PDF theo byte gốc, `Content-Type: application/pdf`, tên tải an toàn |
| DELETE /documents/{id} | ID UUID | 204 sau khi xóa object và metadata của người gọi; object đã vắng mặt vẫn cho phép xóa metadata |

Metadata công khai trong API có `id`, `filename`, `page_count`, `byte_size`, `sha256`, `created_at`. Máy chủ xác định số trang, digest và kích thước từ tệp PDF; không nhận chủ sở hữu hoặc đường dẫn lưu trữ trong payload. Filename và giới hạn theo [mô hình dữ liệu](../data-model.md).

## Lỗi và thử lại

Dạng lỗi `{"error":{"code":"...","message":"...","request_id":"..."}}`. Flutter dịch hoặc ánh xạ lỗi sang tiếng Việt trong màn hình hiện tại.

- 400 `INVALID_INPUT`: input, cursor hoặc UUID không hợp lệ.
- 401 `SESSION_INVALID`: token thiếu, hết hạn hoặc phiên đã thu hồi; đăng nhập lỗi dùng thông báo chung.
- 404 `DOCUMENT_NOT_FOUND`: không tìm thấy bản `ready` thuộc người dùng hiện tại.
- 409 `UPLOAD_KEY_CONFLICT`: cùng mã lần tải lên nhưng tệp hoặc tên khác.
- 413 `FILE_TOO_LARGE`: PDF lớn hơn 20 MiB hoặc multipart thiếu `Content-Length` hay khai vượt 20 MiB + 64 KiB.
- 413 `QUOTA_EXCEEDED`: bản ghi mới vượt số tài liệu hoặc dung lượng của tài khoản, tính cả `pending`. Retry với UUID đã có giữ quy tắc so khớp nội dung.
- 415 `INVALID_PDF`: loại tệp không hợp lệ hoặc không đọc được thành PDF trong giới hạn kiểm tra.
- 429 `RATE_LIMITED`: hạn chế xác thực, upload, và nhóm đọc/xóa dùng chung hạn mức 120 lượt/phút theo tài khoản.
- 503 `BUSY`: tiến trình đã đạt giới hạn upload và download đồng thời.
- 503 `DEPENDENCY_UNAVAILABLE`: xác thực, kiểm tra phiên, cơ sở dữ liệu hoặc Storage không sẵn sàng. Không mở quyền hoặc báo đã lưu.
