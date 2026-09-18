-- Collaborative households, invitations, shared recipes/plans, and shared calendar.
-- Run after 20260918100000_favourite_pagination_indexes.sql.

create extension if not exists pgcrypto;

create table public.households (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 80),
  owner_id uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.household_members (
  household_id uuid not null references public.households(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null check (role in ('owner', 'member')),
  joined_at timestamptz not null default now(),
  primary key (household_id, user_id),
  unique (user_id)
);

create unique index household_single_owner_idx
  on public.household_members (household_id) where role = 'owner';

create table public.household_invitations (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  inviter_id uuid not null references public.profiles(id) on delete cascade,
  invitee_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'revoked', 'expired')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '7 days'),
  responded_at timestamptz,
  check (inviter_id <> invitee_id)
);

create unique index household_pending_invitation_idx
  on public.household_invitations (household_id, invitee_id)
  where status = 'pending';
create index household_invitations_invitee_idx
  on public.household_invitations (invitee_id, created_at desc);

create table public.household_recipes (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  source_recipe_id uuid references public.recipes(id) on delete set null,
  created_by uuid not null references public.profiles(id) on delete restrict default auth.uid(),
  updated_by uuid not null references public.profiles(id) on delete restrict default auth.uid(),
  version integer not null default 1 check (version > 0),
  payload jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (household_id, source_recipe_id)
);

create table public.household_meal_plans (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  source_plan_id uuid references public.meal_plans(id) on delete set null,
  created_by uuid not null references public.profiles(id) on delete restrict default auth.uid(),
  updated_by uuid not null references public.profiles(id) on delete restrict default auth.uid(),
  version integer not null default 1 check (version > 0),
  payload jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (household_id, source_plan_id)
);

create table public.household_plan_meals (
  id uuid primary key,
  plan_id uuid not null references public.household_meal_plans(id) on delete cascade,
  household_id uuid not null references public.households(id) on delete cascade,
  week integer not null check (week > 0),
  weekday integer not null check (weekday between 1 and 7),
  meal_type text not null check (meal_type in ('Breakfast', 'Snack', 'Lunch', 'Second Snack', 'Dinner')),
  recipe_id uuid not null references public.household_recipes(id) on delete restrict,
  meal_order integer not null default 0,
  unique (plan_id, week, weekday, meal_type)
);

create table public.household_calendar_meals (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  meal_date date not null,
  meal_type text not null check (meal_type in ('Breakfast', 'Snack', 'Lunch', 'Second Snack', 'Dinner')),
  recipe_id uuid not null references public.household_recipes(id) on delete restrict,
  assignment_id uuid,
  created_by uuid not null references public.profiles(id) on delete restrict default auth.uid(),
  updated_by uuid not null references public.profiles(id) on delete restrict default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (household_id, meal_date, meal_type)
);

create index household_recipes_household_idx on public.household_recipes (household_id, updated_at desc);
create index household_plans_household_idx on public.household_meal_plans (household_id, updated_at desc);
create index household_calendar_range_idx on public.household_calendar_meals (household_id, meal_date);
create index household_plan_meals_recipe_idx on public.household_plan_meals (recipe_id);

create or replace function public.is_household_member(target_household uuid, target_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.household_members
    where household_id = target_household and user_id = target_user
  );
$$;

create or replace function public.is_household_owner(target_household uuid, target_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.households
    where id = target_household and owner_id = target_user
  );
$$;

revoke all on function public.is_household_member(uuid, uuid) from public;
revoke all on function public.is_household_owner(uuid, uuid) from public;
grant execute on function public.is_household_member(uuid, uuid) to authenticated;
grant execute on function public.is_household_owner(uuid, uuid) to authenticated;

create or replace function public.bump_household_content_version()
returns trigger language plpgsql set search_path = public as $$
begin
  new.version = old.version + 1;
  new.updated_at = now();
  new.updated_by = auth.uid();
  return new;
end;
$$;

create trigger household_recipes_version before update on public.household_recipes
  for each row execute procedure public.bump_household_content_version();
create trigger household_plans_version before update on public.household_meal_plans
  for each row execute procedure public.bump_household_content_version();
create trigger households_updated_at before update on public.households
  for each row execute procedure public.set_updated_at();
create trigger household_calendar_updated_at before update on public.household_calendar_meals
  for each row execute procedure public.set_updated_at();

alter table public.households enable row level security;
alter table public.household_members enable row level security;
alter table public.household_invitations enable row level security;
alter table public.household_recipes enable row level security;
alter table public.household_meal_plans enable row level security;
alter table public.household_plan_meals enable row level security;
alter table public.household_calendar_meals enable row level security;

create policy "Members read household" on public.households for select to authenticated
  using (
    public.is_household_member(id)
    or exists (
      select 1 from public.household_invitations
      where household_id = households.id
        and invitee_id = auth.uid()
        and status = 'pending'
    )
  );
create policy "Owners update household" on public.households for update to authenticated
  using (public.is_household_owner(id)) with check (owner_id = auth.uid());
create policy "Owners delete household" on public.households for delete to authenticated
  using (public.is_household_owner(id));

create policy "Members read household members" on public.household_members for select to authenticated
  using (public.is_household_member(household_id));

create policy "Owners read household invitations" on public.household_invitations for select to authenticated
  using (public.is_household_owner(household_id) or invitee_id = auth.uid());
create policy "Members read household recipes" on public.household_recipes for select to authenticated
  using (public.is_household_member(household_id));
create policy "Members create household recipes" on public.household_recipes for insert to authenticated
  with check (public.is_household_member(household_id) and created_by = auth.uid() and updated_by = auth.uid());
create policy "Members update household recipes" on public.household_recipes for update to authenticated
  using (public.is_household_member(household_id)) with check (public.is_household_member(household_id));
create policy "Members delete household recipes" on public.household_recipes for delete to authenticated
  using (public.is_household_member(household_id));

create policy "Members read household plans" on public.household_meal_plans for select to authenticated
  using (public.is_household_member(household_id));
create policy "Members create household plans" on public.household_meal_plans for insert to authenticated
  with check (public.is_household_member(household_id) and created_by = auth.uid() and updated_by = auth.uid());
create policy "Members update household plans" on public.household_meal_plans for update to authenticated
  using (public.is_household_member(household_id)) with check (public.is_household_member(household_id));
create policy "Members delete household plans" on public.household_meal_plans for delete to authenticated
  using (public.is_household_member(household_id));

create policy "Members read household plan meals" on public.household_plan_meals for select to authenticated
  using (public.is_household_member(household_id));
create policy "Members read household calendar" on public.household_calendar_meals for select to authenticated
  using (public.is_household_member(household_id));
create policy "Members create household calendar" on public.household_calendar_meals for insert to authenticated
  with check (
    public.is_household_member(household_id)
    and created_by = auth.uid()
    and updated_by = auth.uid()
    and exists (select 1 from public.household_recipes where id = household_calendar_meals.recipe_id and household_recipes.household_id = household_calendar_meals.household_id)
  );
create policy "Members update household calendar" on public.household_calendar_meals for update to authenticated
  using (public.is_household_member(household_id))
  with check (
    public.is_household_member(household_id)
    and exists (select 1 from public.household_recipes where id = household_calendar_meals.recipe_id and household_recipes.household_id = household_calendar_meals.household_id)
  );
create policy "Members delete household calendar" on public.household_calendar_meals for delete to authenticated
  using (public.is_household_member(household_id));

grant select, update, delete on public.households to authenticated;
grant select on public.household_members to authenticated;
grant select on public.household_invitations to authenticated;
grant select, insert, update, delete on public.household_recipes to authenticated;
grant select, insert, update, delete on public.household_meal_plans to authenticated;
grant select on public.household_plan_meals to authenticated;
grant select, insert, update, delete on public.household_calendar_meals to authenticated;

create or replace function public.create_household(household_name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare new_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not exists (select 1 from profiles where id = auth.uid() and username is not null and btrim(display_name) <> '') then
    raise exception 'Complete your profile before creating a household';
  end if;
  if exists (select 1 from household_members where user_id = auth.uid()) then
    raise exception 'You already belong to a household';
  end if;
  if char_length(btrim(household_name)) not between 1 and 80 then
    raise exception 'Household name must be between 1 and 80 characters';
  end if;
  insert into households (name, owner_id) values (btrim(household_name), auth.uid()) returning id into new_id;
  insert into household_members (household_id, user_id, role) values (new_id, auth.uid(), 'owner');
  return new_id;
end;
$$;

create or replace function public.invite_household_member(invitee_username text)
returns uuid language plpgsql security definer set search_path = public as $$
declare target_household uuid; target_user uuid; invitation_id uuid;
begin
  select id into target_household from households where owner_id = auth.uid();
  if target_household is null then raise exception 'Only a household owner can invite members'; end if;
  select id into target_user from profiles where lower(username::text) = lower(btrim(invitee_username));
  if target_user is null then raise exception 'No user found with that username'; end if;
  if target_user = auth.uid() then raise exception 'You cannot invite yourself'; end if;
  if exists (select 1 from household_members where user_id = target_user) then raise exception 'That user already belongs to a household'; end if;
  update household_invitations set status = 'expired', responded_at = now()
    where household_id = target_household and invitee_id = target_user and status = 'pending' and expires_at <= now();
  if exists (select 1 from household_invitations where household_id = target_household and invitee_id = target_user and status = 'pending') then
    raise exception 'An invitation is already pending';
  end if;
  insert into household_invitations (household_id, inviter_id, invitee_id)
    values (target_household, auth.uid(), target_user) returning id into invitation_id;
  return invitation_id;
end;
$$;

create or replace function public.respond_to_household_invitation(invitation_id uuid, accept_invitation boolean)
returns void language plpgsql security definer set search_path = public as $$
declare invitation household_invitations%rowtype;
begin
  select * into invitation from household_invitations where id = invitation_id for update;
  if invitation.id is null or invitation.invitee_id <> auth.uid() then raise exception 'Invitation not found'; end if;
  if invitation.status <> 'pending' then raise exception 'This invitation is no longer pending'; end if;
  if invitation.expires_at <= now() then
    update household_invitations set status = 'expired', responded_at = now() where id = invitation_id;
    raise exception 'This invitation has expired';
  end if;
  if accept_invitation then
    if exists (select 1 from household_members where user_id = auth.uid()) then raise exception 'You already belong to a household'; end if;
    insert into household_members (household_id, user_id, role) values (invitation.household_id, auth.uid(), 'member');
    update household_invitations set status = 'accepted', responded_at = now() where id = invitation_id;
    update household_invitations set status = 'declined', responded_at = now()
      where invitee_id = auth.uid() and status = 'pending' and id <> invitation_id;
  else
    update household_invitations set status = 'declined', responded_at = now() where id = invitation_id;
  end if;
end;
$$;

create or replace function public.revoke_household_invitation(invitation_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update household_invitations set status = 'revoked', responded_at = now()
  where id = invitation_id and status = 'pending' and public.is_household_owner(household_id);
  if not found then raise exception 'Pending invitation not found'; end if;
end;
$$;

create or replace function public.transfer_household_ownership(new_owner_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare target_household uuid;
begin
  select id into target_household from households where owner_id = auth.uid() for update;
  if target_household is null then raise exception 'Only the household owner can transfer ownership'; end if;
  if not public.is_household_member(target_household, new_owner_id) then raise exception 'The new owner must be a household member'; end if;
  update household_members set role = 'member' where household_id = target_household and user_id = auth.uid();
  update household_members set role = 'owner' where household_id = target_household and user_id = new_owner_id;
  update households set owner_id = new_owner_id where id = target_household;
end;
$$;

create or replace function public.remove_household_member(member_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare target_household uuid;
begin
  select id into target_household from households where owner_id = auth.uid();
  if target_household is null then raise exception 'Only the household owner can remove members'; end if;
  if member_id = auth.uid() then raise exception 'Transfer ownership or delete the household before leaving'; end if;
  delete from household_members where household_id = target_household and user_id = member_id and role = 'member';
  if not found then raise exception 'Member not found'; end if;
end;
$$;

create or replace function public.leave_household()
returns void language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from households where owner_id = auth.uid()) then raise exception 'Transfer ownership or delete the household before leaving'; end if;
  delete from household_members where user_id = auth.uid();
  if not found then raise exception 'You do not belong to a household'; end if;
end;
$$;

create or replace function public.share_recipe_to_household(recipe_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare target_household uuid; source_payload jsonb; shared_id uuid;
begin
  select household_id into target_household from household_members where user_id = auth.uid();
  if target_household is null then raise exception 'Join a household before sharing'; end if;
  select id into shared_id from household_recipes where household_id = target_household and source_recipe_id = recipe_id;
  if shared_id is not null then return shared_id; end if;
  select payload into source_payload from recipes where id = recipe_id and user_id = auth.uid();
  if source_payload is null then raise exception 'Recipe not found'; end if;
  shared_id := gen_random_uuid();
  source_payload := jsonb_set(source_payload, '{id}', to_jsonb(shared_id::text));
  insert into household_recipes (id, household_id, source_recipe_id, created_by, updated_by, payload)
    values (shared_id, target_household, recipe_id, auth.uid(), auth.uid(), source_payload);
  return shared_id;
end;
$$;

create or replace function public.share_meal_plan_to_household(plan_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  target_household uuid;
  source_payload jsonb;
  source_meal jsonb;
  source_recipe uuid;
  shared_recipe uuid;
  shared_plan uuid;
  recipe_payload jsonb;
  remapped_meals jsonb := '[]'::jsonb;
  remapped_meal jsonb;
begin
  select household_id into target_household from household_members where user_id = auth.uid();
  if target_household is null then raise exception 'Join a household before sharing'; end if;
  select id into shared_plan from household_meal_plans where household_id = target_household and source_plan_id = plan_id;
  if shared_plan is not null then return shared_plan; end if;
  select payload into source_payload from meal_plans where id = plan_id and user_id = auth.uid();
  if source_payload is null then raise exception 'Meal plan not found'; end if;

  for source_meal in select value from jsonb_array_elements(coalesce(source_payload->'meals', '[]'::jsonb)) loop
    source_recipe := (source_meal->>'recipeID')::uuid;
    select id into shared_recipe from household_recipes
      where household_id = target_household and source_recipe_id = source_recipe;
    if shared_recipe is null then
      select payload into recipe_payload from recipes where id = source_recipe and user_id = auth.uid();
      if recipe_payload is null then raise exception 'A recipe used by this plan is unavailable'; end if;
      shared_recipe := gen_random_uuid();
      recipe_payload := jsonb_set(recipe_payload, '{id}', to_jsonb(shared_recipe::text));
      insert into household_recipes (id, household_id, source_recipe_id, created_by, updated_by, payload)
        values (shared_recipe, target_household, source_recipe, auth.uid(), auth.uid(), recipe_payload);
    end if;
    remapped_meal := jsonb_set(source_meal, '{recipeID}', to_jsonb(shared_recipe::text));
    remapped_meals := remapped_meals || jsonb_build_array(remapped_meal);
  end loop;

  shared_plan := gen_random_uuid();
  source_payload := jsonb_set(source_payload, '{id}', to_jsonb(shared_plan::text));
  source_payload := jsonb_set(source_payload, '{meals}', remapped_meals);
  insert into household_meal_plans (id, household_id, source_plan_id, created_by, updated_by, payload)
    values (shared_plan, target_household, plan_id, auth.uid(), auth.uid(), source_payload);
  for remapped_meal in select value from jsonb_array_elements(remapped_meals) loop
    insert into household_plan_meals (id, plan_id, household_id, week, weekday, meal_type, recipe_id, meal_order)
    values (
      (remapped_meal->>'id')::uuid,
      shared_plan,
      target_household,
      (remapped_meal->>'week')::integer,
      (remapped_meal->>'weekday')::integer,
      remapped_meal->>'mealType',
      (remapped_meal->>'recipeID')::uuid,
      coalesce((remapped_meal->>'order')::integer, 0)
    );
  end loop;
  return shared_plan;
end;
$$;

create or replace function public.save_household_meal_plan(
  p_household_id uuid,
  p_plan_id uuid,
  p_expected_version integer,
  p_payload jsonb
)
returns void language plpgsql security definer set search_path = public as $$
declare meal jsonb; current_version integer;
begin
  if not public.is_household_member(p_household_id) then raise exception 'Household membership required'; end if;
  select version into current_version from household_meal_plans where id = p_plan_id and household_id = p_household_id for update;
  if current_version is null then
    insert into household_meal_plans (id, household_id, created_by, updated_by, payload)
      values (p_plan_id, p_household_id, auth.uid(), auth.uid(), p_payload);
  else
    if p_expected_version is null or current_version <> p_expected_version then raise exception 'Someone else changed this meal plan. Reload it and try again.'; end if;
    update household_meal_plans set payload = p_payload
      where id = p_plan_id and household_id = p_household_id;
    delete from household_plan_meals where plan_id = p_plan_id;
  end if;
  for meal in select value from jsonb_array_elements(coalesce(p_payload->'meals', '[]'::jsonb)) loop
    if not exists (select 1 from household_recipes where id = (meal->>'recipeID')::uuid and household_id = p_household_id) then
      raise exception 'Meal plans may only use recipes from this household';
    end if;
    insert into household_plan_meals (id, plan_id, household_id, week, weekday, meal_type, recipe_id, meal_order)
    values ((meal->>'id')::uuid, p_plan_id, p_household_id, (meal->>'week')::integer, (meal->>'weekday')::integer, meal->>'mealType', (meal->>'recipeID')::uuid, coalesce((meal->>'order')::integer, 0));
  end loop;
end;
$$;

revoke all on function public.create_household(text) from public;
revoke all on function public.invite_household_member(text) from public;
revoke all on function public.respond_to_household_invitation(uuid, boolean) from public;
revoke all on function public.revoke_household_invitation(uuid) from public;
revoke all on function public.transfer_household_ownership(uuid) from public;
revoke all on function public.remove_household_member(uuid) from public;
revoke all on function public.leave_household() from public;
revoke all on function public.share_recipe_to_household(uuid) from public;
revoke all on function public.share_meal_plan_to_household(uuid) from public;
revoke all on function public.save_household_meal_plan(uuid, uuid, integer, jsonb) from public;

grant execute on function public.create_household(text) to authenticated;
grant execute on function public.invite_household_member(text) to authenticated;
grant execute on function public.respond_to_household_invitation(uuid, boolean) to authenticated;
grant execute on function public.revoke_household_invitation(uuid) to authenticated;
grant execute on function public.transfer_household_ownership(uuid) to authenticated;
grant execute on function public.remove_household_member(uuid) to authenticated;
grant execute on function public.leave_household() to authenticated;
grant execute on function public.share_recipe_to_household(uuid) to authenticated;
grant execute on function public.share_meal_plan_to_household(uuid) to authenticated;
grant execute on function public.save_household_meal_plan(uuid, uuid, integer, jsonb) to authenticated;
