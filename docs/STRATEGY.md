# Strategy — v4.10

This is an evidence-based behavioural reconstruction, not the original proprietary EA.

## Entry

- Reads live XAUUSD ticks on M1.
- Scores price velocity over 1, 3 and 10 seconds, tick-rate expansion, acceleration, M1 body strength and a micro breakout.
- A signal must remain present for 400 ms before the first continuation stop is armed.
- Only one directional pending stop exists at a time.

## Adding positions

- After a fill, one same-direction continuation stop is maintained ahead of price.
- New positions are added only while same-direction momentum remains supportive.
- The campaign stops adding immediately when momentum fades or strong opposite pressure appears.
- Existing positions remain open and are managed independently.

## Individual protection

Every position receives:

- Initial SL: 1.20 ATR.
- Initial TP: 1.00 ATR.
- Break-even trigger: 0.45 ATR.
- Break-even buffer: spread plus a small ATR allowance.
- Trailing activation: 0.75 ATR.
- Trailing distance: 0.35 ATR.

Stops only tighten; they never move backwards.

## Direction reversal protection

- No BUY campaign can become a SELL campaign while any BUY position or pending order remains, and vice versa.
- When a completed campaign becomes flat, the engine requires a quiet reset for 1.2 seconds.
- A new campaign in the opposite direction requires a stronger score and a one-second held signal.

## Capital limits

- Fixed lot: 0.01 by default.
- Maximum simultaneous positions: 10.
- Maximum total lots: 0.10.
- Emergency floating loss: 1.5% of balance.
- Daily realised loss lock: 4%.

These are conservative demo starting values, not proof of profitability.
