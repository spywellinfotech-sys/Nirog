\set GP '00000000-0000-0000-0000-0000000c0601'
\set A1 '00000000-0000-0000-0000-0000000000a1'
select t.login(:'GP');
select public.set_my_mobile('9876500999');
select t.root();
select t.ok((select phone from public.profiles where id = :'GP') = '+919876500999', 'a patient can add their mobile number');
select t.login(:'GP');
select t.denied($$select public.set_my_mobile('12345')$$, 'invalid_phone', 'a bad number is refused');
select t.root();
select t.login(:'A1');
select t.denied($$select public.set_my_mobile('9876500999')$$, 'phone_in_use', 'a number used by another account is refused');
select t.root();
select t.denied($$select public.set_my_mobile('9876500111')$$, 'not_authenticated', 'anonymous callers are refused');
