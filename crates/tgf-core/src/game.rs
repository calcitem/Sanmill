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
}
