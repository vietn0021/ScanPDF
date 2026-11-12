create or replace function public.scanpdf_reserve_document(
  p_row jsonb, p_max_count int, p_max_bytes bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  candidate public.cloud_documents;
  existing public.cloud_documents;
  document_count bigint;
  total_bytes bigint;
begin
  candidate := pg_catalog.jsonb_populate_record(null::public.cloud_documents, p_row);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(candidate.owner_id::text, 0));

  select * into existing from public.cloud_documents
    where owner_id = candidate.owner_id and upload_id = candidate.upload_id;
  if found then
    return pg_catalog.to_jsonb(existing);
  end if;

  select count(*), coalesce(sum(byte_size), 0) into document_count, total_bytes
    from public.cloud_documents where owner_id = candidate.owner_id;
  if document_count >= p_max_count or total_bytes + candidate.byte_size > p_max_bytes then
    raise exception 'ScanPDF quota exceeded' using errcode = 'SPQ01';
  end if;

  insert into public.cloud_documents
    (id, owner_id, upload_id, filename, page_count, byte_size, sha256, object_key, status)
  values
    (candidate.id, candidate.owner_id, candidate.upload_id, candidate.filename,
     candidate.page_count, candidate.byte_size, candidate.sha256, candidate.object_key, 'pending')
  returning * into existing;
  return pg_catalog.to_jsonb(existing);
end;
$$;

revoke all on function public.scanpdf_reserve_document(jsonb, int, bigint) from public, anon, authenticated;
grant execute on function public.scanpdf_reserve_document(jsonb, int, bigint) to service_role;
grant delete on table public.cloud_documents to service_role;
