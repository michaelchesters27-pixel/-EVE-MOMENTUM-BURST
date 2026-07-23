# Validation record — v3.01

Automated validation checks:

- EA/Railway/package version identity;
- magic number and persistent-state isolation;
- v2.09, v2.10 and v2.11 legacy recognition;
- balanced source delimiters and unique function definitions;
- tick-burst arming rather than candle arming;
- one directional scout pending stop in default mode;
- ATR-normalised 1-second and 3-second velocity;
- acceleration, tick expansion and micro-break requirements;
- M5 soft bias;
- burst expiry and quiet-reset rearming;
- no opposite reversal or hedge campaign;
- dynamic scout profit lock;
- momentum-stall banking;
- proof-based Position 2;
- expiring stale confirmation orders;
- one future ladder stop;
- profitable-basket and re-acceleration requirement for additions;
- pre-armed shared SL;
- Bid/Ask crossed-SL watchdogs;
- wide-spread entry quarantine;
- pending-order cancellation before forced closure;
- no analytics-score dependency in operational trading functions;
- Railway current-magic performance filtering.

The deterministic strategy model also encodes the supplied v2.11 finding that one-position baskets were positive while all multi-position baskets were negative.

Python/Node validation cannot compile MQL5. MetaEditor compilation with **0 errors** remains mandatory.
