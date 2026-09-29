-- Private profiles and approval-based follow requests.
-- Run after 20260928170000_user_follows.sql.

alter table public.profiles
  add column if not exists is_private boolean not null default false;

alter table public.user_follows
  add column if not exists status text not null default 'accepted',
  add column if not exists responded_at timestamptz;

alter table public.user_follows
  drop constraint if exists user_follows_status_valid;
alter table public.user_follows
  add constraint user_follows_status_valid
  check (status in ('pending', 'accepted'));

create index if not exists user_follows_accepted_followed_idx
  on public.user_follows (followed_id, created_at desc)
  where status = 'accepted';
create index if not exists user_follows_pending_followed_idx
  on public.user_follows (followed_id, created_at desc)
  where status = 'pending';

-- Requests are created through request_follow so a client cannot mark itself
-- accepted when the target account is private.
drop policy if exists "Users create their own follows" on public.user_follows;
revoke insert on table public.user_follows from authenticated;

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
begin
  if auth.uid() is null then
    raise exception 'Authentication is required';
  end if;
  if target_user = auth.uid() then
    raise exception 'You cannot follow yourself';
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

create or replace function public.respond_to_follow_request(requester_id uuid, approve boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication is required';
  end if;

  if approve then
    update public.user_follows as uf
      set status = 'accepted', responded_at = now()
      where uf.follower_id = requester_id
        and uf.followed_id = auth.uid()
        and uf.status = 'pending';
  else
    delete from public.user_follows as uf
      where uf.follower_id = requester_id
        and uf.followed_id = auth.uid()
        and uf.status = 'pending';
  end if;

  if not found then
    raise exception 'Follow request not found';
  end if;
end;
$$;

revoke all on function public.request_follow(uuid) from public;
revoke all on function public.respond_to_follow_request(uuid, boolean) from public;
grant execute on function public.request_follow(uuid) to authenticated;
grant execute on function public.respond_to_follow_request(uuid, boolean) to authenticated;

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
         and uf.status = 'accepted'
     )
  order by fp.created_at desc;
$$;

drop function if exists public.search_social_profiles(text, integer);
create function public.search_social_profiles(search_text text, result_limit integer default 20)
returns table (
  id uuid,
  display_name text,
  username text,
  is_private boolean,
  follower_count bigint,
  following_count bigint,
  is_following boolean,
  is_requested boolean
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
    pr.is_private,
    (select count(*) from public.user_follows as uf where uf.followed_id = pr.id and uf.status = 'accepted'),
    (select count(*) from public.user_follows as uf where uf.follower_id = pr.id and uf.status = 'accepted'),
    exists (select 1 from public.user_follows as uf where uf.follower_id = auth.uid() and uf.followed_id = pr.id and uf.status = 'accepted'),
    exists (select 1 from public.user_follows as uf where uf.follower_id = auth.uid() and uf.followed_id = pr.id and uf.status = 'pending')
  from public.profiles as pr
  where pr.id <> auth.uid()
    and pr.username is not null
    and pr.username::text ilike '%' || lower(btrim(search_text)) || '%'
  order by
    case when pr.username::text = lower(btrim(search_text)) then 0 else 1 end,
    pr.username::text
  limit least(greatest(result_limit, 1), 20);
$$;

drop function if exists public.relationship_profiles(uuid, text, text, integer, integer);
create function public.relationship_profiles(
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
  is_private boolean,
  follower_count bigint,
  following_count bigint,
  is_following boolean,
  is_requested boolean,
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
    pr.is_private,
    (select count(*) from public.user_follows as f where f.followed_id = pr.id and f.status = 'accepted'),
    (select count(*) from public.user_follows as f where f.follower_id = pr.id and f.status = 'accepted'),
    exists (select 1 from public.user_follows as f where f.follower_id = auth.uid() and f.followed_id = pr.id and f.status = 'accepted'),
    exists (select 1 from public.user_follows as f where f.follower_id = auth.uid() and f.followed_id = pr.id and f.status = 'pending'),
    count(*) over ()
  from public.user_follows as uf
  join public.profiles as pr on pr.id = case
    when relationship_kind = 'followers' then uf.follower_id
    when relationship_kind = 'following' then uf.followed_id
  end
  where uf.status = 'accepted'
    and (
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

-- A private account's posts and attached recipes are visible only to its owner
-- and accepted followers. Profile identity and relationship lists remain public.
drop policy if exists "Authenticated users read feed posts" on public.feed_posts;
create policy "Authenticated users read permitted feed posts" on public.feed_posts
  for select to authenticated
  using (
    author_id = auth.uid()
    or exists (
      select 1 from public.profiles as pr
      where pr.id = feed_posts.author_id
        and (
          not pr.is_private
          or exists (
            select 1 from public.user_follows as uf
            where uf.follower_id = auth.uid()
              and uf.followed_id = feed_posts.author_id
              and uf.status = 'accepted'
          )
        )
    )
  );

drop policy if exists "Authenticated users read published recipes" on public.recipes;
create policy "Authenticated users read permitted published recipes" on public.recipes
  for select to authenticated
  using (
    exists (
      select 1
      from public.feed_posts as fp
      join public.profiles as pr on pr.id = fp.author_id
      where fp.recipe_id = recipes.id
        and (
          fp.author_id = auth.uid()
          or not pr.is_private
          or exists (
            select 1 from public.user_follows as uf
            where uf.follower_id = auth.uid()
              and uf.followed_id = fp.author_id
              and uf.status = 'accepted'
          )
        )
    )
  );

-- Engagement and image objects inherit the post's visibility too. This keeps a
-- guessed post ID or storage path from disclosing private-account activity.
drop policy if exists "Authenticated users read post likes" on public.post_likes;
create policy "Authenticated users read permitted post likes" on public.post_likes
  for select to authenticated
  using (exists (select 1 from public.feed_posts as fp where fp.id = post_likes.post_id));

drop policy if exists "Users manage their own post likes" on public.post_likes;
create policy "Users manage their own permitted post likes" on public.post_likes
  for all to authenticated
  using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id
    and exists (select 1 from public.feed_posts as fp where fp.id = post_likes.post_id)
  );

drop policy if exists "Authenticated users read post comments" on public.post_comments;
create policy "Authenticated users read permitted post comments" on public.post_comments
  for select to authenticated
  using (exists (select 1 from public.feed_posts as fp where fp.id = post_comments.post_id));

drop policy if exists "Users create their own post comments" on public.post_comments;
create policy "Users create comments on permitted posts" on public.post_comments
  for insert to authenticated
  with check (
    auth.uid() = author_id
    and exists (select 1 from public.feed_posts as fp where fp.id = post_comments.post_id)
  );

drop policy if exists "Authenticated users read post photos" on storage.objects;
create policy "Authenticated users read permitted post photos" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'post-photos'
    and exists (
      select 1
      from public.feed_posts as fp
      where name = any(fp.photo_paths)
    )
  );
