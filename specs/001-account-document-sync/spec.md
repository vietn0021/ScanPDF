# Đặc tả đăng nhập và lưu PDF theo tài khoản

**Trạng thái:** Đã chốt ranh giới xuất PDF; đặc tả cho lần tích hợp backend đầu tiên.

ScanPDF hiện tạo và lưu PDF cục bộ trong ứng dụng Flutter. Đăng nhập và đồng bộ đang dùng dữ liệu minh họa. Thay đổi đầu tiên là cho phép người dùng đăng nhập bằng tài khoản thật, lưu một PDF đã tạo lên kho riêng tư và tải lại tài liệu đó sau khi đăng nhập trên thiết bị khác.

## Clarifications

### Session 2026-11-07

- Q: Với bản ScanPDF có backend, đồ án có bắt buộc Node.js tạo file khi người dùng bấm “Xuất PDF” không? → A: Không. Flutter tiếp tục tạo PDF trên điện thoại; Node.js xử lý tài khoản và lưu trực tuyến.

## Kịch bản sử dụng

### P1 Đăng nhập và mở thư viện cá nhân

Người dùng tạo tài khoản hoặc đăng nhập từ giao diện hiện có. Sau khi xác thực thành công, họ chỉ thấy thư viện trực tuyến thuộc tài khoản của mình.

1. Khi thông tin đăng nhập hợp lệ, ứng dụng mở thư viện của đúng người dùng.
2. Khi đăng nhập không thành công, ứng dụng hiển thị lỗi phù hợp và không mở thư viện trực tuyến.
3. Yêu cầu dùng phiên hết hạn hoặc đã được máy chủ xác nhận thu hồi bị từ chối. Nếu đăng xuất khi mất mạng, ứng dụng khóa quyền truy cập trên thiết bị và thông báo chưa xác nhận thu hồi phiên trên máy chủ. Đổi tài khoản không hiển thị thư viện hoặc bản lưu cục bộ của tài khoản trước.

### P1 Lưu một PDF trực tuyến và tải lại

Người dùng xuất PDF, mở kết quả lưu và chọn tải lên. Sau khi hoàn tất, tài liệu xuất hiện trong thư viện trực tuyến với tên và số trang. Người dùng có thể tải về và mở đúng PDF đó.

1. Tệp và bản ghi phải thuộc tài khoản xác thực đã gửi yêu cầu.
2. Chỉ hiện “Đã lưu trực tuyến” khi máy chủ xác nhận hoàn tất cả phần tệp và thông tin tài liệu.
3. Khi đăng nhập cùng tài khoản trên một thiết bị khác, người dùng có thể xem danh sách, tải và mở tài liệu đã lưu.
4. Tài khoản khác không thể đọc, tải hoặc thay đổi tài liệu, kể cả khi biết mã tài liệu hoặc đường dẫn tệp.

### P2 Giữ bản trên máy khi tải lên lỗi

Người dùng vẫn mở và chia sẻ được PDF đã lưu cục bộ khi mất mạng. Sau khi kết nối trở lại và phiên đăng nhập hợp lệ, họ có thể thử tải lên lại.

1. Lỗi tải lên không xóa hoặc thay đổi file PDF trên máy.
2. Khi thử lại cùng lần lưu, ứng dụng không tạo thêm bản ghi trùng nếu lần trước đã hoàn tất nhưng mất phản hồi.
3. Tệp không hợp lệ hoặc lớn hơn 20 MiB bị từ chối với thông báo rõ ràng. Bản cục bộ vẫn dùng được.

## Yêu cầu và phạm vi

- **FR-001:** Xác thực yêu cầu đọc và ghi; xác định chủ sở hữu từ phiên đã được máy chủ xác minh.
- **FR-002:** Chỉ cho chủ sở hữu liệt kê, tải lên và tải xuống tài liệu của mình.
- **FR-003:** Lưu PDF riêng tư cùng mã tài liệu, tên, số trang, dung lượng và thời điểm tạo.
- **FR-004:** Phân biệt trạng thái lưu trên máy, đang tải lên, đã lưu trực tuyến và tải lên lỗi.
- **FR-005:** Flutter tạo, lưu và chia sẻ PDF cục bộ mà không cần mạng. Backend chỉ nhận tệp PDF đã tạo khi người dùng chủ động tải lên; không nhận ảnh quét để dựng PDF.
- **FR-006:** Không tải tự động tài liệu từ tài khoản mẫu hoặc chuyển tài liệu giữa các tài khoản khi đổi phiên.
- **FR-007:** Phiên bị máy chủ xác nhận thu hồi không thể dùng lại để liệt kê, tải lên hoặc tải xuống tài liệu; đăng xuất trên một thiết bị không làm mất phiên của cùng tài khoản trên thiết bị khác.
- **FR-008:** Thử lại cùng một lần tải lên trả về cùng tài liệu. Dùng cùng mã lần tải lên với nội dung khác phải bị từ chối; không ghi đè bản đã lưu.

Ngoài phạm vi lần đầu: OCR, đổi mật khẩu và cập nhật hồ sơ qua máy chủ, đổi tên hoặc xóa bản trực tuyến, chia sẻ liên kết công khai và hợp nhất thay đổi giữa nhiều thiết bị.

## Tiêu chí hoàn thành

- Thử với hai tài khoản: tài khoản A tải lên và tải lại được PDF; tài khoản B không thể liệt kê hoặc tải tệp của A.
- PDF tải lại có cùng nội dung byte với PDF đã tải lên.
- Mô phỏng mất mạng khi tải lên: PDF cục bộ vẫn mở được; thử lại thành công và chỉ có một bản ghi trực tuyến.
- Tệp hợp lệ đúng 20 MiB được chấp nhận; tệp lớn hơn một byte bị từ chối và không xuất hiện trong thư viện trực tuyến.
- Dùng lại token cũ sau khi máy chủ xác nhận đăng xuất: cả ba thao tác tài liệu bị từ chối; phiên trên thiết bị thứ hai vẫn hoạt động.
- Ở chế độ ngoại tuyến, xuất và mở được PDF thử nghiệm nhiều trang đúng thứ tự; tích hợp trực tuyến không thay đổi tệp đã tạo.

## Giả định cho lần tích hợp đầu tiên

- Dùng email và mật khẩu; yêu cầu xác nhận email trước khi tài khoản mới truy cập trực tuyến. Kiểm thử có thể dùng tài khoản mẫu đã xác nhận trong môi trường phát triển.
- Chấp nhận mỗi tệp PDF tối đa 20 MiB cho lần tích hợp đầu tiên. Tệp vượt mức vẫn có thể lưu và chia sẻ trên máy; chỉ tải lên bị từ chối.
- Nghiệm thu trước trên Android với máy chủ phát triển và dữ liệu mẫu. Bản web tiếp tục phục vụ luồng minh họa; phát hành máy chủ công khai không thuộc phạm vi lần đầu.
