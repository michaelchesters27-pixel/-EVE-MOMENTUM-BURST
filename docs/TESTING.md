# Demo testing procedure — v3.00

## Clean deployment

1. Keep Algo Trading off.
2. Close/delete all v2.09, v2.10 and v2.11 positions and pending orders.
3. Replace the full GitHub repository.
4. Compile `mt5/EVE_Momentum_Burst_EA_v3.00.mq5` in MetaEditor with 0 errors.
5. Attach it to XAUUSD M1 on the IC Markets demo account.
6. Turn Algo Trading on.
7. Allow at least 30 seconds for live-tick warmup.

## Flat-state test

Confirm:

- the EA normally shows `WATCHING LIVE TICKS`;
- no pending order exists during quiet price action;
- a BUY burst creates one BUY STOP only;
- a SELL burst creates one SELL STOP only;
- an untriggered scout expires and is removed;
- the engine waits for a quiet reset before arming again.

## Scout test

After the first position triggers, confirm:

- no opposite pending order remains;
- Position 1 has a real broker-side SL;
- after useful profit, the SL moves into profit and continues to improve as peak profit increases;
- when live support stalls after useful profit, the EA banks the position;
- the dashboard describes the scout proof state.

## Position 2 test

Position 2 must not be armed until:

- scout peak is at least the configured proof threshold;
- current estimated net profit remains above its threshold;
- the scout SL is already in profit;
- same-direction live velocity and acceleration return;
- tick-rate expansion and a fresh micro-break confirm continuation;
- M5 is not directly opposite.

If proof fades, the pending confirmation must be cancelled while the scout remains protected.

## Confirmed ladder test

After Position 2 fills:

- both open positions must show the exact same SL;
- only one future ladder order may exist;
- no future order may remain when continuation proof fades;
- a later fill must progress in the correct direction;
- the full basket must clear when the shared SL is reached.

## Dashboard data test

Confirm the performance section says `MAGIC 2207202630 ONLY`. Old v2.11 results must not appear in the v3.00 statistics.
