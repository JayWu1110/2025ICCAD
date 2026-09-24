# 2025 ICCAD Contest Problem C

**Incremental Placement Optimization Beyond Detailed Placement: Simultaneous Gate Sizing, Buffering, and Cell Relocation**

## 1. Problem
After detailed placement, jointly apply **gate sizing**, **buffering**, and **cell relocation** to improve PPA while keeping placement legal. Contest score:

$$
S = 1000 P - 50 D - 300 R,\quad
P = \alpha\,TNS_{norm} + \beta\,POWER_{norm} + \gamma\,WL_{norm}
$$

## 2. What this repo provides
| Component | Role |
|-----------|------|
| `src/aes_cipher_top/` | AES benchmark (DEF/SDC/netlist/Bookshelf/CSV) |
| `src/ASAP7/` | 7nm Liberty / LEF / RC |
| `src/openRoad_eval_script/` | **Reproducible OpenROAD eval + adaptive optimizer** |
| `src/python/` | Contest score proxy, placement analysis, future joint-opt scaffold |
| `src/ICCAD_ProbC_ENV/` | CUDA + PyTorch Docker for differentiable backends |
| `src/openroad_docker/` | Project-local OpenROAD Docker launcher |
| `RESULTS.md` | **Recommended deliverable and ranking notes** |
| `report/` / `slides/` | Course report & presentation |

### Recommended deliverable (best result)

**`hybrid_polish` is the best result** (best TNS/WNS among all runs):

`src/openRoad_eval_script/results/aes_cipher_top_hybrid_polish.def`

See [`RESULTS.md`](RESULTS.md) for the full comparison and rationale.

## 3. Quick start (OpenROAD)

> **Project-local Docker:** [`src/openroad_docker/`](src/openroad_docker/)  
> (`./run.sh build` / `./run.sh shell` — mounts `src/` at `/workspace`)

### 3.0 Recommended (environment definition in repo)
```bash
cd src/openroad_docker
# put openroad_*.deb here, enable Docker Desktop WSL integration, then:
./run.sh build && ./run.sh shell
# or reuse old container:
# ./run.sh import-from-container openroad-env
```

### 3.1 Environment (legacy manual container)
Install Docker, create an Ubuntu 22.04 container, install OpenROAD
`openroad_2.0-17598-ga008522d8_amd64-ubuntu-22.04.deb` from
[Precision-Innovations/OpenROAD releases](https://github.com/Precision-Innovations/OpenROAD/releases).

Copy into the container (from `src/`):
```bash
docker cp ./openRoad_eval_script openroad-env:/workspace/
docker cp ./ASAP7 openroad-env:/workspace/
docker cp ./aes_cipher_top openroad-env:/workspace/
docker cp ./python openroad-env:/workspace/
```

### 3.2 Baseline metrics only
```bash
cd /workspace/openRoad_eval_script
openroad -exit eval_def.tcl
```

### 3.3 Adaptive optimization (recommended)
Contest-legal repair flags, strategy selection, legalize, improve placement, power recovery:
```bash
openroad -exit optimize_adaptive.tcl
# or
bash run_experiments.sh          # adaptive
bash run_experiments.sh --all    # sweep size_only / full_buffer / timing_first / adaptive
```

Outputs land in `openRoad_eval_script/results/` (`*.def`, `*_metrics.txt`, `*_summary.txt`, logs).

Forced strategy:
```bash
PROBC_FORCE_STRATEGY=timing_first openroad -exit optimize_adaptive.tcl
# size_only | full_buffer | timing_first | adaptive
```

Dedicated wrappers: `optimize_size_only.tcl`, `optimize_timing_first.tcl`.

### 3.4 Sweep → CSV (completion items 1+2+3)
Records **TNS/WNS/power**, **avg displacement D (µm)**, **runtime**, and builds a comparison table:

```bash
# From host (uses Docker image):
cd src/openroad_docker
./run.sh sweep          # all strategies (long)
./run.sh csv            # rebuild CSV only
./run.sh eval-result aes_cipher_top_timing_first.def

# Or inside container:
cd /workspace/openRoad_eval_script
bash run_experiments.sh --all
bash run_experiments.sh --eval results/aes_cipher_top_timing_first.def
python3 ../python/compare_results.py --results-dir results
```

Artifacts:
- `results/comparison.csv` / `comparison.json`
- `supplements/ICCAD_C_strategy_comparison.csv` (copy)

### 3.4b Hybrid + polish (strengthen)
```bash
cd src/openroad_docker
# Full strengthen (hybrid from scratch + polish winners) — ~30–60 min
./run.sh strengthen

# Or stepwise:
./run.sh hybrid
./run.sh polish aes_cipher_top_full_buffer.def full_buffer_polish
./run.sh polish aes_cipher_top_size_only.def size_only_polish
./run.sh csv
```

New scripts: `optimize_hybrid.tcl`, `optimize_polish.tcl`.

### 3.5 Score / analyze (no OpenROAD required)
```bash
cd src/python
python3 contest_score.py --from-report          # rank report-table strategies by proxy S
python3 compare_results.py                      # table from results/
python3 analyze_placement.py                    # cell mix / sizing headroom
python3 -m framework.smoke_test                 # scaffold unit smoke tests
```

## 4. Method (implemented)
1. **Baseline STA** via placement parasitics.
2. **Policy** from |TNS| / WL pressure → `timing_first` | `adaptive` | `size_only` | `full_buffer`.
3. **Legal moves only**: no pin-swap / gate-cloning / buffer-removal.
4. **Resize-before-buffer** in adaptive mode; buffer percent capped when possible.
5. **Legalize + improve_placement** after disruptive passes.
6. **Power recovery** on positive-slack paths.
7. **Proxy score** aligns local ranking with contest \(S\) (see `contest_score.py --from-report`).

Roadmap scaffold: `src/python/framework/` (window schedule, displacement budget, plug-in STA/size/buffer/relocate backends for INSTA / FusionSizer / RLPlace).

## 5. Directory
```text
.
├── references.bib
├── report/  slides/  supplements/
└── src/
    ├── aes_cipher_top/
    ├── ASAP7/
    ├── ICCAD_ProbC_ENV/
    ├── openRoad_eval_script/
    │   ├── common.tcl
    │   ├── eval_def.tcl
    │   ├── optimize_adaptive.tcl
    │   ├── optimize_size_only.tcl
    │   ├── optimize_timing_first.tcl
    │   ├── run_experiments.sh
    │   └── results/
    └── python/
        ├── contest_score.py
        ├── analyze_placement.py
        └── framework/
```

## 6. Notes
- OpenROAD version changes results; pin the contest/deb version when comparing.
- GUI (optional): VcXsrv on Windows + `openroad -gui`.
- Command reference: `supplements/openroad_commands.txt`.
