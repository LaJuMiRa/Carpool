-- Tests für Code-Raten, Mitglieder entfernen, Schadenfotos, Reservierung bearbeiten /
-- verlängern / übergeben (Kontextmenü F11), Sperre durch laufende Fahrten und Konto löschen.
-- Läuft komplett in einer Transaktion mit Rollback, hinterlässt keine Daten.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

create temp table _tap (n serial, line text) on commit drop;
create temp table _ids (k text primary key, v uuid) on commit drop;
grant all on _tap, _ids to authenticated;
grant usage on sequence _tap_n_seq to authenticated;

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
create function pg_temp.member(p_user text) returns uuid
language sql stable as $$ select id from public.members where user_id = pg_temp.id(p_user) $$;
grant execute on all functions in schema pg_temp to authenticated;

insert into _tap (line) select no_plan();

insert into auth.users (id, email, aud, role) values
  ('00000000-0000-4000-8000-000000000101', 'papa@edit.local',  'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-000000000102', 'lisa@edit.local',  'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-000000000103', 'jonas@edit.local', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-000000000104', 'rater@edit.local', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-000000000105', 'solo@edit.local',  'authenticated', 'authenticated');
insert into _ids values
  ('u_papa',  '00000000-0000-4000-8000-000000000101'),
  ('u_lisa',  '00000000-0000-4000-8000-000000000102'),
  ('u_jonas', '00000000-0000-4000-8000-000000000103'),
  ('u_rater', '00000000-0000-4000-8000-000000000104'),
  ('u_solo',  '00000000-0000-4000-8000-000000000105');

set local role authenticated;

select pg_temp.login(pg_temp.id('u_papa'));
insert into _ids select 'family', (public.create_family('Familie Edit', 'Papa') ->> 'family_id')::uuid;

-- Code-Raten ----------------------------------------------------------------
select pg_temp.login(pg_temp.id('u_rater'));
insert into _tap (line) select is(
  (select count(*) from generate_series(1, 5) i
    where public.join_family('ZZZ-ZZ' || i, 'Rater') ->> 'reason' = 'invalid_invite_code')::int, 5,
  'join_family: falsche Codes werden als Antwort gemeldet');
insert into _tap (line) select throws_ok(
  format($$ select public.join_family(%L, 'Rater') $$,
         (select invite_code from public.families where id = pg_temp.id('family'))),
  'P0001', 'too_many_attempts', 'join_family: nach 5 Fehlversuchen gesperrt, auch mit richtigem Code');

-- Beitreten -----------------------------------------------------------------
reset role;
create temp table _code on commit drop as select invite_code as code from public.families where id = (select v from _ids where k = 'family');
grant select on _code to authenticated;
set local role authenticated;

select pg_temp.login(pg_temp.id('u_lisa'));
insert into _tap (line) select is(
  (public.join_family((select code from _code), 'Lisa') ->> 'ok')::boolean, true,
  'join_family: richtiger Code meldet ok');
select pg_temp.login(pg_temp.id('u_jonas'));
select public.join_family((select code from _code), 'Jonas');

select pg_temp.login(pg_temp.id('u_papa'));
insert into public.cars (family_id, make, model, paint, nickname, primary_member_id)
values (pg_temp.id('family'), 'VW', 'Golf', 'silber', 'Radieschen', pg_temp.member('u_jonas'));
insert into public.cars (family_id, make, model, paint)
values (pg_temp.id('family'), 'Škoda', 'Octavia', 'grau');
insert into _ids select 'golf', id from public.cars where model = 'Golf' and family_id = pg_temp.id('family');
insert into _ids select 'octavia', id from public.cars where model = 'Octavia' and family_id = pg_temp.id('family');

-- Bearbeiten ----------------------------------------------------------------
select pg_temp.login(pg_temp.id('u_lisa'));
insert into _ids select 'r_lisa', (public.reserve(pg_temp.id('golf'), pg_temp.at(2, '10:00'), pg_temp.at(2, '12:00'))
                                   -> 'booking_ids' ->> 0)::uuid;
select pg_temp.login(pg_temp.id('u_jonas'));
insert into _ids select 'r_jonas', (public.reserve(pg_temp.id('golf'), pg_temp.at(2, '14:00'), pg_temp.at(2, '16:00'))
                                    -> 'booking_ids' ->> 0)::uuid;

select pg_temp.login(pg_temp.id('u_lisa'));
insert into _tap (line) select is(
  (public.check_reservation(pg_temp.id('golf'), pg_temp.at(2, '09:00'), pg_temp.at(2, '12:00'),
                            p_booking_id => pg_temp.id('r_lisa')) ->> 'ok')::boolean, true,
  'check_reservation: eigene bearbeitete Buchung ist kein Konflikt');
insert into _tap (line) select ok(
  pg_temp.id('golf') in (select id from public.free_cars(pg_temp.at(2, '10:00'), pg_temp.at(2, '12:00'),
                                                         pg_temp.id('r_lisa'))),
  'free_cars: Auto der bearbeiteten Buchung gilt als frei');
insert into _tap (line) select is(
  (public.update_booking(pg_temp.id('r_lisa'), pg_temp.id('golf'), pg_temp.at(2, '09:00'), pg_temp.at(2, '13:00'))
     ->> 'ok')::boolean, true,
  'update_booking: Zeit ändern');
insert into _tap (line) select is(
  (select ends_at from public.bookings where id = pg_temp.id('r_lisa')), pg_temp.at(2, '13:00'),
  'update_booking: neues Ende gespeichert');
insert into _tap (line) select is(
  public.update_booking(pg_temp.id('r_lisa'), pg_temp.id('golf'), pg_temp.at(2, '09:00'), pg_temp.at(2, '15:00'))
     ->> 'reason', 'conflict',
  'update_booking: Überschneidung mit Jonas wird gemeldet');
insert into _tap (line) select is(
  (public.update_booking(pg_temp.id('r_lisa'), pg_temp.id('golf'), pg_temp.at(2, '09:00'), pg_temp.at(2, '15:00'))
     -> 'free_car_ids' ->> 0)::uuid, pg_temp.id('octavia'),
  'update_booking: freie Autos zum Tauschen');
insert into _tap (line) select is(
  (public.update_booking(pg_temp.id('r_lisa'), pg_temp.id('octavia'), pg_temp.at(2, '09:00'), pg_temp.at(2, '15:00'))
     ->> 'ok')::boolean, true,
  'update_booking: Auto tauschen');
insert into _tap (line) select throws_ok(
  format($$ select public.update_booking(%L, %L, %L, %L) $$, pg_temp.id('r_jonas'), pg_temp.id('golf'),
         pg_temp.at(2, '14:00'), pg_temp.at(2, '17:00')),
  'P0001', 'not_owner', 'update_booking: nur eigene Buchungen');

-- Hauptnutzer übernimmt beim Bearbeiten (Jonas ist Hauptnutzer vom Golf).
select pg_temp.login(pg_temp.id('u_lisa'));
insert into _ids select 'r_lisa2', (public.reserve(pg_temp.id('golf'), pg_temp.at(3, '10:00'), pg_temp.at(3, '12:00'))
                                    -> 'booking_ids' ->> 0)::uuid;
select pg_temp.login(pg_temp.id('u_jonas'));
insert into _ids select 'r_jonas2', (public.reserve(pg_temp.id('octavia'), pg_temp.at(3, '10:00'), pg_temp.at(3, '12:00'))
                                     -> 'booking_ids' ->> 0)::uuid;
insert into _tap (line) select is(
  (public.update_booking(pg_temp.id('r_jonas2'), pg_temp.id('golf'), pg_temp.at(3, '10:00'), pg_temp.at(3, '12:00'),
                         p_displace => true) ->> 'displaced_count')::int, 1,
  'update_booking: Hauptnutzer übernimmt beim Bearbeiten');
reset role;
insert into _tap (line) select is(
  (select (payload ->> 'replacement_car_id')::uuid from public.notifications
    where kind = 'booking_displaced' and payload ->> 'booking_id' = pg_temp.id('r_lisa2')::text),
  pg_temp.id('octavia'),
  'update_booking: Verdrängte bekommt das Auto, das durch das Bearbeiten frei wird');
set local role authenticated;

-- Verlängern ----------------------------------------------------------------
insert into _tap (line) select is(
  (public.extend_booking(pg_temp.id('r_jonas'), pg_temp.at(2, '17:00')) ->> 'ok')::boolean, true,
  'extend_booking: Reservierung verlängern');
select pg_temp.login(pg_temp.id('u_lisa'));
insert into _ids select 'r_lisa3', (public.reserve(pg_temp.id('golf'), pg_temp.at(2, '17:30'), pg_temp.at(2, '19:00'))
                                    -> 'booking_ids' ->> 0)::uuid;
select pg_temp.login(pg_temp.id('u_jonas'));
insert into _tap (line) select is(
  public.extend_booking(pg_temp.id('r_jonas'), pg_temp.at(2, '18:00')) -> 'conflicts' -> 0 ->> 'first_name', 'Lisa',
  'extend_booking: Konflikt nennt die Person');
insert into _tap (line) select throws_ok(
  format($$ select public.extend_booking(%L, %L) $$, pg_temp.id('r_jonas'), pg_temp.at(2, '16:30')),
  'P0001', 'invalid_range', 'extend_booking: neues Ende muss später sein');

select public.take_car(pg_temp.id('octavia'));
insert into _tap (line) select is(
  (public.extend_booking((select id from public.bookings where member_id = pg_temp.member('u_jonas')
                           and status = 'active' and ends_at is null), now() + interval '2 hours') ->> 'ok')::boolean,
  true, 'extend_booking: laufende Fahrt bekommt geplantes Ende');
insert into _tap (line) select ok(
  (select planned_ends_at is not null from public.bookings
    where member_id = pg_temp.member('u_jonas') and status = 'active' and ends_at is null),
  'extend_booking: geplantes Ende gespeichert');

-- Übergeben -----------------------------------------------------------------
select pg_temp.login(pg_temp.id('u_lisa'));
insert into _tap (line) select is(
  (public.transfer_booking(pg_temp.id('r_lisa3'), pg_temp.member('u_papa')) ->> 'ok')::boolean, true,
  'transfer_booking: an Papa übergeben');
insert into _tap (line) select is(
  (select member_id from public.bookings where id = pg_temp.id('r_lisa3')), pg_temp.member('u_papa'),
  'transfer_booking: Buchung gehört Papa');
reset role;
insert into _tap (line) select is(
  (select count(*) from public.notifications
    where kind = 'booking_transferred' and member_id = pg_temp.member('u_papa'))::int, 1,
  'transfer_booking: Papa bekommt eine Nachricht');
set local role authenticated;
select pg_temp.login(pg_temp.id('u_lisa'));
insert into _tap (line) select throws_ok(
  format($$ select public.transfer_booking(%L, %L) $$, pg_temp.id('r_lisa3'), pg_temp.member('u_jonas')),
  'P0001', 'not_owner', 'transfer_booking: übergebene Buchung gehört nicht mehr mir');

-- Mitglieder entfernen ------------------------------------------------------
insert into _tap (line) select throws_ok(
  format($$ select public.remove_member(%L) $$, pg_temp.member('u_jonas')),
  'P0001', 'admin_required', 'remove_member: nur Admins');
select pg_temp.login(pg_temp.id('u_papa'));
insert into _tap (line) select throws_ok(
  format($$ select public.remove_member(%L) $$, pg_temp.member('u_papa')),
  'P0001', 'cannot_remove_self', 'remove_member: nicht sich selbst');
insert into _tap (line) select throws_ok(
  format($$ select public.remove_member(%L) $$, pg_temp.member('u_jonas')),
  'P0001', 'member_driving', 'remove_member: nicht während einer Fahrt');
insert into _ids select 'm_lisa', pg_temp.member('u_lisa');
insert into _tap (line) select ok(
  (public.remove_member(pg_temp.id('m_lisa')) ->> 'cancelled_count')::int >= 1,
  'remove_member: künftige Reservierungen werden storniert');
insert into _tap (line) select ok(
  (select removed_at is not null and user_id is null from public.members where id = pg_temp.id('m_lisa')),
  'remove_member: Mitglied bleibt als entfernt erhalten');
select pg_temp.login(pg_temp.id('u_lisa'));
insert into _tap (line) select throws_ok(
  $$ select public.take_car((select id from public.cars limit 1)) $$,
  'P0001', 'not_a_member', 'remove_member: Entfernte hat keinen Zugriff mehr');
insert into _tap (line) select is(
  (public.join_family((select code from _code), 'Lisa') ->> 'member_id')::uuid, pg_temp.id('m_lisa'),
  'join_family: Entfernte kann wieder beitreten und bekommt ihr altes Mitglied');

-- Schadenfotos --------------------------------------------------------------
select pg_temp.login(pg_temp.id('u_jonas'));
insert into public.damages (car_id, description, photo_path, drivable)
values (pg_temp.id('golf'), 'Kratzer', pg_temp.id('family') || '/x.jpg', true);
insert into _tap (line) select lives_ok(
  $$ update public.damages set resolved_at = now(), photo_path = null where description = 'Kratzer' $$,
  'Schäden: Erledigt entfernt den Fotopfad');
insert into _tap (line) select ok(
  (select polname from pg_policy where polname = 'damage_photos_delete'
     and pg_get_expr(polqual, polrelid) like '%foldername%') is not null,
  'Storage: Fotos der eigenen Familie dürfen alle löschen');

-- Laufende Fahrt blockiert das Auto -------------------------------------------
select pg_temp.login(pg_temp.id('u_papa'));
select public.take_car(pg_temp.id('golf'));
select pg_temp.login(pg_temp.id('u_lisa'));
insert into _tap (line) select is(
  public.check_reservation(pg_temp.id('golf'), now() + interval '5 minutes', now() + interval '65 minutes') ->> 'reason',
  'conflict', 'Fahrt ohne Plan: Auto ist die nächste Stunde belegt');
insert into _tap (line) select is(
  (public.check_reservation(pg_temp.id('golf'), now() + interval '70 minutes', now() + interval '2 hours') ->> 'ok')::boolean,
  true, 'Fahrt ohne Plan: danach darf man reservieren');
insert into _tap (line) select ok(
  pg_temp.id('golf') not in (select id from public.free_cars(now() + interval '5 minutes', now() + interval '1 hour')),
  'Fahrt ohne Plan: free_cars zeigt das Auto nicht');
reset role;
update public.bookings set planned_ends_at = now() - interval '1 day'
 where car_id = pg_temp.id('golf') and status = 'active' and ends_at is null;
set local role authenticated;
select pg_temp.login(pg_temp.id('u_lisa'));
insert into _tap (line) select is(
  public.check_reservation(pg_temp.id('golf'), now() + interval '5 minutes', now() + interval '65 minutes') ->> 'reason',
  'conflict', 'Überfällige Fahrt: Auto ist die nächste Stunde belegt');
reset role;
update public.bookings set planned_ends_at = now() + interval '3 hours'
 where car_id = pg_temp.id('golf') and status = 'active' and ends_at is null;
set local role authenticated;
select pg_temp.login(pg_temp.id('u_lisa'));
insert into _tap (line) select is(
  public.check_reservation(pg_temp.id('golf'), now() + interval '2 hours', now() + interval '150 minutes') ->> 'reason',
  'conflict', 'Fahrt mit Plan: belegt bis zum geplanten Ende');
insert into _tap (line) select is(
  (public.check_reservation(pg_temp.id('golf'), now() + interval '185 minutes', now() + interval '4 hours') ->> 'ok')::boolean,
  true, 'Fahrt mit Plan: danach frei');

-- Konto löschen ---------------------------------------------------------------
select pg_temp.login(pg_temp.id('u_jonas'));
insert into _tap (line) select throws_ok(
  $$ select public.delete_account() $$, 'P0001', 'member_driving', 'delete_account: nicht während einer Fahrt');
select pg_temp.login(pg_temp.id('u_papa'));
select public.return_car(4, pg_temp.id('golf'));
insert into _tap (line) select throws_ok(
  $$ select public.delete_account() $$, 'P0001', 'transfer_admin_first',
  'delete_account: letzter Admin muss erst jemand anderen zum Admin machen');
select pg_temp.login(pg_temp.id('u_lisa'));
insert into _tap (line) select is(
  (public.delete_account() ->> 'family_deleted')::boolean, false, 'delete_account: Mitglied löscht sein Konto');
reset role;
insert into _tap (line) select ok(
  (select removed_at is not null and user_id is null from public.members where id = pg_temp.id('m_lisa')),
  'delete_account: Mitglied bleibt als entfernt für alte Fahrten');
insert into _tap (line) select ok(
  not exists (select 1 from auth.users where id = pg_temp.id('u_lisa')), 'delete_account: Anmeldung ist gelöscht');
set local role authenticated;

select pg_temp.login(pg_temp.id('u_solo'));
insert into _ids select 'solo_family', (public.create_family('Solo', 'Solo') ->> 'family_id')::uuid;
insert into _tap (line) select is(
  (public.delete_account() ->> 'family_deleted')::boolean, true,
  'delete_account: einziges Mitglied löscht die ganze Familie');
reset role;
insert into _tap (line) select ok(
  not exists (select 1 from public.families where id = pg_temp.id('solo_family')),
  'delete_account: Familie ist weg');

insert into _tap (line) select * from finish();
select string_agg(line, E'\n' order by n) as tap from _tap;
rollback;
