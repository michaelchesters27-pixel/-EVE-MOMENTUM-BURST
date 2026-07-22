# Validation record

Automated validation performed in the build environment:

- Node syntax check for Railway server and dashboard JavaScript
- Node test suite for detailed performance calculations, settings validation, CSV escaping and HTTP server construction
- Local API integration checks
- ZIP integrity check
- MQL5 static checks for balanced braces/parentheses, duplicate function definitions and undefined EA input references

The MQL5 EA must still be compiled in the user's MetaEditor. A static source check is not a MetaEditor compilation.
