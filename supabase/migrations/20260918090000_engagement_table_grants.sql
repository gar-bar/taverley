-- RLS policies do not grant table privileges by themselves.
-- Run after 20260917173000_engagement_permissions.sql.

grant select, insert, delete on table public.post_likes to authenticated;
grant select, insert, delete on table public.post_favourites to authenticated;
grant select, insert, delete on table public.post_comments to authenticated;
grant select, insert, delete on table public.recipe_favourites to authenticated;
