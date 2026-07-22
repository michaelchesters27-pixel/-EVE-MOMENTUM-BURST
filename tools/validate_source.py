#!/usr/bin/env python3
"""Static package validation for EVE Momentum Burst v2.06.

This is not a substitute for MetaEditor compilation. It catches structural damage and
verifies the locked campaign invariants requested for this build.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "mt5" / "EVE_Momentum_Burst_EA_v2.06.mq5"


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
                state = "line_comment"
                out.extend("  ")
                i += 2
                continue
            if c == "/" and n == "*":
                state = "block_comment"
                out.extend("  ")
                i += 2
                continue
            if c == '"':
                state = "string"
                out.append(" ")
                i += 1
                continue
            out.append(c)
        elif state == "line_comment":
            if c == "\n":
                state = "code"
                out.append("\n")
            else:
                out.append(" ")
        elif state == "block_comment":
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
    if state in {"block_comment", "string"}:
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
                state = "line_comment"
                i += 2
                continue
            if c == "/" and n == "*":
                state = "block_comment"
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
        elif state == "line_comment":
            if c == "\n":
                state = "code"
        elif state == "block_comment":
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

    # Balanced delimiters after comments/strings are removed.
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

    # Function names should be unique in this single-source EA.
    names = re.findall(
        r"(?m)^\s*(?:void|bool|int|long|ulong|double|string|datetime|ENUM_[A-Z0-9_]+)\s+([A-Za-z_]\w*)\s*\([^;{}]*\)\s*\{",
        clean,
    )
    duplicates = sorted({name for name in names if names.count(name) > 1})
    if duplicates:
        fail(f"duplicate function definitions: {duplicates}")

    required_fragments = {
        "v2.06 property": '#property version   "2.06"',
        "new persistent prefix": 'StringFormat("EMB206_%I64d_%I64u_"',
        "isolated magic number": "InpMagicNumber                    = 2207202606",
        "legacy cleanup magic": "InpLegacyMagicNumber               = 2207202603",
        "legacy pending cleanup": "HandleLegacyPendingCleanup()",
        "analytics-only score": "InpAnalyticsReferenceScore",
        "no strategy request cooldown": "InpTradeRequestCooldownMs           = 0",
        "no position ceiling": "InpMaximumPositions                = 0",
        "no total-lot ceiling": "InpMaximumTotalLots                = 0.0",
        "no session gate": "InpUseSessionFilter                = false",
        "no fixed TP": "InpTakeProfitATR                   = 0.0",
        "profit-lock input": "InpNewestSLPreviousLegLockFraction",
        "newest position tracking": "newest_position_id",
        "newest SL event": "deal_reason == DEAL_REASON_SL && position_id > 0 && position_id == newest_position_id",
        "second-trigger confirmation": "CountOurPositionsBySide(campaign_current_side) >= 2",
        "confirmation anchor": '"CONFIRMATION", lot, desired, atr_value, base',
        "ladder anchor": '"LADDER", CalculateLegLot(), desired, CurrentOrderAtr(), base',
        "profit lock comparison": "sl > protect_anchor_price : sl < protect_anchor_price",
        "SL and no TP submit": "safe_price, trade_symbol, sl, 0.0, ORDER_TIME_GTC",
    }
    for label, fragment in required_fragments.items():
        if fragment not in text:
            fail(f"missing invariant: {label}")

    manage = function_body(text, "ManageBasket")
    for forbidden in (
        "InsideTradingSessionUTC(",
        "TradingConditionsOkay(",
        "TryAddRollingLeg(",
        "MaintainReverseStop(",
        "TrailAllPositions(",
        "InpMaximumBasketLossMoney",
        "InpMaximumBasketMinutes",
        "InpPostCampaignCooldownSeconds",
        "manual_news_lock",
    ):
        if forbidden in manage:
            fail(f"active ManageBasket contains forbidden gate/call: {forbidden}")

    operational_functions = [
        "ManageBasket",
        "MaintainMovingStraddle",
        "MaintainProvisionalCampaign",
        "MaintainActiveLadder",
        "BuildSafePendingLevels",
    ]
    for function_name in operational_functions:
        body = function_body(text, function_name)
        for forbidden in (
            "InpAnalyticsReferenceScore",
            "buy_score",
            "sell_score",
            "score_gap",
            ".decision",
            ".momentum_state",
            ".block_reason",
        ):
            if forbidden in body:
                fail(f"{function_name} contains analytics/score dependency: {forbidden}")

    moving = function_body(text, "MaintainMovingStraddle")
    if "manual_news_lock" in moving or "InsideTradingSessionUTC(" in moving:
        fail("flat candle straddle is still gated by news/session logic")

    legacy = function_body(text, "HandleLegacyPendingCleanup")
    for fragment in ("InpLegacyMagicNumber", "trade.OrderDelete", "EVE-MB2-", "EVE25-"):
        if fragment not in text:
            fail(f"legacy isolation missing: {fragment}")

    close = function_body(text, "ContinuePendingClose")
    positions_index = close.find("CountOurPositions() > 0")
    pending_index = close.find("CountOurPendingOrders() > 0")
    if positions_index < 0 or pending_index < 0 or positions_index >= pending_index:
        fail("basket close must process positions before pending orders")

    active = function_body(text, "MaintainActiveLadder")
    if 'if(DeleteOneForActiveLadder(side)) return;' not in active:
        fail("active ladder does not wait for opposite/legacy order cleanup")

    levels = function_body(text, "BuildSafePendingLevels")
    for fragment in (
        "protect_anchor_price + required_gap",
        "protect_anchor_price - required_gap",
        "entry - stops_distance",
        "entry + stops_distance",
        "prior_leg_locked",
    ):
        if fragment not in levels:
            fail(f"profit-lock level construction missing: {fragment}")

    print(f"PASS: {SOURCE.name}")
    print(f"Functions: {len(names)} unique")
    print("Locked invariants: score-independent candle straddle, 2-trigger confirmation, continuous stop ladder, previous-leg SL profit lock, newest-SL basket bank, legacy order isolation, no automatic strategy gates")
    print("NOTE: MetaEditor compilation is still required.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
