\set U1 '00000000-0000-0000-0000-0000000c0091'
\set U2 '00000000-0000-0000-0000-0000000c0092'
insert into auth.users (id, email) values (:'U1', 'dup1@example.com'), (:'U2', 'dup2@example.com');

select t.login(:'U1');
select public.register_doctor('{"phone":"9876511111","name":"Dr. Dup One","spec":"Cardiologist","fee_inr":900,"city":"Delhi","address":"5 Heart Lane","council":"DMC","reg_no":"DMC-91","reg_year":2001,"days":[1,2],"sessions":[{"s":600,"e":720}],"step":20}'::jsonb);
select t.ok((select phone from public.profiles where id = :'U1') = '+919876511111', 'doctor registration stores the mobile number on the profile');
select t.denied($$select public.register_doctor('{"phone":"9876522222","name":"Dr. Dup One Again","spec":"Cardiologist","fee_inr":900,"city":"Delhi","address":"x","council":"DMC","reg_no":"DMC-92","reg_year":2001,"days":[1],"sessions":[{"s":600,"e":720}]}'::jsonb)$$, 'already_registered', 'the same account cannot register twice');
select t.root();

select t.login(:'U2');
select t.denied($$select public.register_doctor('{"phone":"9876511111","name":"Dr. Dup Two","spec":"Cardiologist","fee_inr":900,"city":"Delhi","address":"x","council":"DMC","reg_no":"DMC-93","reg_year":2001,"days":[1],"sessions":[{"s":600,"e":720}]}'::jsonb)$$, 'phone_in_use', 'a mobile number used by one doctor cannot register another doctor');
select t.denied($$select public.register_facility('{"contact_phone":"9876511111","kind":"lab","name":"Dup Lab","city":"Delhi","address":"7 Lab Road","services":[]}'::jsonb)$$, 'phone_in_use', 'a doctor''s mobile number cannot be reused for a facility');
select t.denied($$select public.register_doctor('{"phone":"12345","name":"Dr. Bad Phone","spec":"Cardiologist","fee_inr":900,"city":"Delhi","address":"x","council":"DMC","reg_no":"DMC-94","reg_year":2001,"days":[1],"sessions":[{"s":600,"e":720}]}'::jsonb)$$, 'invalid_phone', 'a malformed mobile number is rejected');
select t.ok((select role from public.profiles where id = :'U2') = 'patient', 'rejected registrations leave the account untouched');
select public.register_facility('{"contact_phone":"9876533333","kind":"lab","name":"Unique Lab","city":"Delhi","address":"7 Lab Road","services":[]}'::jsonb);
select t.ok((select role from public.profiles where id = :'U2') = 'facility', 'a different mobile number registers fine');
select t.root();
