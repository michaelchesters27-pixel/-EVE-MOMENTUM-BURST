# EVE MOMENTUM BURST v2.04

A complete replacement for EVE Momentum Burst v2.03. This version implements a strict OCO campaign engine, a controlled rolling ladder, canary banking and a non-blocking telemetry queue. It is a behavioural reconstruction based on the supplied evidence; it is not the original commercial EA source code.

## Correct campaign sequence

1. While flat, the EA builds one BUY STOP above price and one SELL STOP below price.
2. Both entry orders must be confirmed before the straddle is marked ready.
3. The first triggered order permanently selects the campaign's starting direction.
4. The opposite entry-bracket order is cancelled and confirmed gone before ladder additions or reversal logic are permitted.
5. If both entry orders cross before OCO cancellation completes, the first-triggered side is retained and the accidental second side is closed.
6. Additional same-direction legs require price progress, a profitable basket, a profitable newest leg, spacing, acceleration and momentum confirmation.
7. A separate reversal stop is not armed immediately. It is created only after the campaign has aged and developed protected profit.
8. The reversal stop is fixed at the campaign's hard invalidation area rather than chasing ordinary M1 price noise.
9. Canary and basket giveback rules bank the campaign before another straddle can be created.
10. A post-campaign cooldown prevents immediate spread-paying re-entry in the same range.

## Connection hardening

- No HTTP call is made from `OnTick` or `OnTradeTransaction`.
- Legs, orders, baskets, banking decisions, scans and events are queued locally.
- The one-second timer sends at most one blocking network request per pass.
- Heartbeats always have priority over command polling and evidence uploads.
- WebRequest timeout is reduced to 800 ms.
- Dashboard status remains CONNECTED for 45 seconds, DELAYED from 45 to 120 seconds, and OFFLINE only after 120 seconds.
- A delayed dashboard does not stop local MT5 trade management.

## Demo testing mode

Enabled by default. Consecutive losses, daily P/L and basket count are recorded but cannot automatically lock new entries. Manual pause, news lock, close and emergency controls remain active.

## Repository structure

- `mt5/EVE_Momentum_Burst_EA_v2.04.mq5` — complete EA source
- `railway/` — dashboard, controls, persistence, CSV exports and analysis
- `supabase/schema.sql` — optional permanent evidence database
- `docs/INSTALL-EASY.md` — deployment steps
- `docs/STRATEGY.md` — detailed campaign logic
- `docs/TESTING.md` — demo validation process
- `docs/VALIDATION.md` — checks completed in this package

## Identity

- Magic number: `2207202603`
- Trade comment: `EVE-MOMENTUM-V2.04`
- Railway root directory: `railway`
- Chart: `XAUUSD M1`
- Railway domain: `https://eve-momentum-burst-production.up.railway.app`

MetaEditor is the definitive MQL5 compilation check.
