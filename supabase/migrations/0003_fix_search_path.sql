-- Linter fix: pin search_path on the two helper functions that did not set it.
alter function public.new_ref(text) set search_path = public, pg_temp;
alter function public.clinic_now() set search_path = public, pg_temp;
