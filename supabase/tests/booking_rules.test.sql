-- Tests für Belegungsregeln, Verdrängen, Rückgängig, Serien und RLS.
-- Läuft komplett in einer Transaktion mit Rollback, hinterlässt keine Daten.
-- Ausführen: Inhalt per Supabase-Connector (execute_sql) oder psql einspielen;
-- Ergebnis ist die TAP-Ausgabe der letzten Abfrage.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

create temp table _tap (n serial, line text) on commit drop;
create temp table _ids (k text primary key, v uuid) on commit drop;
create temp table _code (code text) on commit drop;
grant all on _tap, _ids, _code to authenticated;
grant usage on sequence _tap_n_seq to authenticated;

-- Zeitpunkt in Wiener Ortszeit: Tag relativ zu heute + Uhrzeit.
create function pg_temp.at(p_day int, p_time text) returns timestamptz
language sql stable as $$
  select (((now() at time zone 'Europe/Vienna')::date + p_day) + p_time::time) at time zone 'Europe/Vienna'
$$;
create function pg_temp.id(p_key text) returns uuid
language sql stable as $$ select v from _ids where k = p_key $$;
create function pg_temp.login(p_user uuid) returns void
language sql as $$
  select set_config('request.jwt.claims',
                    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  select null::void
$$;
grant execute on all functions in schema pg_temp to authenticated;

insert into _tap (line) select no_plan();

-- Fixtures ------------------------------------------------------------------
insert into auth.users (id, email, aud, role) values
  ('00000000-0000-4000-8000-000000000001', 'papa@test.local',  'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-000000000002', 'mama@test.local',  'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-000000000003', 'lisa@test.local',  'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-000000000004', 'jonas@test.local', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-000000000009', 'fremd@test.local', 'authenticated', 'authenticated');
insert into _ids values
  ('u_papa',  '00000000-0000-4000-8000-000000000001'),
  ('u_mama',  '00000000-0000-4000-8000-000000000002'),
  ('u_lisa',  '00000000-0000-4000-8000-000000000003'),
  ('u_jonas', '00000000-0000-4000-8000-000000000004'),
  ('u_fremd', '00000000-0000-4000-8000-000000000009');

set local role authenticated;

-- Familie -------------------------------------------------------------------
select pg_temp.login(pg_temp.id('u_papa'));
insert into _ids select 'family', (public.create_family('Familie Test', 'Papa') ->> 'family_id')::uuid;
insert into _tap (line) select is(
  (select role from public.members where user_id = pg_temp.id('u_papa')), 'admin',
  'create_family: Gründer ist Admin');
insert into _tap (line) select ok(
  (select invite_code ~ '^[A-Z0-9]{3}-[A-Z0-9]{3}$' from public.families where id = pg_temp.id('family')),
  'create_family: Einladungscode im Format K7P-2QX');
insert into _tap (line) select throws_ok(
  $$ select public.create_family('Zweite', 'Papa') $$, 'P0001', 'already_member',
  'create_family: nur eine Familie pro Konto');

insert into _code select invite_code from public.families where id = pg_temp.id('family');

select pg_temp.login(pg_temp.id('u_lisa'));
insert into _tap (line) select throws_ok(
  $$ select public.join_family('XXX-XXX', 'Lisa') $$, 'P0001', 'invalid_invite_code',
  'join_family: falscher Code wird abgelehnt');
insert into _tap (line) select lives_ok(
  format($$ select public.join_family(%L, 'Lisa') $$,
         lower((select code from _code))),
  'join_family: Code ohne Beachtung der Groß-/Kleinschreibung');
insert into _tap (line) select is(
  (select short from public.members where user_id = pg_temp.id('u_lisa')), 'Li',
  'join_family: Kürzel aus dem Vornamen');

select pg_temp.login(pg_temp.id('u_mama'));
select public.join_family((select code from _code), 'Mama');
select pg_temp.login(pg_temp.id('u_jonas'));
select public.join_family((select code from _code), 'Jonas');

-- Einen Namen gibt es nur einmal, ein bereits beigetretenes Mitglied bleibt vergeben.
select pg_temp.login(pg_temp.id('u_fremd'));
insert into _tap (line) select throws_ok(
  format($$ select public.join_family(%L, 'lisa') $$, (select code from _code)),
  'P0001', 'name_taken', 'join_family: vergebener Name wird abgelehnt');

-- Autos ---------------------------------------------------------------------
select pg_temp.login(pg_temp.id('u_papa'));
insert into public.cars (family_id, make, model, paint, nickname, primary_member_id)
values (pg_temp.id('family'), 'VW', 'Golf', 'silber', 'Radieschen',
        (select id from public.members where user_id = pg_temp.id('u_papa')));
insert into public.cars (family_id, make, model, paint)
values (pg_temp.id('family'), 'Škoda', 'Octavia', 'dunkelgrau');
insert into public.cars (family_id, make, model, paint, nickname, primary_member_id)
values (pg_temp.id('family'), 'Toyota', 'Yaris', 'blau', 'Flitzer',
        (select id from public.members where user_id = pg_temp.id('u_jonas')));
insert into _ids select 'golf', id from public.cars where model = 'Golf';
insert into _ids select 'octavia', id from public.cars where model = 'Octavia';
insert into _ids select 'yaris', id from public.cars where model = 'Yaris';

insert into _tap (line) select results_eq(
  $$ select color_slot from public.cars order by color_slot $$, array[1, 2, 3],
  'Autos: Kalenderfarben werden fortlaufend vergeben');

select pg_temp.login(pg_temp.id('u_lisa'));
insert into _tap (line) select throws_ok(
  format($$ insert into public.cars (family_id, make, model, paint) values (%L, 'Fiat', 'Panda', 'rot') $$,
         pg_temp.id('family')),
  '42501', null, 'RLS: nur Admins legen Autos an');
insert into _tap (line) select throws_ok(
  format($$ insert into public.bookings (family_id, car_id, member_id, starts_at, kind)
            values (%L, %L, %L, now(), 'trip') $$,
         pg_temp.id('family'), pg_temp.id('golf'),
         (select id from public.members where user_id = pg_temp.id('u_lisa'))),
  '42501', null, 'RLS: Buchungen nie direkt, nur per RPC');
insert into _tap (line) select throws_ok(
  $$ update public.members set role = 'admin' where user_id = auth.uid() $$,
  'P0001', 'admin_required', 'Mitglieder: Rolle ändern nur Admins');

-- Fremde Familie sieht nichts.
select pg_temp.login(pg_temp.id('u_fremd'));
select public.create_family('Familie Fremd', 'Fremd');
insert into _tap (line) select is(
  (select count(*) from public.cars)::int, 0, 'RLS: fremde Familie sieht keine Autos');
insert into _tap (line) select is(
  (select count(*) from public.members)::int, 1, 'RLS: fremde Familie sieht nur sich selbst');
insert into _tap (line) select throws_ok(
  format($$ select public.take_car(%L) $$, pg_temp.id('golf')),
  'P0001', 'car_not_found', 'take_car: Auto einer fremden Familie');
insert into _tap (line) select throws_ok(
  $$ update public.members set role = 'member' where user_id = auth.uid() $$,
  'P0001', 'last_admin', 'Mitglieder: letzter Admin bleibt Admin');

-- Nehmen / Zurückgeben / Rückgängig ----------------------------------------
select pg_temp.login(pg_temp.id('u_lisa'));
insert into _tap (line) select is(
  (public.take_car(pg_temp.id('golf')) ->> 'ok')::boolean, true, 'take_car: freies Auto nehmen');
insert into _tap (line) select throws_ok(
  format($$ select public.take_car(%L) $$, pg_temp.id('octavia')),
  'P0001', 'already_driving', 'take_car: nur eine laufende Fahrt pro Person');

select pg_temp.login(pg_temp.id('u_mama'));
insert into _tap (line) select throws_ok(
  format($$ select public.take_car(%L) $$, pg_temp.id('golf')),
  'P0001', 'car_busy', 'take_car: Auto ist unterwegs');

select pg_temp.login(pg_temp.id('u_lisa'));
insert into _tap (line) select throws_ok(
  $$ select public.return_car(5) $$, 'P0001', 'invalid_fuel', 'return_car: Tankstand nur 1–4');
select public.return_car(2);
insert into _tap (line) select is(
  (select fuel_quarters from public.cars where id = pg_temp.id('golf')), 2,
  'return_car: Tankstand wird übernommen');
insert into _tap (line) select is(
  (select status from public.bookings where car_id = pg_temp.id('golf') order by created_at desc limit 1),
  'completed', 'return_car: Fahrt ist abgeschlossen');

insert into _tap (line) select is(
  public.undo_last_action() ->> 'kind', 'return', 'undo: Zurückgeben rückgängig');
insert into _tap (line) select ok(
  exists (select 1 from public.bookings
           where car_id = pg_temp.id('golf') and status = 'active' and ends_at is null),
  'undo: Fahrt läuft wieder');
insert into _tap (line) select is(
  (select fuel_quarters from public.cars where id = pg_temp.id('golf')), 4,
  'undo: Tankstand wieder wie vorher');
select public.return_car(3);

select pg_temp.login(pg_temp.id('u_jonas'));
select public.take_car(pg_temp.id('yaris'));
select public.undo_last_action();
insert into _tap (line) select is(
  (select status from public.bookings where car_id = pg_temp.id('yaris') order by created_at desc limit 1),
  'cancelled', 'undo: Nehmen rückgängig storniert die Fahrt');
insert into _tap (line) select throws_ok(
  $$ select public.undo_last_action() $$, 'P0001', 'nothing_to_undo',
  'undo: nichts mehr rückgängig zu machen');

-- Rückgängig nur innerhalb des Zeitfensters.
select public.take_car(pg_temp.id('yaris'));
reset role;
update private.member_actions set created_at = clock_timestamp() - interval '1 minute'
 where member_id = (select id from public.members where user_id = pg_temp.id('u_jonas'));
set local role authenticated;
insert into _tap (line) select throws_ok(
  $$ select public.undo_last_action() $$, 'P0001', 'nothing_to_undo',
  'undo: nach Ablauf des Zeitfensters nicht mehr möglich');
select public.return_car(4);

-- Reservieren & Konflikte ---------------------------------------------------
select pg_temp.login(pg_temp.id('u_mama'));
insert into _ids select 'r_mama', (public.reserve(pg_temp.id('golf'), pg_temp.at(1, '10:00'),
                                                  pg_temp.at(1, '12:00')) -> 'booking_ids' ->> 0)::uuid;
insert into _tap (line) select isnt(pg_temp.id('r_mama'), null, 'reserve: freies Auto reservieren');

select pg_temp.login(pg_temp.id('u_lisa'));
insert into _tap (line) select is(
  public.check_reservation(pg_temp.id('golf'), pg_temp.at(1, '11:00'), pg_temp.at(1, '13:00')) ->> 'reason',
  'conflict', 'check_reservation: Überschneidung erkannt');
insert into _tap (line) select is(
  public.reserve(pg_temp.id('golf'), pg_temp.at(1, '11:00'), pg_temp.at(1, '13:00')) -> 'conflicts' -> 0 ->> 'first_name',
  'Mama', 'reserve: Konflikt nennt, wer das Auto hat');
insert into _tap (line) select is(
  jsonb_array_length(public.reserve(pg_temp.id('golf'), pg_temp.at(1, '11:00'), pg_temp.at(1, '13:00')) -> 'free_car_ids'),
  2, 'reserve: alle freien Autos im Zeitraum werden angeboten');
insert into _tap (line) select is(
  (select count(*) from public.bookings where member_id = (select id from public.members where user_id = pg_temp.id('u_lisa'))
     and kind = 'reservation')::int,
  0, 'reserve: bei Konflikt wird nichts gebucht');
insert into _tap (line) select is(
  (public.reserve(pg_temp.id('golf'), pg_temp.at(1, '12:00'), pg_temp.at(1, '13:00')) ->> 'ok')::boolean,
  true, 'reserve: direkt anschließend ist erlaubt');
insert into _tap (line) select throws_ok(
  format($$ select public.reserve(%L, %L, %L) $$, pg_temp.id('golf'), pg_temp.at(1, '13:00'), pg_temp.at(1, '12:00')),
  'P0001', 'invalid_range', 'reserve: Ende vor Beginn');
insert into _tap (line) select throws_ok(
  format($$ select public.reserve(%L, %L, %L) $$, pg_temp.id('golf'), pg_temp.at(-1, '10:00'), pg_temp.at(-1, '12:00')),
  'P0001', 'starts_in_past', 'reserve: nicht in der Vergangenheit');
insert into _tap (line) select results_eq(
  format($$ select model from public.free_cars(%L, %L) $$, pg_temp.at(1, '10:30'), pg_temp.at(1, '11:30')),
  array['Octavia', 'Yaris'], 'free_cars: liefert nur freie Autos');

reset role;
insert into _tap (line) select throws_ok(
  format($$ insert into public.bookings (family_id, car_id, member_id, starts_at, ends_at, kind)
            values (%L, %L, %L, %L, %L, 'reservation') $$,
         pg_temp.id('family'), pg_temp.id('golf'),
         (select id from public.members where user_id = pg_temp.id('u_jonas')),
         pg_temp.at(1, '11:00'), pg_temp.at(1, '11:30')),
  '23P01', null, 'Constraint: Überschneidung ist in der Datenbank ausgeschlossen');
set local role authenticated;

-- Verdrängen ----------------------------------------------------------------
select pg_temp.login(pg_temp.id('u_lisa'));
insert into _tap (line) select is(
  public.reserve(pg_temp.id('golf'), pg_temp.at(1, '10:00'), pg_temp.at(1, '11:00'), p_displace => true) ->> 'reason',
  'not_displaceable', 'displace: nur der Hauptnutzer darf verdrängen');

select pg_temp.login(pg_temp.id('u_papa'));
insert into _tap (line) select is(
  (public.reserve(pg_temp.id('golf'), pg_temp.at(1, '10:30'), pg_temp.at(1, '11:30'), p_displace => true) ->> 'displaced_count')::int,
  1, 'displace: Hauptnutzer übernimmt fremde Reservierung');

reset role;
insert into _tap (line) select is(
  (select status from public.bookings where id = pg_temp.id('r_mama')), 'displaced',
  'displace: Reservierung ist verdrängt');
insert into _tap (line) select is(
  (select displaced_by from public.bookings where id = pg_temp.id('r_mama')),
  (select id from public.members where user_id = pg_temp.id('u_papa')),
  'displace: verdrängt durch Hauptnutzer');
insert into _tap (line) select ok(
  exists (select 1 from public.notifications
           where kind = 'booking_displaced'
             and member_id = (select id from public.members where user_id = pg_temp.id('u_mama'))
             and payload ->> 'replacement_car_id' is not null),
  'displace: Verdrängte bekommt Nachricht mit Ersatzauto');
set local role authenticated;

-- Ohne Ersatzauto: erst Warnung, nach Bestätigung trotzdem.
select pg_temp.login(pg_temp.id('u_mama'));
insert into _ids select 'r_mama2', (public.reserve(pg_temp.id('golf'), pg_temp.at(2, '10:00'),
                                                   pg_temp.at(2, '12:00')) -> 'booking_ids' ->> 0)::uuid;
select public.reserve(pg_temp.id('octavia'), pg_temp.at(2, '09:00'), pg_temp.at(2, '13:00'));
select pg_temp.login(pg_temp.id('u_lisa'));
select public.reserve(pg_temp.id('yaris'), pg_temp.at(2, '09:00'), pg_temp.at(2, '13:00'));

select pg_temp.login(pg_temp.id('u_papa'));
insert into _tap (line) select is(
  public.reserve(pg_temp.id('golf'), pg_temp.at(2, '10:00'), pg_temp.at(2, '12:00'), p_displace => true) ->> 'reason',
  'no_replacement', 'displace: Warnung, wenn kein Ersatzauto frei ist');
insert into _tap (line) select is(
  (select status from public.bookings where id = pg_temp.id('r_mama2')), 'active',
  'displace: ohne Bestätigung bleibt die Reservierung');
insert into _tap (line) select is(
  (public.displace(pg_temp.id('r_mama2'), p_accept_no_replacement => true) ->> 'replacement_found')::boolean,
  false, 'displace: nach Bestätigung trotzdem übernommen, ohne Ersatz');

-- Laufende Fahrt kann nie verdrängt werden.
select pg_temp.login(pg_temp.id('u_lisa'));
insert into _ids select 'trip_lisa', (public.take_car(pg_temp.id('golf')) ->> 'booking_id')::uuid;
select pg_temp.login(pg_temp.id('u_papa'));
insert into _tap (line) select throws_ok(
  format($$ select public.displace(%L, true) $$, pg_temp.id('trip_lisa')),
  'P0001', 'not_displaceable', 'displace: laufende Fahrt nie verdrängbar');
insert into _tap (line) select is(
  public.reserve(pg_temp.id('golf'), now(), now() + interval '1 hour', p_displace => true) ->> 'reason',
  'not_displaceable', 'reserve: laufende Fahrt blockiert auch für den Hauptnutzer');
select pg_temp.login(pg_temp.id('u_lisa'));
select public.return_car(4);

-- Eigene Reservierung wird beim Nehmen zur Fahrt.
select pg_temp.login(pg_temp.id('u_mama'));
insert into _ids select 'r_soon', (public.reserve(pg_temp.id('octavia'), now() + interval '5 minutes',
                                                  now() + interval '2 hours') -> 'booking_ids' ->> 0)::uuid;
insert into _tap (line) select is(
  (public.take_car(pg_temp.id('octavia')) ->> 'from_reservation')::boolean, true,
  'take_car: eigene Reservierung wird zur Fahrt');
insert into _tap (line) select ok(
  (select planned_ends_at is not null and kind = 'trip' from public.bookings where id = pg_temp.id('r_soon')),
  'take_car: geplantes Ende bleibt erhalten');

-- Rückgabe benachrichtigt die nächste Person, Rückgängig holt das zurück.
select pg_temp.login(pg_temp.id('u_jonas'));
select public.reserve(pg_temp.id('octavia'), pg_temp.at(3, '08:00'), pg_temp.at(3, '09:00'));
select pg_temp.login(pg_temp.id('u_mama'));
select public.return_car(1);
reset role;
insert into _tap (line) select ok(
  exists (select 1 from public.notifications
           where kind = 'car_free' and sent_at is null and send_after > now()
             and member_id = (select id from public.members where user_id = pg_temp.id('u_jonas'))),
  'return_car: nächste Person wird (verzögert) benachrichtigt');
set local role authenticated;
select public.undo_last_action();
reset role;
insert into _tap (line) select ok(
  not exists (select 1 from public.notifications
               where kind = 'car_free'
                 and member_id = (select id from public.members where user_id = pg_temp.id('u_jonas'))),
  'undo: Benachrichtigung wird zurückgezogen');
set local role authenticated;
select public.return_car(1);

-- Fremde laufende Reservierung blockiert das Nehmen.
reset role;
insert into public.bookings (family_id, car_id, member_id, starts_at, ends_at, kind)
values (pg_temp.id('family'), pg_temp.id('yaris'),
        (select id from public.members where user_id = pg_temp.id('u_jonas')),
        now() - interval '10 minutes', now() + interval '1 hour', 'reservation');
set local role authenticated;
select pg_temp.login(pg_temp.id('u_lisa'));
insert into _tap (line) select throws_ok(
  format($$ select public.take_car(%L) $$, pg_temp.id('yaris')),
  'P0001', 'car_reserved', 'take_car: Auto ist gerade für jemand anderen reserviert');

-- Stornieren ----------------------------------------------------------------
insert into _tap (line) select throws_ok(
  format($$ select public.cancel_booking(%L) $$, pg_temp.id('r_mama2')),
  'P0001', 'not_owner', 'cancel_booking: nur eigene Reservierungen');

-- Serien --------------------------------------------------------------------
select pg_temp.login(pg_temp.id('u_jonas'));
insert into _ids
select 'series_first', (r -> 'booking_ids' ->> 0)::uuid
  from (select public.reserve(
          pg_temp.id('yaris'),
          (((date_trunc('week', now() at time zone 'Europe/Vienna') + interval '14 days')::date + time '07:00')
             at time zone 'Europe/Vienna'),
          (((date_trunc('week', now() at time zone 'Europe/Vienna') + interval '14 days')::date + time '17:00')
             at time zone 'Europe/Vienna'),
          p_rrule => 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH',
          p_until => (date_trunc('week', now() at time zone 'Europe/Vienna') + interval '32 days')::date) r) x;
insert into _tap (line) select is(
  (select count(*) from public.bookings where series_id is not null and status = 'active')::int, 12,
  'Serie: Mo–Do über drei Wochen ergibt 12 Termine');
insert into _tap (line) select is(
  (select to_char(starts_at at time zone 'Europe/Vienna', 'HH24:MI') from public.bookings
    where id = pg_temp.id('series_first')),
  '07:00', 'Serie: Uhrzeit in Wiener Ortszeit');

select pg_temp.login(pg_temp.id('u_lisa'));
insert into _tap (line) select is(
  public.check_reservation(
    pg_temp.id('yaris'),
    (((date_trunc('week', now() at time zone 'Europe/Vienna') + interval '15 days')::date + time '08:00')
       at time zone 'Europe/Vienna'),
    (((date_trunc('week', now() at time zone 'Europe/Vienna') + interval '15 days')::date + time '09:00')
       at time zone 'Europe/Vienna')) ->> 'reason',
  'conflict', 'Serie: Termine blockieren wie normale Reservierungen');
insert into _tap (line) select throws_ok(
  format($$ select public.reserve(%L, %L, %L, p_rrule => 'FREQ=DAILY') $$,
         pg_temp.id('octavia'), pg_temp.at(1, '07:00'), pg_temp.at(1, '08:00')),
  'P0001', 'invalid_rrule', 'Serie: nur wöchentliche Regeln');

select pg_temp.login(pg_temp.id('u_jonas'));
insert into _tap (line) select is(
  (public.cancel_booking(pg_temp.id('series_first'), p_whole_series => true) ->> 'cancelled_count')::int, 12,
  'Serie: ganze Serie stornieren');

reset role;
insert into _tap (line) select lives_ok(
  $$ select private.materialize_series() $$, 'Cron: Materialisierung läuft fehlerfrei');

insert into _tap (line) select * from finish();
select string_agg(line, E'\n' order by n) as tap from _tap;
rollback;
