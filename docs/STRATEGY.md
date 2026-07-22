# Strategy specification — v2.08

## Flat state

The EA maintains one current-candle BUY STOP and one current-candle SELL STOP. At a new M1 candle, it refreshes each side individually while the other side remains live.

## First trigger: provisional 1/2

If BUY triggers first:

- BUY 1 opens with a broker-side SL;
- the SELL STOP remains active;
- BUY STOP 2 is placed higher.

SELL is the exact reverse.

If the opposite stop triggers before the second same-side stop, the first breakout failed. The failed side is closed and the newly triggered side becomes provisional.

## Second trigger: direction confirmation

A second BUY confirms only when the actual fill is higher than BUY 1. A second SELL confirms only when the actual fill is lower than SELL 1.

A spread spike, gap or delayed fill that produces the wrong fill order is not momentum confirmation. It triggers full campaign quarantine and closure.

## Active ladder

After confirmation:

- the opposite pending stop is removed;
- same-direction pending stops are staged ahead;
- each fill adds another equal-lot position;
- the pending ladder is replenished continuously;
- no fixed TP is used.

## Stop-loss geometry

Every pending order carries its own broker-side SL.

For confirmation/ladder BUY orders, the newest SL is between the previous BUY trigger and the newest BUY trigger. For SELL orders it is between the previous SELL trigger and newest SELL trigger.

## Full-basket exit

A normal newest-leg broker SL event starts full-basket banking.

The EA also has a quote-side watchdog:

- BUY positions are checked against Bid;
- SELL positions are checked against Ask.

If the quote has crossed a displayed SL but the position remains open, the EA treats this as an execution-integrity breach. It first cancels all remaining pending orders, then closes every open campaign position.

## No strategy restrictions

The operational state machine does not reference BUY/SELL analytics scores. It has no session filter, news gate, campaign timer, post-campaign cooldown, maximum position count or maximum total-lot gate.
