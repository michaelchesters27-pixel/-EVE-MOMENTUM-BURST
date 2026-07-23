# Demo testing procedure — v2.11

1. Keep Algo Trading off.
2. Close old v2.09/v2.10 positions and delete their pending orders.
3. Replace the full GitHub repository with this package.
4. Compile `mt5/EVE_Momentum_Burst_EA_v2.11.mq5` in MetaEditor with 0 errors.
5. Attach it to XAUUSD M1 on the IC Markets demo account.
6. Turn Algo Trading on.
7. Allow at least 30 seconds for the live tick buffer to warm.

## Flat-state test

Confirm the EA normally shows `WATCHING LIVE TICKS` with no pending orders.

During a genuine fast move, confirm:

- one BUY STOP and one SELL STOP appear;
- the dashboard says `TICK-BURST BRACKET READY`;
- if neither triggers within the configured lifetime, both are removed;
- the EA waits for a quiet reset before arming again.

## Provisional test

After Position 1 triggers:

- the opposite stop remains;
- the same-direction Position 2 stop is prepared only after Position 1 has the same planned SL;
- a profitable Position 1 moves its real SL into profit;
- a wrong-direction or non-progressing fill causes campaign closure.

## Confirmed ladder test

After Position 2 confirms:

- the opposite pending stop disappears;
- all open positions display the exact same SL;
- only one future ladder pending order exists;
- when that shared SL is reached, the entire campaign finishes.

## Spread test

During an abnormal spread:

- no fresh pending entries remain;
- open positions keep their broker-side SL;
- entries may resume only after spread normalises and a fresh burst is detected.
