# EVE MOMENTUM BURST v3.01

Complete GitHub-ready replacement for v3.00.

## Why v3.01 exists

v3.00 detected the scout profit-lock condition, but a live IC Markets request was rejected as `invalid stops` while a pending-order cancellation was `frozen`. The EA then failed to choose a broker-legal fallback SL or close the profitable scout immediately. v3.01 fixes that exact execution path.

The earlier supplied v2.11 MT5 history was isolated by its `EVE31-*` comments. It contained 55 completed baskets and 70 positions.

The decisive finding was:

- 43 one-position baskets: **+$3.70 net**;
- 12 baskets with two or three positions: **-$8.52 net**;
- none of the multi-position baskets won;
- no completed `EVE31-LAD` position appeared in the report.

The scout position showed an edge. Adding a second position too easily destroyed it. v3.01 therefore protects the scout first and permits extra size only after the move proves itself again.

See `docs/V2.11-REPORT-ANALYSIS.md` for the complete isolated breakdown.

## v3.01 operating model

1. The EA watches live broker ticks continuously.
2. M1 ATR defines what meaningful movement looks like.
3. M5 supplies a soft directional bias.
4. A direction-consistent acceleration burst arms **one pending stop only**:
   - BUY burst → one BUY STOP;
   - SELL burst → one SELL STOP.
5. When that order triggers, it becomes the **scout position**.
6. Every other pending EVE order is removed. The EA never opens an opposite reversal or hedge inside that campaign.
7. The scout receives a real broker-side SL.
8. After useful profit appears, its SL dynamically protects about 65% of the best floating profit, subject to broker distance and execution.
9. If live momentum stalls while useful profit remains, the EA banks the scout instead of waiting for a deeper retracement.
10. Position 2 is considered only after all of these are true:
    - scout peak profit is at least $0.60;
    - estimated current net profit is at least $0.35;
    - a broker-side profit lock is already active;
    - price re-accelerates in the same direction;
    - tick activity expands;
    - a fresh same-direction micro-break occurs;
    - M5 is not directly opposite.
11. Position 2 and the scout share the same broker-side SL.
12. After confirmation, only one future ladder stop is allowed, and only while the basket is already profitable and price re-accelerates again.

## Default protection values

- Initial scout SL: `0.75 × M1 ATR`, adjusted for broker rules.
- Fixed TP: none.
- Profit-lock trigger: `$0.20` peak.
- Minimum intended protected net profit: `$0.10`.
- Profit-lock giveback: `35%`, retaining about `65%` of peak.
- Momentum-stall bank activates after at least `$0.25` peak and `$0.05` estimated current net.
- Position 2 proof: `$0.60` peak and `$0.35` estimated current net plus live re-acceleration.

These are EA inputs and can be changed later after a meaningful demo sample. They are not controlled by the dashboard analytics score.

## Execution safety

- Position 1 profit protection runs before any pending-order cleanup, freeze wait or legacy cleanup.
- The requested lock is clamped to the nearest broker-legal price using both stop-level and freeze-level distance plus a safety buffer.
- If the desired lock is rejected, the EA retries once farther from price.
- If no profitable legal SL is possible, or the broker rejects both SL attempts, the EA closes Position 1 first and cleans pending orders afterwards.
- Frozen pending orders cannot block the urgent Position 1 close path.
- Wide spread removes pending entries but leaves open positions protected.
- BUY SL watchdog uses Bid.
- SELL SL watchdog uses Ask.
- Wrong-sequence or non-progressing fills close the full campaign.
- Any mixed BUY/SELL state closes the full campaign; no reversal is adopted.
- A fill whose SL is already invalid closes the campaign.
- Pending orders are cancelled before forced basket closure.
- Only one confirmation or ladder pending order may survive.
- v2.09, v2.10 and v2.11 orders are isolated from v3.01.
- Railway performance is filtered to v3.01 magic `2207202631`; older dashboard records are excluded.

## Version identity

- EA version: `3.01`
- Railway version: `3.0.1`
- Magic number: `2207202631`
- Order comments: `EVE32-INIT`, `EVE32-CONF`, `EVE32-LAD`
- Persistent state prefix: `EMB301_*`

## Package contents

- `mt5/EVE_Momentum_Burst_EA_v3.01.mq5`
- `railway/`
- `supabase/schema.sql`
- `docs/`
- `tools/`

MetaEditor is the definitive MQL5 compiler. Compile with **0 errors** and test on the IC Markets demo account before any live consideration.
