# Demo testing procedure — v3.02

## Installation proof

1. Keep Algo Trading OFF.
2. Remove all old EVE positions and pending orders.
3. Compile `mt5/EVE_Momentum_Burst_EA_v3.02.mq5` with 0 errors.
4. Attach v3.02 to XAUUSD M1.
5. Confirm chart/dashboard version `3.02`, Railway `3.0.2`, magic `2207202632`.
6. Turn Algo Trading ON.

## Mandatory live-state tests

### A. Flat state

Expected:

- Supervisor: `IDLE` while no burst exists.
- Positions: 0.
- Pending: 0.

### B. Armed state

When a burst arms a scout:

- Supervisor: `ARMED`.
- Exactly one pending order.
- BUY STOP must be above Ask.
- SELL STOP must be below Bid.
- Order role/comment must be `EVE33-INIT`.

### C. Wrong-side recovery

If any pending order is observed on the wrong side of live price:

- Supervisor must show `RECOVERY`.
- No new order may be created.
- The stale ticket must be deleted or, if it changes into a position, the full exposure must be closed.
- If the broker rejects the first cancellation and price later returns to the valid side, the EA must remain in `RECOVERY` and continue deleting it.
- Supervisor may return to `IDLE` only when positions = 0 and pending = 0.

### D. Scout protection

After one scout position reaches the profit-lock trigger:

- A profitable broker-side SL must appear, or
- the scout must close while still profitable.

A frozen or stale pending ticket must not block this protection path.

### E. Confirmation

With one scout position:

- At most one pending order may exist.
- It must be same-direction and comment `EVE33-CONF`.
- It must expire/remove when proof fades.

### F. Confirmed basket

With two or more positions:

- All positions must be the same direction.
- All positions must show the same shared SL.
- At most one `EVE33-LAD` pending order may exist.

### G. First-fill slippage

A materially adverse fill beyond the original pending price must produce an execution-integrity event and close the campaign. It must not be adopted as a normal scout or ladder fill.

## Data collection

Run on demo only. Save:

- MT5 HTML report;
- Experts and Journal around any recovery/fault event;
- dashboard Baskets, Legs and Orders CSV exports.

Do not consider live funds until these execution tests have passed repeatedly and a statistically meaningful forward-test sample is positive after commission and slippage.
