#!/usr/bin/env python3
"""Static validation for EVE Momentum Burst v2.10."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "mt5" / "EVE_Momentum_Burst_EA_v2.10.mq5"
SERVER = ROOT / "railway" / "src" / "server.js"
PACKAGE = ROOT / "railway" / "package.json"


def fail(message: str) -> None:
    raise AssertionError(message)


def strip_comments_and_strings(text: str) -> str:
    out: list[str] = []
    i = 0
    state = "code"
    while i < len(text):
        c = text[i]
        n = text[i + 1] if i + 1 < len(text) else ""
        if state == "code":
            if c == "/" and n == "/":
                state = "line"; out.extend("  "); i += 2; continue
            if c == "/" and n == "*":
                state = "block"; out.extend("  "); i += 2; continue
            if c == '"':
                state = "string"; out.append(" ")
            else:
                out.append(c)
        elif state == "line":
            if c == "\n": state = "code"; out.append("\n")
            else: out.append(" ")
        elif state == "block":
            if c == "*" and n == "/":
                state = "code"; out.extend("  "); i += 2; continue
            out.append("\n" if c == "\n" else " ")
        elif state == "string":
            if c == "\\": out.extend("  "); i += 2; continue
            if c == '"': state = "code"
            out.append("\n" if c == "\n" else " ")
        i += 1
    if state in {"block", "string"}: fail(f"unterminated {state}")
    return "".join(out)


def function_body(text: str, name: str) -> str:
    match = re.search(
        rf"(?m)^\s*(?:void|bool|int|long|ulong|double|string|datetime|ENUM_[A-Z0-9_]+)\s+{re.escape(name)}\s*\([^;]*?\)\s*\{{",
        text,
        re.S,
    )
    if not match: fail(f"function not found: {name}")
    start = text.find("{", match.start())
    depth = 0
    i = start
    state = "code"
    while i < len(text):
        c = text[i]
        n = text[i + 1] if i + 1 < len(text) else ""
        if state == "code":
            if c == "/" and n == "/": state = "line"; i += 2; continue
            if c == "/" and n == "*": state = "block"; i += 2; continue
            if c == '"': state = "string"
            elif c == "{": depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0: return text[start + 1 : i]
        elif state == "line":
            if c == "\n": state = "code"
        elif state == "block":
            if c == "*" and n == "/": state = "code"; i += 2; continue
        elif state == "string":
            if c == "\\": i += 2; continue
            if c == '"': state = "code"
        i += 1
    fail(f"unclosed function body: {name}")
    return ""


def require_order(body: str, fragments: list[str], message: str) -> None:
    positions = [body.find(fragment) for fragment in fragments]
    if any(pos < 0 for pos in positions) or positions != sorted(positions):
        fail(message + f"; positions={positions}")


def main() -> int:
    if not SOURCE.exists(): fail(f"missing source: {SOURCE}")
    text = SOURCE.read_text(encoding="utf-8")
    clean = strip_comments_and_strings(text)

    # Balanced delimiters after comments and strings are removed.
    stack: list[tuple[str, int]] = []
    pairs = {")": "(", "]": "[", "}": "{"}
    line = 1
    for c in clean:
        if c == "\n": line += 1
        elif c in "([{": stack.append((c, line))
        elif c in ")]}" :
            if not stack or stack[-1][0] != pairs[c]: fail(f"delimiter mismatch at line {line}: {c}")
            stack.pop()
    if stack: fail(f"unclosed delimiter {stack[-1]}")

    names = re.findall(
        r"(?m)^\s*(?:void|bool|int|long|ulong|double|string|datetime|ENUM_[A-Z0-9_]+)\s+([A-Za-z_]\w*)\s*\([^;{}]*\)\s*\{",
        clean,
    )
    duplicates = sorted({name for name in names if names.count(name) > 1})
    if duplicates: fail(f"duplicate function definitions: {duplicates}")

    required = {
        "property": '#property version   "2.10"',
        "heartbeat": '\\"version\\":\\"2.10\\"',
        "magic": "InpMagicNumber                    = 2207202610",
        "legacy magic": "InpLegacyMagicNumber               = 2207202609",
        "persistent prefix": 'StringFormat("EMB210_%I64d_%I64u_"',
        "new initial comment": 'comment = "EVE30-INIT"',
        "new confirmation comment": 'comment = "EVE30-CONF"',
        "new ladder comment": 'string comment = "EVE30-LAD"',
        "legacy v2.09 comments": 'StringFind(comment, "EVE29-")',
        "one-attempt input": "InpOneCampaignAttemptPerCandle      = true",
        "wait-next phase": "CAMPAIGN_WAIT_NEXT_CANDLE",
        "finished-candle persistence": 'GVSet("finishedcandle", (double)last_campaign_finished_candle)',
        "no timed cooldown": "InpPostCampaignCooldownSeconds     = 0",
        "profit-lock trigger": "InpProvisionalLockTriggerMoney     = 0.20",
        "profit-lock minimum": "InpProvisionalLockMinimumMoney     = 0.10",
        "profit-lock giveback": "InpProvisionalLockGivebackPercent  = 50.0",
        "profit-lock function": "MaintainProvisionalProfitLock",
        "profit-lock broker SL": "trade.PositionModify(ticket, target, tp)",
        "profit-lock giveback close": 'BankBasket("POSITION 1 PROFIT GIVEBACK EXIT"',
        "no fixed TP": "InpTakeProfitATR                   = 0.0",
        "one future stop": "confirmed campaign permits exactly one same-side ladder stop ahead",
        "prearm synchronisation": "SynchronizeExistingPositionsToTarget",
        "exact pending placement": "PlacePendingOrderExact",
        "shared basket stop": "SynchronizeSharedBasketStop",
        "cost-aware projected target": "FindProjectedTargetPrice",
        "commission reserve": "InpSharedSLCommissionReservePerLot = 8.00",
        "spread safety": "InpPausePendingEntriesOnWideSpread  = true",
        "spread checker": "EntrySpreadSafe",
        "crossed-SL watchdog": "DetectExecutionIntegrityBreach(tick);",
        "wrong-sequence fill": "SequentialFillProgressed(execution_side, previous_trigger, price)",
        "pending-first close": "CANCELLING ALL PENDING BEFORE BANKING",
        "safe buy refresh": "REFRESHING BUY - SELL REMAINS LIVE",
        "safe sell refresh": "REFRESHING SELL - BUY REMAINS LIVE",
        "no request cooldown": "InpTradeRequestCooldownMs           = 0",
        "unlimited positions": "InpMaximumPositions                = 0",
        "unlimited lots": "InpMaximumTotalLots                = 0.0",
        "no session gate": "InpUseSessionFilter                = false",
    }
    for label, fragment in required.items():
        if fragment not in text: fail(f"missing invariant: {label}")

    # Operational trading functions must not depend on display analytics.
    operational = (
        "ManageBasket",
        "MaintainMovingStraddle",
        "MaintainProvisionalCampaign",
        "MaintainProvisionalProfitLock",
        "MaintainActiveLadder",
        "BuildSafePendingLevels",
        "SynchronizeExistingPositionsToTarget",
        "SynchronizeSharedBasketStop",
        "DetectExecutionIntegrityBreach",
    )
    for name in operational:
        body = function_body(text, name)
        for forbidden in ("InpAnalyticsReferenceScore", "buy_score", "sell_score", "score_gap", ".decision", ".momentum_state"):
            if forbidden in body: fail(f"{name} contains analytics dependency: {forbidden}")

    moving = function_body(text, "MaintainMovingStraddle")
    wait_i = moving.find("last_campaign_finished_candle")
    wait_phase_i = moving.find("CAMPAIGN_WAIT_NEXT_CANDLE", wait_i)
    wait_cancel_i = moving.find("CancelPendingOrders()", wait_phase_i)
    if min(wait_i, wait_phase_i, wait_cancel_i) < 0 or not (wait_i < wait_phase_i < wait_cancel_i):
        fail("same-candle restart must be blocked and pending orders cleared")
    if "EntrySpreadSafe(spread_reason)" not in moving or "WIDE SPREAD - ENTRIES DISARMED" not in moving:
        fail("flat-state wide-spread entry quarantine missing")

    provisional_lock = function_body(text, "MaintainProvisionalProfitLock")
    for fragment in ("newest_leg_peak_profit", "peak * keep_fraction", "CalculateProvisionalLockTarget", "trade.PositionModify(ticket, target, tp)"):
        if fragment not in provisional_lock: fail(f"Position 1 profit-lock invariant missing: {fragment}")
    if "return true;" not in provisional_lock:
        fail("Position 1 lock must be able to pause Position 2 placement while protection is being armed")

    provisional = function_body(text, "MaintainProvisionalCampaign")
    require_order(
        provisional,
        [
            'BuildSafePendingLevels(StopTypeForSide(side), "CONFIRMATION"',
            'SynchronizeExistingPositionsToTarget(side, planned_sl, "CONFIRMATION PRE-ARM")',
            'PlacePendingOrderExact(StopTypeForSide(side), "CONFIRMATION"',
        ],
        "Position 1 must be pre-armed before Position 2 is placed",
    )
    if "MaintainProvisionalProfitLock()" not in provisional:
        fail("provisional campaign does not call Position 1 profit lock")

    active = function_body(text, "MaintainActiveLadder")
    require_order(
        active,
        [
            'BuildSafePendingLevels(StopTypeForSide(side), "LADDER"',
            'SynchronizeExistingPositionsToTarget(side, planned_sl, "NEXT LADDER PRE-ARM")',
            'PlacePendingOrderExact(StopTypeForSide(side), "LADDER"',
        ],
        "existing positions must be pre-armed before the one future ladder stop is placed",
    )

    delete_active = function_body(text, "DeleteOneForActiveLadder")
    if "bool kept_one = false" not in delete_active or "role == \"LADDER\" && !kept_one" not in delete_active:
        fail("active ladder does not enforce exactly one future pending stop")

    levels = function_body(text, "BuildSafePendingLevels")
    for fragment in ("FindProjectedTargetPrice", "existing_protection", "geometry_ok"):
        if fragment not in levels:
            fail(f"pending shared SL invariant missing: {fragment}")
    target_i = levels.find("FindProjectedTargetPrice")
    preserve_i = levels.find("candidate = type == ORDER_TYPE_BUY_STOP ? MathMax(candidate, existing_protection)", target_i)
    geometry_i = levels.find("geometry_ok", preserve_i)
    if min(target_i, preserve_i, geometry_i) < 0 or not (target_i < preserve_i < geometry_i):
        fail("pending shared SL must calculate profit, preserve stronger protection, then verify broker geometry")
    if "tp = 0.0" not in levels:
        fail("pending levels must use no fixed TP")

    integrity = function_body(text, "DetectExecutionIntegrityBreach")
    for fragment in ("tick.bid <= sl + tolerance", "tick.ask >= sl - tolerance", "SequentialFillProgressed"):
        if fragment not in integrity: fail(f"execution-integrity watchdog missing: {fragment}")

    manage = function_body(text, "ManageBasket")
    require_order(
        manage,
        ["DeleteOneForActiveLadder(campaign_current_side)", "SynchronizeSharedBasketStop()", "MaintainActiveLadder()"],
        "active campaign must clean orders, synchronise actual fills, then prepare one future order",
    )

    close = function_body(text, "ContinuePendingClose")
    require_order(
        close,
        ["CountOurPendingOrders() > 0", "CountOurPositions() > 0"],
        "campaign closure must quarantine pending orders before closing positions",
    )

    server = SERVER.read_text(encoding="utf-8")
    package = PACKAGE.read_text(encoding="utf-8")
    if "version: '2.0.10'" not in server: fail("Railway server version is not 2.0.10")
    if '"version": "2.0.10"' not in package: fail("Railway package version is not 2.0.10")

    print(f"PASS: {SOURCE.name}")
    print(f"Functions: {len(names)} unique")
    print("Verified: one M1 attempt, Position 1 profit lock, pre-armed shared SL, one order ahead, spread quarantine, execution watchdog")
    print("NOTE: MetaEditor compilation is still required.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
