# Demo testing procedure — v2.09

## Before testing

1. Compile `mt5/EVE_Momentum_Burst_EA_v2.09.mq5` with 0 errors.
2. Use an IC Markets demo hedging account.
3. Confirm EA version 2.09 in MT5 and Railway.
4. Confirm no v2.08 position remains.

## Flat bracket test

Confirm one BUY STOP and one SELL STOP are live. On a new M1 candle, confirm neither side is intentionally left unprotected while the other side refreshes.

## Provisional test

Allow the first side to trigger. Confirm the opposite stop remains and the second same-side confirmation stop appears.

## Shared-SL test

Allow the second same-side stop to trigger correctly. Confirm:

- the opposite stop is removed;
- the newest position receives the calculated shared SL first;
- every older position is then modified to exactly the same SL price;
- the dashboard shows that the shared basket SL is armed;
- the next ladder order is not newly added until synchronisation finishes.

## Exit test

Reverse price through the shared SL. Confirm all positions close at the shared area, all remaining pending orders are cleared and a fresh candle bracket is created immediately.

## Spread/gap test

Confirm a later BUY fill below the previous BUY or a later SELL fill above the previous SELL is rejected and the full campaign is quarantined.
