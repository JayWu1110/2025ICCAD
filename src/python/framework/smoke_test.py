#!/usr/bin/env python3
"""Sanity checks for the framework scaffold (no OpenROAD required)."""

from framework.cost import ContestWeights, DesignMetrics, evaluate_score, working_cost
from framework.pipeline import AdaptiveConfig, WindowScheduler, choose_openroad_seed_strategy


def test_score_prefers_better_tns_with_bounded_wl():
    base = DesignMetrics(tns=-100709.3, power=5.53e-2, hpwl=32394.3)
    good = DesignMetrics(tns=-12829.0, power=5.75e-2, hpwl=34396.8, displacement=0.5, runtime_s=63)
    bad_wl = DesignMetrics(tns=-12000.0, power=5.90e-2, hpwl=50000.0, displacement=1.2, runtime_s=80)
    w = ContestWeights()
    assert evaluate_score(good, base, w) > evaluate_score(bad_wl, base, w)
    assert working_cost(good, base, w) < working_cost(bad_wl, base, w)


def test_strategy_policy():
    assert choose_openroad_seed_strategy(-100709) == "timing_first"
    assert choose_openroad_seed_strategy(-20000) == "adaptive"
    assert choose_openroad_seed_strategy(-5000) == "size_only"
    assert choose_openroad_seed_strategy(-20000, hpwl_ratio_to_ref=1.2) == "size_only"


def test_scheduler_accepts_improvement():
    base = DesignMetrics(tns=-100.0, power=1.0, hpwl=100.0)

    def sta_fn(window, changelist):
        # Pretend each iter halves |TNS| with tiny WL hit
        m = DesignMetrics(tns=-50.0, power=1.01, hpwl=101.0, displacement=0.1, runtime_s=1.0)
        return m, {"ok": True}

    sched = WindowScheduler(
        AdaptiveConfig(w0=8, w_max=8, w_inc=8, rot=1),
        sta_fn=sta_fn,
    )
    state = sched.run(base)
    assert abs(state.best_metrics.tns) < abs(base.tns)


if __name__ == "__main__":
    test_score_prefers_better_tns_with_bounded_wl()
    test_strategy_policy()
    test_scheduler_accepts_improvement()
    print("All framework smoke tests passed.")
