# Easy installation

## GitHub and Railway

1. Stop and remove the old Momentum Burst EA only after its positions and orders are flat.
2. Replace the complete contents of the `EVE-MOMENTUM-BURST` GitHub repository with this package.
3. Railway Root Directory: `railway`.
4. Railway variables:
   - `BOT_TOKEN=EVE-MOMENTUM-DEMO-2026`
   - `AUTO_ENABLED=true`
   - `DATA_DIR=/data`
5. Wait for Railway deployment to show version `v2.0.0`.

## MetaEditor

1. Open `mt5/EVE_Momentum_Burst_EA_v2.00.mq5`.
2. Press F7.
3. Confirm MetaEditor reports zero errors before attachment.

## MT5

1. Open a separate XAUUSD M1 chart.
2. Add `https://eve-momentum-burst-production.up.railway.app` under Tools > Options > Expert Advisors > Allow WebRequest.
3. Attach `EVE_Momentum_Burst_EA_v2.00`.
4. Set:
   - `InpRailwayBaseUrl=https://eve-momentum-burst-production.up.railway.app`
   - `InpBotToken=EVE-MOMENTUM-DEMO-2026`
5. Tick Allow Algo Trading and keep the global Algo Trading button enabled.

## Dashboard

Open the Railway domain, enter the same token, then use Lot and Ladder Control. Press Apply settings. The EA receives changes during its next control poll.
