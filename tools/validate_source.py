#!/usr/bin/env python3
"""Static validation for EVE Fury Reconstruction Demo v4.10."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "mt5" / "EVE_Fury_Reconstruction_Demo_v4.10.mq5"
SERVER = ROOT / "railway" / "src" / "server.js"
APP = ROOT / "railway" / "public" / "app.js"
INDEX = ROOT / "railway" / "public" / "index.html"


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
        else:
            if c == "\\":
                out.extend("  "); i += 2; continue
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
        fmt = "".join(literals)
        expected = len(spec_re.findall(fmt))
        actual = max(0, len(parts) - 1)
        if expected != actual:
            line = text.count("\n", 0, start) + 1
            fail(f"StringFormat mismatch line {line}: {expected} placeholders, {actual} arguments")
        position = i + 1


def function_body(text: str, name: str) -> str:
    pattern = re.compile(rf"(?m)^\s*[A-Za-z_][A-Za-z0-9_<>]*\s+{re.escape(name)}\s*\([^;]*?\)\s*\{{", re.S)
    match = pattern.search(text)
    if not match: fail(f"function not found: {name}")
    start = text.find("{", match.start())
    clean = strip_comments_and_strings(text[start:])
    depth = 0
    for offset, c in enumerate(clean):
        if c == "{": depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return text[start + 1:start + offset]
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
            if not stack or stack[-1][0] != pairs[c]: fail(f"delimiter mismatch line {line}: {c}")
            stack.pop()
    if stack: fail(f"unclosed delimiter {stack[-1]}")

    validate_string_formats(text)

    names = re.findall(r"(?m)^\s*(?:void|bool|int|long|ulong|double|string|datetime)\s+([A-Za-z_]\w*)\s*\([^;{}]*\)\s*\{", clean)
    duplicates = sorted({name for name in names if names.count(name) > 1})
    if duplicates: fail(f"duplicate function definitions: {duplicates}")

    required = {
        "version": '#property version   "4.10"',
        "magic": "InpMagicNumber                    = 2407202641",
        "strategy": "INDIVIDUAL_SL_TP_MOMENTUM_LADDER",
        "buy stop individual sl tp": "trade.BuyStop(volume, entry, trade_symbol, sl, tp, ORDER_TIME_GTC, 0, comment)",
        "sell stop individual sl tp": "trade.SellStop(volume, entry, trade_symbol, sl, tp, ORDER_TIME_GTC, 0, comment)",
        "quiet reset": "QuietResetComplete",
        "opposite confirmation": "InpOppositeSignalHoldMilliseconds",
        "opposite multiplier": "InpOppositeThresholdMultiplier",
        "freeze aware cancel": "OrderInsideFreezeZone",
        "reselect after delete failure": "if(!OrderSelect(ticket)) continue;",
        "individual protection": "ManageIndividualProtection",
        "break even": "InpBreakEvenTriggerATR",
        "trailing": "InpTrailingActivationATR",
        "http backoff": "RegisterHttpFailure",
        "heartbeat version": '\\"version\\":\\"4.10\\"',
    }
    for label, fragment in required.items(): require(text, fragment, label)

    forbidden = [
        "shared_basket_stop", "SynchronizeSharedBasketStop", "DETERMINISTIC_SCOUT_LADDER",
        "SCOUT OPEN", "re-acceleration", "ORDER_TIME_SPECIFIED", "ORDER_TIME_DAY",
        "EVE33-INIT", "EVE33-CONF", "EVE33-LAD",
    ]
    for fragment in forbidden:
        if fragment in text: fail(f"legacy/faulty engine fragment remains: {fragment}")

    run_engine = function_body(text, "RunEngine")
    require(run_engine, "if(positions > 0)", "active exposure branch")
    require(run_engine, "CancelAllPending(\"momentum faded or opposite pressure confirmed\")", "no active flip")
    if "ConfirmedSignal()" in run_engine.split("if(positions > 0)", 1)[1].split("return;", 1)[0]:
        fail("active position branch may evaluate a new opposite campaign")

    confirmed = function_body(text, "ConfirmedSignal")
    for fragment in ("opposite_to_last", "InpOppositeThresholdMultiplier", "InpOppositeSignalHoldMilliseconds"):
        require(confirmed, fragment, f"opposite confirmation {fragment}")

    cancel = function_body(text, "CancelAllPending")
    for fragment in ("OrderInsideFreezeZone", "trade.OrderDelete", "if(!OrderSelect(ticket)) continue;"):
        require(cancel, fragment, f"safe cancel {fragment}")

    protect = function_body(text, "ManageIndividualProtection")
    for fragment in ("PositionModify", "BetterStop", "ClampLegalStop", "StopImprovesEnough"):
        require(protect, fragment, f"individual protection {fragment}")

    post = function_body(text, "PostJson")
    require(post, "Connection: close", "HTTP connection close")
    require(post, "RegisterHttpFailure", "HTTP failure backoff")
    if "/api/ea/event" in text or "/api/ea/bank" in text:
        fail("high-frequency event/bank telemetry endpoints must not remain")

    server = SERVER.read_text(encoding="utf-8")
    app = APP.read_text(encoding="utf-8")
    index = INDEX.read_text(encoding="utf-8")
    for fragment in ("version: '4.1.0'", "INDIVIDUAL SL/TP MOMENTUM LADDER", "CURRENT_EA_MAGIC = '2407202641'"):
        require(server, fragment, f"Railway {fragment}")
    for fragment in ("every position has its own broker-side SL and TP", "/7 BUY", "/7 SELL"):
        require(app, fragment, f"dashboard {fragment}")
    require(index, "EVE Fury Reconstruction Demo v4.10", "dashboard title")

    print("PASS: EVE Fury Reconstruction Demo v4.10 static validation")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
