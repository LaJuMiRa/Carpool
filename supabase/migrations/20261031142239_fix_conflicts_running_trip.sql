-- Laufende Fahrt: Obergrenze nie vor dem Start (Start per clock_timestamp()
-- kann innerhalb derselben Transaktion nach now() liegen).
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
                       greatest(coalesce(b.planned_ends_at, now()), now(), b.starts_at), '[]')
               && tstzrange(p_start, p_end)
         end
$$;

revoke execute on function private.conflicts(uuid, timestamptz, timestamptz) from public, anon, authenticated;
