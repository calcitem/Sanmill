// SPDX-License-Identifier: AGPL-3.0-or-later
// Root-position analysis for puzzle generation: shortest/slower/non-winning
// logical-turn classification, tempting-trap detection, symmetry-canonical
// dedup keys, and a heuristic "human difficulty" probe.
//
// A useful puzzle needs both a precise best continuation and plausible
// alternatives. The helpers below measure those properties without treating
// a structural pattern or heuristic search result as proof.

use perfect_db::database::PerfectQuery;
use perfect_db::index::symmetry::{SYMMETRY_COUNT, transform24};
use perfect_db::{PerfectLogicalTurnChoice, PerfectMoveOrdering};
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

/// Deterministic work budget for each heuristic difficulty probe.
///
/// Perfect DB remains the correctness authority. The search probe is only a
/// human-difficulty signal, so a fixed node cap prevents one strategically
/// dense position from stalling an offline generation batch while keeping
/// repeated runs reproducible.
pub(super) const PROBE_NODE_LIMIT: u64 = 5_000;

/// Classification of every complete legal root turn by Perfect DB outcome.
#[derive(Debug, Clone)]
pub(super) struct RootTurnBreakdown {
    /// Every complete first turn tied for the shortest forced win.
    pub shortest_winning: Vec<PerfectLogicalTurnChoice>,
    /// Complete first turns that still force a win but take longer.
    pub slower_winning: Vec<PerfectLogicalTurnChoice>,
    /// Complete first turns that lead only to a draw or loss.
    pub non_winning_count: usize,
    /// At least one non-winning turn starts by closing a mill: the greedy,
    /// natural-looking capture is exactly the choice that spoils the win.
    pub tempting_mill_mistake: bool,
    /// No shortest winning first turn forms a mill immediately, so the
    /// solution starts with a quiet move.
    pub quiet_first_move: bool,
}

impl RootTurnBreakdown {
    /// Number of legal turns that fail to achieve the shortest forced win.
    pub fn non_shortest_count(&self) -> usize {
        self.slower_winning.len() + self.non_winning_count
    }
}

/// Classify every complete legal root turn against its Perfect DB outcome.
///
/// A mill-forming primary action and its compulsory removal remain one
/// classification unit, so a good primary action followed by a bad capture
/// cannot be mistaken for a correct solution.
pub(super) fn classify_root_turns(
    rules: &MillRules,
    snap: &GameStateSnapshot,
    turns: &[PerfectLogicalTurnChoice],
    root_side: i8,
) -> RootTurnBreakdown {
    let best_winning_outcome = turns
        .iter()
        .filter(|choice| choice.outcome.wdl() == 1)
        .map(|choice| choice.outcome)
        .max_by(|left, right| PerfectMoveOrdering::StrictSteps.compare(*left, *right))
        .expect("a forced-win root must expose at least one winning logical turn");

    let mut shortest_winning = Vec::new();
    let mut slower_winning = Vec::new();
    let mut non_winning_count = 0usize;
    let mut tempting_mill_mistake = false;
    let mut any_shortest_winning_mill = false;
    for choice in turns {
        assert!(
            !choice.actions.is_empty(),
            "a complete logical turn must contain at least one action"
        );
        let closes = closes_mill(rules, snap, choice.actions[0], root_side);
        if choice.outcome.wdl() != 1 {
            non_winning_count += 1;
            tempting_mill_mistake |= closes;
        } else if PerfectMoveOrdering::StrictSteps
            .compare(choice.outcome, best_winning_outcome)
            .is_eq()
        {
            shortest_winning.push(choice.clone());
            any_shortest_winning_mill |= closes;
        } else {
            slower_winning.push(choice.clone());
        }
    }

    RootTurnBreakdown {
        quiet_first_move: !shortest_winning.is_empty() && !any_shortest_winning_mill,
        shortest_winning,
        slower_winning,
        non_winning_count,
        tempting_mill_mistake,
    }
}

/// True when playing `action` forms a mill for `mover`, i.e. the same side
/// keeps the move and owes a removal. This is the "tempting" move shape:
/// closing a mill and capturing looks like progress even when the database
/// says it throws the win away.
pub(super) fn closes_mill(
    rules: &MillRules,
    snap: &GameStateSnapshot,
    action: Action,
    mover: i8,
) -> bool {
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

/// Canonical editorial-comparison key with the solver normalised to White.
///
/// The regular generation key deliberately keeps colours distinct because
/// side to move and hand counts are part of a puzzle's identity. Editorial
/// collision checks are stricter: the same solver/defender structure remains
/// recognisable when every colour and the side to move are exchanged.
#[cfg(test)]
pub(super) fn canonical_solver_symmetry_key(query: &PerfectQuery) -> u64 {
    let (solver, defender, solver_in_hand, defender_in_hand) = if query.side_to_move == 0 {
        (
            query.white_bits,
            query.black_bits,
            query.white_in_hand,
            query.black_in_hand,
        )
    } else {
        (
            query.black_bits,
            query.white_bits,
            query.black_in_hand,
            query.white_in_hand,
        )
    };
    assert!(
        solver_in_hand < 16 && defender_in_hand < 16,
        "hand counts must fit the 4-bit key fields"
    );

    let mut best = u64::MAX;
    for op in 0..SYMMETRY_COUNT as u8 {
        let solver = u64::from(transform24(op, solver));
        let defender = u64::from(transform24(op, defender));
        let key = solver
            | (defender << 24)
            | (u64::from(solver_in_hand) << 48)
            | (u64::from(defender_in_hand) << 52);
        best = best.min(key);
    }
    best
}

/// Search options for the difficulty probe: a deterministic, no-frills PVS
/// at full skill, matching how the in-app engine examines a position.
pub(super) fn heuristic_search_options() -> SearchOptions {
    SearchOptions {
        depth_extension: true,
        node_limit: Some(PROBE_NODE_LIMIT),
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
    rules: &MillRules,
    game: &MillGame,
    snap: &GameStateSnapshot,
    winning: &[Vec<Action>],
    seed: u64,
) -> Option<i32> {
    assert!(
        !winning.is_empty(),
        "difficulty probe requires at least one winning root move"
    );
    for &depth in PROBE_DEPTHS.iter() {
        let mut current = *snap;
        let root_side = current.side_to_move;
        let mut chosen_turn = Vec::new();
        loop {
            let mut workbench = game.build_workbench(&current);
            let mut searcher = Searcher::<MillGame>::new();
            searcher.set_options(heuristic_search_options());
            searcher.set_policy(SearchPolicy {
                quiescence_kind_tag: Some(MillActionKind::Remove as i16),
                ..Default::default()
            });
            searcher.set_random_seed(seed ^ chosen_turn.len() as u64);
            let result = searcher.search_pvs(&mut workbench, depth);
            chosen_turn.push(result.best_action);
            current = rules.apply(&current, result.best_action);
            if rules.outcome(&current).kind != tgf_core::OutcomeKind::Ongoing
                || current.side_to_move != root_side
            {
                break;
            }
            assert!(
                chosen_turn.len() < 12,
                "one Mill logical turn cannot contain twelve actions"
            );
        }
        if winning.contains(&chosen_turn) {
            return Some(depth);
        }
    }
    None
}
