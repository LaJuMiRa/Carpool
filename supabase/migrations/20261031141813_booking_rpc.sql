-- RPCs: Belegung, Konflikte, Verdrängen, Rückgängig
-- Fehler als Exception mit festem Code (z. B. 'car_busy'); Konflikte beim
-- Reservieren als JSON-Antwort, damit das Formular sie direkt anzeigen kann.

-- Konstanten ----------------------------------------------------------------
create function private.undo_window() returns interval
language sql immutable set search_path = '' as $$ select interval '15 seconds' $$;

-- So früh darf man die eigene Reservierung schon als Fahrt antreten.
create function private.own_reservation_lead() returns interval
language sql immutable set search_path = '' as $$ select interval '15 minutes' $$;

-- So weit im Voraus werden Serien als einzelne Buchungen angelegt.
create function private.series_horizon_days() returns int
language sql immutable set search_path = '' as $$ select 56 $$;

create function private.max_reservation_length() returns interval
language sql immutable set search_path = '' as $$ select interval '14 days' $$;

-- Konfliktprüfung -----------------------------------------------------------
-- Aktive Buchungen eines Autos, die [p_start, p_end) berühren. Eine laufende
-- Fahrt belegt das Auto bis zum geplanten Ende, mindestens aber bis jetzt.
create function private.conflicts(p_car_id uuid, p_start timestamptz, p_end timestamptz)
returns setof public.bookings
language sql stable security definer set search_path = ''
as $$
  select b.* from public.bookings b
   where b.car_id = p_car_id
     and b.status = 'active'
     and case
           when b.ends_at is not null then
             tstzrange(b.starts_at, b.ends_at) && tstzrange(p_start, p_end)
           else
             tstzrange(b.starts_at, greatest(coalesce(b.planned_ends_at, now()), now()), '[]')
               && tstzrange(p_start, p_end)
         end
$$;

create function private.car_is_free(p_car_id uuid, p_start timestamptz, p_end timestamptz)
returns boolean
language sql stable security definer set search_path = ''
as $$ select not exists (select 1 from private.conflicts(p_car_id, p_start, p_end)) $$;

-- Erstes freies Ersatzauto für eine Buchung (nach Kalenderfarbe).
create function private.find_replacement(p_booking public.bookings) returns uuid
language sql stable security definer set search_path = ''
as $$
  select c.id from public.cars c
   where c.family_id = p_booking.family_id
     and not c.archived
     and c.id <> p_booking.car_id
     and private.car_is_free(c.id, p_booking.starts_at, p_booking.ends_at)
   order by c.color_slot
   limit 1
$$;

-- Darf p_member diese Buchung verdrängen? Nur zukünftige Reservierungen
-- anderer, nur als Hauptnutzer des Autos.
create function private.can_displace(p_booking public.bookings, p_member public.members)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select p_booking.kind = 'reservation'
     and p_booking.status = 'active'
     and p_booking.starts_at > now()
     and p_booking.member_id <> p_member.id
     and exists (select 1 from public.cars
                  where id = p_booking.car_id and primary_member_id = p_member.id)
$$;

create function private.conflict_json(p_booking public.bookings, p_member public.members)
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'booking_id',   p_booking.id,
    'kind',         p_booking.kind,
    'starts_at',    p_booking.starts_at,
    'ends_at',      coalesce(p_booking.ends_at, p_booking.planned_ends_at),
    'member_id',    p_booking.member_id,
    'first_name',   (select first_name from public.members where id = p_booking.member_id),
    'can_displace', private.can_displace(p_booking, p_member))
$$;

-- Autos der Familie, die in allen Zeiträumen frei sind.
create function private.free_car_ids(p_family_id uuid, p_ranges tstzrange[], p_exclude uuid)
returns uuid[]
language sql stable security definer set search_path = ''
as $$
  select coalesce(array_agg(c.id order by c.color_slot), '{}')
    from public.cars c
   where c.family_id = p_family_id
     and not c.archived
     and c.id is distinct from p_exclude
     and not exists (select 1 from unnest(p_ranges) r
                      where not private.car_is_free(c.id, lower(r), upper(r)))
$$;

-- Wöchentliche Termine zwischen zwei Tagen in der Zeitzone der Familie.
create function private.weekly_occurrences(p_rrule text, p_start_time time, p_end_time time,
                                           p_from date, p_to date, p_time_zone text)
returns table (starts_at timestamptz, ends_at timestamptz)
language sql stable set search_path = ''
as $$
  select (d::date + p_start_time) at time zone p_time_zone,
         (d::date + p_end_time) at time zone p_time_zone
    from generate_series(p_from::timestamp, p_to::timestamp, interval '1 day') d
   where (array['MO','TU','WE','TH','FR','SA','SU'])[extract(isodow from d)::int]
         = any (string_to_array(split_part(p_rrule, 'BYDAY=', 2), ','))
   order by 1
$$;

-- Verdrängen: Status setzen, Verdrängten benachrichtigen, Ersatz vorschlagen.
create function private.displace_booking(p_booking public.bookings, p_by public.members)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  replacement uuid := private.find_replacement(p_booking);
begin
  update public.bookings
     set status = 'displaced', displaced_by = p_by.id
   where id = p_booking.id;

  insert into public.notifications (family_id, member_id, kind, payload)
  values (p_booking.family_id, p_booking.member_id, 'booking_displaced',
          jsonb_build_object('booking_id', p_booking.id, 'car_id', p_booking.car_id,
                             'starts_at', p_booking.starts_at, 'ends_at', p_booking.ends_at,
                             'displaced_by', p_by.id, 'replacement_car_id', replacement));
  return replacement;
end $$;

create function private.lock_car(p_car_id uuid) returns void
language sql security definer set search_path = ''
as $$ select null::void from public.cars where id = p_car_id for update $$;

-- Reservieren (gemeinsam für reserve und check_reservation) -----------------
create function private.reserve_impl(
  p_car_id uuid, p_starts_at timestamptz, p_ends_at timestamptz,
  p_rrule text, p_until date, p_displace boolean, p_accept_no_replacement boolean,
  p_dry_run boolean)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  m public.members := private.require_member();
  car public.cars := private.require_car(p_car_id, m.family_id);
  tz text;
  ranges tstzrange[];
  local_start timestamp;
  local_end timestamp;
  from_day date;
  to_day date;
  conflict_rows public.bookings[];
  b public.bookings;
  missing int := 0;
  displaced int := 0;
  new_series_id uuid;
  new_ids uuid[];
begin
  if p_starts_at is null or p_ends_at is null or p_ends_at <= p_starts_at then
    raise exception 'invalid_range' using errcode = 'P0001';
  end if;
  if p_starts_at < now() - interval '5 minutes' then
    raise exception 'starts_in_past' using errcode = 'P0001';
  end if;
  if p_ends_at - p_starts_at > private.max_reservation_length() then
    raise exception 'range_too_long' using errcode = 'P0001';
  end if;

  if not p_dry_run then
    perform private.lock_car(car.id);
  end if;

  select time_zone into tz from public.families where id = m.family_id;

  if p_rrule is null then
    ranges := array[tstzrange(p_starts_at, p_ends_at)];
  else
    if p_rrule !~ '^FREQ=WEEKLY;BYDAY=(MO|TU|WE|TH|FR|SA|SU)(,(MO|TU|WE|TH|FR|SA|SU))*$' then
      raise exception 'invalid_rrule' using errcode = 'P0001';
    end if;
    local_start := p_starts_at at time zone tz;
    local_end := p_ends_at at time zone tz;
    if local_start::date <> local_end::date then
      raise exception 'series_must_end_same_day' using errcode = 'P0001';
    end if;
    from_day := local_start::date;
    if p_until is not null and p_until < from_day then
      raise exception 'invalid_until' using errcode = 'P0001';
    end if;
    to_day := least(coalesce(p_until, 'infinity'::date), from_day + private.series_horizon_days());
    select coalesce(array_agg(tstzrange(o.starts_at, o.ends_at) order by o.starts_at), '{}')
      into ranges
      from private.weekly_occurrences(p_rrule, local_start::time, local_end::time,
                                      from_day, to_day, tz) o
     where o.ends_at > now();
    if cardinality(ranges) = 0 then
      raise exception 'no_occurrences' using errcode = 'P0001';
    end if;
  end if;

  select coalesce(array_agg(x order by x.starts_at), '{}') into conflict_rows
    from public.bookings x
   where x.id in (select c.id
                    from unnest(ranges) r
                    cross join lateral private.conflicts(car.id, lower(r), upper(r)) c);

  if cardinality(conflict_rows) > 0 then
    if not p_displace or p_dry_run
       or exists (select 1 from unnest(conflict_rows) c where not private.can_displace(c, m)) then
      return jsonb_build_object(
        'ok', false,
        'reason', case when p_displace and not p_dry_run then 'not_displaceable' else 'conflict' end,
        'conflicts', (select jsonb_agg(private.conflict_json(c, m)) from unnest(conflict_rows) c),
        'free_car_ids', to_jsonb(private.free_car_ids(m.family_id, ranges, car.id)));
    end if;

    select count(*) into missing
      from unnest(conflict_rows) c where private.find_replacement(c) is null;
    if missing > 0 and not p_accept_no_replacement then
      return jsonb_build_object(
        'ok', false, 'reason', 'no_replacement', 'missing_replacements', missing,
        'conflicts', (select jsonb_agg(private.conflict_json(c, m)) from unnest(conflict_rows) c));
    end if;

    foreach b in array conflict_rows loop
      perform private.displace_booking(b, m);
      displaced := displaced + 1;
    end loop;
  end if;

  if p_dry_run then
    return jsonb_build_object('ok', true);
  end if;

  if p_rrule is not null then
    insert into public.booking_series (family_id, car_id, member_id, rrule, start_time, end_time,
                                       starts_on, until, materialized_until)
    values (m.family_id, car.id, m.id, p_rrule, local_start::time, local_end::time,
            from_day, p_until, to_day)
    returning id into new_series_id;
  end if;

  with inserted as (
    insert into public.bookings (family_id, car_id, member_id, starts_at, ends_at, kind, series_id)
    select m.family_id, car.id, m.id, lower(r), upper(r), 'reservation', new_series_id
      from unnest(ranges) r
    returning id, starts_at
  )
  select array_agg(id order by starts_at) into new_ids from inserted;

  return jsonb_build_object('ok', true, 'booking_ids', to_jsonb(new_ids),
                            'series_id', new_series_id, 'displaced_count', displaced);
exception
  when exclusion_violation then
    raise exception 'conflict_retry' using errcode = 'P0001';
end $$;

-- Öffentliche RPCs ----------------------------------------------------------

-- Reservieren, einmalig oder wöchentlich (p_rrule = 'FREQ=WEEKLY;BYDAY=MO,TU').
-- Antwort: {ok:true, booking_ids, series_id, displaced_count}
--      oder {ok:false, reason:'conflict'|'not_displaceable'|'no_replacement', conflicts, free_car_ids}
create function public.reserve(
  p_car_id uuid, p_starts_at timestamptz, p_ends_at timestamptz,
  p_rrule text default null, p_until date default null,
  p_displace boolean default false, p_accept_no_replacement boolean default false)
returns jsonb
language sql security definer set search_path = ''
as $$
  select private.reserve_impl(p_car_id, p_starts_at, p_ends_at, p_rrule, p_until,
                              p_displace, p_accept_no_replacement, false)
$$;

-- Prüfen ohne zu buchen (für den Hinweis direkt im Formular).
create function public.check_reservation(
  p_car_id uuid, p_starts_at timestamptz, p_ends_at timestamptz,
  p_rrule text default null, p_until date default null)
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select private.reserve_impl(p_car_id, p_starts_at, p_ends_at, p_rrule, p_until,
                              false, false, true)
$$;

-- Alle Autos der Familie, die im Zeitraum frei sind.
create function public.free_cars(p_starts_at timestamptz, p_ends_at timestamptz)
returns setof public.cars
language plpgsql stable security definer set search_path = ''
as $$
declare
  m public.members := private.require_member();
begin
  if p_starts_at is null or p_ends_at is null or p_ends_at <= p_starts_at then
    raise exception 'invalid_range' using errcode = 'P0001';
  end if;
  return query
    select c.* from public.cars c
     where c.family_id = m.family_id and not c.archived
       and private.car_is_free(c.id, p_starts_at, p_ends_at)
     order by c.color_slot;
end $$;

-- Einzelne Reservierung verdrängen (Hauptnutzer). Der Aufrufer erfährt nur,
-- ob ein Ersatzauto gefunden wurde, nicht welches.
create function public.displace(p_booking_id uuid, p_accept_no_replacement boolean default false)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  m public.members := private.require_member();
  b public.bookings;
  replacement uuid;
begin
  select * into b from public.bookings where id = p_booking_id and family_id = m.family_id;
  if not found then
    raise exception 'booking_not_found' using errcode = 'P0001';
  end if;
  perform private.lock_car(b.car_id);
  select * into b from public.bookings where id = p_booking_id;

  if not private.can_displace(b, m) then
    raise exception 'not_displaceable' using errcode = 'P0001';
  end if;
  if private.find_replacement(b) is null and not p_accept_no_replacement then
    return jsonb_build_object('ok', false, 'reason', 'no_replacement');
  end if;

  replacement := private.displace_booking(b, m);
  return jsonb_build_object('ok', true, 'replacement_found', replacement is not null);
end $$;

-- Nehmen: freies Auto sofort belegen (offene Fahrt). Hat der Aufrufer jetzt
-- oder in Kürze eine eigene Reservierung, wird sie zur Fahrt.
create function public.take_car(p_car_id uuid) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  m public.members := private.require_member();
  car public.cars := private.require_car(p_car_id, m.family_id);
  other public.bookings;
  own public.bookings;
  booking_id uuid;
begin
  perform private.lock_car(car.id);

  if exists (select 1 from public.bookings
              where car_id = car.id and status = 'active' and ends_at is null) then
    raise exception 'car_busy' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.bookings
              where member_id = m.id and status = 'active' and ends_at is null) then
    raise exception 'already_driving' using errcode = 'P0001';
  end if;

  select * into other from public.bookings
   where car_id = car.id and status = 'active' and kind = 'reservation'
     and member_id <> m.id and starts_at <= now() and ends_at > now()
   limit 1;
  if found then
    raise exception 'car_reserved' using errcode = 'P0001';
  end if;

  select * into own from public.bookings
   where car_id = car.id and member_id = m.id and status = 'active' and kind = 'reservation'
     and starts_at <= now() + private.own_reservation_lead() and ends_at > now()
   order by starts_at
   limit 1
   for update;

  if found then
    update public.bookings
       set kind = 'trip', starts_at = clock_timestamp(), ends_at = null,
           planned_ends_at = own.ends_at, fuel_quarters_on_take = car.fuel_quarters
     where id = own.id;
    booking_id := own.id;
  else
    insert into public.bookings (family_id, car_id, member_id, starts_at, kind, fuel_quarters_on_take)
    values (m.family_id, car.id, m.id, clock_timestamp(), 'trip', car.fuel_quarters)
    returning id into booking_id;
  end if;

  insert into private.member_actions (member_id, kind, booking_id, previous)
  values (m.id, 'take', booking_id,
          case when own.id is not null
               then jsonb_build_object('kind', 'reservation', 'starts_at', own.starts_at,
                                       'ends_at', own.ends_at)
               else '{}'::jsonb end);

  return jsonb_build_object('ok', true, 'booking_id', booking_id,
                            'from_reservation', own.id is not null);
end $$;

-- Zurückgeben: laufende Fahrt beenden, Tankstand speichern, nächste Person
-- benachrichtigen (verzögert, damit Rückgängig sie noch zurückholen kann).
create function public.return_car(p_fuel_quarters int, p_car_id uuid default null) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  m public.members := private.require_member();
  trip public.bookings;
  car public.cars;
  next_booking public.bookings;
  note_ids uuid[] := '{}';
begin
  if p_fuel_quarters is null or p_fuel_quarters not between 1 and 4 then
    raise exception 'invalid_fuel' using errcode = 'P0001';
  end if;

  select * into trip from public.bookings
   where member_id = m.id and status = 'active' and ends_at is null
     and (p_car_id is null or car_id = p_car_id)
   for update;
  if not found then
    raise exception 'no_running_trip' using errcode = 'P0001';
  end if;

  select * into car from public.cars where id = trip.car_id for update;

  update public.bookings
     set ends_at = greatest(clock_timestamp(), trip.starts_at + interval '1 second'),
         status = 'completed', fuel_quarters_on_return = p_fuel_quarters
   where id = trip.id;
  update public.cars set fuel_quarters = p_fuel_quarters where id = car.id;

  select * into next_booking from public.bookings
   where car_id = car.id and status = 'active' and kind = 'reservation'
     and member_id <> m.id and ends_at > now()
   order by starts_at
   limit 1;
  if found then
    with n as (
      insert into public.notifications (family_id, member_id, kind, payload, send_after)
      values (m.family_id, next_booking.member_id, 'car_free',
              jsonb_build_object('car_id', car.id, 'booking_id', next_booking.id,
                                 'starts_at', next_booking.starts_at, 'returned_by', m.id,
                                 'fuel_quarters', p_fuel_quarters),
              now() + private.undo_window())
      returning id
    )
    select array_agg(id) into note_ids from n;
  end if;

  insert into private.member_actions (member_id, kind, booking_id, previous, notification_ids)
  values (m.id, 'return', trip.id, jsonb_build_object('fuel_quarters', car.fuel_quarters), note_ids);

  return jsonb_build_object('ok', true, 'booking_id', trip.id);
end $$;

-- Rückgängig: letzte Aktion (Nehmen/Zurückgeben) innerhalb des Zeitfensters.
create function public.undo_last_action() returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  m public.members := private.require_member();
  a private.member_actions;
  b public.bookings;
begin
  select * into a from private.member_actions
   where member_id = m.id and undone_at is null
     and created_at > clock_timestamp() - private.undo_window()
   order by created_at desc
   limit 1
   for update;
  if not found then
    raise exception 'nothing_to_undo' using errcode = 'P0001';
  end if;

  select * into b from public.bookings where id = a.booking_id for update;
  perform private.lock_car(b.car_id);

  begin
    if a.kind = 'take' then
      if b.status <> 'active' or b.ends_at is not null then
        raise exception 'undo_expired' using errcode = 'P0001';
      end if;
      if a.previous ->> 'kind' = 'reservation' then
        update public.bookings
           set kind = 'reservation',
               starts_at = (a.previous ->> 'starts_at')::timestamptz,
               ends_at = (a.previous ->> 'ends_at')::timestamptz,
               planned_ends_at = null, fuel_quarters_on_take = null
         where id = b.id;
      else
        update public.bookings
           set status = 'cancelled',
               ends_at = greatest(clock_timestamp(), b.starts_at + interval '1 second')
         where id = b.id;
      end if;
    else
      if b.status <> 'completed' then
        raise exception 'undo_expired' using errcode = 'P0001';
      end if;
      update public.bookings
         set status = 'active', ends_at = null, fuel_quarters_on_return = null
       where id = b.id;
      update public.cars set fuel_quarters = (a.previous ->> 'fuel_quarters')::int
       where id = b.car_id;
      delete from public.notifications
       where id = any (a.notification_ids) and sent_at is null;
    end if;
  exception
    when unique_violation or exclusion_violation then
      raise exception 'undo_expired' using errcode = 'P0001';
  end;

  update private.member_actions set undone_at = clock_timestamp() where id = a.id;
  return jsonb_build_object('ok', true, 'kind', a.kind, 'booking_id', b.id);
end $$;

-- Eigene Reservierung stornieren; mit p_whole_series auch alle folgenden der Serie.
create function public.cancel_booking(p_booking_id uuid, p_whole_series boolean default false)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  m public.members := private.require_member();
  b public.bookings;
  n int;
begin
  select * into b from public.bookings
   where id = p_booking_id and family_id = m.family_id
   for update;
  if not found then
    raise exception 'booking_not_found' using errcode = 'P0001';
  end if;
  if b.member_id <> m.id then
    raise exception 'not_owner' using errcode = 'P0001';
  end if;
  if b.kind <> 'reservation' or b.status <> 'active' or b.ends_at <= now() then
    raise exception 'not_cancellable' using errcode = 'P0001';
  end if;

  if p_whole_series and b.series_id is not null then
    update public.bookings set status = 'cancelled'
     where series_id = b.series_id and status = 'active' and kind = 'reservation'
       and starts_at >= b.starts_at;
    get diagnostics n = row_count;
    update public.booking_series set status = 'cancelled' where id = b.series_id;
  else
    update public.bookings set status = 'cancelled' where id = b.id;
    n := 1;
  end if;

  return jsonb_build_object('ok', true, 'cancelled_count', n);
end $$;

-- Rechte --------------------------------------------------------------------
revoke execute on all functions in schema private from public, anon, authenticated;
grant execute on function private.my_member_id(), private.my_family_id(), private.is_admin()
  to authenticated;

revoke execute on function
  public.reserve(uuid, timestamptz, timestamptz, text, date, boolean, boolean),
  public.check_reservation(uuid, timestamptz, timestamptz, text, date),
  public.free_cars(timestamptz, timestamptz),
  public.displace(uuid, boolean),
  public.take_car(uuid),
  public.return_car(int, uuid),
  public.undo_last_action(),
  public.cancel_booking(uuid, boolean)
  from public, anon;
grant execute on function
  public.reserve(uuid, timestamptz, timestamptz, text, date, boolean, boolean),
  public.check_reservation(uuid, timestamptz, timestamptz, text, date),
  public.free_cars(timestamptz, timestamptz),
  public.displace(uuid, boolean),
  public.take_car(uuid),
  public.return_car(int, uuid),
  public.undo_last_action(),
  public.cancel_booking(uuid, boolean)
  to authenticated;
