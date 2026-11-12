export class ApiError extends Error {
  constructor(status, code, message) {
    super(message);
    Object.assign(this, {status, code});
  }
}

export const invalid = (message = 'Dữ liệu không hợp lệ.') => new ApiError(400, 'INVALID_INPUT', message);
export const unauthorized = () => new ApiError(401, 'SESSION_INVALID', 'Phiên hoặc thông tin đăng nhập không hợp lệ.');
export const unavailable = () => new ApiError(503, 'DEPENDENCY_UNAVAILABLE', 'Dịch vụ chưa sẵn sàng. Vui lòng thử lại.');
export const missing = () => new ApiError(404, 'DOCUMENT_NOT_FOUND', 'Không tìm thấy tài liệu.');
export const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
