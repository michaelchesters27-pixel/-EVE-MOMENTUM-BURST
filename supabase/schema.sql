-- Optional permanent storage for EVE MOMENTUM BURST v1.10.
-- Safe to run on a new project or on the v1.00 tables.

create table if not exists public.eve_momentum_scans (
  id text primary key,
  "receivedAt" timestamptz default now(),
  account text,
  symbol text,
  magic text,
  "barTime" bigint,
  "snapshotMs" numeric,
  decision text,
  "watchDirection" text,
  "momentumState" text,
  "buyScore" integer,
  "sellScore" integer,
  "scoreGap" integer,
  "blockReason" text,
  regime text,
  "regimeReason" text,
  "m5Confirmation" text,
  atr double precision,
  "atrRatio" double precision,
  "velocity1s" double precision,
  "velocity3s" double precision,
  "velocity10s" double precision,
  "velocity30s" double precision,
  acceleration double precision,
  "tickRateRatio" double precision,
  "bodyAtr" double precision,
  "bodyRatio" double precision,
  "extensionAtr" double precision,
  "extensionLimitAtr" double precision,
  "spreadPoints" double precision,
  "medianSpreadPoints" double precision,
  "microHigh" double precision,
  "microLow" double precision,
  "microBreakBuy" boolean,
  "microBreakSell" boolean,
  "buyComponents" text,
  "sellComponents" text
);

create table if not exists public.eve_momentum_trades (
  id text primary key,
  "receivedAt" timestamptz default now(),
  account text,
  symbol text,
  magic text,
  side text,
  volume double precision,
  "positionsOpened" integer,
  "maxConcurrentPositions" integer,
  "entryTime" bigint,
  "exitTime" bigint,
  "entryPrice" double precision,
  "exitPrice" double precision,
  "entryScore" integer,
  "oppositeScore" integer,
  "entryRegime" text,
  "entryState" text,
  "entryReason" text,
  "exitReason" text,
  "netProfit" double precision,
  mfe double precision,
  mae double precision,
  "durationSeconds" integer,
  "closeAttempts" integer,
  "closeTriggerProfit" double precision,
  "peakBasketProfit" double precision,
  "targetMoney" double precision,
  "trailStartMoney" double precision,
  "givebackMoney" double precision,
  status text
);

create table if not exists public.eve_momentum_events (
  id text primary key,
  at timestamptz default now(),
  type text,
  message text,
  data jsonb
);

-- Upgrade columns for an existing v1.00 project.
alter table public.eve_momentum_scans add column if not exists "snapshotMs" numeric;
alter table public.eve_momentum_scans add column if not exists "momentumState" text;
alter table public.eve_momentum_scans add column if not exists "velocity1s" double precision;
alter table public.eve_momentum_scans add column if not exists "velocity3s" double precision;
alter table public.eve_momentum_scans add column if not exists "velocity10s" double precision;
alter table public.eve_momentum_scans add column if not exists "velocity30s" double precision;
alter table public.eve_momentum_scans add column if not exists acceleration double precision;
alter table public.eve_momentum_scans add column if not exists "tickRateRatio" double precision;
alter table public.eve_momentum_scans add column if not exists "bodyAtr" double precision;
alter table public.eve_momentum_scans add column if not exists "extensionLimitAtr" double precision;
alter table public.eve_momentum_scans add column if not exists "microHigh" double precision;
alter table public.eve_momentum_scans add column if not exists "microLow" double precision;
alter table public.eve_momentum_scans add column if not exists "microBreakBuy" boolean;
alter table public.eve_momentum_scans add column if not exists "microBreakSell" boolean;

alter table public.eve_momentum_trades add column if not exists "positionsOpened" integer;
alter table public.eve_momentum_trades add column if not exists "maxConcurrentPositions" integer;
alter table public.eve_momentum_trades add column if not exists "entryState" text;
alter table public.eve_momentum_trades add column if not exists "peakBasketProfit" double precision;
alter table public.eve_momentum_trades add column if not exists "targetMoney" double precision;
alter table public.eve_momentum_trades add column if not exists "trailStartMoney" double precision;
alter table public.eve_momentum_trades add column if not exists "givebackMoney" double precision;

alter table public.eve_momentum_scans enable row level security;
alter table public.eve_momentum_trades enable row level security;
alter table public.eve_momentum_events enable row level security;

create index if not exists eve_momentum_scans_received_at_idx on public.eve_momentum_scans ("receivedAt" desc);
create index if not exists eve_momentum_trades_exit_time_idx on public.eve_momentum_trades ("exitTime" desc);

-- No public policies are created. Railway writes with the service-role key.
