-- A lead can record the patient's city.
alter table public.leads add column if not exists city text not null default '' check (char_length(city) <= 60);
