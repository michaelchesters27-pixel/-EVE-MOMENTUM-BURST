# EVE MOMENTUM BURST v2.05

This is the complete GitHub-ready replacement for v2.04.

v2.05 runs the exact candle-triggered ladder requested:

1. While flat, every new M1 candle receives one BUY STOP and one SELL STOP.
2. The first triggered order starts a provisional direction.
3. The opposite stop remains active while the bot places the second same-direction stop.
4. The second same-direction trigger confirms the direction.
5. Only after that second trigger does the EA cancel the opposite stop.
6. The EA then stages 12 same-direction stop orders ahead of price and continuously replenishes them. The campaign itself has no position-count, total-lot, score, session, duration or strategy-cooldown gate.
7. Every triggered position has its own broker-side stop loss and no fixed take profit.
8. Confirmation and ladder orders are automatically spaced far enough for the newest order's SL to sit beyond the previous trigger price. For a BUY ladder, the newest SL is above the prior BUY trigger; for a SELL ladder, it is below the prior SELL trigger.
9. When the newest triggered position closes by broker-side SL, the EA immediately closes all older campaign positions, then removes every remaining pending order.
10. It immediately returns to the current-candle straddle with no post-campaign cooldown.
11. If the opposite stop triggers before the second same-side confirmation, the first direction is treated as a false breakout: the failed position is closed and the newly triggered side becomes provisional.

## 24/5 operation

There is no automatic session filter, momentum-score gate, spread gate, daily lock, consecutive-loss lock, campaign timer, position ceiling, total-lot ceiling or strategy cooldown. The EA keeps operating whenever MT5 is connected, Algo Trading is permitted and the broker is accepting orders.

Manual **Pause**, **Close Basket**, **Emergency Stop** and dashboard Autonomous On/Off controls remain available. They are direct user controls, not automatic strategy restrictions. Pause and emergency state persist across midnight until deliberately changed.

A short retry after a rejected, frozen or invalid broker request remains necessary for orderly trade-server communication; it is not an entry cooldown.

## Profit-lock geometry

The default `InpNewestSLPreviousLegLockFraction = 0.65` places a confirmation/ladder leg's SL 65% of the way from the previous trigger toward its own trigger, while also respecting the broker's minimum stop distance. This means the previous same-direction position is beyond break-even by price when the newest SL is reached. Spread, commission, swaps, gaps and slippage can still affect the final net result.

## Important account requirement

Use an MT5 hedging account. During a provisional false-breakout transition, BUY and SELL positions can exist briefly while the failed side is being closed.

## Repository structure

- `mt5/EVE_Momentum_Burst_EA_v2.05.mq5` — complete EA source
- `railway/` — dashboard, controls, persistence, CSV exports and analysis
- `supabase/schema.sql` — optional permanent evidence database
- `tools/validate_source.py` — local structural/source validation
- `docs/INSTALL-EASY.md` — deployment steps
- `docs/STRATEGY.md` — exact state machine
- `docs/TESTING.md` — demo validation sequence
- `docs/VALIDATION.md` — checks completed in this package

## Identity

- Magic number: `2207202603`
- Trade comment: `EVE-MOMENTUM-V2.05`
- Railway root directory: `railway`
- Intended chart: `XAUUSD M1`
- Railway domain: `https://eve-momentum-burst-production.up.railway.app`

MetaEditor is the definitive MQL5 compilation check. Compile with zero errors and test on the IC Markets demo account before any live deployment.
