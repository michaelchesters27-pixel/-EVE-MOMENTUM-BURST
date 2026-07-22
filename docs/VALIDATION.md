# Validation record — v2.05

Checks completed in this package:

- balanced MQL5 braces, brackets and parentheses using a string/comment-aware scan;
- unique MQL5 function definitions;
- no calls from the active state machine to legacy market-order adding, reversal-stop or trailing functions;
- pending orders are submitted with a broker-side SL and `TP = 0`;
- confirmation/ladder SL construction requires the newest SL to sit beyond the previous trigger price;
- ladder spacing automatically widens to preserve that previous-leg price lock while respecting broker stop distance;
- the opposite provisional stop remains until two same-direction positions exist;
- confirmed ladder placement waits while an unwanted opposite/legacy pending order still exists;
- a broker-side SL close on the tracked newest position identifier requests full-basket closure;
- full-basket closure closes positions before clearing pending orders;
- v2.05 persistent state uses `EMB205`, avoiding v2.04 state inheritance;
- manual pause/emergency state is not automatically cleared at midnight;
- Railway JavaScript syntax checks pass;
- Railway Node test suite passes;
- local Railway `/api/state` check reports version 2.0.5;
- `tools/validate_source.py` passes.

MetaEditor is not available in this build environment. A zero-error MetaEditor compile remains mandatory before attaching the EA to MT5.
