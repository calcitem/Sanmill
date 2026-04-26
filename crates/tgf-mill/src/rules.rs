// SPDX-License-Identifier: GPL-3.0-or-later
// Rust-native Mill rules scaffold.
//
// This is intentionally conservative: Phase 4 starts with a small, tested core
// (initial state, placing, adjacent movement, phase transition).  Full mill
// detection, removal obligations, capture variants, repetition, and evaluation
// are added incrementally and checked against the mature C++ engine.

use tgf_core::{
    Action, ActionList, BoardTopology, GameRules, GameStateSnapshot, Outcome,
    OutcomeKind,
};

use crate::topology::{default_mill_topology, MillTopology};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(i16)]
pub enum MillActionKind {
    Place = 0,
    Move = 1,
    Remove = 2,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(i16)]
pub enum MillPhase {
    Ready = 0,
    Placing = 1,
    Moving = 2,
    GameOver = 3,
}

#[derive(Clone, Debug)]
pub struct MillVariantOptions {
    pub piece_count: u8,
    pub fly_piece_count: u8,
    pub may_fly: bool,
    pub has_diagonal_lines: bool,
}

impl Default for MillVariantOptions {
    fn default() -> Self {
        Self {
            piece_count: 9,
            fly_piece_count: 3,
            may_fly: true,
            has_diagonal_lines: false,
        }
    }
}

#[derive(Debug)]
pub struct MillRules {
    options: MillVariantOptions,
    topology: MillTopology,
}

impl MillRules {
    pub fn new(options: MillVariantOptions) -> Self {
        Self {
            options,
            topology: default_mill_topology(),
        }
    }

    fn decode(snapshot: &GameStateSnapshot) -> MillState {
        MillState::decode(snapshot)
    }

    fn encode(&self, state: MillState) -> GameStateSnapshot {
        GameStateSnapshot {
            side_to_move: state.side_to_move,
            phase_tag: state.phase as i16,
            move_number: state.move_number,
            zobrist_key: 0,
            opaque_payload: state.encode(),
        }
    }
}

impl Default for MillRules {
    fn default() -> Self {
        Self::new(MillVariantOptions::default())
    }
}

impl GameRules for MillRules {
    fn game_id(&self) -> &str {
        "mill"
    }

    fn topology(&self) -> &dyn BoardTopology {
        &self.topology
    }

    fn initial_state(&self, _variant_options: &[u8]) -> GameStateSnapshot {
        let state = MillState {
            board: [0; 24],
            side_to_move: 0,
            phase: MillPhase::Placing,
            move_number: 0,
            pieces_in_hand: [self.options.piece_count, self.options.piece_count],
            pieces_on_board: [0, 0],
        };
        self.encode(state)
    }

    fn legal_actions(&self, snap: &GameStateSnapshot, out: &mut ActionList<256>) {
        let state = Self::decode(snap);
        match state.phase {
            MillPhase::Placing => {
                if state.pieces_in_hand[state.side_to_move as usize] == 0 {
                    return;
                }
                for (node, piece) in state.board.iter().enumerate() {
                    if *piece == 0 {
                        out.push(Action {
                            kind_tag: MillActionKind::Place as i16,
                            from_node: -1,
                            to_node: node as i16,
                            aux: -1,
                            payload_bits: 0,
                        });
                    }
                }
            }
            MillPhase::Moving => {
                let side = state.side_to_move as usize;
                let can_fly = self.options.may_fly
                    && state.pieces_on_board[side] <= self.options.fly_piece_count;
                for (from, piece) in state.board.iter().enumerate() {
                    if *piece != state.side_to_move + 1 {
                        continue;
                    }
                    if can_fly {
                        for (to, target) in state.board.iter().enumerate() {
                            if *target == 0 {
                                out.push(move_action(from, to));
                            }
                        }
                    } else {
                        for &to in self.topology.neighbors(from as u16) {
                            if state.board[to as usize] == 0 {
                                out.push(move_action(from, to as usize));
                            }
                        }
                    }
                }
            }
            MillPhase::Ready | MillPhase::GameOver => {}
        }
    }

    fn apply(&self, snap: &GameStateSnapshot, action: Action) -> GameStateSnapshot {
        let mut state = Self::decode(snap);
        match action.kind_tag {
            x if x == MillActionKind::Place as i16 => {
                let to = action.to_node as usize;
                debug_assert!(state.board[to] == 0);
                let side = state.side_to_move as usize;
                state.board[to] = state.side_to_move + 1;
                state.pieces_in_hand[side] = state.pieces_in_hand[side].saturating_sub(1);
                state.pieces_on_board[side] += 1;
                state.move_number += 1;
                if state.pieces_in_hand[0] == 0 && state.pieces_in_hand[1] == 0 {
                    state.phase = MillPhase::Moving;
                }
                state.side_to_move ^= 1;
            }
            x if x == MillActionKind::Move as i16 => {
                let from = action.from_node as usize;
                let to = action.to_node as usize;
                debug_assert_eq!(state.board[from], state.side_to_move + 1);
                debug_assert_eq!(state.board[to], 0);
                state.board[from] = 0;
                state.board[to] = state.side_to_move + 1;
                state.move_number += 1;
                state.side_to_move ^= 1;
            }
            _ => {}
        }
        self.encode(state)
    }

    fn outcome(&self, snap: &GameStateSnapshot) -> Outcome {
        let state = Self::decode(snap);
        if state.phase == MillPhase::GameOver {
            Outcome {
                kind: OutcomeKind::Abandoned,
                reason: "gameOver".to_owned(),
            }
        } else {
            Outcome {
                kind: OutcomeKind::Ongoing,
                reason: "ongoing".to_owned(),
            }
        }
    }
}

fn move_action(from: usize, to: usize) -> Action {
    Action {
        kind_tag: MillActionKind::Move as i16,
        from_node: from as i16,
        to_node: to as i16,
        aux: -1,
        payload_bits: 0,
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct MillState {
    board: [i8; 24],
    side_to_move: i8,
    phase: MillPhase,
    move_number: i16,
    pieces_in_hand: [u8; 2],
    pieces_on_board: [u8; 2],
}

impl MillState {
    fn encode(self) -> [u8; 256] {
        let mut payload = [0_u8; 256];
        for (i, piece) in self.board.iter().enumerate() {
            payload[i] = *piece as u8;
        }
        payload[24] = self.pieces_in_hand[0];
        payload[25] = self.pieces_in_hand[1];
        payload[26] = self.pieces_on_board[0];
        payload[27] = self.pieces_on_board[1];
        payload
    }

    fn decode(snapshot: &GameStateSnapshot) -> Self {
        let payload = snapshot.opaque_payload;
        let mut board = [0_i8; 24];
        for (i, slot) in board.iter_mut().enumerate() {
            *slot = payload[i] as i8;
        }
        Self {
            board,
            side_to_move: snapshot.side_to_move,
            phase: match snapshot.phase_tag {
                x if x == MillPhase::Ready as i16 => MillPhase::Ready,
                x if x == MillPhase::Moving as i16 => MillPhase::Moving,
                x if x == MillPhase::GameOver as i16 => MillPhase::GameOver,
                _ => MillPhase::Placing,
            },
            move_number: snapshot.move_number,
            pieces_in_hand: [payload[24], payload[25]],
            pieces_on_board: [payload[26], payload[27]],
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn initial_state_has_24_placing_actions() {
        let rules = MillRules::default();
        let snap = rules.initial_state(&[]);
        let mut actions = ActionList::<256>::new();
        rules.legal_actions(&snap, &mut actions);
        assert_eq!(actions.len(), 24);
        assert!(actions.iter().all(|a| a.kind_tag == MillActionKind::Place as i16));
    }

    #[test]
    fn place_action_reduces_hand_and_switches_side() {
        let rules = MillRules::default();
        let snap = rules.initial_state(&[]);
        let next = rules.apply(
            &snap,
            Action {
                kind_tag: MillActionKind::Place as i16,
                from_node: -1,
                to_node: 0,
                aux: -1,
                payload_bits: 0,
            },
        );
        let state = MillRules::decode(&next);
        assert_eq!(state.board[0], 1);
        assert_eq!(state.side_to_move, 1);
        assert_eq!(state.pieces_in_hand[0], 8);
        assert_eq!(state.pieces_on_board[0], 1);
    }
}
