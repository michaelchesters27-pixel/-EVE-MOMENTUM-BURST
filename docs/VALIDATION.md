# Validation record — v2.09

Automated checks in this package verify:

- EA property, heartbeat and Railway version `2.09` / `2.0.9`;
- v2.09 magic `2207202609` and v2.08 isolation magic `2207202608`;
- new `EVE29-*` order comments and `EMB209_*` persistent state prefix;
- wrong-sequence fill protection;
- Bid/Ask crossed-SL watchdogs;
- shared basket-profit calculation and commission reserve;
- newest-position-first SL synchronisation;
- one identical SL across all same-direction positions;
- no new ladder construction before shared-SL synchronisation;
- pending-order quarantine before forced position closure;
- safe two-sided candle refresh;
- no strategy cooldown, position gate, total-lot gate or session gate.

MetaEditor compilation cannot be performed by the included Python validators and remains mandatory.
