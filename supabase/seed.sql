-- Beispiel-Familie Berger aus den Mockups (F02, F10, F15).
-- Mitglieder sind noch nicht beigetreten (user_id null). Wer mit Code K7P-2QX
-- und einem dieser Vornamen beitritt, übernimmt das Mitglied inkl. Rolle.
-- Zeiten relativ zu heute (Wien), damit Übersicht und Kalender gefüllt sind.
-- Erneut ausführbar: löscht die Familie vorher.

delete from public.families where invite_code = 'K7P-2QX';

insert into public.families (id, name, invite_code)
values ('b0000000-0000-4000-8000-000000000001', 'Familie Berger', 'K7P-2QX');

insert into public.members (id, family_id, first_name, short, role) values
  ('b0000000-0000-4000-8000-000000000011', 'b0000000-0000-4000-8000-000000000001', 'Papa',  'Pa', 'admin'),
  ('b0000000-0000-4000-8000-000000000012', 'b0000000-0000-4000-8000-000000000001', 'Mama',  'Ma', 'admin'),
  ('b0000000-0000-4000-8000-000000000013', 'b0000000-0000-4000-8000-000000000001', 'Lisa',  'Li', 'member'),
  ('b0000000-0000-4000-8000-000000000014', 'b0000000-0000-4000-8000-000000000001', 'Jonas', 'Jo', 'member'),
  ('b0000000-0000-4000-8000-000000000015', 'b0000000-0000-4000-8000-000000000001', 'Felix', 'Fe', 'member');

insert into public.cars (id, family_id, make, model, paint, nickname, plate, primary_member_id,
                         color_slot, fuel_quarters, pickerl_until, service_due, odometer_km) values
  ('b0000000-0000-4000-8000-000000000021', 'b0000000-0000-4000-8000-000000000001',
   'VW', 'Golf', 'silber', 'Radieschen', 'W-12345B', 'b0000000-0000-4000-8000-000000000011',
   1, 3, (current_date + 140), (current_date + 60), 84210),
  ('b0000000-0000-4000-8000-000000000022', 'b0000000-0000-4000-8000-000000000001',
   'Škoda', 'Octavia', 'dunkelgrau', null, 'W-67890K', null,
   2, 4, (current_date + 25), (current_date + 200), 132400),
  ('b0000000-0000-4000-8000-000000000023', 'b0000000-0000-4000-8000-000000000001',
   'Toyota', 'Yaris', 'blau', 'Flitzer', null, 'b0000000-0000-4000-8000-000000000014',
   3, 2, (current_date + 300), null, null);

-- Heute: Mama fährt Octavia 08:00–17:30, Lisa fährt Radieschen seit 09:12,
-- Felix hat Flitzer 14:00–19:00, Jonas braucht Radieschen ab 18:00.
with today as (select (now() at time zone 'Europe/Vienna')::date as d)
insert into public.bookings (family_id, car_id, member_id, starts_at, ends_at, planned_ends_at,
                             kind, fuel_quarters_on_take)
select 'b0000000-0000-4000-8000-000000000001', car_id::uuid, member_id::uuid,
       (d + s::time) at time zone 'Europe/Vienna',
       case when e is null then null else (d + e::time) at time zone 'Europe/Vienna' end,
       case when p is null then null else (d + p::time) at time zone 'Europe/Vienna' end,
       kind, fuel
  from today, (values
    ('b0000000-0000-4000-8000-000000000022', 'b0000000-0000-4000-8000-000000000012', '08:00', null,    '17:30', 'trip',        4),
    ('b0000000-0000-4000-8000-000000000021', 'b0000000-0000-4000-8000-000000000013', '09:12', null,    null,    'trip',        3),
    ('b0000000-0000-4000-8000-000000000023', 'b0000000-0000-4000-8000-000000000015', '14:00', '19:00', null,    'reservation', null),
    ('b0000000-0000-4000-8000-000000000021', 'b0000000-0000-4000-8000-000000000014', '18:00', '22:00', null,    'reservation', null)
  ) as v (car_id, member_id, s, e, p, kind, fuel);
