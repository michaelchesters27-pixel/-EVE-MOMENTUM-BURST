# Easy installation — v2.08

1. Leave **Algo Trading OFF**.
2. Close every open position belonging to v2.06/v2.07.
3. Delete any remaining v2.06/v2.07 pending EVE orders.
4. Replace the complete GitHub repository with this package and let Railway redeploy.
5. In MT5, open **File → Open Data Folder**.
6. Open `MQL5/Experts` and copy in `mt5/EVE_Momentum_Burst_EA_v2.08.mq5`.
7. Open that file in MetaEditor and press **Compile**. Require **0 errors**.
8. Remove v2.06/v2.07 from the XAUUSD M1 chart.
9. Attach `EVE_Momentum_Burst_EA_v2.08`.
10. Enter the same Railway URL and bot token.
11. Press **OK**, then turn **Algo Trading ON**.
12. Confirm the chart says v2.08 and the dashboard heartbeat reports EA `2.08`.
13. While flat, confirm both a BUY STOP and SELL STOP are shown.

Do not attach v2.08 over an old open EVE position. Its new magic number intentionally isolates this corrected campaign engine.
