-- Carpool: Grundschema
-- Zeiten immer timestamptz (UTC), Regeln für die App siehe CLAUDE.md.

create extension if not exists btree_gist with schema extensions;

create schema if not exists private;
revoke all on schema private from public;

-- Familien ------------------------------------------------------------------
create table public.families (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 1 and 60),
  invite_code text not null unique check (invite_code ~ '^[A-Z0-9]{3}-[A-Z0-9]{3}$'),
  time_zone   text not null default 'Europe/Vienna',
  created_at  timestamptz not null default now()
);

-- Mitglieder ----------------------------------------------------------------
-- user_id ist null, solange ein angelegtes Mitglied noch nicht beigetreten ist.
create table public.members (
  id         uuid primary key default gen_random_uuid(),
  family_id  uuid not null references public.families (id) on delete cascade,
  user_id    uuid unique references auth.users (id) on delete set null,
  first_name text not null check (char_length(first_name) between 2 and 40),
  short      text not null check (char_length(short) = 2),
  role       text not null default 'member' check (role in ('admin', 'member')),
  created_at timestamptz not null default now()
);
create index members_family_idx on public.members (family_id);
create unique index members_family_first_name_key on public.members (family_id, lower(first_name));

-- Autos ---------------------------------------------------------------------
create table public.cars (
  id                uuid primary key default gen_random_uuid(),
  family_id         uuid not null references public.families (id) on delete cascade,
  make              text not null check (char_length(make) between 1 and 40),
  model             text not null check (char_length(model) between 1 and 40),
  paint             text not null check (char_length(paint) between 1 and 40),
  nickname          text check (nickname is null or char_length(nickname) between 1 and 30),
  plate             text check (plate is null or char_length(plate) between 1 and 15),
  primary_member_id uuid references public.members (id) on delete set null,
  color_slot        int not null check (color_slot >= 1),
  image_url         text,
  fuel_quarters     int not null default 4 check (fuel_quarters between 1 and 4),
  pickerl_until     date,
  service_due       date,
  odometer_km       int check (odometer_km is null or odometer_km >= 0),
  archived          boolean not null default false,
  created_at        timestamptz not null default now()
);
create index cars_family_idx on public.cars (family_id);
create index cars_primary_member_idx on public.cars (primary_member_id);

-- Wiederkehrende Serien -----------------------------------------------------
-- Nur wöchentlich, Uhrzeiten in der Zeitzone der Familie, Ende am selben Tag.
create table public.booking_series (
  id                 uuid primary key default gen_random_uuid(),
  family_id          uuid not null references public.families (id) on delete cascade,
  car_id             uuid not null references public.cars (id) on delete cascade,
  member_id          uuid not null references public.members (id) on delete cascade,
  rrule              text not null check (rrule ~ '^FREQ=WEEKLY;BYDAY=(MO|TU|WE|TH|FR|SA|SU)(,(MO|TU|WE|TH|FR|SA|SU))*$'),
  start_time         time not null,
  end_time           time not null check (end_time > start_time),
  starts_on          date not null,
  until              date check (until is null or until >= starts_on),
  materialized_until date not null,
  status             text not null default 'active' check (status in ('active', 'cancelled')),
  created_at         timestamptz not null default now()
);
create index booking_series_family_idx on public.booking_series (family_id);
create index booking_series_car_idx on public.booking_series (car_id);
create index booking_series_member_idx on public.booking_series (member_id);

-- Buchungen -----------------------------------------------------------------
-- reservation: immer mit Ende. trip: ends_at null, solange die Fahrt läuft.
-- planned_ends_at: geplantes Ende einer Fahrt, die aus einer Reservierung entstand.
create table public.bookings (
  id                      uuid primary key default gen_random_uuid(),
  family_id               uuid not null references public.families (id) on delete cascade,
  car_id                  uuid not null references public.cars (id) on delete cascade,
  member_id               uuid not null references public.members (id) on delete cascade,
  starts_at               timestamptz not null,
  ends_at                 timestamptz,
  planned_ends_at         timestamptz,
  kind                    text not null check (kind in ('reservation', 'trip')),
  series_id               uuid references public.booking_series (id) on delete set null,
  status                  text not null default 'active'
                          check (status in ('active', 'completed', 'cancelled', 'displaced')),
  displaced_by            uuid references public.members (id) on delete set null,
  fuel_quarters_on_take   int check (fuel_quarters_on_take between 1 and 4),
  fuel_quarters_on_return int check (fuel_quarters_on_return between 1 and 4),
  created_at              timestamptz not null default now(),
  constraint bookings_end_after_start check (ends_at is null or ends_at > starts_at),
  constraint bookings_open_iff_running_trip check ((kind = 'trip' and status = 'active') = (ends_at is null)),
  constraint bookings_displaced_reservation check (status <> 'displaced' or kind = 'reservation')
);
create index bookings_family_starts_idx on public.bookings (family_id, starts_at);
create index bookings_car_idx on public.bookings (car_id);
create index bookings_member_idx on public.bookings (member_id);
create index bookings_series_idx on public.bookings (series_id);
create index bookings_displaced_by_idx on public.bookings (displaced_by);

-- Keine Überschneidung aktiver Buchungen mit Ende auf demselben Auto.
alter table public.bookings
  add constraint bookings_no_overlap
  exclude using gist (car_id with =, tstzrange(starts_at, ends_at) with &&)
  where (status = 'active' and ends_at is not null);

-- Laufende Fahrten: höchstens eine je Auto und eine je Mitglied.
create unique index bookings_one_running_trip_per_car
  on public.bookings (car_id) where (status = 'active' and ends_at is null);
create unique index bookings_one_running_trip_per_member
  on public.bookings (member_id) where (status = 'active' and ends_at is null);

-- Schäden -------------------------------------------------------------------
create table public.damages (
  id          uuid primary key default gen_random_uuid(),
  family_id   uuid not null references public.families (id) on delete cascade,
  car_id      uuid not null references public.cars (id) on delete cascade,
  reported_by uuid references public.members (id) on delete set null,
  description text not null check (char_length(description) between 1 and 1000),
  photo_path  text,
  drivable    boolean not null,
  created_at  timestamptz not null default now(),
  resolved_at timestamptz
);
create index damages_family_idx on public.damages (family_id);
create index damages_car_idx on public.damages (car_id);
create index damages_reported_by_idx on public.damages (reported_by);

-- Geräte für Push -----------------------------------------------------------
create table public.device_tokens (
  member_id  uuid not null references public.members (id) on delete cascade,
  platform   text not null check (platform in ('ios', 'android')),
  token      text not null check (char_length(token) between 1 and 512),
  updated_at timestamptz not null default now(),
  primary key (platform, token)
);
create index device_tokens_member_idx on public.device_tokens (member_id);

-- Einstellungen -------------------------------------------------------------
create table public.settings (
  member_id               uuid primary key references public.members (id) on delete cascade,
  notify_car_free         boolean not null default true,
  notify_booking_displaced boolean not null default true,
  notify_reservation_soon boolean not null default true,
  notify_return_overdue   boolean not null default true,
  notify_service_pickerl  boolean not null default true,
  calendar_car_animation  text not null default 'once' check (calendar_car_animation in ('once', 'loop', 'off')),
  launch_animation        text not null default 'first' check (launch_animation in ('first', 'always'))
);

-- Benachrichtigungen (Outbox, wird von einer Edge Function verschickt) ------
create table public.notifications (
  id         uuid primary key default gen_random_uuid(),
  family_id  uuid not null references public.families (id) on delete cascade,
  member_id  uuid not null references public.members (id) on delete cascade,
  kind       text not null check (kind in ('car_free', 'booking_displaced', 'reservation_soon',
                                           'return_overdue', 'service_pickerl', 'series_occurrence_skipped')),
  payload    jsonb not null default '{}'::jsonb,
  send_after timestamptz not null default now(),
  sent_at    timestamptz,
  created_at timestamptz not null default now()
);
create index notifications_member_idx on public.notifications (member_id);
create index notifications_family_idx on public.notifications (family_id);
create index notifications_pending_idx on public.notifications (send_after) where sent_at is null;

-- Aktionen für "Rückgängig" (intern) ----------------------------------------
create table private.member_actions (
  id               uuid primary key default gen_random_uuid(),
  member_id        uuid not null references public.members (id) on delete cascade,
  kind             text not null check (kind in ('take', 'return')),
  booking_id       uuid not null references public.bookings (id) on delete cascade,
  previous         jsonb not null default '{}'::jsonb,
  notification_ids uuid[] not null default '{}',
  created_at       timestamptz not null default clock_timestamp(),
  undone_at        timestamptz
);
create index member_actions_member_idx on private.member_actions (member_id, created_at desc);
create index member_actions_booking_idx on private.member_actions (booking_id);
