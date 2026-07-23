# Strategy specification — v3.02

## 1. Detection

The EA watches live ticks. M1 ATR defines normal movement and M5 supplies a soft directional bias. Analytics scores are display-only.

A directional burst requires same-direction 1-second and 3-second velocity, acceleration, tick-rate expansion, a micro-breakout and acceptable spread.

## 2. Directional scout

A BUY burst places one BUY STOP. A SELL burst places one SELL STOP. No opposite order is placed, and the legacy setting cannot re-enable a two-sided bracket.

The pending order expires server-side when supported. If it becomes stale, wrong-side, duplicated, stuck in a request state or inconsistent with the live positions, the execution supervisor enters recovery and removes it.

## 3. Scout management

The first fill is the scout. It receives a real broker-side SL and no fixed TP.

After the configured profit trigger, the EA dynamically protects profit. Protection runs before any pending-order cleanup. If the broker cannot accept a profitable legal SL, the scout is closed.

## 4. Confirmation and ladder

Position 2 requires protected scout profit and fresh same-direction re-acceleration. Once confirmed, every position shares one broker-side SL and only one future ladder order can exist.

A later BUY fill must be higher than the previous BUY trigger. A later SELL fill must be lower than the previous SELL trigger.

## 5. Strict state machine

The supervisor reconstructs state from MT5 every pass:

- `IDLE`: no positions, no pending order.
- `ARMED`: no position, one valid initial pending order.
- `SCOUT`: one position, zero or one valid same-side confirmation order.
- `CONFIRMED`: two or more same-side positions, zero or one valid same-side ladder order.
- `EXITING`: campaign close is active.
- `RECOVERY`: an order invariant has failed and new entries are blocked.
- `FAULT`: mixed positions or a recovery order has produced exposure; the basket is closed.

A BUY STOP at or below Ask is wrong-side. A SELL STOP at or above Bid is wrong-side. Wrong-side orders are not treated as frozen. Once recovery starts, it remains latched and keeps removing the ticket even if price later returns to the valid side.

## 6. Exit

The scout can close by initial SL, protected SL, momentum-stall bank, execution-integrity protection or manual/emergency close.

A confirmed basket exits through the shared SL or a full-basket execution-integrity close.
