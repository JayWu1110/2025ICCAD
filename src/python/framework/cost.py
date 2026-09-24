"""Contest-aligned multi-objective cost (shared with contest_score.py ideas)."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass
class ContestWeights:
    alpha: float = 0.50  # TNS
    beta: float = 0.25  # Power
    gamma: float = 0.25  # Wirelength
    w_p: float = 1000.0
    w_d: float = 50.0
    w_r: float = 300.0


@dataclass
class DesignMetrics:
    tns: float
    power: float
    hpwl: float
    displacement: float = 0.0
    runtime_s: float = 0.0


def _tns_norm(tns_new: float, tns_base: float) -> float:
    mag_b = abs(tns_base)
    mag_n = abs(tns_new)
    if mag_b == 0:
        return 1.0 if mag_n == 0 else 0.0
    return min(2.0, mag_b / max(mag_n, 1e-12))


def _ratio_improve(new: float, base: float) -> float:
    if base == 0:
        return 1.0
    if new == 0:
        return 2.0
    return min(2.0, max(0.0, base / new))


def evaluate_score(
    current: DesignMetrics,
    baseline: DesignMetrics,
    weights: ContestWeights | None = None,
) -> float:
    """Higher is better (official S direction)."""
    w = weights or ContestWeights()
    p = (
        w.alpha * _tns_norm(current.tns, baseline.tns)
        + w.beta * _ratio_improve(current.power, baseline.power)
        + w.gamma * _ratio_improve(current.hpwl, baseline.hpwl)
    )
    r_proxy = current.runtime_s / 100.0
    return w.w_p * p - w.w_d * current.displacement - w.w_r * r_proxy


def working_cost(
    current: DesignMetrics,
    baseline: DesignMetrics,
    weights: ContestWeights | None = None,
) -> float:
    """Lower is better — convenient for accept/reject loops."""
    return -evaluate_score(current, baseline, weights)
