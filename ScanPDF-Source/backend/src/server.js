import {createApp} from './app.js';
import {supabaseServices} from './supabase.js';

const {SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, SUPABASE_SECRET_KEY, SUPABASE_EMAIL_REDIRECT_URL,
  HOST = '127.0.0.1', PORT = '3000'} = process.env;
if (!SUPABASE_URL || !SUPABASE_PUBLISHABLE_KEY || !SUPABASE_SECRET_KEY) {
  throw new Error('Điền SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY và SUPABASE_SECRET_KEY trong backend/.env.');
}
const url = new URL(SUPABASE_URL);
if (url.protocol !== 'https:' && !(url.protocol === 'http:' && ['localhost', '127.0.0.1'].includes(url.hostname))) {
  throw new Error('SUPABASE_URL phải dùng HTTPS hoặc HTTP cục bộ.');
}
if (!/^\d+$/.test(PORT) || Number(PORT) < 1 || Number(PORT) > 65535) throw new Error('PORT không hợp lệ.');
const app = createApp(supabaseServices({
  url: url.origin, publishableKey: SUPABASE_PUBLISHABLE_KEY,
  secretKey: SUPABASE_SECRET_KEY, emailRedirect: SUPABASE_EMAIL_REDIRECT_URL,
}));
app.listen(Number(PORT), HOST, () => console.log(`ScanPDF API: http://${HOST}:${PORT}/v1`));
