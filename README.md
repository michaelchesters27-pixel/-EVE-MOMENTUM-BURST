# EVE Fury Reconstruction Demo v4.10

A clean, demo-only MT5 XAUUSD momentum-ladder reconstruction based on the observable behaviour in the supplied Markflipper/Fury Flipper videos and screenshots.

Main EA: `mt5/EVE_Fury_Reconstruction_Demo_v4.10.mq5`

## What changed from the faulty v4.00 package

- The old v3.02 scout/shared-SL engine was removed rather than renamed.
- Every pending order and every filled position has its own broker-side SL and TP.
- The bot never flips direction while a campaign still has exposure.
- After a campaign finishes, price must first quieten and then produce a new confirmed burst.
- An opposite-direction campaign needs a stronger signal held for longer.
- Pending orders use `ORDER_TIME_GTC`; no broker-invalid expiry time is sent.
- Cancellation checks that an order still exists and defers deletion inside the broker freeze zone instead of repeatedly sending invalid requests.
- Railway telemetry is deliberately rate-limited and uses exponential backoff after HTTP failures.

Defaults are 0.01 lot, a maximum of 10 simultaneous positions, 0.10 maximum total lots, individual 1.20 ATR SL, individual 1.00 ATR TP, break-even at 0.45 ATR, and trailing from 0.75 ATR.

This is not the seller's original source code and is not claimed to be an exact clone. Use a hedging demo account only.
