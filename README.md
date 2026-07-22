# EVE Momentum Burst v2.00

A full replacement for v1.10, reconstructed from the visible operating behaviour supplied in screenshots. It is not Mark Flipper's proprietary source code.

## Core engine

1. While flat, the EA maintains a moving BUY STOP above price and SELL STOP below price.
2. The first breakout order triggered chooses the initial direction.
3. The opposite pending order is repositioned as a stop-and-reverse trigger.
4. The EA adds same-direction market legs while live velocity, acceleration and tick activity remain strong.
5. Every position receives its own broker-side SL, TP, break-even and graduated trailing stop.
6. Older positions receive more trailing room; the newest positions are protected more tightly.
7. The newest position is the momentum canary. Its current and peak profit are tracked.
8. The ladder banks when the canary gives back its progress, turns negative after developing, the basket gives back configured peak profit, or opposite acceleration takes control.
9. Individual legs may close without forcing the complete ladder to close.
10. All basket closes use transaction-safe CLOSE PENDING and automatic retry.

## Dashboard lot control

- Fixed lot per position
- Initial positions
- Maximum open positions
- Maximum total lots
- Optional balance-scaled lots
- Equity amount represented by each 0.01 lot

Settings are stored by Railway and polled by MT5. They apply only to future entries.

## Evidence database

The dashboard records and exports:

- completed baskets
- every individual position leg
- every pending-order placement, cancellation and rejection
- every banking decision
- live momentum scans
- settings and control events

Summary analysis includes win rate, profit factor, net profit, average basket, duration, peak floating profit, giveback, drawdown, BUY/SELL performance and banking-reason performance.

## Deployment

- GitHub repository: `EVE-MOMENTUM-BURST`
- Railway root directory: `railway`
- MT5 chart: XAUUSD M1
- Magic number: `2207202603`
- Railway domain: `https://eve-momentum-burst-production.up.railway.app`

Read `DEPLOY-THIS-FIRST.txt` and `docs/INSTALL-EASY.md`.
