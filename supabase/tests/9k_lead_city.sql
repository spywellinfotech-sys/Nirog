select t.ok(exists(select 1 from information_schema.columns where table_schema='public' and table_name='leads' and column_name='city'), 'leads can record a city');
