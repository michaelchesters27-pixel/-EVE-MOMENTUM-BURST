# Validation record — v2.11

Automated checks verify:

- version and magic isolation;
- v2.09/v2.10 legacy recognition;
- tick-by-tick burst arming rather than candle arming;
- ATR-normalised 1-second and 3-second velocity thresholds;
- acceleration ratio and tick-rate expansion;
- direction-consistent micro-breakout;
- M5 soft bias with stronger counter-trend requirements;
- burst expiry and quiet-reset rearming;
- Position 1 profit lock;
- no fixed TP;
- fill-progression protection;
- one future ladder stop;
- pre-armed shared SL;
- Bid/Ask crossed-SL watchdogs;
- wide-spread pending-entry quarantine;
- pending-order cancellation before forced closure;
- no analytics-score dependency in operational trading functions.

Python validation cannot compile MQL5. MetaEditor compilation with 0 errors remains mandatory.
