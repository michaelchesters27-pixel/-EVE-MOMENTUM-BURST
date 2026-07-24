# Demo testing procedure — v4.10

## Installation proof

1. Compile with 0 MetaEditor errors.
2. Attach to XAUUSD M1 on a hedging demo account.
3. Confirm chart version `4.10`, Railway `4.1.0`, magic `2407202641`.
4. Confirm Railway heartbeat changes from OFFLINE to CONNECTED.

## Mandatory checks

### Flat state

- No position and no pending order unless a live burst is confirmed.
- Engine reads `WAITING FOR BURST` or `WAITING FOR QUIET RESET`.

### First order

- Exactly one BUY STOP or SELL STOP.
- BUY STOP is above Ask; SELL STOP is below Bid.
- The order uses GTC and has its own SL and TP.

### Filled position

- The position retains a broker-side SL and TP.
- No opposite-direction pending order is created.

### Momentum ladder

- At most one same-direction continuation pending order is ahead.
- Every newly filled position has its own SL and TP.
- The maximum position and total-lot limits are respected.

### Momentum fade

- Future pending additions are cancelled or safely deferred if inside the broker freeze zone.
- Existing positions are not force-closed merely because adding stopped.

### Direction change

- No opposite campaign starts while exposure remains.
- After the campaign finishes, the engine waits for quiet reset.
- Opposite direction requires the stronger held-signal rule.

### Railway

- Heartbeat is sent at the configured interval, not continuously.
- Failed HTTP requests back off instead of flooding the service.
- Dashboard reports EA 4.10 and the new strategy label.

Save the MT5 HTML report plus Experts and Journal screenshots for every execution fault. Do not consider live funds without a substantial positive forward-test sample after spread, commission and slippage.
