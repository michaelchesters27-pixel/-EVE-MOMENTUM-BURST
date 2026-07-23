# Easy installation — v2.09

1. Keep Algo Trading OFF.
2. Close every open v2.08 EVE position.
3. Delete any remaining v2.08 EVE pending orders.
4. Replace the complete GitHub repository with this package.
5. Wait for Railway to redeploy version `2.0.9`.
6. Copy `mt5/EVE_Momentum_Burst_EA_v2.09.mq5` into `MQL5/Experts`.
7. Open the file in MetaEditor and compile it with 0 errors.
8. Remove v2.08 from the XAUUSD M1 chart.
9. Attach v2.09 and enter the Railway URL and bot token.
10. Turn Algo Trading ON.
11. Confirm the dashboard reports EA `2.09` and both flat-state pending stops appear.
12. After two same-direction fills, confirm every open position displays the same SL price.
