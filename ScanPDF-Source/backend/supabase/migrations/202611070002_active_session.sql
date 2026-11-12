create or replace function public.scanpdf_session_active(p_session_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from auth.sessions
    where id = p_session_id and user_id = p_user_id
      and (not_after is null or not_after > now())
  );
$$;
revoke all on function public.scanpdf_session_active(uuid, uuid) from public, anon, authenticated;
grant execute on function public.scanpdf_session_active(uuid, uuid) to service_role;
