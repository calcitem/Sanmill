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
5. When using `/home/user/Sanmill-master` as the reference, ignore its Qt UI
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
env CARGO_TARGET_DIR=/tmp/sanmill-symbol-release \
  CARGO_PROFILE_RELEASE_STRIP=false \
  CARGO_PROFILE_RELEASE_DEBUG=1 \
  RUSTFLAGS="-C force-frame-pointers=yes" \
  cargo build --release -p tgf-cli
```

The repository's normal release profile strips symbols. Do not overwrite or
time the standard `target/release/tgf` when the goal is only to get function
names for `perf`; use the `/tmp` profiling binary for call stacks and the
standard release binary for comparable timings.

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

## Next-branch performance baseline

Do not judge every optimization only against `/home/user/Sanmill-master`.
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
python3 scripts/compare_engine_perf.py \
  --current 'target/release/tgf uci' \
  --master '/tmp/sanmill_master_engine_perf' \
  --current-depth-go 'gomtdf {depth}' \
  --master-depth-go 'gomtdf {depth}' \
  --cases start,reduced_material \
  --skills 15 \
  --depths 12 \
  --repeat 3 \
  --timeout 240 \
  --csv /tmp/sanmill_perf_candidate.csv

python3 scripts/check_search_perf_baseline.py \
  --baseline tests/search_perf_baseline.toml \
  --result /tmp/sanmill_perf_candidate.csv
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
  `crates/tgf-search/src/tt.rs`.
- Evaluation:
  `crates/tgf-mill/src/evaluator.rs` and rule helpers it calls.
- CLI/diagnostic overhead:
  `crates/tgf-cli/src/mill_uci/`.
- Flutter/FRB integration overhead:
  `crates/tgf-frb/src/games/mill/search.rs` and
  `src/ui/flutter_app/lib/games/mill/`.
- Reference-scope guard:
  do not use `/home/user/Sanmill-master/src/ui/qt/` or other Qt-only code as
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

Reference anchors for future audits:

- Legacy master engine: `~/Sanmill-master/src/search.cpp`,
  `search_engine.cpp`, `position.cpp`, `movegen.h`, `movepick.h`, `tt.cpp`,
  `hashmap.h`, `mills.cpp`, and `evaluate.cpp`.
- Stockfish design references: `~/Stockfish/src/tt.cpp`,
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
- Specialize standard Nine Men's Morris rule checks.  The current Rust code
  already has `standard_fast_path`, cached color bitboards, line masks, and
  neighbor masks, but many hot helpers still branch through variant options.
  Profile whether a standard-only helper for move generation, removal checks,
  and move-order scoring can remove option loads without duplicating complex
  variant logic.  Keep generic variant paths conservative and covered.
- Continue converting scans to ordered bit operations.  Master uses `Bitboard`
  plus stable priority lists; Rust should keep emitted order identical while
  replacing repeated full-board scans with masks, `trailing_zeros`, and
  precomputed peer/line masks where the order is provably unchanged.
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
- Add a remove-only quiescence generator.  Current Rust qsearch generates the
  complete legal action list and then retains only remove actions.  Legacy
  master asks `MovePicker` for `REMOVE` moves directly.  Add a Mill-specific
  quiescence/remove-only path that emits the same ordered remove actions
  without placing or moving candidates first.  Validate qsearch node parity and
  self-play movelist parity before accepting it.
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
- Revisit remove-target ordering with bitsets.  Master combines bitboards with
  stable priority lists.  Rust can first compute the legal removal target mask
  and then emit targets by precomputed priority ranks.  This should remove
  repeated legality branches while preserving exact emitted order.
- Cache node-local move-order inputs.  Move scoring repeatedly uses side
  bitboards, opponent bitboards, phase flags, standard-rule flags, and
  occupancy-derived facts.  Measure a small node-local context passed through
  scoring helpers instead of reloading those fields for every action.
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
  otherwise unchanged.
- Keep thread creation out of repeated UI searches.  Stockfish parks workers
  and reuses per-thread state.  Rust Lazy-SMP currently spawns workers per
  search.  A persistent worker pool can reduce OS calls and preserve cache
  warmth for repeated Flutter engine moves, but it must keep deterministic
  one-thread behavior unchanged and avoid global locks in the node loop.
- Review fixed-depth abort checks.  Master treats `MoveTime=0` as unlimited.
  Rust fixed-depth searches still poll the abort flag periodically, which is
  needed for UI responsiveness but adds a branch and atomic load in benchmark
  runs.  Consider a benchmark-only or engine-option path that proves no abort
  polling is required, while preserving external stop behavior for releases.
- Replace fallback search/random move paths with surfaced errors where safe.
  Existing FRB fallback logic can hide search failures by running a shallow
  retry or choosing a random move.  For deterministic performance audits this
  must be disabled so regressions fail loudly and movelist comparisons remain
  meaningful.
- Audit benchmark timing and node accounting before trusting new baselines.
  `tgf bench` must never time multiple searches while reporting only one
  search's nodes.  If a warm-up search is desired, run it before the timer; if
  two measured searches are desired, report the sum of both node counts.  This
  is a measurement fix, not an engine-speed optimization, and should be
  committed separately from search changes.
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
- Cache mill-formation scores by bit masks.  Master repeatedly calls
  `potential_mills_count` during move ordering; Rust already uses line masks,
  but every action still recomputes several facts.  Investigate tables keyed by
  destination, cleared source, side bitboard, and line masks so standard
  scoring becomes a small number of bit operations with comments explaining the
  constants.
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
- Add cheap label/square lookup tables for UCI and diagnostics.  `node_from_label`
  and `square_to_node` currently scan tiny arrays, which is not a search-node
  cost but can show up in CLI benchmark harnesses and repeated self-play log
  parsing.  Static tables or generated match arms are acceptable if comments
  keep the legacy square mapping clear.
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
- TT prefetch: `TGF_PREFETCH_MODE=first` can help some moving/capture probes
  without changing nodes, while `all` has shown regressions. Keep prefetch
  default-off until a full matrix proves a stable win.
- TT allocation/reuse: master owns a process-global TT and `clear()` is a
  fake-clean generation bump. Rust UCI and FRB search paths must reuse
  `SharedTt` across searches and call `clear_tt()` / `bump_age()` before each
  new search. Do not allocate a fresh 16 Mi-slot TT inside every `go`,
  `gomtdf`, or Flutter search request; repeated in-process depth-18 probes
  showed this as high `sys` time rather than a tree-shape issue.
- TT first-touch behavior: Rust zeroed allocation may leave TT pages backed by
  demand-zero mappings. The first search can then fault once on probe reads and
  again on save writes. Pre-touch process-global UCI/FRB TT allocations with a
  physical clear, then use fake-clean for later searches. Validate this with
  `perf stat -e page-faults,minor-faults,task-clock` on a fresh-process first
  `gomtdf` probe.
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
