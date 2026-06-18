---
name: engine-performance-audit
description: Locate Sanmill engine performance regressions and hotspots by comparing next with ~/Sanmill-master master, using parity checks, compare_engine_perf.py, perf, Criterion, and focused traces.
---

# Engine Performance Audit

## Goal

Find why the Sanmill engine is slower, where time is spent, and which change
can improve it without breaking search parity. Prefer evidence over intuition:
same position, same options, same nodes, measured time, then profiler output.

Use `/home/user/Sanmill` on `next` as the Rust/TGF candidate and
`/home/user/Sanmill-master` on `master` as the legacy C++ reference unless the
user gives different paths.

## Hard rules

1. Prove deterministic parity before interpreting timing.
2. Treat any bestmove, score, depth, root-order, iteration, or node-count
   difference as a correctness problem, not a performance problem.
3. Never compare against stale binaries. Rebuild and record executable paths.
4. Change one variable at a time: build flags, TT size, thread count, depth,
   rule options, and database/book settings must be explicit.
5. Do not casually delete diagnostic code added during an investigation.
   Treat useful probes, scripts, trace commands, and counters as reusable
   project assets for future audits. Keep them only if they are maintainable
   and do not affect formal release performance.
6. Never put profiling overhead in release hot paths. Gate instrumentation
   behind debug/test code, feature flags, CLI diagnostics, scripts, or other
   opt-in paths so normal engine builds remain fast.
7. Preserve monomorphized Rust search paths. Avoid `dyn`, heap allocation, or
   fallback behavior in hot paths unless measurements justify it.
8. Report exact commands and raw artifact paths. Do not claim a universal
   speedup from a single position or noisy run.

## Baseline checklist

Run these first in both repositories:

```bash
git status --short --branch
git rev-parse --show-toplevel
git log -1 --oneline
```

Build candidate:

```bash
cargo build --release -p tgf-cli
ls -l target/release/tgf
file target/release/tgf
```

Build reference:

```bash
bash /home/user/Sanmill-master/scripts/build_console_engine.sh \
  /tmp/sanmill_master_engine_perf
ls -l /tmp/sanmill_master_engine_perf
file /tmp/sanmill_master_engine_perf
```

If symbolized profiling is needed, rebuild a profiling-only binary with debug
symbols and frame pointers. Keep the comparable release binary separate.

Rust:

```bash
RUSTFLAGS="-C force-frame-pointers=yes -C debuginfo=1" \
  cargo build --release -p tgf-cli
```

C++: inspect `scripts/build_console_engine.sh` and add `-g
-fno-omit-frame-pointer` to a temporary profiling build only. Record the exact
command because it is no longer the standard reference build.

## First split: nodes or ns/node

Use `scripts/compare_engine_perf.py` to decide whether the candidate searches
more nodes or spends more time per node.

Shallow deterministic matrix:

```bash
python3 scripts/compare_engine_perf.py \
  --current 'target/release/tgf uci' \
  --master '/tmp/sanmill_master_engine_perf' \
  --current-depth-go 'gomtdf {depth}' \
  --master-depth-go 'gomtdf {depth}' \
  --cases start,placing4,placing8,placing14,moving_entry,moving_loop,capture_pending,reduced_material,flutter_n30_e20_black20 \
  --skills 2,5,15 \
  --depths 1,2 \
  --repeat 3 \
  --timeout 180 \
  --csv /tmp/sanmill_perf_compare.csv
```

For `SkillLevel=1`, the legacy `gomtdf` command does not enter
`SearchEngine::executeSearch()`, so prime the master engine before the measured
fixed-depth probe:

```bash
python3 scripts/compare_engine_perf.py \
  --current 'target/release/tgf uci' \
  --master '/tmp/sanmill_master_engine_perf' \
  --current-depth-go 'gomtdf {depth}' \
  --master-depth-go 'gomtdf {depth}' \
  --master-prime-go go \
  --cases start,placing4,moving_entry,capture_pending \
  --skills 1 \
  --depths 1,2 \
  --repeat 3 \
  --timeout 180 \
  --csv /tmp/sanmill_perf_skill1.csv
```

Interpretation:

- `move/score/nodes` differ: stop and use `refactor-parity-audit`.
- nodes match but Rust is slower: profile Rust for ns/node hotspots.
- nodes differ but move/score match: investigate root order, qsearch, TT, draw
  cuts, and node accounting before optimizing.
- Rust is faster at shallow depth but slower deep: suspect TT, allocation,
  recursion shape, cache behavior, or repetition/history overhead.

## Stable Rust benchmarks

Use these when the issue is in Rust without needing C++ comparison:

```bash
cargo run --release -p tgf-cli -- bench
cargo bench -p tgf-mill
cargo bench -p tgf-mill -- mill_workbench_key_after_place
cargo bench -p tgf-search
```

Compare against `tests/perf_baseline.toml` for hard perft counts and
conservative runtime floors. Criterion output lives under `target/criterion/`.

## perf workflow

Check availability:

```bash
command -v perf
perf --version
cat /proc/sys/kernel/perf_event_paranoid
```

Create a deterministic UCI transcript for one expensive case:

```bash
cat >/tmp/sanmill_perf.uci <<'EOF'
uci
setoption name DeveloperMode value false
setoption name DrawOnHumanExperience value true
setoption name Shuffling value false
setoption name MoveTime value 0
setoption name Algorithm value 2
setoption name UsePerfectDatabase value false
setoption name NMoveRule value 20
setoption name EndgameNMoveRule value 20
setoption name ThreefoldRepetitionRule value true
setoption name SkillLevel value 15
isready
ucinewgame
position startpos moves d6 f4 d2 b4
gomtdf 14
quit
EOF
```

Collect counters:

```bash
perf stat -r 5 -d -- target/release/tgf uci < /tmp/sanmill_perf.uci
perf stat -r 5 -d -- /tmp/sanmill_master_engine_perf < /tmp/sanmill_perf.uci
```

Collect call stacks for one engine at a time:

```bash
perf record -F 997 --call-graph dwarf \
  -o /tmp/sanmill-current.data -- \
  target/release/tgf uci < /tmp/sanmill_perf.uci

perf report --stdio -i /tmp/sanmill-current.data \
  --sort comm,dso,symbol | head -120
```

Use `--call-graph fp` when binaries were built with frame pointers and DWARF
unwinding is too slow or noisy. Use `perf annotate -i <data>` for a single hot
symbol after `perf report` identifies it.

If `perf` is blocked by permissions, request approval for the minimum required
command. If approval is not appropriate, fall back to:

- `cargo flamegraph` if already installed;
- `valgrind --tool=callgrind` for slow but deterministic call counts;
- `heaptrack` or `valgrind --tool=massif` for allocation/memory suspicion;
- `hyperfine` for command-level timing only after parity is locked.

## Hotspot map

Start near the hottest symbol, then map it to the owning layer:

- Search core: `crates/tgf-search/src/searcher/`, especially
  `mod.rs`, `iterative_mtdf.rs`, `move_order.rs`, and `qsearch.rs`.
- Mill move generation and ordering:
  `crates/tgf-mill/src/rules/legal_actions.rs`,
  `crates/tgf-mill/src/rules/game_impls.rs`, and
  `crates/tgf-mill/src/rules/move_priority.rs`.
- Apply/undo and state churn:
  `crates/tgf-mill/src/rules/legal_apply.rs`,
  `crates/tgf-mill/src/rules/transitions.rs`, and `MillWorkbench`.
- Hashing and TT prefetch:
  `crates/tgf-mill/src/rules/zobrist.rs` and
  `crates/tgf-search/src/transposition_table.rs`.
- Evaluation:
  `crates/tgf-mill/src/evaluator.rs` and rule helpers it calls.
- CLI/diagnostic overhead:
  `crates/tgf-cli/src/mill_uci/`.
- Flutter/FRB integration overhead:
  `crates/tgf-frb/src/games/mill/search.rs` and
  `src/ui/flutter_app/lib/games/mill/`.
- Perfect database overhead:
  `crates/perfect-db/` and the C++ shim under `crates/perfect-db/csrc/`.

## Optimization discipline

When a hotspot is identified:

1. Minimize to one command, one position, one depth, one metric.
2. Add or keep a reusable diagnostic if it will prevent future rework.
3. Patch the owning layer, not a wrapper, unless the wrapper is the measured
   bottleneck.
4. Prefer data-layout, allocation removal, cache locality, and branch reduction
   before unsafe code.
5. Use `assert!` for invariants. Do not add fallbacks that mask state bugs.
6. Re-run parity first, then performance. Record before/after nodes and time.
7. If speed improves only by changing node count, prove the new node count is
   still master-equivalent or explain the intentional algorithmic change.

## Report format

Keep the final report short but complete:

```text
Reference: /home/user/Sanmill-master <branch> <sha> <binary>
Candidate: /home/user/Sanmill <branch> <sha> <binary>
Case: <position/options/depth>
Parity: bestmove=<same?> score=<same?> nodes=<same?>
Timing: current=<ms> master=<ms> ratio=<x> ns/node=<values>
Profiler: <top symbols with percentages>
Diagnosis: <single likely bottleneck and evidence>
Change: <patch or proposed patch>
Validation: <commands and results>
Residual risk: <coverage gaps>
```
