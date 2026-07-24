#!/usr/bin/env python3
"""Deterministic behavioural checks for v4.10."""
from __future__ import annotations


def score_signal(v1: float, v3: float, v10: float, tick_ratio: float, acceleration: float, micro_break: bool, body: float, side: str) -> int:
    sign = 1 if side == "BUY" else -1
    score = 0
    score += sign * v1 >= 0.040
    score += sign * v3 >= 0.070
    score += sign * v10 >= 0.100
    score += tick_ratio >= 1.10
    score += acceleration >= 1.05 and sign * v1 > 0
    score += micro_break
    score += sign * body >= 0.08
    return int(score)


def opposite_allowed(last_side: str, new_side: str, quiet_reset: bool, score: int, held_ms: int) -> bool:
    if not quiet_reset:
        return False
    if last_side != "NONE" and new_side != last_side:
        return score >= 6 and held_ms >= 1000
    return score >= 5 and held_ms >= 400


def legal_stop(side: str, desired: float, bid: float, ask: float, minimum: float) -> float:
    return min(desired, bid - minimum) if side == "BUY" else max(desired, ask + minimum)


def better_stop(side: str, old: float, candidate: float) -> float:
    if old <= 0:
        return candidate
    return max(old, candidate) if side == "BUY" else min(old, candidate)


def cancel_action(order_exists: bool, active_state: bool, in_freeze: bool) -> str:
    if not order_exists or not active_state:
        return "CLEAR"
    if in_freeze:
        return "DEFER"
    return "DELETE"


def main() -> None:
    checks = 0
    buy = score_signal(.06, .10, .15, 1.3, 1.4, True, .12, "BUY")
    sell = score_signal(.06, .10, .15, 1.3, 1.4, False, .12, "SELL")
    assert buy >= 5 and sell < buy; checks += 1

    assert not opposite_allowed("SELL", "BUY", False, 7, 5000); checks += 1
    assert not opposite_allowed("SELL", "BUY", True, 5, 1500); checks += 1
    assert not opposite_allowed("SELL", "BUY", True, 7, 999); checks += 1
    assert opposite_allowed("SELL", "BUY", True, 7, 1000); checks += 1
    assert opposite_allowed("BUY", "BUY", True, 5, 400); checks += 1

    assert better_stop("BUY", 100.0, 100.5) == 100.5; checks += 1
    assert better_stop("BUY", 100.5, 100.2) == 100.5; checks += 1
    assert better_stop("SELL", 100.0, 99.5) == 99.5; checks += 1
    assert better_stop("SELL", 99.5, 99.8) == 99.5; checks += 1
    assert legal_stop("BUY", 100.8, 100.9, 100.92, .2) == 100.7; checks += 1
    assert legal_stop("SELL", 99.2, 99.08, 99.10, .2) == 99.3; checks += 1

    assert cancel_action(False, True, False) == "CLEAR"; checks += 1
    assert cancel_action(True, False, False) == "CLEAR"; checks += 1
    assert cancel_action(True, True, True) == "DEFER"; checks += 1
    assert cancel_action(True, True, False) == "DELETE"; checks += 1

    print(f"PASS: {checks} v4.10 deterministic safety checks")


if __name__ == "__main__":
    main()
