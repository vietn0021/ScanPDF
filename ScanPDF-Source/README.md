# ScanPDF

Mã nguồn Flutter nằm trong `frontend`. API Node.js/Express, cấu hình Supabase và migration nằm trong `backend`. Flutter quét ảnh, tạo, lưu và chia sẻ PDF trên thiết bị. Khi người dùng chọn **Lưu trực tuyến**, API lưu bản PDF vào thư viện riêng của tài khoản.

## Chạy trên Windows và Android

Cần Node.js 24 LTS, Flutter với Android SDK và một dự án Supabase. Trong Supabase Auth, bật đăng ký bằng email và **Confirm email**. Khi thử gửi thư đến địa chỉ ngoài nhóm dự án, cấu hình SMTP cho dự án. [Cài Node.js](https://nodejs.org/en/download) · [Thiết lập Flutter trên Android](https://docs.flutter.dev/platform-integration/android/setup) · [Cấu hình SMTP Supabase](https://supabase.com/docs/guides/auth/auth-smtp)

### 1. Chạy backend

Mở PowerShell tại thư mục `ScanPDF-Source` rồi chạy:

```powershell
cd backend
if (!(Test-Path .env)) { Copy-Item .env.example .env }
```

Điền các giá trị sau trong `backend/.env`:

| Biến | Giá trị lấy từ Supabase |
| --- | --- |
| `SUPABASE_URL` | Project URL, dạng `https://<project-ref>.supabase.co` |
| `SUPABASE_PUBLISHABLE_KEY` | Publishable key dùng cho Auth |
| `SUPABASE_SECRET_KEY` | Secret key dành cho máy chủ |
| `SUPABASE_DB_URL` | URI **Session pooler** hoặc **Direct connection** kèm mật khẩu DB, ưu tiên `sslmode=require` với dự án hosted |

Giữ `HOST=127.0.0.1`, `PORT=3000` và để trống `TRUST_PROXY` khi chạy trực tiếp trên máy phát triển. Lệnh sau áp dụng các migration rồi mở API:

```powershell
npm.cmd ci
npm.cmd run start:setup
```

Các lần sau chạy `npm.cmd start`. Kiểm tra API tại `http://127.0.0.1:3000/health`. Chỉ lệnh setup cần mật khẩu PostgreSQL. Giữ khóa máy chủ và URI DB trong backend. [API keys](https://supabase.com/docs/guides/api/api-keys) · [Chuỗi kết nối Supabase](https://supabase.com/docs/guides/database/connecting-to-postgres)

| Biến | Giá trị và phạm vi |
| --- | --- |
| `TRUST_PROXY` | Đặt `1` khi API đứng sau đúng một reverse proxy đáng tin cậy và chỉ nhận lưu lượng qua proxy đó. Xóa giá trị khi chạy trực tiếp trên localhost. |
| `MAX_HEAVY` | Mặc định `2` lượt upload và tải nội dung đang mở trên mỗi tiến trình. |
| `MAX_DOCUMENTS_PER_OWNER` | Mặc định `200` tài liệu trên mỗi tài khoản, tính cả `pending`. |
| `MAX_BYTES_PER_OWNER` | Mặc định `209715200` byte (200 MiB) trên mỗi tài khoản, tính cả `pending`. |

Mốc cấu hình ban đầu cho host 512 MB là `MAX_HEAVY=2` cùng `NODE_OPTIONS=--max-old-space-size=256`. Với host 1 GB, bắt đầu từ `MAX_HEAVY=4`. Giới hạn V8 heap và RSS của tiến trình là hai số khác nhau. Đo lại với tải và tài liệu thực tế trên host trước khi chốt cấu hình.

Thư viện trực tuyến hỗ trợ xóa từng tài liệu. API xóa object trước rồi xóa dòng PostgreSQL. Khi xóa tài khoản, `ON DELETE CASCADE` chỉ xóa các dòng PostgreSQL. Các object dưới `<owner_id>/` trong Storage cần được dọn riêng.

### 2. Chạy frontend

Mở PowerShell thứ hai tại `ScanPDF-Source`:

```powershell
cd frontend
if (!(Test-Path .env)) { Copy-Item .env.example .env }
flutter pub get
flutter run --dart-define-from-file=.env
```

- **Android Emulator** dùng URL mặc định `http://10.0.2.2:3000/v1`.
- **Điện thoại Android cắm USB** bật USB debugging, chạy `adb reverse tcp:3000 tcp:3000`, rồi đặt `SCANPDF_API_BASE_URL=http://127.0.0.1:3000/v1` trong `frontend/.env`.
- **Android kết nối từ xa** dùng URL HTTPS của API. Bản web giữ luồng dùng thử.

Đăng ký, xác nhận email và đăng nhập. Xuất một PDF rồi chọn **Lưu trực tuyến** ở màn hình kết quả. Mở **Thư viện → Thư viện trực tuyến** để tải và xem tệp. PDF tải từ thư viện trực tuyến dùng vùng tạm riêng của ứng dụng trong lúc xem.

Khi triển khai, thêm `https://<service>.onrender.com/auth/confirmed` vào **Authentication → URL Configuration → Redirect URLs** trong Supabase và đặt cùng URL cho `SUPABASE_EMAIL_REDIRECT_URL` trên Render. Trang này hướng dẫn người dùng quay lại ScanPDF sau khi mở liên kết xác nhận. Nếu dùng email template tùy chỉnh, giữ liên kết xác nhận của Supabase và cấu hình để nó dùng URL chuyển hướng.

Người dùng đã đăng nhập có thể đổi mật khẩu từ mục **Tài khoản**. API gửi mật khẩu hiện tại và mật khẩu mới qua kết nối HTTPS tới Supabase Auth. Nếu Supabase yêu cầu xác thực lại do phiên đã cũ, đăng xuất và đăng nhập lại trước khi đổi.

## Triển khai Render

Tạo một Web Service dùng Node từ repository này.

| Thiết lập | Giá trị |
| --- | --- |
| Root Directory | `ScanPDF-Source/backend` |
| Build Command | `npm ci` |
| Start Command | `node src/server.js` |
| Health Check Path | `/health` |
| Biến runtime | `HOST=0.0.0.0`, `NODE_VERSION=24.22.2`, `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_SECRET_KEY` |

Áp dụng migration cho đúng dự án Supabase trước khi mở API. Có thể chạy `npm.cmd run setup` từ backend trên máy phát triển với chuỗi kết nối DB đã cấu hình. Giữ `SUPABASE_DB_URL` ở môi trường chạy migration. Render cấp `PORT` và URL HTTPS của dịch vụ. [Render Web Services](https://render.com/docs/web-services) · [Cấu hình secret trên Render](https://render.com/docs/configure-environment-variables)

Sau khi triển khai, kiểm tra `https://<service>.onrender.com/health` và thử đăng nhập, tải lên, tải xuống, xóa PDF với tài khoản thử. Từ thư mục `frontend`, build APK trỏ đến API HTTPS.

```powershell
flutter build apk --release --dart-define=SCANPDF_API_BASE_URL=https://<service>.onrender.com/v1
```

Thay `<service>` bằng tên dịch vụ thật trước khi chạy lệnh. Xem [cách ký và kiểm tra APK](frontend/README.md#ký-bản-phát-hành-android).

## Kiểm thử

```powershell
# Chạy từ backend
npm.cmd test

# Chạy từ frontend
flutter analyze
flutter test
```

Để kiểm thử với Supabase, dùng dự án phát triển đã chạy migration và hai tài khoản thử đã xác nhận email. Bỏ dấu `#` và điền nhóm biến `SCANPDF_TEST_*` trong `backend/.env`, sau đó chạy `npm.cmd run test:integration`. Bài kiểm thử tạo một PDF mẫu trong thư viện tài khoản A. [Kịch bản nghiệm thu](../specs/001-account-document-sync/quickstart.md)

Test quota tích hợp tạo tài khoản thử riêng qua Auth Admin, chạy ba lượt tranh chỗ cuối và dọn Storage trước khi xóa tài khoản thử. Chạy bộ test này trên dự án phát triển.
