# EVE MOMENTUM BURST v2.10

Complete GitHub-ready replacement for v2.09.

## What v2.10 changes

The overnight v2.09 report showed that the profitable ladders were not the main problem. Most losses came from Position 1 or Position 1 + Position 2 repeatedly entering M1 noise, closing, and immediately starting again.

v2.10 corrects that execution pattern:

1. While flat, the EA maintains one BUY STOP and one SELL STOP for the current M1 candle.
2. Only one campaign attempt is allowed per M1 candle. This is not a timed cooldown. After a campaign ends, the EA waits for the next candle.
3. Position 1 remains provisional and the opposite stop stays live.
4. Position 1 has no fixed TP. After its floating profit reaches the configured trigger, its real broker-side SL is moved into profit and follows a 50% giveback rule.
5. Position 2 is not armed until Position 1 already carries the exact SL that Position 2 will receive.
6. A second BUY must fill higher than BUY 1. A second SELL must fill lower than SELL 1.
7. After confirmation, the opposite stop is cancelled.
8. Exactly one future same-direction ladder stop is allowed at a time.
9. Before that future stop is armed, every existing position must already carry the exact same planned broker-side basket SL.
10. When the shared SL is reached, the full campaign is cleared and the EA waits for the next M1 candle.

## Position 1 profit lock

Default behaviour:

- activation after Position 1 has reached at least `$0.20` floating profit;
- intended minimum protected net profit: `$0.10`;
- retain 50% of Position 1's best floating profit as the peak grows;
- no fixed TP;
- if profit gives back before the broker permits the SL modification, the EA banks the position rather than allowing it to become a full loser.

## Wide-spread safety

The EA still runs whenever the broker market is available, but it does not leave fresh pending entries active during an abnormal spread. Open positions keep their broker-side SL. Pending entries are restored automatically when spread returns to the configured safe range.

## Version isolation

- v2.10 magic number: `2207202610`
- v2.10 order comments: `EVE30-INIT`, `EVE30-CONF`, `EVE30-LAD`
- v2.10 persistent-state prefix: `EMB210_*`
- previous v2.09 magic isolated/cleaned: `2207202609`

Close every v2.09 position and delete its pending orders before attaching v2.10. Recognised v2.09 pending orders are also removed automatically when the broker permits deletion.

## Package contents

- `mt5/EVE_Momentum_Burst_EA_v2.10.mq5` — complete EA source
- `railway/` — dashboard/API service
- `supabase/schema.sql` — optional research database schema
- `docs/` — installation, strategy, testing and validation notes
- `tools/` — static source validator and deterministic execution-safety tests

MetaEditor is the definitive MQL5 compiler. Compile the EA with **0 errors** and test it on the IC Markets demo account before considering live use.
