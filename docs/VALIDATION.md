# Validation record — v2.10

Automated checks in this package verify:

- EA property and heartbeat version `2.10`, Railway version `2.0.10`;
- v2.10 magic `2207202610` and v2.09 isolation magic `2207202609`;
- `EVE30-*` order comments and `EMB210_*` persistent-state prefix;
- one campaign attempt per M1 candle and no timed strategy cooldown;
- Position 1 profit-lock trigger, minimum lock and 50% giveback calculation;
- no fixed TP;
- second-fill progression protection;
- pre-arming existing positions before Position 2 or the next ladder order is placed;
- exactly one future same-direction ladder order;
- shared basket-profit calculation and cost reserve;
- exact broker-side shared SL synchronisation;
- Bid/Ask crossed-SL watchdogs;
- abnormal-spread pending-entry quarantine;
- pending-order quarantine before forced position closure;
- safe two-sided candle refresh;
- no analytics-score dependency in operational trading functions;
- no session, position-count or total-lot strategy gate.

The Python validators cannot compile MQL5. MetaEditor compilation with **0 errors** remains mandatory.
