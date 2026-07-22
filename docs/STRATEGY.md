# Strategy specification

## Core objective

Trade short XAUUSD M1 directional bursts while rejecting weak, expensive, extended or badly located entries.

## BUY/SELL score — 11 points

Each direction is scored independently on the last fully closed M1 candle.

1. **ATR-normalised velocity — 2 points**
   - Weighted movement over 1, 3 and 5 closed candles.
   - Direction must exceed 0.35 ATR by default.
2. **Candle strength — 2 points**
   - Body is at least 60% of range.
   - Bullish close is near the high; bearish close is near the low.
3. **Breakout — 2 points**
   - Closed candle breaks the previous 10-candle range with an ATR buffer.
4. **ATR expansion — 1 point**
   - Current ATR is at least 1.10 times its recent average.
5. **Tick-volume expansion — 1 point**
   - Last closed candle volume is at least 1.20 times its recent average.
6. **EMA alignment — 1 point**
   - EMA9 above/below EMA21.
7. **EMA slope — 1 point**
   - EMA9 rising/falling over three bars.
8. **Directional consistency — 1 point**
   - At least two of the latest three closed candles support the direction.

Default entry requirement:

- Normal/high-momentum regime: at least 7/11.
- Quiet regime: at least 8/11.
- Directional score advantage: at least 3 points.
- M5 confirmation must support the selected direction.

## Anti-chase and location protection

A qualified score is still rejected when:

- Price is more than 0.85 ATR from EMA9.
- More than four same-direction candles have already printed.
- A BUY is within 0.30 ATR of recent M5 resistance without a confirmed breakout.
- A SELL is within 0.30 ATR of recent M5 support without a confirmed breakout.

This directly addresses the risk of buying a bullish bias at resistance immediately before a retracement.

## Market regimes

- `QUIET` — compressed ATR or EMA separation; threshold becomes stricter.
- `NORMAL` — normal directional conditions.
- `HIGH_MOMENTUM` — expanding ATR, velocity and score.
- `CHAOTIC` — abnormal spread; no entry.

## Position management

- One position maximum.
- Fixed 0.01 lot default.
- Initial SL: 1.00 ATR.
- Initial TP: 1.20 ATR.
- Break-even begins at +0.45 ATR and includes a cost buffer.
- Trailing begins at +0.60 ATR.
- Strong momentum uses a wider 0.45 ATR trail.
- Normal momentum uses 0.30 ATR.
- Weakening momentum uses 0.18 ATR.
- Confirmed opposite M1 score plus M5 reversal may close a profitable position.
- Maximum holding time: 15 minutes.

## Daily safety

- Maximum daily loss: 2% of start-of-day balance.
- Daily profit stop: 3%.
- Maximum trades: 20 per UTC day.
- Maximum consecutive losses: 4.
- New day state persists across MT5 restarts through terminal Global Variables.

## Deliberately excluded from v1.00

- Burst entries
- Multi-position baskets
- Pending ladders
- Pyramiding
- Martingale
- Averaging into losses
- Automatic high-impact calendar API

A manual dashboard news lock is included. Automated news integration should be added only after baseline performance is understood.
