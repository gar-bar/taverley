# Taverley account system: remaining work

## Current implementation

- The app requires authentication before showing recipes and meal plans.
- Development sign-in uses Supabase's stock email magic-link flow.
- A successful session is stored securely in Keychain and refreshed when needed.
- Recipe, meal-plan, and calendar data are designed to load and save privately per account.
- Existing local demo data is not migrated into an account; a new account begins empty.
- Apple sign-in is intentionally not implemented yet.
- The sign-in screen has a persistent **Skip for now** option for development. It uses local-only data and sends no authentication email.

## Required before the first end-to-end test

1. In Supabase **Authentication → URL Configuration → Redirect URLs**, add:

   ```
   taverley://auth/callback
   ```

2. In Supabase **SQL Editor**, run [the initial migration](../supabase/migrations/20260913112000_account_data.sql).

   This creates the private `profiles`, `recipes`, `meal_plans`, and `calendar_meals` tables and turns on Row Level Security.

3. Use an email address that belongs to the Supabase organization to test the app's magic-link sign-in.

4. Verify the full flow:

   - Request a sign-in link in the app.
   - Open the link on the same simulator or device.
   - Confirm the app opens signed in.
   - Create a recipe, meal plan, and calendar entry.
   - Relaunch the app and confirm the data is still present.

## Development limitations

- Supabase's built-in email sender only sends to organization members.
- It is rate-limited to two auth emails per hour.
- It uses the default magic-link email, not a branded six-digit-code email.

These are acceptable for personal development only.

## Before inviting external testers or launching

1. Buy or use a domain you control.
2. Configure custom SMTP (for example, Resend) in Supabase.
3. Set up SPF, DKIM, and DMARC DNS records for the sending domain.
4. Change the sender to something like `Taverley <no-reply@auth.yourdomain.com>`.
5. Decide whether to retain magic links or restore six-digit email codes. The ready-to-use code email is in [magic-link.html](../supabase/templates/magic-link.html).
6. Test sign-in and account recovery with non-team email addresses.
7. Review Supabase Auth rate limits and error logs.

## Apple sign-in: defer until release preparation

1. Enroll in the Apple Developer Program.
2. Finalize and register the production bundle ID. Do not change it after release.
3. Enable the **Sign in with Apple** capability for that App ID.
4. Add the entitlement in Xcode, implement the Apple credential flow, and link the resulting identity to the same Supabase user account.
5. Test on a signed physical device and through TestFlight.

## Future product work

- Add account settings: display name, profile editing, and sign out.
- Add avatar image upload to Supabase Storage instead of device-only storage.
- Add sync status and error feedback in the app rather than silently retrying after a failed save.
- Add conflict handling for edits made from multiple devices.
- Add data export and account deletion controls before public launch.
