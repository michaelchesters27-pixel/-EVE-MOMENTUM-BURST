# EVE MOMENTUM BURST v1.10

A separate, demo-first XAUUSD M1 live momentum EA inspired by the **visible behaviour** of Fury Flipper / Mark Flipper screenshots and trade histories. It does not contain or claim to reproduce private proprietary source code.

## What changed from v1.00

v1.00 waited for completed M1 candles and used one position. v1.10 measures momentum **inside the live candle** and can open a controlled position burst while acceleration is occurring.

## Live momentum engine

The EA samples the broker's own XAUUSD ticks and calculates:

- 1-second, 3-second, 10-second and 30-second ATR-normalised velocity
- acceleration versus deceleration
- short-window tick-arrival expansion
- live M1 candle-body expansion and close location
- micro-high / micro-low breakout
- ATR activity
- EMA 9 / 21 / 50 alignment
- recent directional pressure
- M5 directional support as one score component, not an absolute gate

The live state machine is:

- `IDLE` - no meaningful impulse
- `ARMED` - pressure is building
- `BURST` - live breakout plus acceleration qualifies
- `DECAY` - current basket momentum is weakening
- `FLIP` - strong opposite acceleration overtakes the basket direction
- `EXHAUSTED` - price is extended without enough continuing acceleration
- `CHAOTIC` - broker spread is abnormal

## Controlled Flipper-mode execution

Default demo settings:

- initial burst: `3 x 0.01`
- maximum positions: `5`
- maximum total exposure: `0.05 lots`
- one same-direction continuation stop at a time
- continuation can add only when the existing basket is profitable
- each position receives an immediate broker-side SL and TP
- no martingale, no grid and no adding to a losing basket

## Dynamic anti-chase logic

The old fixed 0.85 ATR rejection is gone.

- A move may continue beyond the normal extension limit when live velocity, acceleration and tick activity remain strong.
- An extended move is blocked when speed is decelerating.
- This is designed to enter during a burst rather than detect the move only after it has finished.

## Fast banking

Protection operates at two levels:

1. Every position has its own SL, TP, break-even and trailing stop.
2. The complete basket records peak profit and closes together on:
   - adaptive money target
   - profit giveback trail
   - momentum decay while profitable
   - strong opposite momentum flip
   - basket loss cap
   - maximum duration
   - manual or emergency close

Closing uses a persistent `CLOSE PENDING` state, cancels pending orders, retries temporary broker failures and confirms the basket is flat before reporting the realised result.

## Repository structure

- `mt5/EVE_Momentum_Burst_EA_v1.10.mq5` - complete MT5 EA source
- `railway/` - monitoring dashboard, controls, CSV exports and local persistence
- `supabase/schema.sql` - optional permanent storage, including upgrade statements for v1.00 tables
- `docs/INSTALL-EASY.md` - exact deployment steps
- `docs/STRATEGY.md` - detailed live logic and risk controls
- `docs/TESTING.md` - demo validation plan
- `docs/VALIDATION.md` - checks performed

## Identity

- Magic number: `2207202603`
- Trade comment: `EVE-MOMENTUM-V1.1`
- Railway root directory: `railway`
- Chart: `XAUUSD M1`

## Safety position

The screenshots demonstrate bursts, fast exits, trailing, pending stops and variable lots. They do not prove the private entry formula, long-term drawdown or the safety of promotional account sizes. v1.10 therefore copies the visible execution style while keeping exposure deliberately capped for demo research.
