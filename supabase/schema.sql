-- Optional permanent storage for EVE MOMENTUM BURST v1.00
-- Run once in a separate Supabase project.

create table if not exists public.eve_momentum_scans (
  id text primary key,
  "receivedAt" timestamptz default now(),
  account text,
  symbol text,
  magic text,
  "barTime" bigint,
  decision text,
  "watchDirection" text,
  "buyScore" integer,
  "sellScore" integer,
  "scoreGap" integer,
  "blockReason" text,
  regime text,
  "regimeReason" text,
  "m5Confirmation" text,
  atr double precision,
  "atrRatio" double precision,
  "velocityAtr" double precision,
  "bodyRatio" double precision,
  "volumeRatio" double precision,
  "extensionAtr" double precision,
  "spreadPoints" double precision,
  "medianSpreadPoints" double precision,
  resistance double precision,
  support double precision,
  "buyComponents" text,
  "sellComponents" text
);

create table if not exists public.eve_momentum_trades (
  id text primary key,
  "receivedAt" timestamptz default now(),
  account text,
  symbol text,
  magic text,
  ticket text,
  "positionId" text,
  side text,
  volume double precision,
  "entryTime" bigint,
  "exitTime" bigint,
  "entryPrice" double precision,
  "exitPrice" double precision,
  "entryScore" integer,
  "oppositeScore" integer,
  "entryRegime" text,
  "entryReason" text,
  "exitReason" text,
  "netProfit" double precision,
  mfe double precision,
  mae double precision,
  "durationSeconds" integer,
  "closeAttempts" integer,
  "closeTriggerProfit" double precision,
  status text
);

create table if not exists public.eve_momentum_events (
  id text primary key,
  at timestamptz default now(),
  type text,
  message text,
  data jsonb
);

alter table public.eve_momentum_scans enable row level security;
alter table public.eve_momentum_trades enable row level security;
alter table public.eve_momentum_events enable row level security;

-- No public policies are created. Railway writes with the service-role key.
create index if not exists eve_momentum_scans_bar_time_idx on public.eve_momentum_scans ("barTime" desc);
create index if not exists eve_momentum_trades_exit_time_idx on public.eve_momentum_trades ("exitTime" desc);
