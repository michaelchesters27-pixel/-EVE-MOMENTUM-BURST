# EVE Fury Reconstruction Demo v4.00

This is an evidence-based behavioural reconstruction, not Markflipper's proprietary source code.

## Trading behaviour

- XAUUSD M1 tick-burst detection.
- Chooses one direction from live velocity, acceleration, tick-rate expansion and a micro breakout.
- Places one stop order in the detected direction.
- After a fill, keeps one same-direction continuation stop ahead while momentum remains active.
- Maximum 10 simultaneous positions by default.
- Every pending order is created with its own broker-side SL and TP.
- Every open position is managed independently.
- At 0.30 ATR progress, its SL advances to cost-adjusted break-even.
- At 0.45 ATR progress, an individual 0.25 ATR trailing stop begins.
- An individual SL does not automatically liquidate the remaining positions.
- When momentum fades, future pending orders are cancelled; existing positions remain governed by their own SL/TP.
- When all positions are closed, the campaign resets and waits for a fresh quiet-reset plus burst.

## Default risk geometry

- Initial SL: 1.20 ATR.
- TP: 0.80 ATR.
- Break-even trigger: 0.30 ATR.
- Trail activation: 0.45 ATR.
- Trail distance: 0.25 ATR.
- Fixed lot: 0.01.
- Maximum positions: 10.

These are starting hypotheses for demo testing. The videos cannot reveal the original private thresholds, exact filters, or long-term losses.
