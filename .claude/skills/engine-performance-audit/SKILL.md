---
name: engine-performance-audit
description: Locate Sanmill engine performance regressions and hotspots by comparing the next-branch Rust/TGF engine with the legacy master C++ reference, using parity checks, compare_engine_perf.py, profilers (perf on Linux, WPA/flamegraph on Windows), Criterion, and focused traces.
---

# Engine Performance Audit

## Goal

Find why the Sanmill engine is slower, where time is spent, and which change
can improve it without breaking search parity. Prefer evidence over intuition:
same position, same options, same nodes, measured time, then profiler output.

Resolve the three repository roots and per-platform tool names from the
"Repositories, paths, and platform" section below, then reuse the placeholders
(`$NEXT`, `$MASTER`, `$SF`, `$TGF`, `$PY`, `$MASTER_BIN`, `$SCRATCH`) in every
command instead of hardcoding any absolute path.

## Repositories, paths, and platform

This skill compares a Rust/TGF candidate on `next` against a legacy C++
reference on `master`, with Stockfish as a design reference only. Resolve the
three repo roots and tool names once per shell, then reuse the placeholders in
every command below. Replace the example values with the user's actual paths.

| Placeholder   | Meaning                         | Windows (Git Bash)                 | Linux / macOS          |
| ------------- | ------------------------------- | ---------------------------------- | ---------------------- |
| `$NEXT`       | Rust/TGF candidate (`next`)     | `D:/Repo/Sanmill`                  | `~/Sanmill`            |
| `$MASTER`     | Legacy C++ reference (`master`) | `D:/Repo/Sanmill-master/Sanmill`   | `~/Sanmill-master`     |
| `$SF`         | Stockfish design reference      | `D:/Repo/Stockfish`                | `~/Stockfish`          |
| `$TGF`        | Candidate engine binary         | `target/release/tgf.exe`           | `target/release/tgf`   |
| `$PY`         | Python interpreter              | `python`                           | `python3`              |

On Windows the master repo root has a nested `Sanmill` folder
(`D:/Repo/Sanmill-master/Sanmill`), not `D:/Repo/Sanmill-master`. Use
drive-letter forward-slash paths (`D:/Repo/...`) so both Git Bash and native
Python accept the same string; do not use the `/d/Repo/...` MSYS form for
arguments passed to Python scripts.

Set up the environment once per shell. Windows (Git Bash / MSYS2):

```bash
export NEXT="D:/Repo/Sanmill"
export MASTER="D:/Repo/Sanmill-master/Sanmill"
export SF="D:/Repo/Stockfish"
export TGF="target/release/tgf.exe"
export PY="python"
export SCRATCH="$(cygpath -m "$TEMP")/sanmill-perf"
export MASTER_BIN="$SCRATCH/master_engine.exe"
mkdir -p "$SCRATCH"
cd "$NEXT"
```

Linux / macOS:

```bash
export NEXT="$HOME/Sanmill"
export MASTER="$HOME/Sanmill-master"
export SF="$HOME/Stockfish"
export TGF="target/release/tgf"
export PY="python3"
export SCRATCH="${TMPDIR:-/tmp}/sanmill-perf"
export MASTER_BIN="$SCRATCH/master_engine"
mkdir -p "$SCRATCH"
cd "$NEXT"
```

Platform gotchas (verified on the current Windows host):

- The candidate binary is `target/release/tgf.exe` on Windows. Commands and
  `compare_engine_perf.py --current` must use `$TGF`, otherwise the script
  aborts with `current engine not found` because it checks the literal path.
- Use `$PY`. This host has no `python3` alias, only `python`.
- `perf` and `/proc/sys/kernel/perf_event_paranoid` are Linux-only; the whole
  "perf workflow" section does not run on Windows. Use the Windows alternatives
  noted there (Windows Performance Analyzer / ETW, `cargo flamegraph`,
  `hyperfine`); symbols come from the `tgf.pdb` next to `tgf.exe`.
- Keep scratch files under `$SCRATCH` (a real path both Git Bash and native
  Python understand). Do not hardcode `/tmp`: Git Bash `/tmp` and native
  Python's `/tmp` resolve to different locations on Windows.
- Building `$MASTER_BIN` needs MinGW-w64 `g++` on Windows;
  `build_console_engine.sh` autodetects it and emits a `.exe`.

## Hard rules

1. Prove deterministic parity before interpreting timing.
2. Treat any bestmove, score, depth, root-order, iteration, or node-count
   difference as a correctness problem, not a performance problem.
3. Never compare against stale binaries. Rebuild and record executable paths.
4. Change one variable at a time: build flags, TT size, thread count, depth,
   rule options, and database/book settings must be explicit.
5. When using `$MASTER` as the reference, ignore its Qt UI
   code. Compare only the core engine/search/rules code, Flutter-facing engine
   integration, Flutter UI behavior that drives engine calls, and shared build
   tooling needed to reproduce those paths.
6. Do not casually delete diagnostic code added during an investigation.
   Treat useful probes, scripts, trace commands, and counters as reusable
   project assets for future audits. Keep them only if they are maintainable
   and do not affect formal release performance.
7. Never put profiling overhead in release hot paths. Gate instrumentation
   behind debug/test code, feature flags, CLI diagnostics, scripts, or other
   opt-in paths so normal engine builds remain fast.
8. Preserve monomorphized Rust search paths. Avoid `dyn`, heap allocation, or
   fallback behavior in hot paths unless measurements justify it.
9. Report exact commands and raw artifact paths. Do not claim a universal
   speedup from a single position or noisy run.
10. Treat killer-move and history-heuristic searchers as experimental only.
    Before keeping either one, prove that bestmove, score, root order,
    self-play movelist, and node counts remain master-equivalent, then show a
    stable speedup across the standard comparison matrix. Remove or disable
    them when they slow the engine down or only win by changing the tree.

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
ls -l "$TGF"
file "$TGF"
```

Build reference:

```bash
bash "$MASTER/scripts/build_console_engine.sh" "$MASTER_BIN"
ls -l "$MASTER_BIN"
file "$MASTER_BIN"
```

On Windows this requires MinGW-w64 `g++` on `PATH`; the script autodetects it
and writes a `.exe` (so `$MASTER_BIN` already ends in `.exe`).

If symbolized profiling is needed, rebuild a profiling-only binary with debug
symbols and frame pointers. Keep the comparable release binary separate.

Rust:

```bash
env CARGO_TARGET_DIR="$SCRATCH/symbol-release" \
  CARGO_PROFILE_RELEASE_STRIP=false \
  CARGO_PROFILE_RELEASE_DEBUG=1 \
  RUSTFLAGS="-C force-frame-pointers=yes" \
  cargo build --release -p tgf-cli
```

The repository's normal release profile strips symbols on Linux. Do not
overwrite or time the standard `$TGF` when the goal is only to get function
names for `perf`; use the `$SCRATCH/symbol-release` profiling binary for call
stacks and the standard release binary for comparable timings. On Windows this
frame-pointer rebuild is unnecessary: the release `tgf.exe` already ships a
`tgf.pdb` next to it, which WPA/VTune/`cargo flamegraph` consume directly.

C++: inspect `$MASTER/scripts/build_console_engine.sh` and add `-g
-fno-omit-frame-pointer` to a temporary profiling build only. Record the exact
command because it is no longer the standard reference build.

## First split: nodes or ns/node

Use `scripts/compare_engine_perf.py` to decide whether the candidate searches
more nodes or spends more time per node.

Shallow deterministic matrix:

```bash
"$PY" scripts/compare_engine_perf.py \
  --current "$TGF uci" \
  --master "$MASTER_BIN" \
  --current-depth-go 'gomtdf {depth}' \
  --master-depth-go 'gomtdf {depth}' \
  --cases start,placing4,placing8,placing14,moving_entry,moving_loop,capture_pending,reduced_material,flutter_n30_e20_black20 \
  --skills 2,5,15 \
  --depths 1,2 \
  --repeat 3 \
  --timeout 180 \
  --csv "$SCRATCH/sanmill_perf_compare.csv"
```

For `SkillLevel=1`, the legacy `gomtdf` command does not enter
`SearchEngine::executeSearch()`, so prime the master engine before the measured
fixed-depth probe:

```bash
"$PY" scripts/compare_engine_perf.py \
  --current "$TGF uci" \
  --master "$MASTER_BIN" \
  --current-depth-go 'gomtdf {depth}' \
  --master-depth-go 'gomtdf {depth}' \
  --master-prime-go go \
  --cases start,placing4,moving_entry,capture_pending \
  --skills 1 \
  --depths 1,2 \
  --repeat 3 \
  --timeout 180 \
  --csv "$SCRATCH/sanmill_perf_skill1.csv"
```

Interpretation:

- `move/score/nodes` differ: stop and use `refactor-parity-audit`.
- nodes match but Rust is slower: profile Rust for ns/node hotspots.
- nodes differ but move/score match: investigate root order, qsearch, TT, draw
  cuts, and node accounting before optimizing.
- Rust is faster at shallow depth but slower deep: suspect TT, allocation,
  recursion shape, cache behavior, or repetition/history overhead.

## Next-branch performance baseline

Do not judge every optimization only against `$MASTER`.
Master is still the reference for parity and broad context, but it can mislead
when deciding whether a new next-branch change improved or regressed relative
to the previous Rust/TGF implementation.

After a safe optimization is validated, lock a Rust/TGF search baseline in
`tests/search_perf_baseline.toml`. The baseline should record the command,
case names, skill, fixed depth, bestmove, score, node count, median elapsed
time, and run samples. Treat node, score, and bestmove changes as parity
problems unless the algorithmic change was explicitly accepted.

For future optimization candidates, run the same fixed-depth probe and compare
against the locked Rust baseline before making claims about improvement:

```bash
"$PY" scripts/compare_engine_perf.py \
  --current "$TGF uci" \
  --master "$MASTER_BIN" \
  --current-depth-go 'gomtdf {depth}' \
  --master-depth-go 'gomtdf {depth}' \
  --cases start,reduced_material \
  --skills 15 \
  --depths 12 \
  --repeat 3 \
  --timeout 240 \
  --csv "$SCRATCH/sanmill_perf_candidate.csv"

"$PY" scripts/check_search_perf_baseline.py \
  --baseline tests/search_perf_baseline.toml \
  --result "$SCRATCH/sanmill_perf_candidate.csv"
```

Only update `tests/search_perf_baseline.toml` after parity checks pass and the
candidate is intentionally accepted as the new next-branch baseline. Keep the
old CSV path or raw run samples in the baseline notes when useful, but do not
depend on `/tmp` artifacts remaining available.

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

**Linux only.** `perf` does not exist on Windows (verified: not found), and
`/proc/sys/kernel/perf_event_paranoid` is a Linux pseudo-file. On Windows,
profile with Windows Performance Analyzer (WPR/WPA or `xperf`), `cargo
flamegraph` (blondie/ETW backend, run from an elevated shell), or `hyperfine`
for whole-command timing only after parity is locked; symbols come from the
`tgf.pdb` next to `tgf.exe`. The remaining commands in this section assume a
Linux host.

Check availability:

```bash
command -v perf
perf --version
cat /proc/sys/kernel/perf_event_paranoid
```

Create a deterministic UCI transcript for one expensive case:

```bash
cat >"$SCRATCH/sanmill_perf.uci" <<'EOF'
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
perf stat -r 5 -d -- "$TGF" uci < "$SCRATCH/sanmill_perf.uci"
perf stat -r 5 -d -- "$MASTER_BIN" < "$SCRATCH/sanmill_perf.uci"
```

Collect call stacks for one engine at a time:

```bash
perf record -F 997 --call-graph dwarf \
  -o "$SCRATCH/sanmill-current.data" -- \
  "$TGF" uci < "$SCRATCH/sanmill_perf.uci"

perf report --stdio -i "$SCRATCH/sanmill-current.data" \
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
  `crates/tgf-search/src/tt.rs`.
- Evaluation:
  `crates/tgf-mill/src/rules/evaluation.rs` and rule helpers it calls.
- CLI/diagnostic overhead:
  `crates/tgf-cli/src/mill_uci/`.
- Flutter/FRB integration overhead:
  `crates/tgf-frb/src/games/mill/search.rs` and
  `src/ui/flutter_app/lib/games/mill/`.
- Reference-scope guard:
  do not use `$MASTER/src/ui/qt/` or other Qt-only code as
  parity or performance evidence. Use Flutter and core engine paths instead.
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

## StateInfo / undo-stack experiments

When investigating Mill `do_move` / `undo_move` overhead, Stockfish is useful
as a design reference but not as a literal container recipe:

- Stockfish links `StateInfo` objects through `previous` pointers, but those
  objects are owned by a preallocated search stack. Do not model this with
  Rust `std::collections::LinkedList`; pointer chasing and per-node allocation
  would work against the search hot path.
- Legacy Sanmill `Sanmill::Stack<T, 128>` is also a fixed-capacity contiguous
  stack. In Rust, prefer `Vec::with_capacity(128)` plus `assert!` capacity
  checks, `ArrayVec`, or a thin fixed-capacity wrapper over contiguous storage.
- A StateInfo-style refactor only helps if it reduces copied state. Merely
  changing `Vec<MillUndoState>` into a linked structure while copying the same
  `MillState` fields is not an optimization.
- Before reducing copied fields, add or run a test that enumerates legal
  actions from representative positions, applies `do_move`, runs `undo_move`,
  and compares every `MillState` field with the pre-move value.
- Keep complex or uncommon rule paths conservative. It is acceptable for
  standard release rules to use compact deltas while variants such as delayed
  marking, removal-by-mill-count, or custodian/intervention/leap captures fall
  back to full snapshots until they have equally strong coverage.
- After every undo-layout change, run node-count parity first, then self-play
  movelist parity, then performance timing. Do not keep an optimization that
  only wins by changing nodes or move order.

## Performance TODO backlog

Use this backlog before inventing new performance work.  Start with
node-preserving conservative changes, because they can be accepted with the
fixed-position deterministic benchmark when bestmove, score, root order, and
node counts stay identical.  Move to behavior-changing experiments only after
the conservative queue is exhausted or profiling proves the hotspot cannot be
fixed without changing the searched tree.

Two standing rules for this backlog:

- **Follow the profiler, not the queue length.** The measured dominant cost is
  TT `probe_value_bound` / `save` memory traffic in deep moving searches (see
  Current investigation notes). Conservative work that targets TT locality
  (prefetch, page size, per-node slot touches) outranks another
  move-gen/move-order micro-optimization, even though micro-ops are easier to
  land.
- **Evidence bar for rejecting a node-preserving change.** Do not revert a
  parity-preserving change on a <~5% median delta from one or two positions;
  that is inside this harness's noise. A rejection needs the full standard
  matrix (including a deep moving position such as `moving_entry d15`) plus
  instruction / cache-miss counters (`perf stat` on Linux, WPA/ETW on Windows).
  Several past rejections below do not meet this bar and are flagged for re-try.

Reference anchors for future audits:

- Legacy master engine: `$MASTER/src/search.cpp`,
  `search_engine.cpp`, `position.cpp`, `movegen.h`, `movepick.h`, `tt.cpp`,
  `hashmap.h`, `mills.cpp`, and `evaluate.cpp`.
- Stockfish design references: `$SF/src/tt.cpp`,
  `position.cpp`, `movepick.cpp`, `thread.cpp`, and `memory.cpp`.
- Current Rust hot paths: `crates/tgf-search/src/searcher/`,
  `crates/tgf-search/src/thread_pool.rs`,
  `crates/tgf-mill/src/rules/`, and
  `crates/tgf-core/src/action.rs`.

Conservative, node-preserving candidates:

- Compact search-only action representation.  Current `tgf_core::Action` is a
  12-byte `repr(C)` boundary type, while master stores `Move` as a compact
  integer and Stockfish stores moves in dense stack arrays.  Prototype a
  search-only packed Mill action (`u16` or `u32`) or an internal packed action
  list that converts exactly at API boundaries.  Validate with
  `generate_legal_ctx_uses_*`, do/undo field-restore tests, fixed-depth node
  parity, and self-play movelist parity before changing any public FRB shape.
- Group standard undo scalars into a copyable block.  `MillStandardUndo`
  currently restores many scalar fields one by one.  A `Copy` scalar payload
  with explicit layout/size assertions may let Rust lower restore to a block
  copy while keeping `MillBoardUndo` and repetition history separate.  This is
  only safe if every copied field is proven necessary by the existing
  do/undo-all-fields tests; never omit a field just because it looks cold.
- Reduce repetition-history allocation and cloning.  `MillState::key_history`
  and root repetition context still use `Vec<u64>`, while master keeps the
  search path in a fixed `Sanmill::Stack<Position, 128>` and Stockfish owns
  preallocated `StateInfo` objects outside the hot allocation path.  Evaluate a
  bounded inline/ring representation for reversible history, preserving the
  256-entry runtime cap and 24-entry snapshot window exactly.
- [x] Specialize standard Nine Men's Morris move generation and moving
  move-order scoring.  The current Rust code already had `standard_fast_path`,
  cached color bitboards, line masks, and neighbor masks, but perf on
  `capture_pending` depth 18 still showed visible time in
  `generate_move_actions_with_priority`, `MillMoveOrderScorer::score`, and
  generic `order_moves`.

  Done on 2026-06-21: hoisted the standard/diagonal/fly rule-shape branch out
  of the per-piece move-generation loop, then added a standard moving-phase
  batch scorer that lazily caches block scores by destination square.  The
  scorer keeps each action's own-mill test per `from -> to`, but avoids
  repeating opponent block potential and adjacent-opponent popcounts for the
  same `to`.  The first eager 24-node cache attempt hurt short action lists;
  keep the lazy cache shape unless a later profile shows full-board
  precomputation wins on a different CPU.

  Accepted as node-preserving on the Linux/KVM baseline: bestmove, score, and
  node counts stayed identical for `start` depth 12, `reduced_material` depth
  12, `moving_loop` depth 18, and `capture_pending` depth 18.  New locked
  medians in `tests/search_perf_baseline.toml` were `start` 1033.03 ms
  (`5.74%` faster than the pre-change Linux lock), `reduced_material` 935.05
  ms (`0.35%` faster), `moving_loop` 52.86 ms (`2.52%` slower; short/noisy
  137k-node case), and `capture_pending` 1899.53 ms (`3.57%` faster).  Treat
  this as a small conservative win, not as proof that move-order micro-opts
  outrank TT/cache work in deeper moving searches.
- Revisit standard removal checks only if profiling shows remove scoring or
  removal generation above the current TT/movegen/apply hotspots.  The
  2026-06-21 profile had `remove_move_score` around 1.2% self time, so this
  is lower priority than TT layout, action compaction, and apply/undo memory
  traffic.
- Continue converting scans to ordered bit operations.  Master uses `Bitboard`
  plus stable priority lists; Rust should keep emitted order identical while
  replacing repeated full-board scans with masks, `trailing_zeros`, and
  precomputed peer/line masks where the order is provably unchanged.
- [x] Audit master-normalized node numbering for bitboard geometry.  Master
  numbers real board squares as `SQ_8..SQ_31`, starting at the inner 12
  o'clock point and proceeding clockwise by ring.  Rust previously used a
  Flutter-oriented dense order that required mapping tables for legacy square
  conversion and inverted master parity in a move-order branch.  Prototype
  `node = legacy Square - SQ_BEGIN` so all real nodes are still dense
  `0..23` while preserving master's bitboard geometry and parity directly.

  Checked on 2026-06-19: migrated topology, mill lines, priority tables, FEN
  square ordering, Zobrist square ordering, notation lookup, FRB tests, and
  oracle-facing tests to the master-normalized layout.  The fixed-depth
  probes preserved bestmove, score, and node counts for `start` and
  `reduced_material` at skill 15 depth 12 (`5,580,055` and `3,209,969`
  nodes respectively).  Layout-only timing was mixed and should not be cited
  as a speed win by itself.  After adding fixed-width two-line standard mill
  checks and a placing-phase stalemate guard, whole-process `perf stat` on
  the same UCI inputs showed fewer instructions and branches than clean
  `a23638fb9`: `start` about 4.966B vs 5.008B instructions and
  `reduced_material` about 3.765B vs 3.821B instructions.  I-cache and iTLB
  events were still worse than clean HEAD, so perf elapsed time was not a
  reliable acceptance signal for this experiment.
  Search-only fixed-core A/B remained noisy:
  `/tmp/sanmill_node_layout_nopack_affinity_a23638fb9_r9.csv` kept nodes
  identical and showed small median wins (`start` `0.997x`,
  `reduced_material` `0.985x`).  Treat this as a small conservative
  improvement and as an enabling layout/bitboard cleanup, not as a large
  standalone NPS win until a broader same-process benchmark confirms it.

  Rejected during this audit: caching phase/star booleans inside
  `MillMoveOrderScorer`, packed peer/line tables for `formed_mill_bits_at`,
  branchless formed-mill bit synthesis, and splitting evaluator
  standard/diagonal neighbor loops.  Each preserved parity but worsened at
  least one of instructions, cache events, I-cache events, or fixed-position
  timing, so those exact micro-optimizations should not be reintroduced unless
  a later profile changes the cost model.
- Audit `key_after` prefetch quality.  The current Mill override deliberately
  predicts only the cache-line address and skips rare misc/capture-state
  updates.  If TT prefetch becomes useful again, measure whether a slightly
  more accurate but still O(1) key prediction improves TT-cache locality
  without paying a do/undo cost.
- Re-check hot `dyn` use only at runtime boundaries.  `Searcher<G: Game>` is
  already monomorphised; remaining `dyn GameRules`, `dyn BoardTopology`, and
  CLI game registries are boundary/tooling paths.  Do not refactor them unless
  a profile shows they appear under search, FRB search dispatch, or repeated
  engine session creation.
- Measure build-level optimizations separately.  PGO, target CPU flags, LTO,
  or allocator changes can improve throughput, but they are not substitutes
  for algorithmic parity.  Record build flags and keep them out of same-run
  source-level A/B measurements unless the experiment is explicitly about
  release configuration.
- [x] Add a remove-only quiescence generator.  Current Rust qsearch generates the
  complete legal action list and then retains only remove actions.  Legacy
  master asks `MovePicker` for `REMOVE` moves directly.  Add a Mill-specific
  quiescence/remove-only path that emits the same ordered remove actions
  without placing or moving candidates first.  Validate qsearch node parity and
  self-play movelist parity before accepting it.

  Done on 2026-06-19: added `Game::generate_quiescence_ctx` with a conservative
  default fallback that preserves existing games, then overrode it for
  `MillGame` to call `generate_remove_actions` directly when qsearch requests
  `MillActionKind::Remove`.  A Mill test verifies the specialized path emits
  the same remove actions in the same order as filtering `generate_legal_ctx`.
  This should preserve node counts while avoiding place/move generation at
  qsearch nodes.  Revisit if packed search actions or a staged MovePicker are
  introduced, because those may want a more general kind-specific generator.
- [x] Avoid full root-history scans when a boolean is enough.  Search repetition
  checks often need to know whether the current key appears at least once in
  the root history, but the current implementation may count every match.
  Mirror master's end-biased scan style where possible and stop as soon as the
  threshold is met.  Keep threefold adjudication exact when it really needs a
  count of three.

  Done on 2026-06-19: added `Workbench::has_current_repetition` as a fast
  boolean hook and changed search to call it instead of comparing
  `current_repetition_count() >= 1`.  `MillWorkbench` overrides the hook with
  an `any()` scan that stops at the first matching key, while the exact count
  API remains available for diagnostics and tests.  This is a conservative
  per-node hot-path cleanup and should preserve node counts.  Revisit this
  direction only if repetition metadata is later carried directly in reversible
  state updates, which could remove the scan entirely.
- Replace capped `Vec::remove(0)` history aging.  Runtime key history has a
  fixed 256-entry cap and a 24-entry serialized snapshot window, but removing
  the oldest key from a `Vec` shifts the whole tail.  A ring buffer, bounded
  inline queue, or split hot/cold history can preserve external behavior while
  making eviction O(1).
- Reduce `build_workbench` root-history cloning.  FRB and CLI search setup can
  clone repetition history into each workbench.  Measure repeated engine calls
  and consider borrowing, sharing, or fixed-capacity copying only the search
  window that is actually queried during deterministic search.

  Partial cleanup on 2026-06-20: `MillRules::repetition_history_from_snapshots`
  no longer fully decodes every historical snapshot just to test whether the
  serialized repetition window is empty.  It now reads the dedicated payload
  length byte and uses the snapshot Zobrist key directly, falling back to a
  full decode only when it must return the current snapshot's embedded
  key-history window.  This preserves root repetition semantics while reducing
  per-search setup work in FRB/CLI paths that pass a non-empty history stack.
  The larger `root_repetition_history` clone into `MillGame` /
  `MillWorkbench` is still open and should be measured separately.
- Split hot and cold Mill state fields.  Standard search nodes mostly touch
  side-to-move, phase, piece counts, board cells, color bitboards, pending
  removals, rule50, key, and compact repetition data.  Fields such as formed
  mills, preferred remove targets, UI-facing capture metadata, and full
  key-history storage should be reviewed for cold placement so the standard
  undo and state copies carry fewer cache lines.
- Cache a compact standard-rule fast path.  `MillRules` is general and
  variant-rich.  For default Nine Men's Morris, a small immutable fast-path
  descriptor in `MillWorkbench` could avoid repeated option loads and branch
  chains in move generation, mill checks, remove legality, and move-order
  bias.  Keep asserts proving that the fast descriptor matches the full rules.
- [x] Revisit remove-target ordering with bitsets.  Master combines bitboards with
  stable priority lists.  Rust can first compute the legal removal target mask
  and then emit targets by precomputed priority ranks.  This should remove
  repeated legality branches while preserving exact emitted order.

  Checked on 2026-06-19: prototyped a regular-remove `legal_targets` mask and
  a stalemate-adjacency target mask, then emitted removals through the same
  `priority.iter().rev()` loop to preserve order.  The patch kept bestmove,
  score, depth, and node counts unchanged, but same-run release A/B against
  `a23638fb9` was mixed: `start` depth 12 was only 0.989x while
  `reduced_material` depth 12 regressed to 1.037x.  The code change was
  reverted.  Do not reintroduce this exact mask-hoist unless a future profile
  shows regular remove target filtering as a dominant hotspot or a broader
  packed/staged move generator changes the cost model.  Raw rejected CSV:
  `/tmp/sanmill_remove_targets_mask_r7.csv`.
- [x] Cache node-local move-order inputs.  Move scoring repeatedly uses side
  bitboards, opponent bitboards, phase flags, standard-rule flags, and
  occupancy-derived facts.  Measure a small node-local context passed through
  scoring helpers instead of reloading those fields for every action.

  Done on 2026-06-19: added `Game::move_order_scores_ctx` as a batch scoring
  hook with a conservative default that exactly mirrors repeated
  `move_order_bias_ctx` calls.  `MillGame` overrides it with a
  `MillMoveOrderScorer` that caches side/opponent bitboards, piece counts,
  phase/rule flags, and the MCTS flag once per generated move list.  A unit
  test compares every batch score with the single-action scorer and validates
  the `needs_sort` result.  Same-run release A/B against pre-change
  `5164064c1` kept bestmove, score, depth, and node counts unchanged:
  `start` depth 12 improved 1171.73 ms -> 1098.21 ms (0.937x), and
  `reduced_material` depth 12 improved 919.53 ms -> 835.00 ms (0.908x).
  Raw CSV: `/tmp/sanmill_move_order_batch_scores_r7.csv`.  Revisit this
  area when compact search-only actions or a staged MovePicker are introduced,
  because either change may require a different score storage layout.

  Follow-up on 2026-06-19: avoided three per-list `count_ones()` calls in
  the common non-delayed-marking path by reading the already-maintained
  `pieces_on_board` counters when they are invariant-equivalent to
  `by_color_bb.count_ones()`.  Debug assertions guard that invariant, and
  tests were fixed where hand-built fixtures had inconsistent board/count
  data.  A first version showed an apparent remove-root regression; deeper
  analysis found the cause was not the counter fast path but remove-only
  action lists still constructing the full place/move scorer.  The accepted
  patch routes remove-only lists through a lightweight `remove_move_score`
  scorer before building `MillMoveOrderScorer`.  Same-run release A/B against
  the previous local binary kept bestmove, score, depth, and nodes unchanged:
  `start` d8 `0.885x`, `placing4` d8 `0.877x`, `placing8` d8 `0.903x`,
  `placing14` d8 `0.727x`, `reduced_material` d8 `0.954x`; deeper small-case
  checks gave `capture_pending` d12 `0.882x`, `moving_loop` d12 `0.783x`, and
  `moving_entry` d15 `0.996x`.  Raw CSVs:
  `/tmp/sanmill_piece_count_remove_split_matrix_r7.csv`,
  `/tmp/sanmill_piece_count_remove_split_smallcases_d12_r11.csv`, and
  `/tmp/sanmill_piece_count_remove_split_moving_entry_d15_r11.csv`.
  Treat earlier noisy rejected/accepted notes as hypotheses when they lack a
  theory plus counter or profiler evidence; repeat them with deeper probes
  before ruling out theoretically sound optimizations.
- Audit exact standard `key_after` for prefetch only.  Rust currently accepts a
  rough O(1) key prediction because prefetch only needs a likely cache line.
  If prefetch is enabled in benchmarks, compare a standard-only exact child
  key that includes pending-removal and misc-state updates.  Do not use this
  path for correctness; it is a locality experiment only.
- Add TT occupancy and replacement diagnostics.  Stockfish reports hashfull
  and uses age-aware replacement data; master exposes TT hit/miss counters in
  debug builds.  Rust should have cheap optional counters for TT hit, miss,
  overwrite, age skip, and occupancy sampling so future TT experiments are not
  judged only by elapsed time.
- Parallelize large TT clear and pre-touch.  Stockfish clears TT memory with
  worker threads and NUMA-aware chunking.  Rust currently initializes shared TT
  state at session boundaries.  For large hash sizes, measure a parallel clear
  and page pre-touch path; this affects startup and first-search latency rather
  than per-node behavior.
- Compare TT index mapping.  Stockfish uses a high-multiply index to spread
  keys across clusters, while legacy Sanmill and current Rust primarily use
  masked bits.  Treat alternate indexing as diagnostic first, because it can
  change collisions, TT hits, and node counts even when search code is
  otherwise unchanged.  Note the current design uses `cluster_ix = key_sig &
  mask` AND stores `key_sig = key as u32`, so index and signature share the low
  bits: within one bucket only the top `32 - cluster_bits` bits (8 bits at the
  default 24) actually discriminate, i.e. ~1/256 in-bucket false matches.  The
  `tt.rs` comment claiming the 32-bit signature "eliminates the 1/256
  false-positive rate" is therefore overstated (master shares this property).
  An independent index (high bits) + signature (low bits) split is the real
  fix, but it changes collisions/nodes, so re-baseline parity before keeping it.
- Keep thread creation out of repeated UI searches.  Stockfish parks workers
  and reuses per-thread state.  Rust Lazy-SMP currently spawns workers per
  search.  A persistent worker pool can reduce OS calls and preserve cache
  warmth for repeated Flutter engine moves, but it must keep deterministic
  one-thread behavior unchanged and avoid global locks in the node loop.
- [x] Review fixed-depth abort checks.  Master treats `MoveTime=0` as unlimited.
  Rust fixed-depth searches still poll the abort flag periodically, which is
  needed for UI responsiveness but adds a branch and atomic load in benchmark
  runs.  Consider a benchmark-only or engine-option path that proves no abort
  polling is required, while preserving external stop behavior for releases.

  Checked on 2026-06-19: `Searcher` already has `fixed_depth_no_budget` and
  polls the external abort flag only every 1024 nodes in fixed-depth searches
  without node/time limits.  A narrower prototype skipped the extra child-loop
  abort check in that mode while keeping node-entry polling, but same-run
  release A/B against `a23638fb9` regressed `reduced_material` depth 12 to
  1.065x and left `start` effectively flat at 1.006x.  The code change was
  reverted.  Do not weaken abort polling further unless a profile points
  directly at these loop checks or a dedicated benchmark-only mode is accepted.
  Raw rejected CSV: `/tmp/sanmill_abort_between_moves_r7.csv`.
- Replace fallback search/random move paths with surfaced errors where safe.
  Existing FRB fallback logic can hide search failures by running a shallow
  retry or choosing a random move.  For deterministic performance audits this
  must be disabled so regressions fail loudly and movelist comparisons remain
  meaningful.
- [x] Stop early while checking real-play threefold counts.  Production apply
  only needs to know whether the current repetition signature occurs at least
  three times.  Counting every matching key across the full capped history is
  unnecessary once the third match is found.

  Done on 2026-06-20: both `push_key_and_check_threefold` variants now use a
  small `key_occurs_at_least` helper that exits at the threshold.  This is a
  Rust kernel apply-boundary cleanup, not a search-node optimization, and it
  preserves repetition adjudication semantics.  Validated with
  `cargo test -p tgf-mill repetition_history` and
  `cargo test -p tgf-mill threefold`.
- [x] Audit benchmark timing and node accounting before trusting new baselines.
  `tgf bench` must never time multiple searches while reporting only one
  search's nodes.  If a warm-up search is desired, run it before the timer; if
  two measured searches are desired, report the sum of both node counts.  This
  is a measurement fix, not an engine-speed optimization, and should be
  committed separately from search changes.

  Done on 2026-06-19: changed `tgf bench` to run one unmeasured depth-4 warm-up
  search, then rebuild the workbench and time exactly one measured depth-4
  search.  The reported `nps`, `depth10_ms`, and TT hit rate now all come from
  the same measured search.  Added `search_depth = 4` and
  `search_warmup_runs = 1` metadata so future baseline readers know the exact
  harness semantics.  Revisit only if the benchmark corpus is broadened or if
  the legacy `depth10_ms` compatibility field is renamed in a schema update.
- Broaden the fixed-position benchmark corpus.  Stockfish keeps many benchmark
  positions and legacy Sanmill has self-play benchmark scaffolding.  Sanmill's
  Rust benchmark should include representative placing, moving, removal,
  high-mobility, repeated-position, TT-heavy, and near-terminal positions so a
  local win on the start position does not hide regressions elsewhere.
- Expose kind-specific generation through the game trait where it pays off.
  Master uses `generate<PLACE>`, `generate<MOVE>`, `generate<REMOVE>`, and
  `generate<LEGAL>` templates; Rust currently has one `generate_legal_ctx`
  entry point and qsearch filters after the fact.  A conservative trait
  extension can add optional kind-specific generation with a default fallback
  to preserve non-Mill games.
- Prototype a master-style signed packed Mill action internally.  Master
  encodes place/move/remove in a single signed `Move` integer (`remove` is
  negative; from/to occupy byte fields), while Stockfish fits chess moves into
  `u16`.  A Rust search-only `PackedMillAction` can reduce stack pressure in
  move lists and score arrays while preserving the public `Action` ABI at
  FRB/CLI boundaries.
- Precompute standard move-action templates.  Stockfish's SIMD movegen is not
  directly portable to Mill, but its idea of precomputed ordered move payloads
  is useful.  For standard Mill, store ordered move actions per source square
  and filter them with empty-neighbor masks, so generation copies compact
  prebuilt actions instead of rebuilding every `Action` field at each node.
- [x] Cache mill-formation scores by bit masks.  Master repeatedly calls
  `potential_mills_count` during move ordering; Rust already uses line masks,
  but every action still recomputes several facts.  Investigate tables keyed by
  destination, cleared source, side bitboard, and line masks so standard
  scoring becomes a small number of bit operations with comments explaining the
  constants.

  Checked on 2026-06-19: prototyped a standard placing-path table that
  precomputed per-destination own/opponent mill counts once per generated move
  list and then indexed it from `MillMoveOrderScorer`.  The patch preserved
  bestmove, score, depth, and node counts, but same-run release A/B against
  `a23638fb9` regressed both locked cases: `start` depth 12 was 1.040x and
  `reduced_material` depth 12 was 1.038x.  The fixed cost of filling the
  24-entry table outweighed the saved peer-mask scans in the current move
  lists, so the code change was reverted.  Revisit only after packed actions,
  staged generation, or a profile showing move-order mill counting as dominant
  changes this cost model.  Raw rejected CSV:
  `/tmp/sanmill_place_mill_counts_r7.csv`.
- Carry repetition metadata on reversible state updates.  Stockfish computes a
  repetition distance once in `do_move` and then checks `st->repetition`
  cheaply.  Mill cannot copy the chess cuckoo algorithm blindly, but it can
  store exact per-position repetition metadata during reversible transitions so
  search does not rescan root/key history at every node.
- Review topology allocation at engine boundaries.  Current shared topology is
  cached with `OnceLock`, but `MillTopology::new` still builds `Vec` and
  `Vec<Vec<u16>>` shapes.  Keep this out of the node hot path; if repeated
  engine/session construction appears in profiles, replace standard topology
  construction with static arrays and borrowed slices.
- 2026-06-19 partial note: `MillUciCodec` now reuses
  `shared_mill_topology(false)` instead of constructing a fresh owned topology
  for every encode/decode call.  Keep this broader item open because FRB
  topology export and session construction still intentionally build owned
  blobs, and replacing `MillTopology::new` with borrowed static arrays should
  wait for a profile that shows repeated boundary construction as material.
- [x] Add cheap label/square lookup tables for UCI and diagnostics.  `node_from_label`
  and `square_to_node` currently scan tiny arrays, which is not a search-node
  cost but can show up in CLI benchmark harnesses and repeated self-play log
  parsing.  Static tables or generated match arms are acceptable if comments
  keep the legacy square mapping clear.

  Done on 2026-06-19: replaced the 24-node case-insensitive label scan with a
  direct ASCII byte match and replaced the legacy square scan with explicit
  match arms.  This is a boundary/harness cleanup, not a fixed-depth search
  NPS optimization, so no `tests/search_perf_baseline.toml` update is needed.
  Tests covered the existing lowercase mapping, uppercase UCI compatibility,
  and invalid label/square rejection:
  `cargo test -p tgf-mill topology::tests::labels_match_cxx_square_table`,
  `cargo test -p tgf-mill notation::tests`, and
  `cargo clippy -p tgf-mill --all-targets --all-features -- -D warnings`.
- [x] Reduce Flutter AI self-play boundary overhead.  Do not assume a board
  node-numbering change will show up as a large Flutter self-play speedup:
  the production UI path includes FRB stream delivery, best-move mapping,
  session apply, header refresh, animation/event-loop delay, opening-book
  lookup, and logging around each engine move.  Those costs are outside the
  search node loop and can mask small ns/node wins from engine layout work.

  Done on 2026-06-19: `NativeMillGameSession` now remembers the exact
  `GameAction` matched from the legal-action list for the latest search
  result.  If that same object is immediately applied, Dart skips the
  redundant pre-apply `isLegal()` call while still using Rust's checked
  `tgf_kernel_apply` path, so stale or illegal actions are still surfaced.
  The unit test fake port verifies ordinary user actions still call
  `isLegal()` and search-and-apply avoids the second legality query.
  `moveApplied` events also derive `boardLayout` directly from the native
  `tgfPayload` board bytes instead of calling Rust `exportFen()` and slicing
  the first token after every apply.  This keeps recorder metadata intact
  while avoiding an extra FRB call, full FEN serialization, and Dart string
  parsing on every AI self-play move.

  Also gate normal AI/search trace logging behind `EnvironmentConfig.devMode`.
  The default Flutter log level records all messages to console and an in-memory
  buffer, so per-search-event and per-self-play-iteration `logger.i` calls are
  real UI-path work.  Keep warnings and errors outside the gate; only routine
  progress traces should be dev-only.  Revisit this area with a dedicated
  same-process Flutter/FRB self-play benchmark before making claims about
  percentage speedups.
- [x] Reduce opening-book and best-move mapping costs in Flutter AI self-play.
  Do not dismiss this area because pure engine NPS looks stable: Flutter
  AI-vs-AI pays boundary costs once per applied engine move, and those costs
  can hide small search-node wins from board-index or bitboard work.  Keep the
  theoretical model explicit: after the game leaves opening-book coverage,
  exporting FEN and normalising string fields cannot improve move quality; and
  after Rust has already reported a concrete best-move notation, converting the
  full legal-action list to Dart objects just to find one matching string is
  avoidable work.

  Done on 2026-06-19: `MillOpeningBookProvider.lookup` now returns before
  `getFen()` when the session is terminal or not in `placing` phase.  This is
  data-backed: the current 1461 node-id opening-book FEN keys all use phase
  token `p`; delayed-removal entries use action token `r` while staying in
  phase `p`, so they remain eligible.  A regression test uses a counting
  native session to prove moving-phase lookup does not export FEN.

  Done on 2026-06-19: `NativeMillGameSession` maps a Rust bestMove event by
  parsing the single UCI notation from `EngineEvent.reason`, building one
  `TgfAction`/`GameAction`, and asking the live kernel whether that action is
  still legal.  This preserves the stale-search guard but avoids materialising
  and string-scanning the whole legal-action list after every search.  Tests
  keep the two important safety cases covered: two moves can share a
  destination node, and place/move can share a destination in
  `mayMoveInPlacingPhase` variants.  The stale test fixtures were also updated
  from old node ids to the current node-id map (`a1` = 21, `a4` = 22, `a7` =
  23), because old-number assumptions can otherwise hide the real cost model.

  Validated with:
  `flutter test test/games/mill/mill_opening_book_provider_test.dart`,
  `flutter test test/games/mill/native_mill_game_session_test.dart`, and
  `flutter test test/games/mill/native_mill_ai_vs_ai_selfplay_ffi_test.dart`.

  Revisit this area with a dedicated same-process Flutter/FRB self-play
  benchmark before claiming a percentage speedup.  Remaining UI-loop costs:
  header refresh and the deliberate animation or `Duration.zero` yield after
  each move.
- Audit score-width choices in move ordering.  Master ratings fit in small
  signed integers, while Rust currently computes `i32` scores and stores a
  temporary `[i32; 72]` score array beside a 72-action stack list.  A
  Mill-specific packed move list can use a narrower score lane if assertions
  prove no comparison-changing saturation occurs.
- Preserve master-style debug hooks without hot-path branches.  Legacy
  `search.cpp` has many subtree node-count diagnostics that helped isolate
  parity mismatches, but they are hard-coded branches.  Rust diagnostics should
  provide equivalent root/subtree counters behind compile-time or explicit
  debug options so they remain reusable without release overhead.

Bottleneck-aligned conservative candidates added 2026-06-21 (see review):

- Large pages for the 128 MiB TT: tried on Windows in `f439c38c0`
  (`VirtualAlloc(MEM_LARGE_PAGES)`) and reverted in `65999263e`.  Windows large
  pages REQUIRE `SeLockMemoryPrivilege` ("Lock pages in memory"), which ordinary
  users never enable (it needs an admin policy change plus a re-login), so the
  path was dormant for end users (4 KiB fallback = zero benefit) while carrying
  unsafe FFI (token-privilege adjustment, VirtualAlloc/VirtualFree, a backing
  enum).  Default-on prefetch already hides most of the TT miss + TLB latency it
  targeted (the prefetch warms the cache line and its TLB translation), and
  Windows has no privilege-free transparent-huge-page mechanism, so there is no
  way to reach normal users.  Linux still benefits for free via the kept
  `madvise(MADV_HUGEPAGE)` hint in `advise_huge_pages`.  Revisit only if Windows
  gains a privilege-free large-page path, or a privilege-holding benchmark shows
  a real gain ON TOP of prefetch.
- Re-time the noise-rejected node-preserving micro-optimizations.  The
  mill-formation score table, the remove-target bitset ordering, and the
  fixed-depth abort-check trim were each reverted on a <5% delta from `start` +
  `reduced_material` only.  Per the evidence bar above, re-run them on the deep
  moving cases with instruction / cache-miss counters before treating them as
  dead; the harness wall-clock alone did not justify the rejections.
- [x] Per-node repetition path scan: CHECKED 2026-06-21, negligible -- DO NOT
  pursue.  uProf `assess` on a repetition-heavy `moving_loop d24` workload, with
  `path_repeats_since_reset` and `has_current_repetition` FORCED non-inline
  (rebuild verified), attributed ZERO measurable cycles to both: they do not
  appear in the function profile at all, while functions down to 2.5% do, and
  `alpha_beta` stayed ~18% even with the repetition code pulled out of it.  Why
  it is cheap: `do_move` keeps `key_history` unchanged during search (the
  pre-root window is fixed and short, the in-search path is the small
  `repetition_stack`).  Also a landmine: the tempting `step-by-2`
  (even-distance-only) micro-opt is UNSAFE in Mill, because a mill-forming Move
  does not flip side-to-move, so distance parity != side-to-move parity inside a
  reversible window -- it could drop a real repetition and change the move list.
  Real hotspots on that workload instead: move generation + apply/undo
  (`do_move` ~20%, `generate_move_actions_with_priority` ~19%, `undo_move` ~7%,
  `apply_to_state` ~6%, `generate_remove_actions` ~5% => ~57%) and move ordering
  (`MillMoveOrderScorer::score` ~11%, `order_moves` ~8%, `remove_move_score` ~3%
  => ~22%).  Target move generation / apply / move-order scoring next, not
  repetition.
- [x] Snapshot the TT generation per search.  `ClusteredTt::get` /
  `probe_value_bound` / `save` each reloaded `current_age` (a relaxed atomic)
  on every node, yet it is constant during one search.  Cache it in
  `Searcher`, synchronize at root-search start and after Searcher-owned TT age
  bumps, and keep the old uncached `get` path for diagnostics.

  Done on 2026-06-21: added a Searcher-local `tt_age` used by the hot
  `probe_tt` / `save_tt` path.  This preserves SharedTt semantics because
  UCI/FRB either bump before constructing workers or call `clear_tt()` through
  the Searcher, and root-search start also resynchronizes in case an external
  SharedTt bump happened before reuse.  Fixed-position checks preserved
  bestmove, score, and node counts.  Against the previous Linux/KVM lock:
  `start` depth 12 improved 1033.03 ms -> 972.67 ms (`5.84%`),
  `reduced_material` depth 12 improved 935.05 ms -> 866.56 ms (`7.32%`),
  `moving_loop` depth 18 was effectively flat/noisy at 52.86 ms -> 53.33 ms,
  and `capture_pending` depth 18 improved 1899.53 ms -> 1765.44 ms (`7.06%`).
  Treat this as a small node-preserving cleanup, not a replacement for deeper
  TT layout / replacement experiments.

Behavior-changing or high-risk experiments:

- TT cluster and replacement policy.  Stockfish uses 32-byte clusters with
  three entries, relative-age replacement, and low-bit in-cluster signatures;
  the current Rust table uses one packed atomic 8-byte slot per index.  A
  clustered TT may improve hit rate and locality but will change collision
  behavior and likely node counts.  Treat this as a search-behavior experiment:
  report node deltas, score/bestmove changes, TT-hit changes, and self-play or
  head-to-head results.
- TT move ordering.  Master has `TT_MOVE_ENABLE` support but the default build
  leaves it disabled; Stockfish uses `ttMove` as the first staged candidate.
  Enabling a TT move bonus or storing best action in Rust TT may improve node
  count, but it intentionally changes move order.  Gate it behind an option
  until fixed-position reports plus self-play show a stable practical win.
- Staged MovePicker-style generation.  Stockfish emits TT move, captures, good
  quiets, bad captures, and bad quiets lazily.  Mill has fewer moves and a
  different tactical structure, so do not copy the chess staging blindly.
  Prototype only if profiling shows scoring/sorting dominates, and expect node
  counts or move lists to change.
- Killer/history heuristics.  Earlier Rust experiments were not stable wins.
  Revisit only with a clearly isolated profile target and the full aggressive
  validation path: fixed-position behavior report, self-play movelist
  comparison, and head-to-head results.
- Parallel-search and TT contention changes.  Lazy-SMP, shared TT atomics,
  counters, and abort flags can be limited by false sharing or cache-line
  ping-pong.  Any sharding, padding, or relaxed-racy TT write change must be
  measured with multi-thread NPS, CPU utilization, context switches, and
  unchanged single-thread behavior first.
- Aspiration windows and root-window policy.  Rust keeps aspiration disabled by
  default for deterministic parity, while Stockfish depends on carefully tuned
  aspiration behavior.  Enabling it can reduce nodes or hurt stability; judge
  it with head-to-head and self-play, not fixed-node parity alone.
- Lazy-SMP result voting and helper behavior.  Stockfish has mature worker
  coordination and best-thread selection.  Rust currently chooses the helper
  result conservatively.  Any voting, depth preference, or helper-specific
  randomization is a practical-playing-strength experiment and may change the
  principal variation.
- Qsearch TT and static-eval caching.  Stockfish probes TT in qsearch and can
  reuse stored static evaluation.  Legacy Sanmill qsearch does not probe TT, so
  adding this to Rust is not a parity-preserving change.  Treat it as a later
  playing-strength/performance experiment with node deltas, not as a
  conservative speed fix.
- Repetition lookahead pruning.  Stockfish's `upcoming_repetition` uses a
  cuckoo-style mechanism to detect drawing moves before searching them.  Mill
  repetition patterns differ and the existing master engine only checks
  repeated positions after traversal.  Any lookahead repetition pruning changes
  the tree and needs self-play validation.
- Null-move, futility, probcut, LMR, and singular-extension ideas.  Stockfish's
  search contains many chess-tuned pruning rules.  They should not be copied
  into Mill by default.  Record them only as inspiration after conservative
  data-layout and generation work is exhausted, and require head-to-head
  evidence because nodes and movelists will change.

## Current investigation notes

- Sorting: legacy master calls `partial_insertion_sort(moves, endMoves,
  INT_MIN)`, which behaves as a full stable descending insertion sort for the
  generated move list. Rust `order_moves` should preserve stable descending
  order. A safe optimization is to score once and skip insertion sort when the
  generated score sequence is already non-increasing. Do not replace this with
  an unstable sort; equal-score order affects node parity.
- Killer/history ordering: previous experiments were not stable wins. Keep
  them disabled unless a future audit proves unchanged root order, self-play
  movelist, and node counts plus a stable speedup across the standard matrix.
- TT size/locality: shrinking `TGF_TT_CLUSTER_BITS` can make deep
  `moving_entry` much faster, but it changes TT collision behavior and node
  counts. Treat it as a diagnostic for cache locality, not a default release
  fix, unless node-count parity is explicitly re-baselined and accepted.
- TT prefetch (RESOLVED 2026-06-21, now default-on for the CLI engine):
  re-measured on an AMD Ryzen 9 7950X3D (Zen4, 3D V-Cache) under the new
  evidence bar. `all` (full prefetch) is a node-preserving win on every tested
  position vs off — start d12 0.77x, placing8 d12 0.87x, placing14 d12 0.88x,
  capture_pending d12 0.83x, reduced_material d12 0.94x, moving_entry d20 0.85x,
  moving_loop d20 0.88x, flutter_n30_e20_black20 0.95x — with identical
  node/bestmove/score. (placing8 first looked like a 1.07x regression at
  repeat=5; that was noise — at repeat=11 it is a 0.87x win, a live example of
  the evidence bar above.) AMD uProf `assess` confirmed the mechanism: off->all
  raised IPC 1.59->2.39 and cut CYCLES_NOT_IN_HALT ~33% at equal RETIRED_INST,
  i.e. prefetch hides the dominant TT miss latency (helped here by the large
  V-Cache L3). `first` was ~flat. `prefetch_mode_from_env` now returns `all`
  when `TGF_PREFETCH_MODE` is unset; override with `=off` / `=first`. The
  earlier slow-PC "all regresses" note was microarchitecture-specific. STILL
  PENDING: validate on Intel and mobile ARM before enabling prefetch in the
  game-neutral `SearchOptions::default()` and the FRB/Flutter search path,
  which both remain off for now.
- TT allocation/reuse: master owns a process-global TT and `clear()` is a
  fake-clean generation bump. Rust UCI and FRB search paths must reuse
  `SharedTt` across searches and call `clear_tt()` / `bump_age()` before each
  new search. Do not allocate a fresh 16 Mi-slot TT inside every `go`,
  `gomtdf`, or Flutter search request; repeated in-process depth-18 probes
  showed this as high `sys` time rather than a tree-shape issue.
- TT first-touch behavior: `TtStorage::new` already eagerly writes every slot
  at allocation (the `ptr.add(i).write(TtCluster::empty())` loop), so pages are
  physically first-touched once and later searches only `bump_age`. The earlier
  "first search faults on demand-zero pages" hypothesis is therefore already
  handled for the initial allocation; do not re-derive it. The remaining open
  work is (a) parallelizing that first-touch for very large hashes and (b)
  large pages -- Linux gets transparent THP for free via `madvise`, but the
  Windows `VirtualAlloc(MEM_LARGE_PAGES)` path was tried (`f439c38c0`) and
  reverted (`65999263e`): it needs `SeLockMemoryPrivilege` that normal users
  lack (dormant, 4 KiB fallback), so it is not a general Windows win. Validate
  page behavior with
  `perf stat -e page-faults,minor-faults,dTLB-load-misses` (Linux) or WPA/ETW
  memory counters (Windows) on a fresh-process first `gomtdf` probe.
- Measurement caveat: `scripts/compare_engine_perf.py` starts a fresh process
  for each measured run, so it hides benefits that come from reusing process
  state such as TT allocation. Pair it with a same-process repeated-search
  `perf stat` run and inspect user/sys time when auditing allocation fixes.
- Recent prefetch retest after standard apply fast paths: both `first` and
  `all` preserved nodes/bestmove on the tested matrix, but worsened
  `placing8` / `capture_pending` and did not improve `moving_entry d15`.
  Do not enable either mode by default from a single moving-position win.
- Standard Remove fast path experiment: a narrow search-only remove fast path
  preserved node and self-play parity, but did not produce a stable timing win
  and sometimes worsened `moving_entry d15`. Do not keep or reintroduce it
  unless a future profile shows remove apply itself as the dominant bottleneck.
- Standard move-generation branch-hoist experiment: hoisting `can_fly` /
  `has_diagonal_lines` out of the per-piece loop preserved parity but did not
  improve the standard matrix. Avoid making the generator more duplicated for
  that micro-optimization alone.
- Standard mobility-count fast path: direct `state.board` reads for
  non-diagonal, non-marked positions preserve parity and can slightly reduce
  apply/remove overhead. Keep the generic `live_piece` path for delayed-marked
  and diagonal variants.
- Known current hotspots after the safe fast paths: depth-aware TT
  `probe_value_bound` / `save` memory traffic dominates deep moving searches;
  Mill apply, move-order scoring, and move generation are secondary. This
  points to TT/cache layout and compact search-action representation as the
  next major design areas, not to a different sorting algorithm.

## Report format

Keep the final report short but complete:

```text
Reference: $MASTER <branch> <sha> <binary>
Candidate: $NEXT <branch> <sha> <binary>
Case: <position/options/depth>
Parity: bestmove=<same?> score=<same?> nodes=<same?>
Timing: current=<ms> master=<ms> ratio=<x> ns/node=<values>
Profiler: <top symbols with percentages>
Diagnosis: <single likely bottleneck and evidence>
Change: <patch or proposed patch>
Validation: <commands and results>
Residual risk: <coverage gaps>
```
