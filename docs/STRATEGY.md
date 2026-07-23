# Strategy specification — v2.09

## Flat state

The EA maintains one current-candle BUY STOP and one current-candle SELL STOP. At a new M1 candle, it refreshes each side individually while the other side remains live.

## First trigger

The first BUY or SELL is provisional. The opposite stop remains live and a second stop is placed in the triggered direction.

If the opposite stop triggers before the second same-side stop, the first breakout failed. The failed side is closed and the newly triggered side becomes provisional.

## Confirmation

A second BUY confirms only when its actual fill is higher than BUY 1. A second SELL confirms only when its actual fill is lower than SELL 1. A wrong-sequence fill triggers full campaign quarantine and closure.

## Shared basket SL

After confirmation, the EA calculates one SL price from the actual open positions:

- BUY basket: shared SL is above the previous BUY entry but below the newest BUY entry;
- SELL basket: shared SL is below the previous SELL entry but above the newest SELL entry;
- the calculation includes a minimum net-profit target and a configurable commission reserve;
- the shared SL never deliberately weakens the most protective existing SL;
- the newest position is modified first, then every older position receives the exact same SL.

Once every position is synchronised, the ladder continues building.

## Basket exit

Any broker-side SL closure starts full-campaign cleanup. Because all positions share the same SL, they are intended to close together. The EA also watches Bid for BUY positions and Ask for SELL positions. If a position remains open after its SL is crossed, all pending orders are cancelled and the remaining basket is force-closed.

## No strategy restrictions

BUY/SELL analytics scores do not control orders. There is no session filter, campaign timer, post-campaign cooldown, maximum-position gate or maximum-total-lot gate.
