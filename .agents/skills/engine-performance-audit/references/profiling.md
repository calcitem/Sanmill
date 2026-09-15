# Profiling Sanmill

Use this reference for measured engine or Flutter/FRB boundary costs.
Resolve the repository, binary, interpreter, and a writable scratch directory
from the current environment. Do not reuse historical host paths as defaults.

## Workload and binary identity

Record the position or replay, rules, algorithm, evaluator, TT settings,
thread count, seed, depth/node/time limits, and database/book configuration.
A CLI benchmark does not measure all Flutter session costs.

Build the candidate with `cargo build --release -p tgf-cli` when needed.
On Windows the binary is normally `target/release/tgf.exe`; elsewhere it is
`target/release/tgf`. Check the actual file. On Windows use paths understood
by both Git Bash and native Python; their interpretations of `/tmp` can
differ. Discover `python` / `python3` instead of assuming a host alias.

Keep a symbolized profiling build separate from the binary used for ordinary
release comparisons. Inspect the Cargo profile and available symbols first.
If additional symbols or frame pointers are needed, a Bash example is:

```bash
env CARGO_TARGET_DIR="$SCRATCH/symbol-release" \
  CARGO_PROFILE_RELEASE_STRIP=false \
  CARGO_PROFILE_RELEASE_DEBUG=1 \
  RUSTFLAGS="-C force-frame-pointers=yes" \
  cargo build --release -p tgf-cli
```

Here `SCRATCH` is an already selected writable scratch directory. Record
these flags; do not mix timings from differently instrumented builds.

## Platform tools

- Linux: `perf stat` for counters, `perf record` / `perf report` for
  call stacks, and `perf annotate` for a measured symbol.
- Windows: available WPR/WPA, ETW, VTune, or AMD uProf tooling. Verify symbol
  availability, session ownership, and any privilege requirement first.
- macOS: available Instruments or platform profiling tools.
- Command-level timing tools and Criterion are useful without system tracing,
  but they do not establish which function consumes time.

For Linux, with `TGF` set to the actual binary and a deterministic
`sanmill_perf.uci` transcript prepared under `SCRATCH`:

```bash
perf stat -r 5 -d -- "$TGF" uci < "$SCRATCH/sanmill_perf.uci"
perf record -F 997 --call-graph dwarf \
  -o "$SCRATCH/sanmill-current.data" -- \
  "$TGF" uci < "$SCRATCH/sanmill_perf.uci"
perf report --stdio -i "$SCRATCH/sanmill-current.data" --sort comm,dso,symbol
```

Use frame-pointer unwinding only with a suitable build. When profiling needs
additional permission, finish available unprivileged checks and prepare the
specific command before requesting the minimum necessary authorization.
Do not change global tracing/security policy to make an optional tool work.
Do not stop or overwrite another user's trace session.

## Locate the owning layer

| Cost | Likely area |
| --- | --- |
| Search, iterations, ordering, qsearch | `crates/tgf-search/src/searcher/` |
| Move generation / priority | `crates/tgf-mill/src/rules/legal_actions.rs`, `game_impls.rs`, `move_priority.rs` |
| Apply / undo / state copying | `crates/tgf-mill/src/rules/legal_apply.rs`, `transitions.rs`, `MillWorkbench` |
| Hashing / TT | `crates/tgf-mill/src/rules/zobrist.rs`, `crates/tgf-search/src/tt.rs` |
| Evaluation | `crates/tgf-mill/src/rules/evaluation.rs` |
| Protocol and benchmark overhead | `crates/tgf-cli/src/mill_uci/` |
| Flutter/FRB session overhead | `crates/tgf-frb/src/games/mill/search.rs`, `src/ui/flutter_app/lib/games/mill/` |
| Perfect database | `crates/perfect-db/`; C++ oracle only when its feature is actually enabled |

Inspect current modules before assuming a historical symbol still exists.

## Measurement boundaries

- `compare_engine_perf.py` starts fresh processes. Pair it with repeated
  same-process searches to assess TT reuse, initialization, and first-touch
  costs.
- Count every measured search's nodes and time consistently; exclude warm-up
  from both or include it in both.
- Use representative placing, moving, capture, repeated-position, and terminal
  workloads where relevant. A small or noisy case does not prove a general win.
- Measure allocations and state copies at the boundary where they occur.
  Do not move history reconstruction into every search node.
- Before reducing undo payloads, compare all state fields after apply/undo on
  representative legal actions, including uncommon variants. A compact
  standard path can coexist with a fully checked general path.
- Preserve cancellation, external-input validation, warnings, and errors in
  production. Optional diagnostic logging must not add release hot-path cost.
