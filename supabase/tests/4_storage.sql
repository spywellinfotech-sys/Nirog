\set A '00000000-0000-0000-0000-0000000000a1'
\set B '00000000-0000-0000-0000-0000000000a2'
\set ADM '00000000-0000-0000-0000-0000000000b1'
select t.login(:'A');
insert into storage.objects (bucket_id, name) values ('verification-docs', '00000000-0000-0000-0000-0000000000a1/cert.pdf');
select t.denied($$insert into storage.objects (bucket_id, name) values ('verification-docs', '00000000-0000-0000-0000-0000000000a2/cert.pdf')$$, 'row-level security', 'cannot upload into another user''s folder');
select t.root();
select t.login(:'B');
select t.ok((select count(*) from storage.objects where bucket_id = 'verification-docs') = 0, 'other users cannot read private documents');
select t.root();
select t.login(:'ADM');
select t.ok((select count(*) from storage.objects where bucket_id = 'verification-docs') = 1, 'admin can read private documents');
select t.root();
select t.anon();
select t.ok((select count(*) from storage.objects where bucket_id = 'verification-docs') = 0, 'anon cannot read private documents');
select t.root();
