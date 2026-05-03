// SPDX-License-Identifier: GPL-3.0-or-later
// Othello board state plus the snapshot encode / decode round-trip.

use tgf_core::{GameStateSnapshot, OPAQUE_PAYLOAD_LEN};

use super::topology::{idx, in_bounds};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct OthelloState {
    pub(crate) board: [i8; 64],
    pub(crate) side_to_move: i8,
    pub(crate) move_number: i16,
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

pub(crate) fn encode(state: OthelloState) -> GameStateSnapshot {
    let mut payload = [0_u8; OPAQUE_PAYLOAD_LEN];
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

pub(crate) fn decode(snapshot: &GameStateSnapshot) -> OthelloState {
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

pub(crate) fn othello_key(state: &OthelloState) -> u64 {
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

/// Apply an Othello place-and-flip action.  Caller must ensure the
/// move is legal (`would_flip` would return `(>0, _)`); the rules
/// trait validates legality before delegating here.
pub(crate) fn apply_othello_action(state: &mut OthelloState, action: tgf_core::Action) {
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

/// Returns the number of opponent pieces that placing on `sq` would
/// flip, paired with the directions in which flips occur.  Empty
/// directions and squares that already hold a piece return `(0, [])`.
pub(crate) fn would_flip(state: &OthelloState, sq: usize) -> (usize, Vec<(i32, i32)>) {
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
