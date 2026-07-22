# Demo testing plan

## First validation

1. Railway reports v1.1.0 and MT5 EA 1.10.
2. The dashboard receives live snapshots every few seconds.
3. Momentum state moves between IDLE, ARMED, BURST, DECAY and EXHAUSTED.
4. When a BURST enters, MT5 shows three 0.01 positions with immediate SL and TP.
5. The dashboard shows the same position count, total lots, basket P/L and peak P/L.
6. A continuation stop appears only while the basket is profitable and live momentum remains BURST.
7. The total never exceeds five positions or 0.05 lots at default settings.
8. Basket target or profit trail closes all positions and removes pending orders.
9. The completed basket is recorded once with all legs and actual net P/L.

## Adverse checks

- Disable Algo Trading and confirm entry is blocked.
- Turn News Lock ON and confirm entry is blocked.
- Pause the EA and confirm open protection remains active but new entries/adds stop.
- Use Close Full Basket and verify CLOSE PENDING until all positions and orders are gone.
- During broker market closure, verify the close remains pending and retries after reopening.
- Manually close one basket leg and verify the EA flattens the remaining basket.

## Data review

Do not judge the edge from one or two baskets. Export both CSV files after at least:

- 50 completed baskets
- a mix of London, New York and quieter periods
- winning and losing market conditions

Review score bands, velocity, tick-rate expansion, extension, duration, MFE, MAE and exit reason before changing thresholds or exposure.
