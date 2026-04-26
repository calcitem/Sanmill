#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)
#
# scripts/record_rust_perf_baseline.py
#
# Runs the Rust TGF benchmark command and writes a TOML result compatible with
# tests/perf_baseline.toml and scripts/check_perf_baseline.py.

import argparse
import subprocess
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output",
        default="target/tgf_perf_result.toml",
        help="Path to write perf-baseline-compatible TOML",
    )
    parser.add_argument(
        "--release",
        action="store_true",
        help="Run cargo in release mode",
    )
    args = parser.parse_args()

    repo = Path(__file__).resolve().parents[1]
    output = (repo / args.output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)

    cmd = ["cargo", "run"]
    if args.release:
        cmd.append("--release")
    cmd += ["-p", "tgf-cli", "--", "bench"]

    print(f"[record_rust_perf_baseline] running: {' '.join(cmd)}", file=sys.stderr)
    proc = subprocess.run(
        cmd,
        cwd=repo,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if proc.stderr:
        print(proc.stderr, file=sys.stderr, end="")
    if proc.returncode != 0:
        print(proc.stdout, file=sys.stderr, end="")
        return proc.returncode

    output.write_text(proc.stdout, encoding="utf-8")
    print(f"[record_rust_perf_baseline] wrote {output}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
