-- ============================================================
-- MIGRATION: lists table + Gmail sync support
--
-- schema.sql now includes this permanently for fresh installs.
-- This file is for the already-live database — paste it into the
-- Supabase SQL Editor and run once. Safe to re-run: every statement
-- either uses IF NOT EXISTS or is naturally idempotent.
-- ============================================================

create table if not exists lists (
  id         text primary key,
  name       text not null,
  colour     text not null default 'var(--purple)',
  position   int  not null default 0,
  created_at timestamptz not null default now()
);

insert into lists (id, name, colour, position) values
  ('daily', 'Daily WDL',     'var(--purple)', 1),
  ('high',  'High Priority', 'var(--red)',    2),
  ('med',   'Medium',        'var(--amber)',  3),
  ('low',   'Low',           'var(--green)',  4),
  ('geoff', 'Geoff',         'var(--teal)',   5),
  ('gmail', 'Gmail',         'var(--coral)',  6)
on conflict (id) do nothing;

alter table tasks add column if not exists gmail_message_id text unique;
alter table tasks add column if not exists gmail_thread_id  text;

create table if not exists gmail_sync_state (
  id             int primary key default 1,
  backfill_done  boolean not null default false,
  last_synced_at timestamptz,
  check (id = 1)
);

insert into gmail_sync_state (id) values (1) on conflict (id) do nothing;

-- Baseline grants — same statement as in schema.sql. Re-running it is
-- what makes the two new tables visible to RLS at all (Postgres checks
-- table-level grants before RLS is ever evaluated).
grant usage on schema public to anon, authenticated, service_role;
grant all on all tables in schema public to anon, authenticated, service_role;
grant all on all sequences in schema public to anon, authenticated, service_role;

alter table lists            enable row level security;
alter table gmail_sync_state enable row level security;

drop policy if exists lists_staff on lists;
create policy lists_staff on lists for all
  using (current_role_is(array['owner','staff']::user_role[]));

drop policy if exists gmail_sync_state_none on gmail_sync_state;
create policy gmail_sync_state_none on gmail_sync_state for select using (false);
