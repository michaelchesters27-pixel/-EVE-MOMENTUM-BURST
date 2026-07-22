# Easy installation — v2.04

## GitHub and Railway

1. Wait until the old Momentum Burst EA has no open positions or pending orders.
2. Remove v2.03 from its XAUUSD M1 chart.
3. Replace the complete contents of the `EVE-MOMENTUM-BURST` GitHub repository with this package.
4. Keep Railway Root Directory as `railway`.
5. Keep:
   - `BOT_TOKEN=EVE-MOMENTUM-DEMO-2026`
   - `AUTO_ENABLED=true`
   - `DATA_DIR=/data`
6. Wait until the dashboard shows `v2.0.4`.

## MetaEditor

1. Open `mt5/EVE_Momentum_Burst_EA_v2.04.mq5`.
2. Press F7.
3. Confirm MetaEditor reports `0 errors`.

## MT5

1. Open XAUUSD M1.
2. Under Tools > Options > Expert Advisors, allow:
   `https://eve-momentum-burst-production.up.railway.app`
3. Attach `EVE_Momentum_Burst_EA_v2.04`.
4. Set:
   - `InpRailwayBaseUrl=https://eve-momentum-burst-production.up.railway.app`
   - `InpBotToken=EVE-MOMENTUM-DEMO-2026`
5. Tick Allow Algo Trading and keep MT5 Algo Trading enabled.

The dashboard lot and ladder settings apply to new positions only.
