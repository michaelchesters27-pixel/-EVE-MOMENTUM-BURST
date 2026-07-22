# Demo testing procedure — v2.08

## Installation test

1. Compile `mt5/EVE_Momentum_Burst_EA_v2.08.mq5` with 0 errors.
2. Attach it to XAUUSD M1 on the demo hedging account.
3. Confirm EA version 2.08 in MT5 and Railway.
4. Confirm the new magic number is `2207202608`.

## Flat bracket test

- Confirm BUY STOP and SELL STOP are both present.
- Wait through several new M1 candles.
- Confirm one side remains live while the other is refreshed; the EA must not remain one-sided.

## Provisional test

- First same-side trigger: one position plus two pending directions.
- Opposite stop remains until the second same-side trigger.

## Confirmation test

- A later BUY must fill above the previous BUY.
- A later SELL must fill below the previous SELL.
- After a valid second trigger, confirm the opposite stop is removed and the same-side ladder builds.

## Spread/gap safety test

Use Strategy Tester or a controlled demo period to verify:

- a second BUY filled below/equal to the first BUY triggers `EXECUTION INTEGRITY BREACH`;
- a second SELL filled above/equal to the first SELL triggers the same;
- a BUY whose Bid is already at/below its SL is closed;
- a SELL whose Ask is already at/above its SL is closed;
- a fill with SL on the wrong side of its actual fill is closed;
- pending orders are cancelled before basket positions are banked;
- no repeated invalid cancellation spam occurs for a ticket that has already changed state.

## Newest-SL test

Allow a valid ladder to form, then reverse price through the newest leg SL. Confirm all pending orders disappear and all older positions are closed.
