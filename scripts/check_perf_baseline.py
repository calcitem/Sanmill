#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)
#
# scripts/check_perf_baseline.py
#
# Compares a freshly-run benchmark result against the locked baseline in
# tests/perf_baseline.toml and exits non-zero if any threshold is exceeded.
#
# Usage:
#   python3 scripts/check_perf_baseline.py \
#       --baseline tests/perf_baseline.toml \
#       --result   /tmp/bench_result.toml
#
# The --result file has the same TOML schema as the baseline.

import argparse
import sys

try:
    import tomllib  # Python 3.11+
except ImportError:
    try:
        import tomli as tomllib  # pip install tomli
    except ImportError:
        print("[check_perf_baseline] ERROR: install tomllib or tomli", file=sys.stderr)
        sys.exit(1)

THRESHOLDS = {
    "nps":             {"field": ["baseline", "nps"],               "max_regress_pct": 5.0,   "direction": "lower_is_bad"},
    "depth10_ms":      {"field": ["baseline", "depth10_ms"],        "max_regress_pct": 5.0,   "direction": "higher_is_bad"},
    "tt_hit_rate":     {"field": ["baseline", "tt", "hit_rate_pct"],"max_regress_pp":  1.0,   "direction": "lower_is_bad"},
    "first_move_ms":   {"field": ["baseline", "startup", "first_move_ms"], "max_regress_pct": 10.0, "direction": "higher_is_bad"},
}

PERFT_KEYS = [
    ["baseline", "perft", "start_d1"],
    ["baseline", "perft", "start_d2"],
    ["baseline", "perft", "mid_d3"],
]


def get_nested(d, keys):
    for k in keys:
        d = d.get(k, None)
        if d is None:
            return None
    return d


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--baseline", required=True)
    ap.add_argument("--result",   required=True)
    args = ap.parse_args()

    with open(args.baseline, "rb") as f:
        baseline = tomllib.load(f)
    with open(args.result, "rb") as f:
        result = tomllib.load(f)

    failed = False

    # Perft: must be exactly equal (0 tolerance)
    for key_path in PERFT_KEYS:
        key_name = ".".join(key_path)
        bval = get_nested(baseline, key_path)
        rval = get_nested(result, key_path)
        if bval is None or bval == 0:
            continue  # not yet populated
        if rval is None:
            print(f"[MISSING] {key_name} not in result file")
            failed = True
            continue
        if bval != rval:
            print(f"[FAIL] PERFT {key_name}: baseline={bval} result={rval} "
                  f"(must be exactly equal, diff={rval - bval})")
            failed = True
        else:
            print(f"[PASS] PERFT {key_name}: {bval}")

    # Performance metrics: percentage/pp thresholds
    for name, spec in THRESHOLDS.items():
        bval = get_nested(baseline, spec["field"])
        rval = get_nested(result, spec["field"])
        if bval is None or bval == 0:
            continue  # not yet populated
        if rval is None:
            print(f"[MISSING] {name} not in result")
            failed = True
            continue

        direction = spec["direction"]
        if "max_regress_pct" in spec:
            threshold = spec["max_regress_pct"]
            if direction == "lower_is_bad":
                regress = (bval - rval) / bval * 100.0 if bval > 0 else 0
                ok = regress <= threshold
                label = f"drop {regress:.1f}% (limit {threshold}%)"
            else:  # higher_is_bad
                regress = (rval - bval) / bval * 100.0 if bval > 0 else 0
                ok = regress <= threshold
                label = f"increase {regress:.1f}% (limit {threshold}%)"
        else:  # pp threshold for TT hit rate
            threshold = spec["max_regress_pp"]
            regress = bval - rval
            ok = regress <= threshold
            label = f"drop {regress:.2f}pp (limit {threshold}pp)"

        status = "[PASS]" if ok else "[FAIL]"
        print(f"{status} {name}: baseline={bval} result={rval} — {label}")
        if not ok:
            failed = True

    if failed:
        print("\nPerformance regression detected — refusing to merge.")
        sys.exit(1)
    else:
        print("\nAll performance thresholds met.")
        sys.exit(0)


if __name__ == "__main__":
    main()
