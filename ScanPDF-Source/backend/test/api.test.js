import assert from 'node:assert/strict';
import {createHash, randomUUID} from 'node:crypto';
import {once} from 'node:events';
import {request as httpRequest} from 'node:http';
import {test} from 'node:test';
import {PDFDocument} from 'pdf-lib';
import {createApp, MAX_PDF} from '../src/app.js';
import {ApiError, missing, unauthorized, unavailable} from '../src/errors.js';

async function fixture(t, {maxHeavy, quota = Infinity} = {}) {
  const a = {id: randomUUID(), email: 'a@example.com'};
  const b = {id: randomUUID(), email: 'b@example.com'};
  const rows = new Map(), files = new Map();
  const sessions = new Map([['alice', a], ['alice2', a], ['bob', b]]);
  const state = {failReady: false, failVerify: false};
  const lookup = (owner, id) => [...rows.values()].find(r => r.id === id && r.owner_id === owner);
  const auth = {
    async register() {},
    async changePassword(token, user, current, password) {
      state.passwordChange = {token, user, current, password};
    },
    async login(email, password) {
      if (email !== a.email || password !== 'Example123') throw unauthorized();
      return {user: a, access_token: 'alice', refresh_token: 'refresh', expires_at: 100};
    },
    async refresh(token) {
      if (token !== 'refresh') throw unauthorized();
      return {user: a, access_token: 'alice2', refresh_token: 'rotated', expires_at: 200};
    },
    async verify(token) {
      if (state.failVerify) throw unavailable();
      if (!sessions.has(token)) throw unauthorized();
      return sessions.get(token);
    },
    async logout(token) { sessions.delete(token); },
  };
  const documents = {
    async reserve(row) {
      const key = row.owner_id + row.upload_id;
      if (!rows.has(key) && [...rows.values()].filter(r => r.owner_id === row.owner_id).length >= quota) {
        throw new ApiError(413, 'QUOTA_EXCEEDED', 'Quota exceeded');
      }
      if (!rows.has(key)) rows.set(key, {...row, created_at: new Date().toISOString()});
      return rows.get(key);
    },
    async put(key, bytes) {
      if (files.has(key)) return false;
      files.set(key, bytes);
      return true;
    },
    async file(key) {
      await state.beforeFile?.();
      return files.get(key);
    },
    async ready(owner, id) {
      if (state.failReady) throw unavailable();
      const row = lookup(owner, id);
      row.status = 'ready';
      return row;
    },
    async list(owner, cursor) {
      return [...rows.values()].filter(r => r.owner_id === owner && r.status === 'ready')
        .filter(r => !cursor || r.created_at < cursor.time ||
          (r.created_at === cursor.time && r.id < cursor.id))
        .sort((a, b) => b.created_at.localeCompare(a.created_at) || b.id.localeCompare(a.id))
        .slice(0, 31);
    },
    async find(owner, id) {
      const row = lookup(owner, id);
      return row?.status === 'ready' ? row : null;
    },
    async remove(owner, id) {
      const row = await this.find(owner, id);
      if (!row) throw missing();
      state.storageDeletes = (state.storageDeletes ?? 0) + 1;
      files.delete(row.object_key);
      if (state.failDeleteRow) throw unavailable();
      rows.delete(row.owner_id + row.upload_id);
    },
  };
  const server = createApp({auth, documents}, {maxHeavy}).listen(0, '127.0.0.1');
  t.after(() => new Promise(resolve => server.close(resolve)));
  await once(server, 'listening');
  const base = 'http://127.0.0.1:' + server.address().port + '/v1';
  const request = (path, token, options = {}) => fetch(base + path, {
    ...options, headers: {...(token && {Authorization: 'Bearer ' + token}), ...options.headers},
  });
  const post = (path, body, token) => request(path, token, {
    method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body),
  });
  const pdf = await PDFDocument.create();
  pdf.addPage();
  pdf.addPage();
  const bytes = Buffer.from(await pdf.save());
  const upload = (token, key, payload = bytes, filename = 'Giấy tờ.pdf') => {
    const body = new FormData();
    body.set('filename', filename);
    body.set('file', new Blob([payload], {type: 'application/pdf'}), 'scan.pdf');
    return request('/documents', token, {method: 'POST', headers: {'Idempotency-Key': key}, body});
  };
  return {a, b, base, bytes, files, rows, request, post, upload, state};
}

test('rejects missing length and oversized multipart before parsing', async t => {
  const {base} = await fixture(t);
  for (const headers of [{'Transfer-Encoding': 'chunked'}, {'Content-Length': MAX_PDF + 65537}]) {
    const response = await new Promise((resolve, reject) => {
      const req = httpRequest(base + '/documents', {method: 'POST', headers: {
        Authorization: 'Bearer alice', 'Content-Type': 'multipart/form-data', Connection: 'close', ...headers,
      }}, resolve);
      req.on('error', reject);
      req.end();
    });
    assert.equal(response.statusCode, 413);
    let body = '';
    for await (const chunk of response) body += chunk;
    assert.equal(JSON.parse(body).error.code, 'FILE_TOO_LARGE');
  }
});

test('heavy gate is shared and releases on response and disconnect', async t => {
  const {base, upload, request, state} = await fixture(t, {maxHeavy: 1});
  const doc = await (await upload('alice', randomUUID())).json();
  const path = '/documents/' + doc.id + '/content';
  for (const disconnect of [false, true]) {
    const entered = Promise.withResolvers(), proceed = Promise.withResolvers();
    state.beforeFile = () => { entered.resolve(); return proceed.promise; };
    t.after(proceed.resolve);
    const req = httpRequest(base + path, {headers: {Authorization: 'Bearer alice'}});
    const closed = new Promise(resolve => req.on('close', resolve));
    req.on('error', () => {});
    const response = new Promise(resolve => req.on('response', resolve));
    req.end();
    await entered.promise;
    const busy = await upload('alice', randomUUID());
    assert.equal(busy.status, 503);
    assert.equal((await busy.json()).error.code, 'BUSY');
    if (disconnect) {
      req.destroy();
      await closed;
    } else {
      proceed.resolve();
      assert.equal((await response).statusCode, 200);
      (await response).resume();
      await closed;
    }
    state.beforeFile = null;
    try {
      await assert.doesNotReject(async () => {
        for (let attempt = 0; attempt < 10; attempt++) {
          const next = await request(path, 'alice');
          await next.arrayBuffer();
          if (next.status === 200) return;
          await new Promise(resolve => setTimeout(resolve, 10));
        }
        assert.fail('slot was not returned');
      });
    } finally {
      proceed.resolve();
    }
  }
});

test('read routes share a per-owner rate limit', async t => {
  const {request} = await fixture(t);
  for (let i = 0; i < 120; i++) {
    const path = ['/auth/me', '/documents', '/documents/' + randomUUID() + '/content'][i % 3];
    const result = await request(path, 'alice');
    assert.equal(result.status, i % 3 === 2 ? 404 : 200);
    await result.text();
  }
  for (const path of ['/auth/me', '/documents', '/documents/' + randomUUID() + '/content']) {
    assert.equal((await request(path, 'alice2')).status, 429);
  }
  assert.equal((await request('/auth/me', 'bob')).status, 200);
});

test('quota rejects new uploads but permits identical retries', async t => {
  const {upload, bytes} = await fixture(t, {quota: 1});
  const key = randomUUID();
  const initial = await upload('alice', key);
  assert.equal(initial.status, 201);
  const full = await upload('alice', randomUUID());
  assert.equal(full.status, 413);
  assert.equal((await full.json()).error.code, 'QUOTA_EXCEEDED');
  const retry = await upload('alice', key);
  assert.equal(retry.status, 200);
  assert.deepEqual(await retry.json(), await initial.json());
  assert.equal((await upload('alice', key, bytes, 'Other.pdf')).status, 409);
});

test('delete is owner-only and retries after Storage removal', async t => {
  const {upload, request, files, rows, state} = await fixture(t);
  const doc = await (await upload('alice', randomUUID())).json();
  const remove = (id, token = 'alice') => request('/documents/' + id, token, {method: 'DELETE'});
  assert.equal((await remove('invalid')).status, 400);
  assert.equal((await remove(doc.id, 'bob')).status, 404);
  assert.equal(state.storageDeletes, undefined);
  state.failDeleteRow = true;
  assert.equal((await remove(doc.id)).status, 503);
  assert.equal(files.size, 0);
  assert.equal(rows.size, 1);
  state.failDeleteRow = false;
  assert.equal((await remove(doc.id)).status, 204);
  assert.equal(rows.size, 0);
  assert.equal((await remove(doc.id)).status, 404);
  const second = await (await upload('alice', randomUUID())).json();
  files.clear();
  assert.equal((await remove(second.id)).status, 204);
  assert.equal(rows.size, 0);
});

test('auth validates inputs, refreshes, rejects revoked tokens and reports unavailable dependencies', async t => {
  const {a, post, request, state, upload} = await fixture(t);
  assert.equal((await post('/auth/register', {email: 'A@example.com', password: 'Example123!'})).status, 202);
  assert.equal((await post('/auth/register', {email: 'A@example.com', password: 'Example123'})).status, 400);
  assert.equal((await post('/auth/register', {email: 'A@example.com', password: 'short'})).status, 400);
  assert.equal((await post('/auth/login', {email: a.email, password: 'wrong'})).status, 401);
  const login = await post('/auth/login', {email: a.email, password: 'Example123'});
  assert.equal((await login.json()).access_token, 'alice');
  assert.equal((await (await post('/auth/refresh', {refresh_token: 'refresh'})).json()).refresh_token, 'rotated');
  assert.equal((await post('/auth/refresh', {refresh_token: 'expired'})).status, 401);
  assert.equal((await request('/auth/me')).status, 401);
  assert.deepEqual(await (await request('/auth/me', 'alice')).json(), {user: a});
  state.failVerify = true;
  assert.equal((await request('/auth/me', 'alice')).status, 503);
  state.failVerify = false;
  assert.equal((await request('/auth/logout', 'alice', {method: 'POST'})).status, 204);
  assert.equal((await request('/documents', 'alice')).status, 401);
  assert.equal((await upload('alice', randomUUID())).status, 401);
  assert.equal((await request('/documents/' + randomUUID() + '/content', 'alice')).status, 401);
  assert.equal((await request('/auth/me', 'alice2')).status, 200);
});

test('password change requires a session and validates both passwords', async t => {
  const {a, post, state} = await fixture(t);
  const data = {current_password: 'Example123', new_password: 'NewExample123!'};
  assert.equal((await post('/auth/password', data)).status, 401);
  assert.equal((await post('/auth/password', {...data, new_password: 'weak'}, 'alice')).status, 400);
  assert.equal((await post('/auth/password', {...data, current_password: data.new_password}, 'alice')).status, 400);
  assert.equal(state.passwordChange, undefined);
  assert.equal((await post('/auth/password', data, 'alice')).status, 204);
  assert.deepEqual(state.passwordChange, {token: 'alice', user: a, current: data.current_password, password: data.new_password});
});

test('a PDF belongs only to its owner and downloads with the original bytes', async t => {
  const {bytes, upload, request, files} = await fixture(t);
  const response = await upload('alice', randomUUID());
  assert.equal(response.status, 201);
  const doc = await response.json();
  assert.equal(doc.page_count, 2);
  assert.equal(doc.sha256, createHash('sha256').update(bytes).digest('hex'));
  assert.deepEqual(Object.keys(doc).sort(), ['byte_size', 'created_at', 'filename', 'id', 'page_count', 'sha256']);
  assert.deepEqual((await (await request('/documents', 'alice2')).json()).items, [doc]);
  assert.deepEqual((await (await request('/documents', 'bob')).json()).items, []);
  assert.equal((await request('/documents/' + doc.id + '/content', 'bob')).status, 404);
  const file = await request('/documents/' + doc.id + '/content', 'alice2');
  assert.equal(file.headers.get('content-type'), 'application/pdf');
  assert.match(file.headers.get('cache-control'), /no-store/);
  assert.deepEqual(Buffer.from(await file.arrayBuffer()), bytes);
  files.set([...files.keys()][0], Buffer.from('corrupt'));
  assert.equal((await request('/documents/' + doc.id + '/content', 'alice2')).status, 503);
});

test('same upload key recovers a pending object and concurrent retries produce a single document', async t => {
  const {upload, request, bytes, files, rows, state} = await fixture(t);
  const key = randomUUID();
  state.failReady = true;
  assert.equal((await upload('alice', key)).status, 503);
  assert.deepEqual((await (await request('/documents', 'alice')).json()).items, []);
  state.failReady = false;
  const retries = await Promise.all([upload('alice', key), upload('alice2', key)]);
  assert.deepEqual(retries.map(response => response.status), [200, 200]);
  const [first, second] = await Promise.all(retries.map(response => response.json()));
  assert.equal(first.id, second.id);
  assert.equal((await upload('alice', key, bytes, 'Tên khác.pdf')).status, 409);
  assert.equal(files.size, 1);
  assert.equal(rows.size, 1);
});

test('checks PDF content, filename and the exact 20 MiB upload limit', async t => {
  const {bytes, upload} = await fixture(t);
  const padded = Buffer.alloc(MAX_PDF, 32);
  bytes.copy(padded, padded.length - bytes.length);
  // Pad before the PDF, after a valid comment header, while preserving its original cross-reference offsets.
  const startxref = bytes.lastIndexOf(Buffer.from('startxref'));
  assert.ok(startxref > 0);
  bytes.subarray(0, startxref).copy(padded);
  bytes.subarray(startxref).copy(padded, padded.length - (bytes.length - startxref));
  const exact = await upload('alice', randomUUID(), padded);
  assert.equal(exact.status, 201, await exact.text());
  assert.equal((await upload('alice', randomUUID(), Buffer.concat([padded, Buffer.from(' ')]))).status, 413);
  assert.equal((await upload('alice', randomUUID(), Buffer.from('%PDF-1.7\ninvalid'))).status, 415);
  assert.equal((await upload('alice', randomUUID(), bytes, '../scan.pdf')).status, 400);
});

test('paginates ready documents with a stable timestamp and UUID cursor', async t => {
  const {a, rows, request} = await fixture(t);
  for (let i = 0; i < 35; i++) {
    const id = randomUUID();
    rows.set(id, {id, owner_id: a.id, status: 'ready', created_at: '2026-11-07T12:00:00.123456+00:00'});
  }
  const first = await (await request('/documents', 'alice')).json();
  assert.equal(first.items.length, 30);
  const second = await (await request('/documents?cursor=' + first.next_cursor, 'alice')).json();
  assert.equal(second.items.length, 5);
  assert.equal(second.next_cursor, null);
  assert.equal(new Set([...first.items, ...second.items].map(item => item.id)).size, 35);
  assert.equal((await request('/documents?cursor=malformed', 'alice')).status, 400);
});
