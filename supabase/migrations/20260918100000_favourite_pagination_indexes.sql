-- Supports newest-first, per-user favourite pagination.

create index if not exists post_favourites_user_created_at_idx
  on public.post_favourites (user_id, created_at desc);

create index if not exists recipe_favourites_user_created_at_idx
  on public.recipe_favourites (user_id, created_at desc);
