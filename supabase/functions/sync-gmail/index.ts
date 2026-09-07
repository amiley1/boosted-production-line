// sync-gmail
//
// Pulls inbox emails from Gmail and drops each one into the To Do
// board's "Gmail" section as a task — one row per email, deduped by
// Gmail's message id so ticking a task off (or deleting it) doesn't
// bring it back on the next run.
//
// Runs on a schedule (see supabase/functions/sync-gmail/README.md for
// setup) — never called from index.html, and no Gmail scope or token
// is ever shipped to the browser or the anon key.
//
// Required secrets (see README):
//   GMAIL_CLIENT_ID, GMAIL_CLIENT_SECRET, GMAIL_REFRESH_TOKEN
// Auto-provided by Supabase at runtime:
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const GMAIL_CLIENT_ID = Deno.env.get('GMAIL_CLIENT_ID')!;
const GMAIL_CLIENT_SECRET = Deno.env.get('GMAIL_CLIENT_SECRET')!;
const GMAIL_REFRESH_TOKEN = Deno.env.get('GMAIL_REFRESH_TOKEN')!;

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
);

// Messages per Gmail API page. Also the page size checked on every
// run once the initial backfill is done (newest mail sorts first).
const PAGE_SIZE = 50;

async function getAccessToken(): Promise<string> {
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: GMAIL_CLIENT_ID,
      client_secret: GMAIL_CLIENT_SECRET,
      refresh_token: GMAIL_REFRESH_TOKEN,
      grant_type: 'refresh_token',
    }),
  });
  if (!res.ok) throw new Error(`token refresh failed: ${res.status} ${await res.text()}`);
  return (await res.json()).access_token;
}

async function listInboxPage(token: string, pageToken?: string) {
  const url = new URL('https://gmail.googleapis.com/gmail/v1/users/me/messages');
  url.searchParams.set('labelIds', 'INBOX');
  url.searchParams.set('maxResults', String(PAGE_SIZE));
  if (pageToken) url.searchParams.set('pageToken', pageToken);
  const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  if (!res.ok) throw new Error(`messages.list failed: ${res.status} ${await res.text()}`);
  return res.json();
}

async function getMessage(token: string, id: string) {
  const url = new URL(`https://gmail.googleapis.com/gmail/v1/users/me/messages/${id}`);
  url.searchParams.set('format', 'metadata');
  url.searchParams.append('metadataHeaders', 'Subject');
  url.searchParams.append('metadataHeaders', 'From');
  const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  if (!res.ok) throw new Error(`messages.get failed: ${res.status} ${await res.text()}`);
  return res.json();
}

// deno-lint-ignore no-explicit-any
function taskTextFrom(msg: any): string {
  const headers = msg.payload?.headers || [];
  const get = (name: string) => headers.find((h: any) => h.name === name)?.value || '';
  const from = get('From').replace(/<.*?>/, '').replace(/"/g, '').trim();
  const subject = get('Subject') || '(no subject)';
  return from ? `${from}: ${subject}` : subject;
}

Deno.serve(async () => {
  try {
    const token = await getAccessToken();

    const { data: state } = await supabase
      .from('gmail_sync_state')
      .select('*')
      .eq('id', 1)
      .single();
    const backfillDone = state?.backfill_done ?? false;

    let inserted = 0;
    let pageToken: string | undefined;

    do {
      // deno-lint-ignore no-explicit-any
      const page: any = await listInboxPage(token, pageToken);
      const ids: string[] = (page.messages || []).map((m: { id: string }) => m.id);

      for (const id of ids) {
        const msg = await getMessage(token, id);
        const { error } = await supabase.from('tasks').insert({
          text: taskTextFrom(msg),
          list_id: 'gmail',
          done: false,
          gmail_message_id: msg.id,
          gmail_thread_id: msg.threadId,
        });
        // Unique violation on gmail_message_id just means this email
        // was already synced — that's the dedup, not a real error.
        if (error && error.code !== '23505') throw error;
        if (!error) inserted++;
      }

      pageToken = page.nextPageToken;
      // Once the full inbox has been backfilled once, only the first
      // (newest) page needs checking on later runs — older mail is
      // already in the table and inserts no-op harmlessly either way.
    } while (pageToken && !backfillDone);

    await supabase
      .from('gmail_sync_state')
      .update({ backfill_done: true, last_synced_at: new Date().toISOString() })
      .eq('id', 1);

    return new Response(JSON.stringify({ ok: true, inserted }), {
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (e) {
    console.error(e);
    return new Response(JSON.stringify({ ok: false, error: String(e) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});
