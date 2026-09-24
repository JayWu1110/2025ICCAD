#!/usr/bin/env python3
"""Contest-aligned score helper for ICCAD 2025 Problem C.

Official score:
    S = 1000 * P - 50 * D - 300 * R
    P = alpha * TNS_norm + beta * POWER_norm + gamma * WL_norm

This module:
  - Normalizes metrics vs a baseline
  - Computes a proxy score for local ranking of strategies
  - Parses OpenROAD metric logs when numeric fields are present

Weights alpha/beta/gamma vary per testcase; defaults match a balanced
aes_cipher_top working set and are overridable via CLI/YAML.
"""

from __future__ import annotations

import argparse
import json
import math
import re
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Optional


@dataclass
class Weights:
    alpha: float = 0.50
    beta: float = 0.25
    gamma: float = 0.25
    # Score formula coefficients from the problem statement
    w_p: float = 1000.0
    w_d: float = 50.0
    w_r: float = 300.0


@dataclass
class Metrics:
    tns: float
    power: float
    hpwl: float
    displacement: float = 0.0
    runtime_s: float = 0.0
    wns: Optional[float] = None
    label: str = ""


def normalize_improve(new: float, base: float, *, lower_is_better: bool) -> float:
    """Map improvement into ~[0, 1+] where larger is better for P.

    For negative TNS (more negative = worse): improvement when |new| < |base|.
    For power/HPWL: improvement when new < base.
    """
    if base == 0:
        return 1.0
    if lower_is_better:
        # 1 means same as base; >1 means better (smaller)
        return float(base / new) if new != 0 else 2.0
    # higher_is_better (unused for TNS magnitude path)
    return float(new / base) if base != 0 else 0.0


def tns_norm(tns_new: float, tns_base: float) -> float:
    """TNS is typically negative; rank by magnitude reduction."""
    mag_b = abs(tns_base)
    mag_n = abs(tns_new)
    if mag_b == 0:
        return 1.0 if mag_n == 0 else 0.0
    # Cap at 2.0 to avoid exploding when nearly fixed
    return min(2.0, mag_b / max(mag_n, 1e-12))


def compute_p(m: Metrics, base: Metrics, w: Weights) -> float:
    tn = tns_norm(m.tns, base.tns)
    pn = normalize_improve(m.power, base.power, lower_is_better=True)
    wn = normalize_improve(m.hpwl, base.hpwl, lower_is_better=True)
    # Clamp power/wl norms into a sane range
    pn = min(max(pn, 0.0), 2.0)
    wn = min(max(wn, 0.0), 2.0)
    return w.alpha * tn + w.beta * pn + w.gamma * wn


def compute_score(m: Metrics, base: Metrics, w: Weights | None = None) -> dict:
    w = w or Weights()
    p = compute_p(m, base, w)
    s = w.w_p * p - w.w_d * m.displacement - w.w_r * (m.runtime_s / 100.0)
    return {
        "label": m.label,
        "P": p,
        "D": m.displacement,
        "R_proxy": m.runtime_s / 100.0,
        "S": s,
        "tns": m.tns,
        "power": m.power,
        "hpwl": m.hpwl,
        "runtime_s": m.runtime_s,
        "tns_improve_pct": (1.0 - abs(m.tns) / abs(base.tns)) * 100.0
        if base.tns != 0
        else 0.0,
    }


_FLOAT = r"([-+]?(?:\d+\.\d*|\d*\.\d+|\d+)(?:[eE][-+]?\d+)?)"


def parse_metrics_file(path: Path) -> dict:
    """Best-effort parse of our metrics logs + free-form OpenROAD dumps."""
    text = path.read_text(errors="ignore")
    out: dict = {"path": str(path), "raw_len": len(text)}

    # Common patterns
    for key, pat in [
        ("tns", rf"(?:tns|TNS)\s*[:=]?\s*{_FLOAT}"),
        ("wns", rf"(?:wns|WNS)\s*[:=]?\s*{_FLOAT}"),
        ("power", rf"(?:Total|total)?\s*power\s*[:=]?\s*{_FLOAT}"),
        ("hpwl", rf"(?:hpwl|HPWL|wire.?length)\s*[:=]?\s*{_FLOAT}"),
        ("runtime", rf"(?:runtime|elapsed)\s*[:=]?\s*{_FLOAT}"),
    ]:
        ms = re.findall(pat, text, flags=re.IGNORECASE)
        if ms:
            try:
                out[key] = float(ms[-1])
            except ValueError:
                pass

    if "selected_strategy" in text:
        m = re.search(r"selected_strategy:\s*(\S+)", text)
        if m:
            out["strategy"] = m.group(1)
    return out


def load_json_metrics(path: Path) -> Metrics:
    data = json.loads(path.read_text())
    return Metrics(**data)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--baseline-tns", type=float, default=-100709.3)
    ap.add_argument("--baseline-power", type=float, default=5.53e-2)
    ap.add_argument("--baseline-hpwl", type=float, default=32394.3)
    ap.add_argument("--metrics", type=Path, help="Single metrics log to parse")
    ap.add_argument("--results-dir", type=Path, help="Directory of *_metrics.txt")
    ap.add_argument("--candidate", type=Path, help="JSON Metrics for candidate")
    ap.add_argument("--alpha", type=float, default=0.50)
    ap.add_argument("--beta", type=float, default=0.25)
    ap.add_argument("--gamma", type=float, default=0.25)
    ap.add_argument(
        "--from-report",
        action="store_true",
        help="Rank strategies using numbers from the course report table",
    )
    args = ap.parse_args()

    w = Weights(alpha=args.alpha, beta=args.beta, gamma=args.gamma)
    base = Metrics(
        tns=args.baseline_tns,
        power=args.baseline_power,
        hpwl=args.baseline_hpwl,
        label="baseline",
    )

    if args.from_report:
        # Numbers from main.tex experimental table (legal rows)
        candidates = [
            Metrics(-15592.41, 5.91e-2, 40027.2, 0.6, 71.237, label="buffer_resize_dp"),
            Metrics(-15946.53, 5.77e-2, 35290.9, 0.3, 121.441, label="resize_only_dp"),
            Metrics(-14786.6, 5.92e-2, 44278.3, 0.8, 79.852, label="dp_buffer_resize_dp"),
            Metrics(-12829.12, 5.75e-2, 34396.8, 0.5, 62.826, label="dp_buf_res_dp_improve"),
        ]
        rows = [compute_score(c, base, w) for c in candidates]
        rows.sort(key=lambda r: r["S"], reverse=True)
        print("Ranked proxy scores (from report table):")
        for i, r in enumerate(rows, 1):
            print(
                f"  {i}. {r['label']:28s}  S={r['S']:.2f}  "
                f"P={r['P']:.3f}  TNS_impr={r['tns_improve_pct']:.1f}%"
            )
        best = rows[0]
        print(f"\nBest proxy: {best['label']} (prefer this legal flow as default seed)")
        return

    if args.candidate:
        m = load_json_metrics(args.candidate)
        print(json.dumps(compute_score(m, base, w), indent=2))
        return

    if args.metrics:
        parsed = parse_metrics_file(args.metrics)
        print(json.dumps(parsed, indent=2))
        if all(k in parsed for k in ("tns", "power", "hpwl")):
            m = Metrics(
                tns=parsed["tns"],
                power=parsed["power"],
                hpwl=parsed["hpwl"],
                runtime_s=float(parsed.get("runtime", 0.0)),
                label=parsed.get("strategy", args.metrics.stem),
            )
            print("--- proxy score ---")
            print(json.dumps(compute_score(m, base, w), indent=2))
        return

    if args.results_dir:
        paths = sorted(args.results_dir.glob("*_metrics.txt"))
        if not paths:
            print(f"No *_metrics.txt under {args.results_dir}")
            return
        for p in paths:
            print(f"\n## {p.name}")
            print(json.dumps(parse_metrics_file(p), indent=2))
        return

    ap.print_help()


if __name__ == "__main__":
    main()
