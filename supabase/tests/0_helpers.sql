create schema t;
grant usage on schema t to public;
create table t.results (name text, passed boolean);
grant all on t.results to public;

create function t.login(u uuid) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', u::text, false); execute 'set role authenticated'; end $$;
create function t.anon() returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', '', false); execute 'set role anon'; end $$;
create function t.root() returns void language plpgsql as $$
begin execute 'reset role'; perform set_config('request.jwt.claim.sub', '', false); end $$;

create function t.ok(cond boolean, name text) returns void language plpgsql as $$
begin
  insert into t.results values (name, coalesce(cond, false));
  raise notice '% %', case when coalesce(cond,false) then 'PASS' else 'FAIL' end, name;
  if not coalesce(cond, false) then raise exception 'TEST FAILED: %', name; end if;
end $$;

-- Runs statement text and requires an error whose message contains p_msg.
create function t.denied(stmt text, p_msg text, name text) returns void language plpgsql as $$
declare m text;
begin
  begin execute stmt; m := null;
  exception when others then m := sqlerrm; end;
  perform t.ok(m is not null and position(p_msg in m) > 0, name || ' [' || coalesce(m, 'no error') || ']');
end $$;
grant execute on all functions in schema t to public;

-- Fixed users
insert into auth.users (id, email, phone) values
 ('00000000-0000-0000-0000-0000000000a1', null, '919000000001'),   -- patient Asha
 ('00000000-0000-0000-0000-0000000000a2', null, '919000000002'),   -- patient Bala
 ('00000000-0000-0000-0000-0000000000d1', 'doc1@example.test', null),
 ('00000000-0000-0000-0000-0000000000d2', 'doc2@example.test', null),
 ('00000000-0000-0000-0000-0000000000f1', 'lab1@example.test', null),
 ('00000000-0000-0000-0000-0000000000b1', 'admin@example.test', null),
 ('00000000-0000-0000-0000-0000000000c1', 'sales@example.test', null);
