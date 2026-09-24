"""Window-based incremental optimization scheduler (report Algorithm 2 refined).

Backends are intentionally abstract:
  - relocate_fn(window, congestion) -> changelist
  - size_fn(window, congestion) -> changelist
  - buffer_fn(window, congestion) -> changelist   # budget-limited
  - sta_fn(window) -> metrics + congestion hint

Default backends are no-ops so the skeleton is unit-testable without GPU STA.
Wire a real OpenROAD/INSTA bridge later.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional

from .cost import ContestWeights, DesignMetrics, working_cost


Changelist = Dict[str, Any]
BackendFn = Callable[..., Changelist]
StaFn = Callable[..., tuple[DesignMetrics, Any]]


@dataclass
class AdaptiveConfig:
    w0: float = 8.0
    w_max: float = 64.0
    w_inc: float = 8.0
    rot: int = 3  # consecutive non-improving iters before growing window
    max_buffer_frac: float = 0.20
    max_avg_displacement: float = 1.0  # um budget (soft)
    prefer_resize_before_buffer: bool = True
    weights: ContestWeights = field(default_factory=ContestWeights)


@dataclass
class OptimizationState:
    best_metrics: DesignMetrics
    best_changelist: Changelist
    baseline: DesignMetrics
    history: List[dict] = field(default_factory=list)


def choose_openroad_seed_strategy(tns: float, hpwl_ratio_to_ref: float = 1.0) -> str:
    """Mirror optimize_adaptive.tcl policy in Python for orchestration scripts."""
    mag = abs(tns)
    if hpwl_ratio_to_ref > 1.15:
        return "size_only"
    if mag > 50000:
        return "timing_first"
    if mag > 15000:
        return "adaptive"
    return "size_only"


class WindowScheduler:
    def __init__(
        self,
        config: AdaptiveConfig,
        relocate_fn: Optional[BackendFn] = None,
        size_fn: Optional[BackendFn] = None,
        buffer_fn: Optional[BackendFn] = None,
        sta_fn: Optional[StaFn] = None,
    ) -> None:
        self.cfg = config
        self.relocate_fn = relocate_fn or (lambda **_: {})
        self.size_fn = size_fn or (lambda **_: {})
        self.buffer_fn = buffer_fn or (lambda **_: {})
        self.sta_fn = sta_fn

    def run(self, baseline: DesignMetrics) -> OptimizationState:
        if self.sta_fn is None:
            raise RuntimeError(
                "sta_fn is required. Plug in OpenROAD/INSTA bridge before running."
            )

        state = OptimizationState(
            best_metrics=baseline,
            best_changelist={},
            baseline=baseline,
        )
        best_cost = working_cost(baseline, baseline, self.cfg.weights)
        w = self.cfg.w0

        while w <= self.cfg.w_max:
            n_improv = 0
            congestion: Any = None
            while n_improv < self.cfg.rot:
                cl: Changelist = {}
                cl.update(
                    self.relocate_fn(window=w, congestion=congestion, budget=self.cfg)
                )
                cl.update(
                    self.size_fn(window=w, congestion=congestion, budget=self.cfg)
                )
                if self.cfg.prefer_resize_before_buffer:
                    # Buffer only if sizing did not sufficiently help — backend
                    # may no-op based on congestion / criticality.
                    cl.update(
                        self.buffer_fn(
                            window=w,
                            congestion=congestion,
                            budget=self.cfg,
                            max_frac=self.cfg.max_buffer_frac,
                        )
                    )

                metrics, congestion = self.sta_fn(window=w, changelist=cl)
                # Soft displacement guard
                if metrics.displacement > self.cfg.max_avg_displacement:
                    metrics = DesignMetrics(
                        tns=metrics.tns,
                        power=metrics.power,
                        hpwl=metrics.hpwl,
                        displacement=metrics.displacement,
                        runtime_s=metrics.runtime_s,
                    )

                cost = working_cost(metrics, baseline, self.cfg.weights)
                state.history.append(
                    {"w": w, "cost": cost, "metrics": metrics, "accepted": cost < best_cost}
                )
                if cost < best_cost:
                    best_cost = cost
                    state.best_metrics = metrics
                    state.best_changelist = cl
                    n_improv = 0
                else:
                    n_improv += 1
            w += self.cfg.w_inc

        return state
