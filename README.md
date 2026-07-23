# EVE MOMENTUM BURST v2.09

Complete GitHub-ready replacement for v2.08.

## Trading behaviour

1. While flat, every new M1 candle has one BUY STOP above it and one SELL STOP below it.
2. The first trigger is provisional. The opposite stop remains live.
3. A second same-direction fill confirms momentum only when it fills farther in the correct direction.
4. After confirmation, the opposite pending stop is removed.
5. Same-direction stop orders are staged ahead and replenished continuously.
6. Every position initially opens with a real broker-side SL.
7. After two or more same-direction positions exist, the EA calculates one profitable shared basket SL from the actual fills.
8. The newest position is updated first, then every older position is moved to exactly the same SL price.
9. The shared SL is calculated to protect at least the configured net basket profit after the configured commission reserve.
10. When the shared SL is reached, the broker closes the positions and the EA clears any remaining campaign orders before restarting.

## Shared basket SL

For a BUY ladder, the shared SL is above enough older BUY entries to bank their profit but below the newest BUY entry. For a SELL ladder, it is below enough older SELL entries but above the newest SELL entry.

The EA does not add another new ladder order until the currently open positions are synchronised to the shared SL. Existing broker-side pending orders remain protected by their own attached SLs during fast execution.

## Execution safety retained from v2.08

- wrong-sequence BUY/SELL fills are rejected;
- a second BUY must fill higher and a second SELL must fill lower;
- BUY stop execution is checked against Bid and SELL stop execution against Ask;
- missing or crossed broker-side SLs trigger campaign quarantine;
- pending orders are cancelled before forced basket closure;
- stale pending tickets are refreshed instead of being deleted repeatedly;
- the two-sided flat bracket is refreshed one side at a time.

## Version isolation

- v2.09 magic number: `2207202609`
- v2.09 order comments: `EVE29-INIT`, `EVE29-CONF`, `EVE29-LAD`
- previous v2.08 magic isolated/cleaned: `2207202608`

Close any open v2.08 positions before attaching v2.09. Recognised v2.08 pending orders are removed automatically when possible.

## Package contents

- `mt5/EVE_Momentum_Burst_EA_v2.09.mq5` — complete EA source
- `railway/` — dashboard/API service
- `supabase/schema.sql` — optional research database schema
- `docs/` — installation, strategy, testing and validation notes
- `tools/` — source and deterministic safety validators

MetaEditor is the definitive MQL5 compiler. Compile the EA with **0 errors** and test it on the IC Markets demo account before any live use.
