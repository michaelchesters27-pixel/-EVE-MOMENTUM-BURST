#!/usr/bin/env python3
"""Static validation for EVE Momentum Burst v2.08."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "mt5" / "EVE_Momentum_Burst_EA_v2.08.mq5"


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
                state = "line"
                out.extend("  ")
                i += 2
                continue
            if c == "/" and n == "*":
                state = "block"
                out.extend("  ")
                i += 2
                continue
            if c == '"':
                state = "string"
                out.append(" ")
            else:
                out.append(c)
        elif state == "line":
            if c == "\n":
                state = "code"
                out.append("\n")
            else:
                out.append(" ")
        elif state == "block":
            if c == "*" and n == "/":
                state = "code"
                out.extend("  ")
                i += 2
                continue
            out.append("\n" if c == "\n" else " ")
        elif state == "string":
            if c == "\\":
                out.extend("  ")
                i += 2
                continue
            if c == '"':
                state = "code"
            out.append("\n" if c == "\n" else " ")
        i += 1
    if state in {"block", "string"}:
        fail(f"unterminated {state}")
    return "".join(out)


def function_body(text: str, name: str) -> str:
    match = re.search(rf"\b{name}\s*\([^;]*?\)\s*\{{", text, re.S)
    if not match:
        fail(f"function not found: {name}")
    start = text.find("{", match.start())
    depth = 0
    i = start
    state = "code"
    while i < len(text):
        c = text[i]
        n = text[i + 1] if i + 1 < len(text) else ""
        if state == "code":
            if c == "/" and n == "/":
                state = "line"
                i += 2
                continue
            if c == "/" and n == "*":
                state = "block"
                i += 2
                continue
            if c == '"':
                state = "string"
            elif c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    return text[start + 1 : i]
        elif state == "line":
            if c == "\n":
                state = "code"
        elif state == "block":
            if c == "*" and n == "/":
                state = "code"
                i += 2
                continue
        elif state == "string":
            if c == "\\":
                i += 2
                continue
            if c == '"':
                state = "code"
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
        if c == "\n":
            line += 1
        elif c in "([{":
            stack.append((c, line))
        elif c in ")]}":
            if not stack or stack[-1][0] != pairs[c]:
                fail(f"delimiter mismatch at line {line}: {c}")
            stack.pop()
    if stack:
        fail(f"unclosed delimiter {stack[-1]}")

    names = re.findall(
        r"(?m)^\s*(?:void|bool|int|long|ulong|double|string|datetime|ENUM_[A-Z0-9_]+)\s+([A-Za-z_]\w*)\s*\([^;{}]*\)\s*\{",
        clean,
    )
    duplicates = sorted({name for name in names if names.count(name) > 1})
    if duplicates:
        fail(f"duplicate function definitions: {duplicates}")

    required = {
        "property": '#property version   "2.08"',
        "heartbeat": '\\"version\\":\\"2.08\\"',
        "magic": "InpMagicNumber                    = 2207202608",
        "legacy magic": "InpLegacyMagicNumber               = 2207202606",
        "persistent prefix": 'StringFormat("EMB208_%I64d_%I64u_"',
        "new comments": 'comment = "EVE28-LAD"',
        "legacy comments": 'StringFind(comment, "EVE26-")',
        "tick watchdog": "DetectExecutionIntegrityBreach(tick);",
        "timer watchdog": "DetectExecutionIntegrityBreach(safety_tick);",
        "fill progression": "SequentialFillProgressed(execution_side, previous_trigger, price)",
        "fill/sl validation": "INVALID BUY FILL/SL",
        "buy quote watchdog": "tick.bid <= sl + tolerance",
        "sell quote watchdog": "tick.ask >= sl - tolerance",
        "missing sl watchdog": "has no broker-side SL",
        "pending-first close": "CANCELLING ALL PENDING BEFORE BANKING",
        "stale delete refresh": "ORDER CHANGED STATE - REFRESHING",
        "safe candle refresh": "SAFE TWO-SIDED REFRESH",
        "no strategy cooldown": "InpTradeRequestCooldownMs           = 0",
        "unlimited positions": "InpMaximumPositions                = 0",
        "unlimited lots": "InpMaximumTotalLots                = 0.0",
        "no session gate": "InpUseSessionFilter                = false",
    }
    for label, fragment in required.items():
        if fragment not in text:
            fail(f"missing invariant: {label}")

    for name in (
        "ManageBasket",
        "MaintainMovingStraddle",
        "MaintainProvisionalCampaign",
        "MaintainActiveLadder",
        "BuildSafePendingLevels",
        "DetectExecutionIntegrityBreach",
    ):
        body = function_body(text, name)
        for forbidden in (
            "InpAnalyticsReferenceScore",
            "buy_score",
            "sell_score",
            "score_gap",
            ".decision",
            ".momentum_state",
        ):
            if forbidden in body:
                fail(f"{name} contains analytics dependency: {forbidden}")

    moving = function_body(text, "MaintainMovingStraddle")
    if "CancelPendingOrders();\n         return;\n      }\n      ResetStraddleAnchor" in moving:
        fail("new-candle refresh still deletes the whole bracket")
    for fragment in ("REFRESHING BUY - SELL REMAINS LIVE", "REFRESHING SELL - BUY REMAINS LIVE", "straddle_buy_synced_candle", "straddle_sell_synced_candle"):
        if fragment not in moving:
            fail(f"safe two-sided refresh missing: {fragment}")

    close = function_body(text, "ContinuePendingClose")
    pending_index = close.find("CountOurPendingOrders() > 0")
    position_index = close.find("CountOurPositions() > 0")
    if pending_index < 0 or position_index < 0 or pending_index >= position_index:
        fail("campaign closure must quarantine pending orders before positions")

    transaction = function_body(text, "OnTradeTransaction")
    if transaction.find("fill_breach") > transaction.find("campaign_phase = CAMPAIGN_ACTIVE"):
        fail("fill integrity is checked too late")

    print(f"PASS: {SOURCE.name}")
    print(f"Functions: {len(names)} unique")
    print("Execution guards: sequential fills, actual-fill SL geometry, live quote SL watchdog, pending-first quarantine, stale-ticket refresh, safe two-sided candle refresh")
    print("NOTE: MetaEditor compilation is still required.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
