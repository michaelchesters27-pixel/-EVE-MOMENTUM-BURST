# Validation record — v2.04

Performed in the build environment:

- clean `npm ci`
- Railway server JavaScript syntax check
- dashboard JavaScript syntax check
- four Node automated tests
- local HTTP/API integration check with a v2.04 heartbeat and campaign fields
- local health endpoint confirmed version 2.0.4
- MQL5 structural checks:
  - balanced braces and parentheses
  - no duplicate function definitions
  - StringFormat placeholder/argument counts checked
  - no reserved identifier `protected`
  - strict OCO-cancelling state present
  - first-triggered-side conflict cleanup present
  - ladder additions blocked until OCO confirmation
  - newest-leg progress gate present
  - fixed hard-invalidation reversal stop present
  - one-request execution gate present
  - non-heartbeat telemetry removed from OnTick/OnTradeTransaction and queued for timer delivery
  - one blocking network request maximum per timer pass
  - heartbeat is first network priority
  - dashboard thresholds set to CONNECTED <45s, DELAYED 45–120s, OFFLINE >120s

MetaEditor compilation is still required. Static validation is not a substitute for the MQL5 compiler.
