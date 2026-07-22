# EVE MOMENTUM BURST v1.00

A separate, demo-first XAUUSD momentum research bot inspired by the **visible behaviour** described in the Markflipper / Fury Flipper reconstruction PDF. It is not the original proprietary algorithm and does not claim to reproduce private source code.

## What v1.00 does

- Analyses **broker-native XAUUSD M1 candles inside MT5**. Railway is used for monitoring, controls and evidence storage, not for time-critical entry calculation.
- Uses an explicit **0–11 BUY score** and **0–11 SELL score**:
  - ATR-normalised price velocity: 2 points
  - Strong candle body and close location: 2 points
  - Recent-range breakout: 2 points
  - ATR expansion: 1 point
  - Tick-volume expansion: 1 point
  - EMA 9/21 alignment: 1 point
  - EMA slope: 1 point
  - Directional candle consistency: 1 point
- Uses M5 confirmation, dynamic spread control, session control and an anti-chase location filter.
- Refuses BUY entries directly beneath recent M5 resistance and SELL entries directly above recent M5 support unless a real breakout has occurred.
- Opens **one 0.01 position only** by default.
- Places broker-side SL and TP immediately.
- Uses cost-adjusted break-even, momentum-sensitive ATR trailing and a 15-minute maximum holding time.
- Never martingales, grids, averages into losses, bursts or pyramids in this baseline version.
- Retains a transaction-safe `CLOSE PENDING` state and automatically retries after temporary broker errors, including market closure.
- Logs every closed M1 scan, accepted/rejected decision and completed trade.
- Tracks entry score, opposite score, regime, MFE, MAE, duration, realised net P/L and exit reason.

## Repository structure

- `mt5/EVE_Momentum_Burst_EA_v1.00.mq5` — complete MT5 EA source.
- `railway/` — Node dashboard, control API, CSV exports and persistence.
- `supabase/schema.sql` — optional permanent cloud database.
- `docs/INSTALL-EASY.md` — step-by-step deployment.
- `docs/STRATEGY.md` — exact strategy and safety rules.
- `docs/VALIDATION.md` — checks performed and remaining MetaEditor requirement.

## Default identity

- Magic number: `2207202603`
- Trade comment: `EVE-MOMENTUM-V1`
- Railway root directory: `railway`
- Recommended chart: `XAUUSD, M1`

## Safety position

This release is intentionally conservative. The PDF's multi-order burst and pyramiding concepts are not enabled. Those features should only be considered after the scan/trade database demonstrates a stable edge on real-tick demo data.
