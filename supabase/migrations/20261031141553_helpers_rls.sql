-- Hilfsfunktionen, Trigger, Row Level Security, Rechte

-- Hilfsfunktionen -----------------------------------------------------------
create function private.my_member_id() returns uuid
language sql stable security definer set search_path = ''
as $$ select id from public.members where user_id = auth.uid() $$;

create function private.my_family_id() returns uuid
language sql stable security definer set search_path = ''
as $$ select family_id from public.members where user_id = auth.uid() $$;

create function private.is_admin() returns boolean
language sql stable security definer set search_path = ''
as $$ select coalesce((select role = 'admin' from public.members where user_id = auth.uid()), false) $$;

-- Wirft not_a_member, wenn der Aufrufer keiner Familie angehört.
create function private.require_member() returns public.members
language plpgsql stable security definer set search_path = ''
as $$
declare
  m public.members;
begin
  select * into m from public.members where user_id = auth.uid();
  if not found then
    raise exception 'not_a_member' using errcode = 'P0001';
  end if;
  return m;
end $$;

-- Wirft car_not_found, wenn das Auto nicht zur Familie gehört oder archiviert ist.
create function private.require_car(p_car_id uuid, p_family_id uuid) returns public.cars
language plpgsql stable security definer set search_path = ''
as $$
declare
  c public.cars;
begin
  select * into c from public.cars
   where id = p_car_id and family_id = p_family_id and not archived;
  if not found then
    raise exception 'car_not_found' using errcode = 'P0001';
  end if;
  return c;
end $$;

-- Erster Großbuchstabe + zweiter Kleinbuchstabe: "Lisa" -> "Li".
create function private.short_name(p_first_name text) returns text
language sql immutable set search_path = ''
as $$ select upper(substr(btrim(p_first_name), 1, 1)) || lower(substr(btrim(p_first_name), 2, 1)) $$;

-- Einladungscode wie K7P-2QX, ohne verwechselbare Zeichen (0/O, 1/I).
create function private.new_invite_code() returns text
language plpgsql volatile set search_path = ''
as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  code text;
begin
  loop
    code := '';
    for i in 1..6 loop
      code := code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
      if i = 3 then code := code || '-'; end if;
    end loop;
    exit when not exists (select 1 from public.families where invite_code = code);
  end loop;
  return code;
end $$;

-- Trigger -------------------------------------------------------------------
-- Autos: Kalenderfarbe vergeben, Hauptnutzer muss zur Familie gehören.
create function private.cars_before_write() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.color_slot is null then
    select coalesce(min(s), 1) into new.color_slot
      from generate_series(1, 1 + (select count(*) from public.cars where family_id = new.family_id)) s
     where s not in (select color_slot from public.cars
                      where family_id = new.family_id and not archived and id <> new.id);
  end if;
  if new.primary_member_id is not null and not exists (
       select 1 from public.members where id = new.primary_member_id and family_id = new.family_id) then
    raise exception 'member_not_in_family' using errcode = 'P0001';
  end if;
  return new;
end $$;

create trigger cars_before_write before insert or update on public.cars
  for each row execute function private.cars_before_write();

-- Mitglieder: Rolle ändern nur Admins, letzter Admin bleibt Admin.
create function private.members_before_update() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.role is distinct from old.role then
    if auth.uid() is not null and not private.is_admin() then
      raise exception 'admin_required' using errcode = 'P0001';
    end if;
    if old.role = 'admin' and not exists (
         select 1 from public.members
          where family_id = old.family_id and role = 'admin' and id <> old.id) then
      raise exception 'last_admin' using errcode = 'P0001';
    end if;
  end if;
  if new.first_name is distinct from old.first_name and new.short is not distinct from old.short then
    new.short := private.short_name(new.first_name);
  end if;
  return new;
end $$;

create trigger members_before_update before update on public.members
  for each row execute function private.members_before_update();

-- Neue Mitglieder bekommen Standard-Einstellungen.
create function private.members_after_insert() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.settings (member_id) values (new.id) on conflict do nothing;
  return new;
end $$;

create trigger members_after_insert after insert on public.members
  for each row execute function private.members_after_insert();

-- Schäden: Familie vom Auto übernehmen, Melder ist der Aufrufer.
create function private.damages_before_insert() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  select family_id into new.family_id from public.cars where id = new.car_id;
  if auth.uid() is not null then
    new.reported_by := private.my_member_id();
  end if;
  return new;
end $$;

create trigger damages_before_insert before insert on public.damages
  for each row execute function private.damages_before_insert();

-- Row Level Security --------------------------------------------------------
alter table public.families       enable row level security;
alter table public.members        enable row level security;
alter table public.cars           enable row level security;
alter table public.booking_series enable row level security;
alter table public.bookings       enable row level security;
alter table public.damages        enable row level security;
alter table public.device_tokens  enable row level security;
alter table public.settings       enable row level security;
alter table public.notifications  enable row level security;

create policy families_select on public.families for select to authenticated
  using (id = (select private.my_family_id()));
create policy families_update on public.families for update to authenticated
  using (id = (select private.my_family_id()) and (select private.is_admin()));

create policy members_select on public.members for select to authenticated
  using (family_id = (select private.my_family_id()));
create policy members_update on public.members for update to authenticated
  using (family_id = (select private.my_family_id())
         and (id = (select private.my_member_id()) or (select private.is_admin())));

create policy cars_select on public.cars for select to authenticated
  using (family_id = (select private.my_family_id()));
create policy cars_insert on public.cars for insert to authenticated
  with check (family_id = (select private.my_family_id()) and (select private.is_admin()));
create policy cars_update on public.cars for update to authenticated
  using (family_id = (select private.my_family_id()) and (select private.is_admin()));

create policy booking_series_select on public.booking_series for select to authenticated
  using (family_id = (select private.my_family_id()));

create policy bookings_select on public.bookings for select to authenticated
  using (family_id = (select private.my_family_id()));

create policy damages_select on public.damages for select to authenticated
  using (family_id = (select private.my_family_id()));
create policy damages_insert on public.damages for insert to authenticated
  with check (family_id = (select private.my_family_id()));
create policy damages_update on public.damages for update to authenticated
  using (family_id = (select private.my_family_id()));

create policy device_tokens_select on public.device_tokens for select to authenticated
  using (member_id = (select private.my_member_id()));

create policy settings_select on public.settings for select to authenticated
  using (member_id = (select private.my_member_id()));
create policy settings_update on public.settings for update to authenticated
  using (member_id = (select private.my_member_id()));

create policy notifications_select on public.notifications for select to authenticated
  using (member_id = (select private.my_member_id()));

-- Rechte --------------------------------------------------------------------
-- Schreiben läuft über RPCs; direkt nur, was keine Geschäftslogik braucht.
revoke all on all tables in schema public from anon, authenticated;
revoke all on all tables in schema private from anon, authenticated;

grant select on public.families, public.members, public.cars, public.booking_series,
                public.bookings, public.damages, public.device_tokens, public.settings,
                public.notifications to authenticated;
grant update (name) on public.families to authenticated;
grant update (first_name, short, role) on public.members to authenticated;
grant insert (make, model, paint, nickname, plate, primary_member_id, color_slot, image_url,
              fuel_quarters, pickerl_until, service_due, odometer_km, family_id)
  on public.cars to authenticated;
grant update (make, model, paint, nickname, plate, primary_member_id, color_slot, image_url,
              fuel_quarters, pickerl_until, service_due, odometer_km, archived)
  on public.cars to authenticated;
grant insert (car_id, description, photo_path, drivable) on public.damages to authenticated;
grant update (resolved_at) on public.damages to authenticated;
grant update (notify_car_free, notify_booking_displaced, notify_reservation_soon,
              notify_return_overdue, notify_service_pickerl, calendar_car_animation, launch_animation)
  on public.settings to authenticated;

-- Hilfsfunktionen werden in Policies aufgerufen.
grant usage on schema private to authenticated;
alter default privileges in schema private revoke execute on functions from public;
revoke execute on all functions in schema private from public, anon, authenticated;
grant execute on function private.my_member_id(), private.my_family_id(), private.is_admin()
  to authenticated;
