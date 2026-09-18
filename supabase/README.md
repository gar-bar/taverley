# Supabase setup

1. In the Supabase Dashboard, open **SQL Editor** and run [the initial migration](migrations/20260913112000_account_data.sql). It creates private, user-owned profile, recipe, meal-plan, and calendar tables protected by Row Level Security.
2. In **Authentication → Providers → Email**, enable email signup and **Confirm Email**. Set the minimum password length to 12 and require a number and symbol.
3. Configure a custom SMTP provider and sender domain. Supabase keeps template editing disabled while its default sender is active.
4. Install [confirm-signup.html](templates/confirm-signup.html) as the Confirm signup template and [recovery.html](templates/recovery.html) as the Reset password template. Both use the six-digit `{{ .Token }}` flow expected by the app. Until custom SMTP is configured, signup also supports Supabase's default confirmation link and returns the user to password sign-in.

## Shared feed setup

After the initial migration, run [the shared feed migration](migrations/20260917160000_shared_feed.sql). It adds unique usernames, authenticated shared posts, live links to published recipes, and the private `post-photos` Storage bucket. Linked recipes can be read by signed-in feed users; unlinked recipes remain private.

Then run [the feed engagement migration](migrations/20260917170000_feed_engagement.sql). It adds likes, comments, post favourites, and recipe favourites with Row Level Security so users can change only their own reactions and comments.

Finally, run [the engagement-permissions migration](migrations/20260917173000_engagement_permissions.sql). It makes the RLS policies explicit for like and favourite reads, inserts, and deletes.

Run [the engagement table-grants migration](migrations/20260918090000_engagement_table_grants.sql) as well. It gives authenticated users the table privileges required for those RLS policies to take effect.

For the paginated My Favourites screen, also run [the favourite pagination index migration](migrations/20260918100000_favourite_pagination_indexes.sql).

## Collaborative households

Run [the collaborative households migration](migrations/20260918110000_collaborative_households.sql) after all migrations above. It creates one-household-per-user membership, seven-day username invitations, owner administration, collaboratively editable household recipe and meal-plan copies, and a shared meal calendar. Its Row Level Security policies restrict content to current household members and membership administration to the household owner.

On an existing Supabase project, do not rerun the full migration history in the SQL Editor. Run only migrations that have not already been applied. For the household feature, copy and run only `20260918110000_collaborative_households.sql` after confirming the earlier feed migrations are present.

The migration also installs the transaction functions used by the app for accepting invitations, transferring ownership, and copying a meal plan together with all of its referenced recipes. After running it, sign out and back in so the app refreshes its session and loads the new household state.

## Account lifecycle

Run [the account lifecycle migration](migrations/20260918130000_account_lifecycle.sql) after the household migration. It adds username availability and claim functions, prevents partial client-side profile deletion, and prepares household ownership and attribution for permanent account deletion.

Deploy the authenticated deletion function:

```sh
supabase functions deploy delete-account
```

The hosted function receives `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` from the Supabase runtime. Do not add the service-role key to the iOS app, `Info.plist`, or source control. Account deletion remains an in-app action; the function is only its privileged backend.

The app uses the public Supabase URL and publishable key in `RecipeApp/Info.plist`. The service-role key must never be placed in the app or committed to this repository.
