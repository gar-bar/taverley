-- Explicit operation-level RLS for engagement tables.
-- Run after 20260917170000_feed_engagement.sql.

drop policy if exists "Users manage their own post likes" on public.post_likes;
drop policy if exists "Users insert their own post likes" on public.post_likes;
drop policy if exists "Users delete their own post likes" on public.post_likes;
create policy "Users insert their own post likes" on public.post_likes
  for insert to authenticated with check (auth.uid() = user_id);
create policy "Users delete their own post likes" on public.post_likes
  for delete to authenticated using (auth.uid() = user_id);

drop policy if exists "Users manage their own post favourites" on public.post_favourites;
drop policy if exists "Users read their own post favourites" on public.post_favourites;
drop policy if exists "Users insert their own post favourites" on public.post_favourites;
drop policy if exists "Users delete their own post favourites" on public.post_favourites;
create policy "Users read their own post favourites" on public.post_favourites
  for select to authenticated using (auth.uid() = user_id);
create policy "Users insert their own post favourites" on public.post_favourites
  for insert to authenticated with check (auth.uid() = user_id);
create policy "Users delete their own post favourites" on public.post_favourites
  for delete to authenticated using (auth.uid() = user_id);

drop policy if exists "Users manage their own recipe favourites" on public.recipe_favourites;
drop policy if exists "Users read their own recipe favourites" on public.recipe_favourites;
drop policy if exists "Users insert their own recipe favourites" on public.recipe_favourites;
drop policy if exists "Users delete their own recipe favourites" on public.recipe_favourites;
create policy "Users read their own recipe favourites" on public.recipe_favourites
  for select to authenticated using (auth.uid() = user_id);
create policy "Users insert their own recipe favourites" on public.recipe_favourites
  for insert to authenticated
  with check (
    auth.uid() = user_id
    and exists (select 1 from public.recipes where recipes.id = recipe_favourites.recipe_id)
  );
create policy "Users delete their own recipe favourites" on public.recipe_favourites
  for delete to authenticated using (auth.uid() = user_id);
