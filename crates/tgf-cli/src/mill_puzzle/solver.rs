// SPDX-License-Identifier: AGPL-3.0-or-later
// Builds a single concrete puzzle solution line.
//
// The solving side always plays the Perfect DB's fastest winning move; the
// opponent always plays the heuristic engine's best reply -- never the DB's
// best *defense*. This mirrors the property the puzzle generator is asked
// for: a puzzle must still work when the opponent responds the way a real
// (non-perfect) player actually would, not with the theoretically most
// stubborn (and often unnatural) defense.

use perfect_db::database::{Database, DatabaseProvider};
use perfect_db::{PerfectMoveOrdering, best_move_choice_with_ordering};
use tgf_core::{
    Action, Game, GameRules, GameStateSnapshot, MoveOrderAlgorithm, MoveOrderContext, OutcomeKind,
};
use tgf_mill::{MillActionKind, MillGame, MillRules, MillUciCodec, MillVariantOptions};
use tgf_search::{SearchOptions, SearchPolicy, Searcher};

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
}

/// Safety cap on plies per constructed line. Real Mill forced wins within
/// the puzzle-relevant depth range (a handful of moves per side) resolve
/// in well under this; hitting it indicates the heuristic opponent and the
/// Perfect DB disagree about the position being lost, so the candidate is
/// discarded rather than trusted.
const MAX_SOLUTION_PLIES: usize = 60;

fn heuristic_search_options() -> SearchOptions {
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
    let mut forced_next = Some(first_action);

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
            let choice = match best_move_choice_with_ordering(
                database,
                rules,
                &snap,
                options,
                PerfectMoveOrdering::StrictSteps,
            ) {
                Ok(Some(choice)) => choice,
                Ok(None) => return None,
                Err(err) if err.is_missing_asset() => return None,
                Err(err) => panic!(
                    "[puzzle-gen] Perfect DB error while extending the solving side's line: {err}"
                ),
            };
            MillUciCodec::decode_action(&snap, &choice.token).unwrap_or_else(|| {
                panic!(
                    "[puzzle-gen] Perfect DB token `{}` failed to decode",
                    choice.token
                )
            })
        } else {
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
    }

    if rules.outcome(&snap).kind != OutcomeKind::Win(solver_side) {
        return None;
    }

    let solver_move_count = plies.iter().filter(|p| p.side == solver_side).count() as i32;
    Some(BuiltSolution {
        plies,
        solver_move_count,
        sacrifice,
    })
}
