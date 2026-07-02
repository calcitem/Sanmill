// SPDX-License-Identifier: AGPL-3.0-or-later
// Builds a single concrete puzzle solution line.
//
// The solving side always plays the Perfect DB's fastest winning move; the
// opponent always plays the heuristic engine's best reply -- never the DB's
// best *defense*. This mirrors the property the puzzle generator is asked
// for: a puzzle must still work when the opponent responds the way a real
// (non-perfect) player actually would, not with the theoretically most
// stubborn (and often unnatural) defense.
//
// While playing the line out, this module also collects the tactical
// fingerprint that later drives difficulty rating and puzzle prose: how
// many solver decisions had exactly one winning choice, whether the solver
// chains mills on consecutive moves, whether the opponent reached the
// flying stage and still lost, and whether the final blow was
// immobilization rather than material.

use perfect_db::database::{Database, DatabaseProvider};
use perfect_db::{PerfectMoveOrdering, all_move_outcomes_with_ordering};
use tgf_core::{Action, ActionList, Game, GameRules, GameStateSnapshot, OutcomeKind};
use tgf_mill::{MillActionKind, MillGame, MillPhase, MillRules, MillUciCodec, MillVariantOptions};
use tgf_search::{SearchPolicy, Searcher};

use super::analysis::heuristic_search_options;

/// One ply of a constructed solution line, in absolute board notation.
#[derive(Debug, Clone)]
pub(crate) struct SolutionPly {
    pub notation: String,
    /// Absolute side that played this ply: 0 = white, 1 = black.
    pub side: i8,
}

/// A fully played-out forced-win line starting from a specific first move.
#[derive(Debug, Clone)]
pub(crate) struct BuiltSolution {
    pub plies: Vec<SolutionPly>,
    /// Number of plies belonging to the solving side. Matches how the
    /// Flutter app's `PuzzleSolution.getPlayerMoveCount` counts moves: every
    /// entry belonging to the solver -- including a removal right after the
    /// solver forms a mill -- counts as one "move".
    pub solver_move_count: i32,
    /// True when the opponent captured one of the solving side's pieces at
    /// some point in the line: the solver had to accept a material
    /// sacrifice to keep the forced win alive.
    pub sacrifice: bool,
    /// Solver decision points after the forced first move where exactly one
    /// available action kept the win. High counts mean the line demands
    /// precision the whole way, not just at the first move.
    pub only_move_count: i32,
    /// Total solver decision points examined for [`Self::only_move_count`].
    pub decision_point_count: i32,
    /// The solver closed mills on two consecutive solver moves -- the
    /// classic swing/double-mill motif.
    pub double_mill: bool,
    /// The opponent reached the flying stage (down to the fly threshold in
    /// the moving phase) and still could not save the game.
    pub vs_flying: bool,
    /// The final win came by leaving the opponent without a legal move
    /// (herding/immobilization), not by capturing below three pieces.
    pub immobilization_win: bool,
}

/// Safety cap on plies per constructed line. Real Mill forced wins within
/// the puzzle-relevant depth range (a handful of moves per side) resolve
/// in well under this; hitting it indicates the heuristic opponent and the
/// Perfect DB disagree about the position being lost, so the candidate is
/// discarded rather than trusted.
const MAX_SOLUTION_PLIES: usize = 60;

/// Play out a forced-win line from `root_snap`, where `solver_side` commits
/// to `first_action` and then keeps playing the Perfect DB's fastest
/// winning move, while the opponent always plays the heuristic searcher's
/// choice at `opponent_depth`.
///
/// Returns `None` when the line cannot be completed cleanly: the Perfect DB
/// does not cover a position the line reaches, the safety ply cap is hit,
/// or the game does not end in a win for `solver_side`. All of these are
/// expected, ordinary outcomes during random sampling -- the caller simply
/// tries another sampled position.
#[allow(clippy::too_many_arguments)]
pub(crate) fn build_solution_line<P: DatabaseProvider>(
    database: &mut Database<P>,
    rules: &MillRules,
    game: &MillGame,
    options: &MillVariantOptions,
    opponent_depth: i32,
    opponent_seed: u64,
    root_snap: GameStateSnapshot,
    solver_side: i8,
    first_action: Action,
) -> Option<BuiltSolution> {
    assert!(
        solver_side == 0 || solver_side == 1,
        "puzzle solver side must be white or black"
    );

    let mut snap = root_snap;
    let mut plies: Vec<SolutionPly> = Vec::new();
    let mut sacrifice = false;
    let mut only_move_count = 0i32;
    let mut decision_point_count = 0i32;
    let mut double_mill = false;
    let mut vs_flying = false;
    let mut forced_next = Some(first_action);
    // `Some(closed)` after each solver place/move; two consecutive `true`
    // values are the swing-mill motif.
    let mut prev_solver_move_closed_mill: Option<bool> = None;

    let mut searcher = Searcher::<MillGame>::new();
    searcher.set_options(heuristic_search_options());
    searcher.set_policy(SearchPolicy {
        quiescence_kind_tag: Some(MillActionKind::Remove as i16),
        ..Default::default()
    });
    searcher.set_random_seed(opponent_seed);

    for _ in 0..MAX_SOLUTION_PLIES {
        if rules.outcome(&snap).kind != OutcomeKind::Ongoing {
            break;
        }
        let mover = snap.side_to_move;
        assert!(
            mover == 0 || mover == 1,
            "puzzle solution ply must have a definite side to move while ongoing"
        );

        let action = if let Some(forced) = forced_next.take() {
            forced
        } else if mover == solver_side {
            pick_solver_action(
                database,
                rules,
                &snap,
                options,
                &mut only_move_count,
                &mut decision_point_count,
            )?
        } else {
            let state = MillRules::decode_snapshot(snap);
            if options.may_fly
                && state.phase() == MillPhase::Moving
                && state.pieces_on_board()[mover as usize] <= options.fly_piece_count
            {
                vs_flying = true;
            }
            let mut workbench = game.build_workbench(&snap);
            let result = searcher.search_pvs(&mut workbench, opponent_depth);
            if result.best_action.is_none() {
                return None;
            }
            result.best_action
        };

        if mover != solver_side && action.kind_tag == MillActionKind::Remove as i16 {
            sacrifice = true;
        }

        plies.push(SolutionPly {
            notation: MillUciCodec::encode_action(action),
            side: mover,
        });
        snap = rules.apply(&snap, action);

        if mover == solver_side && action.kind_tag != MillActionKind::Remove as i16 {
            let closed = snap.side_to_move == solver_side
                && MillRules::decode_snapshot(snap).pending_removals()[solver_side as usize] > 0;
            if closed && prev_solver_move_closed_mill == Some(true) {
                double_mill = true;
            }
            prev_solver_move_closed_mill = Some(closed);
        }
    }

    if rules.outcome(&snap).kind != OutcomeKind::Win(solver_side) {
        return None;
    }

    // If the loser still holds at least the survival threshold in material,
    // the win must have come from running them out of legal moves.
    let final_state = MillRules::decode_snapshot(snap);
    let opponent = (1 - solver_side) as usize;
    let immobilization_win =
        final_state.pieces_on_board()[opponent] >= options.pieces_at_least_count;

    let solver_move_count = plies.iter().filter(|p| p.side == solver_side).count() as i32;
    Some(BuiltSolution {
        plies,
        solver_move_count,
        sacrifice,
        only_move_count,
        decision_point_count,
        double_mill,
        vs_flying,
        immobilization_win,
    })
}

/// Choose the solver's move at one decision point: enumerate every legal
/// action's Perfect DB outcome, record only-move statistics, and return the
/// fastest winning action (first among strict-step ties, matching the
/// deterministic order `best_move_choice_with_ordering` used previously).
fn pick_solver_action<P: DatabaseProvider>(
    database: &mut Database<P>,
    rules: &MillRules,
    snap: &GameStateSnapshot,
    options: &MillVariantOptions,
    only_move_count: &mut i32,
    decision_point_count: &mut i32,
) -> Option<Action> {
    let outcomes = match all_move_outcomes_with_ordering(
        database,
        rules,
        snap,
        options,
        PerfectMoveOrdering::StrictSteps,
    ) {
        Ok(Some(outcomes)) => outcomes,
        Ok(None) => return None,
        Err(err) if err.is_missing_asset() => return None,
        Err(err) => {
            panic!("[puzzle-gen] Perfect DB error while extending the solving side's line: {err}")
        }
    };

    let mut legal = ActionList::<256>::new();
    rules.legal_actions(snap, &mut legal);
    assert_eq!(
        legal.as_slice().len(),
        outcomes.len(),
        "move outcome enumeration must align 1:1 with legal_actions"
    );

    let winning_here = outcomes.iter().filter(|c| c.outcome.wdl() == 1).count();
    assert!(
        winning_here >= 1,
        "a forced-win line must keep at least one winning move at every solver decision"
    );
    *decision_point_count += 1;
    if winning_here == 1 {
        *only_move_count += 1;
    }

    let mut best_idx = 0usize;
    for (idx, choice) in outcomes.iter().enumerate().skip(1) {
        if PerfectMoveOrdering::StrictSteps
            .compare(choice.outcome, outcomes[best_idx].outcome)
            .is_gt()
        {
            best_idx = idx;
        }
    }
    assert_eq!(
        outcomes[best_idx].outcome.wdl(),
        1,
        "the best strict-steps move in a forced win must itself be winning"
    );
    Some(legal.as_slice()[best_idx])
}
