# Testing plan

## Immediate demo test

1. Run on the existing IC Markets demo account only.
2. Attach to XAUUSD M1.
3. Confirm one new scan arrives after each closed M1 candle.
4. Confirm rejected scans contain a clear reason.
5. Confirm the EA never opens more than one position.
6. Confirm SL and TP are attached immediately.
7. Test dashboard pause/resume while flat.
8. Test `Close bot position` on a tiny demo trade.
9. Test Emergency Stop and reset.
10. Export scans and trades as CSV.

## Data requirement before changing strategy

- First review: at least 50 completed trades.
- Major threshold decisions: preferably 100–200 trades across trend and range days.
- Do not change settings after every isolated winner or loss.

## Backtest standard

Use MT5 Strategy Tester with:

- Every tick based on real ticks
- Variable spread
- Commission
- Realistic delay/slippage
- Different months and market regimes

Do not judge an M1 scalper using one-minute OHLC modelling.

## Evidence to compare

- Entry score band
- BUY versus SELL
- Normal versus high-momentum regime
- MFE and MAE
- Exit reason
- Time of day
- Spread ratio
- Extension at entry
- Near-resistance/support blocks
- Win rate, expected payoff, profit factor and drawdown
