# Demo testing procedure — v2.02

1. Compile v2.02 in MetaEditor and attach it to XAUUSD M1.
2. Leave it running without manual interference for a defined test window.
3. Confirm Pending Order Activity shows `PLACED`, `MODIFIED` and `CANCEL-REQUESTED` rather than repeated `invalid price` or `invalid request`.
4. Confirm only one BUY STOP and one SELL STOP exist while flat.
5. Confirm only the opposite reversal stop remains during a ladder.
6. Confirm a mixed-direction transition removes old-direction positions without duplicate requests.
7. Confirm basket reports appear only after positions and pending orders are both zero.
8. Export Baskets, Legs, Orders, Banking and Scans CSV files.
9. Compare canary exits, peak-giveback exits, BUY/SELL results, position counts and market regimes.
10. Change one setting at a time.

Railway local JSONL data may be lost on redeployment unless a persistent volume or Supabase is used.
