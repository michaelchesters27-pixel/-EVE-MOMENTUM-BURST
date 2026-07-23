# Strategy specification — v3.01

## 1. Market observation

- Execution is tick-by-tick.
- M1 ATR measures current volatility.
- M5 supplies a soft directional bias.
- A candle opening does not create a trade attempt.
- Analytics scores are displayed but never gate an order.

## 2. Directional burst arming

While flat, the EA normally has no pending orders.

A directional scout is armed only when the same direction passes all live tests:

- 1-second ATR-normalised velocity;
- 3-second velocity in the same direction;
- acceleration of 1-second speed versus 3-second speed;
- expanding tick-arrival rate;
- a fresh micro-range breakout;
- acceptable spread.

A counter-M5 burst is allowed only if it is stronger by the configured multiplier.

Default mode places one order only:

- BUY burst → BUY STOP;
- SELL burst → SELL STOP.

If it does not trigger within the burst lifetime, it is removed. A fresh scout cannot arm until the market first quietens and then produces a new burst.

## 3. Scout position

The first fill is the scout. All other EVE pending orders are cancelled.

The scout:

- has a real broker-side initial SL;
- has no fixed TP;
- never flips into an opposite campaign;
- starts dynamically locking profit after its peak reaches the configured trigger;
- can be banked when momentum stalls while useful net profit remains.

For a BUY scout, live support means positive 1-second and 3-second velocity. For a SELL scout, both must remain negative. If support disappears for the configured confirmation period after a useful peak, the basket is closed to bank the remaining profit.

## 4. Position 2 proof

Position 2 is not placed simply because price moved a fixed distance.

The scout must first prove itself through:

- minimum peak profit;
- minimum retained estimated net profit;
- an active broker-side profit lock;
- same-direction 1-second and 3-second re-acceleration;
- sufficient acceleration ratio;
- sufficient tick-rate expansion;
- a fresh same-direction micro-break;
- no directly opposite M5 bias.

The confirmation order expires quickly if the proof fades. The scout remains protected and can still bank on a momentum stall.

## 5. Confirmed ladder

When Position 2 genuinely fills farther in the correct direction:

- the campaign becomes confirmed;
- every open position is synchronised to one shared broker-side SL;
- only one future ladder stop may exist;
- the basket must already meet the minimum profit requirement;
- each new order requires a fresh re-acceleration signal.

A later BUY fill must be above the previous BUY trigger. A later SELL fill must be below the previous SELL trigger. Any non-progressing fill is an execution-integrity breach and the full basket is closed.

## 6. Exit logic

### Scout exits

The scout can finish through:

- its initial SL;
- its dynamic profit-lock SL;
- a direct EA bank when useful profit remains but momentum has stalled;
- execution-integrity protection;
- manual close, pause handling or emergency stop.

### Confirmed basket exits

All positions share one broker-side SL. If any shared SL is reported as hit, or live Bid/Ask crosses the stop while the broker leaves a position open, the EA cancels pending entries and clears the full basket.

There is no fixed TP, score gate, session gate, campaign-duration gate, maximum-position strategy gate or total-lot strategy gate.

## 7. No in-campaign reversal

v3.01 never treats an opposite fill as a new campaign direction. A mixed BUY/SELL state is considered unsafe and causes the entire campaign to be closed.

## Broker-rejected profit-lock handling

Position 1 protection has absolute execution priority. The EA calculates the desired profit SL, clamps it to the nearest legal level using the broker stop level, freeze level, tick size and an extra buffer, and submits that legal price. If the broker rejects it, the EA recalculates once farther away. If that is also rejected, or no legal profitable SL exists, the EA closes Position 1 before trying to clean any pending order. Frozen pending orders cannot block this path.
