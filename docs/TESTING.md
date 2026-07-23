# Demo testing procedure — v2.10

## Before testing

1. Compile `mt5/EVE_Momentum_Burst_EA_v2.10.mq5` with 0 errors.
2. Use an IC Markets demo hedging account.
3. Confirm EA version 2.10 in MT5 and Railway.
4. Confirm no v2.09 position or pending order remains.

## Flat bracket test

Confirm one BUY STOP and one SELL STOP are live. On a new M1 candle, confirm each side is refreshed individually rather than intentionally deleting both at once.

## One-attempt-per-candle test

Allow a campaign to start and finish within one M1 candle. Confirm no fresh bracket appears until the next M1 candle starts.

## Position 1 profit-lock test

Allow Position 1 to trigger without Position 2:

- before the configured profit trigger, the original broker SL remains;
- after the peak reaches the trigger, Position 1's real SL moves into profit;
- as the peak increases, the SL may improve but must never weaken;
- there is no fixed TP;
- if price retraces, Position 1 closes in protected profit rather than returning to a normal full loss.

## Confirmation pre-arm test

Before Position 2 appears, confirm Position 1 already has the exact SL shown on the pending Position 2 order. A second BUY must be above BUY 1; a second SELL must be below SELL 1.

## One-order-ahead ladder test

After Position 2 confirms:

- the opposite stop is removed;
- all open positions show one identical SL;
- only one future same-direction ladder stop exists;
- before that stop is placed, all existing positions already show its exact SL;
- after it triggers, only one replacement future stop is prepared.

## Exit test

Reverse price through the shared SL. Confirm open positions close around the shared level, remaining pending orders are removed, and the EA waits for the next M1 candle.

## Spread test

Increase or observe an abnormal spread on demo. Confirm fresh pending entries are removed, existing positions retain broker-side SL protection, and pending entries return only after spread normalises.

## Execution-integrity test

Confirm a later BUY fill below the previous BUY, a later SELL fill above the previous SELL, an SL on the wrong side of the newest fill, or an open position beyond its SL causes full-campaign quarantine.
