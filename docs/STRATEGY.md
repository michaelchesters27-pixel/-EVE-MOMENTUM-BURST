# Strategy specification — v2.04

## 1. Flat and OCO straddle

When flat and sufficiently active, the EA maintains exactly one BUY STOP above Ask and one SELL STOP below Bid. The minimum distance is the greatest of:

- broker stop/freeze distance plus the adaptive request buffer;
- 0.20 ATR;
- 0.25 XAUUSD price units by default.

Both orders must exist before the engine reports `OCO STRADDLE READY`.

## 2. First trigger wins

The first entry-bracket deal sets `campaign_start_side`. The engine immediately enters `OCO CANCELLING` and blocks all ladder additions and reversal creation until every remaining entry-bracket order is confirmed gone.

MT5 hedging accounts do not provide a native OCO order type. If both pending orders trigger before cancellation can complete, the EA retains the first-triggered side and closes the accidental second side one position at a time.

## 3. Campaign lock

After OCO confirmation, a short lock prevents new requests while the initial trade settles. Broker-side SL and TP continue to protect the position during this period.

## 4. Rolling ladder

A new same-direction leg requires all of the following:

- campaign phase is ACTIVE;
- no entry-bracket order remains;
- maximum position and total-lot limits allow it;
- basket profit is at least the configured add threshold;
- newest leg is already profitable;
- score and live acceleration support the campaign direction;
- price has advanced by the required ATR/fixed spacing;
- add cooldown has expired.

The EA never intentionally adds to a losing campaign.

## 5. Reversal stop

A reversal stop is separate from the original OCO entry bracket. It is created only when:

- the OCO cancellation is complete;
- the campaign has aged at least the arm delay;
- the basket has reached the minimum protected profit.

The order is positioned at the original hard campaign invalidation/SL area. It does not follow every small M1 movement or the latest trailing stop.

If it triggers, the engine enters REVERSING, retains the new reversal side and closes old-direction legs one at a time. No additions are allowed until only the new direction remains.

## 6. Individual protection

Each leg receives broker-side SL and TP. Break-even and graduated trailing are managed per ticket. Only one position modification is sent per execution cycle.

## 7. Banking

The newest leg is the canary. A campaign can bank when:

- the canary gives back most of its peak while momentum weakens;
- the canary turns negative after the ladder has developed;
- the basket gives back the configured percentage of peak floating profit;
- opposite pressure dominates while the basket is profitable;
- maximum loss or duration is reached;
- the user closes it or activates emergency stop.

Pending orders are removed first. Positions are closed one at a time. A campaign is recorded only after both counts are zero.

## 8. Anti-whipsaw reset

After a campaign closes, no new straddle is built until the configured post-campaign cooldown expires. The default is 15 seconds.

## 9. Evidence

Each record includes a permanent campaign ID. Basket records report:

- starting and final direction;
- BUY and SELL leg counts;
- reversal count;
- peak, drawdown, giveback and realised net result;
- exact banking/exit reason.
