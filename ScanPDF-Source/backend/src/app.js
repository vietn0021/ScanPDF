import {randomUUID, createHash} from 'node:crypto';
import {Worker} from 'node:worker_threads';
import express from 'express';
import {rateLimit} from 'express-rate-limit';
import multer from 'multer';
import {ApiError, invalid, missing, unauthorized, unavailable, uuid} from './errors.js';

export const MAX_PDF = 20 * 1024 * 1024;
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const metadata = ({id, filename, page_count, byte_size, sha256, created_at}) =>
  ({id, filename, page_count, byte_size, sha256, created_at});

function sizeGuard(req, _res, next) {
  const length = req.get('Content-Length') ?? '';
  if (!/^\d+$/.test(length) || Number(length) > MAX_PDF + 64 * 1024) {
    return next(new ApiError(413, 'FILE_TOO_LARGE', 'PDF tối đa 20 MiB và phải có kích thước tải lên.'));
  }
  next();
}

async function countPages(bytes) {
  const worker = new Worker(new URL('./pdf-worker.js', import.meta.url), {
    workerData: bytes, resourceLimits: {maxOldGenerationSizeMb: 96},
  });
  try {
    return await new Promise(resolve => {
      const timer = setTimeout(() => resolve(null), 3000);
      timer.unref();
      worker.once('message', value => { clearTimeout(timer); resolve(value); });
      worker.once('error', () => { clearTimeout(timer); resolve(null); });
      worker.once('exit', () => { clearTimeout(timer); resolve(null); });
    });
  } finally {
    await worker.terminate();
  }
}

function validNewPassword(password) {
  return typeof password === 'string' && password.length >= 8 && password.length <= 128 &&
    /[A-Z]/.test(password) && /[a-z]/.test(password) && /[0-9]/.test(password) && /[^a-zA-Z0-9\s]/.test(password);
}

function credentials(body, register) {
  const email = typeof body?.email === 'string' ? body.email.trim().toLowerCase() : '';
  const password = body?.password;
  if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ||
      typeof password !== 'string' || password.length < (register ? 8 : 1) || password.length > 128) {
    throw invalid('Kiểm tra email và mật khẩu.');
  }
  if (register && !validNewPassword(password)) {
    throw invalid('Mật khẩu cần chữ hoa, chữ thường, số và ký tự đặc biệt.');
  }
  return {email, password};
}

function parseCursor(value) {
  if (value === undefined) return null;
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]{1,160}$/.test(value)) throw invalid();
  const [time, id, extra] = Buffer.from(value, 'base64url').toString('utf8').split('|');
  if (extra !== undefined || !uuid.test(id ?? '') ||
      !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+]00:00)$/.test(time) ||
      !Number.isFinite(Date.parse(time))) throw invalid();
  return {time, id};
}

export function createApp({auth, documents}, {maxHeavy = Number(process.env.MAX_HEAVY ?? 2)} = {}) {
  if (!Number.isSafeInteger(maxHeavy) || maxHeavy < 1) throw new Error('MAX_HEAVY phải là số nguyên dương.');
  const app = express();
  if (process.env.TRUST_PROXY) {
    const hops = Number(process.env.TRUST_PROXY);
    if (!Number.isSafeInteger(hops) || hops < 0) throw new Error('TRUST_PROXY phải là số hop hợp lệ.');
    app.set('trust proxy', Number(process.env.TRUST_PROXY));
  }
  app.disable('x-powered-by');
  app.use((req, res, next) => {
    req.requestId = randomUUID();
    res.set({'Cache-Control': 'private, no-store', 'X-Request-Id': req.requestId, 'X-Content-Type-Options': 'nosniff'});
    next();
  });
  app.use(express.json({limit: '12kb'}));
  const limiter = (limit, keyGenerator) => rateLimit({
    windowMs: 60_000, limit, standardHeaders: 'draft-8', legacyHeaders: false,
    ...(keyGenerator ? {keyGenerator} : {}),
    handler: (_req, _res, next) => next(new ApiError(429, 'RATE_LIMITED', 'Quá nhiều yêu cầu.')),
  });
  const authLimit = limiter(20);
  const uploadLimit = limiter(8, req => req.user.id);
  const apiLimit = limiter(120, req => req.user.id);
  let heavy = 0;
  function gate(_req, res, next) {
    if (heavy >= maxHeavy) return next(new ApiError(503, 'BUSY', 'Máy chủ đang bận. Vui lòng thử lại.'));
    heavy++;
    function release() {
      res.off('finish', release);
      res.off('close', release);
      heavy--;
    }
    res.once('finish', release);
    res.once('close', release);
    next();
  }
  const upload = multer({limits: {fileSize: MAX_PDF + 1, files: 1, fields: 1, parts: 3, fieldSize: 512}}).single('file');
  async function session(req, _res, next) {
    const match = /^Bearer ([A-Za-z0-9_.-]{1,8192})$/i.exec(req.get('Authorization') ?? '');
    if (!match) throw unauthorized();
    req.token = match[1];
    req.user = await auth.verify(req.token);
    next();
  }
  app.get('/health', (_req, res) => res.json({status: 'ok'}));
  app.get('/auth/confirmed', (_req, res) => res.type('text/plain').send(
    'Quay lại ScanPDF và đăng nhập. Nếu email chưa được xác nhận, hãy dùng liên kết mới nhất trong hộp thư.',
  ));
  app.post('/v1/auth/register', authLimit, async (req, res) => {
    const {email, password} = credentials(req.body, true);
    await auth.register(email, password);
    res.status(202).json({message: 'Nếu đăng ký hợp lệ, hãy kiểm tra email để xác nhận tài khoản.'});
  });
  app.post('/v1/auth/login', authLimit, async (req, res) => {
    const {email, password} = credentials(req.body, false);
    res.json(await auth.login(email, password));
  });
  app.post('/v1/auth/refresh', authLimit, async (req, res) => {
    const token = req.body?.refresh_token;
    if (typeof token !== 'string' || !token || token.length > 4096) throw invalid();
    res.json(await auth.refresh(token));
  });
  app.get('/v1/auth/me', session, apiLimit, (req, res) => res.json({user: req.user}));
  app.post('/v1/auth/password', authLimit, session, async (req, res) => {
    const {current_password: current, new_password: password} = req.body ?? {};
    if (typeof current !== 'string' || !current.length || current.length > 128 ||
        !validNewPassword(password) || current === password) {
      throw invalid('Nhập mật khẩu hiện tại và một mật khẩu mới hợp lệ, khác mật khẩu cũ.');
    }
    await auth.changePassword(req.token, req.user, current, password);
    res.status(204).end();
  });
  app.post('/v1/auth/logout', session, async (req, res) => {
    await auth.logout(req.token);
    res.status(204).end();
  });
  app.get('/v1/documents', session, apiLimit, async (req, res) => {
    const docs = await documents.list(req.user.id, parseCursor(req.query.cursor));
    const items = docs.slice(0, 30).map(metadata);
    const last = items.at(-1);
    res.json({items, next_cursor: docs.length > 30
      ? Buffer.from(`${last.created_at}|${last.id}`).toString('base64url') : null});
  });
  app.post('/v1/documents', session, uploadLimit, sizeGuard, gate, upload, async (req, res) => {
    const owner = req.user.id;
    const uploadId = (req.get('Idempotency-Key') ?? '').toLowerCase();
    const filename = typeof req.body?.filename === 'string' ? req.body.filename.trim() : '';
    if (!uuid.test(uploadId) || !/^[^/\\\p{Cc}]{1,120}$/u.test(filename) ||
        !/\.pdf$/i.test(filename)) throw invalid('Tên PDF hoặc mã tải lên không hợp lệ.');
    const bytes = req.file?.buffer;
    if (!bytes?.length || req.file.mimetype !== 'application/pdf' ||
        bytes.subarray(0, 5).toString('ascii') !== '%PDF-') {
      throw new ApiError(415, 'INVALID_PDF', 'Tệp PDF không hợp lệ.');
    }
    if (bytes.length > MAX_PDF) throw new ApiError(413, 'FILE_TOO_LARGE', 'PDF tối đa 20 MiB.');
    const pageCount = await countPages(bytes);
    if (!Number.isInteger(pageCount) || pageCount < 1 || pageCount > 500) {
      throw new ApiError(415, 'INVALID_PDF', 'PDF phải đọc được và có từ 1 đến 500 trang.');
    }
    const id = randomUUID(), sha = digest(bytes);
    const row = await documents.reserve({id, owner_id: owner, upload_id: uploadId, filename,
      page_count: pageCount, byte_size: bytes.length, sha256: sha, object_key: `${owner}/${id}.pdf`, status: 'pending'});
    if (row.sha256 !== sha || row.filename !== filename || row.byte_size !== bytes.length) {
      throw new ApiError(409, 'UPLOAD_KEY_CONFLICT', 'Mã tải lên đã dùng cho tệp khác.');
    }
    if (row.status === 'ready') return res.json(metadata(row));
    if (!await documents.put(row.object_key, bytes)) {
      const saved = await documents.file(row.object_key);
      if (saved.length !== bytes.length || digest(saved) !== sha) throw unavailable();
    }
    const result = await documents.ready(owner, row.id);
    res.status(row.id === id ? 201 : 200).json(metadata(result));
  });
  app.get('/v1/documents/:id/content', session, apiLimit, gate, async (req, res) => {
    if (!uuid.test(req.params.id)) throw invalid();
    const row = await documents.find(req.user.id, req.params.id);
    if (!row) throw missing();
    const bytes = await documents.file(row.object_key);
    if (bytes.length !== row.byte_size || digest(bytes) !== row.sha256) throw unavailable();
    res.attachment(row.filename).type('application/pdf').send(bytes);
  });
  app.delete('/v1/documents/:id', session, apiLimit, async (req, res) => {
    if (!uuid.test(req.params.id)) throw invalid();
    await documents.remove(req.user.id, req.params.id);
    res.status(204).end();
  });
  app.use((_req, _res, next) => next(missing()));
  app.use((error, req, res, _next) => {
    if (!(error instanceof ApiError)) {
      if (error.code === 'LIMIT_FILE_SIZE') error = new ApiError(413, 'FILE_TOO_LARGE', 'PDF tối đa 20 MiB.');
      else if (error instanceof multer.MulterError || error.status === 400) error = invalid();
      else if (error.status === 413) error = new ApiError(413, 'FILE_TOO_LARGE', 'Yêu cầu quá lớn.');
      else {
        console.error('request_failed', req.requestId, error.name);
        error = unavailable();
      }
    }
    res.status(error.status).json({error: {code: error.code, message: error.message, request_id: req.requestId}});
  });
  return app;
}
