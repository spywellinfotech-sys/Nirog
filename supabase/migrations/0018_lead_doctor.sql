-- A lead can name the doctor the patient wants (optional).
alter table public.leads add column if not exists doctor_id bigint references public.doctors(id) on delete set null;
