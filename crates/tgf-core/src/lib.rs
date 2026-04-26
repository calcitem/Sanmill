// SPDX-License-Identifier: GPL-3.0-or-later
// TGF core – public re-exports.
//
// Phase 1 scaffold: all modules compile to empty stubs; the actual trait
// definitions are introduced in Phases 3–5.

pub mod action;
pub mod board_topology;
pub mod game;
pub mod game_state;

// Convenience re-exports for downstream crates.
pub use action::{Action, ActionList};
pub use board_topology::{BoardTopology, Decoration, Edge, UnitPoint, Zone};
pub use game::{Evaluator, Game, GameRules, Workbench};
pub use game_state::{GameStateSnapshot, Outcome, OutcomeKind};

/// Phase 1 smoke-check: ensures the crate compiles.
#[cfg(test)]
mod tests {
    #[test]
    fn smoke() {
        assert_eq!(2 + 2, 4);
    }
}
