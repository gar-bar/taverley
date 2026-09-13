# Supabase setup

1. In the Supabase Dashboard, open **SQL Editor** and run [the initial migration](migrations/20260913112000_account_data.sql). It creates private, user-owned profile, recipe, meal-plan, and calendar tables protected by Row Level Security.
2. In **Authentication → URL Configuration → Redirect URLs**, add `taverley://auth/callback`. This returns a successful magic-link sign-in to the app.
3. For development, add your own email address as an authorized team address. The built-in sender can deliver its stock magic-link email to team members only, with a two-email-per-hour limit.
4. Before external testing or launch, configure a custom SMTP provider and sender domain. At that point, [magic-link.html](templates/magic-link.html) is available if you decide to switch back to a six-digit-code email flow.

The app uses the public Supabase URL and publishable key in `RecipeApp/Info.plist`. The service-role key must never be placed in the app or committed to this repository.
