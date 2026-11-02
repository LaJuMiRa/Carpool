-- Offene Punkte nach Phase 8: Code-Raten bremsen, Mitglieder entfernen, Schadenfotos löschen.

-- Beitreten: höchstens 5 falsche Codes in 15 Minuten je Konto ----------------------------
-- Ein falscher Code wird als Antwort {ok:false, reason:'invalid_invite_code'} gemeldet statt als
-- Exception, damit der Fehlversuch gespeichert bleibt (eine Exception rollt alles zurück).
create table private.join_attempts (
  user_id      uuid not null,
  attempted_at timestamptz not null default now()
);
create index join_attempts_user_idx on private.join_attempts (user_id, attempted_at);

create function private.join_attempt_limit() returns int
language sql immutable set search_path = '' as $$ select 5 $$;

create function private.join_attempt_window() returns interval
language sql immutable set search_path = '' as $$ select interval '15 minutes' $$;

-- Entfernte Mitglieder bleiben als Zeile erhalten (vergangene Fahrten zeigen weiter den Namen).
alter table public.members add column removed_at timestamptz;

-- Antwort: {ok:true, family_id, member_id, role} oder {ok:false, reason:'invalid_invite_code'}.
-- Gibt es ein noch nicht beigetretenes oder entferntes Mitglied mit demselben Vornamen,
-- übernimmt der Aufrufer dieses (inkl. Rolle und vergangener Fahrten).
drop function public.join_family(text, text);
create function public.join_family(p_invite_code text, p_first_name text) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  f public.families;
  m public.members;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.members where user_id = auth.uid()) then
    raise exception 'already_member' using errcode = 'P0001';
  end if;
  if (select count(*) from private.join_attempts
       where user_id = auth.uid() and attempted_at > now() - private.join_attempt_window())
     >= private.join_attempt_limit() then
    raise exception 'too_many_attempts' using errcode = 'P0001';
  end if;

  select * into f from public.families where invite_code = upper(btrim(p_invite_code));
  if not found then
    delete from private.join_attempts
     where user_id = auth.uid() and attempted_at < now() - interval '1 day';
    insert into private.join_attempts (user_id) values (auth.uid());
    return jsonb_build_object('ok', false, 'reason', 'invalid_invite_code');
  end if;

  select * into m from public.members
   where family_id = f.id and lower(first_name) = lower(btrim(p_first_name))
   for update;

  if found then
    if m.user_id is not null then
      raise exception 'name_taken' using errcode = 'P0001';
    end if;
    update public.members set user_id = auth.uid(), removed_at = null
     where id = m.id returning * into m;
  else
    insert into public.members (family_id, user_id, first_name, short)
    values (f.id, auth.uid(), btrim(p_first_name), private.short_name(p_first_name))
    returning * into m;
  end if;

  return jsonb_build_object('ok', true, 'family_id', f.id, 'member_id', m.id, 'role', m.role);
end $$;

-- Mitglied entfernen (Admin) -------------------------------------------------------------
-- Nicht sich selbst, nicht während einer laufenden Fahrt. Künftige Reservierungen und Serien
-- werden storniert, Hauptnutzer-Rollen und Geräte entfernt. Die Person landet beim nächsten
-- Öffnen der App bei „Familie beitreten".
create function public.remove_member(p_member_id uuid) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  m public.members := private.require_member();
  target public.members;
  cancelled int;
begin
  if m.role <> 'admin' then
    raise exception 'admin_required' using errcode = 'P0001';
  end if;
  select * into target from public.members
   where id = p_member_id and family_id = m.family_id and removed_at is null
   for update;
  if not found then
    raise exception 'member_not_in_family' using errcode = 'P0001';
  end if;
  if target.id = m.id then
    raise exception 'cannot_remove_self' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.bookings
              where member_id = target.id and status = 'active' and ends_at is null) then
    raise exception 'member_driving' using errcode = 'P0001';
  end if;

  update public.bookings set status = 'cancelled'
   where member_id = target.id and status = 'active' and kind = 'reservation' and ends_at > now();
  get diagnostics cancelled = row_count;
  update public.booking_series set status = 'cancelled'
   where member_id = target.id and status = 'active';
  update public.cars set primary_member_id = null where primary_member_id = target.id;
  delete from public.device_tokens where member_id = target.id;
  delete from public.notifications where member_id = target.id and sent_at is null;
  update public.members set user_id = null, role = 'member', removed_at = now()
   where id = target.id;

  return jsonb_build_object('ok', true, 'cancelled_count', cancelled);
end $$;

-- Schadenfotos: beim „Erledigt" löscht die App das Foto; das darf jedes Familienmitglied ----
drop policy damage_photos_delete on storage.objects;
create policy damage_photos_delete on storage.objects for delete to authenticated
  using (bucket_id = 'damage-photos'
         and (storage.foldername(name))[1] = (select private.my_family_id())::text);
grant update (photo_path) on public.damages to authenticated;

-- Rechte --------------------------------------------------------------------------------
revoke execute on function private.join_attempt_limit(), private.join_attempt_window()
  from public, anon, authenticated;
revoke execute on function public.join_family(text, text), public.remove_member(uuid) from public, anon;
grant execute on function public.join_family(text, text), public.remove_member(uuid) to authenticated;
