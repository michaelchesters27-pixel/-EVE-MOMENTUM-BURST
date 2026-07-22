# Installation — simple steps

## Part A — GitHub and Railway

1. Create a new GitHub repository named `EVE-MOMENTUM-BURST`.
2. Upload **all files inside this ZIP** to that repository.
3. In Railway, create a new project from the GitHub repository.
4. Open Railway **Settings** and set **Root Directory** to:

   `railway`

5. Open Railway **Variables** and add:

   - `BOT_TOKEN` — make up a long private token, for example `EVE-MOMENTUM-PRIVATE-2026-X9`
   - `AUTO_ENABLED` = `true`
   - `DATA_DIR` = `/data`

6. Optional but recommended: add a Railway Volume mounted at `/data`. This keeps scan/trade files after redeployments.
7. Wait for Railway to show the service as deployed.
8. Copy the Railway public URL, for example:

   `https://eve-momentum-burst-production.up.railway.app`

## Part B — MetaEditor

1. Open MT5.
2. Press `F4` to open MetaEditor.
3. In MetaEditor, open:

   `mt5/EVE_Momentum_Burst_EA_v1.00.mq5`

4. Change these two input defaults at the top if preferred, or set them when attaching the EA:

   - `InpRailwayBaseUrl` = your new Railway public URL
   - `InpBotToken` = the exact Railway `BOT_TOKEN`

5. Press **Compile**.
6. Continue only when MetaEditor reports **0 errors**.

## Part C — allow the Railway connection

1. In MT5 click **Tools** → **Options**.
2. Click **Expert Advisors**.
3. Tick **Allow WebRequest for listed URL**.
4. Add the Railway public URL exactly, without a slash at the end.
5. Press **OK**.

## Part D — attach the EA

1. Open a new `XAUUSD` chart.
2. Set the chart to **M1**.
3. Keep EVE Gold Runner and EVESBOT on their own separate charts.
4. Drag `EVE_Momentum_Burst_EA_v1.00` onto the new M1 chart.
5. On the **Inputs** tab:
   - confirm `InpFixedLot = 0.01`
   - enter the exact Railway URL
   - enter the exact BOT_TOKEN
6. Tick **Allow Algo Trading**.
7. Press **OK**.
8. Make sure the main MT5 **Algo Trading** button is green.

## Part E — open the dashboard

1. Open the Railway public URL in your browser.
2. Paste the exact `BOT_TOKEN` from Railway.
3. Press **Connect**.
4. Confirm:
   - Railway: ONLINE
   - MT5 EA: CONNECTED
   - EA version: 1.00
   - Algo Trading: ALLOWED
   - Position: NONE or ACTIVE
   - Fresh M1 scans appear once each minute

## Optional Supabase database

The bot works without Supabase. To keep a permanent queryable database:

1. Create a separate Supabase project.
2. Run `supabase/schema.sql` once in the SQL Editor.
3. Add `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` to Railway Variables.
4. Redeploy Railway.
