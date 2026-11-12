# Đối chiếu 19 khung Stitch

Mở **Tài khoản → Xem mẫu giao diện → Đối chiếu 19 màn hình Stitch**. Mỗi mục có ảnh tham chiếu gốc và nút mở giao diện Flutter. Các màn hình dùng chung thành phần và thích ứng theo kích thước màn hình; bảng chia sẻ và quyền camera thật do hệ điều hành hoặc trình duyệt hiển thị.

| Khung Stitch | Giao diện và thao tác Flutter | Trạng thái dữ liệu |
| --- | --- | --- |
| 01 Khởi động | Logo, tiến trình, hai hướng vào đăng nhập hoặc thư viện, trạng thái ngoại tuyến | Kiểm tra phiên cục bộ; không có xác thực từ máy chủ |
| 02 Đăng nhập | Lỗi biểu mẫu, hiện mật khẩu, quên mật khẩu, ghi nhớ phiên, dùng ngoại tuyến, nút Google/Zalo | Phiên cục bộ dùng được; quên mật khẩu, Google và Zalo là mẫu |
| 03 Đăng ký | Họ tên, email, mật khẩu, độ mạnh, xác nhận và lựa chọn đã đọc hướng dẫn | Chỉ tạo hồ sơ cục bộ; xác nhận email là mẫu |
| 04 Hồ sơ | Hồ sơ và ảnh đại diện, thống kê PDF, đồng bộ, Wi-Fi, Pro, sinh trắc học, chất lượng và quyền riêng tư | Hồ sơ, thống kê và chất lượng dùng dữ liệu cục bộ; Pro, Drive, Cloud, Wi-Fi và sinh trắc học là mẫu |
| 05 Đổi mật khẩu | Mật khẩu hiện tại/mới, độ mạnh, xác nhận, tùy chọn đăng xuất thiết bị khác | Kiểm tra biểu mẫu; không đổi mật khẩu hoặc đăng xuất thiết bị thật |
| 06 Thư viện | Tìm kiếm, sắp xếp, lưới/danh sách, bộ lọc và menu tài liệu | Dữ liệu trên máy; trạng thái đồng bộ là mẫu |
| 07 Chọn nguồn | Camera, chọn ảnh, dùng tài liệu mẫu, hộp thoại minh họa quyền | Quyền thật do thiết bị xử lý; màn hình đối chiếu không xin quyền |
| 08 Camera | Xem trước, tự động/thủ công, khung tài liệu/thẻ/hóa đơn/sách, thêm ảnh, xem lại và chụp tiếp | Luồng thường dùng camera thật; khung đối chiếu dùng ảnh mẫu |
| 09 Cắt viền | Dò mép, kéo bốn góc, xoay 90°, đặt lại, hủy và áp dụng | Thao tác trên ảnh; dò mép phụ thuộc chất lượng ảnh |
| 10 Chỉnh ảnh | Màu, tăng cường, xám, đen trắng, sáng/tương phản, xoay và áp dụng bộ lọc nhiều trang | Xử lý thật trên ảnh; không tuyên bố kết quả OCR |
| 11 Sắp xếp trang | Lưới, kéo thả, xoay tất cả, bộ lọc, thêm, sửa và xóa trang | Thao tác trong phiên quét |
| 12 Thiết lập xuất | Tên tệp, ảnh xem trước, A4/Letter/khổ gốc, chất lượng, nén, đặt lại, OCR và khóa tệp | Khổ giấy, chất lượng và nén có hiệu lực; OCR và khóa tệp là mẫu |
| 13 Tiến trình xuất | Tiến trình theo trang, hủy trước khi ghi, lỗi và thử lại | Xuất thật trong luồng thường; khung đối chiếu không ghi tệp |
| 14 Kết quả lưu | Ảnh bìa, khổ giấy, dung lượng, kết quả cục bộ, mở và chia sẻ | PDF cục bộ thật; đồng bộ và thử tải lên là mẫu |
| 15 Xem PDF | Phóng to/thu nhỏ, vừa trang, lưới chọn trang, chi tiết, đổi tên, xuất ảnh trang và chia sẻ | Xem và quản lý dữ liệu cục bộ; OCR, in và chỉnh PDF đã lưu là mẫu |
| 16 Chia sẻ | Tóm tắt tệp, ứng dụng đích minh họa và mở bảng chia sẻ thiết bị | Chỉ chuyển tệp qua hệ điều hành khi người dùng bấm mở bảng chia sẻ |
| 17 OCR chọn phạm vi | Chọn trang hiện tại hoặc tất cả, thiết lập tiếng Việt | Dữ liệu mẫu |
| 18 OCR tiến trình | Vòng tiến trình, trạng thái từng trang, hủy, lỗi và xem kết quả mẫu | Dữ liệu mẫu; không chạy OCR |
| 19 OCR kết quả | Văn bản từng trang, đếm từ/ký tự, cảnh báo và sao chép | Sao chép văn bản minh họa; không sửa PDF gốc |

Chưa triển khai máy chủ, xác thực thật, lưu trực tuyến, OCR, khóa PDF hay thanh toán. Khung tham chiếu là ảnh từ ZIP; bản Flutter không hiển thị dung lượng, tỷ lệ nhận dạng hay trạng thái bảo mật giả trên dữ liệu thật.
