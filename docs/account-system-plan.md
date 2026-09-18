# Taverley account system: remaining work

## Current implementation

- The app requires authentication before showing recipes and meal plans.
- Users can create accounts, confirm their email with a six-digit code, sign in, and recover forgotten passwords.
- A successful session is stored securely in Keychain and refreshed when needed.
- Recipe, meal-plan, and calendar data are designed to load and save privately per account.
- Existing local demo data is not migrated into an account; a new account begins empty.
- Apple sign-in is intentionally not implemented yet.
- A unique username is the account's visible identity throughout the app.
- Signed-in users can permanently delete their account from Account Settings after password reauthentication and typing `DELETE`.
- The sign-in screen has a **Skip for now** option in Debug builds only.

## Required before the first end-to-end test

1. In Supabase **SQL Editor**, run [the initial migration](../supabase/migrations/20260913112000_account_data.sql).

   This creates the private `profiles`, `recipes`, `meal_plans`, and `calendar_meals` tables and turns on Row Level Security.

2. Run [the shared feed migration](../supabase/migrations/20260917160000_shared_feed.sql).

   This adds shared posts, unique usernames, authenticated access to linked recipes, and the protected post-photo bucket.

3. Run the remaining migrations through `20260918130000_account_lifecycle.sql`, install the signup and recovery email templates, and deploy the `delete-account` Edge Function.

4. Verify the full flow:

   - Sign in with the test account in the app.
   - Create a recipe, meal plan, and calendar entry.
   - Relaunch the app and confirm the data is still present.

## Before inviting external testers or launching

1. Buy or use a domain you control.
2. Configure custom SMTP (for example, Resend) in Supabase.
3. Set up SPF, DKIM, and DMARC DNS records for the sending domain.
4. Change the sender to something like `Taverley <no-reply@auth.yourdomain.com>`.
5. Test signup, recovery, and account deletion with non-team email addresses.
6. Review Supabase Auth rate limits and error logs.

## Apple sign-in: defer until release preparation

1. Enroll in the Apple Developer Program.
2. Finalize and register the production bundle ID. Do not change it after release.
3. Enable the **Sign in with Apple** capability for that App ID.
4. Add the entitlement in Xcode, implement the Apple credential flow, and link the resulting identity to the same Supabase user account.
5. Test on a signed physical device and through TestFlight.

## Future product work

- Add username editing and profile customization.
- Add avatar image upload to Supabase Storage instead of device-only storage.
- Add sync status and error feedback in the app rather than silently retrying after a failed save.
- Add conflict handling for edits made from multiple devices.
- Add account data export before public launch.
