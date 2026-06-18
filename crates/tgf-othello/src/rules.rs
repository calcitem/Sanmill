// SPDX-License-Identifier: GPL-3.0-or-later
// `OthelloRules` plus the `GameRules` trait implementation.

use tgf_core::{
    Action, ActionList, BoardTopology, GameRules, GameStateSnapshot, Outcome, OutcomeKind,
};

use crate::OthelloActionKind;
use crate::state::{OthelloState, apply_othello_action, decode, encode, would_flip};
use crate::topology::OthelloTopology;

#[derive(Clone, Debug, Default)]
pub struct OthelloRules {
    topology: OthelloTopology,
}

impl OthelloRules {
    pub(crate) fn legal_actions_for<const N: usize>(state: &OthelloState, out: &mut ActionList<N>) {
        for sq in 0..64_usize {
            if state.board[sq] == 0 && would_flip(state, sq).0 > 0 {
                out.push(Action {
                    kind_tag: OthelloActionKind::Place as i16,
                    from_node: -1,
                    to_node: sq as i16,
                    aux: -1,
                    payload_bits: 0,
                });
            }
        }
    }
}

impl GameRules for OthelloRules {
    fn game_id(&self) -> &str {
        "othello"
    }

    fn topology(&self) -> &dyn BoardTopology {
        &self.topology
    }

    fn initial_state(&self, _variant_options: &[u8]) -> GameStateSnapshot {
        encode(OthelloState::default())
    }

    fn legal_actions(&self, snap: &GameStateSnapshot, out: &mut ActionList<256>) {
        Self::legal_actions_for(&decode(snap), out);
    }

    fn apply(&self, snap: &GameStateSnapshot, action: Action) -> GameStateSnapshot {
        let mut state = decode(snap);
        apply_othello_action(&mut state, action);
        encode(state)
    }

    fn outcome(&self, snap: &GameStateSnapshot) -> Outcome {
        let state = decode(snap);
        let empty = state.board.iter().filter(|p| **p == 0).count();
        if empty > 0 {
            return Outcome {
                kind: OutcomeKind::Ongoing,
                reason: "ongoing".to_owned(),
            };
        }
        let p1 = state.board.iter().filter(|p| **p == 1).count();
        let p2 = state.board.iter().filter(|p| **p == 2).count();
        if p1 > p2 {
            Outcome {
                kind: OutcomeKind::Win(0),
                reason: "othelloDiskCount".to_owned(),
            }
        } else if p2 > p1 {
            Outcome {
                kind: OutcomeKind::Win(1),
                reason: "othelloDiskCount".to_owned(),
            }
        } else {
            Outcome {
                kind: OutcomeKind::Draw,
                reason: "othelloDraw".to_owned(),
            }
        }
    }
}
