-- Bearbeiten mit Übernehmen: Die bearbeitete Buchung zieht weg, ihr altes Auto ist für den
-- Verdrängten damit frei. Ersatzauto-Suche und Verdrängen ignorieren sie deshalb.

drop function private.find_replacement(public.bookings);
create function private.find_replacement(p_booking public.bookings, p_ignore uuid default null)
returns uuid
language sql stable security definer set search_path = ''
as $$
  select c.id from public.cars c
   where c.family_id = p_booking.family_id
     and not c.archived
     and c.id <> p_booking.car_id
     and private.car_is_free_except(c.id, p_booking.starts_at, p_booking.ends_at, p_ignore)
   order by c.color_slot
   limit 1
$$;

drop function private.displace_booking(public.bookings, public.members);
create function private.displace_booking(p_booking public.bookings, p_by public.members,
                                         p_ignore uuid default null)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  replacement uuid := private.find_replacement(p_booking, p_ignore);
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

create or replace function private.reserve_impl(
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
      from unnest(conflict_rows) c where private.find_replacement(c, p_booking_id) is null;
    if missing > 0 and not p_accept_no_replacement then
      return jsonb_build_object(
        'ok', false, 'reason', 'no_replacement', 'missing_replacements', missing,
        'conflicts', (select jsonb_agg(private.conflict_json(c, m)) from unnest(conflict_rows) c));
    end if;

    foreach b in array conflict_rows loop
      perform private.displace_booking(b, m, p_booking_id);
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

revoke execute on all functions in schema private from public, anon, authenticated;
grant execute on function private.my_member_id(), private.my_family_id(), private.is_admin()
  to authenticated;
