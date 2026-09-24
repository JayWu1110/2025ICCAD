# Problem C sources

## Goal
Simultaneous **gate sizing**, **buffering**, and **cell relocation** after detailed placement to improve timing, power, and HPWL under legality and contest score \(S\).

## Best result
**`hybrid_polish`** — `openRoad_eval_script/results/aes_cipher_top_hybrid_polish.def`  
Details: [RESULTS.md](../RESULTS.md)

## Run
See the top-level [README.md](../README.md).

Short path inside an OpenROAD container:
```bash
cd openRoad_eval_script
openroad -exit eval_def.tcl
openroad -exit optimize_adaptive.tcl
bash run_experiments.sh --strengthen
```

From host (Docker):
```bash
cd openroad_docker
./run.sh strengthen
./run.sh csv
```

Python helpers:
```bash
cd python
python3 contest_score.py --from-report
python3 compare_results.py
python3 analyze_placement.py
python3 -m framework.smoke_test
```
