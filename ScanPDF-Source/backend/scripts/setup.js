import {readFile, readdir} from 'node:fs/promises';
import {Client} from 'pg';

if (!process.env.SUPABASE_DB_URL) throw new Error('Điền SUPABASE_DB_URL trong backend/.env trước khi chạy setup.');
const folder = new URL('../supabase/migrations/', import.meta.url);
const client = new Client({connectionString: process.env.SUPABASE_DB_URL, connectionTimeoutMillis: 10000});
let connected = false;
try {
  await client.connect();
  connected = true;
  await client.query('begin');
  for (const file of (await readdir(folder)).filter(name => name.endsWith('.sql')).sort()) {
    await client.query(await readFile(new URL(file, folder), 'utf8'));
  }
  await client.query('commit');
  console.log('ScanPDF: bảng, bucket riêng tư và hàm kiểm tra phiên đã sẵn sàng.');
} catch (error) {
  if (connected) await client.query('rollback').catch(() => {});
  console.error('Không thể áp dụng migration. Kiểm tra SUPABASE_DB_URL và quyền quản trị. Mã:', error.code ?? error.name);
  process.exitCode = 1;
} finally {
  await client.end().catch(() => {});
}
