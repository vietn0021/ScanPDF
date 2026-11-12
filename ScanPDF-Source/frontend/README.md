# ScanPDF Flutter

Ứng dụng chụp hoặc nhập ảnh, chỉnh trang và tạo PDF trên thiết bị. Bản Android tích hợp Express và Supabase để đăng ký bằng email, đăng nhập, lưu PDF theo yêu cầu, xem và xóa PDF trực tuyến. Web dùng cho luồng trải nghiệm cục bộ. Xem [README bản tích hợp](../README.md) để cấu hình backend và Supabase.

## Chạy Android

```powershell
if (!(Test-Path .env)) { Copy-Item .env.example .env }
flutter pub get
flutter run --dart-define-from-file=.env
```

- Emulator dùng `SCANPDF_API_BASE_URL=http://10.0.2.2:3000/v1` khi chạy debug.
- Điện thoại qua USB có thể dùng `adb reverse tcp:3000 tcp:3000` với URL `http://127.0.0.1:3000/v1` khi chạy debug.
- Bản release yêu cầu HTTPS nếu bật API. Chọn **Lưu trực tuyến** sau khi xuất PDF để tải lên. Trong **Thư viện trực tuyến**, chạm tài liệu để mở hoặc chọn biểu tượng xóa để xóa bản trên máy chủ.

## Ký bản phát hành Android

Đặt cấu hình keystore release trong `android/key.properties` với các mục `storeFile`, `storePassword`, `keyAlias` và `keyPassword`. `storeFile` có thể là đường dẫn tuyệt đối hoặc tương đối với `android/`. Giữ file cấu hình và keystore ngoài gói mã nguồn chia sẻ.

Gradle dùng khóa debug khi thiếu file cấu hình để phục vụ build thử nội bộ. APK bàn giao hoặc đưa lên Google Play phải ký bằng keystore release. Kiểm tra APK trước khi bàn giao.

```powershell
apksigner verify --print-certs <duong-dan-apk>
```

Lệnh phải xác minh thành công và thông tin chứng thư không được có chuỗi `Android Debug`.

## Luồng quét và chế độ mẫu

- Quét hoặc nhập tối đa 50 trang, chỉnh phối cảnh, xoay, bộ lọc, độ sáng, tương phản và thứ tự. PDF có thể xuất theo A4, Letter hoặc tỷ lệ ảnh.
- Có thể dùng tài khoản mẫu, tài liệu mẫu và bộ 19 màn hình tham chiếu bằng `--dart-define=DESIGN_PREVIEW=true`. Trên Android đã kết nối API, vào **Tài khoản → Đổi mật khẩu** để cập nhật mật khẩu. OCR và khôi phục mật khẩu qua email chưa được triển khai.
- Xem [đối chiếu các khung Stitch](STITCH-REVIEW.md) để kiểm tra phạm vi từng màn hình.

## Kiểm tra

```powershell
flutter analyze
flutter test
```
