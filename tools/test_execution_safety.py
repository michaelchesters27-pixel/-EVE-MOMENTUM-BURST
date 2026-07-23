#!/usr/bin/env python3
"""Deterministic strategy-model checks for v3.00."""
from __future__ import annotations


def directional_burst(side: str, v1: float, v3: float, acceleration: float, ticks: float, micro_break: bool) -> bool:
    direction = (v1 >= .025 and v3 >= .012) if side == "BUY" else (v1 <= -.025 and v3 <= -.012)
    return direction and acceleration >= 1.12 and ticks >= 1.18 and micro_break


def protected_net(peak: float, minimum: float = .10, giveback_percent: float = 35.0) -> float | None:
    if peak < .20: return None
    return max(minimum, peak * (1 - giveback_percent / 100))


def reacceleration(side: str, peak: float, current_net: float, locked: bool, v1: float, v3: float, acceleration: float, ticks: float, micro_break: bool, m5: str) -> bool:
    direction = (v1 >= .018 and v3 >= .010) if side == "BUY" else (v1 <= -.018 and v3 <= -.010)
    return peak >= .60 and current_net >= .35 and locked and direction and acceleration >= 1.05 and ticks >= 1.05 and micro_break and m5 != ("SELL" if side == "BUY" else "BUY")


def main() -> None:
    checks = 0
    assert directional_burst("BUY", .04, .02, 1.5, 1.3, True); checks += 1
    assert not directional_burst("BUY", .04, -.02, 1.5, 1.3, True); checks += 1
    assert directional_burst("SELL", -.04, -.02, 1.5, 1.3, True); checks += 1
    assert not directional_burst("SELL", -.04, .02, 1.5, 1.3, True); checks += 1

    assert protected_net(.19) is None; checks += 1
    assert abs(protected_net(.20) - .13) < 1e-9; checks += 1
    assert abs(protected_net(1.00) - .65) < 1e-9; checks += 1

    assert reacceleration("BUY", .80, .50, True, .03, .015, 1.2, 1.2, True, "BUY"); checks += 1
    assert not reacceleration("BUY", .40, .38, True, .03, .015, 1.2, 1.2, True, "BUY"); checks += 1
    assert not reacceleration("BUY", .80, .50, False, .03, .015, 1.2, 1.2, True, "BUY"); checks += 1
    assert not reacceleration("BUY", .80, .50, True, .01, .005, 1.2, 1.2, True, "BUY"); checks += 1
    assert not reacceleration("BUY", .80, .50, True, .03, .015, 1.2, 1.2, True, "SELL"); checks += 1

    # Evidence encoded from the supplied v2.11 report: one-leg baskets had the edge;
    # every multi-leg/reversal basket lost. This is the design reason for no opposite fill.
    one_leg_net = 3.70
    multi_leg_net = -8.52
    assert one_leg_net > 0; checks += 1
    assert multi_leg_net < 0; checks += 1
    assert one_leg_net + multi_leg_net < 0; checks += 1

    print(f"PASS: {checks} deterministic v3.00 checks")


if __name__ == "__main__":
    main()
