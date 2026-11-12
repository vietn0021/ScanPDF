# Tasks: Đăng nhập và lưu PDF theo tài khoản

**Đầu vào:** [Đặc tả](spec.md), [kế hoạch](plan.md), [mô hình dữ liệu](data-model.md), [hợp đồng](contracts/http-api.md), [nghiệm thu](quickstart.md).

Các đường dẫn mã nguồn bên dưới tính từ `ScanPDF-Source/`. Dấu kiểm ghi việc triển khai hoặc kiểm thử đã thực hiện.

## Phase 1: Setup

- [x] T001 Xác nhận Node.js 24.22.2 chạy được. Ghi cách dùng Supabase hosted hoặc CLI/Docker trong hướng dẫn chạy.
- [x] T002 Khởi tạo Express 5, lệnh chạy và lockfile trong `backend/package.json` và `backend/package-lock.json`.
- [x] T003 [P] Cấu hình xác nhận email và hộp thư thử trong `backend/supabase/config.toml`.
- [x] T004 [P] Thêm biến mẫu và kiểm tra cấu hình trong `backend/.env.example`, `backend/src/server.js` và `backend/scripts/setup.js`.

## Phase 2: Foundational

- [x] T005 Tạo bảng và bucket riêng tư trong `backend/supabase/migrations/202611070001_documents.sql` với ràng buộc theo [mô hình dữ liệu](data-model.md).
- [x] T006 [P] Tạo hàm kiểm tra cặp UUID phiên và người dùng trong `backend/supabase/migrations/202611070002_active_session.sql`. Chỉ máy chủ có quyền thực thi.
- [x] T007 [P] Tạo API v1, chuẩn lỗi, request ID, giới hạn request và tần suất trong `backend/src/app.js` và `backend/src/errors.js`.
- [x] T008 [P] Tạo lớp API Flutter, cấu hình URL và quyền mạng Android. Chấp nhận HTTP cục bộ ở debug.

## Phase 3: User Story 1 — Đăng nhập và mở thư viện cá nhân (P1)

**Kiểm tra độc lập:** xác nhận email, đăng nhập A trên hai thiết bị, thu hồi phiên thứ nhất và kiểm tra phiên thứ hai còn hoạt động.

- [x] T009 [P] [US1] Kiểm thử đăng ký, đăng nhập, làm mới, phiên thiếu, phiên đã đăng xuất và lỗi tra cứu trong `backend/test/api.test.js`.
- [x] T010 [US1] Nối đăng ký, đăng nhập, làm mới, thông tin phiên và đăng xuất thiết bị trong `backend/src/app.js` và `backend/src/supabase.js`.
- [x] T011 [US1] Xác minh JWT và kiểm tra phiên trong `backend/src/supabase.js`. Thiếu phiên trả 401, lỗi tra cứu trả 503.
- [x] T012 [P] [US1] Bổ sung kho phiên Flutter theo tùy chọn ghi nhớ, làm mới đơn luồng và xóa phiên khi đăng xuất trong `frontend/lib/online/session_store.dart`.
- [x] T013 [US1] Nối đăng nhập, đăng ký và phục hồi phiên. Tách `auth:<user_uuid>` và giữ luồng mẫu trong `frontend/lib/main.dart`, `frontend/lib/account.dart` và `frontend/lib/scan_data.dart`.
- [x] T014 [US1] Kiểm thử đổi tài khoản và đăng xuất ngoại tuyến trong `frontend/test/online_test.dart`. Hiển thị kết quả thu hồi trong `frontend/lib/main.dart`.

## Phase 4: User Story 2 — Lưu một PDF trực tuyến và tải lại (P1)

**Kiểm tra độc lập:** A lưu PDF, thiết bị thứ hai tải và mở cùng tệp; B biết ID vẫn không tải được.

- [x] T015 [P] [US2] Kiểm thử upload, list, download, cách ly tài khoản, phiên thu hồi, đúng 20 MiB và PDF lỗi trong `backend/test/api.test.js`.
- [x] T016 [US2] Kiểm tra tệp, số trang, kích thước, SHA-256 và tên trong `backend/src/app.js` và `backend/src/pdf-worker.js`.
- [x] T017 [US2] Dành chỗ theo `(owner_id, upload_id)`, lưu object riêng, chuyển `ready`, phân trang và kiểm tra chủ sở hữu trong `backend/src/app.js` và `backend/src/supabase.js`.
- [x] T018 [P] [US2] Mở PDF tải xuống bằng Android `PdfRenderer` trong `frontend/android/app/src/main/kotlin/vn/scanpdf/scanpdf/MainActivity.kt` và `frontend/lib/online/documents.dart`.
- [x] T019 [US2] Nối tải lên, danh sách, kiểm tra hash và mở tệp tạm theo tài khoản trong `frontend/lib/online/documents.dart`, `frontend/lib/editor.dart` và `frontend/lib/library.dart`.
- [ ] T020 [US2] Chạy `backend/test/supabase.test.js` với hai tài khoản thật trên dự án phát triển. Xác nhận tải và mở PDF trên cài đặt Android sạch theo [quickstart.md](quickstart.md).

## Phase 5: User Story 3 — Giữ bản trên máy và thử lại (P2)

**Kiểm tra độc lập:** ngắt mạng khi tải lên, đóng app, mở lại và thử cùng mã; một tệp trực tuyến, PDF cục bộ còn nguyên.

- [x] T021 [P] [US3] Kiểm thử thử lại đồng thời, lỗi sau khi ghi file và đổi payload cùng UUID trong `backend/test/api.test.js`.
- [x] T022 [US3] Đối chiếu hash, kích thước và tên. Khôi phục object đã ghi, xử lý thử lại đồng thời và từ chối payload khác trong `backend/src/app.js`.
- [x] T023 [US3] Lưu UUID và tên lần tải lên theo tài khoản trong `frontend/lib/online/documents.dart`. Giữ file cục bộ và chờ API xác nhận.
- [x] T024 [US3] Kiểm thử mất mạng, khôi phục mã khi dựng lại màn hình, giữ file cục bộ và cách ly mẫu trong `frontend/test/online_test.dart` và `frontend/test/scan_flow_test.dart`.

## Phase 6: Verification

- [x] T025 Chạy kiểm thử backend, phân tích và kiểm thử Flutter, build Android. Ghi kết quả theo [quickstart.md](quickstart.md).
- [x] T026 Đối chiếu mã và kiểm thử với [đặc tả](spec.md), [hợp đồng HTTP](contracts/http-api.md) và `frontend/STITCH-REVIEW.md`.

## Dependencies & Execution Order

Setup → Foundational → US1 → US2 → US3 → Verification. Trong US1 có thể chuẩn bị kiểm thử hợp đồng và kho phiên Flutter song song; US2 có thể kiểm tra trình xem trong khi viết API; US3 có thể viết kịch bản lỗi trước khi tích hợp thử lại.

## Implementation Strategy

Triển khai dọc theo từng câu chuyện. US1 là mốc đầu: đăng nhập và thu hồi phiên thật. MVP tính năng hoàn chỉnh cần US1 + US2 + US3 để chứng minh lưu và tải PDF riêng tư kể cả khi có sự cố mạng. Không đưa OCR, triển khai công khai hay sửa chức năng xuất PDF vào đợt này.

## Phase 7: Convergence

- [ ] T027 [HIGH] Sau T020, thử upload PDF đúng 20 MiB vào bucket Supabase, ngắt mạng trong lúc upload trên Android rồi đóng và mở lại ứng dụng. Xác nhận file cục bộ mở được và lần thử lại chỉ tạo một mục, theo tiêu chí hoàn thành và US3 trong [đặc tả](spec.md) (partial).
