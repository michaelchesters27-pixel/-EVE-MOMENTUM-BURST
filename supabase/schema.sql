-- EVE Momentum Burst v2.04 optional permanent research database
-- Run once in Supabase SQL Editor, then add SUPABASE_URL and
-- SUPABASE_SERVICE_ROLE_KEY to Railway Variables.

create table if not exists public.eve_momentum_scans (
  id text primary key,
  captured_at timestamptz not null default now(),
  payload jsonb not null
);
create table if not exists public.eve_momentum_baskets (
  id text primary key,
  captured_at timestamptz not null default now(),
  payload jsonb not null
);
create table if not exists public.eve_momentum_legs (
  id text primary key,
  captured_at timestamptz not null default now(),
  payload jsonb not null
);
create table if not exists public.eve_momentum_orders (
  id text primary key,
  captured_at timestamptz not null default now(),
  payload jsonb not null
);
create table if not exists public.eve_momentum_bank_decisions (
  id text primary key,
  captured_at timestamptz not null default now(),
  payload jsonb not null
);
create table if not exists public.eve_momentum_events (
  id text primary key,
  captured_at timestamptz not null default now(),
  payload jsonb not null
);

create index if not exists eve_momentum_scans_captured_idx on public.eve_momentum_scans(captured_at desc);
create index if not exists eve_momentum_baskets_captured_idx on public.eve_momentum_baskets(captured_at desc);
create index if not exists eve_momentum_legs_captured_idx on public.eve_momentum_legs(captured_at desc);
create index if not exists eve_momentum_orders_captured_idx on public.eve_momentum_orders(captured_at desc);
create index if not exists eve_momentum_bank_captured_idx on public.eve_momentum_bank_decisions(captured_at desc);
create index if not exists eve_momentum_events_captured_idx on public.eve_momentum_events(captured_at desc);

alter table public.eve_momentum_scans enable row level security;
alter table public.eve_momentum_baskets enable row level security;
alter table public.eve_momentum_legs enable row level security;
alter table public.eve_momentum_orders enable row level security;
alter table public.eve_momentum_bank_decisions enable row level security;
alter table public.eve_momentum_events enable row level security;

-- No public policies are created. Railway writes with the service-role key.
