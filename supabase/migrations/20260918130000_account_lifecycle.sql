-- Account onboarding, username claiming, and safe profile cascades.
-- Run after 20260918110000_collaborative_households.sql.

drop policy if exists "Users manage their own profile" on public.profiles;

drop policy if exists "Users insert their own profile" on public.profiles;
create policy "Users insert their own profile" on public.profiles
  for insert to authenticated with check (auth.uid() = id);

drop policy if exists "Users update their own profile" on public.profiles;
create policy "Users update their own profile" on public.profiles
  for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);

-- Profile deletion is intentionally not granted to clients. The delete-account
-- Edge Function removes the Auth user, which cascades through this table.

create or replace function public.is_username_available(candidate text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    char_length(lower(btrim(candidate))) between 3 and 30
    and lower(btrim(candidate)) ~ '^[a-z0-9._]+$'
    and not exists (
      select 1 from public.profiles
      where lower(username::text) = lower(btrim(candidate))
    );
$$;

revoke all on function public.is_username_available(text) from public;
grant execute on function public.is_username_available(text) to anon, authenticated;

create or replace function public.claim_username(candidate text)
returns public.profiles
language plpgsql
security invoker
set search_path = ''
as $$
declare
  normalized text := lower(btrim(candidate));
  claimed public.profiles;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if char_length(normalized) not between 3 and 30 or normalized !~ '^[a-z0-9._]+$' then
    raise exception 'Invalid username';
  end if;

  insert into public.profiles (id, display_name, username)
  values (auth.uid(), normalized, normalized)
  on conflict (id) do update
    set display_name = excluded.display_name,
        username = excluded.username,
        updated_at = now()
  returning * into claimed;
  return claimed;
exception
  when unique_violation then raise exception 'Username is already taken' using errcode = '23505';
end;
$$;

revoke all on function public.claim_username(text) from public;
grant execute on function public.claim_username(text) to authenticated;

-- Shared household content survives a contributor leaving, without retaining
-- a foreign-key reference to the deleted profile.
alter table public.household_recipes alter column created_by drop not null;
alter table public.household_recipes alter column updated_by drop not null;
alter table public.household_meal_plans alter column created_by drop not null;
alter table public.household_meal_plans alter column updated_by drop not null;
alter table public.household_calendar_meals alter column created_by drop not null;
alter table public.household_calendar_meals alter column updated_by drop not null;

alter table public.household_recipes drop constraint if exists household_recipes_created_by_fkey;
alter table public.household_recipes drop constraint if exists household_recipes_updated_by_fkey;
alter table public.household_meal_plans drop constraint if exists household_meal_plans_created_by_fkey;
alter table public.household_meal_plans drop constraint if exists household_meal_plans_updated_by_fkey;
alter table public.household_calendar_meals drop constraint if exists household_calendar_meals_created_by_fkey;
alter table public.household_calendar_meals drop constraint if exists household_calendar_meals_updated_by_fkey;

alter table public.household_recipes add constraint household_recipes_created_by_fkey foreign key (created_by) references public.profiles(id) on delete set null;
alter table public.household_recipes add constraint household_recipes_updated_by_fkey foreign key (updated_by) references public.profiles(id) on delete set null;
alter table public.household_meal_plans add constraint household_meal_plans_created_by_fkey foreign key (created_by) references public.profiles(id) on delete set null;
alter table public.household_meal_plans add constraint household_meal_plans_updated_by_fkey foreign key (updated_by) references public.profiles(id) on delete set null;
alter table public.household_calendar_meals add constraint household_calendar_meals_created_by_fkey foreign key (created_by) references public.profiles(id) on delete set null;
alter table public.household_calendar_meals add constraint household_calendar_meals_updated_by_fkey foreign key (updated_by) references public.profiles(id) on delete set null;

create or replace function public.prepare_profile_deletion()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  owned_household uuid;
  successor uuid;
begin
  -- Remove authored posts before auth.users cascades into recipes. Posts use a
  -- restrictive recipe foreign key, so this ordering keeps the cascade safe.
  delete from public.feed_posts where author_id = old.id;

  for owned_household in select id from households where owner_id = old.id for update loop
    select user_id into successor
    from household_members
    where household_id = owned_household and user_id <> old.id
    order by joined_at asc, user_id asc
    limit 1;

    if successor is null then
      delete from households where id = owned_household;
    else
      update household_members set role = 'member'
        where household_id = owned_household and user_id = old.id;
      update household_members set role = 'owner'
        where household_id = owned_household and user_id = successor;
      update households set owner_id = successor where id = owned_household;
    end if;
  end loop;
  return old;
end;
$$;

drop trigger if exists profiles_prepare_deletion on public.profiles;
create trigger profiles_prepare_deletion before delete on public.profiles
  for each row execute procedure public.prepare_profile_deletion();
