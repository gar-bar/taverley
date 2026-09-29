-- Public one-way following and a feed scoped to the signed-in user.
-- Run after 20260918130000_account_lifecycle.sql.

create table if not exists public.user_follows (
  follower_id uuid not null references public.profiles(id) on delete cascade,
  followed_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, followed_id),
  constraint user_follows_no_self_follow check (follower_id <> followed_id)
);

create index if not exists user_follows_followed_id_idx
  on public.user_follows (followed_id, created_at desc);
create index if not exists user_follows_follower_id_idx
  on public.user_follows (follower_id, created_at desc);

alter table public.user_follows enable row level security;

drop policy if exists "Authenticated users read follows" on public.user_follows;
create policy "Authenticated users read follows" on public.user_follows
  for select to authenticated using (true);

drop policy if exists "Users create their own follows" on public.user_follows;
create policy "Users create their own follows" on public.user_follows
  for insert to authenticated with check (auth.uid() = follower_id);

drop policy if exists "Users delete their own follows" on public.user_follows;
create policy "Users delete their own follows" on public.user_follows
  for delete to authenticated using (auth.uid() = follower_id);

grant select, insert, delete on table public.user_follows to authenticated;

create or replace function public.following_feed()
returns setof public.feed_posts
language sql
stable
security invoker
set search_path = ''
as $$
  select fp.*
  from public.feed_posts as fp
  where fp.author_id = auth.uid()
     or exists (
       select 1
       from public.user_follows as uf
       where uf.follower_id = auth.uid()
         and uf.followed_id = fp.author_id
     )
  order by fp.created_at desc;
$$;

revoke all on function public.following_feed() from public;
grant execute on function public.following_feed() to authenticated;

create or replace function public.search_social_profiles(search_text text, result_limit integer default 20)
returns table (
  id uuid,
  display_name text,
  username text,
  follower_count bigint,
  following_count bigint,
  is_following boolean
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    pr.id,
    pr.display_name,
    pr.username::text,
    (select count(*) from public.user_follows f where f.followed_id = pr.id),
    (select count(*) from public.user_follows f where f.follower_id = pr.id),
    (select count(*) > 0 from public.user_follows f
      where f.follower_id = auth.uid() and f.followed_id = pr.id)
  from public.profiles as pr
  where pr.id <> auth.uid()
    and pr.username is not null
    and pr.username::text ilike '%' || lower(btrim(search_text)) || '%'
  order by
    case when pr.username::text = lower(btrim(search_text)) then 0 else 1 end,
    pr.username::text
  limit least(greatest(result_limit, 1), 20);
$$;

create or replace function public.relationship_profiles(
  target_user uuid,
  relationship_kind text,
  search_text text default '',
  page_offset integer default 0,
  page_limit integer default 25
)
returns table (
  id uuid,
  display_name text,
  username text,
  follower_count bigint,
  following_count bigint,
  is_following boolean,
  total_count bigint
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    pr.id,
    pr.display_name,
    pr.username::text,
    (select count(*) from public.user_follows f where f.followed_id = pr.id),
    (select count(*) from public.user_follows f where f.follower_id = pr.id),
    (select count(*) > 0 from public.user_follows f
      where f.follower_id = auth.uid() and f.followed_id = pr.id),
    count(*) over ()
  from public.user_follows as uf
  join public.profiles as pr on pr.id = case
    when relationship_kind = 'followers' then uf.follower_id
    when relationship_kind = 'following' then uf.followed_id
  end
  where (
    (relationship_kind = 'followers' and uf.followed_id = target_user)
    or (relationship_kind = 'following' and uf.follower_id = target_user)
  )
    and (search_text = '' or pr.username::text ilike '%' || lower(btrim(search_text)) || '%')
  order by uf.created_at desc, pr.username::text
  offset greatest(page_offset, 0)
  limit least(greatest(page_limit, 1), 50);
$$;

revoke all on function public.search_social_profiles(text, integer) from public;
revoke all on function public.relationship_profiles(uuid, text, text, integer, integer) from public;
grant execute on function public.search_social_profiles(text, integer) to authenticated;
grant execute on function public.relationship_profiles(uuid, text, text, integer, integer) to authenticated;
