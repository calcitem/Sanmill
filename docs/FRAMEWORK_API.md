# TGF Framework API

This document defines the current public contract of TGF
(TabletopGameFramework), the Rust framework used by Sanmill and future
board/tabletop/card games.

It is not a changelog.  It is the API boundary that new game crates should
implement and that Flutter modules should consume.

## Crate layout

```text
crates/
├── tgf-core        # Game-neutral traits and POD types
├── tgf-search      # Generic monomorphised searchers
├── tgf-mill        # Mill game implementation
├── tgf-othello     # Othello pressure-test implementation
├── tgf-legacy-cxx  # Transitional bridge to the mature C++ engine
├── tgf-frb         # FRB API surface compiled as rust_lib_sanmill
└── tgf-cli         # Rust CLI / benchmark helper
```

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
- killer/history move ordering
- node and wall-clock abort checks
- deterministic random search seed
- FRB search event stream
- single-threaded UCT-style MCTS tree

Still incomplete compared with mature C++:

- exact C++ MovePicker ordering weights
- C++ TT compact value/depth truncation semantics
- rule50 and repetition
- full qsearch parity
- MCTS alpha-beta assisted simulation
- multi-threaded MCTS shared visits
- perfect DB / endgame learning

## FRB API boundary

The Flutter-facing Rust library is the `tgf-frb` crate, whose Cargo package and
library target are named `rust_lib_sanmill` to match the generated Flutter FFI
plugin.

Stable current FRB surfaces include:

- `kernelTopology()` for Mill geometry
- `legacyKernel*` functions for transitional C++ bridge access
- `nativeMill*` smoke/differential/search APIs
- `nativeOthello*` pressure-test APIs
- `nativeMillSearchEvents(depth)` stream
- `nativeMillSearchStop()` cancellation request

Generated Dart files under `lib/src/rust/frb_generated*.dart` are committed and
must be regenerated after every FRB API change.

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

## Legacy C++ bridge policy

`tgf-legacy-cxx` is transitional and intentionally small.

Allowed uses:

- differential tests against mature C++ behavior
- temporary FRB-backed MillRulesPort and LegacyTgfKernel
- perfect DB/opening book retention until Rust replacements are justified

Rules:

- The C++ bridge is not thread-safe.  Tests touching it must serialize access.
- New Rust game logic must not depend on global C++ rule state.
- Do not widen the bridge unless it directly supports a migration step or a
  differential test.

## Adding a new game

To add a deterministic perfect-information game:

1. Create `crates/tgf-<id>`.
2. Implement `BoardTopology` if the game has a board geometry.
3. Implement `GameRules` for runtime boundary use.
4. Implement `Game`, `Workbench`, and `Evaluator` for search.
5. Add Rust tests for `legal_actions`, `apply`, `perft`, and search smoke.
6. Add a Flutter module under `lib/games/<id>`.
7. Do not modify `tgf-core`, `tgf-search`, or `game_platform` unless the new
   game exposes a real framework gap.

For stochastic tabletop games, add an opt-in `ChanceGame` extension trait later
instead of changing `Game`.  For hidden-information card games, add an opt-in
`PartialInformationGame` extension trait later instead of weakening current
perfect-information invariants.
