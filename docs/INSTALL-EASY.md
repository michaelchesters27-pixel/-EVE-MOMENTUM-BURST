# Easy installation — v2.06

## GitHub and Railway

1. Replace the entire existing GitHub repository with the contents of this ZIP.
2. Do not upload the ZIP itself; upload its contents.
3. Keep Railway's root directory set to `railway`.
4. Keep the start command as `npm start`.
5. Preserve the existing Railway variables, especially `BOT_TOKEN`.
6. Wait until the dashboard shows `v2.0.6`.

## MetaTrader 5

1. Open MetaEditor.
2. Open `mt5/EVE_Momentum_Burst_EA_v2.06.mq5`.
3. Press **Compile**.
4. Do not continue unless MetaEditor shows **0 errors**.
5. In MT5, remove v2.04 from the chart.
6. Delete any old pending orders left by v2.04 before attaching v2.06.
7. Refresh Expert Advisors in Navigator.
8. Attach `EVE_Momentum_Burst_EA_v2.06` to **XAUUSD M1**.
9. Enter the exact Railway URL and BOT_TOKEN in the EA inputs.
10. Enable Algo Trading.

## Expected first state

While flat, the EA should report `EVERY-CANDLE STRADDLE` and then `CANDLE STRADDLE READY`, with one BUY STOP and one SELL STOP visible.

After the first trigger it should report `PROVISIONAL 1/2`. The opposite stop must remain until the second same-direction stop triggers.
