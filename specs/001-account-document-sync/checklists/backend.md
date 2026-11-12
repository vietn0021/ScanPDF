# Checklist chất lượng yêu cầu backend ScanPDF

## Phạm vi và phân quyền

- [x] CHK001 Có xác định rõ bên tạo PDF và khi nào mới gửi tệp lên máy chủ không? [Spec FR-005]
- [x] CHK002 Có phân biệt xác thực, phiên bị thu hồi, lỗi phụ thuộc và truy cập chéo tài khoản không? [Spec FR-001, FR-002, FR-007; Contract Lỗi]
- [x] CHK003 Có xác định dữ liệu mẫu, quyền khi đổi tài khoản và giới hạn chia sẻ không? [Spec FR-006; Plan Constitution Check]

## Dữ liệu và nghiệm thu

- [x] CHK004 Có giới hạn file theo byte, số trang và quy tắc nhận diện PDF lỗi không? [Data model cloud_documents; Contract Lỗi]
- [x] CHK005 Có quy tắc thử lại, phát hiện trùng và phục hồi khi file đã ghi nhưng metadata chưa hoàn tất không? [Spec FR-008; Research R05]
- [x] CHK006 Có tiêu chí mở PDF trên thiết bị thứ hai, kiểm tra hash và giữ bản cục bộ khi lỗi mạng không? [Quickstart US2, US3]
- [x] CHK007 Có nêu rõ môi trường thử Android, điểm lưu bí mật và các chức năng ngoài phạm vi không? [Spec Giả định; Plan Technical Context]
