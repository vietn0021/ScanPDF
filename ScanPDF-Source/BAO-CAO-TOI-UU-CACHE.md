# Báo cáo tối ưu ảnh bìa thư viện ScanPDF

Ngày 12/11/2026 · Phạm vi là thư viện cục bộ trong `ScanPDF-Source/frontend`.

## Vấn đề và thay đổi

Trước đây, mỗi lần thẻ tài liệu dựng lại, `FutureBuilder` gọi `store.page(owner, doc, 0)` để lấy ảnh trang đầu. Trên Android, thao tác này đọc lại JPEG từ bộ nhớ thiết bị. `cacheWidth` giảm kích thước ảnh khi giải mã, còn việc đọc JPEG vẫn diễn ra.

- Dùng chung widget ảnh bìa cho dạng danh sách và dạng lưới. Mỗi widget giữ một `Future` đọc trang đầu suốt vòng đời của nó. Thay đổi tên tài liệu hoặc dựng lại thẻ đang hiển thị dùng lại kết quả đọc.
- Khóa widget ảnh bìa theo nguồn lưu trữ, chủ sở hữu và mã tài liệu. Khi một trong ba giá trị đổi, Flutter tạo trạng thái ảnh bìa mới. Thẻ lưới cũng có khóa theo mã tài liệu, tương tự thẻ danh sách.
- Giữ kích thước giải mã hiện có, 140 px ở danh sách và 240 px ở lưới. Khi widget bị hủy, lần hiển thị sau có thể đọc lại JPEG. Cache này có phạm vi theo widget và dùng bộ nhớ, nên không phát sinh tệp cache chứa tài liệu.

Mã triển khai nằm trong [`frontend/lib/library.dart`](frontend/lib/library.dart). Kiểm thử hồi quy nằm trong [`frontend/test/scan_flow_test.dart`](frontend/test/scan_flow_test.dart).

## Kiểm chứng

Hai widget test đếm số lần đọc ảnh trang đầu ở cả dạng danh sách và dạng lưới. Lần hiển thị đầu đọc một lần. Khi dựng lại thẻ với tên mới, tổng số lần đọc vẫn là một. Khi đổi chủ sở hữu và giữ nguyên mã tài liệu, widget đọc ảnh theo chủ sở hữu mới.

- Bộ test Flutter đạt 17/17.
- `dart analyze` trên hai tệp Dart đã sửa không báo vấn đề.

Chưa đo thời gian cuộn, thời gian tải hoặc RAM trên thiết bị Android. Kết quả hiện tại xác nhận số lần đọc qua `ScanStore` trong các trường hợp được kiểm thử. PDF trực tuyến và các hạng mục tối ưu backend nằm ngoài phạm vi đợt này.
