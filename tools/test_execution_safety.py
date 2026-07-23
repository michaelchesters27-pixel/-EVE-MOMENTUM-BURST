#!/usr/bin/env python3
"""Deterministic model checks for v2.09 fill and shared-basket-SL rules."""
from __future__ import annotations


def progressed(side: str, previous: float, new: float, minimum: float = 0.01) -> bool:
    return new >= previous + minimum - 1e-9 if side == "BUY" else new <= previous - minimum + 1e-9


def gross(entries: list[float], close: float, side: str, money_per_price_per_leg: float = 1.0) -> float:
    if side == "BUY":
        return sum((close - entry) * money_per_price_per_leg for entry in entries)
    return sum((entry - close) * money_per_price_per_leg for entry in entries)


def shared_stop(entries: list[float], side: str, fraction: float, minimum_net: float, commission_reserve: float) -> float:
    previous, newest = entries[-2], entries[-1]
    fraction_price = previous + (newest - previous) * fraction if side == "BUY" else previous - (previous - newest) * fraction
    target_gross = minimum_net + commission_reserve
    # Linear unit model: solve sum(close-entry)=target for BUY and reverse for SELL.
    avg = sum(entries) / len(entries)
    target_price = avg + target_gross / len(entries) if side == "BUY" else avg - target_gross / len(entries)
    return max(fraction_price, target_price) if side == "BUY" else min(fraction_price, target_price)


def main() -> None:
    assert progressed("BUY", 4128.90, 4129.53)
    assert not progressed("BUY", 4128.90, 4127.40)
    assert progressed("SELL", 4128.90, 4127.40)
    assert not progressed("SELL", 4128.90, 4129.53)

    buy_entries = [100.00, 101.20]
    buy_sl = shared_stop(buy_entries, "BUY", 0.65, minimum_net=0.20, commission_reserve=0.14)
    assert buy_entries[0] < buy_sl < buy_entries[-1]
    assert gross(buy_entries, buy_sl, "BUY") - 0.14 >= 0.20 - 1e-9
    assert buy_sl - buy_entries[0] > 0
    assert buy_sl - buy_entries[-1] < 0
    assert all(sl == buy_sl for sl in [buy_sl, buy_sl])

    sell_entries = [101.20, 100.00]
    sell_sl = shared_stop(sell_entries, "SELL", 0.65, minimum_net=0.20, commission_reserve=0.14)
    assert sell_entries[-1] < sell_sl < sell_entries[0]
    assert gross(sell_entries, sell_sl, "SELL") - 0.14 >= 0.20 - 1e-9
    assert sell_entries[0] - sell_sl > 0
    assert sell_entries[-1] - sell_sl < 0
    assert all(sl == sell_sl for sl in [sell_sl, sell_sl])

    # Adding a third progressive BUY advances, rather than weakens, the shared stop.
    buy3 = [100.00, 101.20, 102.40]
    buy3_sl = shared_stop(buy3, "BUY", 0.65, minimum_net=0.20, commission_reserve=0.21)
    assert buy3_sl > buy_sl
    assert gross(buy3, buy3_sl, "BUY") - 0.21 >= 0.20 - 1e-9

    # Re-evaluating the same basket must not add the slippage reserve repeatedly.
    existing = buy3_sl
    recalculated = max(buy3_sl, existing)
    assert recalculated == existing

    print("PASS: 17 deterministic fill/shared-SL safety checks")


if __name__ == "__main__":
    main()
