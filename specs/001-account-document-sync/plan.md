# Implementation Plan: Đăng nhập và lưu PDF theo tài khoản

**Feature**: `001-account-document-sync` | **Date**: 2026-11-07 | **Spec**: [spec.md](spec.md)

## Summary

Flutter tiếp tục quét và tạo PDF trên thiết bị. Bổ sung API Node.js/Express để xác thực tài khoản, tải lên PDF đã tạo và tải lại tài liệu riêng tư trên thiết bị khác. Chỉ thay các điểm tích hợp trực tuyến của giao diện Stitch; bản mẫu và lưu cục bộ không phụ thuộc máy chủ.

## Technical Context

- **Flutter:** dùng lại Flutter 3.35/Dart 3.9 và mô hình `SavedScan`. `ScanPDF-Source/frontend/lib/main.dart` dùng UUID do máy chủ trả về để tách thư viện thật và thư viện mẫu.
- **API:** Node.js 24 LTS, Express 5, REST có tiền tố `/v1`. Dùng Supabase Auth qua Node để đăng ký, đăng nhập, làm mới và thu hồi phiên.
- **Dữ liệu:** Supabase PostgreSQL + Storage riêng tư. Chỉ Node có quyền đọc bảng và kho tệp; mọi truy vấn tài liệu lấy chủ sở hữu từ phiên đã kiểm chứng. Flutter không nhận khóa dịch vụ hoặc URL tải công khai.
- **Khởi chạy:** Android là đích nghiệm thu. Dùng dự án Supabase phát triển và hai tài khoản thử đã xác nhận. Có thể dùng Supabase hosted với `npm run start:setup` hoặc cấu hình CLI/Docker trong backend. Đã kiểm tra Node 24.22.2.
- **Kiểm thử:** kiểm thử API, tích hợp hai tài khoản với kho thật trong môi trường phát triển, và kiểm thử Flutter liên quan.

## Constitution Check

- **I — Thay đổi theo đặc tả:** ba luồng độc lập và hợp đồng API có thể kiểm tra. Giữ các màn hình và điều hướng hiện có.
- **II — Giữ luồng cục bộ:** không chuyển tạo PDF lên Node. Mất mạng không làm mất PDF đã lưu; trạng thái trực tuyến là lớp bổ sung.
- **III — Phân quyền:** xác minh token và phiên còn hiệu lực, lọc theo chủ sở hữu; kiểm thử phiên hết hạn, token sau đăng xuất và truy cập chéo. Không đưa bí mật vào Flutter.
- **IV — Tách dữ liệu mẫu:** giữ kho mẫu riêng; chỉ tải lên từ tài khoản thật do người dùng chủ động chọn.
- **V — Kiểm thử:** tiêu chí và môi trường được liệt kê trong [quickstart.md](quickstart.md).

## Project Structure

### Documentation

- [Quyết định kỹ thuật](research.md)
- [Mô hình dữ liệu](data-model.md)
- [Hợp đồng HTTP](contracts/http-api.md)
- [Hướng dẫn nghiệm thu](quickstart.md)

### Source Code

```text
ScanPDF-Source/
  backend/
    package.json
    .env.example
    src/
    scripts/
    supabase/
    test/
  frontend/
    .env.example
    lib/online/
    lib/{main,account,scan_data,editor,library}.dart
    android/
    test/
```

Luồng tích hợp Flutter đặt ở `frontend/lib/online/`. Lưu PDF cục bộ dùng `ScanStore`. Android dùng `PdfRenderer` để xem bản tải đã kiểm tra SHA-256 trong vùng tạm riêng.

## Complexity Tracking

Giữ một API và một dịch vụ dữ liệu. Cần lưu dấu lần tải lên và trạng thái chờ vì PostgreSQL và Storage không cùng một giao dịch; thiết kế phải xử lý trường hợp đã ghi file nhưng chưa trả được kết quả.
