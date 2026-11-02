-- Phase 7: Push-Nachrichten.
-- Erinnerungen landen wie alle Nachrichten in public.notifications (Outbox). Jede Minute ruft
-- pg_cron die Edge Function "send-push" auf; sie holt fällige Nachrichten mit claim_push_batch()
-- ab und verschickt sie über APNs (später FCM). Texte baut die Edge Function.

create extension if not exists pg_net;

-- Doppelte Erinnerungen vermeiden (Suche nach Buchung bzw. Auto in der Outbox).
create index notifications_booking_idx on public.notifications (kind, (payload ->> 'booking_id'));
create index notifications_car_idx on public.notifications (kind, (payload ->> 'car_id'));

-- Reservierung beginnt bald (≤ 15 min) und Rückgabe überfällig (geplantes Ende + 15 min) --------
create function private.reminder_lead() returns interval
language sql immutable set search_path = '' as $$ select interval '15 minutes' $$;

create function private.queue_reminders() returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  created integer := 0;
  n integer;
begin
  insert into public.notifications (family_id, member_id, kind, payload)
  select b.family_id, b.member_id, 'reservation_soon',
         jsonb_build_object('booking_id', b.id, 'car_id', b.car_id,
                            'starts_at', b.starts_at, 'ends_at', b.ends_at)
    from public.bookings b
   where b.kind = 'reservation' and b.status = 'active'
     and b.starts_at > now() and b.starts_at <= now() + private.reminder_lead()
     and not exists (select 1 from public.notifications x
                      where x.kind = 'reservation_soon' and x.payload ->> 'booking_id' = b.id::text);
  get diagnostics n = row_count;
  created := created + n;

  insert into public.notifications (family_id, member_id, kind, payload)
  select b.family_id, b.member_id, 'return_overdue',
         jsonb_build_object('booking_id', b.id, 'car_id', b.car_id, 'planned_ends_at', b.planned_ends_at)
    from public.bookings b
   where b.kind = 'trip' and b.status = 'active' and b.ends_at is null
     and b.planned_ends_at < now() - private.reminder_lead()
     and not exists (select 1 from public.notifications x
                      where x.kind = 'return_overdue' and x.payload ->> 'booking_id' = b.id::text);
  get diagnostics n = row_count;
  return created + n;
end $$;

-- Pickerl und Service (täglich): einmal je Auto und Termin, sobald er ≤ 30 Tage entfernt ist.
-- Empfänger: Hauptnutzer, sonst alle Admins. Pickerl gilt bis Monatsende.
create function private.queue_car_reminders() returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  created integer;
begin
  with due as (
    select c.id as car_id, c.family_id, c.primary_member_id, d.field, d.due_on
      from public.cars c
      join public.families f on f.id = c.family_id
     cross join lateral (values
       ('pickerl', (date_trunc('month', c.pickerl_until) + interval '1 month - 1 day')::date),
       ('service', c.service_due)
     ) as d(field, due_on)
     where not c.archived and d.due_on is not null
       and d.due_on <= (now() at time zone f.time_zone)::date + 30
  ), recipients as (
    select due.*, m.id as member_id
      from due
      join public.members m on m.family_id = due.family_id
     where m.user_id is not null
       and (m.id = due.primary_member_id or (due.primary_member_id is null and m.role = 'admin'))
  )
  insert into public.notifications (family_id, member_id, kind, payload)
  select r.family_id, r.member_id, 'service_pickerl',
         jsonb_build_object('car_id', r.car_id, 'field', r.field, 'due_on', r.due_on)
    from recipients r
   where not exists (select 1 from public.notifications x
                      where x.kind = 'service_pickerl' and x.member_id = r.member_id
                        and x.payload ->> 'car_id' = r.car_id::text
                        and x.payload ->> 'field' = r.field
                        and x.payload ->> 'due_on' = r.due_on::text);
  get diagnostics created = row_count;
  return created;
end $$;

-- Fällige Nachrichten abholen (nur Edge Function / service_role) -----------------------------
-- Markiert sie sofort als verschickt (kein Doppelversand bei parallelen Aufrufen; mehr als 1 h
-- überfällige werden nur markiert, nicht geliefert) und liefert
-- alles, was für Text und Versand nötig ist: Auto- und Personennamen, Zeitzone, Schalter, Geräte.
create function public.claim_push_batch(p_limit integer default 100) returns jsonb
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
                           where m.id = coalesce(c.payload ->> 'displaced_by', c.payload ->> 'returned_by')::uuid),
           'tokens', (select coalesce(jsonb_agg(jsonb_build_object('platform', d.platform, 'token', d.token)),
                                      '[]'::jsonb)
                        from public.device_tokens d where d.member_id = c.member_id)
         )), '[]'::jsonb)
    into result
    from claimed c
    join public.families f on f.id = c.family_id
    left join public.settings s on s.member_id = c.member_id
   -- Mehr als 1 h überfällig (z. B. bevor Push eingerichtet war): nur als erledigt markieren.
   where c.send_after > now() - interval '1 hour';
  return result;
end $$;

-- Ungültige Gerätetoken (APNs 410 / BadDeviceToken) entfernen.
create function public.drop_device_tokens(p_tokens text[]) returns integer
language sql security definer set search_path = ''
as $$
  with gone as (delete from public.device_tokens where token = any (p_tokens) returning 1)
  select count(*)::integer from gone
$$;

revoke execute on function public.claim_push_batch(integer), public.drop_device_tokens(text[])
  from public, anon, authenticated;
grant execute on function public.claim_push_batch(integer), public.drop_device_tokens(text[]) to service_role;
revoke execute on function private.queue_reminders(), private.queue_car_reminders()
  from public, anon, authenticated;

-- Edge Function anstoßen, wenn etwas fällig ist. URL und Geheimnis liegen im Vault:
--   select vault.create_secret('https://<ref>.supabase.co', 'project_url');
--   select vault.create_secret('<zufälliger Wert>', 'push_dispatch_secret');
-- Ohne beide Einträge passiert nichts (Nachrichten bleiben in der Outbox liegen).
create function private.dispatch_push() returns void
language plpgsql security definer set search_path = ''
as $$
declare
  url text;
  secret text;
begin
  if not exists (select 1 from public.notifications where sent_at is null and send_after <= now()) then
    return;
  end if;
  select decrypted_secret into url from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into secret from vault.decrypted_secrets where name = 'push_dispatch_secret';
  if url is null or secret is null then
    return;
  end if;
  perform net.http_post(
    url := url || '/functions/v1/send-push',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || secret),
    body := '{}'::jsonb);
end $$;

revoke execute on function private.dispatch_push() from public, anon, authenticated;

select cron.schedule('queue-reminders', '* * * * *', 'select private.queue_reminders()');
select cron.schedule('queue-car-reminders', '0 6 * * *', 'select private.queue_car_reminders()');
select cron.schedule('dispatch-push', '* * * * *', 'select private.dispatch_push()');
