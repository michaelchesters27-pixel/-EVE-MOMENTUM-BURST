# Strategy specification — v2.11

## Time handling

- Execution is tick-by-tick.
- M1 ATR defines normal volatility.
- M5 supplies a soft directional bias.
- Candle opening does not create a trade attempt.

## Burst arming

While flat, the EA normally has no pending orders.

A bracket is armed only when live movement is direction-consistent:

- 1-second velocity exceeds its ATR-normalised threshold;
- 3-second velocity confirms the same direction;
- 1-second speed is expanding versus 3-second speed;
- tick arrival rate is above its 30-second baseline;
- price breaks the recent micro-range;
- spread remains acceptable.

A burst against M5 is permitted, but it must exceed stronger thresholds.

The bracket expires if neither side triggers within its lifetime. A new bracket is not permitted until live velocity quietens.

## First trigger

The first BUY or SELL is provisional. The opposite stop remains active.

Position 1 receives a real broker-side SL. Once it reaches the configured profit trigger, that SL moves into profit using the Position 1 giveback rule.

## Confirmation

A second BUY confirms only if its actual fill is above BUY 1. A second SELL confirms only if its actual fill is below SELL 1.

Before Position 2 is submitted, Position 1 must already carry the exact SL that Position 2 will receive.

If the opposite stop triggers first, the original breakout is treated as failed. The failed side is closed and the new side becomes provisional.

## Confirmed ladder

After confirmation:

- the opposite stop is removed;
- all open positions share one exact broker-side SL;
- only one same-direction ladder stop exists ahead;
- the next stop is not placed until every open position already carries the SL that the future position will receive.

## Exit

The shared SL is the normal campaign exit.

The EA also checks live Bid for BUY positions and live Ask for SELL positions. If a position remains open after its SL is crossed, the EA removes pending entries and force-closes the remaining basket.

There is no fixed TP, session gate, campaign timer, score gate, maximum-position gate or total-lot gate in the strategy logic.
