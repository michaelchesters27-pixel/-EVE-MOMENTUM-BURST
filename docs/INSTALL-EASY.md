# Easy installation — v2.11

1. Keep MT5 Algo Trading off.
2. Close any old EVE positions.
3. Delete any old EVE pending orders.
4. Replace the complete GitHub repository with this package.
5. Wait for Railway to deploy version `2.0.11`.
6. Copy `mt5/EVE_Momentum_Burst_EA_v2.11.mq5` into `MQL5/Experts`.
7. Open it in MetaEditor and compile with 0 errors.
8. Remove the older EA from the XAUUSD chart.
9. Attach v2.11 to XAUUSD M1.
10. Enter the Railway URL and bot token.
11. Turn Algo Trading on.
12. Wait at least 30 seconds for tick warmup.
13. Confirm the dashboard reports EA `2.11`.

While the market is quiet, no pending orders is normal. The BUY STOP and SELL STOP appear only after a genuine live burst.
