-- Shared post engagement and private per-user favourites.
-- Run after 20260917160000_shared_feed.sql.

create extension if not exists pgcrypto;

create table if not exists public.post_likes (
  post_id uuid not null references public.feed_posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create table if not exists public.post_favourites (
  post_id uuid not null references public.feed_posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create table if not exists public.post_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.feed_posts(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade default auth.uid(),
  body text not null check (length(btrim(body)) > 0),
  created_at timestamptz not null default now()
);

create table if not exists public.recipe_favourites (
  recipe_id uuid not null references public.recipes(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  created_at timestamptz not null default now(),
  primary key (recipe_id, user_id)
);

create index if not exists post_likes_post_id_idx on public.post_likes (post_id);
create index if not exists post_comments_post_id_created_at_idx on public.post_comments (post_id, created_at);
create index if not exists post_favourites_user_id_idx on public.post_favourites (user_id);
create index if not exists recipe_favourites_user_id_idx on public.recipe_favourites (user_id);

alter table public.post_likes enable row level security;
alter table public.post_favourites enable row level security;
alter table public.post_comments enable row level security;
alter table public.recipe_favourites enable row level security;

drop policy if exists "Authenticated users read post likes" on public.post_likes;
create policy "Authenticated users read post likes" on public.post_likes
  for select to authenticated using (true);

drop policy if exists "Users manage their own post likes" on public.post_likes;
create policy "Users manage their own post likes" on public.post_likes
  for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users manage their own post favourites" on public.post_favourites;
create policy "Users manage their own post favourites" on public.post_favourites
  for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Authenticated users read post comments" on public.post_comments;
create policy "Authenticated users read post comments" on public.post_comments
  for select to authenticated using (true);

drop policy if exists "Users create their own post comments" on public.post_comments;
create policy "Users create their own post comments" on public.post_comments
  for insert to authenticated
  with check (auth.uid() = author_id);

drop policy if exists "Authors delete their own post comments" on public.post_comments;
create policy "Authors delete their own post comments" on public.post_comments
  for delete to authenticated
  using (auth.uid() = author_id);

drop policy if exists "Users manage their own recipe favourites" on public.recipe_favourites;
create policy "Users manage their own recipe favourites" on public.recipe_favourites
  for all to authenticated
  using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id
    and exists (
      select 1 from public.recipes
      where recipes.id = recipe_favourites.recipe_id
    )
  );
