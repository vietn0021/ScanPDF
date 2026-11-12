# ScanPDF

ScanPDF là ứng dụng Android viết bằng Flutter để chụp hoặc nhập ảnh, chỉnh từng trang và xuất PDF trên thiết bị. Khi bật kết nối trực tuyến, người dùng có thể lưu, tải, xem và xóa PDF trong thư viện riêng. Express xác thực yêu cầu và làm việc với Supabase Auth, PostgreSQL và Storage.

## Tính năng

- Chụp hoặc nhập ảnh, cắt viền, chỉnh phối cảnh, xoay, áp dụng bộ lọc và đổi thứ tự trang.
- Xuất tài liệu tối đa 50 trang ở khổ A4, Letter hoặc theo tỷ lệ ảnh. Tìm kiếm, đổi tên, xóa và chia sẻ PDF trên thiết bị.
- Đăng ký bằng email và lưu PDF trực tuyến theo yêu cầu trên Android. API kiểm tra chủ sở hữu, kích thước, số trang và hạn mức lưu trữ.
- Web dùng cho trải nghiệm cục bộ. OCR và đổi mật khẩu hiện là giao diện minh họa.

## Cấu trúc repository

| Đường dẫn | Nội dung |
| --- | --- |
| [`ScanPDF-Source/frontend/`](ScanPDF-Source/frontend/) | Ứng dụng Flutter, cấu hình Android, tài nguyên Stitch và widget test. |
| [`ScanPDF-Source/backend/`](ScanPDF-Source/backend/) | Express API, cấu hình Supabase, migration và test API. |
| [`specs/001-account-document-sync/`](specs/001-account-document-sync/) | Đặc tả tài khoản, mô hình dữ liệu, hợp đồng API và kịch bản nghiệm thu. |
| [`BAO-CAO-DU-AN-SCANPDF.md`](BAO-CAO-DU-AN-SCANPDF.md) | Báo cáo kiến trúc, logic, bảo mật, kết quả kiểm thử và giới hạn đã biết. |

## Bắt đầu

1. Cài Node.js 24, Flutter tương thích Dart 3.9.2 và Android SDK. Chuẩn bị dự án Supabase phát triển nếu cần thử chức năng trực tuyến.
2. Làm theo [hướng dẫn chạy backend và cấu hình Supabase](ScanPDF-Source/README.md#1-chạy-backend) để áp dụng migration và mở API.
3. Làm theo [hướng dẫn chạy Flutter](ScanPDF-Source/frontend/README.md#chạy-android) để kết nối ứng dụng với backend. Có thể chạy luồng tài liệu mẫu cục bộ bằng `flutter run` từ thư mục `ScanPDF-Source/frontend`.

## Kiểm thử

```powershell
npm.cmd --prefix ScanPDF-Source/backend ci
npm.cmd --prefix ScanPDF-Source/backend test
Set-Location ScanPDF-Source/frontend
flutter pub get
flutter analyze
flutter test
```

Xem [kịch bản nghiệm thu](specs/001-account-document-sync/quickstart.md) để kiểm tra với Supabase phát triển. Kiểm tra `/health` xác nhận tiến trình API đang chạy. Để xác nhận toàn bộ luồng, đăng nhập bằng tài khoản thử, lưu PDF trực tuyến, tải lại và xóa bản thử trên cloud.

## Triển khai và build APK

Xem [cấu hình Render](ScanPDF-Source/README.md#triển-khai-render) và [hướng dẫn ký APK release](ScanPDF-Source/frontend/README.md#ký-bản-phát-hành-android). Khóa Supabase phía máy chủ và keystore được cấu hình bên ngoài Git. APK sử dụng URL HTTPS của API khi bật tính năng trực tuyến.
