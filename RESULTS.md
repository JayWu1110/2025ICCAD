# Results and recommended deliverable

## Conclusion

**Best result: `hybrid_polish`**

| Item | Value |
|------|--------|
| DEF | `src/openRoad_eval_script/results/aes_cipher_top_hybrid_polish.def` |
| TNS | -8792.57 |
| WNS | -47.79 |
| Power | ~5.98e-02 W |
| HPWL | ~35082 |
| Avg displacement D | ~0.95 um |

This is the **best timing quality** among all strategies we ran (sweep + strengthen + no-recover polish). Relative to the contest baseline (TNS ≈ -100709, WNS ≈ -340), TNS/WNS improve substantially.

Do **not** pick a row only by the CSV `proxy_S` column for `*_polish` entries: that score uses **polish-only wall time** (~20–30 s), which inflates S versus full optimize runs. Ranking for delivery should prioritize **TNS / WNS / HPWL / D**, where **`hybrid_polish` wins**.

## Rejected / weaker alternatives

| Strategy | Why not best |
|----------|----------------|
| `hybrid_polish_nr` | TNS slightly worse than `hybrid_polish` (-8809 vs -8792); no clear PPA win |
| `full_buffer_polish` | Timing got worse after polish (TNS -17726) |
| `size_only_polish` | Worse TNS/WNS than `hybrid_polish` |
| `full_buffer` / `timing_first` / `size_only` / `adaptive` / `hybrid` | Worse TNS and/or WNS than `hybrid_polish` |

## How this DEF was produced

1. Sweep base strategies (`size_only`, `full_buffer`, `timing_first`, `adaptive`)
2. `./run.sh strengthen` → `optimize_hybrid.tcl` then polish winners
3. Polish of `aes_cipher_top_hybrid.def` → **`aes_cipher_top_hybrid_polish.def`**

## Reproduce comparison table

```bash
cd src/openroad_docker
./run.sh csv
# or
python3 ../python/compare_results.py --results-dir ../openRoad_eval_script/results
```

Artifacts: `openRoad_eval_script/results/comparison.csv` and `supplements/ICCAD_C_strategy_comparison.csv`.
