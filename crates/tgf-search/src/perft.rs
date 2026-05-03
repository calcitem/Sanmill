// SPDX-License-Identifier: GPL-3.0-or-later
// Game-neutral perft (performance test).

use tgf_core::{ActionList, Game, Workbench};

/// Game-neutral perft: counts the leaves of the legal-action tree at the
/// requested depth.  At depth 0 we count the current node as one leaf; at
/// depth 1 we count the number of immediately legal actions.  This matches
/// the standard perft contract used by the mature C++ engine for parity
/// regression testing.
pub fn perft<G: Game>(wb: &mut G::Workbench, depth: i32) -> u64 {
    if depth <= 0 || wb.is_terminal() {
        return 1;
    }
    let mut moves = ActionList::<256>::new();
    G::generate_legal(wb, &mut moves);
    if moves.is_empty() {
        return 1;
    }
    let mut nodes = 0_u64;
    for action in moves {
        wb.do_move(action);
        nodes += perft::<G>(wb, depth - 1);
        wb.undo_move();
    }
    nodes
}
