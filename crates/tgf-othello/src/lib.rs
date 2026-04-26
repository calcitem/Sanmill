// SPDX-License-Identifier: GPL-3.0-or-later
// Othello/Reversi pressure-test implementation for TGF.

use tgf_core::{
    Action, ActionList, BoardTopology, Edge, Evaluator, Game, GameRules,
    GameStateSnapshot, Outcome, OutcomeKind, UnitPoint, Workbench, Zone,
};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(i16)]
pub enum OthelloActionKind {
    Place = 0,
}

#[derive(Clone, Debug, Default)]
pub struct OthelloGame;

#[derive(Clone, Debug, Default)]
pub struct OthelloRules {
    topology: OthelloTopology,
}

#[derive(Clone, Debug)]
pub struct OthelloWorkbench {
    rules: OthelloRules,
    state: OthelloState,
    undo_stack: Vec<OthelloState>,
}

pub struct OthelloEvaluator;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct OthelloState {
    board: [i8; 64],
    side_to_move: i8,
    move_number: i16,
}

impl Default for OthelloState {
    fn default() -> Self {
        let mut board = [0_i8; 64];
        board[idx(3, 3)] = 2;
        board[idx(4, 4)] = 2;
        board[idx(3, 4)] = 1;
        board[idx(4, 3)] = 1;
        Self {
            board,
            side_to_move: 0,
            move_number: 0,
        }
    }
}

impl OthelloRules {
    fn encode(&self, state: OthelloState) -> GameStateSnapshot {
        let mut payload = [0_u8; 256];
        for (i, piece) in state.board.iter().enumerate() {
            payload[i] = *piece as u8;
        }
        GameStateSnapshot {
            side_to_move: state.side_to_move,
            phase_tag: 0,
            move_number: state.move_number,
            zobrist_key: othello_key(&state),
            opaque_payload: payload,
        }
    }

    fn decode(snapshot: &GameStateSnapshot) -> OthelloState {
        let mut board = [0_i8; 64];
        for (i, slot) in board.iter_mut().enumerate() {
            *slot = snapshot.opaque_payload[i] as i8;
        }
        OthelloState {
            board,
            side_to_move: snapshot.side_to_move,
            move_number: snapshot.move_number,
        }
    }

    fn legal_actions_for(state: &OthelloState, out: &mut ActionList<256>) {
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
        self.encode(OthelloState::default())
    }

    fn legal_actions(&self, snap: &GameStateSnapshot, out: &mut ActionList<256>) {
        Self::legal_actions_for(&Self::decode(snap), out);
    }

    fn apply(&self, snap: &GameStateSnapshot, action: Action) -> GameStateSnapshot {
        let mut state = Self::decode(snap);
        apply_othello_action(&mut state, action);
        self.encode(state)
    }

    fn outcome(&self, _snap: &GameStateSnapshot) -> Outcome {
        Outcome {
            kind: OutcomeKind::Ongoing,
            reason: "ongoing".to_owned(),
        }
    }
}

impl Workbench for OthelloWorkbench {
    fn snapshot(&self) -> GameStateSnapshot {
        self.rules.encode(self.state)
    }

    fn key(&self) -> u64 {
        othello_key(&self.state)
    }

    fn side_to_move(&self) -> i8 {
        self.state.side_to_move
    }

    fn is_terminal(&self) -> bool {
        let mut list = ActionList::<256>::new();
        OthelloRules::legal_actions_for(&self.state, &mut list);
        list.is_empty()
    }

    fn do_move(&mut self, a: Action) {
        self.undo_stack.push(self.state);
        apply_othello_action(&mut self.state, a);
    }

    fn undo_move(&mut self) {
        if let Some(prev) = self.undo_stack.pop() {
            self.state = prev;
        }
    }
}

impl Evaluator<OthelloWorkbench> for OthelloEvaluator {
    fn score(wb: &OthelloWorkbench) -> i32 {
        let own = wb.state.side_to_move + 1;
        let opp = (wb.state.side_to_move ^ 1) + 1;
        let own_count = wb.state.board.iter().filter(|p| **p == own).count() as i32;
        let opp_count = wb.state.board.iter().filter(|p| **p == opp).count() as i32;
        (own_count - opp_count) * 100
    }
}

impl Game for OthelloGame {
    type Workbench = OthelloWorkbench;
    type Evaluator = OthelloEvaluator;

    fn build_workbench(&self, snap: &GameStateSnapshot) -> Self::Workbench {
        OthelloWorkbench {
            rules: OthelloRules::default(),
            state: OthelloRules::decode(snap),
            undo_stack: Vec::new(),
        }
    }

    fn generate_legal(wb: &Self::Workbench, out: &mut ActionList<256>) {
        OthelloRules::legal_actions_for(&wb.state, out);
    }
}

#[derive(Clone, Debug)]
pub struct OthelloTopology {
    points: Vec<UnitPoint>,
    edges: Vec<Edge>,
    zones: Vec<Zone>,
}

impl Default for OthelloTopology {
    fn default() -> Self {
        let points = (0..64)
            .map(|i| UnitPoint {
                x: (i % 8) as f32 / 7.0,
                y: (i / 8) as f32 / 7.0,
            })
            .collect::<Vec<_>>();
        let mut edges = Vec::new();
        for r in 0..8 {
            for c in 0..8 {
                if c < 7 {
                    edges.push(Edge {
                        a: idx(c, r) as u16,
                        b: idx(c + 1, r) as u16,
                    });
                }
                if r < 7 {
                    edges.push(Edge {
                        a: idx(c, r) as u16,
                        b: idx(c, r + 1) as u16,
                    });
                }
            }
        }
        Self {
            points,
            edges,
            zones: Vec::new(),
        }
    }
}

impl BoardTopology for OthelloTopology {
    fn name(&self) -> &str {
        "othello.8x8"
    }

    fn node_count(&self) -> u16 {
        64
    }

    fn coordinate_of(&self, node: u16) -> UnitPoint {
        self.points[node as usize]
    }

    fn label_of(&self, _node: u16) -> &str {
        ""
    }

    fn node_from_label(&self, _label: &str) -> Option<u16> {
        None
    }

    fn neighbors(&self, _node: u16) -> &[u16] {
        &[]
    }

    fn edges(&self) -> &[Edge] {
        &self.edges
    }

    fn line_groups(&self) -> &[Vec<u16>] {
        &[]
    }

    fn zones(&self) -> &[Zone] {
        &self.zones
    }

    fn decorations(&self) -> &[tgf_core::Decoration] {
        &[]
    }
}

fn apply_othello_action(state: &mut OthelloState, action: Action) {
    let sq = action.to_node as usize;
    let (count, dirs) = would_flip(state, sq);
    debug_assert!(count > 0, "illegal Othello action");
    let own = state.side_to_move + 1;
    state.board[sq] = own;
    for (dx, dy) in dirs {
        let mut c = (sq % 8) as i32 + dx;
        let mut r = (sq / 8) as i32 + dy;
        while in_bounds(c, r) {
            let i = idx(c as usize, r as usize);
            if state.board[i] == own {
                break;
            }
            state.board[i] = own;
            c += dx;
            r += dy;
        }
    }
    state.side_to_move ^= 1;
    state.move_number += 1;
}

fn would_flip(state: &OthelloState, sq: usize) -> (usize, Vec<(i32, i32)>) {
    if state.board[sq] != 0 {
        return (0, Vec::new());
    }
    let own = state.side_to_move + 1;
    let opp = (state.side_to_move ^ 1) + 1;
    let mut total = 0_usize;
    let mut dirs = Vec::new();
    for dy in -1..=1 {
        for dx in -1..=1 {
            if dx == 0 && dy == 0 {
                continue;
            }
            let mut count = 0_usize;
            let mut c = (sq % 8) as i32 + dx;
            let mut r = (sq / 8) as i32 + dy;
            while in_bounds(c, r) {
                let piece = state.board[idx(c as usize, r as usize)];
                if piece == opp {
                    count += 1;
                } else if piece == own && count > 0 {
                    total += count;
                    dirs.push((dx, dy));
                    break;
                } else {
                    break;
                }
                c += dx;
                r += dy;
            }
        }
    }
    (total, dirs)
}

fn idx(c: usize, r: usize) -> usize {
    r * 8 + c
}

fn in_bounds(c: i32, r: i32) -> bool {
    (0..8).contains(&c) && (0..8).contains(&r)
}

fn othello_key(state: &OthelloState) -> u64 {
    let mut key = 0xcbf2_9ce4_8422_2325_u64;
    let mut mix = |byte: u8| {
        key ^= u64::from(byte);
        key = key.wrapping_mul(0x1000_0000_01b3);
    };
    for piece in state.board {
        mix(piece as u8);
    }
    mix(state.side_to_move as u8);
    mix((state.move_number & 0xff) as u8);
    mix(((state.move_number >> 8) & 0xff) as u8);
    if key == 0 {
        1
    } else {
        key
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tgf_core::Game;
    use tgf_search::{perft, Searcher};

    #[test]
    fn initial_othello_has_four_legal_actions() {
        let rules = OthelloRules::default();
        let snap = rules.initial_state(&[]);
        let mut actions = ActionList::<256>::new();
        rules.legal_actions(&snap, &mut actions);
        assert_eq!(actions.len(), 4);
    }

    #[test]
    fn applying_opening_action_flips_one_disc() {
        let rules = OthelloRules::default();
        let snap = rules.initial_state(&[]);
        let mut actions = ActionList::<256>::new();
        rules.legal_actions(&snap, &mut actions);
        let next = rules.apply(&snap, actions[0]);
        let state = OthelloRules::decode(&next);
        let black = state.board.iter().filter(|p| **p == 1).count();
        let white = state.board.iter().filter(|p| **p == 2).count();
        assert_eq!(black, 4);
        assert_eq!(white, 1);
    }

    #[test]
    fn searcher_works_with_othello_game() {
        let rules = OthelloRules::default();
        let game = OthelloGame;
        let snap = rules.initial_state(&[]);
        let mut wb = game.build_workbench(&snap);
        assert_eq!(perft::<OthelloGame>(&mut wb, 1), 4);
        let mut searcher = Searcher::<OthelloGame>::new();
        let result = searcher.search(&mut wb, 1);
        assert!(!result.best_action.is_none());
    }
}
