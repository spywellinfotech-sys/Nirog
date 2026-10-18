-- Ambulance listings can carry a WhatsApp number so patients can send their location on WhatsApp after they call.
alter table public.ambulance_services add column whatsapp text check (whatsapp is null or whatsapp ~ '^[6-9][0-9]{9}$');

create or replace function public.admin_save_ambulance(p jsonb) returns public.ambulance_services
language plpgsql security definer set search_path = public, pg_temp as $$
declare i bigint := nullif(p->>'id','')::bigint; n text := trim(coalesce(p->>'name','')); ph text := trim(coalesce(p->>'phone',''));
  c text := nullif(trim(coalesce(p->>'city','')), ''); k text := coalesce(nullif(p->>'kind',''), 'private'); nt text := trim(coalesce(p->>'note',''));
  wa text := nullif(regexp_replace(coalesce(p->>'whatsapp', ''), '\s', '', 'g'), '');
  act boolean := coalesce((p->>'active')::boolean, true); r public.ambulance_services;
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  if char_length(n) < 3 or char_length(n) > 80 then raise exception 'invalid_name'; end if;
  if ph !~ '^\+?[0-9][0-9 -]{2,14}$' then raise exception 'invalid_phone'; end if;
  if wa is not null and wa !~ '^[6-9][0-9]{9}$' then raise exception 'invalid_whatsapp'; end if;
  if k not in ('govt','private') then raise exception 'invalid_kind'; end if;
  if c is not null and char_length(c) > 60 then raise exception 'invalid_city'; end if;
  if char_length(nt) > 120 then raise exception 'invalid_note'; end if;
  if i is null then
    insert into public.ambulance_services (name, phone, whatsapp, city, kind, note, active) values (n, ph, wa, c, k, nt, act) returning * into r;
  else
    update public.ambulance_services set name = n, phone = ph, whatsapp = wa, city = c, kind = k, note = nt, active = act where id = i returning * into r;
    if not found then raise exception 'not_found'; end if;
  end if;
  return r;
end $$;
revoke all on function public.admin_save_ambulance(jsonb) from public, anon;
grant execute on function public.admin_save_ambulance(jsonb) to authenticated;
