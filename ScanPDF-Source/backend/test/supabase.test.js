import assert from 'node:assert/strict';
import {createHash, randomUUID} from 'node:crypto';
import {once} from 'node:events';
import {test} from 'node:test';
import {createClient} from '@supabase/supabase-js';
import {PDFDocument} from 'pdf-lib';
import {createApp} from '../src/app.js';
import {bucket, supabaseServices} from '../src/supabase.js';

test('Supabase development project: separate accounts, private PDF and session revocation', {
  skip: process.env.SCANPDF_RUN_INTEGRATION !== '1',
  timeout: 90_000,
}, async t => {
  const {
    SUPABASE_URL: url, SUPABASE_PUBLISHABLE_KEY: publishableKey, SUPABASE_SECRET_KEY: secretKey,
    SCANPDF_TEST_EMAIL_A: emailA, SCANPDF_TEST_PASSWORD_A: passwordA,
    SCANPDF_TEST_EMAIL_B: emailB, SCANPDF_TEST_PASSWORD_B: passwordB,
  } = process.env;
  assert.ok(url && publishableKey && secretKey && emailA && passwordA && emailB && passwordB,
    'Configure backend/.env with two confirmed development accounts.');
  assert.notEqual(emailA.toLowerCase(), emailB.toLowerCase());
  const api = createApp(supabaseServices({url, publishableKey, secretKey})).listen(0, '127.0.0.1');
  t.after(() => new Promise(resolve => api.close(resolve)));
  await once(api, 'listening');
  const base = 'http://127.0.0.1:' + api.address().port + '/v1';
  const call = (path, token, options = {}) => fetch(base + path, {
    ...options, headers: {...(token && {Authorization: 'Bearer ' + token}), ...options.headers},
  });
  const json = (path, body) => call(path, null, {
    method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body),
  });
  async function login(email, password) {
    const result = await json('/auth/login', {email, password});
    assert.equal(result.status, 200);
    return result.json();
  }
  const a = await login(emailA, passwordA);
  const a2 = await login(emailA, passwordA);
  const b = await login(emailB, passwordB);
  const refreshed = await json('/auth/refresh', {refresh_token: a2.refresh_token});
  assert.equal(refreshed.status, 200);
  const otherDeviceToken = (await refreshed.json()).access_token;

  const pdf = await PDFDocument.create();
  for (let page = 0; page < 3; page++) pdf.addPage();
  const original = await pdf.save();
  const key = randomUUID();
  const upload = (token, filename = 'ScanPDF test ' + key + '.pdf') => {
    const body = new FormData();
    body.set('filename', filename);
    body.set('file', new Blob([original], {type: 'application/pdf'}), 'scan.pdf');
    return call('/documents', token, {method: 'POST', headers: {'Idempotency-Key': key}, body});
  };
  const initial = await upload(a.access_token);
  assert.equal(initial.status, 201, await initial.clone().text());
  const doc = await initial.json();
  assert.equal(doc.page_count, 3);
  assert.equal(doc.sha256, createHash('sha256').update(original).digest('hex'));
  const duplicates = await Promise.all([upload(a.access_token), upload(otherDeviceToken)]);
  for (const result of duplicates) {
    assert.equal(result.status, 200);
    assert.equal((await result.json()).id, doc.id);
  }
  assert.equal((await upload(a.access_token, 'other.pdf')).status, 409);
  const listA = await (await call('/documents', otherDeviceToken)).json();
  const listB = await (await call('/documents', b.access_token)).json();
  assert.equal(listA.items.filter(item => item.id === doc.id).length, 1);
  assert.ok(!listB.items.some(item => item.id === doc.id));
  const path = '/documents/' + doc.id + '/content';
  const downloaded = await call(path, otherDeviceToken);
  assert.equal(downloaded.status, 200);
  assert.deepEqual(new Uint8Array(await downloaded.arrayBuffer()), original);
  assert.equal((await call(path, b.access_token)).status, 404);

  const ownerClient = createClient(url, publishableKey, {accessToken: async () => a.access_token});
  const direct = await ownerClient.storage.from(bucket).download(a.user.id + '/' + doc.id + '.pdf');
  assert.ok(direct.error);
  assert.equal((await call('/auth/logout', a.access_token, {method: 'POST'})).status, 204);
  assert.equal((await call('/documents', a.access_token)).status, 401);
  assert.equal((await upload(a.access_token)).status, 401);
  assert.equal((await call(path, a.access_token)).status, 401);
  assert.equal((await call(path, otherDeviceToken)).status, 200);
  assert.equal((await call('/auth/logout', otherDeviceToken, {method: 'POST'})).status, 204);
  assert.equal((await call('/auth/logout', b.access_token, {method: 'POST'})).status, 204);
});

test('Supabase development project: atomic quota and idempotency at capacity', {
  skip: process.env.SCANPDF_RUN_INTEGRATION !== '1',
  timeout: 90_000,
}, async t => {
  const {SUPABASE_URL: url, SUPABASE_PUBLISHABLE_KEY: publishableKey,
    SUPABASE_SECRET_KEY: secretKey} = process.env;
  assert.ok(url && publishableKey && secretKey, 'Configure an isolated development project.');
  const admin = createClient(url, secretKey, {auth: {persistSession: false, autoRefreshToken: false}});
  const originalCount = process.env.MAX_DOCUMENTS_PER_OWNER;
  const originalBytes = process.env.MAX_BYTES_PER_OWNER;
  process.env.MAX_DOCUMENTS_PER_OWNER = '1';
  process.env.MAX_BYTES_PER_OWNER = '209715200';
  let services;
  try {
    services = supabaseServices({url, publishableKey, secretKey});
  } finally {
    if (originalCount === undefined) delete process.env.MAX_DOCUMENTS_PER_OWNER;
    else process.env.MAX_DOCUMENTS_PER_OWNER = originalCount;
    if (originalBytes === undefined) delete process.env.MAX_BYTES_PER_OWNER;
    else process.env.MAX_BYTES_PER_OWNER = originalBytes;
  }
  const api = createApp(services, {maxHeavy: 2}).listen(0, '127.0.0.1');
  t.after(() => new Promise(resolve => api.close(resolve)));
  await once(api, 'listening');
  const endpoint = 'http://127.0.0.1:' + api.address().port + '/v1/documents';
  const pdf = await PDFDocument.create();
  pdf.addPage();
  const bytes = await pdf.save();
  pdf.addPage();
  const differentBytes = await pdf.save();

  for (let round = 0; round < 3; round++) {
    const email = `scanpdf-quota-${randomUUID()}@example.com`;
    const password = randomUUID();
    const account = await admin.auth.admin.createUser({email, password, email_confirm: true});
    assert.ifError(account.error);
    const owner = account.data.user.id;
    try {
      const {access_token} = await services.auth.login(email, password);
      const upload = (key, payload = bytes) => {
        const body = new FormData();
        body.set('filename', 'Quota test.pdf');
        body.set('file', new Blob([payload], {type: 'application/pdf'}), 'scan.pdf');
        return fetch(endpoint, {method: 'POST', headers: {
          Authorization: 'Bearer ' + access_token, 'Idempotency-Key': key,
        }, body});
      };
      const keys = [randomUUID(), randomUUID()];
      const results = await Promise.all(keys.map(key => upload(key)));
      const data = await Promise.all(results.map(result => result.json()));
      assert.deepEqual(results.map(result => result.status).sort(), [201, 413], JSON.stringify(data));
      const winner = results.findIndex(result => result.status === 201);
      assert.equal(data[1 - winner].error.code, 'QUOTA_EXCEEDED');
      const retry = await upload(keys[winner]);
      assert.equal(retry.status, 200);
      assert.deepEqual(await retry.json(), data[winner]);
      const conflict = await upload(keys[winner], differentBytes);
      assert.equal(conflict.status, 409);
      assert.equal((await conflict.json()).error.code, 'UPLOAD_KEY_CONFLICT');
    } finally {
      const listed = await admin.storage.from(bucket).list(owner);
      assert.ifError(listed.error);
      if (listed.data.length) {
        const removed = await admin.storage.from(bucket).remove(listed.data.map(file => `${owner}/${file.name}`));
        assert.ifError(removed.error);
      }
      const deleted = await admin.auth.admin.deleteUser(owner);
      assert.ifError(deleted.error);
    }
  }
});
