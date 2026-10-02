-- In-app bug reports submitted from Profile > Settings.
create table if not exists public.bug_reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  subject text not null check (char_length(btrim(subject)) between 1 and 120),
  details text not null check (char_length(btrim(details)) between 10 and 5000),
  app_version text not null,
  build_number text not null,
  system_version text not null,
  created_at timestamptz not null default now()
);

alter table public.bug_reports enable row level security;

drop policy if exists "Users submit their own bug reports" on public.bug_reports;
create policy "Users submit their own bug reports" on public.bug_reports
  for insert to authenticated with check (auth.uid() = user_id);

revoke all on table public.bug_reports from anon;
grant insert on table public.bug_reports to authenticated;
