---
name: engine-performance-audit
description: Diagnose Sanmill engine performance regressions, measured hotspots, or deterministic H2H anomalies. Use for those investigations, not routine engine edits or generic UI performance.
---

# Engine Performance Audit

Locate a measured cost or explain an engine anomaly using a reproducible
workload. A read-only audit produces evidence and recommendations; a requested
fix continues through repair and validation within the authorized scope.

## Choose the investigation

| Question | Relevant guidance |
| --- | --- |
| Did a Rust change regress performance? | Compare the candidate with the previous Rust revision or an applicable accepted Rust baseline |
| Which function, allocation, or boundary is expensive? | [Profiling](references/profiling.md) for the current platform and workload |
| Does a port preserve the legacy engine contract? | [Legacy comparison](references/legacy-comparison.md) and declared parity fields |
| Why did deterministic H2H produce an anomaly? | [H2H forensics](references/h2h-forensics.md) |
| Was this specific optimization tried before? | Search [Experiment history](references/experiment-history.md) for the symbol or idea |

Read only the relevant reference. Legacy C++, Stockfish, a full Perfect DB,
and every historical experiment are not prerequisites for ordinary Rust
profiling. Stockfish is a design reference only when a concrete mechanism is
being considered; its chess heuristics are not Mill acceptance criteria.

## Establish a comparable baseline

- Identify candidate and reference by repository root, commit, build flags,
  binary, options, and workload. Branch names do not establish architecture.
  Use a fresh build or verify that an existing binary matches the source.
- Keep the pre-change binary and current measurements separate. Do not
  overwrite unrelated builds, raw evidence, or an approved baseline.
- Align rules, evaluator weights, algorithm, TT capacity and policy, thread
  count, seeds, shuffling, depth or node budget, and book/database use.
  Freeze time-based variability for deterministic comparisons.
- Prefer same-host, interleaved A/B samples with warm-up outside the measured
  interval. Keep nodes and elapsed time from the same measured searches.
- `tests/perf_baseline.toml` contains perft and conservative runtime gates.
  `tests/search_perf_baseline.toml` records a separate dated Rust search
  baseline. Verify its revision, settings, and machine before using its timing;
  do not compare elapsed time across different machines as a regression claim.

Rust benchmark entrypoints from the repository root:

```bash
python scripts/record_rust_perf_baseline.py --release --output target/tgf_perf_result.toml
python scripts/check_perf_baseline.py --baseline tests/perf_baseline.toml --result target/tgf_perf_result.toml
cargo bench -p tgf-mill
cargo bench -p tgf-search
```

Choose the affected benchmark, not all commands by default.
`scripts/compare_engine_perf.py` can compare two explicit UCI commands;
its `--master` argument is a reference label, not a requirement for C++.
Use `--help` / `--list-cases` to select the relevant cases. For Rust on
both sides, each engine command includes `uci`.

## Interpret differences and continue

For a parity-preserving refactor or optimization, unexplained differences in
declared bestmove, score, depth, root order, iterations, or node counts block a
parity or speedup claim. Stop expanding that comparison and isolate the first
divergence; do not end the task at the first mismatch. Use the
[search parity procedure](../refactor-parity-audit/references/search-parity.md)
when detailed traces are needed.

For an explicitly authorized algorithm or evaluator change, different nodes
or moves may be intended. Keep rule/state correctness requirements and report
the behavior, strength, and performance differences against the chosen
baseline. Do not require reverting accepted tuned behavior merely to match a
retired engine, or present statistical H2H agreement as exact equivalence.

When nodes match, investigate elapsed time and ns/node. When they differ,
separate search-tree changes, node accounting, and per-node cost before
claiming an improvement.

## Optimization and evidence

- Start from current profiles and the affected product path. UI/FRB setup,
  book lookup, logging, and session costs can matter even when search NPS is
  stable. Do not use legacy Qt-only behavior as Flutter evidence.
- Change one performance variable at a time. Preserve monomorphized hot paths
  and use the safety and validation constraints in [AGENTS.md](../../../AGENTS.md).
- Keep useful, maintainable diagnostics behind opt-in, debug, or test paths.
  Remove one-off noise; preserve raw traces and reproducible commands.
- Keep an optimization only with sufficient evidence for its claimed benefit.
  A noisy result is inconclusive; it is not proof of a speedup or regression.
  Broaden measurements when necessary for a decision, not indefinitely.
- Killer/history heuristics, pruning, TT policy, and other search-behavior
  experiments need explicit scope and correctness/strength evidence. A
  request for a behavior-preserving speed fix does not authorize enabling them.
- Generating measurements or a candidate baseline is not permission to replace
  an approved shared baseline. Inspect the report, preserve prior evidence,
  and update only within the user's existing authorization.

Report the exact revisions, commands, options, relevant raw artifacts,
diagnosis, changes or recommendations, validation, and remaining uncertainty.
Unavailable profilers or reference data should limit the affected conclusion;
continue independent checks instead of repeatedly asking to proceed.
