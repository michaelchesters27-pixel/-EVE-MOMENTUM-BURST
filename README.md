# EVE MOMENTUM BURST v2.02

A complete replacement for the EVE Momentum Burst demo project. The engine reconstructs the visible moving-straddle, stop-and-reverse, rolling-ladder and canary-banking behaviour observed in the supplied screenshots. It does not contain the original commercial EA's private source code.

## Core execution model

- XAUUSD M1 live-tick analysis
- moving BUY STOP above price and SELL STOP below price
- first triggered order selects the active direction
- opposite pending stop becomes the reversal trigger
- rolling same-direction position ladder while momentum remains strong
- fixed broker-side SL and TP on every leg
- individual break-even and graduated trailing
- newest-position canary and basket peak-giveback banking
- dashboard-controlled lot size, initial legs, maximum positions and total lots
- detailed basket, leg, order, scan and banking records

## v2.02 execution repair

v2.02 replaces the aggressive cancel-and-recreate loop from v2.01 with a broker-aware synchronisation layer:

- only one trade request is released at a time
- pending orders are modified in place where possible
- deletions are sent one ticket at a time and confirmed gone before another request
- prices are rebuilt from the latest Bid/Ask immediately before submission
- order prices are rounded in the safe direction to the symbol tick size
- stop level, freeze level and an adaptive safety buffer are respected
- invalid-price, locked, frozen, timeout and request-frequency errors trigger controlled backoff
- position trailing changes only one ticket per cycle
- mixed-direction reversal closes one old-direction leg per confirmed cycle
- basket closing clears pending orders first, then closes positions one at a time
- no basket is reported complete until positions and pending orders are both flat

## Repository structure

- `mt5/EVE_Momentum_Burst_EA_v2.02.mq5` — complete EA source
- `railway/` — dashboard, controls, persistence, CSV exports and analysis
- `supabase/schema.sql` — optional permanent evidence database
- `docs/INSTALL-EASY.md` — deployment steps
- `docs/STRATEGY.md` — operating logic
- `docs/TESTING.md` — demo testing process
- `docs/VALIDATION.md` — validation record

## Identity

- Magic number: `2207202603`
- Trade comment: `EVE-MOMENTUM-V2`
- Railway root directory: `railway`
- Chart: `XAUUSD M1`
- Railway domain: `https://eve-momentum-burst-production.up.railway.app`

MetaEditor remains the definitive MQL5 compiler check.
