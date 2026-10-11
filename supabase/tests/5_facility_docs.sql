\set A '00000000-0000-0000-0000-0000000000a1'
\set F1 '00000000-0000-0000-0000-0000000000f1'
\set ADM '00000000-0000-0000-0000-0000000000b1'

select t.login(:'F1');
insert into public.facility_documents (facility_id, kind, storage_path, file_name) values (1, 'lic', '00000000-0000-0000-0000-0000000000f1/lic.pdf', 'licence.pdf');
select t.ok((select count(*) from public.facility_documents) = 1, 'facility owner can add and read its documents');
select t.root();
select t.login(:'A');
select t.denied($$insert into public.facility_documents (facility_id, kind, storage_path) values (1, 'lic', 'x/y.pdf')$$, 'row-level security', 'another user cannot add documents to a facility');
select t.ok((select count(*) from public.facility_documents) = 0, 'another user cannot read facility documents');
select t.root();
select t.login(:'ADM');
select t.ok((select count(*) from public.facility_documents) = 1, 'admin can read facility documents');
select t.root();
select t.anon();
select t.denied($$select * from public.facility_documents$$, 'permission denied', 'public cannot read facility documents');
select t.root();
