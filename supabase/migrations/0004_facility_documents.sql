-- Files a lab, centre or hospital uploads for verification (licence, ID, accreditation, photos).
-- Same idea as doctor_documents: the owner adds rows, the owner and admins read them.
create table public.facility_documents (
  id            bigint generated always as identity primary key,
  facility_id   bigint not null references public.facilities(id) on delete cascade,
  kind          text not null check (kind in ('lic','id','acc','photo')),
  storage_path  text not null,
  file_name     text not null default '',
  created_at    timestamptz not null default now()
);
create index facility_documents_idx on public.facility_documents (facility_id);
alter table public.facility_documents enable row level security;
create policy facdocs_read on public.facility_documents for select
  using (facility_id = public.my_facility_id() or public.is_admin());
create policy facdocs_insert on public.facility_documents for insert
  with check (facility_id = public.my_facility_id());
grant select, insert on public.facility_documents to authenticated;
