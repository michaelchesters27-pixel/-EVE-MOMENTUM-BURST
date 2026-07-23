# Strategy specification — v2.10

## Flat state

The EA maintains one current-candle BUY STOP and one current-candle SELL STOP. At a new M1 candle, it refreshes each side individually while the other side remains live.

Only one campaign attempt is permitted per M1 candle. When a campaign finishes, the EA waits for the next M1 candle before creating another bracket. This is candle discipline, not a timed cooldown.

## First trigger

The first BUY or SELL is provisional. The opposite stop remains live and one same-direction confirmation stop is prepared.

If the opposite stop triggers before the second same-side stop, the first breakout failed. The failed side is closed and the newly triggered side becomes provisional within the same campaign.

## Position 1 profit protection

Position 1 has no fixed TP. Once it reaches the configured peak-profit trigger, the EA moves its actual broker-side SL into profit.

The default lock retains half of the best Position 1 floating profit, subject to the configured minimum protected profit and trading-cost reserve. The SL only moves in the protective direction; it is never deliberately weakened.

If profit gives back before the broker permits the SL to be armed, the EA requests a campaign close rather than allowing Position 1 to return to a normal full loss.

## Confirmation

A second BUY confirms only when its actual fill is higher than BUY 1. A second SELL confirms only when its actual fill is lower than SELL 1.

Before Position 2 is placed:

- the intended shared SL is calculated from Position 1, the proposed Position 2 entry, lot size, cost reserve and required net profit;
- Position 1 must already carry that exact SL;
- Position 2 is then submitted with the same SL already attached.

A wrong-sequence fill or an already-crossed SL triggers full campaign quarantine and closure.

## Confirmed ladder

After confirmation, the opposite pending stop is removed.

Only one future same-direction ladder stop may exist. Before it is placed, every current position must already carry the exact SL that the future position will receive. When that pending order triggers, the basket is recalculated from the actual fills before one new future order is prepared.

## Basket exit

All confirmed positions share one broker-side SL. When that SL is reached, the broker is intended to close the positions together. The EA then removes any remaining pending campaign order and waits for the next M1 candle.

The EA also independently watches Bid for BUY positions and Ask for SELL positions. If the broker leaves a position open after its SL is crossed, pending entries are quarantined and the full remaining basket is force-closed.

## Wide-spread handling

During an abnormal spread, fresh pending entries are removed. Existing positions remain protected by their broker-side SL. Entry orders are restored automatically when spread normalises.

## What does not control entries

BUY/SELL analytics scores are display-only. There is no score gate, session gate, campaign-duration gate, fixed TP, maximum-position gate or maximum-total-lot gate in the strategy logic.
