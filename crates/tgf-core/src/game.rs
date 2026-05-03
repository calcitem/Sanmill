// SPDX-License-Identifier: GPL-3.0-or-later
// Phase 1 scaffold – Game trait family.
//
// Full implementations (MillGame, Searcher<G>) are introduced in Phases 4-5.
// This module only defines the minimal trait shapes needed by tgf-frb so that
// the workspace compiles end-to-end in Phase 1.

use crate::{
    action::{Action, ActionList},
    board_topology::BoardTopology,
    game_state::{GameStateSnapshot, Outcome},
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
}

/// Per-game static evaluator.  Methods are free functions (not `&self`) so the
/// compiler can inline them at generic instantiation sites without a vtable.
pub trait Evaluator<W: Workbench> {
    fn score(wb: &W) -> i32;
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
}
