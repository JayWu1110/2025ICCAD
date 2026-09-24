#!/usr/bin/env python3
"""Analyze aes_cipher_top placement / cell library mix.

Useful for:
  - understanding sizing headroom (INV/BUF drive-strength distribution)
  - estimating displacement between baseline CSV and an optimized DEF dump
  - feeding future window-based / RL relocators
"""

from __future__ import annotations

import argparse
import csv
import re
from collections import Counter, defaultdict
from pathlib import Path


SIZE_TOKEN = re.compile(
    r"(?P<base>[A-Za-z0-9]+?)(?P<drive>x\d+|xp\d+)?_(?P<lib>ASAP7.*)"
)


def load_cell_info(path: Path) -> list[dict]:
    with path.open(newline="") as f:
        return list(csv.DictReader(f))


def summarize(cells: list[dict]) -> None:
    print(f"cells: {len(cells)}")
    classes = Counter(c["class"] for c in cells)
    print(f"classes: {dict(classes)}")

    drives = Counter()
    vts = Counter()
    bases = Counter()
    for c in cells:
        t = c["type"]
        m = SIZE_TOKEN.search(t)
        if not m:
            bases[t] += 1
            continue
        bases[m.group("base")] += 1
        drives[m.group("drive") or "x?"] += 1
        # VT often encoded as _L / _R / _SL / _SRAM before ASAP7 suffix patterns
        if "_SL" in t:
            vts["SLVT"] += 1
        elif "_L_" in t or t.endswith("_L"):
            vts["LVT"] += 1
        elif "_R" in t:
            vts["RVT"] += 1
        else:
            vts["other"] += 1

    print("top cell bases:")
    for k, v in bases.most_common(15):
        print(f"  {k:20s} {v}")
    print("drive strengths:")
    for k, v in drives.most_common():
        print(f"  {k:8s} {v}")
    print("VT mix (heuristic):")
    for k, v in vts.most_common():
        print(f"  {k:8s} {v}")

    # Bounding box / density proxy
    xs = [float(c["px"]) for c in cells]
    ys = [float(c["py"]) for c in cells]
    print(
        f"bbox: x=[{min(xs):.1f},{max(xs):.1f}] "
        f"y=[{min(ys):.1f},{max(ys):.1f}]"
    )


def avg_manhattan(a: list[dict], b_by_name: dict[str, dict]) -> float:
    total = 0.0
    n = 0
    for c in a:
        name = c["cell"]
        if name not in b_by_name:
            continue
        dx = abs(float(c["px"]) - float(b_by_name[name]["px"]))
        dy = abs(float(c["py"]) - float(b_by_name[name]["py"]))
        total += dx + dy
        n += 1
    return total / n if n else 0.0


def sizing_headroom(cells: list[dict]) -> None:
    """Count how many cells sit at min/max drive — sizing opportunity map."""
    by_base: dict[str, Counter] = defaultdict(Counter)
    for c in cells:
        m = SIZE_TOKEN.search(c["type"])
        if not m:
            continue
        by_base[m.group("base")][m.group("drive") or "x?"] += 1

    print("\nSizing headroom (bases with >=2 drive options present):")
    multi = {b: ctr for b, ctr in by_base.items() if len(ctr) >= 2}
    for b, ctr in sorted(multi.items(), key=lambda kv: -sum(kv[1].values()))[:20]:
        print(f"  {b}: {dict(ctr)}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    root = Path(__file__).resolve().parents[1]
    default_csv = root / "aes_cipher_top" / "aes_cipher_top_cell_info.csv"
    ap.add_argument("--cell-info", type=Path, default=default_csv)
    ap.add_argument(
        "--compare",
        type=Path,
        help="Second cell_info CSV to estimate avg Manhattan displacement",
    )
    args = ap.parse_args()

    cells = load_cell_info(args.cell_info)
    summarize(cells)
    sizing_headroom(cells)

    if args.compare:
        other = load_cell_info(args.compare)
        by = {c["cell"]: c for c in other}
        d = avg_manhattan(cells, by)
        # CSV coordinates appear in design DB units (micron*1000 style);
        # report both raw and /1000 as um guess.
        print(f"\navg Manhattan displacement (raw units): {d:.3f}")
        print(f"avg Manhattan displacement (if /1000 -> um): {d/1000.0:.4f} um")


if __name__ == "__main__":
    main()
