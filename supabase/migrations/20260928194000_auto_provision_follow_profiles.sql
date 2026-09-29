-- Automatically provision a social profile for authenticated legacy accounts.
-- Run after 20260928193000_follow_profile_bootstrap.sql.

create or replace function public.request_follow(target_user uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_is_private boolean;
  next_status text;
  saved_status text;
  requested_username text;
  fallback_username text;
  suffix integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required';
  end if;
  if target_user = auth.uid() then
    raise exception 'You cannot follow yourself';
  end if;

  -- Older accounts may have Auth credentials but no row in profiles. Create a
  -- stable social identity automatically; no extra setup step is required.
  if not exists (select 1 from public.profiles as pr where pr.id = auth.uid()) then
    select coalesce(au.raw_user_meta_data ->> 'username', split_part(au.email, '@', 1))
      into requested_username
    from auth.users as au
    where au.id = auth.uid();

    requested_username := lower(regexp_replace(coalesce(requested_username, ''), '[^a-z0-9._]', '', 'g'));
    if char_length(requested_username) not between 3 and 30 then
      requested_username := 'user.' || substr(replace(auth.uid()::text, '-', ''), 1, 12);
    end if;

    fallback_username := requested_username;
    while exists (select 1 from public.profiles as pr where pr.username::text = fallback_username) loop
      suffix := suffix + 1;
      fallback_username := left(requested_username, 24) || '.' || suffix::text;
    end loop;

    insert into public.profiles (id, display_name, username)
    values (auth.uid(), fallback_username, fallback_username);
  end if;

  select pr.is_private into target_is_private
  from public.profiles as pr
  where pr.id = target_user;
  if target_is_private is null then
    raise exception 'Profile not found';
  end if;

  next_status := case when target_is_private then 'pending' else 'accepted' end;
  insert into public.user_follows (follower_id, followed_id, status, responded_at)
  values (auth.uid(), target_user, next_status, case when next_status = 'accepted' then now() else null end)
  on conflict (follower_id, followed_id) do update
    set status = case
      when public.user_follows.status = 'accepted' then 'accepted'
      else excluded.status
    end,
    responded_at = case
      when public.user_follows.status = 'accepted' then public.user_follows.responded_at
      when excluded.status = 'accepted' then now()
      else null
    end
  returning status into saved_status;

  return saved_status;
end;
$$;

revoke all on function public.request_follow(uuid) from public;
grant execute on function public.request_follow(uuid) to authenticated;
