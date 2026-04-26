// SPDX-License-Identifier: GPL-3.0-or-later
// Rust-native Mill rules scaffold.
//
// This is intentionally conservative: Phase 4 starts with a small, tested core
// (initial state, placing, adjacent movement, phase transition).  Full mill
// detection, removal obligations, capture variants, repetition, and evaluation
// are added incrementally and checked against the mature C++ engine.

use tgf_core::{
    Action, ActionList, BoardTopology, Evaluator, Game, GameRules,
    GameStateSnapshot, Outcome, OutcomeKind, Workbench,
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
    pub pieces_at_least_count: u8,
    pub may_fly: bool,
    pub has_diagonal_lines: bool,
}

impl Default for MillVariantOptions {
    fn default() -> Self {
        Self {
            piece_count: 9,
            fly_piece_count: 3,
            pieces_at_least_count: 3,
            may_fly: true,
            has_diagonal_lines: false,
        }
    }
}

#[derive(Clone, Debug)]
pub struct MillRules {
    options: MillVariantOptions,
    topology: MillTopology,
}

#[derive(Clone, Debug, Default)]
pub struct MillGame {
    options: MillVariantOptions,
}

#[derive(Clone, Debug)]
pub struct MillWorkbench {
    rules: MillRules,
    state: MillState,
    undo_stack: Vec<MillState>,
}

pub struct MillEvaluator;

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

    pub fn moving_mill_remove_count_smoke() -> u32 {
        let rules = MillRules::default();
        let state = MillState {
            board: {
                let mut board = [0_i8; 24];
                board[1] = 1;
                board[2] = 1;
                board[3] = 1;
                board[6] = 2;
                board[5] = 2;
                board[10] = 2;
                board
            },
            side_to_move: 0,
            phase: MillPhase::Moving,
            move_number: 18,
            pieces_in_hand: [0, 0],
            pieces_on_board: [3, 3],
            pending_removals: [0, 0],
            winner: -1,
        };
        let after_move = rules.apply(
            &rules.encode(state),
            Action {
                kind_tag: MillActionKind::Move as i16,
                from_node: 3,
                to_node: 0,
                aux: -1,
                payload_bits: 0,
            },
        );
        let mut actions = ActionList::<256>::new();
        rules.legal_actions(&after_move, &mut actions);
        actions
            .iter()
            .filter(|a| a.kind_tag == MillActionKind::Remove as i16)
            .count() as u32
    }

    pub fn removal_below_three_winner_smoke() -> i32 {
        let rules = MillRules::default();
        let state = MillState {
            board: {
                let mut board = [0_i8; 24];
                board[0] = 1;
                board[1] = 1;
                board[2] = 1;
                board[6] = 2;
                board[5] = 2;
                board
            },
            side_to_move: 0,
            phase: MillPhase::Moving,
            move_number: 20,
            pieces_in_hand: [0, 0],
            pieces_on_board: [3, 2],
            pending_removals: [1, 0],
            winner: -1,
        };
        let after_remove = rules.apply(
            &rules.encode(state),
            Action {
                kind_tag: MillActionKind::Remove as i16,
                from_node: -1,
                to_node: 6,
                aux: -1,
                payload_bits: 0,
            },
        );
        MillRules::decode(&after_remove).winner as i32
    }
}

impl Default for MillRules {
    fn default() -> Self {
        Self::new(MillVariantOptions::default())
    }
}

impl MillGame {
    pub fn new(options: MillVariantOptions) -> Self {
        Self { options }
    }
}

impl Workbench for MillWorkbench {
    fn snapshot(&self) -> GameStateSnapshot {
        self.rules.encode(self.state)
    }

    fn key(&self) -> u64 {
        // Native Zobrist comes later; keep deterministic zero key in Phase 4.
        0
    }

    fn side_to_move(&self) -> i8 {
        self.state.side_to_move
    }

    fn is_terminal(&self) -> bool {
        self.state.phase == MillPhase::GameOver
    }

    fn do_move(&mut self, a: Action) {
        self.undo_stack.push(self.state);
        let next = self.rules.apply(&self.snapshot(), a);
        self.state = MillRules::decode(&next);
    }

    fn undo_move(&mut self) {
        if let Some(prev) = self.undo_stack.pop() {
            self.state = prev;
        }
    }
}

impl Evaluator<MillWorkbench> for MillEvaluator {
    fn score(wb: &MillWorkbench) -> i32 {
        let white = wb.state.pieces_on_board[0] as i32
            + wb.state.pieces_in_hand[0] as i32;
        let black = wb.state.pieces_on_board[1] as i32
            + wb.state.pieces_in_hand[1] as i32;
        let score = (white - black) * 100;
        if wb.state.side_to_move == 0 {
            score
        } else {
            -score
        }
    }
}

impl Game for MillGame {
    type Workbench = MillWorkbench;
    type Evaluator = MillEvaluator;

    fn build_workbench(&self, snap: &GameStateSnapshot) -> Self::Workbench {
        let rules = MillRules::new(self.options.clone());
        let state = MillRules::decode(snap);
        MillWorkbench {
            rules,
            state,
            undo_stack: Vec::new(),
        }
    }

    fn generate_legal(wb: &Self::Workbench, out: &mut ActionList<256>) {
        wb.rules.legal_actions(&wb.snapshot(), out);
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
            pending_removals: [0, 0],
            winner: -1,
        };
        self.encode(state)
    }

    fn legal_actions(&self, snap: &GameStateSnapshot, out: &mut ActionList<256>) {
        let state = Self::decode(snap);
        match state.phase {
            MillPhase::Placing => {
                if state.pending_removals[state.side_to_move as usize] > 0 {
                    self.generate_remove_actions(&state, out);
                    return;
                }
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
                if state.pending_removals[state.side_to_move as usize] > 0 {
                    self.generate_remove_actions(&state, out);
                    return;
                }
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
                if forms_mill(&state, to, state.side_to_move) {
                    state.pending_removals[side] = 1;
                } else {
                    state.side_to_move ^= 1;
                }
            }
            x if x == MillActionKind::Move as i16 => {
                let from = action.from_node as usize;
                let to = action.to_node as usize;
                debug_assert_eq!(state.board[from], state.side_to_move + 1);
                debug_assert_eq!(state.board[to], 0);
                state.board[from] = 0;
                state.board[to] = state.side_to_move + 1;
                state.move_number += 1;
                let side = state.side_to_move as usize;
                if forms_mill(&state, to, state.side_to_move) {
                    state.pending_removals[side] = 1;
                } else {
                    state.side_to_move ^= 1;
                }
            }
            x if x == MillActionKind::Remove as i16 => {
                let to = action.to_node as usize;
                let side = state.side_to_move as usize;
                let opponent = (state.side_to_move ^ 1) as usize;
                debug_assert_eq!(state.board[to], opponent as i8 + 1);
                debug_assert!(state.pending_removals[side] > 0);
                state.board[to] = 0;
                state.pieces_on_board[opponent] =
                    state.pieces_on_board[opponent].saturating_sub(1);
                state.pending_removals[side] =
                    state.pending_removals[side].saturating_sub(1);
                if state.phase == MillPhase::Moving
                    && state.pieces_on_board[opponent] < self.options.pieces_at_least_count
                {
                    state.phase = MillPhase::GameOver;
                    state.winner = state.side_to_move;
                    state.side_to_move = -1;
                } else if state.pending_removals[side] == 0 {
                    state.side_to_move ^= 1;
                }
            }
            _ => {}
        }
        self.encode(state)
    }

    fn outcome(&self, snap: &GameStateSnapshot) -> Outcome {
        let state = Self::decode(snap);
        if state.phase == MillPhase::GameOver {
            Outcome {
                kind: OutcomeKind::Win(state.winner),
                reason: "loseFewerThanThree".to_owned(),
            }
        } else {
            Outcome {
                kind: OutcomeKind::Ongoing,
                reason: "ongoing".to_owned(),
            }
        }
    }
}

impl MillRules {
    fn generate_remove_actions(&self, state: &MillState, out: &mut ActionList<256>) {
        let opponent_piece = (state.side_to_move ^ 1) + 1;
        let has_non_mill_target = state
            .board
            .iter()
            .enumerate()
            .any(|(idx, piece)| *piece == opponent_piece && !is_piece_in_mill(state, idx));

        for (node, piece) in state.board.iter().enumerate() {
            if *piece != opponent_piece {
                continue;
            }
            if has_non_mill_target && is_piece_in_mill(state, node) {
                continue;
            }
            out.push(Action {
                kind_tag: MillActionKind::Remove as i16,
                from_node: -1,
                to_node: node as i16,
                aux: -1,
                payload_bits: 0,
            });
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
    pending_removals: [u8; 2],
    winner: i8,
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
        payload[28] = self.pending_removals[0];
        payload[29] = self.pending_removals[1];
        payload[30] = self.winner as u8;
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
            pending_removals: [payload[28], payload[29]],
            winner: payload[30] as i8,
        }
    }
}

fn forms_mill(state: &MillState, node: usize, side_to_move: i8) -> bool {
    mill_lines_for_node(node)
        .iter()
        .any(|line| line.iter().all(|idx| state.board[*idx] == side_to_move + 1))
}

fn is_piece_in_mill(state: &MillState, node: usize) -> bool {
    let piece = state.board[node];
    if piece == 0 {
        return false;
    }
    mill_lines_for_node(node)
        .iter()
        .any(|line| line.iter().all(|idx| state.board[*idx] == piece))
}

fn mill_lines_for_node(node: usize) -> Vec<[usize; 3]> {
    STANDARD_MILL_LINES
        .iter()
        .copied()
        .filter(|line| line.contains(&node))
        .collect()
}

const STANDARD_MILL_LINES: &[[usize; 3]] = &[
    [0, 1, 2],
    [2, 3, 4],
    [4, 5, 6],
    [6, 7, 0],
    [8, 9, 10],
    [10, 11, 12],
    [12, 13, 14],
    [14, 15, 8],
    [16, 17, 18],
    [18, 19, 20],
    [20, 21, 22],
    [22, 23, 16],
    [1, 9, 17],
    [3, 11, 19],
    [5, 13, 21],
    [7, 15, 23],
];

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

    #[test]
    fn mill_formation_generates_remove_actions_and_keeps_turn() {
        let rules = MillRules::default();
        let mut snap = rules.initial_state(&[]);

        // Equivalent to the C++ golden scenario:
        // W: d7(1), B: a1(6), W: g7(2), B: d1(5), W: a7(0)
        // White completes a7-d7-g7 and must remove one black piece.
        for node in [1, 6, 2, 5, 0] {
            snap = rules.apply(
                &snap,
                Action {
                    kind_tag: MillActionKind::Place as i16,
                    from_node: -1,
                    to_node: node,
                    aux: -1,
                    payload_bits: 0,
                },
            );
        }

        let state = MillRules::decode(&snap);
        assert_eq!(state.side_to_move, 0, "White keeps turn until removal");
        assert_eq!(state.pending_removals[0], 1);

        let mut actions = ActionList::<256>::new();
        rules.legal_actions(&snap, &mut actions);
        assert_eq!(actions.len(), 2);
        assert!(actions.iter().all(|a| a.kind_tag == MillActionKind::Remove as i16));
        assert!(actions.iter().any(|a| a.to_node == 6)); // a1
        assert!(actions.iter().any(|a| a.to_node == 5)); // d1

        let after_remove = rules.apply(
            &snap,
            Action {
                kind_tag: MillActionKind::Remove as i16,
                from_node: -1,
                to_node: 6,
                aux: -1,
                payload_bits: 0,
            },
        );
        let state = MillRules::decode(&after_remove);
        assert_eq!(state.board[6], 0);
        assert_eq!(state.side_to_move, 1, "Turn passes to black after removal");
        assert_eq!(state.pending_removals[0], 0);
        assert_eq!(state.pieces_on_board[1], 1);
    }

    #[test]
    fn moving_phase_mill_generates_remove_obligation() {
        let rules = MillRules::default();
        let state = MillState {
            // White can move node 1 -> node 0 to complete outer-top mill
            // [0, 1, 2].  Black has enough material that removal is not
            // terminal.
            board: {
                let mut board = [0_i8; 24];
                board[1] = 1; // W d7
                board[2] = 1; // W g7
                board[3] = 1; // W g4 (moving piece)
                board[6] = 2; // B a1
                board[5] = 2; // B d1
                board[10] = 2; // B f6
                board
            },
            side_to_move: 0,
            phase: MillPhase::Moving,
            move_number: 18,
            pieces_in_hand: [0, 0],
            pieces_on_board: [3, 3],
            pending_removals: [0, 0],
            winner: -1,
        };
        let snap = rules.encode(state);
        let after_move = rules.apply(
            &snap,
            Action {
                kind_tag: MillActionKind::Move as i16,
                from_node: 3,
                to_node: 0,
                aux: -1,
                payload_bits: 0,
            },
        );

        let state = MillRules::decode(&after_move);
        assert_eq!(state.side_to_move, 0, "White keeps turn after forming mill");
        assert_eq!(state.pending_removals[0], 1);

        let mut actions = ActionList::<256>::new();
        rules.legal_actions(&after_move, &mut actions);
        assert!(actions.iter().all(|a| a.kind_tag == MillActionKind::Remove as i16));
        assert_eq!(actions.len(), 3);
    }

    #[test]
    fn moving_phase_removal_below_three_ends_game() {
        let rules = MillRules::default();
        let state = MillState {
            board: {
                let mut board = [0_i8; 24];
                board[0] = 1;
                board[1] = 1;
                board[2] = 1;
                board[6] = 2;
                board[5] = 2;
                board
            },
            side_to_move: 0,
            phase: MillPhase::Moving,
            move_number: 20,
            pieces_in_hand: [0, 0],
            pieces_on_board: [3, 2],
            pending_removals: [1, 0],
            winner: -1,
        };
        let snap = rules.encode(state);
        let after_remove = rules.apply(
            &snap,
            Action {
                kind_tag: MillActionKind::Remove as i16,
                from_node: -1,
                to_node: 6,
                aux: -1,
                payload_bits: 0,
            },
        );

        let state = MillRules::decode(&after_remove);
        assert_eq!(state.phase, MillPhase::GameOver);
        assert_eq!(state.winner, 0);
        assert_eq!(state.side_to_move, -1);
        let outcome = rules.outcome(&after_remove);
        assert_eq!(outcome.kind, OutcomeKind::Win(0));
        assert_eq!(outcome.reason, "loseFewerThanThree");
    }

    #[test]
    fn mill_game_workbench_do_and_undo_move() {
        let rules = MillRules::default();
        let game = MillGame::default();
        let snap = rules.initial_state(&[]);
        let mut wb = game.build_workbench(&snap);

        let mut actions = ActionList::<256>::new();
        MillGame::generate_legal(&wb, &mut actions);
        assert_eq!(actions.len(), 24);

        wb.do_move(actions[0]);
        assert_eq!(wb.side_to_move(), 1);
        assert_eq!(wb.state.pieces_in_hand[0], 8);
        assert_eq!(wb.state.pieces_on_board[0], 1);

        wb.undo_move();
        assert_eq!(wb.side_to_move(), 0);
        assert_eq!(wb.state.pieces_in_hand[0], 9);
        assert_eq!(wb.state.pieces_on_board[0], 0);
    }

    #[test]
    fn mill_evaluator_scores_piece_material_from_side_to_move() {
        let rules = MillRules::default();
        let game = MillGame::default();
        let mut snap = rules.initial_state(&[]);
        snap = rules.apply(
            &snap,
            Action {
                kind_tag: MillActionKind::Place as i16,
                from_node: -1,
                to_node: 0,
                aux: -1,
                payload_bits: 0,
            },
        );
        let wb = game.build_workbench(&snap);
        // Material is equal (white has 8 in hand + 1 on board, black has 9 in
        // hand), so score is zero from black-to-move perspective.
        assert_eq!(MillEvaluator::score(&wb), 0);
    }
}
