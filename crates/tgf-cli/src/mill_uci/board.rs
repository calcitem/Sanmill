// SPDX-License-Identifier: GPL-3.0-or-later
// Mill board / FEN helpers used by the UCI loop:
//
//   * print_board_ascii / board_ascii_lines / side_label  — `d` command output
//   * print_uci_options                                  — `uci` response
//   * parse_position_command                             — `position …` parser
//   * action_to_uci / action_from_uci                    — UCI move codec

use tgf_core::{Action, ActionList, GameRules, GameStateSnapshot};
use tgf_mill::{MillRules, MillVariantOptions};

use super::EngineConfig;

pub(super) fn print_board_ascii(state: &GameStateSnapshot, options: &MillVariantOptions) {
    for line in board_ascii_lines(state, options.has_diagonal_lines) {
        println!("{line}");
    }
}

pub(super) fn board_ascii_lines(
    state: &GameStateSnapshot,
    has_diagonal_lines: bool,
) -> Vec<String> {
    let board: [u8; 24] = {
        let mut b = [0_u8; 24];
        b.copy_from_slice(&state.opaque_payload[..24]);
        b
    };
    let glyph = |node: usize| -> char {
        match board[node] {
            1 => 'W',
            2 => 'B',
            _ => '.',
        }
    };
    let g = |n: usize| glyph(n);
    let mut lines = if has_diagonal_lines {
        vec![
            format!("{} ----- {} ----- {}", g(0), g(1), g(2)),
            "| \\     |     / |".to_owned(),
            format!("|  {} -- {} -- {}  |", g(8), g(9), g(10)),
            "|  | \\   |   / |  |".to_owned(),
            format!("|  |  {} {} {}  |  |", g(16), g(17), g(18)),
            format!(
                "{} {} {}       {} {} {}",
                g(7),
                g(15),
                g(23),
                g(19),
                g(11),
                g(3)
            ),
            format!("|  |  {} {} {}  |  |", g(22), g(21), g(20)),
            "|  | /   |   \\ |  |".to_owned(),
            format!("|  {} -- {} -- {}  |", g(14), g(13), g(12)),
            "| /     |     \\ |".to_owned(),
            format!("{} ----- {} ----- {}", g(6), g(5), g(4)),
        ]
    } else {
        vec![
            format!("{} ----- {} ----- {}", g(0), g(1), g(2)),
            "|       |       |".to_owned(),
            format!("|  {} -- {} -- {}  |", g(8), g(9), g(10)),
            "|  |     |     |  |".to_owned(),
            format!("|  |  {} {} {}  |  |", g(16), g(17), g(18)),
            format!(
                "{} {} {}       {} {} {}",
                g(7),
                g(15),
                g(23),
                g(19),
                g(11),
                g(3)
            ),
            format!("|  |  {} {} {}  |  |", g(22), g(21), g(20)),
            "|  |     |     |  |".to_owned(),
            format!("|  {} -- {} -- {}  |", g(14), g(13), g(12)),
            "|       |       |".to_owned(),
            format!("{} ----- {} ----- {}", g(6), g(5), g(4)),
        ]
    };
    lines.push(format!("side: {}", side_label(state.side_to_move)));
    lines.push(format!("phase_tag: {}", state.phase_tag));
    lines.push(format!("move_number: {}", state.move_number));
    lines
}

pub(super) fn side_label(side: i8) -> &'static str {
    match side {
        0 => "white",
        1 => "black",
        _ => "none",
    }
}

pub(super) fn print_uci_options() {
    // Mirrors master src/ucioption.cpp init() ordering (P1-A).
    println!("option name Threads type spin default 1 min 1 max 512");
    println!("option name Hash type spin default 16 min 1 max 33554432");
    println!("option name Clear Hash type button");
    println!("option name Ponder type check default false");
    println!("option name MultiPV type spin default 1 min 1 max 500");
    println!("option name SkillLevel type spin default 1 min 0 max 30");
    println!("option name MoveTime type spin default 1 min 0 max 60");
    println!("option name AiIsLazy type check default false");
    println!("option name IDSEnabled type check default false");
    println!("option name DepthExtension type check default true");
    println!("option name Move Overhead type spin default 10 min 0 max 5000");
    println!("option name Slow Mover type spin default 100 min 10 max 1000");
    println!("option name nodestime type spin default 0 min 0 max 10000");
    println!("option name Shuffling type check default true");
    println!("option name UseLazySmp type check default false");
    println!("option name Algorithm type spin default 2 min 0 max 4");
    println!("option name DrawOnHumanExperience type check default true");
    println!("option name ConsiderMobility type check default true");
    println!("option name FocusOnBlockingPaths type check default true");
    println!("option name DeveloperMode type check default true");
    println!("option name MaxQuiescenceDepth type spin default 0 min 0 max 4");
    // Mill rule variant options (P1-A). Prefer master-compatible names.
    println!("option name PiecesCount type spin default 9 min 9 max 12");
    println!("option name flyPieceCount type spin default 3 min 3 max 4");
    println!("option name PiecesAtLeastCount type spin default 3 min 3 max 5");
    println!("option name HasDiagonalLines type check default false");
    println!("option name MillFormationActionInPlacingPhase type spin default 0 min 0 max 5");
    println!("option name MayMoveInPlacingPhase type check default false");
    println!("option name IsDefenderMoveFirst type check default false");
    println!("option name MayRemoveMultiple type check default false");
    println!("option name MayRemoveFromMillsAlways type check default false");
    println!("option name RestrictRepeatedMillsFormation type check default false");
    println!("option name OneTimeUseMill type check default false");
    println!("option name CustodianCaptureEnabled type check default false");
    println!("option name CustodianCaptureOnSquareEdges type check default true");
    println!("option name CustodianCaptureOnCrossLines type check default true");
    println!("option name CustodianCaptureOnDiagonalLines type check default true");
    println!("option name CustodianCaptureInPlacingPhase type check default true");
    println!("option name CustodianCaptureInMovingPhase type check default true");
    println!("option name CustodianCaptureOnlyWhenOwnPiecesLeq3 type check default false");
    println!("option name InterventionCaptureEnabled type check default false");
    println!("option name InterventionCaptureOnSquareEdges type check default true");
    println!("option name InterventionCaptureOnCrossLines type check default true");
    println!("option name InterventionCaptureOnDiagonalLines type check default true");
    println!("option name InterventionCaptureInPlacingPhase type check default true");
    println!("option name InterventionCaptureInMovingPhase type check default true");
    println!("option name InterventionCaptureOnlyWhenOwnPiecesLeq3 type check default false");
    println!("option name LeapCaptureEnabled type check default false");
    println!("option name LeapCaptureOnSquareEdges type check default true");
    println!("option name LeapCaptureOnCrossLines type check default true");
    println!("option name LeapCaptureOnDiagonalLines type check default true");
    println!("option name LeapCaptureInPlacingPhase type check default true");
    println!("option name LeapCaptureInMovingPhase type check default true");
    println!("option name LeapCaptureOnlyWhenOwnPiecesLeq3 type check default false");
    println!("option name BoardFullAction type spin default 0 min 0 max 4");
    println!("option name StopPlacingWhenTwoEmptySquares type check default false");
    println!("option name StalemateAction type spin default 0 min 0 max 5");
    println!("option name MayFly type check default true");
    println!("option name NMoveRule type spin default 100 min 10 max 200");
    println!("option name EndgameNMoveRule type spin default 100 min 5 max 200");
    println!("option name ThreefoldRepetitionRule type check default true");
}

pub(super) fn parse_position_command(rules: &MillRules, line: &str) -> GameStateSnapshot {
    let tokens = line.split_whitespace().collect::<Vec<_>>();

    let moves_idx = tokens.iter().position(|t| *t == "moves");
    let mut state = match tokens.get(1).copied() {
        Some("startpos") => rules.initial_state(&[]),
        Some("fen") => {
            let fen_end = moves_idx.unwrap_or(tokens.len());
            let fen = tokens[2..fen_end].join(" ");
            match rules.set_from_fen(&fen) {
                Ok(state) => rules.encode_state(state),
                Err(e) => {
                    println!("info string invalid fen ignored: {e}");
                    rules.initial_state(&[])
                }
            }
        }
        _ => rules.initial_state(&[]),
    };

    let Some(moves_idx) = moves_idx else {
        return state;
    };
    for mv in tokens.iter().skip(moves_idx + 1) {
        if let Some(action) = action_from_uci(rules, &state, mv) {
            state = rules.apply(&state, action);
        } else {
            println!("info string illegal move ignored: {mv}");
            break;
        }
    }
    state
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) struct GoOptions {
    pub(super) depth: i32,
    pub(super) movetime_ms: Option<u64>,
    pub(super) node_limit: Option<u64>,
}

/// Parse a `go …` invocation supporting the full UCI `go` subcommand set:
/// `wtime`, `btime`, `winc`, `binc`, `movetime`, `depth`, `nodes`,
/// `infinite`, `ponder`.
///
/// P1-D: `wtime`/`btime` selection is now based on `root_side_to_move`
/// (0=white, 1=black), matching master's time-management semantics.
/// When no explicit `movetime` is given in the `go` command and no
/// wtime/btime is present, `move_time_secs` from `setoption MoveTime`
/// is used as a fallback (master's primary time-control mechanism).
pub(super) fn parse_go_options(
    line: &str,
    root_side_to_move: i8,
    engine_cfg: &EngineConfig,
) -> GoOptions {
    let tokens = line.split_whitespace().collect::<Vec<_>>();

    let find_u64 = |key: &str| -> Option<u64> {
        tokens
            .windows(2)
            .find(|w| w[0] == key)
            .and_then(|w| w[1].parse::<u64>().ok())
    };
    let find_i32 = |key: &str| -> Option<i32> {
        tokens
            .windows(2)
            .find(|w| w[0] == key)
            .and_then(|w| w[1].parse::<i32>().ok())
    };

    if tokens.contains(&"infinite") || tokens.contains(&"ponder") {
        return GoOptions {
            depth: 64,
            movetime_ms: None,
            node_limit: None,
        };
    }

    let depth = find_i32("depth").unwrap_or(0).max(0);
    let node_limit = find_u64("nodes");

    // Explicit go movetime takes highest priority.
    let movetime_ms = if let Some(ms) = find_u64("movetime") {
        Some(ms)
    } else {
        // P1-D: select wtime/btime based on side_to_move (matching master
        // SearchEngine time-management which uses the correct clock for
        // the player to move).
        let (time_key, inc_key) = if root_side_to_move == 1 {
            ("btime", "binc")
        } else {
            ("wtime", "winc")
        };
        let remaining = find_u64(time_key);
        if let Some(r) = remaining {
            let increment = find_u64(inc_key).unwrap_or(0);
            Some((r / 30).saturating_add(increment).max(100))
        } else if engine_cfg.move_time_secs > 0 {
            // Fall back to setoption MoveTime (master's primary mechanism).
            Some(engine_cfg.move_time_secs as u64 * 1000)
        } else {
            None
        }
    };

    GoOptions {
        depth,
        movetime_ms,
        node_limit,
    }
}

pub(super) fn action_from_uci(
    rules: &MillRules,
    state: &GameStateSnapshot,
    move_uci: &str,
) -> Option<Action> {
    let mut actions = ActionList::<256>::new();
    rules.legal_actions(state, &mut actions);
    actions
        .into_iter()
        .find(|a| action_to_uci(*a).as_deref() == Some(move_uci))
}

pub(super) fn action_to_uci(action: Action) -> Option<String> {
    // Delegate to the canonical Mill UCI codec so every consumer
    // (CLI / FRB / transcripts) routes through one implementation.
    let text = tgf_mill::MillUciCodec::encode_action(action);
    if text.is_empty() { None } else { Some(text) }
}
