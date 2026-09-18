# Supabase setup

1. In the Supabase Dashboard, open **SQL Editor** and run [the initial migration](migrations/20260913112000_account_data.sql). It creates private, user-owned profile, recipe, meal-plan, and calendar tables protected by Row Level Security.
2. For development, create test accounts manually in **Authentication → Users → Add user → Create user**. Set an email and password, and auto-confirm the email. This sends no email and works with the app's password sign-in screen.
3. Before external testing or launch, configure a custom SMTP provider and sender domain. This is needed for self-service account creation, password reset, and any future magic-link or six-digit-code flow. [magic-link.html](templates/magic-link.html) is available if you later switch back to email codes.

## Shared feed setup

After the initial migration, run [the shared feed migration](migrations/20260917160000_shared_feed.sql). It adds unique usernames, authenticated shared posts, live links to published recipes, and the private `post-photos` Storage bucket. Linked recipes can be read by signed-in feed users; unlinked recipes remain private.

Then run [the feed engagement migration](migrations/20260917170000_feed_engagement.sql). It adds likes, comments, post favourites, and recipe favourites with Row Level Security so users can change only their own reactions and comments.

Finally, run [the engagement-permissions migration](migrations/20260917173000_engagement_permissions.sql). It makes the RLS policies explicit for like and favourite reads, inserts, and deletes.

Run [the engagement table-grants migration](migrations/20260918090000_engagement_table_grants.sql) as well. It gives authenticated users the table privileges required for those RLS policies to take effect.

The app uses the public Supabase URL and publishable key in `RecipeApp/Info.plist`. The service-role key must never be placed in the app or committed to this repository.
