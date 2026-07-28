// SPDX-License-Identifier: AGPL-3.0-or-later
// Builds exact, displayable puzzle solution lines.
//
// Every decision is made over complete logical Mill turns. A primary action
// and its compulsory removal therefore count as one logical ply even though
// the exported PuzzleSolution keeps both action tokens for replay. The
// Composed-puzzle solutions branch over every fastest database win by the
// solving side. Replay-backed display lines use one deterministic
// principal variation. In both cases the defender follows a strict-best
// reply and, when defeat is forced, delays it.

use perfect_db::database::{Database, DatabaseProvider};
use perfect_db::{
    PerfectLogicalTurnChoice, PerfectMoveOrdering, best_logical_turn_choices_with_ordering,
};
use tgf_core::{GameRules, GameStateSnapshot, OutcomeKind};
use tgf_mill::{MillActionKind, MillPhase, MillRules, MillUciCodec, MillVariantOptions};

/// One action token of a constructed solution line, in absolute notation.
#[derive(Debug, Clone)]
pub(crate) struct SolutionPly {
    pub notation: String,
    /// Absolute side that played this action: 0 = white, 1 = black.
    pub side: i8,
}

/// A fully played-out forced-win line starting from a specific first turn.
#[derive(Debug, Clone)]
pub(crate) struct BuiltSolution {
    pub plies: Vec<SolutionPly>,
    /// Number of complete logical turns played by the solving side. A
    /// mill-forming action and its compulsory removal count once.
    pub solver_move_count: i32,
    /// True when the opponent captured one of the solving side's pieces at
    /// some point in the line.
    pub sacrifice: bool,
    /// Later solver decision points where exactly one complete logical turn
    /// was tied for the fastest forced win.
    pub only_move_count: i32,
    /// Total later solver decision points examined for
    /// [`Self::only_move_count`].
    pub decision_point_count: i32,
    /// The solver closed mills on two consecutive logical turns.
    pub double_mill: bool,
    /// The opponent reached the flying stage and still could not save the
    /// game.
    pub vs_flying: bool,
    /// The final win came by immobilisation rather than material.
    pub immobilization_win: bool,
}

#[derive(Clone)]
struct LineState {
    snap: GameStateSnapshot,
    history: Vec<GameStateSnapshot>,
    plies: Vec<SolutionPly>,
    solver_move_count: i32,
    sacrifice: bool,
    only_move_count: i32,
    decision_point_count: i32,
    double_mill: bool,
    vs_flying: bool,
    previous_solver_turn_closed_mill: bool,
    logical_plies: usize,
}

impl LineState {
    fn new(root_snap: GameStateSnapshot) -> Self {
        Self {
            snap: root_snap,
            history: Vec::new(),
            plies: Vec::new(),
            solver_move_count: 0,
            sacrifice: false,
            only_move_count: 0,
            decision_point_count: 0,
            double_mill: false,
            vs_flying: false,
            previous_solver_turn_closed_mill: false,
            logical_plies: 0,
        }
    }
}

/// Safety cap on complete logical plies per constructed line.
const MAX_SOLUTION_LOGICAL_PLIES: usize = 60;

/// Maximum flattened lines retained for one published puzzle.
///
/// Composed-puzzle entries store every equal-fast attacking continuation so
/// the app can accept it without a runtime database. A composed candidate
/// whose shortest strategy is wider than this belongs in the evidence pool,
/// not the compact built-in pack. Replay-backed entries use the separate
/// principal-variation builder below.
pub(crate) const MAX_EXPORTED_SOLUTION_LINES: usize = 128;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum SolutionBuildFailure {
    EmptyStrategy,
    LineCap,
    UnexpectedTerminal,
    LogicalPlyCap,
    DatabaseUnavailable,
    DefenderEscaped,
}

/// Play out every relevant line beneath one database-winning first turn.
///
/// Later solver nodes branch over every strict-best winning turn. Defender
/// nodes choose the first deterministic strict-best reply; strict ordering
/// preserves a better result when available and otherwise maximises the
/// distance to defeat. This is the official display defence used by the app.
///
/// `None` means that coverage ended, a forced-win invariant failed, the
/// strategy exceeded a safety cap, or a line did not terminate in a solver
/// win.
pub(crate) fn build_solution_lines<P: DatabaseProvider>(
    database: &mut Database<P>,
    rules: &MillRules,
    options: &MillVariantOptions,
    root_snap: GameStateSnapshot,
    solver_side: i8,
    first_turn: &PerfectLogicalTurnChoice,
    max_exported_lines: usize,
) -> Result<Vec<BuiltSolution>, SolutionBuildFailure> {
    assert!(
        solver_side == 0 || solver_side == 1,
        "puzzle solver side must be white or black"
    );
    assert_eq!(
        first_turn.outcome.wdl(),
        1,
        "the first turn of a forced-win line must preserve a win"
    );
    assert!(
        (1..=MAX_EXPORTED_SOLUTION_LINES).contains(&max_exported_lines),
        "the requested compact-line limit must fit the hard safety cap"
    );

    let mut state = LineState::new(root_snap);
    apply_turn(rules, options, solver_side, &mut state, first_turn);
    let mut solutions = Vec::new();
    expand_lines(
        database,
        rules,
        options,
        solver_side,
        state,
        &mut solutions,
        max_exported_lines,
    )?;
    if solutions.is_empty() {
        Err(SolutionBuildFailure::EmptyStrategy)
    } else {
        Ok(solutions)
    }
}

/// Play one deterministic principal variation beneath a database-winning
/// first turn.
///
/// Perfect DB still proves the root and every classified first turn. This
/// function controls only the compact line shown to a human reviewer or
/// solver: at every later decision point it selects the first
/// deterministically ordered strict-best turn. The defender therefore keeps
/// the best available result and, when loss is forced, delays defeat.
pub(crate) fn build_principal_solution_line<P: DatabaseProvider>(
    database: &mut Database<P>,
    rules: &MillRules,
    options: &MillVariantOptions,
    root_snap: GameStateSnapshot,
    solver_side: i8,
    first_turn: &PerfectLogicalTurnChoice,
) -> Result<BuiltSolution, SolutionBuildFailure> {
    assert!(
        solver_side == 0 || solver_side == 1,
        "puzzle solver side must be white or black"
    );
    assert_eq!(
        first_turn.outcome.wdl(),
        1,
        "the first turn of a forced-win line must preserve a win"
    );

    let mut state = LineState::new(root_snap);
    apply_turn(rules, options, solver_side, &mut state, first_turn);
    loop {
        match rules.outcome(&state.snap).kind {
            OutcomeKind::Win(side) if side == solver_side => {
                return Ok(finish_solution(options, solver_side, state));
            }
            OutcomeKind::Ongoing => {}
            _ => return Err(SolutionBuildFailure::UnexpectedTerminal),
        }
        if state.logical_plies >= MAX_SOLUTION_LOGICAL_PLIES {
            return Err(SolutionBuildFailure::LogicalPlyCap);
        }

        let mover = state.snap.side_to_move;
        assert!(
            mover == 0 || mover == 1,
            "puzzle solution must have a definite side to move while ongoing"
        );
        let choices = best_turns(database, rules, &state.snap, &state.history, options)?;
        if mover == solver_side {
            assert!(
                choices.iter().all(|choice| choice.outcome.wdl() == 1),
                "a forced-win principal variation must retain a winning strict-best turn"
            );
            state.decision_point_count += 1;
            if choices.len() == 1 {
                state.only_move_count += 1;
            }
        } else if choices[0].outcome.wdl() != -1 {
            return Err(SolutionBuildFailure::DefenderEscaped);
        }
        apply_turn(rules, options, solver_side, &mut state, &choices[0]);
    }
}

fn expand_lines<P: DatabaseProvider>(
    database: &mut Database<P>,
    rules: &MillRules,
    options: &MillVariantOptions,
    solver_side: i8,
    state: LineState,
    solutions: &mut Vec<BuiltSolution>,
    max_exported_lines: usize,
) -> Result<(), SolutionBuildFailure> {
    match rules.outcome(&state.snap).kind {
        OutcomeKind::Win(side) if side == solver_side => {
            if solutions.len() >= max_exported_lines {
                return Err(SolutionBuildFailure::LineCap);
            }
            solutions.push(finish_solution(options, solver_side, state));
            return Ok(());
        }
        OutcomeKind::Ongoing => {}
        _ => return Err(SolutionBuildFailure::UnexpectedTerminal),
    }
    if state.logical_plies >= MAX_SOLUTION_LOGICAL_PLIES {
        return Err(SolutionBuildFailure::LogicalPlyCap);
    }

    let mover = state.snap.side_to_move;
    assert!(
        mover == 0 || mover == 1,
        "puzzle solution must have a definite side to move while ongoing"
    );
    let choices = best_turns(database, rules, &state.snap, &state.history, options)?;

    if mover == solver_side {
        assert!(
            choices.iter().all(|choice| choice.outcome.wdl() == 1),
            "a forced-win line must retain a winning shortest turn at every solver node"
        );
        let only_move = choices.len() == 1;
        for choice in choices {
            let mut branch = state.clone();
            branch.decision_point_count += 1;
            if only_move {
                branch.only_move_count += 1;
            }
            apply_turn(rules, options, solver_side, &mut branch, &choice);
            expand_lines(
                database,
                rules,
                options,
                solver_side,
                branch,
                solutions,
                max_exported_lines,
            )?;
        }
    } else {
        if choices[0].outcome.wdl() != -1 {
            return Err(SolutionBuildFailure::DefenderEscaped);
        }
        let mut continuation = state;
        apply_turn(rules, options, solver_side, &mut continuation, &choices[0]);
        expand_lines(
            database,
            rules,
            options,
            solver_side,
            continuation,
            solutions,
            max_exported_lines,
        )?;
    }
    Ok(())
}

fn apply_turn(
    rules: &MillRules,
    options: &MillVariantOptions,
    solver_side: i8,
    state: &mut LineState,
    turn: &PerfectLogicalTurnChoice,
) {
    assert!(
        !turn.actions.is_empty(),
        "a complete logical turn must contain at least one action"
    );
    let mover = state.snap.side_to_move;
    if mover != solver_side {
        let mill_state = MillRules::decode_snapshot(state.snap);
        if options.may_fly
            && mill_state.phase() == MillPhase::Moving
            && mill_state.pieces_on_board()[mover as usize] <= options.fly_piece_count
        {
            state.vs_flying = true;
        }
    }

    let closes_mill = turn
        .actions
        .iter()
        .any(|action| action.kind_tag == MillActionKind::Remove as i16);
    if mover == solver_side {
        state.solver_move_count += 1;
        if closes_mill && state.previous_solver_turn_closed_mill {
            state.double_mill = true;
        }
        state.previous_solver_turn_closed_mill = closes_mill;
    } else if closes_mill {
        state.sacrifice = true;
    }

    for &action in &turn.actions {
        assert_eq!(
            state.snap.side_to_move, mover,
            "all actions in a logical turn must belong to the same side"
        );
        state.plies.push(SolutionPly {
            notation: MillUciCodec::encode_action(action),
            side: mover,
        });
        let before = state.snap;
        state.snap = rules.apply_with_history(&before, action, &state.history);
        state.history.push(before);
    }
    state.logical_plies += 1;
    assert!(
        rules.outcome(&state.snap).kind != OutcomeKind::Ongoing || state.snap.side_to_move != mover,
        "a complete logical turn must pass play or end the game"
    );
}

fn finish_solution(
    options: &MillVariantOptions,
    solver_side: i8,
    state: LineState,
) -> BuiltSolution {
    let final_state = MillRules::decode_snapshot(state.snap);
    let opponent = (1 - solver_side) as usize;
    let immobilization_win =
        final_state.pieces_on_board()[opponent] >= options.pieces_at_least_count;
    BuiltSolution {
        plies: state.plies,
        solver_move_count: state.solver_move_count,
        sacrifice: state.sacrifice,
        only_move_count: state.only_move_count,
        decision_point_count: state.decision_point_count,
        double_mill: state.double_mill,
        vs_flying: state.vs_flying,
        immobilization_win,
    }
}

fn best_turns<P: DatabaseProvider>(
    database: &mut Database<P>,
    rules: &MillRules,
    snap: &GameStateSnapshot,
    history: &[GameStateSnapshot],
    options: &MillVariantOptions,
) -> Result<Vec<PerfectLogicalTurnChoice>, SolutionBuildFailure> {
    match best_logical_turn_choices_with_ordering(
        database,
        rules,
        snap,
        history,
        options,
        PerfectMoveOrdering::StrictSteps,
    ) {
        Ok(Some(choices)) if !choices.is_empty() => Ok(choices),
        Ok(Some(_)) | Ok(None) => Err(SolutionBuildFailure::DatabaseUnavailable),
        Err(err) if err.is_missing_asset() => Err(SolutionBuildFailure::DatabaseUnavailable),
        Err(err) => {
            panic!("[puzzle-gen] Perfect DB error while extending an official line: {err}")
        }
    }
}
