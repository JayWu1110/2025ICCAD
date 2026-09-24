#!/usr/bin/env python3
"""Build strategy comparison CSV + proxy scores for ICCAD ProbC results/.

Parses:
  - *_summary.txt / *_metrics.txt written by OpenROAD Tcl flows
  - *_log.txt OpenROAD stdout (TNS/WNS/Power/HPWL fallback)
  - Optional DEF pair for average Manhattan displacement (um)

Usage:
  python3 compare_results.py --results-dir ../openRoad_eval_script/results
  python3 compare_results.py --results-dir ... --ref-def ../aes_cipher_top/aes_cipher_top.def
"""

from __future__ import annotations

import argparse
import csv
import json
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, Optional

# Reuse score helpers
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from contest_score import Metrics, Weights, compute_score  # noqa: E402

_FLOAT = r"([-+]?(?:\d+\.\d*|\d*\.\d+|\d+)(?:[eE][-+]?\d+)?)"


def parse_kv_file(path: Path) -> Dict[str, str]:
    out: Dict[str, str] = {}
    if not path.exists():
        return out
    for line in path.read_text(errors="ignore").splitlines():
        if ":" not in line:
            continue
        k, v = line.split(":", 1)
        out[k.strip()] = v.strip()
    return out


def parse_log_metrics(text: str) -> Dict[str, float]:
    """Pull numbers from OpenROAD logs / METRICS_* lines."""
    out: Dict[str, float] = {}

    def grab(key: str, patterns: list[str]) -> None:
        for pat in patterns:
            ms = re.findall(pat, text, flags=re.IGNORECASE | re.MULTILINE)
            if ms:
                try:
                    out[key] = float(ms[-1])
                    return
                except ValueError:
                    pass

    grab(
        "tns",
        [
            rf"^METRICS_TNS\s+{_FLOAT}",
            rf"^tns\s+{_FLOAT}",
            rf"\btns\b\s*[:=]?\s*{_FLOAT}",
        ],
    )
    grab(
        "wns",
        [
            rf"^METRICS_WNS\s+{_FLOAT}",
            rf"^wns\s+{_FLOAT}",
            rf"\bwns\b\s*[:=]?\s*{_FLOAT}",
        ],
    )
    grab(
        "power",
        [
            rf"^METRICS_POWER\s+{_FLOAT}",
            rf"^Total\s+{_FLOAT}",
            rf"Total\s+Power\s*[:=]?\s*{_FLOAT}",
        ],
    )
    # Prefer design total: 4th field on OpenROAD "Total ... ... ... total" power row
    for m in re.finditer(
        rf"^Total\s+{_FLOAT}\s+{_FLOAT}\s+{_FLOAT}\s+{_FLOAT}",
        text,
        flags=re.MULTILINE,
    ):
        try:
            out["power"] = float(m.group(4))
        except (ValueError, IndexError):
            pass
    for m in re.finditer(rf"^METRICS_POWER\s+(.+)$", text, flags=re.MULTILINE):
        toks = re.findall(_FLOAT, m.group(1))
        if len(toks) >= 4:
            out["power"] = float(toks[3])
    grab(
        "hpwl",
        [
            rf"Legalized HPWL\s*[:=]?\s*{_FLOAT}",
            rf"Original HPWL\s*[:=]?\s*{_FLOAT}",
            rf"\bHPWL\s*[:=]?\s*{_FLOAT}",
        ],
    )
    # Drop nonsensical HPWL parses (e.g. negative from unrelated lines)
    if "hpwl" in out and out["hpwl"] is not None and out["hpwl"] <= 0:
        del out["hpwl"]
    grab(
        "runtime_s",
        [rf"^METRICS_RUNTIME_S\s+{_FLOAT}", rf"runtime_s\s*[:=]\s*{_FLOAT}"],
    )
    grab(
        "displacement_um",
        [rf"^METRICS_DISP_UM\s+{_FLOAT}", rf"displacement_um\s*[:=]\s*{_FLOAT}"],
    )

    # Prefer post_opt block METRICS if both baseline/post present: last wins (OK).
    # Also try tagged post_opt specifically:
    post = re.search(
        rf"==== PPA REPORT \(post_opt\) ====(.*)(?:==== Writing|Done\.|=======)",
        text,
        flags=re.DOTALL,
    )
    if post:
        chunk = post.group(1)
        m = re.search(rf"^METRICS_TNS\s+{_FLOAT}", chunk, re.M)
        if m:
            out["tns"] = float(m.group(1))
        m = re.search(rf"^METRICS_WNS\s+{_FLOAT}", chunk, re.M)
        if m:
            out["wns"] = float(m.group(1))
        m = re.search(rf"^tns\s+{_FLOAT}", chunk, re.M | re.I)
        if m:
            out["tns"] = float(m.group(1))
        m = re.search(rf"^wns\s+{_FLOAT}", chunk, re.M | re.I)
        if m:
            out["wns"] = float(m.group(1))
        m = re.search(
            rf"^\s*Total\s+{_FLOAT}\s+{_FLOAT}\s+{_FLOAT}\s+{_FLOAT}",
            chunk,
            re.M,
        )
        if m:
            out["power"] = float(m.group(4))
        m = re.search(rf"^METRICS_POWER\s+(.+)$", chunk, re.M)
        if m:
            toks = re.findall(_FLOAT, m.group(1))
            if len(toks) >= 4:
                out["power"] = float(toks[3])

    return out


def parse_def_xy(path: Path) -> Dict[str, tuple[float, float]]:
    """Parse COMPONENTS placements from DEF (DBU)."""
    xy: Dict[str, tuple[float, float]] = {}
    if not path.exists():
        return xy
    in_comp = False
    # PLACED ( x y ) or FIXED ( x y )
    place_re = re.compile(
        r"^\s*-?\s*(\S+)\s+\S+.*\b(?:PLACED|FIXED|COVER)\s*\(\s*([-0-9]+)\s+([-0-9]+)\s*\)",
        re.IGNORECASE,
    )
    # Multi-line: name on one line, PLACED on next — handle simple single-line first;
    # also accumulate.
    buf = ""
    for line in path.open(errors="ignore"):
        if line.startswith("COMPONENTS"):
            in_comp = True
            continue
        if in_comp and line.startswith("END COMPONENTS"):
            break
        if not in_comp:
            continue
        buf += " " + line.strip()
        if ";" not in line:
            continue
        m = place_re.search(buf)
        if m:
            xy[m.group(1)] = (float(m.group(2)), float(m.group(3)))
        buf = ""
    return xy


def avg_manhattan_um(
    ref: Dict[str, tuple[float, float]],
    cur: Dict[str, tuple[float, float]],
    dbu_per_um: float = 1000.0,
) -> Optional[float]:
    total = 0.0
    n = 0
    for name, (x0, y0) in ref.items():
        if name not in cur:
            continue
        x1, y1 = cur[name]
        total += abs(x1 - x0) + abs(y1 - y0)
        n += 1
    if n == 0:
        return None
    return (total / n) / dbu_per_um


@dataclass
class Row:
    strategy: str
    tns: Optional[float] = None
    wns: Optional[float] = None
    power: Optional[float] = None
    hpwl: Optional[float] = None
    displacement_um: Optional[float] = None
    runtime_s: Optional[float] = None
    proxy_S: Optional[float] = None
    tns_improve_pct: Optional[float] = None
    def_path: str = ""
    sources: list[str] = field(default_factory=list)


def collect_strategy(results_dir: Path, strategy: str, ref_def: Optional[Path]) -> Row:
    row = Row(strategy=strategy)
    summary = parse_kv_file(results_dir / f"{strategy}_summary.txt")
    metrics = parse_kv_file(results_dir / f"{strategy}_metrics.txt")
    log_path = results_dir / f"{strategy}_log.txt"
    log_m: Dict[str, float] = {}
    if log_path.exists():
        log_m = parse_log_metrics(log_path.read_text(errors="ignore"))
        row.sources.append(log_path.name)

    if summary:
        row.sources.append(f"{strategy}_summary.txt")
    if metrics:
        row.sources.append(f"{strategy}_metrics.txt")

    def fget(*keys: str, power_list: bool = False) -> Optional[float]:
        for src in (summary, metrics):
            for k in keys:
                if k in src and src[k] not in ("", "None"):
                    try:
                        tok = re.findall(_FLOAT, src[k])
                        if not tok:
                            continue
                        # sta::design_power returns a vector; index 3 is total Watts
                        # (internal, switching, leakage, total, ...).
                        if power_list and len(tok) >= 4:
                            return float(tok[3])
                        return float(tok[0])
                    except ValueError:
                        pass
        for k in keys:
            lk = k
            if k.startswith("post_"):
                lk = k[len("post_") :]
            if lk in log_m:
                return log_m[lk]
            if k in log_m:
                return log_m[k]
        return None

    row.tns = fget("post_tns", "tns")
    row.wns = fget("post_wns", "wns")
    row.power = fget("post_power", "power", power_list=True)
    row.hpwl = fget("hpwl")
    row.displacement_um = fget("displacement_um")
    row.runtime_s = fget("runtime_s")
    if "output_def" in summary:
        row.def_path = summary["output_def"]
    elif "output_def" in metrics:
        row.def_path = metrics["output_def"]

    # DEF-based displacement override / fill
    cand = results_dir / f"aes_cipher_top_{strategy}.def"
    if not cand.exists() and row.def_path:
        p = Path(row.def_path)
        cand = p if p.is_absolute() else results_dir / p.name
    if ref_def and ref_def.exists() and cand.exists():
        d = avg_manhattan_um(parse_def_xy(ref_def), parse_def_xy(cand))
        if d is not None:
            row.displacement_um = d
            row.sources.append("def_displacement")
            row.def_path = str(cand)

    if row.hpwl is None and "hpwl" in log_m:
        row.hpwl = log_m["hpwl"]

    return row


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--results-dir",
        type=Path,
        default=Path(__file__).resolve().parents[1]
        / "openRoad_eval_script"
        / "results",
    )
    ap.add_argument(
        "--ref-def",
        type=Path,
        default=Path(__file__).resolve().parents[1]
        / "aes_cipher_top"
        / "aes_cipher_top.def",
        help="Original DEF for displacement D",
    )
    ap.add_argument("--baseline-tns", type=float, default=-100709.3)
    ap.add_argument("--baseline-power", type=float, default=5.53e-2)
    ap.add_argument("--baseline-hpwl", type=float, default=32394.3)
    ap.add_argument("--csv", type=Path, default=None)
    ap.add_argument("--json", type=Path, default=None)
    args = ap.parse_args()

    results_dir = args.results_dir
    results_dir.mkdir(parents=True, exist_ok=True)

    strategies = set()
    for p in results_dir.glob("*_summary.txt"):
        strategies.add(p.name[: -len("_summary.txt")])
    for p in results_dir.glob("*_log.txt"):
        strategies.add(p.name[: -len("_log.txt")])
    for p in results_dir.glob("aes_cipher_top_*.def"):
        strategies.add(p.name[len("aes_cipher_top_") : -len(".def")])
    # Always include baseline if present
    strategies.discard("")
    if not strategies:
        print(f"No results under {results_dir}")
        return

    base = Metrics(
        tns=args.baseline_tns,
        power=args.baseline_power,
        hpwl=args.baseline_hpwl,
        label="baseline",
    )
    w = Weights()

    rows: list[Row] = []
    for s in sorted(strategies):
        row = collect_strategy(results_dir, s, args.ref_def if args.ref_def else None)
        # Score if we have enough
        if row.tns is not None:
            m = Metrics(
                tns=row.tns,
                power=row.power if row.power is not None else args.baseline_power,
                hpwl=row.hpwl if row.hpwl is not None else args.baseline_hpwl,
                displacement=row.displacement_um or 0.0,
                runtime_s=row.runtime_s or 0.0,
                wns=row.wns,
                label=s,
            )
            sc = compute_score(m, base, w)
            row.proxy_S = sc["S"]
            row.tns_improve_pct = sc["tns_improve_pct"]
        rows.append(row)

    rows.sort(key=lambda r: (r.proxy_S is not None, r.proxy_S or -1e99), reverse=True)

    csv_path = args.csv or (results_dir / "comparison.csv")
    fields = [
        "strategy",
        "tns",
        "wns",
        "power",
        "hpwl",
        "displacement_um",
        "runtime_s",
        "tns_improve_pct",
        "proxy_S",
        "def_path",
    ]
    with csv_path.open("w", newline="") as f:
        wr = csv.DictWriter(f, fieldnames=fields)
        wr.writeheader()
        for r in rows:
            wr.writerow({k: getattr(r, k) for k in fields})

    json_path = args.json or (results_dir / "comparison.json")
    json_path.write_text(
        json.dumps([r.__dict__ for r in rows], indent=2, default=str)
    )

    # Also copy to supplements for the course deliverable
    supp = Path(__file__).resolve().parents[2] / "supplements"
    if supp.is_dir():
        dest = supp / "ICCAD_C_strategy_comparison.csv"
        dest.write_text(csv_path.read_text())
        print(f"Also wrote {dest}")

    print(f"Wrote {csv_path}")
    print(f"Wrote {json_path}")
    print()
    print(
        f"{'strategy':18s} {'TNS':>12s} {'WNS':>10s} {'Power':>10s} "
        f"{'HPWL':>10s} {'D_um':>8s} {'R_s':>8s} {'S':>10s}"
    )
    for r in rows:
        print(
            f"{r.strategy:18s} "
            f"{(f'{r.tns:.2f}' if r.tns is not None else '-'):>12s} "
            f"{(f'{r.wns:.2f}' if r.wns is not None else '-'):>10s} "
            f"{(f'{r.power:.3e}' if r.power is not None else '-'):>10s} "
            f"{(f'{r.hpwl:.1f}' if r.hpwl is not None else '-'):>10s} "
            f"{(f'{r.displacement_um:.4f}' if r.displacement_um is not None else '-'):>8s} "
            f"{(f'{r.runtime_s:.1f}' if r.runtime_s is not None else '-'):>8s} "
            f"{(f'{r.proxy_S:.1f}' if r.proxy_S is not None else '-'):>10s}"
        )

    print()
    print(
        "RECOMMENDED DELIVERABLE (best timing PPA): hybrid_polish -> "
        "aes_cipher_top_hybrid_polish.def  (see RESULTS.md; "
        "do not pick polish rows by proxy_S alone)"
    )


if __name__ == "__main__":
    main()
