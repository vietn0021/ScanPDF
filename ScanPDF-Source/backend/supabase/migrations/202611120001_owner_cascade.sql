alter table public.cloud_documents
  drop constraint cloud_documents_owner_id_fkey,
  add constraint cloud_documents_owner_id_fkey
    foreign key (owner_id) references auth.users(id) on delete cascade;
