# Strategy specification — v2.03

## Moving straddle

When flat and armed, the EA maintains one BUY STOP above Ask and one SELL STOP below Bid. The levels are calculated from live ATR, the broker stop/freeze distances, tick size and a safety buffer.

The engine modifies existing orders instead of repeatedly deleting and recreating them. Only one broker trade request may be active during each synchronisation step.

## Breakout and rolling ladder

The first pending order that triggers becomes the active direction. Additional same-direction market legs may be added only when the configured limits, basket-profit requirement, momentum score, acceleration, spacing and cooldown agree.

## Stop-and-reverse

While a ladder is active, only the opposite pending stop is retained. It is aligned to the protected stop or invalidation area. If both directions temporarily coexist on the hedging account, v2.03 closes one old-direction leg per confirmed broker cycle and retains the newest direction.

## Individual protection

Each leg receives fixed SL and TP. Break-even and trailing are managed per ticket. Only one position modification is sent per execution cycle, preventing request collisions.

## Banking

The newest leg is tracked as the canary. The ladder can bank when:

- the canary gives back its configured share of peak profit while momentum weakens;
- the canary turns sufficiently negative after maturing;
- the total basket gives back the configured share of peak floating profit;
- dominant opposite acceleration appears;
- basket loss or duration limits are reached;
- the user closes or invokes emergency stop.

Pending orders are cleared first. Positions are then closed one ticket at a time. The basket is recorded only after both counts are zero.

## Evidence

Scans, pending-order actions, individual legs, banking decisions, baskets and setting changes are recorded separately for analysis.
