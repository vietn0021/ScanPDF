# Quyết định kỹ thuật

## R01 — Flutter tạo PDF, Node xử lý trực tuyến

Giữ `makePdf`, ảnh xem trước và `ScanStore.save` trong Flutter. API chỉ nhận PDF hoàn chỉnh khi người dùng chọn tải lên. Cách tạo PDF tại máy chủ bị loại vì trái với quyết định A và làm bước xuất phụ thuộc mạng.

## R02 — Một API Node.js/Express và Supabase chạy cục bộ trước

Chọn Node.js 24 LTS, Express 5 và Supabase Auth, PostgreSQL, Storage. Dùng Supabase để xử lý mật khẩu và gửi email xác nhận. Môi trường phát triển có thể dùng dự án Supabase hosted hoặc Supabase CLI với Docker. [Node.js LTS](https://nodejs.org/en/about/previous-releases) · [Express routing](https://expressjs.com/en/guide/routing/) · [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started)

## R03 — Xác minh token và kiểm tra phiên còn hoạt động

Node bọc luồng xác thực Supabase. Với mỗi yêu cầu tài liệu, dùng `getClaims(token)` để xác minh chữ ký, hạn và project; kiểm tra `sub`, `aud`, `session_id`. Sau đó gọi hàm SQL chỉ cấp quyền thực thi cho máy chủ để kiểm tra cặp `(session_id, user_id)` trong `auth.sessions`. Thiếu phiên trả 401; lỗi khi kiểm tra trả 503, không trả dữ liệu. Đăng xuất dùng phạm vi `local` để thu hồi phiên hiện tại. JWT đã phát hành có thể vẫn đúng chữ ký sau đăng xuất, nên xác minh chữ ký đơn thuần không đủ. Kiểm tra [Supabase sessions](https://supabase.com/docs/guides/auth/sessions#how-to-ensure-an-access-token-jwt-cannot-be-used-after-a-user-signs-out), [getClaims](https://supabase.com/docs/reference/javascript/auth-getclaims) và [admin signOut](https://supabase.com/docs/reference/javascript/auth-admin-signout).

Flutter giữ access token trong bộ nhớ. Khi người dùng chọn ghi nhớ, giữ refresh token ở kho bí mật của hệ điều hành và mở thư viện cục bộ ngay khi khởi động. Khi cần truy cập trực tuyến, làm mới token một lần tại một thời điểm. Tài khoản chưa xác nhận email không được truy cập; dùng hộp thư thử của stack cục bộ. Khi mất mạng và đăng xuất, xóa phiên trên thiết bị và chỉ xác nhận đã thu hồi từ xa nếu máy chủ trả thành công.

## R04 — Kho riêng tư và quyền sở hữu

Không mở quyền đọc bảng hoặc bucket PDF cho client Supabase. Node dùng thông tin xác thực máy chủ, tìm metadata theo đồng thời mã tài liệu và `owner_id` của phiên trước khi đọc object. Dùng object key do máy chủ tạo. Tải xuống qua Node, không dùng liên kết có thể truy cập lại sau khi thu hồi phiên. Tài liệu thiếu và tài liệu của người khác cùng trả 404. [Supabase Storage access control](https://supabase.com/docs/guides/storage/security/access-control) giải thích khóa dịch vụ vượt qua RLS; vì thế kiểm tra chủ sở hữu ở Node là bắt buộc.

## R05 — Thử lại an toàn với cùng mã lần tải lên

Ứng dụng lưu một UUID ổn định cho lần tải lên. Máy chủ dành chỗ theo cặp chủ sở hữu/UUID trước khi ghi object, đối chiếu SHA-256 và metadata; cùng payload thì dùng lại bản ghi, payload khác trả 409. Không ghi đè object. Nếu việc ghi object đã xong nhưng cập nhật metadata hoặc phản hồi thất bại, thử lại xác minh digest/size của object đã tồn tại rồi hoàn tất bản ghi cũ. Chỉ tài liệu `ready` xuất hiện trong danh sách hoặc được tải xuống.

Giới hạn 20 MiB trên cả API và bucket; đếm bytes thực tế. Supabase [khuyến nghị tải nối tiếp cho file trên 6 MB](https://supabase.com/docs/guides/storage/uploads/standard-uploads). Lần đầu thử lại toàn bộ tệp, chưa nối tiếp theo byte; cần nghiệm thu ở đúng giới hạn đã chốt.

## R06 — Xem PDF tải từ thiết bị khác

Trình xem tải xuống đọc PDF đã xác minh SHA-256 từ vùng tạm riêng. Dùng `PdfRenderer` sẵn có trên Android qua một Flutter MethodChannel. Bản debug chấp nhận HTTP loopback và địa chỉ máy host của emulator. Bản release dùng HTTPS. [Android PdfRenderer](https://developer.android.com/reference/android/graphics/pdf/PdfRenderer) · [Địa chỉ mạng của emulator](https://developer.android.com/studio/run/emulator-networking-address)
