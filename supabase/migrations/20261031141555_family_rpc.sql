-- RPCs: Familie anlegen, beitreten, Einladungscode, Geräte

-- Neue Familie mit dem Aufrufer als Admin.
create function public.create_family(p_family_name text, p_first_name text) returns jsonb
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

  insert into public.families (name, invite_code)
  values (btrim(p_family_name), private.new_invite_code())
  returning * into f;

  insert into public.members (family_id, user_id, first_name, short, role)
  values (f.id, auth.uid(), btrim(p_first_name), private.short_name(p_first_name), 'admin')
  returning * into m;

  return jsonb_build_object('family_id', f.id, 'member_id', m.id, 'invite_code', f.invite_code);
end $$;

-- Beitreten per Code. Gibt es ein noch nicht beigetretenes Mitglied mit
-- demselben Vornamen, übernimmt der Aufrufer dieses (inkl. Rolle).
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

  select * into f from public.families where invite_code = upper(btrim(p_invite_code));
  if not found then
    raise exception 'invalid_invite_code' using errcode = 'P0001';
  end if;

  select * into m from public.members
   where family_id = f.id and lower(first_name) = lower(btrim(p_first_name))
   for update;

  if found then
    if m.user_id is not null then
      raise exception 'name_taken' using errcode = 'P0001';
    end if;
    update public.members set user_id = auth.uid() where id = m.id returning * into m;
  else
    insert into public.members (family_id, user_id, first_name, short)
    values (f.id, auth.uid(), btrim(p_first_name), private.short_name(p_first_name))
    returning * into m;
  end if;

  return jsonb_build_object('family_id', f.id, 'member_id', m.id, 'role', m.role);
end $$;

-- Neuer Einladungscode (nur Admin).
create function public.regenerate_invite_code() returns text
language plpgsql security definer set search_path = ''
as $$
declare
  m public.members := private.require_member();
  code text;
begin
  if m.role <> 'admin' then
    raise exception 'admin_required' using errcode = 'P0001';
  end if;
  code := private.new_invite_code();
  update public.families set invite_code = code where id = m.family_id;
  return code;
end $$;

-- Push-Token registrieren; ein Token gehört immer genau einem Mitglied.
create function public.register_device(p_platform text, p_token text) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  m public.members := private.require_member();
begin
  insert into public.device_tokens (member_id, platform, token)
  values (m.id, p_platform, p_token)
  on conflict (platform, token)
  do update set member_id = excluded.member_id, updated_at = now();
end $$;

create function public.unregister_device(p_token text) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  m public.members := private.require_member();
begin
  delete from public.device_tokens where token = p_token and member_id = m.id;
end $$;

revoke execute on function public.create_family(text, text), public.join_family(text, text),
  public.regenerate_invite_code(), public.register_device(text, text), public.unregister_device(text)
  from public, anon;
grant execute on function public.create_family(text, text), public.join_family(text, text),
  public.regenerate_invite_code(), public.register_device(text, text), public.unregister_device(text)
  to authenticated;
