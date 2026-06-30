#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)
#
# Compare compare_engine_perf.py CSV output against tests/search_perf_baseline.toml.

import argparse
import csv
import statistics
import sys
from pathlib import Path

try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        print("[check_search_perf_baseline] ERROR: install tomllib or tomli", file=sys.stderr)
        sys.exit(1)


def key_for(case):
    return (case["name"], int(case["skill"]), int(case["requested_depth"]))


def parse_int_field(row, field):
    value = row.get(field, "")
    if value == "":
        raise ValueError(f"missing {field}")
    return int(value)


def parse_result_rows(path, engine):
    rows_by_key = {}
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            if row.get("engine") != engine:
                continue
            key = (
                row.get("case", ""),
                parse_int_field(row, "skill"),
                parse_int_field(row, "requested_depth"),
            )
            rows_by_key.setdefault(key, []).append(row)
    return rows_by_key


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", default="tests/search_perf_baseline.toml")
    parser.add_argument(
        "--result",
        required=True,
        action="append",
        help=(
            "CSV emitted by compare_engine_perf.py. Pass multiple times when "
            "the baseline combines separately-collected case groups."
        ),
    )
    parser.add_argument("--engine", default="current", help="engine label to compare from the CSV")
    parser.add_argument(
        "--warn-only",
        action="store_true",
        help="print failures but exit zero; useful while calibrating noisy local runs",
    )
    args = parser.parse_args()

    baseline_path = Path(args.baseline)
    result_paths = [Path(path) for path in args.result]
    with baseline_path.open("rb") as handle:
        baseline = tomllib.load(handle)

    thresholds = baseline.get("thresholds", {})
    max_regress_pct = float(thresholds.get("max_elapsed_regress_pct", 8.0))
    result_rows = {}
    for result_path in result_paths:
        for key, rows in parse_result_rows(result_path, args.engine).items():
            result_rows.setdefault(key, []).extend(rows)

    failed = False
    for case in baseline.get("cases", []):
        key = key_for(case)
        rows = result_rows.get(key, [])
        label = f"{key[0]} skill={key[1]} depth={key[2]}"
        if not rows:
            result_list = ", ".join(str(path) for path in result_paths)
            print(f"[FAIL-missing] {label}: no {args.engine} rows in {result_list}")
            failed = True
            continue

        elapsed = [float(row["elapsed_ms"]) for row in rows]
        median_ms = statistics.median(elapsed)
        baseline_ms = float(case["median_ms"])
        limit_ms = baseline_ms * (1.0 + max_regress_pct / 100.0)

        representative = rows[0]
        checks = []
        if thresholds.get("require_bestmove", True):
            checks.append(("bestmove", str(case["bestmove"]), representative.get("bestmove", "")))
        if thresholds.get("require_score", True):
            checks.append(("score", str(case["score"]), representative.get("score", "")))
        if thresholds.get("require_depth", True):
            checks.append(("depth", str(case["depth"]), representative.get("depth", "")))
        if thresholds.get("require_nodes", True):
            checks.append(("nodes", str(case["nodes"]), representative.get("nodes", "")))

        for field, expected, actual in checks:
            if expected != actual:
                print(f"[FAIL-{field}] {label}: baseline={expected} result={actual}")
                failed = True

        regress_pct = ((median_ms - baseline_ms) / baseline_ms) * 100.0
        if median_ms > limit_ms:
            print(
                f"[FAIL-time] {label}: baseline={baseline_ms:.2f}ms "
                f"result={median_ms:.2f}ms increase={regress_pct:.2f}% "
                f"limit={max_regress_pct:.2f}%"
            )
            failed = True
        else:
            status = "faster" if regress_pct < 0.0 else "slower"
            print(
                f"[PASS] {label}: baseline={baseline_ms:.2f}ms "
                f"result={median_ms:.2f}ms {status}={abs(regress_pct):.2f}% "
                f"nodes={representative.get('nodes', '')}"
            )

    if failed and not args.warn_only:
        print("\nSearch performance baseline check failed.")
        return 1
    if failed:
        print("\nSearch performance baseline check failed in warn-only mode.")
    else:
        print("\nSearch performance baseline check passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
