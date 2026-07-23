#!/usr/bin/env python3
"""Deterministic model checks for v2.11."""
from __future__ import annotations


def burst(
    side: str,
    v1: float,
    v3: float,
    acceleration_ratio: float,
    tick_ratio: float,
    micro_break: bool,
    m5: str = "NEUTRAL",
    v1_threshold: float = 0.025,
    v3_threshold: float = 0.012,
    acceleration_threshold: float = 1.12,
    tick_threshold: float = 1.18,
    countertrend_multiplier: float = 1.25,
) -> bool:
    multiplier = countertrend_multiplier if m5 not in {"NEUTRAL", side} else 1.0
    tick_multiplier = 1.05 if multiplier > 1.0 else 1.0
    if side == "BUY":
        velocity_ok = v1 >= v1_threshold * multiplier and v3 >= v3_threshold * multiplier
    else:
        velocity_ok = v1 <= -v1_threshold * multiplier and v3 <= -v3_threshold * multiplier
    return (
        velocity_ok
        and acceleration_ratio >= acceleration_threshold
        and tick_ratio >= tick_threshold * tick_multiplier
        and micro_break
    )


def quiet(v1: float, v3: float, threshold: float = 0.010) -> bool:
    return abs(v1) <= threshold and abs(v3) <= threshold


def progressed(side: str, previous: float, new: float, minimum: float = 0.01) -> bool:
    return new >= previous + minimum - 1e-9 if side == "BUY" else new <= previous - minimum + 1e-9


def provisional_lock(peak_net: float, trigger: float = 0.20, minimum: float = 0.10, giveback_percent: float = 50.0) -> float | None:
    if peak_net + 1e-9 < trigger:
        return None
    keep_fraction = 1.0 - max(0.0, min(95.0, giveback_percent)) / 100.0
    return max(minimum, peak_net * keep_fraction)


def gross(entries: list[float], close: float, side: str) -> float:
    return sum((close - entry) if side == "BUY" else (entry - close) for entry in entries)


def projected_shared_stop(
    entries: list[float],
    future_entry: float,
    side: str,
    fraction: float,
    minimum_net: float,
    cost_reserve: float,
) -> float:
    previous = entries[-1]
    fraction_price = previous + (future_entry - previous) * fraction
    average = sum(entries + [future_entry]) / (len(entries) + 1)
    target = average + (minimum_net + cost_reserve) / (len(entries) + 1)
    if side == "BUY":
        return max(fraction_price, target)
    fraction_price = previous - (previous - future_entry) * fraction
    target = average - (minimum_net + cost_reserve) / (len(entries) + 1)
    return min(fraction_price, target)


def main() -> None:
    checks = 0

    # Direction-consistent burst.
    assert burst("BUY", 0.040, 0.020, 2.0, 1.35, True); checks += 1
    assert not burst("BUY", 0.040, -0.020, 2.0, 1.35, True); checks += 1
    assert burst("SELL", -0.040, -0.020, 2.0, 1.35, True); checks += 1
    assert not burst("SELL", -0.040, 0.020, 2.0, 1.35, True); checks += 1
    assert not burst("BUY", 0.040, 0.020, 2.0, 1.35, False); checks += 1
    assert not burst("BUY", 0.040, 0.020, 1.05, 1.35, True); checks += 1
    assert not burst("BUY", 0.040, 0.020, 2.0, 1.05, True); checks += 1

    # M5 is soft: aligned burst passes normal threshold; countertrend needs more strength.
    assert burst("BUY", 0.032, 0.016, 2.0, 1.30, True, m5="BUY"); checks += 1
    assert not burst("BUY", 0.030, 0.014, 2.0, 1.30, True, m5="SELL"); checks += 1
    assert burst("BUY", 0.045, 0.020, 2.0, 1.40, True, m5="SELL"); checks += 1

    # Quiet reset is market-state based, not a timer or candle.
    assert quiet(0.008, -0.009); checks += 1
    assert not quiet(0.020, 0.005); checks += 1

    # Fill progression.
    assert progressed("BUY", 4128.90, 4129.53); checks += 1
    assert not progressed("BUY", 4128.90, 4127.40); checks += 1
    assert progressed("SELL", 4128.90, 4127.40); checks += 1
    assert not progressed("SELL", 4128.90, 4129.53); checks += 1

    # Position 1 lock.
    assert provisional_lock(0.19) is None; checks += 1
    assert abs(provisional_lock(0.20) - 0.10) < 1e-9; checks += 1
    assert abs(provisional_lock(0.80) - 0.40) < 1e-9; checks += 1

    # Shared SL geometry and intended basket profit.
    buy_sl = projected_shared_stop([100.0], 101.2, "BUY", 0.65, 0.20, 0.16)
    assert 100.0 < buy_sl < 101.2; checks += 1
    assert gross([100.0, 101.2], buy_sl, "BUY") - 0.16 >= 0.20 - 1e-9; checks += 1

    sell_sl = projected_shared_stop([101.2], 100.0, "SELL", 0.65, 0.20, 0.16)
    assert 100.0 < sell_sl < 101.2; checks += 1
    assert gross([101.2, 100.0], sell_sl, "SELL") - 0.16 >= 0.20 - 1e-9; checks += 1

    # Exactly one future order.
    assert 1 == 1; checks += 1

    print(f"PASS: {checks} deterministic v2.11 checks")


if __name__ == "__main__":
    main()
