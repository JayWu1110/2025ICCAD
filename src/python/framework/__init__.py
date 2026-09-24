"""Future GPU / differentiable incremental optimizer scaffold (Problem C).

This package does NOT replace OpenROAD yet. It encodes the joint objective
and iteration skeleton described in the report + contest-aligned cost, so
INSTA / FusionSizer / RLPlace backends can plug in later.

Typical roadmap:
  1. OpenROAD adaptive flow produces a strong legal seed (optimize_adaptive.tcl)
  2. WindowScheduler grows windows over critical regions
  3. Backends mutate (size, buffer, relocate) under DisplacementBudget
  4. cost.evaluate() accepts / rejects; export DEF changelist
"""

from .cost import ContestWeights, DesignMetrics, evaluate_score
from .pipeline import AdaptiveConfig, WindowScheduler, OptimizationState

__all__ = [
    "ContestWeights",
    "DesignMetrics",
    "evaluate_score",
    "AdaptiveConfig",
    "WindowScheduler",
    "OptimizationState",
]
