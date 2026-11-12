import {createClient} from '@supabase/supabase-js';
import {ApiError, missing, unauthorized, unavailable, uuid} from './errors.js';

export const bucket = 'scanpdf-documents';
export const publicFields = 'id,filename,page_count,byte_size,sha256,created_at';
const internalFields = publicFields + ',owner_id,upload_id,object_key,status';
const noSession = {auth: {persistSession: false, autoRefreshToken: false, detectSessionInUrl: false}};
function requireData({data, error}) {
  if (error) throw unavailable();
  return data;
}
function authResult({data, error}) {
  if (error) {
    if (error.code === 'email_not_confirmed') {
      throw new ApiError(403, 'EMAIL_NOT_CONFIRMED', 'Hãy xác nhận email trước khi đăng nhập.');
    }
    if (['AuthInvalidJwtError', 'AuthSessionMissingError'].includes(error.name)) throw unauthorized();
    if (error.status === 429) throw new ApiError(429, 'RATE_LIMITED', 'Quá nhiều yêu cầu. Vui lòng thử lại sau.');
    if (!error.status || error.status >= 500) throw unavailable();
    throw unauthorized();
  }
  return data;
}
function tokens(session) {
  if (!session || !session.user?.email_confirmed_at) throw unauthorized();
  return {
    user: {id: session.user.id, email: session.user.email},
    access_token: session.access_token,
    refresh_token: session.refresh_token,
    expires_at: session.expires_at,
  };
}

export function supabaseServices({url, publishableKey, secretKey, emailRedirect}) {
  const maxCount = Number(process.env.MAX_DOCUMENTS_PER_OWNER ?? 200);
  const maxBytes = Number(process.env.MAX_BYTES_PER_OWNER ?? 200 * 1024 * 1024);
  if (!Number.isSafeInteger(maxCount) || maxCount < 1 || maxCount > 2147483647 ||
      !Number.isSafeInteger(maxBytes) || maxBytes < 1) {
    throw new Error('Hạn mức tài liệu và dung lượng phải là số nguyên dương hợp lệ.');
  }
  const authClient = () => createClient(url, publishableKey, noSession);
  const verifier = authClient();
  const server = createClient(url, secretKey, noSession);
  const issuer = `${url.replace(/\/$/, '')}/auth/v1`;
  const table = () => server.from('cloud_documents');
  const files = server.storage.from(bucket);

  return {
    auth: {
      async register(email, password) {
        const result = await authClient().auth.signUp({
          email, password, options: emailRedirect ? {emailRedirectTo: emailRedirect} : {},
        });
        if (result.error?.code === 'user_already_exists' || result.error?.code === 'email_exists') return;
        if (result.error?.code === 'weak_password') {
          throw new ApiError(400, 'WEAK_PASSWORD', 'Mật khẩu chưa đáp ứng yêu cầu bảo mật.');
        }
        authResult(result);
      },
      async login(email, password) {
        return tokens(authResult(await authClient().auth.signInWithPassword({email, password})).session);
      },
      async refresh(refresh_token) {
        return tokens(authResult(await authClient().auth.refreshSession({refresh_token})).session);
      },
      async verify(token) {
        const {claims} = authResult(await verifier.auth.getClaims(token)) ?? {};
        if (!claims || claims.iss !== issuer || claims.aud !== 'authenticated' ||
            !uuid.test(claims.sub ?? '') || !uuid.test(claims.session_id ?? '') ||
            !(claims.exp > Date.now() / 1000)) throw unauthorized();
        const active = requireData(await server.rpc('scanpdf_session_active', {
          p_session_id: claims.session_id, p_user_id: claims.sub,
        }));
        if (active !== true) throw unauthorized();
        return {id: claims.sub, email: claims.email ?? ''};
      },
      async logout(token) {
        authResult(await server.auth.admin.signOut(token, 'local'));
      },
      async changePassword(token, user, current, password) {
        if (!user.email) throw unauthorized();
        // Supabase only checks current_password itself if that project setting is enabled.
        const check = await authClient().auth.signInWithPassword({email: user.email, password: current});
        if (check.error?.code === 'invalid_credentials') {
          throw new ApiError(400, 'PASSWORD_REJECTED', 'Mật khẩu hiện tại không đúng.');
        }
        const verified = tokens(authResult(check).session);
        authResult(await server.auth.admin.signOut(verified.access_token, 'local'));
        if (verified.user.id !== user.id) throw unauthorized();
        // GoTrue's user endpoint accepts the access token without importing or rotating the refresh token.
        const response = await fetch(`${issuer}/user`, {
          method: 'PUT',
          headers: {apikey: publishableKey, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json'},
          body: JSON.stringify({current_password: current, password}),
          signal: AbortSignal.timeout(10_000),
        }).catch(() => { throw unavailable(); });
        if (response.ok) {
          await response.body?.cancel();
          return;
        }
        const error = await response.json().catch(() => ({}));
        const code = error?.error_code ?? error?.code;
        if (code === 'reauthentication_needed') {
          throw new ApiError(403, 'REAUTHENTICATION_REQUIRED', 'Hãy đăng xuất, đăng nhập lại rồi đổi mật khẩu.');
        }
        if (response.status === 422 || response.status === 400 || code === 'invalid_credentials' || code === 'current_password_invalid') {
          throw new ApiError(400, 'PASSWORD_REJECTED', 'Kiểm tra mật khẩu hiện tại và chọn mật khẩu mới đáp ứng yêu cầu bảo mật.');
        }
        authResult({error: {status: response.status}});
      },
    },
    documents: {
      async reserve(row) {
        const result = await server.rpc('scanpdf_reserve_document', {
          p_row: row, p_max_count: maxCount, p_max_bytes: maxBytes,
        });
        if (result.error?.code === 'SPQ01') {
          throw new ApiError(413, 'QUOTA_EXCEEDED', 'Thư viện trực tuyến đã đạt hạn mức.');
        }
        return requireData(result);
      },
      async put(key, bytes) {
        const {error} = await files.upload(key, bytes, {contentType: 'application/pdf', upsert: false});
        if (!error) return true;
        if (['409', 'Duplicate', 'ResourceAlreadyExists', 'KeyAlreadyExists'].includes(String(error.statusCode ?? error.status)) ||
            ['Duplicate', 'ResourceAlreadyExists', 'KeyAlreadyExists'].includes(error.error)) return false;
        throw unavailable();
      },
      async file(key) {
        const blob = requireData(await files.download(key));
        if (!blob) throw unavailable();
        return Buffer.from(await blob.arrayBuffer());
      },
      async ready(owner, id) {
        return requireData(await table().update({status: 'ready'}).eq('owner_id', owner).eq('id', id)
          .select(publicFields).single());
      },
      async list(owner, cursor) {
        let q = table().select(publicFields).eq('owner_id', owner).eq('status', 'ready')
          .order('created_at', {ascending: false}).order('id', {ascending: false}).limit(31);
        if (cursor) q = q.or(`created_at.lt.${cursor.time},and(created_at.eq.${cursor.time},id.lt.${cursor.id})`);
        return requireData(await q);
      },
      async find(owner, id) {
        return requireData(await table().select(internalFields)
          .eq('owner_id', owner).eq('id', id).eq('status', 'ready').maybeSingle());
      },
      async remove(owner, id) {
        const row = await this.find(owner, id);
        if (!row) throw missing();
        const {error} = await files.remove([row.object_key]);
        // Storage may return an empty success for a missing object.
        if (error && !['404', 'NoSuchKey', 'ResourceNotFound'].some(code =>
          [error.statusCode, error.status, error.error, error.code].some(value => String(value) === code))) {
          throw unavailable();
        }
        requireData(await table().delete().eq('owner_id', owner).eq('id', id));
      },
    },
  };
}
