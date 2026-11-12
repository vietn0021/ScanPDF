create table if not exists public.cloud_documents (
  id uuid primary key,
  owner_id uuid not null references auth.users(id),
  upload_id uuid not null,
  filename text not null check (
    char_length(filename) between 1 and 120
    and strpos(filename, '/') = 0 and strpos(filename, chr(92)) = 0
    and filename !~ '[[:cntrl:]]' and filename ~* '[.]pdf$'
  ),
  page_count integer not null check (page_count between 1 and 500),
  byte_size integer not null check (byte_size between 1 and 20971520),
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  object_key text not null unique check (object_key = owner_id::text || '/' || id::text || '.pdf'),
  status text not null default 'pending' check (status in ('pending', 'ready')),
  created_at timestamptz not null default now(),
  unique (owner_id, upload_id)
);
create index if not exists scanpdf_ready_by_owner
  on public.cloud_documents (owner_id, created_at desc, id desc) where status = 'ready';

alter table public.cloud_documents enable row level security;
revoke all on table public.cloud_documents from public, anon, authenticated;
grant select, insert, update on table public.cloud_documents to service_role;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('scanpdf-documents', 'scanpdf-documents', false, 20971520, array['application/pdf'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Restrictive policy protects this bucket even if another bucket has broad policies.
drop policy if exists scanpdf_block_direct_client on storage.objects;
create policy scanpdf_block_direct_client on storage.objects as restrictive
  for all to anon, authenticated
  using (bucket_id <> 'scanpdf-documents')
  with check (bucket_id <> 'scanpdf-documents');
