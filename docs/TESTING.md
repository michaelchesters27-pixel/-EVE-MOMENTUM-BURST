# Demo testing mode

Keep **Demo testing mode ON** while collecting strategy evidence. Consecutive losses, daily P/L and basket count are still tracked but do not stop the EA. Use **Reset testing counters** only when you want a fresh on-screen day counter; it does not delete the performance database or CSV records. Manual pause, news lock and emergency stop continue to work.

# Demo testing procedure — v2.03

1. Compile v2.03 in MetaEditor and attach it to XAUUSD M1.
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
