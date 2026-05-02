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
    pub payload_bits: u64,
}
```

Rules:

- `kind_tag` is owned by the concrete game crate.
- `from_node == -1` means no source node, e.g. placing from hand.
- `to_node == -1` means no target node.
- `payload_bits` is game-defined compact data.
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

Current scaffolds already include:

- side-aware score polarity
- TT exact/lower/upper bound handling
- TT best-move ordering
- packed two-slot TT clusters (`AtomicU64` slots) sharable across threads
  via `SharedTt` and the `lazy_smp_search` scaffold
- `SearchThreadPool` (`std::thread` workers + `crossbeam_channel` dispatch)
  used by lazy SMP worker fan-out
- killer/history move ordering
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

### Differential testing

`crates/tgf-frb/src/api/simple.rs::random_walk_native_and_legacy_agree`
plays seeded random Mill games (default 5,000 × 80 plies, override via
`TGF_RANDOM_WALK_GAMES` / `TGF_RANDOM_WALK_SEED`) and asserts that the native
Rust `MillRules` and the legacy C++ engine return identical legal action
sets, phase tags, and side-to-move at every ply.

For the migration plan's 1,000,000-position target, the
`#[ignore]`-marked nightly variant
`crates/tgf-frb/src/api/simple.rs::random_walk_extended` runs 12,500
games × 80 plies (~60 s in release).  Run it explicitly with:

```bash
cargo test --release -p rust_lib_sanmill --lib -- \
    --ignored random_walk_extended
```

Plus the existing fixed-position `native_and_legacy_*` perft tests.

### Still incomplete compared with mature C++

Work in progress (see migration plan phase 5):

- remaining TT parity knobs such as C++ fake-clean age semantics, if retained
- C++ qsearch is currently a depth-0 stand-pat with the recursive remove
  branch gated behind `MAX_QUIESCENCE_DEPTH = 0`; `tgf-search`'s
  `qsearch_with_depth` already runs the full remove extension (sorted via the
  same MovePicker-style scoring) and applies the
  `if (stand_pat > 0) stand_pat += depth;` mate-distance decay.  Future work
  is to lift that depth gate in C++ and verify the deeper qsearch agrees.
- MCTS alpha-beta assisted simulation

**Intentionally staying on the cxx bridge (not “incomplete” bugs):** perfect DB
and opening book remain in C++ by policy; see §Legacy C++ bridge policy.

## Search tuning (Rust `tgf-search` / `tgf-cli`)

- **TT size:** `tgf_cli`’s `bench` and UCI `go` path use
  `Searcher::new_with_tt_cluster_bits` driven by the environment variable
  `TGF_TT_CLUSTER_BITS` (clamped 10–18, default 14).  The TOML block printed by
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

#### Setup-position editing API (Phase 6.A.1)

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

#### FEN import / export API (Phase 6.A.3.B)

- `tgfKernelSetFromFen({handle, fen})` — load a Mill FEN string compatible with
  the legacy Dart/C++ engine format; returns updated snapshot.
- `tgfKernelExportFen({handle})` — serialize current kernel state as a Mill FEN
  string.  Round-trip guarantee: `setFromFen(exportFen(s))` reproduces the same
  board, side, phase, and piece counts (mills-bitmask output as 0).

The Dart wrapper that hides FFI details is
`lib/game_platform/engine/tgf_kernel.dart::TgfKernel`.  It also produces
framework-level `GameStateSnapshot` / `GameOutcome` values directly.

`OthelloGameSession` is the first non-Mill session driven entirely by this
typed API; future games should follow the same pattern.

### Legacy / smoke surfaces

These remain available during the transition:

- `kernelTopology()` for Mill geometry
- `legacyKernel*` functions for the transitional C++ bridge
- `nativeMill*` / `nativeOthello*` smoke and differential helpers
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
6. Register the game id in
   `crates/tgf-frb/src/api/kernel.rs::build_rules_default` so the typed
   `tgf_kernel_create("<game_id>")` factory can route to it.
7. Add a Flutter module under `lib/games/<id>`; for the session class,
   subclass `OthelloGameSession`'s pattern (own a `TgfKernel`, translate
   actions through a small codec) — see
   `lib/games/othello/othello_game_session.dart`.
8. Do not modify `tgf-core`, `tgf-search`, or `game_platform` unless the new
   game exposes a real framework gap.

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
  without introducing a third on-board `MARKED_PIECE` value in Rust yet; this is
  sufficient for FRB state parity but the Flutter legacy renderer still owns
  marked-piece visuals.
- `stalemate_action` for all variants: loss, draw, side-change, stalemated side
  removes and keeps the move, stalemated side removes and changes side, and both
  players remove adjacent opponent pieces in order.
- `threefold_repetition_rule` (state-side detection at apply time;
  rolling 24-entry signature buffer in `MillState.opaque_payload`)
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
`lib/game_platform/mill_marked_pieces_codec.dart` (payload key `millMarkedNodes`
on `GameStateSnapshot`).

Each new field follows the same pattern: extend `MillVariantOptions`, update
`MillRules::apply` / `legal_actions` / `outcome`, mirror it in
`crates/tgf-frb/src/api/simple.rs::MillVariantOptions`, then in
`lib/games/mill/mill_variant_options_mapper.dart`, then re-run
`flutter_rust_bridge_codegen generate`.
