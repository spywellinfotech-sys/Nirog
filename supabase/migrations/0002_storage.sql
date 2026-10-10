-- Storage buckets and policies. Requires Supabase's `storage` schema (present on every Supabase project).
--   doctor-media       public read  : profile photos and clinic gallery (shown to patients)
--   verification-docs  private      : registration certificates and ID (owner + admin only)
-- Object paths must start with the uploader's user id:  <uid>/<anything>
-- Limits: 5 MB per file; images for media, images or PDF for documents.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('doctor-media', 'doctor-media', true, 5242880, array['image/jpeg','image/png','image/webp']),
  ('verification-docs', 'verification-docs', false, 5242880, array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy media_read_public on storage.objects for select to anon, authenticated
  using (bucket_id = 'doctor-media');
create policy media_write_own on storage.objects for insert to authenticated
  with check (bucket_id = 'doctor-media' and (storage.foldername(name))[1] = auth.uid()::text);
create policy media_update_own on storage.objects for update to authenticated
  using (bucket_id = 'doctor-media' and (storage.foldername(name))[1] = auth.uid()::text);
create policy media_delete_own on storage.objects for delete to authenticated
  using (bucket_id = 'doctor-media' and (storage.foldername(name))[1] = auth.uid()::text);

create policy verif_read_own_or_admin on storage.objects for select to authenticated
  using (bucket_id = 'verification-docs' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));
create policy verif_write_own on storage.objects for insert to authenticated
  with check (bucket_id = 'verification-docs' and (storage.foldername(name))[1] = auth.uid()::text);
create policy verif_delete_own on storage.objects for delete to authenticated
  using (bucket_id = 'verification-docs' and (storage.foldername(name))[1] = auth.uid()::text);
