# Boosted Production Line — Project Brief

Internal management app for **Boosted Corporation Pty Ltd**, a JDM dealership and
performance workshop (Tallai, Gold Coast QLD). Specialises in Nissan Skylines —
R32/R33/R34 GT-R — buying, building and selling.

It replaces three things that currently live apart: a physical whiteboard
production line, a Notion sales CRM, and a Notion to-do list. Plus a per-vehicle
expense spreadsheet.

---

## Current state

**Phase 1 prototype, working, not yet live.** Single HTML file, no build step,
no dependencies except the Supabase client from CDN.

| File | What it is |
|---|---|
| `boosted-home.html` | The whole app. Open it in a browser and it runs. |
| `schema.sql` | Postgres/Supabase schema covering all phases. Not yet applied. |

Run it: open `boosted-home.html` in a browser. No server needed.

### What works now
- Four boards on one page: To Do, Production Line, Costs & Margin, Sales CRM
- Drag and drop between lanes/stages/lists (desktop); tap-to-edit on touch
- Add / edit / delete on all four
- Costs & Margin — click a vehicle row to log expenses by category, set
  asking/sale price and purchase date; profit, ROI and days-held are computed
  client-side the same way `vehicle_margins` computes them in Postgres
- Global search filtering all boards simultaneously
- KPI strip across the top summarising all systems, including open-stock spend
- Call mode — Tinder-style lead queue with swipe, tap-to-call, follow-up scheduling
- Persistence via browser storage, plus JSON export/import
- Supabase wiring present but **disabled** (config constants are blank)

### What does not work yet
- Auth is one shared login for the whole team, not per-person accounts —
  fine for now, but nobody can be told apart in the data (see below)
- No sync conflict handling beyond realtime overwrite-on-change
- No website integration
- Supabase path is written but **never tested against a real project** —
  expect column-name mismatches on first connect

### Why there's a login at all
This repo is **public** (`www.bnrmotorsports.com.au` is served from it via
GitHub Pages). The Supabase anon key is meant to be public — it's not a
secret — but only if Row Level Security actually blocks unauthenticated
requests. `schema.sql`'s policies already require a logged-in user with a
`profiles` row, so wiring up sign-in was the only way to go live without
publishing every customer's name and phone number to anyone who finds the
repo. One shared login (not per-person) satisfies that — see "Go live" below.

---

## Architecture and conventions

Deliberately a single file with no build step, so it can be opened, edited and
hosted anywhere without tooling. **Keep it that way unless there's a real reason
not to** — the owner maintains this himself.

### The `db` layer is the important bit
Every read and write goes through the `db` object. In local mode its methods are
no-ops on in-memory arrays; in live mode the same calls hit Postgres. This is why
going live is a two-line config change and not a rewrite.

**Do not bypass `db` and mutate the arrays directly in new code.**

### Field name translation
The app's card shape is friendlier than the table's columns, so there's a
translation layer at the boundary (`toVehicleRow` / `fromVehicleRow`, and the
same for deals and tasks):

| App | Table |
|---|---|
| `chassis` | `chassis_no` |
| `desc` | `model` |
| `lane` | `lane_id` |
| `colour` | `card_colour` |
| `who` | `assigned_initials` |
| `value` (deal) | `offer_amount` |
| `want` (deal) | `looking_for` |
| `when` (task) | `due_time` |
| `asking` (vehicle) | `asking_price` |
| `sale` (vehicle) | `sale_price` |
| `purchaseDate` (vehicle) | `purchase_date` |
| `desc` (expense) | `description` |
| `isQuote` (expense) | `is_quote` |
| `date` (expense) | `incurred_on` |

If you rename a field, update both sides.

### Data model
Lanes and stages are **data, not hardcoded** — see the `lanes` table and the
`LANES`/`STAGES`/`LISTS` arrays. Renaming or reordering a lane shouldn't need a
code change.

`stage_history` is written on every lane change. This is what makes
days-in-stage and reconditioning-time reporting possible later — data the
spreadsheet could never capture. **Don't drop it as unused.**

---

## Decisions already made (don't relitigate without asking)

1. **Custom app, not Airtable.** Chosen because the board must eventually share a
   database with invoicing, expenses and the public website. Off-the-shelf tools
   force webhook glue at exactly that seam.

2. **Supabase over a hand-rolled backend.** Postgres + auth + row-level security +
   realtime out of the box. Free tier is ample at ~30 vehicles and <10 users.

3. **Permissions enforced in the database, not the UI.** Hiding fields in the
   frontend is not security. Importers connect through the `vehicles_importer`
   view, which does not contain price columns at all. RLS is row-level in
   Postgres, so column restriction has to be done with views — that's why the
   view exists.

4. **Profit and ROI are computed views, never stored.** The original spreadsheet
   showed −100% ROI and `#DIV/0!` on a car that actually made +71.7% ($31,311 on
   $43,688.85 cost). Broken formulas silently misreporting a good car as a total
   loss is the specific failure this design prevents.

5. **Expenses are per-vehicle child rows, categorised** (acquisition, freight,
   compliance, mechanical, paint_body, parts, detail, marketing, other).
   Quotes-pending are flagged with `is_quote` so they show without corrupting totals.

6. **Leads link to actual stock.** Free text like "wants a gun metal 32" became a
   `vehicle_id`. Three separate buyers in the real data want the same car; the
   link is what surfaces that.

7. **Business overheads (rent, wages, tooling) stay out** — per-vehicle costing
   only. Full P&L belongs in Xero/MYOB.

---

## Roadmap

Ordered so the app is usable early and layers on top of something already in
daily use. Do not build these in parallel.

- **Phase 0 — Schema.** Done (`schema.sql`), not yet applied to a project.
- **Phase 1 — Board live on Supabase.** ← next
  Create project, run schema, fill config, replace seed arrays with queries,
  add auth, add realtime, deploy.
- **Phase 2 — Expenses.** Expense entry UI and the per-vehicle cost/margin
  panel now exist (Costs & Margin board). Remaining: import the existing
  spreadsheets so historical vehicles aren't started from zero.
- **Phase 3 — Roles.** RLS policies live, importer onboarded against the
  restricted view. Deliberately after Phase 2 so there's real data to protect.
- **Phase 4 — CRM depth.** Contacts/deals fully migrated from Notion,
  follow-up queue, lost-reason reporting, source attribution.
- **Phase 5 — Website sync.** `public_listings` view, publish toggle, enquiry
  capture writing back into the CRM.

---

## Open questions

- **Lane structure is unvalidated.** Owner is trialling the app solo for a week.
  Expect the lanes to change afterwards. Don't harden anything that assumes them.
- **Seed data was transcribed from a photo of the whiteboard at an angle.**
  Several chassis numbers are probably wrong. The owner's corrected export
  replaces it.
- **Call mode follow-up rules are a first guess** (keen = 1 day, not keen = 3 days),
  set in `CALL_RULES`. Daily calls may be too aggressive; a "snooze until date"
  option may matter more than the good/bad split. Also undecided: whether N
  "not keen" swipes should auto-move a lead to Lost.
- **Does the importer see the Sold lane?** Currently yes (read-only). It gives
  them arrival tracking but also visibility on sell-through rate.
- **Pending quote in margin** — currently shown as a separate "cost incl. pending"
  line rather than folded into headline profit. Not settled.

---

## Constraints

- **Real customer data.** The CRM holds buyer names, phone numbers and licence
  numbers. As a licensed motor dealer (QLD Motor Dealer Licence No. 4598539) the
  Australian Privacy Act applies. Don't add analytics, third-party scripts, or
  anything that ships this data off-site. Don't commit exported JSON to a public repo.
- **The owner maintains this.** Favour boring, readable, dependency-light code
  over clever abstractions.
- **iOS matters.** HTML5 drag-and-drop does not fire on iOS Safari — that's why
  touch devices get tap-to-edit and the call mode has real swipe handlers.
  Test any new interaction on touch.

---

## Suggested first task

Apply `schema.sql` to a new Supabase project, fill in `SUPABASE_URL` and
`SUPABASE_ANON_KEY`, and get the board reading and writing live. Expect to fix
one or two column mismatches in the translation layer — that path has never been
run. Verify realtime works with two browser windows open before moving on.

---

## Go live (Supabase)

1. supabase.com → New project (free tier is enough at this scale).
2. SQL Editor → paste all of `schema.sql` → Run.
3. Authentication → Users → Add user. One email/password for the whole
   team is enough — this isn't meant to be per-person yet.
4. Copy that user's UUID from the Users table, then in the SQL Editor:
   ```sql
   insert into profiles (id, full_name, role)
   values ('<uuid-from-step-3>', 'Boosted Staff', 'owner');
   ```
   Skipping this is the most likely failure mode: login succeeds but the
   board stays empty, because RLS has nothing to match `auth.uid()` against.
5. Settings → API → copy the Project URL and the `anon public` key into
   `SUPABASE_URL` / `SUPABASE_ANON_KEY` at the top of the script in
   `boosted-home.html`.
6. Reload. A sign-in screen should appear — log in with the account from
   step 3. Share that same email/password with the rest of the team.

Don't skip step 3-4 to save time. Without a real login gate, the anon key
sitting in this public repo would let anyone on the internet read and edit
every customer's name and phone number — not a hypothetical, since this
repo backs a live public website.
