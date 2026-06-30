#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
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
#
# Exit codes:
#   0 — every populated baseline matched within tolerance (perft exact,
#       runtime metrics within their relative thresholds).
#   1 — at least one populated baseline was violated, or a populated
#       baseline key is missing from the result file.
#
# Behaviour for unpopulated entries:
#   - perft fields with baseline value 0 are reported as
#     [SKIP-perft-not-populated] but DO NOT pass silently in CI:
#     `--require-perft` (default) turns those skips into hard failures so
#     contributors cannot regress while the baseline is empty.  Pass
#     `--no-require-perft` to relax the gate during initial bring-up.

import argparse
import sys

try:
    import tomllib as _tomllib  # Python 3.11+
except ImportError:
    try:
        import tomli as _tomllib  # pip install tomli
    except ImportError:
        print(
            "[check_perf_baseline] ERROR: install tomllib or tomli",
            file=sys.stderr,
        )
        sys.exit(1)

# Runtime metrics are machine-dependent.  When the baseline value is 0 we
# print a [SKIP-baseline-not-populated] message but DO NOT fail CI; this is
# the agreed-upon behaviour until canonical reference hardware records a
# locked value.
THRESHOLDS = {
    "nps": {
        "field": ["baseline", "nps"],
        "max_regress_pct": 5.0,
        "direction": "lower_is_bad",
    },
    "depth10_ms": {
        "field": ["baseline", "depth10_ms"],
        "max_regress_pct": 5.0,
        "direction": "higher_is_bad",
    },
    "tt_hit_rate": {
        "field": ["baseline", "tt", "hit_rate_pct"],
        "max_regress_pp": 1.0,
        "direction": "lower_is_bad",
    },
    "first_move_ms": {
        "field": ["baseline", "startup", "first_move_ms"],
        "max_regress_pct": 10.0,
        "direction": "higher_is_bad",
    },
}

SANITY_FLOORS = {
    "nps": {"min": 100_000},
    "depth10_ms": {"max": 10_000},
    "tt_hit_rate": {"min": 1.0},
}

# Perft node counts are deterministic.  Any populated baseline value must
# be reproduced exactly by the result.  Populated == non-zero (zero
# perft is logically impossible at any depth >= 0).
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
    ap.add_argument("--result", required=True)
    ap.add_argument(
        "--require-perft",
        dest="require_perft",
        action="store_true",
        default=True,
        help=(
            "Fail when a perft baseline is unpopulated (default)."
            " Set --no-require-perft to relax this during bring-up."
        ),
    )
    ap.add_argument(
        "--no-require-perft",
        dest="require_perft",
        action="store_false",
        help="Allow unpopulated perft baselines to pass with a SKIP message.",
    )
    ap.add_argument(
        "--sanity-floor",
        action="store_true",
        help=(
            "When a runtime baseline is 0/missing, still fail obvious "
            "regressions (NPS < 100k, depth10_ms > 10s, TT hit rate < 1%)."
        ),
    )
    args = ap.parse_args()

    with open(args.baseline, "rb") as f:
        baseline = _tomllib.load(f)
    with open(args.result, "rb") as f:
        result = _tomllib.load(f)

    failed = False

    # ---------------------------------------------------------------- perft
    for key_path in PERFT_KEYS:
        key_name = ".".join(key_path)
        bval = get_nested(baseline, key_path)
        rval = get_nested(result, key_path)

        if bval is None or bval == 0:
            tag = "[FAIL-perft-not-populated]" if args.require_perft else (
                "[SKIP-perft-not-populated]"
            )
            print(
                f"{tag} {key_name}: baseline is 0/missing; populate "
                "tests/perf_baseline.toml with the deterministic perft "
                "value (e.g. via `cargo run --release -p tgf-cli -- bench`)."
            )
            if args.require_perft:
                failed = True
            continue

        if rval is None:
            print(
                f"[FAIL-perft-missing] {key_name} not present in result "
                "file; the bench script must always emit perft."
            )
            failed = True
            continue
        if bval != rval:
            print(
                f"[FAIL] PERFT {key_name}: baseline={bval} result={rval} "
                f"(must be exactly equal, diff={rval - bval})"
            )
            failed = True
        else:
            print(f"[PASS] PERFT {key_name}: {bval}")

    # ---------------------------------------------------- runtime thresholds
    for name, spec in THRESHOLDS.items():
        bval = get_nested(baseline, spec["field"])
        rval = get_nested(result, spec["field"])
        if bval is None or bval == 0:
            if args.sanity_floor and name in SANITY_FLOORS:
                if rval is None:
                    print(f"[FAIL-sanity-missing] {name} not in result")
                    failed = True
                    continue
                floor = SANITY_FLOORS[name]
                if "min" in floor and rval < floor["min"]:
                    print(
                        f"[FAIL-sanity-floor] {name}: result={rval} "
                        f"minimum={floor['min']}"
                    )
                    failed = True
                    continue
                if "max" in floor and rval > floor["max"]:
                    print(
                        f"[FAIL-sanity-floor] {name}: result={rval} "
                        f"maximum={floor['max']}"
                    )
                    failed = True
                    continue
                print(
                    f"[PASS-sanity-floor] {name}: result={rval} "
                    "baseline not populated"
                )
                continue
            print(
                f"[SKIP-baseline-not-populated] {name}: baseline is 0; "
                "machine-dependent metric, will be locked from CI artifact "
                "after a canonical reference run."
            )
            continue
        if rval is None:
            print(f"[FAIL-runtime-missing] {name} not in result")
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
        print(
            "\nAll populated baselines met; runtime metrics with empty "
            "baseline were skipped with explicit notice."
        )
        sys.exit(0)


if __name__ == "__main__":
    main()
