-- Run this migration in the Supabase SQL Editor, or with the Supabase CLI.
-- All app content is private: each policy limits access to auth.uid().

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  avatar_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.recipes (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  payload jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.meal_plans (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  payload jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.calendar_meals (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  payload jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.recipes enable row level security;
alter table public.meal_plans enable row level security;
alter table public.calendar_meals enable row level security;

create policy "Users manage their own profile" on public.profiles
  for all using (auth.uid() = id) with check (auth.uid() = id);

create policy "Users manage their own recipes" on public.recipes
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "Users manage their own meal plans" on public.meal_plans
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "Users manage their own calendar meals" on public.calendar_meals
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
security invoker
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_updated_at before update on public.profiles
  for each row execute procedure public.set_updated_at();
create trigger recipes_updated_at before update on public.recipes
  for each row execute procedure public.set_updated_at();
create trigger meal_plans_updated_at before update on public.meal_plans
  for each row execute procedure public.set_updated_at();
create trigger calendar_meals_updated_at before update on public.calendar_meals
  for each row execute procedure public.set_updated_at();
