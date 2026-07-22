# Demo testing procedure — v2.05

Use the IC Markets demo hedging account first.

## Before attaching

1. Compile `mt5/EVE_Momentum_Burst_EA_v2.05.mq5` in MetaEditor.
2. Confirm **0 errors**.
3. Remove v2.04 and delete its old pending orders.
4. Attach v2.05 to XAUUSD M1.
5. Enable Algo Trading.
6. Confirm the Experts tab reports v2.05.

## Scenario A — every-candle straddle

1. Start flat.
2. Confirm exactly one initial BUY STOP and one initial SELL STOP appear.
3. Let a new M1 candle start without either triggering.
4. Confirm the old pair is removed and a fresh pair is created.

## Scenario B — normal BUY confirmation

1. Let the first BUY STOP trigger.
2. Confirm the original SELL STOP remains.
3. Confirm one second BUY STOP is placed above the first entry.
4. Inspect BUY STOP 2 and verify its SL is above BUY position 1's entry.
5. Let BUY STOP 2 trigger.
6. Confirm the SELL STOP is then cancelled.
7. Confirm the EA builds BUY STOP ladder orders ahead.
8. For each ladder order, verify its SL is above the preceding BUY trigger price.

Repeat in reverse for SELL: every new SELL order's SL should be below the preceding SELL trigger.

## Scenario C — provisional false breakout

1. Let the first BUY STOP trigger.
2. Before BUY STOP 2 triggers, let price reverse into the SELL STOP.
3. Confirm the failed BUY closes.
4. Confirm the triggered SELL is retained as provisional SELL position 1.
5. Confirm SELL STOP 2 is placed.
6. Confirm a BUY STOP remains as the opposite guard until SELL position 2 triggers.

## Scenario D — newest-leg basket exit

1. Allow at least three same-direction positions to trigger.
2. Record the newest position identifier, entry and SL.
3. Verify the newest BUY SL is above all older BUY entries, or the newest SELL SL is below all older SELL entries.
4. Let price reverse until the newest position hits its broker-side SL.
5. Confirm the EA enters `BANKING FULL BASKET`.
6. Confirm every older position closes.
7. Confirm all untriggered ladder orders are deleted.
8. Confirm a fresh candle straddle is created immediately with no cooldown.

## Scenario E — restart recovery

1. Restart MT5 with one provisional position active and verify `PROVISIONAL 1/2`.
2. Restart with two or more confirmed same-direction positions and verify the ladder rebuilds.
3. Confirm the newest live position's SL remains the controlling basket-exit trigger.

## Scenario F — unrestricted operation

1. Leave the EA running across several sessions on demo.
2. Confirm there is no time-of-day, score, spread, daily-result, position-count, total-lot or campaign-duration block.
3. Confirm the only normal pauses are deliberate Autonomous Off/Pause/Emergency controls or a broker/terminal inability to accept an order.

Retain screenshots plus the Experts and Journal logs. Watch for broker responses such as invalid stops, frozen orders, insufficient margin and market closed.
