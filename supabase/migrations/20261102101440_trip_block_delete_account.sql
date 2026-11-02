-- 1. Laufende Fahrt ohne (künftiges) geplantes Ende blockiert das Auto noch eine Stunde ab jetzt.
--    Vorher nur bis „jetzt": man konnte ein Auto „ab jetzt" reservieren, während es unterwegs war.
-- 2. Konto löschen (App-Store-Pflicht): Mitglied austragen bzw. Familie löschen, dann den Nutzer.

-- Laufende Fahrt ------------------------------------------------------------------------
create function private.open_trip_block() returns interval
language sql immutable set search_path = '' as $$ select interval '1 hour' $$;

-- Eine laufende Fahrt belegt das Auto bis zum geplanten Ende, wenn es noch kommt; sonst
-- (ohne Plan oder überfällig) bis jetzt + open_trip_block().
create or replace function private.conflicts(p_car_id uuid, p_start timestamptz, p_end timestamptz)
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
             tstzrange(b.starts_at,
                       greatest(case when b.planned_ends_at > now() then b.planned_ends_at
                                     else now() + private.open_trip_block() end,
                                b.starts_at), '[]')
               && tstzrange(p_start, p_end)
         end
$$;

-- Mitglied austragen (gemeinsam für remove_member und delete_account) --------------------
create function private.detach_member(p_member_id uuid) returns int
language plpgsql security definer set search_path = ''
as $$
declare
  cancelled int;
begin
  update public.bookings set status = 'cancelled'
   where member_id = p_member_id and status = 'active' and kind = 'reservation' and ends_at > now();
  get diagnostics cancelled = row_count;
  update public.booking_series set status = 'cancelled'
   where member_id = p_member_id and status = 'active';
  update public.cars set primary_member_id = null where primary_member_id = p_member_id;
  delete from public.device_tokens where member_id = p_member_id;
  delete from public.notifications where member_id = p_member_id and sent_at is null;
  update public.members set user_id = null, role = 'member', removed_at = now()
   where id = p_member_id;
  return cancelled;
end $$;

create or replace function public.remove_member(p_member_id uuid) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  m public.members := private.require_member();
  target public.members;
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
  return jsonb_build_object('ok', true, 'cancelled_count', private.detach_member(target.id));
end $$;

-- Konto löschen ---------------------------------------------------------------------------
-- Nicht während einer Fahrt. Letzter beigetretener Admin neben anderen Beigetretenen muss erst
-- jemand anderen zum Admin machen. Ist man der einzige Beigetretene, wird die Familie gelöscht.
-- Antwort {ok:true, family_deleted}.
create function public.delete_account() returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  m public.members;
  family_deleted boolean := false;
begin
  if uid is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;

  select * into m from public.members where user_id = uid for update;
  if found then
    if exists (select 1 from public.bookings
                where member_id = m.id and status = 'active' and ends_at is null) then
      raise exception 'member_driving' using errcode = 'P0001';
    end if;
    if not exists (select 1 from public.members
                    where family_id = m.family_id and id <> m.id
                      and user_id is not null and removed_at is null) then
      delete from public.families where id = m.family_id;
      family_deleted := true;
    else
      if m.role = 'admin' and not exists (
           select 1 from public.members
            where family_id = m.family_id and id <> m.id and role = 'admin'
              and user_id is not null and removed_at is null) then
        raise exception 'transfer_admin_first' using errcode = 'P0001';
      end if;
      perform private.detach_member(m.id);
    end if;
  end if;

  delete from private.join_attempts where user_id = uid;
  delete from auth.users where id = uid;
  return jsonb_build_object('ok', true, 'family_deleted', family_deleted);
end $$;

-- Rechte --------------------------------------------------------------------------------
revoke execute on function private.open_trip_block(), private.detach_member(uuid)
  from public, anon, authenticated;
revoke execute on function private.conflicts(uuid, timestamptz, timestamptz) from public, anon, authenticated;
revoke execute on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;
