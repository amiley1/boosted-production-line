-- ============================================================
-- BOOSTED PRODUCTION LINE — DATABASE SCHEMA (Phase 0)
-- Postgres / Supabase
--
-- Designed up front to cover all phases so later work is
-- additive, not a migration:
--   Phase 1  board            -> lanes, vehicles
--   Phase 2  expenses         -> expenses, cost/margin views
--   Phase 3  roles            -> profiles, RLS policies
--   Phase 4  CRM              -> contacts, deals
--   Phase 5  website          -> public_listings view
-- ============================================================


-- ------------------------------------------------------------
-- ENUMS
-- ------------------------------------------------------------

create type user_role as enum ('owner', 'staff', 'importer', 'readonly');

create type vehicle_board as enum ('production', 'personal');

create type expense_category as enum (
  'acquisition',      -- purchase price, deposits, final payments
  'freight',          -- shipping, port, wharf
  'compliance',       -- compliance, rego, inspection
  'mechanical',       -- tune, dyno, engine, driveline
  'paint_body',       -- paint, panel, rust, body kit
  'parts',            -- wheels, exhaust, interior, trim
  'detail',           -- detailing, underside, polish
  'marketing',        -- photography, listing fees, auction fees
  'other'
);

create type contact_type as enum ('buyer', 'seller', 'supplier', 'importer', 'trade');

create type deal_stage as enum ('enquiry', 'negotiating', 'deposit', 'won', 'lost');


-- ------------------------------------------------------------
-- USERS / ROLES
-- Extends Supabase auth.users with an app-level role.
-- ------------------------------------------------------------

create table profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  full_name    text not null,
  initials     text,                        -- shown on board cards
  role         user_role not null default 'readonly',
  active       boolean not null default true,
  created_at   timestamptz not null default now()
);


-- ------------------------------------------------------------
-- LANES
-- Board columns are data, not hardcoded — so you can rename or
-- reorder them without a code change.
-- ------------------------------------------------------------

create table lanes (
  id              serial primary key,
  name            text not null,
  board           vehicle_board not null default 'production',
  position        int  not null,
  importer_access text not null default 'none',   -- 'edit' | 'read' | 'none'
  is_terminal     boolean not null default false, -- Sold / archived
  created_at      timestamptz not null default now()
);

insert into lanes (name, board, position, importer_access, is_terminal) values
  ('Overseas / OR',   'production', 1, 'edit', false),
  ('Waiting',         'production', 2, 'edit', false),
  ('Rust / Repaint',  'production', 3, 'read', false),
  ('Roadtest / Tune', 'production', 4, 'read', false),
  ('Sale Ready',      'production', 5, 'read', false),
  ('Pending',         'production', 6, 'none', false),
  ('Sold',            'production', 7, 'read', true),
  ('Personal Cars',   'personal',   1, 'none', false);


-- ------------------------------------------------------------
-- VEHICLES
-- The core table. Everything else hangs off this.
-- ------------------------------------------------------------

create table vehicles (
  id                uuid primary key default gen_random_uuid(),

  -- identity
  chassis_no        text unique,             -- BNR32-307694
  vin               text,
  job_no            int,                     -- your #36 style numbers
  model             text,                    -- R32 GT-R
  variant           text,                    -- V-Spec, N1, GTS-T
  colour            text,
  build_date        text,                    -- 03/1993
  odometer_km       int,
  transmission      text default 'Manual',
  body              text default 'Coupe',
  fuel_type         text default 'Petrol',
  engine_no         text,
  auction_grade     text,                    -- 4B
  card_colour       text default 'teal',     -- teal | coral | amber

  -- board state
  lane_id           int references lanes(id),
  board             vehicle_board not null default 'production',
  position          int not null default 0,  -- order within lane
  assigned_to       uuid references profiles(id),
  assigned_initials text,                    -- shown on the card (AM, JB)
  notes             text,

  -- import / logistics (importer-editable)
  export_cert       text,
  vessel            text,
  port_departure    text,
  eta_australia     date,
  quarantine_clear  boolean default false,
  compliance_booked boolean default false,
  compliance_date   date,
  sourced_by        uuid references profiles(id),

  -- commercial (restricted)
  asking_price      numeric(12,2),
  sale_price        numeric(12,2),
  purchase_date     date,
  list_date         date,
  sale_date         date,
  sold_to           uuid,                    -- FK added after contacts

  -- website (Phase 5)
  is_published      boolean not null default false,
  public_title      text,
  public_description text,
  photos            text[] default '{}',
  published_at      timestamptz,

  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index on vehicles (lane_id);
create index on vehicles (board);
create index on vehicles (is_published);


-- ------------------------------------------------------------
-- STAGE HISTORY
-- Written automatically on every lane change. This is what makes
-- days-in-stage and reconditioning-time reporting possible —
-- data the spreadsheet could never capture.
-- ------------------------------------------------------------

create table stage_history (
  id           bigserial primary key,
  vehicle_id   uuid not null references vehicles(id) on delete cascade,
  lane_id      int  references lanes(id),
  entered_at   timestamptz not null default now(),
  exited_at    timestamptz,
  moved_by     uuid references profiles(id)
);

create index on stage_history (vehicle_id);


-- ------------------------------------------------------------
-- EXPENSES (Phase 2)
-- One row per cost. Replaces the per-car spreadsheet.
-- ------------------------------------------------------------

create table expenses (
  id             uuid primary key default gen_random_uuid(),
  vehicle_id     uuid not null references vehicles(id) on delete cascade,
  category       expense_category not null,
  description    text not null,
  amount         numeric(12,2),             -- null = quote pending
  is_quote       boolean not null default false,
  gst_inclusive  boolean not null default true,
  supplier       text,
  invoice_ref    text,
  incurred_on    date not null default current_date,
  billed_by      uuid references profiles(id),  -- importer-invoiced costs
  notes          text,
  created_at     timestamptz not null default now()
);

create index on expenses (vehicle_id);
create index on expenses (category);


-- ------------------------------------------------------------
-- CRM (Phase 4)
-- ------------------------------------------------------------

create table contacts (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  type         contact_type not null default 'buyer',
  phone        text,
  email        text,
  location     text,
  licence_no   text,
  source       text,                        -- FB, SAU, auction, referral
  notes        text,
  owner_id     uuid references profiles(id),
  created_at   timestamptz not null default now()
);

alter table vehicles
  add constraint vehicles_sold_to_fkey
  foreign key (sold_to) references contacts(id);

create table deals (
  id             uuid primary key default gen_random_uuid(),
  contact_id     uuid not null references contacts(id) on delete cascade,
  vehicle_id     uuid references vehicles(id) on delete set null,
  stage          deal_stage not null default 'enquiry',
  offer_amount   numeric(12,2),
  deposit_paid   numeric(12,2),
  name           text,                        -- denormalised for fast board render
  phone          text,
  location       text,
  source         text,
  looking_for    text,                        -- 'R32 GTR — gun metal'
  next_follow_up date,
  last_called    date,
  call_count     int not null default 0,
  lost_reason    text,
  notes          text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create index on deals (vehicle_id);
create index on deals (contact_id);


-- ------------------------------------------------------------
-- TASKS (To Do board)
-- list_id matches the LISTS array in the app.
-- ------------------------------------------------------------

create table tasks (
  id           uuid primary key default gen_random_uuid(),
  text         text not null,
  list_id      text not null default 'daily',   -- daily | high | med | low | geoff
  done         boolean not null default false,
  due_time     text,                            -- '08:30' — free text, not a timestamp
  vehicle_id   uuid references vehicles(id) on delete set null,
  assigned_to  uuid references profiles(id),
  created_at   timestamptz not null default now()
);

create index on tasks (list_id);
create index on tasks (vehicle_id);


-- ------------------------------------------------------------
-- DERIVED VIEWS — cost, margin, ROI
-- Calculated, never typed. This is the fix for the broken
-- ROI / #DIV/0! formulas in the spreadsheet.
-- ------------------------------------------------------------

create view vehicle_costs as
select
  v.id                                             as vehicle_id,
  coalesce(sum(e.amount) filter (where not e.is_quote), 0)      as total_cost,
  coalesce(sum(e.amount), 0)                                    as total_cost_incl_quotes,
  count(e.id) filter (where e.is_quote)                         as pending_quotes
from vehicles v
left join expenses e on e.vehicle_id = v.id
group by v.id;

create view vehicle_margins as
select
  v.id,
  v.chassis_no,
  v.model,
  v.asking_price,
  v.sale_price,
  c.total_cost,
  coalesce(v.sale_price, v.asking_price) - c.total_cost          as profit,
  case when c.total_cost > 0
       then round(((coalesce(v.sale_price, v.asking_price) - c.total_cost)
                   / c.total_cost) * 100, 1)
  end                                                           as roi_pct,
  case when v.purchase_date is not null
       then (coalesce(v.sale_date, current_date) - v.purchase_date)
  end                                                           as days_held
from vehicles v
join vehicle_costs c on c.vehicle_id = v.id;


-- ------------------------------------------------------------
-- PUBLIC VIEW (Phase 5)
-- What the website reads. Costs, margin and CRM are not columns
-- here — they cannot leak through the public API.
-- ------------------------------------------------------------

create view public_listings as
select
  id, public_title, public_description, model, variant, colour,
  build_date, odometer_km, transmission, body, fuel_type,
  asking_price, photos, published_at
from vehicles
where is_published = true;


-- ------------------------------------------------------------
-- ROW LEVEL SECURITY (Phase 3)
-- Enforced in the database, not the interface.
-- ------------------------------------------------------------

alter table vehicles  enable row level security;
alter table expenses  enable row level security;
alter table contacts  enable row level security;
alter table deals     enable row level security;
alter table tasks     enable row level security;
alter table profiles  enable row level security;

create or replace function current_role_is(roles user_role[])
returns boolean language sql stable as $$
  select exists (
    select 1 from profiles
    where id = auth.uid() and role = any(roles) and active
  );
$$;

-- Vehicles: staff and owner full access; importers see all rows
-- but are restricted to their lanes for writes.
create policy vehicles_read_all on vehicles for select
  using (current_role_is(array['owner','staff','importer','readonly']::user_role[]));

create policy vehicles_write_staff on vehicles for all
  using (current_role_is(array['owner','staff']::user_role[]));

create policy vehicles_write_importer on vehicles for update
  using (
    current_role_is(array['importer']::user_role[])
    and lane_id in (select id from lanes where importer_access = 'edit')
  );

-- Expenses: importers only ever see rows they billed.
create policy expenses_staff on expenses for all
  using (current_role_is(array['owner','staff']::user_role[]));

create policy expenses_importer_own on expenses for select
  using (current_role_is(array['importer']::user_role[]) and billed_by = auth.uid());

-- CRM: staff only.
create policy contacts_staff on contacts for all
  using (current_role_is(array['owner','staff']::user_role[]));

create policy deals_staff on deals for all
  using (current_role_is(array['owner','staff']::user_role[]));

create policy tasks_staff on tasks for all
  using (current_role_is(array['owner','staff']::user_role[]));

create policy profiles_self on profiles for select using (true);


-- ------------------------------------------------------------
-- NOTE ON PRICE COLUMNS
-- RLS is row-level, not column-level. To keep sale_price and
-- asking_price away from importers, the app queries a restricted
-- view for that role rather than the base table:
-- ------------------------------------------------------------

create view vehicles_importer as
select
  id, chassis_no, vin, job_no, model, variant, colour, build_date,
  odometer_km, transmission, body, fuel_type, auction_grade,
  lane_id, board, position, notes, card_colour,
  export_cert, vessel, port_departure, eta_australia,
  quarantine_clear, compliance_booked, compliance_date
from vehicles;
