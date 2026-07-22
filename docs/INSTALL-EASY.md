# Easy upgrade from v1.00 to v1.10

## 1. Make the current bot flat

On the existing Momentum Burst dashboard confirm:

- active position: none
- pending orders: zero
- close pending: no

Then press **Disable autonomous**.

Do not replace the EA while it has a position or pending order.

## 2. Replace GitHub completely

Open the existing `EVE-MOMENTUM-BURST` GitHub repository.

Delete the old repository contents and upload **all contents** of the v1.10 GitHub-ready folder. Do not upload this over EVESBOT or EVE Gold Runner.

Railway settings remain:

```text
Root Directory: railway
Start command: npm start
```

No new Railway variables are required:

```text
BOT_TOKEN=EVE-MOMENTUM-DEMO-2026
AUTO_ENABLED=true
DATA_DIR=/data
```

Supabase remains optional.

## 3. Compile the new EA

1. MT5 -> File -> Open Data Folder.
2. Open `MQL5` -> `Experts`.
3. Copy `EVE_Momentum_Burst_EA_v1.10.mq5` into that folder.
4. Press F4 to open MetaEditor.
5. Open the new v1.10 file.
6. Press F7.
7. Continue only when MetaEditor says `0 errors`.

## 4. Replace the chart EA

1. Return to MT5.
2. Open the XAUUSD M1 chart used by v1.00.
3. Right-click -> Expert List.
4. Remove `EVE_Momentum_Burst_EA_v1.00`.
5. Drag `EVE_Momentum_Burst_EA_v1.10` onto that M1 chart.
6. Tick Allow Algo Trading.
7. In Inputs use:

```text
InpRailwayBaseUrl=https://eve-momentum-burst-production.up.railway.app
InpBotToken=EVE-MOMENTUM-DEMO-2026
```

Keep the generated Railway URL if it differs from the example.

## 5. Verify health

Open the Railway dashboard and confirm:

- Railway ONLINE
- MT5 EA CONNECTED
- EA version 1.10
- live state changes among WARMING, IDLE, ARMED and BURST
- autonomous ON
- positions 0 and pending 0 when flat

The engine needs roughly 12 seconds of live ticks after attachment before it can calculate all velocity windows.
