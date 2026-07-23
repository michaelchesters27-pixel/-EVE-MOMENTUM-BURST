# EVE MOMENTUM BURST v2.11

Complete GitHub-ready replacement for v2.10.

## The key change

v2.11 no longer creates a trade attempt simply because a new M1 candle has opened.

The EA watches live broker ticks continuously. It arms a temporary two-sided BUY STOP / SELL STOP bracket only after it detects a genuine price burst:

- fast 1-second movement;
- sustained 3-second movement in the same direction;
- expanding speed;
- an expanding tick-arrival rate;
- a micro-breakout in the same direction;
- normal spread.

M1 ATR is used to judge whether the movement is meaningful. M5 is a soft directional bias: a counter-trend burst is still allowed, but it must be stronger.

## Campaign operation

1. The live tick engine waits with no pending orders.
2. A genuine burst arms one BUY STOP and one SELL STOP around the recent micro-range.
3. The first triggered position is provisional. The opposite stop remains live.
4. The same-direction confirmation stop is not placed until Position 1 already carries the exact planned shared SL.
5. A second BUY must fill above BUY 1; a second SELL must fill below SELL 1.
6. After confirmation, the opposite stop is cancelled.
7. Every open position receives one identical broker-side basket SL.
8. Only one future ladder stop is permitted at a time.
9. When the shared SL is reached, the campaign is cleared.
10. The EA does not restart on a timer or at the next candle. It waits until live price quietens and then looks for a new burst.

## Position 1 protection

Position 1 has no fixed TP.

After its floating profit reaches the configured trigger, its real broker-side SL moves into profit and retains part of the best profit reached. By default:

- trigger: $0.20;
- minimum intended protected profit: $0.10;
- giveback: 50%.

## Execution safety

- Abnormal spread removes pending entries.
- BUY stop-loss watchdog uses Bid.
- SELL stop-loss watchdog uses Ask.
- Wrong-sequence fills close the campaign.
- A fill whose SL is already invalid closes the campaign.
- Pending orders are cancelled before forced basket closure.
- v2.09 and v2.10 orders are isolated from v2.11.

## Version identity

- EA version: `2.11`
- Railway version: `2.0.11`
- Magic number: `2207202611`
- Order comments: `EVE31-INIT`, `EVE31-CONF`, `EVE31-LAD`
- Persistent state prefix: `EMB211_*`

## Package contents

- `mt5/EVE_Momentum_Burst_EA_v2.11.mq5`
- `railway/`
- `supabase/schema.sql`
- `docs/`
- `tools/`

MetaEditor is the definitive MQL5 compiler. Compile with **0 errors** and run on an IC Markets demo account before considering live use.
