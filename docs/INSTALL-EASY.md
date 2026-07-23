# Easy installation — v3.00

1. Keep MT5 **Algo Trading OFF**.
2. Close every remaining older EVE position.
3. Delete every remaining older EVE pending order.
4. Replace the complete GitHub repository with this package.
5. Wait for Railway to deploy version `3.0.0`.
6. Copy `mt5/EVE_Momentum_Burst_EA_v3.00.mq5` into `MQL5/Experts`.
7. Open it in MetaEditor and compile it with **0 errors**.
8. Remove the older EA from the XAUUSD chart.
9. Attach v3.00 to **XAUUSD M1**.
10. Enter the Railway URL and bot token.
11. Turn Algo Trading ON.
12. Allow at least 30 seconds for the live tick buffer to warm.
13. Confirm the chart and dashboard report EA `3.00` and magic `2207202630`.

## What is normal

While price is quiet, **zero pending orders is correct**.

When a genuine BUY burst appears, expect one BUY STOP only. When a genuine SELL burst appears, expect one SELL STOP only.

After the scout opens, expect all other pending orders to disappear. Position 2 should not appear unless the scout is already protected in profit and a new same-direction acceleration is detected.
