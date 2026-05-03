// SPDX-License-Identifier: GPL-3.0-or-later
// TGF core – public re-exports.
//
// Phase 1 scaffold: all modules compile to empty stubs; the actual trait
// definitions are introduced in Phases 3–5.

pub mod action;
pub mod board_topology;
pub mod game;
pub mod game_state;
pub mod kernel;
pub mod n_move_rule;
pub mod repetition;
pub mod topology_helpers;
pub mod zobrist;

// Convenience re-exports for downstream crates.
pub use action::{action_kind, Action, ActionList, ActionTrail};
pub use board_topology::{BoardTopology, Decoration, Edge, UnitPoint, Zone};
pub use game::{
    assert_game_rules_game_consistency, Evaluator, Game, GameRules, MoveOrderAlgorithm,
    MoveOrderContext, Workbench,
};
pub use game_state::{
    canonical_reason, GameStateSnapshot, MultiPlayerInfo, Outcome, OutcomeKind, OPAQUE_PAYLOAD_LEN,
};
pub use kernel::{GameKernel, KernelError};
pub use n_move_rule::NMoveRuleCounter;
pub use repetition::RepetitionTracker;
pub use zobrist::ZobristTable;

/// Phase 1 smoke-check: ensures the crate compiles.
#[cfg(test)]
mod tests {
    #[test]
    fn smoke() {
        assert_eq!(2 + 2, 4);
    }
}
