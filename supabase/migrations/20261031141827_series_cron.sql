-- Wiederkehrende Serien täglich für die nächsten Wochen materialisieren.

create extension if not exists pg_cron;

-- Legt fehlende Termine aktiver Serien bis zum Horizont an. Belegte Termine
-- werden übersprungen und der Serien-Inhaber benachrichtigt.
create function private.materialize_series() returns int
language plpgsql security definer set search_path = ''
as $$
declare
  s public.booking_series;
  tz text;
  from_day date;
  to_day date;
  o record;
  created int := 0;
begin
  for s in select * from public.booking_series where status = 'active' for update loop
    select time_zone into tz from public.families where id = s.family_id;
    from_day := greatest(s.materialized_until + 1, (now() at time zone tz)::date);
    to_day := least(coalesce(s.until, 'infinity'::date),
                    (now() at time zone tz)::date + private.series_horizon_days());
    continue when to_day < from_day;

    perform private.lock_car(s.car_id);
    for o in select * from private.weekly_occurrences(s.rrule, s.start_time, s.end_time,
                                                      from_day, to_day, tz) loop
      if private.car_is_free(s.car_id, o.starts_at, o.ends_at) then
        insert into public.bookings (family_id, car_id, member_id, starts_at, ends_at, kind, series_id)
        values (s.family_id, s.car_id, s.member_id, o.starts_at, o.ends_at, 'reservation', s.id);
        created := created + 1;
      else
        insert into public.notifications (family_id, member_id, kind, payload)
        values (s.family_id, s.member_id, 'series_occurrence_skipped',
                jsonb_build_object('series_id', s.id, 'car_id', s.car_id,
                                   'starts_at', o.starts_at, 'ends_at', o.ends_at));
      end if;
    end loop;

    update public.booking_series set materialized_until = to_day where id = s.id;
  end loop;
  return created;
end $$;

revoke execute on function private.materialize_series() from public, anon, authenticated;

select cron.schedule('materialize-booking-series', '15 2 * * *',
                     'select private.materialize_series()');
