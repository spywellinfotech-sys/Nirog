-- Admin may overwrite files in broadcast-media (needed for upsert uploads)
drop policy if exists bc_media_update on storage.objects;
create policy bc_media_update on storage.objects for update to authenticated
  using (bucket_id = 'broadcast-media' and public.is_admin())
  with check (bucket_id = 'broadcast-media' and public.is_admin());
