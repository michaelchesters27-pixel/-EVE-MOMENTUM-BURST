#!/usr/bin/env python3
"""Deterministic model checks for v2.08 execution-integrity rules."""
from __future__ import annotations


def progressed(side: str, previous: float, new: float, minimum: float = 0.01) -> bool:
    if side == "BUY":
        return new >= previous + minimum - 1e-9
    if side == "SELL":
        return new <= previous - minimum + 1e-9
    return False


def fill_sl_valid(side: str, fill: float, sl: float, bid: float, ask: float) -> bool:
    if side == "BUY":
        return sl < fill and bid > sl
    if side == "SELL":
        return sl > fill and ask < sl
    return False


def main() -> None:
    assert progressed("BUY", 4128.90, 4129.53)
    assert not progressed("BUY", 4128.90, 4127.40)  # observed bad second BUY
    assert progressed("SELL", 4128.90, 4127.40)
    assert not progressed("SELL", 4128.90, 4129.53)

    assert fill_sl_valid("BUY", 4128.90, 4127.09, 4128.20, 4128.30)
    assert not fill_sl_valid("BUY", 4127.40, 4129.31, 4126.92, 4127.02)  # observed invalid inherited SL
    assert not fill_sl_valid("BUY", 4128.90, 4127.09, 4126.84, 4126.94)  # Bid crossed SL

    assert fill_sl_valid("SELL", 4128.90, 4130.00, 4128.70, 4128.80)
    assert not fill_sl_valid("SELL", 4128.90, 4127.50, 4128.70, 4128.80)
    assert not fill_sl_valid("SELL", 4128.90, 4130.00, 4130.00, 4130.10)  # Ask crossed SL

    print("PASS: 10 deterministic execution-safety scenarios")


if __name__ == "__main__":
    main()
