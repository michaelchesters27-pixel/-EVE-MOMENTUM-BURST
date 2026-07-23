# Easy installation — v2.10

1. Keep Algo Trading OFF.
2. Close every open v2.09 EVE position.
3. Delete any remaining v2.09 EVE pending orders.
4. Replace the complete GitHub repository with this package.
5. Wait for Railway to redeploy version `2.0.10`.
6. Copy `mt5/EVE_Momentum_Burst_EA_v2.10.mq5` into `MQL5/Experts`.
7. Open the file in MetaEditor and compile it with 0 errors.
8. Remove v2.09 from the XAUUSD M1 chart.
9. Attach v2.10 and enter the Railway URL and bot token.
10. Turn Algo Trading ON.
11. Confirm the dashboard reports EA `2.10` and one BUY STOP plus one SELL STOP appear while flat.
12. Confirm a completed campaign waits for the next M1 candle before rearming.
13. When Position 1 earns enough profit, confirm its SL moves above entry for a BUY or below entry for a SELL.
14. Confirm Position 2 is not armed until Position 1 already has Position 2's exact planned SL.
15. After confirmation, confirm exactly one future ladder pending order exists.
