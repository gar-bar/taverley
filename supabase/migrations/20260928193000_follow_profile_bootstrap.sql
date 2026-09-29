-- Repair legacy authenticated accounts that predate profile onboarding.
-- Run after 20260928190000_private_accounts_follow_requests.sql.

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
  requester_username text;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required';
  end if;
  if target_user = auth.uid() then
    raise exception 'You cannot follow yourself';
  end if;

  -- Accounts created by the app keep their selected username in Auth metadata.
  -- Backfill a missing legacy profile before the foreign key is evaluated.
  if not exists (select 1 from public.profiles as pr where pr.id = auth.uid()) then
    select lower(btrim(au.raw_user_meta_data ->> 'username')) into requester_username
    from auth.users as au
    where au.id = auth.uid();

    if requester_username is null
      or char_length(requester_username) not between 3 and 30
      or requester_username !~ '^[a-z0-9._]+$'
      or exists (select 1 from public.profiles as pr where pr.username::text = requester_username) then
      raise exception 'Create a profile before following people';
    end if;

    insert into public.profiles (id, display_name, username)
    values (auth.uid(), requester_username, requester_username);
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
