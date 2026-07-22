# Demo testing procedure

1. Keep the EA on XAUUSD M1 and allow it to run without manual interference.
2. Export Baskets, Legs, Orders, Banking and Scans CSV files after each useful sample.
3. Compare:
   - canary banking outcomes
   - basket peak giveback outcomes
   - BUY versus SELL
   - normal versus high momentum
   - number of legs
   - lot size and maximum exposure
   - time of day
4. Do not change multiple parameters at once. Record each settings version in the events log.
5. Supabase is optional initially. Railway local JSONL records may be lost during redeployment unless a persistent volume is attached.
