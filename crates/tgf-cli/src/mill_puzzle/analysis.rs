// SPDX-License-Identifier: AGPL-3.0-or-later
// Root-position analysis for puzzle generation: winning/mistake move
// classification, tempting-trap detection, symmetry-canonical dedup keys,
// and a heuristic "human difficulty" probe.
//
// The guiding principle (borrowed from the puzzle chapter of Brandwood's
// "Nine Men's Morris: Strategy") is that a position only makes an
// interesting puzzle when wrong moves exist *and* look attractive:
// "Can White play a mill and win?" -- where the answer is often no -- and
// "all other moves lead to losing trajectories". The helpers below measure
// exactly those properties so the generator can filter for them.

use perfect_db::PerfectMoveChoice;
use perfect_db::database::PerfectQuery;
use perfect_db::index::symmetry::{SYMMETRY_COUNT, transform24};
use tgf_core::{Action, Game, GameRules, GameStateSnapshot, MoveOrderAlgorithm, MoveOrderContext};
use tgf_mill::{MillActionKind, MillGame, MillRules};
use tgf_search::{SearchOptions, SearchPolicy, Searcher};

/// Heuristic-search depths granted to the simulated human solver, from
/// casual to strong club level. [`shallowest_solving_depth`] walks them in
/// ascending order; the first depth whose principal move keeps the forced
/// win is the puzzle's "solve depth". A puzzle that falls to the depth-2
/// probe is a one-glance tactic; one that survives every probe needs
/// database-grade precision.
pub(super) const PROBE_DEPTHS: [i32; 4] = [2, 4, 6, 8];

/// Classification of every legal root move by Perfect DB outcome.
#[derive(Debug, Clone)]
pub(super) struct RootMoveBreakdown {
    /// Moves that keep the forced win alive.
    pub winning: Vec<Action>,
    /// Legal moves that immediately throw the forced win away (they lead
    /// to a draw or a loss). These are the puzzle's "error budget": with
    /// no mistakes available the position solves itself.
    pub mistake_count: usize,
    /// At least one mistake closes a mill: the greedy, natural-looking
    /// capture is exactly the move that spoils the win.
    pub tempting_mill_mistake: bool,
    /// No winning first move forms a mill immediately, so the solution
    /// starts with a quiet move -- which humans overlook far more often
    /// than a capture.
    pub quiet_first_move: bool,
}

/// Classify every legal root move against its Perfect DB outcome.
///
/// `legal` and `outcomes` must be the aligned 1:1 pair produced by
/// `GameRules::legal_actions` and `all_move_outcomes_with_ordering`.
pub(super) fn classify_root_moves(
    rules: &MillRules,
    snap: &GameStateSnapshot,
    legal: &[Action],
    outcomes: &[PerfectMoveChoice],
    root_side: i8,
) -> RootMoveBreakdown {
    assert_eq!(
        legal.len(),
        outcomes.len(),
        "move outcome enumeration must align 1:1 with legal_actions"
    );

    let mut winning = Vec::new();
    let mut mistake_count = 0usize;
    let mut tempting_mill_mistake = false;
    let mut any_winning_mill = false;
    for (&action, choice) in legal.iter().zip(outcomes) {
        let closes = closes_mill(rules, snap, action, root_side);
        if choice.outcome.wdl() == 1 {
            winning.push(action);
            any_winning_mill |= closes;
        } else {
            mistake_count += 1;
            tempting_mill_mistake |= closes;
        }
    }

    RootMoveBreakdown {
        quiet_first_move: !winning.is_empty() && !any_winning_mill,
        winning,
        mistake_count,
        tempting_mill_mistake,
    }
}

/// True when playing `action` forms a mill for `mover`, i.e. the same side
/// keeps the move and owes a removal. This is the "tempting" move shape:
/// closing a mill and capturing looks like progress even when the database
/// says it throws the win away.
fn closes_mill(rules: &MillRules, snap: &GameStateSnapshot, action: Action, mover: i8) -> bool {
    if action.kind_tag == MillActionKind::Remove as i16 {
        return false;
    }
    let child = rules.apply(snap, action);
    child.side_to_move == mover
        && MillRules::decode_snapshot(child).pending_removals()[mover as usize] > 0
}

/// Canonical dedup key of a root position under the 16 board symmetries.
///
/// Two sampled roots that are rotations/reflections of each other make the
/// same puzzle in different clothes; the generator keeps only one. Piece
/// colors are *not* swapped: hand counts and side to move give the colors
/// asymmetric roles, so color-swapped positions are genuinely different
/// puzzles.
pub(super) fn canonical_symmetry_key(query: &PerfectQuery) -> u64 {
    let mut best = u64::MAX;
    for op in 0..SYMMETRY_COUNT as u8 {
        let white = u64::from(transform24(op, query.white_bits));
        let black = u64::from(transform24(op, query.black_bits));
        // 24 + 24 + 4 + 4 + 1 bits; hand counts stay below 16 for every
        // supported variant (9/10/12 pieces).
        assert!(
            query.white_in_hand < 16 && query.black_in_hand < 16,
            "hand counts must fit the 4-bit key fields"
        );
        let key = white
            | (black << 24)
            | (u64::from(query.white_in_hand) << 48)
            | (u64::from(query.black_in_hand) << 52)
            | (u64::from(query.side_to_move) << 56);
        best = best.min(key);
    }
    best
}

/// Search options shared by the opponent model and the difficulty probe:
/// a deterministic, no-frills PVS at full skill, matching how the in-app
/// engine plays a position out.
pub(super) fn heuristic_search_options() -> SearchOptions {
    SearchOptions {
        depth_extension: true,
        node_limit: None,
        time_limit_ms: None,
        allow_null_move: false,
        shuffle_root: false,
        enable_prefetch: false,
        prefetch_all: false,
        enable_aspiration_window: false,
        move_order_context: MoveOrderContext {
            algorithm: MoveOrderAlgorithm::Pvs,
            skill_level: 30,
            shuffling: false,
            hash_move: None,
            shuffle_seed: 0,
        },
    }
}

/// Simulate a human solver of increasing strength and report the
/// shallowest [`PROBE_DEPTHS`] entry whose best move keeps the forced win.
///
/// Returns `None` when even the deepest probe picks a losing or drawing
/// move -- the puzzle then requires database-grade precision to solve, the
/// strongest possible difficulty signal.
pub(super) fn shallowest_solving_depth(
    game: &MillGame,
    snap: &GameStateSnapshot,
    winning: &[Action],
    seed: u64,
) -> Option<i32> {
    assert!(
        !winning.is_empty(),
        "difficulty probe requires at least one winning root move"
    );
    for &depth in PROBE_DEPTHS.iter() {
        let mut workbench = game.build_workbench(snap);
        let mut searcher = Searcher::<MillGame>::new();
        searcher.set_options(heuristic_search_options());
        searcher.set_policy(SearchPolicy {
            quiescence_kind_tag: Some(MillActionKind::Remove as i16),
            ..Default::default()
        });
        searcher.set_random_seed(seed);
        let result = searcher.search_pvs(&mut workbench, depth);
        if winning.contains(&result.best_action) {
            return Some(depth);
        }
    }
    None
}
