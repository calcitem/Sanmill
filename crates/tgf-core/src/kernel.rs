// SPDX-License-Identifier: AGPL-3.0-or-later
// Runtime-polymorphic facade used at the FRB / kernel boundary.
//
// `GameKernel` holds an `Arc<dyn GameRules>` so the FRB layer can host
// multiple games without templating on a concrete `Game` type.  The hot
// search path stays generic via `Searcher<G: Game>`; trait-object
// dispatch only happens at IPC granularity (one call per user action),
// which matches the design in
// `.cursor/plans/sanmill_通用棋牌框架重构方案_7a7a6b54.plan.md` §3.1.5.
//
// This is intentionally a small, allocation-light value type so it can be
// owned by an FRB opaque handle on the Dart side without leaking Rust
// internals.

use std::sync::Arc;

use crate::{
    action::{Action, ActionList},
    board_topology::BoardTopology,
    game::GameRules,
    game_state::{GameStateSnapshot, Outcome, OutcomeKind},
};

/// Errors surfaced across the FRB boundary.  The string variants carry
/// only stable English tokens — translation is handled by the shell.
#[derive(Debug, thiserror::Error)]
pub enum KernelError {
    #[error("unknown game id: {0}")]
    UnknownGame(String),
    #[error("illegal action")]
    IllegalAction,
    #[error("nothing to undo")]
    UndoEmpty,
    #[error("nothing to redo")]
    RedoEmpty,
    #[error("variant options invalid: {0}")]
    BadVariant(String),
    #[error("internal: {0}")]
    Internal(String),
}

/// A long-lived game session.  Created from a `GameRules` implementation
/// and owns the current snapshot plus undo/redo stacks.  Lookup by
/// `game_id` is the responsibility of the FRB layer (see `tgf-frb`).
pub struct GameKernel {
    rules: Arc<dyn GameRules>,
    state: GameStateSnapshot,
    history: Vec<GameStateSnapshot>,
    redo_stack: Vec<GameStateSnapshot>,
}

impl GameKernel {
    /// Build a kernel from `rules` and the variant byte payload.  The
    /// payload's format is owned by the concrete game crate; the kernel
    /// passes it through unchanged to `GameRules::initial_state`.
    pub fn new(rules: Arc<dyn GameRules>, variant_options: &[u8]) -> Self {
        let state = rules.initial_state(variant_options);
        Self {
            rules,
            state,
            history: Vec::new(),
            redo_stack: Vec::new(),
        }
    }

    pub fn game_id(&self) -> &str {
        self.rules.game_id()
    }

    pub fn snapshot(&self) -> GameStateSnapshot {
        self.state
    }

    pub fn history_snapshots(&self) -> &[GameStateSnapshot] {
        &self.history
    }

    pub fn outcome(&self) -> Outcome {
        self.rules.outcome(&self.state)
    }

    /// Expose the underlying topology for `kernelTopology`-style FRB calls.
    pub fn topology(&self) -> &dyn BoardTopology {
        self.rules.topology()
    }

    /// Expose the underlying multi-player metadata so the FRB layer
    /// can render team-aware UI.  Most games return the standard
    /// two-player layout; team games (军棋, Halma) override.
    pub fn multi_player_info(&self) -> crate::game_state::MultiPlayerInfo {
        self.rules.multi_player_info()
    }

    /// Generate the legal-action list for the current state.  Returns a
    /// heap `Vec` because FRB needs an owned, sized collection across the
    /// boundary.  Search code should NOT call this; use the generic
    /// `Searcher<G>` path instead, which keeps actions in `ActionList`.
    pub fn legal_actions(&self) -> Vec<Action> {
        let mut buf = ActionList::<256>::new();
        self.rules.legal_actions(&self.state, &mut buf);
        buf.into_iter().collect()
    }

    /// Apply `action` and push the previous state onto the undo stack.
    /// Clears the redo stack on success because diverging from the redo
    /// path produces a new branch.
    pub fn apply(&mut self, action: Action) -> Result<GameStateSnapshot, KernelError> {
        if !self.rules.is_legal(&self.state, action) {
            return Err(KernelError::IllegalAction);
        }
        let previous = self.state;
        let next = self
            .rules
            .apply_with_history(&previous, action, &self.history);
        self.history.push(self.state);
        self.state = next;
        self.redo_stack.clear();
        Ok(self.state)
    }

    /// Apply `action` without legality checking (P3.4).
    /// Mirrors master `Position::do_move` which assumes the move is already
    /// legal. Use for hot paths (search replay, benchmark) where the move
    /// has already been validated by `legal_actions`.
    pub fn apply_unchecked(&mut self, action: Action) -> GameStateSnapshot {
        let previous = self.state;
        let next = self
            .rules
            .apply_with_history(&previous, action, &self.history);
        self.history.push(self.state);
        self.state = next;
        self.redo_stack.clear();
        self.state
    }

    /// Pop one entry from the undo stack and push the current state on
    /// the redo stack.  Errors when there is nothing to undo.
    pub fn undo(&mut self) -> Result<GameStateSnapshot, KernelError> {
        let prev = self.history.pop().ok_or(KernelError::UndoEmpty)?;
        self.redo_stack.push(self.state);
        self.state = prev;
        Ok(self.state)
    }

    /// Symmetric inverse of `undo`.  Errors when there is nothing to redo.
    pub fn redo(&mut self) -> Result<GameStateSnapshot, KernelError> {
        let next = self.redo_stack.pop().ok_or(KernelError::RedoEmpty)?;
        self.history.push(self.state);
        self.state = next;
        Ok(self.state)
    }

    /// Reset to the initial position derived from `variant_options`.
    /// History and redo stacks are cleared.
    pub fn reset(&mut self, variant_options: &[u8]) {
        self.state = self.rules.initial_state(variant_options);
        self.history.clear();
        self.redo_stack.clear();
    }

    /// Number of moves available in the undo stack.  Useful for FRB
    /// callers that want to expose disabled-button hints to the UI.
    pub fn undo_depth(&self) -> usize {
        self.history.len()
    }

    /// Number of moves available in the redo stack.
    pub fn redo_depth(&self) -> usize {
        self.redo_stack.len()
    }

    /// True when the current state is terminal.  Equivalent to
    /// `matches!(self.outcome().kind, OutcomeKind::Win(_) | OutcomeKind::Draw)`
    /// but cheaper because most games can determine this from the
    /// snapshot alone.
    pub fn is_terminal(&self) -> bool {
        !matches!(self.outcome().kind, OutcomeKind::Ongoing)
    }

    /// Replace the current state with an externally-constructed snapshot,
    /// clearing both undo and redo stacks.
    ///
    /// This is the setup-position escape hatch: the FRB layer builds a new
    /// `MillState` via `MillState::set_piece` / `recompute_aux` / `encode`,
    /// then calls this to make the kernel reflect the edited board without
    /// going through legal-action verification.  Only call this from setup
    /// flows where legality is enforced by the UI, not by the engine.
    pub fn replace_state(&mut self, new_state: GameStateSnapshot) {
        self.state = new_state;
        self.history.clear();
        self.redo_stack.clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        action::{Action, ActionList},
        board_topology::{BoardTopology, Decoration, Edge, UnitPoint, Zone},
        game::GameRules,
        game_state::{GameStateSnapshot, Outcome, OutcomeKind},
    };
    use std::sync::Arc;

    /// Minimal "tic-tac-toe-like" 3-slot game used to exercise the kernel
    /// undo/redo and outcome plumbing without dragging in tgf-mill.
    struct ToyTopology;
    impl BoardTopology for ToyTopology {
        fn name(&self) -> &str {
            "toy.3"
        }
        fn node_count(&self) -> u16 {
            3
        }
        fn coordinate_of(&self, _: u16) -> UnitPoint {
            UnitPoint { x: 0.0, y: 0.0 }
        }
        fn label_of(&self, _: u16) -> &str {
            ""
        }
        fn node_from_label(&self, _: &str) -> Option<u16> {
            None
        }
        fn neighbors(&self, _: u16) -> &[u16] {
            &[]
        }
        fn edges(&self) -> &[Edge] {
            &[]
        }
        fn line_groups(&self) -> &[Vec<u16>] {
            &[]
        }
        fn zones(&self) -> &[Zone] {
            &[]
        }
        fn decorations(&self) -> &[Decoration] {
            &[]
        }
    }

    struct ToyRules {
        topo: ToyTopology,
    }

    impl GameRules for ToyRules {
        fn game_id(&self) -> &str {
            "toy"
        }
        fn topology(&self) -> &dyn BoardTopology {
            &self.topo
        }
        fn initial_state(&self, _variant_options: &[u8]) -> GameStateSnapshot {
            GameStateSnapshot::default()
        }
        fn legal_actions(&self, snap: &GameStateSnapshot, out: &mut ActionList<256>) {
            for slot in 0..3_i16 {
                if snap.opaque_payload[slot as usize] == 0 {
                    out.push(Action {
                        kind_tag: 0,
                        from_node: -1,
                        to_node: slot,
                        aux: -1,
                        payload_bits: 0,
                    });
                }
            }
        }
        fn apply(&self, snap: &GameStateSnapshot, action: Action) -> GameStateSnapshot {
            let mut next = *snap;
            let slot = action.to_node as usize;
            next.opaque_payload[slot] = (next.side_to_move + 1) as u8;
            next.side_to_move ^= 1;
            next.move_number += 1;
            next
        }
        fn outcome(&self, snap: &GameStateSnapshot) -> Outcome {
            if snap.opaque_payload[..3].iter().all(|p| *p != 0) {
                Outcome {
                    kind: OutcomeKind::Draw,
                    reason: "boardFull".to_owned(),
                }
            } else {
                Outcome {
                    kind: OutcomeKind::Ongoing,
                    reason: "ongoing".to_owned(),
                }
            }
        }
    }

    fn rules() -> Arc<dyn GameRules> {
        Arc::new(ToyRules { topo: ToyTopology })
    }

    #[test]
    fn legal_actions_match_initial_slots() {
        let kernel = GameKernel::new(rules(), &[]);
        assert_eq!(kernel.legal_actions().len(), 3);
        assert!(!kernel.is_terminal());
        assert_eq!(kernel.undo_depth(), 0);
    }

    #[test]
    fn apply_advances_state_and_records_history() {
        let mut kernel = GameKernel::new(rules(), &[]);
        let actions = kernel.legal_actions();
        let next = kernel.apply(actions[0]).expect("legal apply must succeed");
        assert_ne!(next.opaque_payload[..3], [0, 0, 0]);
        assert_eq!(kernel.undo_depth(), 1);
        assert_eq!(kernel.legal_actions().len(), 2);
    }

    #[test]
    fn undo_and_redo_round_trip() {
        let mut kernel = GameKernel::new(rules(), &[]);
        let actions = kernel.legal_actions();
        let original = kernel.snapshot();
        let after_apply = kernel.apply(actions[0]).unwrap();
        let undone = kernel.undo().unwrap();
        assert_eq!(undone, original);
        assert_eq!(kernel.redo_depth(), 1);
        let redone = kernel.redo().unwrap();
        assert_eq!(redone, after_apply);
        assert_eq!(kernel.redo_depth(), 0);
    }

    #[test]
    fn undo_at_root_is_an_error() {
        let mut kernel = GameKernel::new(rules(), &[]);
        assert!(matches!(kernel.undo(), Err(KernelError::UndoEmpty)));
    }

    #[test]
    fn redo_clears_after_a_new_apply() {
        let mut kernel = GameKernel::new(rules(), &[]);
        let acts0 = kernel.legal_actions();
        kernel.apply(acts0[0]).unwrap();
        kernel.undo().unwrap();
        assert_eq!(kernel.redo_depth(), 1);

        let acts_after_undo = kernel.legal_actions();
        kernel.apply(acts_after_undo[1]).unwrap();
        // Diverging from the redo branch must clear the redo stack.
        assert_eq!(kernel.redo_depth(), 0);
    }

    #[test]
    fn outcome_terminal_after_filling_all_slots() {
        let mut kernel = GameKernel::new(rules(), &[]);
        while !kernel.is_terminal() {
            let acts = kernel.legal_actions();
            assert!(!acts.is_empty());
            kernel.apply(acts[0]).unwrap();
        }
        let outcome = kernel.outcome();
        assert!(matches!(outcome.kind, OutcomeKind::Draw));
    }

    #[test]
    fn illegal_action_returns_kernel_error() {
        let mut kernel = GameKernel::new(rules(), &[]);
        let bogus = Action {
            kind_tag: 0,
            from_node: -1,
            to_node: 99,
            aux: -1,
            payload_bits: 0,
        };
        assert!(matches!(
            kernel.apply(bogus),
            Err(KernelError::IllegalAction)
        ));
    }
}
