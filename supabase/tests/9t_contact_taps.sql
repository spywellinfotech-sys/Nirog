\set A1 '00000000-0000-0000-0000-0000000000a1'
\set ADM '00000000-0000-0000-0000-0000000000b1'
select t.login(:'ADM');
select (public.admin_save_ambulance('{"name":"Tap Ambulance","phone":"9123400099","kind":"private"}')).id as amb \gset
select t.root();
select t.login(:'A1');
select public.log_contact_tap('ambulance', :amb, 'call');
select public.log_contact_tap('ambulance', :amb, 'call');
select public.log_contact_tap('ambulance', :amb, 'whatsapp');
select public.log_contact_tap('ambulance', 999999, 'call');
select t.denied($$select public.log_contact_tap('doctor', 1, 'call')$$, 'invalid_input', 'only facility and ambulance taps are counted');
select t.denied($$select public.admin_contact_stats('ambulance')$$, 'admins_only', 'patients cannot read the tap counts');
select t.root();
select t.denied($$select public.log_contact_tap('ambulance', 1, 'call')$$, 'not_authenticated', 'an anonymous caller cannot log taps');
select t.login(:'ADM');
select public.admin_contact_stats('ambulance') -> (:amb)::text as s \gset
select t.ok((:'s'::jsonb ->> 'total')::int = 2 and (:'s'::jsonb ->> 'call')::int = 1 and (:'s'::jsonb ->> 'whatsapp')::int = 1, 'repeat taps within 10 minutes count once; unknown listings are ignored');
select t.root();
select t.login(:'ADM');
select t.denied($$select public.admin_save_ambulance('{"name":"Bad Wa Ambulance","phone":"9123400098","whatsapp":"12345"}')$$, 'invalid_whatsapp', 'a WhatsApp number must be a 10 digit mobile');
select (public.admin_save_ambulance('{"name":"Wa Ambulance","phone":"0202345678","whatsapp":"98765 43210"}')).whatsapp as wa \gset
select t.ok(:'wa' = '9876543210', 'the WhatsApp number is saved without spaces');
select t.root();
