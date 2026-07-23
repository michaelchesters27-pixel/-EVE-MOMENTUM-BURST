#!/usr/bin/env python3
"""Static validation for EVE Momentum Burst v2.09."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "mt5" / "EVE_Momentum_Burst_EA_v2.09.mq5"


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
    match = re.search(rf"(?m)^\s*(?:void|bool|int|long|ulong|double|string|datetime|ENUM_[A-Z0-9_]+)\s+{name}\s*\([^;]*?\)\s*\{{", text, re.S)
    if not match: fail(f"function not found: {name}")
    start = text.find("{", match.start())
    depth = 0; i = start; state = "code"
    while i < len(text):
        c = text[i]; n = text[i + 1] if i + 1 < len(text) else ""
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


def main() -> int:
    text = SOURCE.read_text(encoding="utf-8")
    clean = strip_comments_and_strings(text)

    stack: list[tuple[str, int]] = []
    pairs = {")": "(", "]": "[", "}": "{"}
    line = 1
    for c in clean:
        if c == "\n": line += 1
        elif c in "([{": stack.append((c, line))
        elif c in ")]}":
            if not stack or stack[-1][0] != pairs[c]: fail(f"delimiter mismatch at line {line}: {c}")
            stack.pop()
    if stack: fail(f"unclosed delimiter {stack[-1]}")

    names = re.findall(r"(?m)^\s*(?:void|bool|int|long|ulong|double|string|datetime|ENUM_[A-Z0-9_]+)\s+([A-Za-z_]\w*)\s*\([^;{}]*\)\s*\{", clean)
    duplicates = sorted({name for name in names if names.count(name) > 1})
    if duplicates: fail(f"duplicate function definitions: {duplicates}")

    required = {
        "property": '#property version   "2.09"',
        "heartbeat": '\\"version\\":\\"2.09\\"',
        "magic": "InpMagicNumber                    = 2207202609",
        "legacy magic": "InpLegacyMagicNumber               = 2207202608",
        "persistent prefix": 'StringFormat("EMB209_%I64d_%I64u_"',
        "new comments": 'comment = "EVE29-LAD"',
        "legacy comments": 'StringFind(comment, "EVE28-")',
        "shared profit": "InpSharedSLMinimumNetProfitMoney",
        "commission reserve": "InpSharedSLCommissionReservePerLot",
        "shared calculation": "CalculateSharedBasketStop",
        "shared synchronisation": "SynchronizeSharedBasketStop",
        "ticket modify": "trade.PositionModify(ticket, target, tp)",
        "newest modify first": "trade.PositionModify(newest_ticket, target, tp)",
        "shared equality": "PositionHasSharedStop(ticket, target)",
        "pending profit aware": "FindProjectedTargetPrice(side, required_gross, entry, entry, pending_volume, target_price)",
        "tick watchdog": "DetectExecutionIntegrityBreach(tick);",
        "timer watchdog": "DetectExecutionIntegrityBreach(safety_tick);",
        "fill progression": "SequentialFillProgressed(execution_side, previous_trigger, price)",
        "pending-first close": "CANCELLING ALL PENDING BEFORE BANKING",
        "safe candle refresh": "SAFE TWO-SIDED REFRESH",
        "no strategy cooldown": "InpTradeRequestCooldownMs           = 0",
        "unlimited positions": "InpMaximumPositions                = 0",
        "unlimited lots": "InpMaximumTotalLots                = 0.0",
        "no session gate": "InpUseSessionFilter                = false",
    }
    for label, fragment in required.items():
        if fragment not in text: fail(f"missing invariant: {label}")

    for name in ("ManageBasket", "MaintainMovingStraddle", "MaintainProvisionalCampaign", "MaintainActiveLadder", "BuildSafePendingLevels", "DetectExecutionIntegrityBreach", "SynchronizeSharedBasketStop"):
        body = function_body(text, name)
        for forbidden in ("InpAnalyticsReferenceScore", "buy_score", "sell_score", "score_gap", ".decision", ".momentum_state"):
            if forbidden in body: fail(f"{name} contains analytics dependency: {forbidden}")

    manage = function_body(text, "ManageBasket")
    cancel_i = manage.find("DeleteOneForActiveLadder(campaign_current_side)")
    sync_i = manage.find("SynchronizeSharedBasketStop()")
    ladder_i = manage.find("MaintainActiveLadder()")
    if min(cancel_i, sync_i, ladder_i) < 0 or not (cancel_i < sync_i < ladder_i):
        fail("active campaign must cancel opposite orders, synchronise shared SL, then build the ladder")

    calc = function_body(text, "CalculateSharedBasketStop")
    reserve_i = calc.find("candidate = side == \"BUY\" ? candidate + reserve : candidate - reserve")
    existing_i = calc.find("MostProtectiveExistingStop(side)")
    if reserve_i < 0 or existing_i < 0 or reserve_i >= existing_i:
        fail("shared-stop reserve must be applied before comparing the existing stop, otherwise it ratchets every tick")

    sync = function_body(text, "SynchronizeSharedBasketStop")
    newest_i = sync.find("trade.PositionModify(newest_ticket, target, tp)")
    older_i = sync.find("for(int i=PositionsTotal()-1")
    if newest_i < 0 or older_i < 0 or newest_i >= older_i:
        fail("newest position must receive the shared SL before older positions")

    integrity = function_body(text, "DetectExecutionIntegrityBreach")
    if "Older BUY positions are allowed" not in integrity or "Older SELL positions are allowed" not in integrity:
        fail("integrity watchdog still rejects profitable shared SLs on older positions")
    if "tick.bid <= sl + tolerance" not in integrity or "tick.ask >= sl - tolerance" not in integrity:
        fail("quote-side crossed-SL watchdog missing")

    moving = function_body(text, "MaintainMovingStraddle")
    for fragment in ("REFRESHING BUY - SELL REMAINS LIVE", "REFRESHING SELL - BUY REMAINS LIVE"):
        if fragment not in moving: fail(f"safe two-sided refresh missing: {fragment}")

    close = function_body(text, "ContinuePendingClose")
    pending_i = close.find("CountOurPendingOrders() > 0")
    positions_i = close.find("CountOurPositions() > 0")
    if pending_i < 0 or positions_i < 0 or pending_i >= positions_i:
        fail("campaign closure must quarantine pending orders before positions")

    print(f"PASS: {SOURCE.name}")
    print(f"Functions: {len(names)} unique")
    print("Shared SL: profit-aware calculation, commission reserve, newest-first synchronisation, identical broker-side SL across positions")
    print("NOTE: MetaEditor compilation is still required.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
