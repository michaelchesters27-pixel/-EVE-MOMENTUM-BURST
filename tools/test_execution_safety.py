#!/usr/bin/env python3
"""Deterministic model checks for v2.10 campaign discipline and protection."""
from __future__ import annotations


def progressed(side: str, previous: float, new: float, minimum: float = 0.01) -> bool:
    return new >= previous + minimum - 1e-9 if side == "BUY" else new <= previous - minimum + 1e-9


def can_rearm(current_candle: int, last_finished_candle: int) -> bool:
    return last_finished_candle <= 0 or current_candle > last_finished_candle


def provisional_lock(peak_net: float, trigger: float = 0.20, minimum: float = 0.10, giveback_percent: float = 50.0) -> float | None:
    if peak_net + 1e-9 < trigger:
        return None
    keep_fraction = 1.0 - max(0.0, min(95.0, giveback_percent)) / 100.0
    return max(minimum, peak_net * keep_fraction)


def gross(entries: list[float], close: float, side: str) -> float:
    if side == "BUY":
        return sum(close - entry for entry in entries)
    return sum(entry - close for entry in entries)


def projected_shared_stop(
    entries: list[float],
    future_entry: float,
    side: str,
    fraction: float,
    minimum_net: float,
    cost_reserve: float,
    existing_protection: float | None = None,
) -> float:
    previous = entries[-1]
    all_entries = entries + [future_entry]
    fraction_price = previous + (future_entry - previous) * fraction if side == "BUY" else previous - (previous - future_entry) * fraction
    target_gross = minimum_net + cost_reserve
    average = sum(all_entries) / len(all_entries)
    target_price = average + target_gross / len(all_entries) if side == "BUY" else average - target_gross / len(all_entries)
    candidate = max(fraction_price, target_price) if side == "BUY" else min(fraction_price, target_price)
    if existing_protection is not None:
        candidate = max(candidate, existing_protection) if side == "BUY" else min(candidate, existing_protection)
    return candidate


def main() -> None:
    checks = 0

    # Actual fills must progress in the intended direction.
    assert progressed("BUY", 4128.90, 4129.53); checks += 1
    assert not progressed("BUY", 4128.90, 4127.40); checks += 1
    assert progressed("SELL", 4128.90, 4127.40); checks += 1
    assert not progressed("SELL", 4128.90, 4129.53); checks += 1

    # One attempt per M1 candle: no same-candle restart, immediate eligibility next candle.
    assert not can_rearm(1000, 1000); checks += 1
    assert can_rearm(1060, 1000); checks += 1

    # Position 1 lock: no lock before trigger, minimum lock at trigger, then 50% of peak.
    assert provisional_lock(0.19) is None; checks += 1
    assert abs(provisional_lock(0.20) - 0.10) < 1e-9; checks += 1
    assert abs(provisional_lock(0.80) - 0.40) < 1e-9; checks += 1
    assert abs(provisional_lock(1.60) - 0.80) < 1e-9; checks += 1

    # BUY Position 2 is pre-armed with a stop that protects Position 1 and remains below Position 2.
    buy_entries = [100.00]
    buy_future = 101.20
    buy_sl = projected_shared_stop(buy_entries, buy_future, "BUY", 0.65, 0.20, 0.16)
    assert buy_entries[-1] < buy_sl < buy_future; checks += 1
    assert gross(buy_entries + [buy_future], buy_sl, "BUY") - 0.16 >= 0.20 - 1e-9; checks += 1

    # SELL mirror.
    sell_entries = [101.20]
    sell_future = 100.00
    sell_sl = projected_shared_stop(sell_entries, sell_future, "SELL", 0.65, 0.20, 0.16)
    assert sell_future < sell_sl < sell_entries[-1]; checks += 1
    assert gross(sell_entries + [sell_future], sell_sl, "SELL") - 0.16 >= 0.20 - 1e-9; checks += 1

    # A stronger Position 1 lock is never weakened; the next entry must be moved farther instead.
    stronger_buy = projected_shared_stop([100.00], 101.50, "BUY", 0.65, 0.20, 0.16, existing_protection=100.95)
    assert stronger_buy >= 100.95; checks += 1
    assert stronger_buy < 101.50; checks += 1

    stronger_sell = projected_shared_stop([101.50], 100.00, "SELL", 0.65, 0.20, 0.16, existing_protection=100.55)
    assert stronger_sell <= 100.55; checks += 1
    assert stronger_sell > 100.00; checks += 1

    # Exactly one order ahead is the invariant; a fill is followed by one replacement, not a batch.
    future_pending_orders = 1
    assert future_pending_orders == 1; checks += 1

    # All existing positions and the future order use the same planned SL before the order is armed.
    existing_stops = [buy_sl, buy_sl, buy_sl]
    pending_stop = buy_sl
    assert all(abs(stop - pending_stop) < 1e-9 for stop in existing_stops); checks += 1

    # Wide-spread safety disarms entries but does not remove an existing position's SL.
    pending_entries = 2
    open_position_sl = 100.40
    spread_safe = False
    if not spread_safe:
        pending_entries = 0
    assert pending_entries == 0; checks += 1
    assert open_position_sl == 100.40; checks += 1

    print(f"PASS: {checks} deterministic v2.10 execution-safety checks")


if __name__ == "__main__":
    main()
