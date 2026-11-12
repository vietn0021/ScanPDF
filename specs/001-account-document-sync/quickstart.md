# Cách nghiệm thu tích hợp lần đầu

## Chuẩn bị

1. Tạo một dự án Supabase phát triển. Với Docker và Supabase CLI, cũng có thể chạy `supabase start` từ `ScanPDF-Source/backend` và dùng hộp thư thử ở cổng 54324.
2. Tạo hai tài khoản thử A và B, xác nhận email cho cả hai. Điền `.env` ở backend và frontend theo [hướng dẫn chạy](../../ScanPDF-Source/README.md).
3. Từ `ScanPDF-Source/backend`, chạy `npm ci`, `npm run start:setup` và `npm test`. Chạy `npm run test:integration` với nhóm biến kiểm thử để thử kho thật.
4. Từ `ScanPDF-Source/frontend`, chạy `flutter run --dart-define-from-file=.env` với Android. Chạy `flutter analyze` và `flutter test`.

## Kịch bản và kết quả mong đợi

1. **US1 — Phiên:** xác nhận email và đăng nhập A trên hai thiết bị; đăng xuất thiết bị thứ nhất. Token đã lưu từ thiết bị thứ nhất bị 401 với list, upload và download; thiết bị thứ hai vẫn hoạt động. Khi mất mạng lúc đăng xuất, khóa dữ liệu trên máy và hiển thị chưa xác nhận thu hồi.
2. **US2 — PDF riêng tư:** A tải PDF ba trang, mở trên thiết bị thứ hai và kiểm tra số trang/hash. B không thấy tệp trong danh sách; gọi tải xuống bằng ID của A nhận 404. Thử trực tiếp bucket bằng quyền client cũng không đọc được.
3. **US3 — Mất mạng và thử lại:** ngắt kết nối khi upload, trước hoàn tất hoặc sau khi server đã ghi nhưng trước khi client nhận phản hồi. PDF trên máy vẫn mở/chia sẻ. Khởi động lại app và thử lại cùng mã: đúng một tài liệu, hash giữ nguyên. Cùng mã với payload khác trả 409. Thử đồng thời cùng payload không tạo trùng.
4. **Giới hạn:** PDF hợp lệ 20 MiB đi qua; file lớn hơn một byte trả 413, PDF hỏng trả 415, cả hai không có trong danh sách. Kiểm tra cả tải không khai kích thước.
5. **Ngoại tuyến:** ngắt mạng trước khi quét/chọn ảnh, đổi thứ tự và xuất PDF. Mở đúng thứ tự trên máy; không có request tạo PDF qua backend. Đổi tài khoản, xác nhận không lộ cache hoặc bản mẫu.

## Kết quả kiểm tra

- Node.js 24.22.2: `npm ci` từ lockfile và 5 bài `npm test` đạt. API dùng dịch vụ xác thực, dữ liệu và kho tệp giả lập. Có kiểm tra đúng 20 MiB, quyền chủ sở hữu, phiên thu hồi và thử lại đồng thời.
- Flutter: phân tích mã không báo lỗi, 13 bài kiểm thử đạt và build APK debug thành công. Các bài kiểm thử gồm xuất PDF cục bộ, mở thư viện đã ghi nhớ khi ngoại tuyến và tái sử dụng mã tải lên.
- Đã áp dụng migration lên dự án Supabase đã cấu hình và kiểm tra bảng `cloud_documents`, bucket riêng tư `scanpdf-documents`, hàm kiểm tra phiên và khóa publishable. Backend trả `ok` tại `/health`. Kiểm thử với hai tài khoản và mở PDF tải về trên Android vẫn thuộc T020 và T027 trong [đầu việc](tasks.md).
