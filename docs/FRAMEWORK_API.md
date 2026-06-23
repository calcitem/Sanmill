# TGF Framework API

This document defines the current public contract of TGF
(TabletopGameFramework), the Rust framework used by Sanmill and future
board/tabletop/card games.

It is not a changelog.  It is the API boundary that new game crates should
implement and that Flutter modules should consume.

## Crate layout

```text
crates/
├── tgf-core     # Game-neutral traits and POD types + GameKernel
├── tgf-search   # Generic monomorphised searchers
├── tgf-mill     # Mill game implementation
├── tgf-othello  # Othello pressure-test implementation
├── tgf-frb      # FRB API surface compiled as rust_lib_sanmill
└── tgf-cli      # Rust CLI / benchmark helper
```

`tgf-core` exposes a runtime-polymorphic `GameKernel` that the FRB layer
consumes for typed Dart sessions; the search hot path stays generic via
`Searcher<G: Game>` to keep `dyn` calls out of the inner loop.

`tgf-core` and `tgf-search` must stay game-neutral.  Concrete games live in
separate crates such as `tgf-mill` and `tgf-othello`.

## Core data types

### `Action`

`Action` is a game-neutral POD move/action encoding.

```rust
#[repr(C)]
pub struct Action {
    pub kind_tag: i16,
    pub from_node: i16,
    pub to_node: i16,
    pub aux: i16,
    pub payload_bits: u32,
}
```

Rules:

- `kind_tag` is owned by the concrete game crate.
- `from_node == -1` means no source node, e.g. placing from hand.
- `to_node == -1` means no target node.
- `payload_bits` is game-defined compact data. Keep large per-move payloads in
  game state or a side structure so search actions stay small.
- `Action::NONE` is the only framework-level sentinel.

### `GameStateSnapshot`

`GameStateSnapshot` is the immutable value crossing game/kernel/FRB
boundaries.

```rust
#[repr(C)]
pub struct GameStateSnapshot {
    pub side_to_move: i8,
    pub phase_tag: i16,
    pub move_number: i16,
    pub zobrist_key: u64,
    pub opaque_payload: [u8; 256],
}
```

Rules:

- `side_to_move` uses game-local player indices.  `-1` means no active player.
- `phase_tag` is interpreted by the owning game.
- `opaque_payload` is game-defined and must remain deterministic.
- Public callers must not inspect `opaque_payload` unless the owning game
  documents its layout.

## Topology API

`BoardTopology` is the single source of truth for board geometry.

```rust
pub trait BoardTopology: Send + Sync {
    fn name(&self) -> &str;
    fn node_count(&self) -> u16;
    fn coordinate_of(&self, node: u16) -> UnitPoint;
    fn label_of(&self, node: u16) -> &str;
    fn node_from_label(&self, label: &str) -> Option<u16>;
    fn neighbors(&self, node: u16) -> &[u16];
    fn edges(&self) -> &[Edge];
    fn line_groups(&self) -> &[Vec<u16>];
    fn zones(&self) -> &[Zone];
    fn decorations(&self) -> &[Decoration];
}
```

Rules:

- `neighbors()` is rules-facing adjacency and must match move generation.
- `edges()` is render-facing geometry and may include visual links that are not
  legal move edges, only when documented by the game crate.
- Labels are stable notation labels, e.g. `d7` for Mill.
- Flutter should consume topology through FRB, not duplicate it in Dart.

## Rules API

### `GameRules`

`GameRules` is object-safe and used at runtime boundaries.

```rust
pub trait GameRules: Send + Sync {
    fn game_id(&self) -> &str;
    fn topology(&self) -> &dyn BoardTopology;
    fn initial_state(&self, variant_options: &[u8]) -> GameStateSnapshot;
    fn legal_actions(&self, snap: &GameStateSnapshot, out: &mut ActionList<256>);
    fn is_legal(&self, snap: &GameStateSnapshot, action: Action) -> bool;
    fn apply(&self, snap: &GameStateSnapshot, action: Action) -> GameStateSnapshot;
    fn outcome(&self, snap: &GameStateSnapshot) -> Outcome;
}
```

Rules:

- `legal_actions` must be deterministic for identical snapshots.
- `apply` may assume `action` was legal and should assert in debug builds if it
  is malformed.
- Implementations must not use global mutable rule state.

### `Game`, `Workbench`, `Evaluator`

These traits are the hot-path compile-time API used by search.

```rust
pub trait Workbench: Sized {
    fn snapshot(&self) -> GameStateSnapshot;
    fn key(&self) -> u64;
    fn side_to_move(&self) -> i8;
    fn is_terminal(&self) -> bool;
    fn do_move(&mut self, a: Action);
    fn undo_move(&mut self);
}

pub trait Evaluator<W: Workbench> {
    fn score(wb: &W) -> i32;
}

pub trait Game: 'static + Send + Sync {
    type Workbench: Workbench;
    type Evaluator: Evaluator<Self::Workbench>;
    fn build_workbench(&self, snap: &GameStateSnapshot) -> Self::Workbench;
    fn generate_legal(wb: &Self::Workbench, out: &mut ActionList<256>);
}
```

Rules:

- Search code must use `Searcher<G: Game>`, not `dyn GameRules`.
- `do_move`, `undo_move`, `generate_legal`, and evaluator calls are hot-path
  functions and should be inlinable.
- If a move keeps the same side to move, search must not negate the recursive
  result.  `Searcher` already enforces this by comparing `side_to_move` before
  and after `do_move`.

## Search API

`tgf-search` currently provides:

- `Searcher<G: Game>`
- `alpha_beta`
- `search_pvs`
- `mtdf`
- `iterative_deepening`
- `qsearch`
- `random_search`
- `perft`
- `MctsSearcher<G: Game>`

The current implementation includes:

- side-aware score polarity
- TT exact/lower/upper bound handling
- TT best-move ordering
- packed two-slot TT clusters (`AtomicU64` slots) sharable across threads
  via `SharedTt` and the `lazy_smp_search` helper
- `SearchThreadPool` (`std::thread` workers + `crossbeam_channel` dispatch)
  used by lazy SMP worker fan-out
- game-specific terminal scoring for rule draws / wins
- node and wall-clock abort checks
- deterministic random search seed
- FRB search event stream
- UCT-style MCTS tree with atomic visit / win counters (`AtomicU32` /
  `AtomicI64`) ready for shared-visits workers

### Benchmarks and gating

`crates/tgf-search/benches/searcher.rs` covers:

- `mill_search_depth_1` / `mill_search_depth_2`
- `mill_pvs_depth_3`
- `mill_perft_depth_2` / `mill_perft_mid_depth_3`
- `mill_iterative_deepening_depth_3`
- `mill_lazy_smp_2_workers_depth_2` (two workers, shared TT)

`cargo run --release -p tgf-cli -- bench` emits a TOML block compatible with
`tests/perf_baseline.toml`.  The deterministic perft fields
(`baseline.perft.start_d1`, `start_d2`, `mid_d3`) are HARD-GATED by
`scripts/check_perf_baseline.py --require-perft`.  Runtime metrics
(`nps`, `depth10_ms`, `tt.hit_rate_pct`, `startup.first_move_ms`) are locked
at conservative absolute floors (`nps >= 500_000`, `depth10_ms <= 100`,
`tt.hit_rate_pct >= 50`, `first_move_ms <= 200`) so the relative regression
thresholds (5 % / 5 % / 1 pp / 10 %) become active.  CI also passes
`--sanity-floor` to keep an absolute lower bound (`nps >= 100_000`,
`depth10_ms <= 10_000`, `tt_hit_rate >= 1`) in place — these two layers are
complementary.  Tighten the runtime baselines toward ~70 % of the canonical
CI run once a stable reference hardware target is selected.

#### Search optimization A/B measurements

Search hot-path optimization claims are measured with
`scripts/compare_engine_perf.py`, not with a self-play match or a UI timer. The
script drives two UCI-compatible engine commands through the same fixed
positions, options, skill level, and fixed-depth `gomtdf` command, then records
wall-clock time plus the engine-reported `bestmove`, `score`, `depth`, and
`nodes`.

The diagnostic harness intentionally removes sources of search nondeterminism
and time-management noise before comparing elapsed time:

- `Shuffling=false` disables randomized move ordering.
- `MoveTime=0` means "no movetime limit" for these fixed-depth probes.
- `UsePerfectDatabase=false` keeps database I/O and lookup policy out of the
  search timing.
- `Algorithm=2` selects the same MTD(f)-style search path used by the
  fixed-depth `gomtdf` command.
- `NMoveRule=20`, `EndgameNMoveRule=20`, and
  `ThreefoldRepetitionRule=true` keep the diagnostic positions bounded and
  aligned with the current Rust baseline unless a case explicitly overrides
  them.

For next-branch optimization work, the comparison target should usually be the
previous locked Rust binary rather than only `~/Sanmill-master`. Comparing only
against the retired master branch can hide regressions between two recent Rust
revisions. A typical local run is:

```bash
cargo build --release -p tgf-cli
cp target/release/tgf /tmp/sanmill_before_candidate_tgf

# Apply and rebuild the candidate change, then run:
python3 scripts/compare_engine_perf.py \
  --current 'target/release/tgf uci' \
  --master '/tmp/sanmill_before_candidate_tgf uci' \
  --current-depth-go 'gomtdf {depth}' \
  --master-depth-go 'gomtdf {depth}' \
  --cases start,reduced_material \
  --skills 15 \
  --depths 12 \
  --repeat 11 \
  --timeout 240 \
  --csv /tmp/sanmill_candidate_r11.csv
```

The `--master` label is historical: in this workflow it often points at the
previous Rust binary. The candidate is accepted only when `bestmove`, `score`,
`depth`, and especially `nodes` are identical for every compared case. Timing
is summarized by the median of the candidate rows because individual runs are
noisy on a multitasking desktop. The reported ratio is:

```text
candidate median elapsed_ms / previous-baseline median elapsed_ms
```

So `0.840x` means the candidate used 84.0% of the previous elapsed time on the
same fixed node count. The current locked search baseline lives in
`tests/search_perf_baseline.toml`; validate a new CSV against it with:

```bash
python3 scripts/check_search_perf_baseline.py \
  --baseline tests/search_perf_baseline.toml \
  --result /tmp/sanmill_candidate_r11.csv
```

The locked baseline stores the exact command, platform, raw per-run timings,
median milliseconds, ns/node, best move, score, depth, and node count. Raw CSV
files are diagnostic artifacts and are not committed; the TOML baseline is the
reviewable record.

This fixed-node-count workflow is for conservative optimizations: data layout,
allocation alignment, undo representation, cache locality, and other changes
that should not alter search decisions. For those changes, identical node
counts are a safety invariant, not a nice-to-have. If the node count changes,
the optimization is no longer being measured as a pure speedup and must be
investigated before accepting the timing result.

More aggressive search changes are evaluated differently. Examples include new
move ordering heuristics, TT move bonuses, pruning changes, extensions,
probabilistic search behavior, or anything that intentionally changes the
visited tree. These changes may legitimately alter node counts and move lists,
so fixed-depth elapsed-time ratios alone are insufficient. For such changes:

- Keep the deterministic fixed-position report, but treat changed nodes,
  scores, or best moves as behavior changes that need explanation.
- Run the ignored self-play parity tests for the affected skill levels, for
  example:

  ```bash
  cargo test -p tgf-mill --test ai_selfplay_master_parity \
    faithful_selfplay_skill2_movelist -- --ignored --exact
  ```

- Compare old and new binaries with self-play or head-to-head harnesses
  (`crates/tgf-mill/tests/ai_selfplay_master_parity.rs`,
  `crates/tgf-cli/tests/head_to_head.rs`, or `scripts/run_head_to_head.sh`)
  before claiming playing-strength or practical speed improvements.
- Report both speed and behavior: elapsed time, NPS or ns/node when useful,
  node-count deltas, move-list changes, score changes, and match/self-play
  results.

### Regression and differential testing

The retired C++ engine is no longer linked into the app or FRB test surface.
Rust/TGF regression coverage now comes from focused Mill rule tests, fixed
search-position tests, self-play/head-to-head harnesses, and legacy oracle
snapshots under `crates/tgf-mill/testdata/legacy_oracle/`.

For broad rule-path coverage, run the Mill rule/action agreement walk and
the FRB oracle replay suite:

```bash
cargo test -p tgf-mill \
    mill_rules_and_game_agree_on_legal_actions_along_random_walk
cargo test -p rust_lib_sanmill oracle_replay
```

Use `scripts/run_head_to_head.sh` for strength and parity checks against a
separately built master-reference engine.  That harness treats the Rust rules
crate as the referee and should not be confused with an in-app C++ bridge.

### Current gaps

- MCTS alpha-beta assisted simulation remains an optional search improvement.
- Perfect database probing is available through the Rust `perfect-db` wrapper
  around the vendored database code, not through the removed legacy engine.

## Search tuning (Rust `tgf-search` / `tgf-cli`)

- **TT size:** `tgf_cli`’s `bench` and UCI `go` path use
  `Searcher::new_with_tt_cluster_bits` driven by the environment variable
  `TGF_TT_CLUSTER_BITS` (clamped 10–26, default 24).  The TOML block printed by
  `cargo run -p tgf-cli -- bench` includes the effective value under `[meta]`.
- **Move order:** `Game::move_order_bias` (default `0`) is added to the
  internal move score.  Mill implements the C++ `RATING_STAR_SQUARE` / star-node
  heuristic from `src/movepick.cpp` for early Black placing positions.

## FRB API boundary

The Flutter-facing Rust library is the `tgf-frb` crate, whose Cargo package and
library target are named `rust_lib_sanmill` to match the generated Flutter FFI
plugin.

### Typed kernel session API (preferred)

Backed by `tgf_core::GameKernel` (see `crates/tgf-core/src/kernel.rs`), the
Dart side gets a long-lived session keyed by an `int` handle:

- `tgfKernelCreate({String gameId})` — `mill` or `othello`, default options.
- `tgfKernelCreateMill({MillVariantOptions variant})` — explicit Mill variant.
- `tgfKernelDispose({int handle})` — drop the Rust session.
- `tgfKernelSnapshot / Outcome / GameId / IsTerminal / UndoDepth / RedoDepth`
- `tgfKernelLegalActions / Apply / Undo / Redo`
- `tgfKernelMillSearchEvents({handle, depth})` — Mill-only PVS stream over the
  kernel’s **current** snapshot; uses the same `MillVariantOptions` stored when
  creating the session (`tgf_kernel_create_mill` / default nine-piece factory).

#### Setup-position editing API

The kernel exposes a direct board-editing flow for the setup-position game mode:

- `tgfKernelSetupClear({handle})` — reset board to empty placing-phase state.
- `tgfKernelSetupSetPiece({handle, node, owner})` — place or clear one piece
  (`owner`: 1 = White, 2 = Black, other = clear).
- `tgfKernelSetupSetSide({handle, side})` — set the side to move (`0` = White).
- `tgfKernelSetupFinish({handle})` — commit the edited board and transition to a
  playable state (Placing or Moving based on `pieces_in_hand`).

**Design note — no Action tri-state:** The legacy C++/Dart `Action` enum
(`place / select / remove`) is intentionally **absent** from the native setup
API.  In the legacy UI, the user selected which piece-type to drag and the
`Action` field tracked that selection.  In the native session, the board editor
cycles the owner value on each tap via `setup_set_piece(node, owner)` — one
call covers all edit intents.  There is no `tgfKernelSetupSetAction` function
and none is planned.

#### FEN import / export API

- `tgfKernelSetFromFen({handle, fen})` — load a Mill FEN string.  New FENs
  carry the `ids:nodes` marker and encode square-like numeric fields as direct
  engine node ids.  Legacy square-id FENs without the marker are still accepted
  at import boundaries.
- `tgfKernelExportFen({handle})` — serialize current kernel state as a Mill FEN
  string in the node-id dialect.  Round-trip guarantee:
  `setFromFen(exportFen(s))` reproduces the same board, side, phase, piece
  counts, remove state, and formed-mill bitmasks.
- Use `scripts/convert_mill_fen_ids.py --write <path>...` for one-shot
  migration of legacy FEN strings in opening books, puzzle data, tests, or
  docs.  The script preserves the historical legacy-oracle snapshots by
  default.

The Dart wrapper that hides FFI details is
`lib/game_platform/engine/tgf_kernel.dart::TgfKernel`.  It also produces
framework-level `GameStateSnapshot` / `GameOutcome` values directly.

`OthelloGameSession` is the first non-Mill session driven entirely by this
typed API; future games should follow the same pattern.

### Smoke surfaces

These remain available for diagnostics and development:

- `kernelTopology()` for Mill geometry
- `nativeMill*` / `nativeOthello*` smoke helpers
- `nativeMillSearchEvents(depth)` stream (start-position smoke; prefer
  `tgfKernelMillSearchEvents` when a typed Mill kernel handle exists)
- `nativeMillSearchStop()` cancellation request

Generated Dart files under `lib/src/rust/frb_generated*.dart` are committed and
must be regenerated after every FRB API change (`flutter_rust_bridge_codegen
generate`).

## Flutter module contract

A Flutter game module should implement `GameModule` without importing Mill
legacy services unless it is the Mill module itself.

A game module should provide:

- `metadata`
- `features`
- `boardGeometry`
- `persistenceScope`
- `startSession()`
- optionally `rulesPort`, `enginePort`, `notationPort`, `ruleSettingsPort`

`OthelloGameModule` is the current non-Mill pressure test.  It validates that a
new game can be registered without changing `game_platform`.


## Adding a new game

To add a deterministic perfect-information game:

1. Create `crates/tgf-<id>`.
2. Implement `BoardTopology` if the game has a board geometry.
3. Implement `GameRules` for runtime boundary use.
4. Implement `Game`, `Workbench`, and `Evaluator` for search.
5. Add Rust tests for `legal_actions`, `apply`, `perft`, and search smoke.
   End-to-end search regression tests against the generic
   `tgf_search::Searcher` belong under `crates/tgf-<id>/tests/` so
   `tgf-search` stays game-neutral.  `crates/tgf-mill/tests/searcher_integration.rs`
   is the canonical example.
6. Register the game id in
   `crates/tgf-frb/src/api/kernel.rs::build_rules_default` so the typed
   `tgf_kernel_create("<game_id>")` factory can route to it.
7. Add a per-game adapter module under `crates/tgf-frb/src/games/<id>/`.
   It owns the FRB-internal helpers for that game (search-event spawn
   functions, action ↔ notation codec, per-handle extras attached to the
   kernel session via `crate::session_registry::put_extras`).  The
   FRB-public DTOs and `pub fn` entry points stay in
   `crates/tgf-frb/src/api/{simple,kernel}.rs` so the generated Dart
   import paths remain stable.  `crates/tgf-frb/src/games/mill/` and
   `crates/tgf-frb/src/games/othello/` are working references.
8. If the CLI needs a UCI surface for the new game, drop a sibling
   `<game>_uci.rs` next to `crates/tgf-cli/src/mill_uci.rs` and extend
   the dispatch in `crates/tgf-cli/src/main.rs`.  Nothing in the entry
   point file generalises today; adding a second adapter is purely
   additive.
9. Add a Flutter module under `lib/games/<id>/`; for the session class,
   subclass `OthelloGameSession`'s pattern (own a `TgfKernel`, translate
   actions through a small codec) — see
   `lib/games/othello/othello_game_session.dart`.
10. If the new game needs to expose extra fields through the
    framework-level `GameStateSnapshot.payload`, implement a
    `TgfKernelExtraDecoder` (see
    `lib/games/mill/mill_marked_pieces_codec.dart::MillKernelExtraDecoder`)
    and register it from the module bootstrap via
    `TgfKernelExtraRegistry.instance.register(GameId.<id>, …)`.  The
    framework `TgfKernel` itself stays game-neutral.
11. Do not modify `tgf-core`, `tgf-search`, or `game_platform` unless the
    new game exposes a real framework gap.

For stochastic tabletop games, add an opt-in `ChanceGame` extension trait later
instead of changing `Game`.  For hidden-information card games, add an opt-in
`PartialInformationGame` extension trait later instead of weakening current
perfect-information invariants.

## Mill rule coverage

`crates/tgf-mill::MillVariantOptions` currently supports:

- `piece_count`, `fly_piece_count`, `pieces_at_least_count`
- `may_fly`
- `has_diagonal_lines` (diagonal adjacency + 4 diagonal mill lines:
  `a7-b6-c5`, `e5-f6-g7`, `a1-b2-c3`, `e3-f2-g1`)
- `may_remove_from_mills_always`
- `may_remove_multiple`
- `n_move_rule`
- `endgame_n_move_rule`
- `may_move_in_placing_phase`
- `is_defender_move_first`
- `restrict_repeated_mills_formation`
- `one_time_use_mill`
- `stop_placing_when_two_empty_squares`
- `board_full_action` for all variants
- `mill_formation_action_in_placing_phase` for all variants at the state-machine
  level.  `markAndDelayRemovingPieces` records the delayed mill-line bitmask
  without introducing a third on-board `MARKED_PIECE` value in Rust. Flutter
  reads those bits from the native snapshot payload for marked-piece visuals.
- `stalemate_action` for all variants: loss, draw, side-change, stalemated side
  removes and keeps the move, stalemated side removes and changes side, and both
  players remove adjacent opponent pieces in order.
- `threefold_repetition_rule` (state-side detection at apply time; runtime
  history keeps up to 256 signatures and snapshots persist the compact
  24-entry payload window)
- `custodian_capture`, `intervention_capture`, and `leap_capture` on square-edge,
  cross, and diagonal lines when `has_diagonal_lines` is true and each capture
  config has `on_diagonal_lines: true`.  The Rust path mirrors the C++ stacking
  semantics: no-mill capture counts add together; leap capture takes precedence
  over mill in moving phase; mill + custodian/intervention only accumulate when
  `may_remove_multiple` is enabled.

All `Rule` fields that affect core Mill move legality and terminal state are
now represented in the Rust path.  Delayed marked-mill bits are encoded in
`MillState.opaque_payload` at bytes 39..43 (`delayed_marked_pieces`, LE u32);
Flutter reads them via `MillMarkedPiecesCodec.markedNodesFromOpaquePayload` in
`lib/games/mill/mill_marked_pieces_codec.dart` (payload key
`millMarkedNodes` on `GameStateSnapshot`).

Each new field follows the same pattern: extend `MillVariantOptions`, update
`MillRules::apply` / `legal_actions` / `outcome`, mirror it in
`crates/tgf-frb/src/api/simple.rs::MillVariantOptions`, then in
`lib/games/mill/mill_variant_options_mapper.dart`, then re-run
`flutter_rust_bridge_codegen generate`.
