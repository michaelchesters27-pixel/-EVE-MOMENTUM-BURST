# v1.10 live strategy specification

## Objective

Enter XAUUSD M1 momentum while it is accelerating, divide the signal into several small protected positions and bank the complete basket quickly as momentum decays.

## 11-point live directional score

BUY and SELL are scored independently.

1. 1-second velocity: 1 point
2. 3-second velocity: 1 point
3. live acceleration: 2 points
4. live M1 body strength: 1 point
5. micro-breakout or strong live body expansion: 1 point
6. tick-arrival expansion: 1 point
7. ATR active regime: 1 point
8. EMA 9/21/50 alignment: 1 point
9. recent directional pressure: 1 point
10. M5 directional support: 1 point

Maximum: 11 points.

Default thresholds:

- quiet market: 8/11
- normal market: 7/11
- high momentum: 6/11
- minimum BUY/SELL gap: 3 points

M5 is supporting evidence only. A powerful live impulse is not automatically rejected solely because M5 is neutral.

## Live state machine

### IDLE

Score is below the arm threshold.

### ARMED

Momentum is building but one element is still missing, such as acceleration, score gap or micro-breakout.

### BURST

The score, score gap, acceleration and live breakout/body-expansion conditions qualify. A flat bot may open the initial position cluster.

### DECAY

The current basket direction loses live score or acceleration. A profitable basket is banked instead of waiting for the full TP.

### FLIP

The opposite score reaches the flip threshold, overtakes the current direction and is accelerating. The current basket closes completely before the next direction can be considered.

### EXHAUSTED

Price is extended beyond its live extension allowance while acceleration is inadequate.

### CHAOTIC

Spread exceeds the absolute cap or the recent broker-spread multiplier.

## Dynamic extension

The maximum distance from EMA9 changes with momentum:

- normal: 1.10 ATR
- strong continuing acceleration: up to 2.50 ATR
- decelerating move: 0.90 ATR

This removes the v1.00 behaviour where a genuine live burst could be rejected simply because it had already moved beyond 0.85 ATR.

## Burst construction

Default:

- three initial market positions
- 0.01 lot per position
- maximum five positions
- maximum total 0.05 lots

One continuation Buy Stop or Sell Stop may be placed in the basket direction. It is cancelled unless:

- the basket is profitable
- the same live direction remains in BURST state
- spread remains acceptable
- position and total-lot caps remain available

The EA never adds to a losing basket.

## Position protection

Every position receives immediately:

- SL: 0.75 ATR
- TP: 0.90 ATR

Then:

- break-even begins after 0.12 ATR favourable movement
- trailing begins after 0.18 ATR
- BURST trail: 0.16 ATR
- normal trail: 0.12 ATR
- decay trail: 0.08 ATR

Broker stop/freeze levels are enforced.

## Basket banking

Targets scale with total volume:

- target: $0.80 per 0.01 lot
- trail activation: $0.30 per 0.01 lot
- giveback: $0.10 per 0.01 lot

Example at 0.03 total lots:

- money target: $2.40
- basket trail starts: $0.90
- allowed giveback: $0.30

Other exits:

- profitable momentum decay
- live opposite-direction flip
- maximum basket loss: $6
- maximum duration: 5 minutes
- manual close or emergency stop

If one leg closes through SL or TP while others remain, the EA flattens the rest of the basket so the positions do not become an unmanaged fragment.

## Daily protection

- maximum daily loss: 3% of start-of-day balance
- daily profit stop: 5%
- maximum baskets: 50 UTC day
- maximum consecutive losses: 5

Daily state and close state persist through MT5 restarts.

## Explicitly excluded

- martingale
- lot multiplication after losses
- averaging into losing trades
- unlimited grids
- hidden recovery orders
- automatic news-event scraping
