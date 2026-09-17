-- Shared authenticated feed, public profile identity, and protected post media.
-- Run after 20260913112000_account_data.sql.

create extension if not exists citext;

alter table public.profiles
  add column if not exists username citext;

alter table public.profiles
  drop constraint if exists profiles_username_format;
alter table public.profiles
  add constraint profiles_username_format check (
    username is null or (
      char_length(username::text) between 3 and 30
      and username::text ~ '^[a-z0-9._]+$'
    )
  );

create unique index if not exists profiles_username_unique
  on public.profiles (username)
  where username is not null;

create table if not exists public.feed_posts (
  id uuid primary key,
  author_id uuid not null references public.profiles(id) on delete cascade default auth.uid(),
  title text not null check (length(btrim(title)) > 0),
  body text not null check (length(btrim(body)) > 0),
  recipe_id uuid references public.recipes(id) on delete restrict,
  photo_paths text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint feed_posts_photo_limit check (cardinality(photo_paths) <= 4)
);

create index if not exists feed_posts_created_at_idx
  on public.feed_posts (created_at desc);
create index if not exists feed_posts_author_id_idx
  on public.feed_posts (author_id);
create index if not exists feed_posts_recipe_id_idx
  on public.feed_posts (recipe_id)
  where recipe_id is not null;

alter table public.feed_posts enable row level security;

drop policy if exists "Authenticated users read profiles" on public.profiles;
create policy "Authenticated users read profiles" on public.profiles
  for select to authenticated
  using (true);

drop policy if exists "Authenticated users read feed posts" on public.feed_posts;
create policy "Authenticated users read feed posts" on public.feed_posts
  for select to authenticated
  using (true);

drop policy if exists "Authors create feed posts" on public.feed_posts;
create policy "Authors create feed posts" on public.feed_posts
  for insert to authenticated
  with check (
    auth.uid() = author_id
    and (
      recipe_id is null
      or exists (
        select 1 from public.recipes
        where recipes.id = feed_posts.recipe_id
          and recipes.user_id = auth.uid()
      )
    )
  );

drop policy if exists "Authors update feed posts" on public.feed_posts;
create policy "Authors update feed posts" on public.feed_posts
  for update to authenticated
  using (auth.uid() = author_id)
  with check (
    auth.uid() = author_id
    and (
      recipe_id is null
      or exists (
        select 1 from public.recipes
        where recipes.id = feed_posts.recipe_id
          and recipes.user_id = auth.uid()
      )
    )
  );

drop policy if exists "Authors delete feed posts" on public.feed_posts;
create policy "Authors delete feed posts" on public.feed_posts
  for delete to authenticated
  using (auth.uid() = author_id);

drop policy if exists "Authenticated users read published recipes" on public.recipes;
create policy "Authenticated users read published recipes" on public.recipes
  for select to authenticated
  using (
    exists (
      select 1 from public.feed_posts
      where feed_posts.recipe_id = recipes.id
    )
  );

drop trigger if exists feed_posts_updated_at on public.feed_posts;
create trigger feed_posts_updated_at before update on public.feed_posts
  for each row execute procedure public.set_updated_at();

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'post-photos',
  'post-photos',
  false,
  10485760,
  array['image/jpeg']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Authenticated users read post photos" on storage.objects;
create policy "Authenticated users read post photos" on storage.objects
  for select to authenticated
  using (bucket_id = 'post-photos');

drop policy if exists "Authors upload post photos" on storage.objects;
create policy "Authors upload post photos" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'post-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Authors update post photos" on storage.objects;
create policy "Authors update post photos" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'post-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'post-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Authors delete post photos" on storage.objects;
create policy "Authors delete post photos" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'post-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
