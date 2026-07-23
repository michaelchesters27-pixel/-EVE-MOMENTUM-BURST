# EVE MOMENTUM BURST v3.02

Complete GitHub-ready replacement for v3.01.

## Why v3.02 exists

v3.01 left a SELL STOP at `4051.92` while live XAUUSD Bid/Ask had already fallen to roughly `4043.24 / 4043.33`.

The exact code fault was in the broker-freeze test. For a SELL STOP it used:

`Bid - order price <= freeze distance`

After price crossed below the order, that value became negative. A negative value always passed the “inside freeze” test, so the EA could classify a crossed, wrong-side order as permanently frozen and refuse to remove it.

v3.02 fixes that fault and adds a deterministic execution supervisor that rebuilds its state from the actual MT5 positions and orders on every management pass.

## Normal operating model

1. Live ticks, M1 ATR and M5 soft bias detect a directional acceleration burst.
2. One directional scout stop is placed: BUY STOP for a BUY burst or SELL STOP for a SELL burst.
3. The pending order has a broker-side expiry when IC Markets supports specified expiration.
4. The first fill becomes the scout and has a real broker-side SL.
5. Scout profit protection has priority over all pending-order cleanup.
6. Position 2 is allowed only after protected scout profit and fresh same-direction re-acceleration.
7. Confirmed positions share one broker-side SL.
8. Only one future ladder order may exist.

## Deterministic execution supervisor

The supervisor derives one state from live MT5 reality:

`IDLE → ARMED → SCOUT → CONFIRMED → EXITING`

Unsafe reality moves the EA into:

`RECOVERY` or `FAULT`

It enforces these invariants:

- BUY STOP must remain above live Ask.
- SELL STOP must remain below live Bid.
- Flat account permits one `INITIAL` pending order only.
- One open scout permits one same-side `CONFIRMATION` order only.
- A confirmed basket permits one same-side `LADDER` order only.
- Duplicate, unknown-role, stale, stuck-transition or wrong-side orders enter recovery immediately.
- A wrong-side order is never mistaken for an order inside the freeze zone.
- Once recovery is latched, deletion continues even if price later moves back to the technically valid side.
- If a recovery order fills and creates a position, the full campaign is closed rather than adopted.
- Recovery clears automatically only when MT5 is genuinely flat and contains no EVE v3.02 pending order.

## Additional execution safety

- Pending orders use server-side expiration where supported.
- First fills are checked against the original planned pending price. Material adverse slippage is an execution-integrity breach and closes the campaign.
- Position 1 profit protection runs before pending cleanup.
- A desired profit SL is clamped to a broker-legal level using stop distance, freeze distance, tick size and an extra buffer.
- If profitable SL protection cannot be placed, Position 1 is closed immediately.
- Mixed BUY/SELL positions close the full campaign.
- The old two-sided research fallback is disabled; v3.02 can arm only one directional scout order.
- Any missing, wrong-side or crossed broker SL triggers full-basket protection.
- Scores remain analytics only.

## Version identity

- EA version: `3.02`
- Railway version: `3.0.2`
- Magic number: `2207202632`
- Order comments: `EVE33-INIT`, `EVE33-CONF`, `EVE33-LAD`
- Persistent state prefix: `EMB302_*`

## Package contents

- `mt5/EVE_Momentum_Burst_EA_v3.02.mq5`
- `railway/`
- `supabase/schema.sql`
- `docs/`
- `tools/`

MetaEditor is the definitive MQL5 compiler. Compile with **0 errors** and test only on the IC Markets demo account until the mandatory recovery tests in `docs/TESTING.md` have passed live.
