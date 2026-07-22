# Strategy specification

## Flat state: moving straddle

The EA maintains two broker pending orders around live price:

- BUY STOP above ask
- SELL STOP below bid

The bracket is refreshed when price moves enough or the orders reach their configured age. Spread, session, account controls and live activity must permit the bracket.

## Breakout and ladder

The first triggered order becomes the active direction. The EA can fill the configured initial position count, then add further same-direction positions only when:

- the position and total-lot limits allow it;
- the basket is not losing when `InpNeverAddToLosingBasket` is enabled;
- live score and acceleration support the active direction;
- price has advanced by the configured ATR spacing;
- the add cooldown has elapsed.

## Reversal order

While a ladder is active, the opposite pending stop is aligned below a BUY ladder or above a SELL ladder. It follows the protected stop/invalidation area. If triggered, the EA removes the old direction and retains the new direction.

## Individual protection

Each leg has a fixed SL and TP. Break-even and trailing are updated per ticket. Newer entries use tighter trailing; older entries receive more room.

## Canary banking

The newest position is tracked separately:

- current profit
- highest profit reached
- age
- ticket

The EA can bank the ladder when the canary gives back the configured share of its peak while momentum is tiring, or when it turns sufficiently negative after the ladder has developed. Basket peak-profit giveback and dominant opposite momentum provide additional banking routes.

## Complete tracking

Baskets, legs, pending orders, banking decisions, scans and events are all recorded separately so each parameter can be analysed instead of guessed.
