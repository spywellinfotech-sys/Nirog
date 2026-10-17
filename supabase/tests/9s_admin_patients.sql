\set A1 '00000000-0000-0000-0000-0000000000a1'
\set ADM '00000000-0000-0000-0000-0000000000b1'
select t.login(:'A1');
select t.denied($$select public.admin_patients('', 10, 0)$$, 'admins_only', 'patients cannot list patients');
select t.login(:'ADM');
select public.admin_patients('', 100, 0) as l \gset
select t.ok((:'l'::jsonb ->> 'total')::int >= 1 and jsonb_array_length(:'l'::jsonb -> 'rows') >= 1, 'admin sees patients');
select t.ok(not exists (select 1 from jsonb_array_elements(:'l'::jsonb -> 'rows') r where r ->> 'id' in (select id::text from public.profiles where role <> 'patient')), 'only patients are listed');
select public.admin_patients('zzzz-no-such-name', 10, 0) as e \gset
select t.ok((:'e'::jsonb ->> 'total')::int = 0, 'search filters by name');
select t.root();
