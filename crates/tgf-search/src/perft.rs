// SPDX-License-Identifier: GPL-3.0-or-later
// Game-neutral perft (performance test).
//
// Three flavours are exposed:
//
//   * `perft`              — classic leaf-count at depth N.
//   * `perft_split`        — per-root-move leaf counts, the "splitperft"
//                            output most chess / checkers test suites
//                            consume to localise mismatches.
//   * `perft_unique_keys`  — count of distinct Zobrist keys reached at
//                            depth N, useful for cheap fuzz-detection of
//                            hash collisions and movement-rule symmetry
//                            bugs.
//
// All three are pure walk routines and never touch the searcher's
// transposition table, killers or evaluator.

use std::collections::HashSet;

use tgf_core::{Action, ActionList, Game, Workbench};

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

/// Per-root-move leaf counts at the requested depth.  Returned as a
/// `Vec<(Action, u64)>` so callers can report mismatches alongside the
/// offending root move (the standard chess "splitperft" workflow).
///
/// `depth` is the *total* search depth; a single ply is consumed by the
/// root expansion before delegating to [`perft`].  When `depth <= 0` or
/// `wb` is already terminal the routine returns an empty vector.
pub fn perft_split<G: Game>(wb: &mut G::Workbench, depth: i32) -> Vec<(Action, u64)> {
    if depth <= 0 || wb.is_terminal() {
        return Vec::new();
    }
    let mut moves = ActionList::<256>::new();
    G::generate_legal(wb, &mut moves);
    if moves.is_empty() {
        return Vec::new();
    }
    let mut out = Vec::with_capacity(moves.len());
    for action in moves {
        wb.do_move(action);
        let leaves = perft::<G>(wb, depth - 1);
        wb.undo_move();
        out.push((action, leaves));
    }
    out
}

/// Count distinct `Workbench::key()` values reached when expanding the
/// legal-action tree to `depth`.  Useful as an independent sanity
/// signal:
///   * collisions with the perft leaf count usually indicate a
///     transposition rather than a bug;
///   * counts dropping below a known-good baseline often surface
///     movement-rule symmetry regressions.
///
/// Allocations: a single `HashSet<u64>` whose size is bounded by the
/// distinct-position count.  Cold path; callers are expected to use
/// this from tests / fuzz harnesses, not from search hot loops.
pub fn perft_unique_keys<G: Game>(wb: &mut G::Workbench, depth: i32) -> usize {
    let mut seen = HashSet::<u64>::new();
    fill_unique_keys::<G>(wb, depth, &mut seen);
    seen.len()
}

fn fill_unique_keys<G: Game>(wb: &mut G::Workbench, depth: i32, out: &mut HashSet<u64>) {
    if depth == 0 || wb.is_terminal() {
        out.insert(wb.key());
        return;
    }
    let mut moves = ActionList::<256>::new();
    G::generate_legal(wb, &mut moves);
    if moves.is_empty() {
        out.insert(wb.key());
        return;
    }
    for action in moves {
        wb.do_move(action);
        fill_unique_keys::<G>(wb, depth - 1, out);
        wb.undo_move();
    }
}
