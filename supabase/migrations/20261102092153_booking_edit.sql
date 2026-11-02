-- Kontextmenü F11: Reservierung bearbeiten, verlängern, an jemand übergeben.
-- Bearbeiten läuft über dieselbe Prüfung wie Reservieren (Konflikte, Tauschen, Übernehmen);
-- die bearbeitete Buchung zählt dabei nicht als Konflikt.

-- Konflikte ohne die Buchung, die gerade bearbeitet wird -------------------------------
create function private.conflicts_except(p_car_id uuid, p_start timestamptz, p_end timestamptz,
                                         p_ignore uuid)
returns setof public.bookings
language sql stable security definer set search_path = ''
as $$
  select c.* from private.conflicts(p_car_id, p_start, p_end) c where c.id is distinct from p_ignore
$$;

create function private.car_is_free_except(p_car_id uuid, p_start timestamptz, p_end timestamptz,
                                           p_ignore uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$ select not exists (select 1 from private.conflicts_except(p_car_id, p_start, p_end, p_ignore)) $$;

create function private.free_car_ids(p_family_id uuid, p_ranges tstzrange[], p_exclude uuid, p_ignore uuid)
returns uuid[]
language sql stable security definer set search_path = ''
as $$
  select coalesce(array_agg(c.id order by c.color_slot), '{}')
    from public.cars c
   where c.family_id = p_family_id
     and not c.archived
     and c.id is distinct from p_exclude
     and not exists (select 1 from unnest(p_ranges) r
                      where not private.car_is_free_except(c.id, lower(r), upper(r), p_ignore))
$$;

-- Eigene, noch nicht vorbei: sonst booking_not_found / not_owner / not_editable.
create function private.require_own_booking(p_booking_id uuid, p_member public.members)
returns public.bookings
language plpgsql security definer set search_path = ''
as $$
declare
  b public.bookings;
begin
  select * into b from public.bookings where id = p_booking_id and family_id = p_member.family_id;
  if not found then
    raise exception 'booking_not_found' using errcode = 'P0001';
  end if;
  if b.member_id <> p_member.id then
    raise exception 'not_owner' using errcode = 'P0001';
  end if;
  if b.status <> 'active' or (b.ends_at is not null and b.ends_at <= now()) then
    raise exception 'not_editable' using errcode = 'P0001';
  end if;
  return b;
end $$;

-- Reservieren und Bearbeiten (p_booking_id gesetzt) -------------------------------------
create function private.reserve_impl(
  p_car_id uuid, p_starts_at timestamptz, p_ends_at timestamptz,
  p_rrule text, p_until date, p_displace boolean, p_accept_no_replacement boolean,
  p_dry_run boolean, p_booking_id uuid)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  m public.members := private.require_member();
  car public.cars := private.require_car(p_car_id, m.family_id);
  edit public.bookings;
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
  if p_booking_id is not null then
    edit := private.require_own_booking(p_booking_id, m);
    if edit.kind <> 'reservation' then
      raise exception 'not_editable' using errcode = 'P0001';
    end if;
    if p_rrule is not null then
      raise exception 'invalid_rrule' using errcode = 'P0001';
    end if;
  end if;

  if p_starts_at is null or p_ends_at is null or p_ends_at <= p_starts_at then
    raise exception 'invalid_range' using errcode = 'P0001';
  end if;
  -- Eine schon laufende Reservierung darf ihren Beginn behalten.
  if p_starts_at < now() - interval '5 minutes'
     and (edit.id is null or p_starts_at <> edit.starts_at) then
    raise exception 'starts_in_past' using errcode = 'P0001';
  end if;
  if p_ends_at <= now() then
    raise exception 'invalid_range' using errcode = 'P0001';
  end if;
  if p_ends_at - p_starts_at > private.max_reservation_length() then
    raise exception 'range_too_long' using errcode = 'P0001';
  end if;

  if not p_dry_run then
    perform private.lock_car(car.id);
    if edit.id is not null and edit.car_id <> car.id then
      perform private.lock_car(edit.car_id);
    end if;
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
                    cross join lateral private.conflicts_except(car.id, lower(r), upper(r), p_booking_id) c);

  if cardinality(conflict_rows) > 0 then
    if not p_displace or p_dry_run
       or exists (select 1 from unnest(conflict_rows) c where not private.can_displace(c, m)) then
      return jsonb_build_object(
        'ok', false,
        'reason', case when p_displace and not p_dry_run then 'not_displaceable' else 'conflict' end,
        'conflicts', (select jsonb_agg(private.conflict_json(c, m)) from unnest(conflict_rows) c),
        'free_car_ids', to_jsonb(private.free_car_ids(m.family_id, ranges, car.id, p_booking_id)));
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

  if edit.id is not null then
    -- Bearbeiteter Serientermin gehört danach nicht mehr zur Serie.
    update public.bookings
       set car_id = car.id, starts_at = p_starts_at, ends_at = p_ends_at, series_id = null
     where id = edit.id;
    if p_starts_at <> edit.starts_at or car.id <> edit.car_id then
      delete from public.notifications
       where kind = 'reservation_soon' and payload ->> 'booking_id' = edit.id::text;
    end if;
    return jsonb_build_object('ok', true, 'booking_ids', jsonb_build_array(edit.id),
                              'series_id', null, 'displaced_count', displaced);
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

create or replace function public.reserve(
  p_car_id uuid, p_starts_at timestamptz, p_ends_at timestamptz,
  p_rrule text default null, p_until date default null,
  p_displace boolean default false, p_accept_no_replacement boolean default false)
returns jsonb
language sql security definer set search_path = ''
as $$
  select private.reserve_impl(p_car_id, p_starts_at, p_ends_at, p_rrule, p_until,
                              p_displace, p_accept_no_replacement, false, null)
$$;

-- Prüfen ohne zu buchen; mit p_booking_id für das Bearbeiten-Formular.
drop function public.check_reservation(uuid, timestamptz, timestamptz, text, date);
create function public.check_reservation(
  p_car_id uuid, p_starts_at timestamptz, p_ends_at timestamptz,
  p_rrule text default null, p_until date default null, p_booking_id uuid default null)
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select private.reserve_impl(p_car_id, p_starts_at, p_ends_at, p_rrule, p_until,
                              false, false, true, p_booking_id)
$$;

drop function private.reserve_impl(uuid, timestamptz, timestamptz, text, date, boolean, boolean, boolean);

-- Eigene Reservierung ändern (Auto, Beginn, Ende). Antwort wie reserve.
create function public.update_booking(
  p_booking_id uuid, p_car_id uuid, p_starts_at timestamptz, p_ends_at timestamptz,
  p_displace boolean default false, p_accept_no_replacement boolean default false)
returns jsonb
language sql security definer set search_path = ''
as $$
  select private.reserve_impl(p_car_id, p_starts_at, p_ends_at, null, null,
                              p_displace, p_accept_no_replacement, false, p_booking_id)
$$;

-- Freie Autos; mit p_booking_id zählt die bearbeitete Buchung nicht.
drop function public.free_cars(timestamptz, timestamptz);
create function public.free_cars(p_starts_at timestamptz, p_ends_at timestamptz,
                                 p_booking_id uuid default null)
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
       and private.car_is_free_except(c.id, p_starts_at, p_ends_at, p_booking_id)
     order by c.color_slot;
end $$;

-- Verlängern: eigene Reservierung (neues Ende) oder laufende Fahrt (neues geplantes Ende).
-- Antwort {ok:true} oder {ok:false, reason:'conflict', conflicts}.
create function public.extend_booking(p_booking_id uuid, p_ends_at timestamptz) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  m public.members := private.require_member();
  b public.bookings := private.require_own_booking(p_booking_id, m);
  old_end timestamptz;
  conflict_rows public.bookings[];
begin
  perform private.lock_car(b.car_id);
  b := private.require_own_booking(p_booking_id, m);

  old_end := case when b.kind = 'reservation' then b.ends_at
                  else greatest(coalesce(b.planned_ends_at, now()), now()) end;
  if p_ends_at is null or p_ends_at <= old_end then
    raise exception 'invalid_range' using errcode = 'P0001';
  end if;
  if p_ends_at - b.starts_at > private.max_reservation_length() then
    raise exception 'range_too_long' using errcode = 'P0001';
  end if;

  select coalesce(array_agg(c order by c.starts_at), '{}') into conflict_rows
    from private.conflicts_except(b.car_id, old_end, p_ends_at, b.id) c;
  if cardinality(conflict_rows) > 0 then
    return jsonb_build_object(
      'ok', false, 'reason', 'conflict',
      'conflicts', (select jsonb_agg(private.conflict_json(c, m)) from unnest(conflict_rows) c));
  end if;

  if b.kind = 'reservation' then
    update public.bookings set ends_at = p_ends_at, series_id = null where id = b.id;
  else
    update public.bookings set planned_ends_at = p_ends_at where id = b.id;
    -- Erinnerung „Rückgabe überfällig" für das neue Ende erneut zulassen.
    delete from public.notifications
     where kind = 'return_overdue' and payload ->> 'booking_id' = b.id::text;
  end if;
  return jsonb_build_object('ok', true);
exception
  when exclusion_violation then
    raise exception 'conflict_retry' using errcode = 'P0001';
end $$;

-- An jemand übergeben: eigene Reservierung gehört danach p_member_id, die Person bekommt
-- eine Nachricht. Serientermine lösen sich aus der Serie.
create function public.transfer_booking(p_booking_id uuid, p_member_id uuid) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  m public.members := private.require_member();
  b public.bookings := private.require_own_booking(p_booking_id, m);
  target public.members;
begin
  if b.kind <> 'reservation' then
    raise exception 'not_editable' using errcode = 'P0001';
  end if;
  select * into target from public.members
   where id = p_member_id and family_id = m.family_id and removed_at is null;
  if not found or target.id = m.id then
    raise exception 'member_not_in_family' using errcode = 'P0001';
  end if;

  update public.bookings set member_id = target.id, series_id = null where id = b.id;
  delete from public.notifications
   where kind = 'reservation_soon' and payload ->> 'booking_id' = b.id::text;
  insert into public.notifications (family_id, member_id, kind, payload)
  values (m.family_id, target.id, 'booking_transferred',
          jsonb_build_object('booking_id', b.id, 'car_id', b.car_id, 'starts_at', b.starts_at,
                             'ends_at', b.ends_at, 'transferred_by', m.id));
  return jsonb_build_object('ok', true);
end $$;

-- Neue Nachricht „booking_transferred" (Schalter „Meine Buchung wurde übernommen") ---------
alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check
  check (kind in ('car_free', 'booking_displaced', 'booking_transferred', 'reservation_soon',
                  'return_overdue', 'service_pickerl', 'series_occurrence_skipped'));

create or replace function public.claim_push_batch(p_limit integer default 100) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  result jsonb;
begin
  with due as (
    select n.id from public.notifications n
     where n.sent_at is null and n.send_after <= now()
     order by n.send_after
     limit least(greatest(p_limit, 1), 500)
     for update skip locked
  ), claimed as (
    update public.notifications n set sent_at = now()
      from due where n.id = due.id
    returning n.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id,
           'kind', c.kind,
           'payload', c.payload,
           'time_zone', f.time_zone,
           'enabled', coalesce(case c.kind
             when 'car_free' then s.notify_car_free
             when 'booking_displaced' then s.notify_booking_displaced
             when 'booking_transferred' then s.notify_booking_displaced
             when 'series_occurrence_skipped' then s.notify_booking_displaced
             when 'reservation_soon' then s.notify_reservation_soon
             when 'return_overdue' then s.notify_return_overdue
             when 'service_pickerl' then s.notify_service_pickerl
           end, true),
           'car_title', (select coalesce(car.nickname, car.model) from public.cars car
                          where car.id = (c.payload ->> 'car_id')::uuid),
           'replacement_title', (select coalesce(car.nickname, car.model) from public.cars car
                                  where car.id = (c.payload ->> 'replacement_car_id')::uuid),
           'actor_name', (select m.first_name from public.members m
                           where m.id = coalesce(c.payload ->> 'displaced_by', c.payload ->> 'returned_by',
                                                 c.payload ->> 'transferred_by')::uuid),
           'tokens', (select coalesce(jsonb_agg(jsonb_build_object('platform', d.platform, 'token', d.token)),
                                      '[]'::jsonb)
                        from public.device_tokens d where d.member_id = c.member_id)
         )), '[]'::jsonb)
    into result
    from claimed c
    join public.families f on f.id = c.family_id
    left join public.settings s on s.member_id = c.member_id
   where c.send_after > now() - interval '1 hour';
  return result;
end $$;

-- Rechte --------------------------------------------------------------------------------
revoke execute on all functions in schema private from public, anon, authenticated;
grant execute on function private.my_member_id(), private.my_family_id(), private.is_admin()
  to authenticated;

revoke execute on function
  public.check_reservation(uuid, timestamptz, timestamptz, text, date, uuid),
  public.update_booking(uuid, uuid, timestamptz, timestamptz, boolean, boolean),
  public.free_cars(timestamptz, timestamptz, uuid),
  public.extend_booking(uuid, timestamptz),
  public.transfer_booking(uuid, uuid),
  public.claim_push_batch(integer)
  from public, anon;
revoke execute on function public.claim_push_batch(integer) from authenticated;
grant execute on function public.claim_push_batch(integer) to service_role;
grant execute on function
  public.check_reservation(uuid, timestamptz, timestamptz, text, date, uuid),
  public.update_booking(uuid, uuid, timestamptz, timestamptz, boolean, boolean),
  public.free_cars(timestamptz, timestamptz, uuid),
  public.extend_booking(uuid, timestamptz),
  public.transfer_booking(uuid, uuid)
  to authenticated;
