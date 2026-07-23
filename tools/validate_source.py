#!/usr/bin/env python3
"""Static validation for EVE Momentum Burst v3.01."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "mt5" / "EVE_Momentum_Burst_EA_v3.01.mq5"
SERVER = ROOT / "railway" / "src" / "server.js"
APP = ROOT / "railway" / "public" / "app.js"
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
            if c == "/" and n == "/": state = "line"; out.extend("  "); i += 2; continue
            if c == "/" and n == "*": state = "block"; out.extend("  "); i += 2; continue
            if c == '"': state = "string"; out.append(" ")
            else: out.append(c)
        elif state == "line":
            if c == "\n": state = "code"; out.append("\n")
            else: out.append(" ")
        elif state == "block":
            if c == "*" and n == "/": state = "code"; out.extend("  "); i += 2; continue
            out.append("\n" if c == "\n" else " ")
        else:
            if c == "\\": out.extend("  "); i += 2; continue
            if c == '"': state = "code"
            out.append("\n" if c == "\n" else " ")
        i += 1
    if state in {"block", "string"}: fail(f"unterminated {state}")
    return "".join(out)



def split_top_level_arguments(text: str) -> list[str]:
    parts: list[str] = []
    start = 0
    depth = 0
    state = "code"
    i = 0
    while i < len(text):
        c = text[i]
        n = text[i + 1] if i + 1 < len(text) else ""
        if state == "code":
            if c == '"': state = "string"
            elif c == "/" and n == "/": state = "line"; i += 1
            elif c == "/" and n == "*": state = "block"; i += 1
            elif c in "([{": depth += 1
            elif c in ")]}": depth -= 1
            elif c == "," and depth == 0:
                parts.append(text[start:i].strip()); start = i + 1
        elif state == "string":
            if c == "\\": i += 1
            elif c == '"': state = "code"
        elif state == "line":
            if c == "\n": state = "code"
        elif state == "block":
            if c == "*" and n == "/": state = "code"; i += 1
        i += 1
    parts.append(text[start:].strip())
    return parts


def validate_string_formats(text: str) -> None:
    marker = "StringFormat("
    position = 0
    spec_re = re.compile(r"%(?!%)(?:[-+0 #]*\d*(?:\.\d+)?(?:I64)?[A-Za-z])")
    while True:
        start = text.find(marker, position)
        if start < 0: return
        open_at = start + len("StringFormat")
        depth = 0
        state = "code"
        i = open_at
        while i < len(text):
            c = text[i]
            n = text[i + 1] if i + 1 < len(text) else ""
            if state == "code":
                if c == '"': state = "string"
                elif c == "/" and n == "/": state = "line"; i += 1
                elif c == "/" and n == "*": state = "block"; i += 1
                elif c == "(": depth += 1
                elif c == ")":
                    depth -= 1
                    if depth == 0: break
            elif state == "string":
                if c == "\\": i += 1
                elif c == '"': state = "code"
            elif state == "line":
                if c == "\n": state = "code"
            elif state == "block":
                if c == "*" and n == "/": state = "code"; i += 1
            i += 1
        if i >= len(text): fail("unclosed StringFormat call")
        inside = text[open_at + 1:i]
        parts = split_top_level_arguments(inside)
        literals = re.findall(r'"((?:\\.|[^"\\])*)"', parts[0], re.S) if parts else []
        format_text = "".join(literals)
        expected = len(spec_re.findall(format_text))
        actual = max(0, len(parts) - 1)
        if expected != actual:
            line = text.count("\n", 0, start) + 1
            fail(f"StringFormat argument mismatch at line {line}: {expected} placeholders, {actual} arguments")
        position = i + 1

def function_body(text: str, name: str) -> str:
    m = re.search(rf"(?m)^\s*(?:void|bool|int|long|ulong|double|string|datetime|ENUM_[A-Z0-9_]+)\s+{re.escape(name)}\s*\([^;]*?\)\s*\{{", text, re.S)
    if not m: fail(f"function not found: {name}")
    start = text.find("{", m.start())
    depth = 0
    i = start
    state = "code"
    while i < len(text):
        c = text[i]; n = text[i + 1] if i + 1 < len(text) else ""
        if state == "code":
            if c == "/" and n == "/": state = "line"; i += 2; continue
            if c == "/" and n == "*": state = "block"; i += 2; continue
            if c == '"': state = "string"
            elif c == "{": depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0: return text[start + 1:i]
        elif state == "line":
            if c == "\n": state = "code"
        elif state == "block":
            if c == "*" and n == "/": state = "code"; i += 2; continue
        else:
            if c == "\\": i += 2; continue
            if c == '"': state = "code"
        i += 1
    fail(f"unclosed function: {name}")
    return ""


def require(text: str, fragment: str, label: str) -> None:
    if fragment not in text: fail(f"missing invariant: {label}")


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

    validate_string_formats(text)

    # Catch accidental repeated declarations copied onto adjacent lines.
    lines = text.splitlines()
    declaration = re.compile(r"^\s*(?:bool|int|long|ulong|double|string|datetime|ENUM_[A-Z0-9_]+)\s+[A-Za-z_]\w*(?:\s*=.*)?;\s*$")
    for index in range(1, len(lines)):
        if declaration.match(lines[index]) and lines[index].strip() == lines[index - 1].strip():
            fail(f"duplicate adjacent local declaration at line {index + 1}: {lines[index].strip()}")

    names = re.findall(r"(?m)^\s*(?:void|bool|int|long|ulong|double|string|datetime|ENUM_[A-Z0-9_]+)\s+([A-Za-z_]\w*)\s*\([^;{}]*\)\s*\{", clean)
    duplicates = sorted({name for name in names if names.count(name) > 1})
    if duplicates: fail(f"duplicate function definitions: {duplicates}")

    required = {
        "property": '#property version   "3.01"',
        "heartbeat version": '\\"version\\":\\"3.01\\"',
        "heartbeat magic": '\\"magic\\":\\"%I64u\\"',
        "strategy label": "SCOUT_PROTECTED_LADDER",
        "magic": "InpMagicNumber                    = 2207202631",
        "previous magic": "InpLegacyMagicNumber               = 2207202630",
        "persistent prefix": 'StringFormat("EMB301_%I64d_%I64u_"',
        "initial comment": 'comment = "EVE32-INIT"',
        "confirmation comment": 'comment = "EVE32-CONF"',
        "ladder comment": 'string comment = "EVE32-LAD"',
        "directional scout input": "InpDirectionalScoutOnly",
        "profit lock": "MaintainProvisionalProfitLock",
        "stall exit": "MaintainScoutStallExit",
        "confirmation proof": "ScoutReadyForConfirmation",
        "ladder proof": "BasketReadyForNextLadder",
        "no TP": "InpTakeProfitATR                   = 0.0",
        "shared stop": "SynchronizeSharedBasketStop",
        "crossed stop watchdog": "DetectExecutionIntegrityBreach(tick);",
        "wide spread": "EntrySpreadSafe",
        "broker legal boundary": "BrokerLegalProtectionBoundary",
        "legal target clamp": "ResolveLegalProfitLockTarget",
        "urgent scout exit": "StartUrgentScoutExit",
        "protection request path": "ProtectionRequestAvailable",
    }
    for label, fragment in required.items(): require(text, fragment, label)

    moving = function_body(text, "MaintainMovingStraddle")
    for fragment in ("buy_burst", "sell_burst", "burst_reset_ready", "BURST EXPIRED", "DIRECTIONAL TICK-BURST SCOUT", "directional live-burst scout; no opposite pending order"):
        require(moving, fragment, f"moving scout {fragment}")
    if moving.count('PlacePendingOrder(wanted, "INITIAL"') != 1:
        fail("directional mode must place exactly one selected scout stop")

    provisional = function_body(text, "MaintainProvisionalCampaign")
    for fragment in ("DeleteOneForProvisional", "MaintainProvisionalProfitLock", "MaintainScoutStallExit", "ScoutReadyForConfirmation", "CONFIRMATION PRE-ARM", "PlacePendingOrderExact"):
        require(provisional, fragment, f"provisional {fragment}")
    for forbidden in ("ProvisionalGuardPrice", "RESTORING OPPOSITE", "opposite stop remains"):
        if forbidden in provisional: fail(f"opposite reversal logic remains in scout campaign: {forbidden}")

    if provisional.find("MaintainProvisionalProfitLock") > provisional.find("DeleteOneForProvisional"):
        fail("Position 1 protection must run before pending-order cleanup")

    manage = function_body(text, "ManageBasket")
    if manage.find("MaintainProvisionalProfitLock") > manage.find("HandleLegacyPendingCleanup"):
        fail("ManageBasket must protect Position 1 before legacy/pending cleanup")
    urgent = function_body(text, "ContinueUrgentScoutExit")
    require(urgent, "trade.PositionClose", "urgent direct position close")
    if "CancelPendingOrders" in urgent:
        fail("urgent scout close must not wait for pending-order cancellation")
    lock = function_body(text, "MaintainProvisionalProfitLock")
    for fragment in ("ResolveLegalProfitLockTarget", "POSITION 1 FALLBACK PROFIT LOCK ARMED", "BROKER REJECTED PROFIT PROTECTION", "StartUrgentScoutExit"):
        require(lock, fragment, f"profit protection {fragment}")
    if "TradeRequestAvailable()" in lock:
        fail("profit protection must bypass pending-delete request locks")

    transaction = function_body(text, "OnTradeTransaction")
    require(transaction, "NO REVERSAL CAMPAIGNS ARE ALLOWED", "opposite fill closes instead of flips")
    require(transaction, "DIRECTIONAL TICK-BURST SCOUT TRIGGER", "directional scout entry reason")

    mixed = function_body(text, "ResolveMixedDirectionIfNeeded")
    require(mixed, "NO REVERSAL OR HEDGE CAMPAIGN", "mixed direction full close")
    if "PositionClose(ticket" in mixed: fail("mixed direction must close the full basket, not retain one side")

    active = function_body(text, "MaintainActiveLadder")
    for fragment in ("BasketReadyForNextLadder", "ladder continuation faded", "NEXT LADDER PRE-ARM", "one stop ahead only"):
        require(active, fragment, f"active ladder {fragment}")

    operational = ("ManageBasket", "MaintainMovingStraddle", "MaintainProvisionalCampaign", "MaintainProvisionalProfitLock", "MaintainActiveLadder", "BuildSafePendingLevels", "SynchronizeSharedBasketStop", "DetectExecutionIntegrityBreach")
    for name in operational:
        body = function_body(text, name)
        for forbidden in ("InpAnalyticsReferenceScore", "buy_score", "sell_score", "score_gap", ".decision"):
            if forbidden in body: fail(f"{name} contains analytics-score dependency: {forbidden}")

    server = SERVER.read_text(encoding="utf-8")
    app = APP.read_text(encoding="utf-8")
    package = PACKAGE.read_text(encoding="utf-8")
    require(server, "version: '3.0.1'", "Railway version")
    require(server, "BROKER-LEGAL SCOUT PROFIT PROTECTION + RE-ACCELERATION LADDER", "Railway mode")
    require(server, "currentVersionRecords", "current-version performance filtering")
    require(server, "CURRENT_EA_MAGIC = '2207202631'", "dashboard default current magic")
    for record_function in ("SendScan", "SendLegRecord", "SendOrderActivity", "SendBankDecision"):
        require(function_body(text, record_function), r'\"magic\":\"%I64u\"', f"{record_function} magic tag")
    require(app, "older bot data is excluded", "dashboard scope message")
    require(package, '"version": "3.0.1"', "package version")

    print(f"PASS: {SOURCE.name}")
    print(f"Functions: {len(names)} unique")
    print("Verified: broker-legal Position 1 SL clamp, protection-first execution ordering, immediate close fallback, directional scout, re-acceleration confirmation, shared SL and current-version dashboard filtering")
    print("NOTE: MetaEditor compilation is still required.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
