# EVE MOMENTUM BURST v2.08

This is the complete GitHub-ready replacement for v2.06/v2.07.

## Exact strategy

1. While flat, the EA keeps one BUY STOP above price and one SELL STOP below price for the current M1 candle.
2. The first triggered order starts a provisional direction.
3. The opposite stop remains active while the EA places the second same-direction stop.
4. The second same-direction trigger confirms direction only when its actual broker fill progressed correctly:
   - a later BUY must fill higher than the previous BUY;
   - a later SELL must fill lower than the previous SELL.
5. After confirmation, the opposite stop is cancelled and the same-direction stop ladder is replenished continuously.
6. Every position has its own broker-side SL and no fixed TP.
7. The newest leg's SL is placed beyond the previous trigger so a normal reversal banks the older positions.
8. When the newest SL is hit, all pending orders are quarantined/cancelled and the remaining basket is closed.
9. The EA immediately returns to the current-candle straddle. There is no strategy cooldown.

## v2.08 execution-safety correction

v2.08 fixes the exact failure seen during the wide-spread execution:

- A BUY fill below/equal to the previous BUY can never confirm a BUY ladder.
- A SELL fill above/equal to the previous SELL can never confirm a SELL ladder.
- A fill whose inherited SL is already on the wrong side of the actual fill is rejected as an execution-integrity breach.
- Every tick checks whether Bid has crossed a BUY SL or Ask has crossed a SELL SL while the position is still open.
- A missing broker-side SL is treated as an integrity breach after a one-second attachment grace period.
- Any integrity breach cancels all remaining pending orders and closes the complete campaign.
- During basket closure, pending orders are cancelled before open positions are banked, preventing another planned ladder leg from joining the exit.
- If an order changes from pending to filled while cancellation is being requested, the EA refreshes state instead of repeatedly submitting an invalid delete request.
- On a new candle, the existing two-sided bracket stays live while each side is refreshed individually. The EA no longer deletes both sides first and leaves a prolonged one-sided bracket.

These are execution-integrity protections, not momentum filters, trading sessions, position limits or cooldowns.

## 24/5 operation

There is no automatic momentum-score gate, session filter, campaign-duration gate, daily-loss lock, consecutive-loss lock, position ceiling, total-lot ceiling or strategy cooldown. The EA operates whenever MT5 is connected, Algo Trading is enabled and the broker accepts orders.

Manual **Pause**, **Close Basket**, **Emergency Stop** and dashboard Autonomous controls remain available.

## Migration safety

- v2.08 magic number: `2207202608`
- v2.08 order comments: `EVE28-INIT`, `EVE28-CONF`, `EVE28-LAD`
- previous v2.06/v2.07 magic: `2207202606`

v2.08 removes recognised v2.06/v2.07 pending EVE orders before starting. It refuses to overlap an open v2.06/v2.07 position. Close old positions first, then attach v2.08.

## Repository structure

- `mt5/EVE_Momentum_Burst_EA_v2.08.mq5` — complete EA source
- `railway/` — dashboard, controls, evidence and exports
- `supabase/schema.sql` — optional permanent database
- `tools/validate_source.py` — static source/package validator
- `tools/test_execution_safety.py` — deterministic safety scenarios
- `docs/INSTALL-EASY.md` — deployment steps
- `docs/STRATEGY.md` — state machine
- `docs/TESTING.md` — demo testing procedure
- `docs/VALIDATION.md` — completed checks

## Required final check

MetaEditor is the definitive MQL5 compiler. Compile `mt5/EVE_Momentum_Burst_EA_v2.08.mq5` with **0 errors** and test on the IC Markets demo account before live use.
