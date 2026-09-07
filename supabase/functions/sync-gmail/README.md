# sync-gmail — setup

Pulls every inbox email into the To Do board's **Gmail** section as a task,
on a schedule, with no browser or Claude session involved once it's running.
Runs as its own Supabase Edge Function — it never touches `index.html`,
never sees the anon key, and the app never gets a Gmail scope.

Do these once, in order.

## 1. Run the database migration

In the Supabase SQL Editor, run
`supabase/migrations/2026-09-07_lists_and_gmail.sql` (paste the whole file,
Run). Adds the `lists` table (also fixes custom To Do sections not
surviving a login), the `gmail` section itself, and the columns/table the
function below needs.

## 2. Google Cloud: get a client ID and secret

1. https://console.cloud.google.com → create a project (any name).
2. **APIs & Services → Library** → search "Gmail API" → Enable.
3. **APIs & Services → OAuth consent screen** → User type "External" →
   fill in app name/support email → **Scopes**: add
   `https://www.googleapis.com/auth/gmail.readonly` → **Test users**: add
   your own Gmail address.
   - Leave it in "Testing" (no Google review needed for personal use), but
     note: Google expires refresh tokens for test-mode apps that go
     unused for 6 months, not on a fixed 7-day timer — fine for a
     function that calls in every 15–30 minutes. If it ever does expire,
     redo step 4 below to get a fresh refresh token.
4. **APIs & Services → Credentials → Create Credentials → OAuth client ID**
   → Application type **Desktop app** → note the **Client ID** and
   **Client Secret**.

## 3. Get a refresh token (one-time, in your browser)

Easiest path — Google's own OAuth Playground, no script to run:

1. https://developers.google.com/oauthplayground
2. Gear icon (top right) → check **"Use your own OAuth credentials"** →
   paste the Client ID and Client Secret from step 2.
3. Left panel → find **Gmail API v1** → tick
   `https://www.googleapis.com/auth/gmail.readonly` → **Authorize APIs** →
   sign in with the Gmail account to sync → allow.
4. **Exchange authorization code for tokens** → copy the **Refresh token**
   shown. That's the one secret you need from this step — the access
   token it also shows expires in an hour and isn't used.

## 4. Deploy the function

Needs the [Supabase CLI](https://supabase.com/docs/guides/cli) installed
locally (`npm install -g supabase`, or see their docs for your OS).

```bash
supabase login
supabase link --project-ref bcwcuuarchoapmkoerqi

supabase secrets set \
  GMAIL_CLIENT_ID=<client id from step 2> \
  GMAIL_CLIENT_SECRET=<client secret from step 2> \
  GMAIL_REFRESH_TOKEN=<refresh token from step 3>

supabase functions deploy sync-gmail
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` don't need setting — Supabase
injects both into every Edge Function automatically.

## 5. Schedule it

Supabase Dashboard → **Edge Functions → sync-gmail → Cron** (or
"Schedules", naming varies by dashboard version) → add a schedule, e.g.
`*/15 * * * *` for every 15 minutes.

If your dashboard doesn't have that yet, the SQL equivalent (uses the
`pg_cron` and `pg_net` extensions — enable both under **Database →
Extensions** first):

```sql
select cron.schedule(
  'sync-gmail-15min',
  '*/15 * * * *',
  $$
  select net.http_post(
    url := 'https://bcwcuuarchoapmkoerqi.supabase.co/functions/v1/sync-gmail',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || '<service_role key, from Project Settings -> API>'
    )
  );
  $$
);
```

## What to expect

- First run walks the **entire** inbox history and adds one task per
  email — if your mate/team has years of mail this could be a lot of
  tasks and may take more than one run to finish (each run picks up
  where dedup leaves off; nothing is lost or duplicated). After that,
  every run only checks the newest ~50 messages.
- Ticking a Gmail task off (or deleting it) is permanent — the same
  email's `gmail_message_id` is never re-inserted.
- If you'd rather it not import your entire mail history, the fix is one
  line: in `index.ts`, change `listInboxPage`'s query to add
  `q: 'newer_than:30d'` (or similar) before the first deploy.
