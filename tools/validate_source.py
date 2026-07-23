#!/usr/bin/env python3
"""Static validation for EVE Momentum Burst v2.11."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "mt5" / "EVE_Momentum_Burst_EA_v2.11.mq5"
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
    if state in {"block", "string"}:
        fail(f"unterminated {state}")
    return "".join(out)


def function_body(text: str, name: str) -> str:
    match = re.search(
        rf"(?m)^\s*(?:void|bool|int|long|ulong|double|string|datetime|ENUM_[A-Z0-9_]+)\s+{re.escape(name)}\s*\([^;]*?\)\s*\{{",
        text,
        re.S,
    )
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
            if c == "/" and n == "/": state = "line"; i += 2; continue
            if c == "/" and n == "*": state = "block"; i += 2; continue
            if c == '"': state = "string"
            elif c == "{": depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    return text[start + 1:i]
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
        "property": '#property version   "2.11"',
        "heartbeat": '\\"version\\":\\"2.11\\"',
        "magic": "InpMagicNumber                    = 2207202611",
        "previous magic": "InpLegacyMagicNumber               = 2207202610",
        "older magic": "InpOlderLegacyMagicNumber          = 2207202609",
        "persistent prefix": 'StringFormat("EMB211_%I64d_%I64u_"',
        "initial comment": 'comment = "EVE31-INIT"',
        "confirmation comment": 'comment = "EVE31-CONF"',
        "ladder comment": 'string comment = "EVE31-LAD"',
        "v2.10 comment cleanup": 'StringFind(comment, "EVE30-")',
        "v2.09 comment cleanup": 'StringFind(comment, "EVE29-")',
        "tick warmup": "InpMinimumWarmupSeconds             = 30",
        "burst 1s threshold": "InpBurstArmVelocity1ATR",
        "burst 3s threshold": "InpBurstArmVelocity3ATR",
        "acceleration ratio": "speed1 / speed3",
        "tick expansion": "InpBurstArmTickExpansion",
        "M5 soft bias": "InpUseM5SoftBias",
        "countertrend multiplier": "InpM5CounterTrendBurstMultiplier",
        "quiet reset": "InpBurstResetQuietVelocityATR",
        "burst expiry": "InpBurstBracketLifetimeSeconds",
        "profit lock": "MaintainProvisionalProfitLock",
        "no TP": "InpTakeProfitATR                   = 0.0",
        "one order ahead": "confirmed campaign permits exactly one same-side ladder stop ahead",
        "prearm": "SynchronizeExistingPositionsToTarget",
        "shared stop": "SynchronizeSharedBasketStop",
        "crossed stop watchdog": "DetectExecutionIntegrityBreach(tick);",
        "wide spread": "EntrySpreadSafe",
    }
    for label, fragment in required.items():
        if fragment not in text:
            fail(f"missing invariant: {label}")

    moving = function_body(text, "MaintainMovingStraddle")
    for fragment in (
        "WATCHING LIVE TICKS",
        "buy_velocity",
        "sell_velocity",
        "buy_burst",
        "sell_burst",
        "last_scan.micro_break_buy",
        "last_scan.micro_break_sell",
        "burst_reset_ready",
        "BURST EXPIRED",
        "TICK-BURST BRACKET READY",
    ):
        if fragment not in moving:
            fail(f"burst engine invariant missing: {fragment}")

    # Critical units check: velocities are already ATR-normalised and must not be multiplied by ATR.
    forbidden_units = (
        "atr * InpBurstArmVelocity1ATR",
        "atr * InpBurstArmVelocity3ATR",
        "atr * InpBurstResetQuietVelocityATR",
    )
    for fragment in forbidden_units:
        if fragment in moving:
            fail(f"ATR-normalised velocity compared with price units: {fragment}")

    require_order(
        moving,
        ["buy_velocity", "buy_acceleration", "buy_tick_expansion", "buy_burst"],
        "BUY burst must require direction-consistent velocity, acceleration, tick expansion and micro-break",
    )
    require_order(
        moving,
        ["sell_velocity", "sell_acceleration", "sell_tick_expansion", "sell_burst"],
        "SELL burst must require direction-consistent velocity, acceleration, tick expansion and micro-break",
    )

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
            if forbidden in body:
                fail(f"{name} contains analytics-score dependency: {forbidden}")

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
        fail("Position 1 profit lock is not called")

    active = function_body(text, "MaintainActiveLadder")
    require_order(
        active,
        [
            'BuildSafePendingLevels(StopTypeForSide(side), "LADDER"',
            'SynchronizeExistingPositionsToTarget(side, planned_sl, "NEXT LADDER PRE-ARM")',
            'PlacePendingOrderExact(StopTypeForSide(side), "LADDER"',
        ],
        "existing positions must be pre-armed before the next ladder order",
    )

    integrity = function_body(text, "DetectExecutionIntegrityBreach")
    for fragment in ("tick.bid <= sl + tolerance", "tick.ask >= sl - tolerance", "SequentialFillProgressed"):
        if fragment not in integrity:
            fail(f"execution watchdog missing: {fragment}")

    close = function_body(text, "ContinuePendingClose")
    require_order(
        close,
        ["CountOurPendingOrders() > 0", "CountOurPositions() > 0"],
        "pending orders must be quarantined before positions close",
    )

    server = SERVER.read_text(encoding="utf-8")
    package = PACKAGE.read_text(encoding="utf-8")
    if "version: '2.0.11'" not in server:
        fail("Railway version mismatch")
    if "LIVE TICK BURST" not in server:
        fail("Railway mode does not describe tick-burst engine")
    if '"version": "2.0.11"' not in package:
        fail("package version mismatch")

    print(f"PASS: {SOURCE.name}")
    print(f"Functions: {len(names)} unique")
    print("Verified: live tick burst, correct ATR-normalised units, M5 soft bias, quiet reset, Position 1 lock, shared SL and execution watchdog")
    print("NOTE: MetaEditor compilation is still required.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
