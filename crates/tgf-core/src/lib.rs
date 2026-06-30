// SPDX-License-Identifier: AGPL-3.0-or-later
// TGF core – public re-exports.
//
// Game-neutral traits, POD types, kernels, and helpers shared by concrete
// game crates and the FRB API layer.

pub mod action;
pub mod board_topology;
pub mod game;
pub mod game_state;
pub mod kernel;
pub mod n_move_rule;
pub mod notation;
pub mod repetition;
pub mod text_format;
pub mod topology_helpers;
pub mod zobrist;

// Convenience re-exports for downstream crates.
pub use action::{
    Action, ActionList, ActionTrail, MoveOrderScore, SEARCH_ACTION_CAPACITY, SearchActionList,
    action_kind, pack_move_order_score,
};
pub use board_topology::{BoardTopology, Decoration, Edge, UnitPoint, Zone};
pub use game::{
    Evaluator, Game, GameRules, MoveOrderAlgorithm, MoveOrderContext, Workbench,
    assert_game_rules_game_consistency,
};
pub use game_state::{
    GameStateSnapshot, MultiPlayerInfo, OPAQUE_PAYLOAD_LEN, Outcome, OutcomeKind, canonical_reason,
};
pub use kernel::{GameKernel, KernelError};
pub use n_move_rule::NMoveRuleCounter;
pub use notation::NotationCodec;
pub use repetition::RepetitionTracker;
pub use text_format::PositionTextFormat;
pub use zobrist::ZobristTable;

/// Smoke-check: ensures the crate compiles.
#[cfg(test)]
mod tests {
    #[test]
    fn smoke() {
        assert_eq!(2 + 2, 4);
    }
}
