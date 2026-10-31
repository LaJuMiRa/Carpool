-- Realtime für Live-Status, privater Bucket für Schadenfotos.

alter publication supabase_realtime
  add table public.bookings, public.cars, public.damages, public.members;

-- Fotos liegen unter <family_id>/<datei>.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('damage-photos', 'damage-photos', false, 10485760,
        array['image/jpeg', 'image/png', 'image/heic'])
on conflict (id) do nothing;

create policy damage_photos_select on storage.objects for select to authenticated
  using (bucket_id = 'damage-photos'
         and (storage.foldername(name))[1] = (select private.my_family_id())::text);

create policy damage_photos_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'damage-photos'
              and (storage.foldername(name))[1] = (select private.my_family_id())::text);

create policy damage_photos_delete on storage.objects for delete to authenticated
  using (bucket_id = 'damage-photos' and owner_id = (select auth.uid())::text);
