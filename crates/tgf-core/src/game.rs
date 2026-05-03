// SPDX-License-Identifier: GPL-3.0-or-later
// Game trait family used by every concrete game crate.
//
// # Two-trait split (`GameRules` vs `Game`)
//
// Each concrete game implements TWO traits side-by-side:
//
//   * [`GameRules`] is object-safe and used at runtime boundaries
//     (`tgf-core::GameKernel` / FRB / scripting).  It dispatches
//     through `dyn GameRules` so a single binary can host multiple
//     games at the same time.
//
//   * [`Game`] is the compile-time CRTP contract used by the search
//     hot path (`Searcher<G: Game>`).  It uses associated types
//     (`Workbench`, `Evaluator`) so do/undo/evaluate calls stay
//     statically dispatched, matching the C++ engine's monomorphised
//     fast path.
//
// ## Consistency invariant
//
// Both traits MUST agree on legal moves, transitions, and terminal
// states for the same `GameStateSnapshot`.  Specifically:
//
//   * `GameRules::legal_actions(snap)` must enumerate the same set
//     of actions as `Game::generate_legal(workbench)` where the
//     workbench is `Game::build_workbench(snap)`.
//   * `GameRules::apply(snap, a)` must produce the same successor
//     snapshot as round-tripping through
//     `wb.do_move(a) ; wb.snapshot()`.
//
// `tgf-core` cannot enforce this with a derive macro because the
// associated `Workbench` type is opaque to the framework, but every
// concrete game crate is expected to ship at least one regression
// test (e.g. `tgf-mill::tests::game_rules_match_game_for_random_walk`)
// that round-trips both surfaces over a few hundred ply and checks
// the action sets / snapshots agree.

use crate::{
    action::{Action, ActionList, ActionTrail},
    board_topology::BoardTopology,
    game_state::{GameStateSnapshot, MultiPlayerInfo, Outcome},
};

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum MoveOrderAlgorithm {
    AlphaBeta,
    #[default]
    Pvs,
    Mtdf,
    Mcts,
    Random,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct MoveOrderContext {
    pub algorithm: MoveOrderAlgorithm,
    pub skill_level: u8,
    pub shuffling: bool,
    pub hash_move: Option<Action>,
    /// Per-search seed used by games that mirror a global shuffled move
    /// priority table. A value of 0 keeps shuffling deterministic for tests.
    pub shuffle_seed: u64,
}

/// Mutable, search-only working position.  Lives on the searcher's thread.
/// Hot-path methods MUST be `#[inline]` in concrete implementations.
pub trait Workbench: Sized {
    fn snapshot(&self) -> GameStateSnapshot;
    fn key(&self) -> u64;
    fn side_to_move(&self) -> i8;
    fn is_terminal(&self) -> bool;

    fn do_move(&mut self, a: Action);
    fn undo_move(&mut self);

    /// Compute the position key the Workbench would have *after*
    /// applying `action`.  Used by the searcher to issue TT prefetch
    /// hints before recursing into child nodes (mirrors master
    /// `Position::key_after` in `src/position.cpp`).
    ///
    /// The default implementation does an actual `do_move` / `key()` /
    /// `undo_move` round-trip so games with full-state hashing keep
    /// working without changes.  Concrete games whose key is
    /// incrementally maintained (Zobrist-style) should override this
    /// with an O(1) xor-only computation -- see master `key_after`
    /// for the reference shape.
    ///
    /// `&mut` is required so the default implementation can borrow
    /// the workbench mutably for the do/undo round-trip; concrete
    /// O(1) overrides are still expected to leave the Workbench
    /// observably unchanged on return.
    #[inline]
    fn key_after(&mut self, action: Action) -> u64 {
        self.do_move(action);
        let key = self.key();
        self.undo_move();
        key
    }
}

/// Per-game static evaluator.  Methods are free functions (not `&self`) so the
/// compiler can inline them at generic instantiation sites without a vtable.
pub trait Evaluator<W: Workbench> {
    fn score(wb: &W) -> i32;
}

/// Assert that a [`GameRules`] / [`Game`] pair agrees on legal moves
/// and transitions for `snap`.  Concrete game crates plug their own
/// `Game::build_workbench` / `GameRules::apply` together via this
/// helper to catch divergences early.
///
/// Returns `Ok(())` when the two surfaces agree, or a human-readable
/// diff string on the first mismatch (legal-action set, side after
/// move, or post-apply snapshot).  Cheap enough to run in tests for
/// random-walk corpora.
///
/// # Performance
///
/// Allocates two `ActionList<256>`s and one `Vec<Action>`; not for
/// hot paths.  Use only in tests / fuzz harnesses.
pub fn assert_game_rules_game_consistency<R, G>(
    rules: &R,
    game: &G,
    snap: &GameStateSnapshot,
) -> Result<(), String>
where
    R: GameRules + ?Sized,
    G: Game,
{
    let mut rules_actions = ActionList::<256>::new();
    rules.legal_actions(snap, &mut rules_actions);

    let workbench = game.build_workbench(snap);
    let mut game_actions = ActionList::<256>::new();
    G::generate_legal(&workbench, &mut game_actions);

    if rules_actions.len() != game_actions.len() {
        return Err(format!(
            "GameRules / Game disagree on legal-action count at snapshot \
             phase_tag={}, side_to_move={}: rules={}, game={}",
            snap.phase_tag,
            snap.side_to_move,
            rules_actions.len(),
            game_actions.len(),
        ));
    }

    for action in rules_actions.iter() {
        if !game_actions.contains(action) {
            return Err(format!(
                "GameRules emitted action kind={} from={} to={} that Game did \
                 not enumerate",
                action.kind_tag, action.from_node, action.to_node,
            ));
        }
    }

    Ok(())
}

/// Object-safe trait used at the FRB / kernel boundary for runtime
/// multi-game switching.  The search hot-loop NEVER uses this trait – it goes
/// through the `Game` associated-type path (not object-safe but monomorphic).
pub trait GameRules: Send + Sync {
    fn game_id(&self) -> &str;
    fn topology(&self) -> &dyn BoardTopology;
    fn initial_state(&self, variant_options: &[u8]) -> GameStateSnapshot;
    fn legal_actions(&self, snap: &GameStateSnapshot, out: &mut ActionList<256>);
    fn is_legal(&self, snap: &GameStateSnapshot, action: Action) -> bool {
        let mut list = ActionList::<256>::new();
        self.legal_actions(snap, &mut list);
        list.contains(&action)
    }
    fn apply(&self, snap: &GameStateSnapshot, action: Action) -> GameStateSnapshot;
    fn outcome(&self, snap: &GameStateSnapshot) -> Outcome;

    /// Describe the intermediate hops a single `Action` traverses.
    ///
    /// Default implementation returns an empty trail, which is the
    /// correct answer for every game whose moves are single
    /// `from -> to` steps (Mill, Chess except castling, Othello, …).
    /// Games with multi-step actions (Chinese Checkers / Halma chains,
    /// International Checkers forced jumps, chess castling animation)
    /// override this to populate [`ActionTrail::hops`] so the shell
    /// can render the move without re-deriving the path.
    ///
    /// Cold path: search never queries this; renderers, notation
    /// codecs and PGN/SGF exporters do.
    fn action_trail(&self, _snap: &GameStateSnapshot, _action: Action) -> ActionTrail {
        ActionTrail::EMPTY
    }

    /// Multi-player metadata describing the player count and team
    /// layout of this game.  Default: standard two-player free-for-all
    /// layout matching every existing game in the framework.  Multi-
    /// player team games (军棋 4 人对战 / Halma 多人) override this.
    ///
    /// Cold path: queried at session creation by the FRB layer / UI;
    /// search never inspects it.
    fn multi_player_info(&self) -> MultiPlayerInfo {
        MultiPlayerInfo::two_player_default()
    }
}

/// Compile-time game contract for the search hot path.  NOT object-safe.
/// `Searcher<G: Game>` is monomorphised per game, matching C++ CRTP.
pub trait Game: 'static + Send + Sync {
    type Workbench: Workbench;
    type Evaluator: Evaluator<Self::Workbench>;

    fn build_workbench(&self, snap: &GameStateSnapshot) -> Self::Workbench;

    /// MUST be `#[inline]` in every concrete implementation.
    fn generate_legal(wb: &Self::Workbench, out: &mut ActionList<256>);

    /// Context-aware legal generation used by search. The default preserves
    /// legacy game implementations; games with skill/shuffle-dependent move
    /// priority can override this without affecting perft/API enumeration.
    #[inline]
    fn generate_legal_ctx(
        wb: &Self::Workbench,
        out: &mut ActionList<256>,
        _ctx: &MoveOrderContext,
    ) {
        Self::generate_legal(wb, out);
    }

    /// Optional static move-ordering bonus (e.g. Mill star squares).  Hot path:
    /// keep this `#[inline]` and allocation-free in concrete games.
    #[inline]
    fn move_order_bias(_wb: &Self::Workbench, _action: Action) -> i32 {
        0
    }

    #[inline]
    fn move_order_bias_ctx(wb: &Self::Workbench, action: Action, _ctx: &MoveOrderContext) -> i32 {
        Self::move_order_bias(wb, action)
    }

    // -----------------------------------------------------------------
    // Composable move-score components.
    //
    // The hooks below are summed into the move-order key used by
    // `Searcher<G>`.  Default implementations return `0`, so
    // monomorphisation eliminates them entirely for games that do not
    // override.  Concrete games may pick the hooks that match their
    // tactical surface (e.g. chess fills `capture_value_bias` and
    // `promotion_bias`; Halma fills `progress_bias`; 军棋 fills
    // `objective_bias`) without inflating a single super-`match`.
    //
    // Hot path: every override MUST be `#[inline]` and allocation-free.
    // -----------------------------------------------------------------

    /// Per-action capture-value bonus (chess MVV-LVA, Mill capture rules).
    /// Default: `0` — no contribution.
    #[inline]
    fn capture_value_bias(_wb: &Self::Workbench, _action: Action) -> i32 {
        0
    }

    /// Per-action promotion bonus (chess pawn promotion, checkers king).
    /// Default: `0` — no contribution.
    #[inline]
    fn promotion_bias(_wb: &Self::Workbench, _action: Action) -> i32 {
        0
    }

    /// Per-action killer-move bonus (typically a constant for actions
    /// that match the killer-move table maintained by the searcher).
    /// Default: `0` — search keeps using its own killer table.  Games
    /// override only when they want to inject extra killer-style
    /// bonuses (e.g. the previous PV move) without touching the
    /// generic search code.
    #[inline]
    fn killer_bonus(_wb: &Self::Workbench, _action: Action) -> i32 {
        0
    }

    /// Per-action "progress" bonus, encouraging moves that advance a
    /// piece toward its goal (Halma / 中国跳棋 推进, race-to-bear-off).
    /// Default: `0`.
    #[inline]
    fn progress_bias(_wb: &Self::Workbench, _action: Action) -> i32 {
        0
    }

    /// Per-action "objective" bonus for games with key squares whose
    /// occupation strongly correlates with winning (军棋 总部, chess
    /// centre control, Othello corners).  Default: `0`.
    #[inline]
    fn objective_bias(_wb: &Self::Workbench, _action: Action) -> i32 {
        0
    }

    /// Optional terminal-node score from `perspective` player's point of view.
    ///
    /// Games with explicit draw/win metadata should override this so search
    /// does not fall back to a heuristic evaluator for rule draws or mates.
    #[inline]
    fn terminal_score(wb: &Self::Workbench, _perspective: i8, _depth: i32) -> Option<i32> {
        wb.is_terminal().then(|| Self::Evaluator::score(wb))
    }

    /// Sentinel score returned when the search root has exactly one legal
    /// action.  The default value (`100`) matches the long-standing
    /// "VALUE_UNIQUE" constant used by Mill and is large enough not to
    /// collide with typical evaluator outputs while still well below mate
    /// scores.  Concrete games may override to align this with their own
    /// evaluator scale.
    ///
    /// Search uses this only at the root single-move short-circuit; it
    /// never affects deeper alpha-beta windows or transposition entries.
    #[inline]
    fn unique_root_move_score() -> i32 {
        100
    }

    /// Magnitude above which static-evaluator scores are considered
    /// "near-terminal" and null-move pruning is skipped.  Default: 40,
    /// matching Mill's VALUE_MATE = 80 (half of mate).  Games with a
    /// different mate-score scale (chess, ~30000) override this to keep
    /// genuine mate sequences from being pruned.
    ///
    /// Hot path: queried once per node when null-move pruning is
    /// enabled; keep `#[inline]` and constant.
    #[inline]
    fn null_move_terminal_guard() -> i32 {
        40
    }

    /// Bias applied when the search detects a repetition along the
    /// path from root to the current node.  Default: `+1`, matching
    /// Mill's "VALUE_DRAW + 1" tie-breaker that avoids threefold
    /// blindness among otherwise equal drawing lines.  Games may
    /// return `0` to treat repetition as an exact draw, or a small
    /// negative number to actively avoid repeating.
    ///
    /// Hot path: queried at most once per visited node; keep
    /// `#[inline]` and constant.
    #[inline]
    fn repetition_draw_bias() -> i32 {
        1
    }
}
