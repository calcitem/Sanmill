// SPDX-License-Identifier: AGPL-3.0-or-later
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
    lines.push(format!(
        "pieces_in_hand: [{}, {}]",
        state.opaque_payload[24], state.opaque_payload[25]
    ));
    lines.push(format!(
        "pieces_on_board: [{}, {}]",
        state.opaque_payload[26], state.opaque_payload[27]
    ));
    lines.push(format!(
        "pending_removals: [{}, {}]",
        state.opaque_payload[28], state.opaque_payload[29]
    ));
    lines.push(format!("winner: {}", state.opaque_payload[30] as i8));
    lines.push(format!(
        "ply_since_capture: {}",
        u16::from(state.opaque_payload[31]) | (u16::from(state.opaque_payload[32]) << 8)
    ));
    lines.push(format!("outcome_reason: {}", state.opaque_payload[43]));
    lines.push(format!("key_history_len: {}", state.opaque_payload[236]));
    lines.push(format!("action_tag: {}", state.opaque_payload[279]));
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
    println!("option name MoveTimeMs type spin default 1000 min 0 max 60000");
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
    println!("option name UsePerfectDatabase type check default false");
    println!("option name PerfectDatabasePath type string default <empty>");
    println!("option name PerfectDatabaseCacheSectors type spin default 0 min 0 max 1048576");
    println!("option name PatchPath type string default <empty>");
    println!("option name PatchAvoidTraps type check default false");
    println!("option name PatchMakeTraps type check default false");
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

#[derive(Clone, Debug)]
pub(super) struct ParsedPosition {
    pub(super) state: GameStateSnapshot,
    pub(super) history: Vec<GameStateSnapshot>,
}

pub(super) fn parse_position_command(rules: &MillRules, line: &str) -> ParsedPosition {
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
    let mut history = Vec::new();

    let Some(moves_idx) = moves_idx else {
        return ParsedPosition { state, history };
    };
    for mv in tokens.iter().skip(moves_idx + 1) {
        if let Some(action) = action_from_uci(rules, &state, mv) {
            let next = rules.apply_with_history(&state, action, &history);
            history.push(state);
            state = next;
        } else {
            println!("info string illegal move ignored: {mv}");
            break;
        }
    }
    ParsedPosition { state, history }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) struct GoOptions {
    pub(super) depth: i32,
    pub(super) depth_is_explicit: bool,
    pub(super) movetime_ms: Option<u64>,
    pub(super) node_limit: Option<u64>,
    /// When set, score all legal moves at depth 2 after the main search and
    /// emit `info topn rank K move <m> score <s>` lines (sorted best-first)
    /// before the final `bestmove` line.  This is primarily intended for
    /// bridge adapters that need per-move scores without running N separate
    /// searches.  The main bestmove is still determined by the full search;
    /// the topn ranking uses a shallow fixed-depth eval sweep.
    pub(super) topn: Option<usize>,
}

/// Parse a `go …` invocation supporting the full UCI `go` subcommand set:
/// `wtime`, `btime`, `winc`, `binc`, `movetime`, `depth`, `nodes`,
/// `infinite`, `ponder`.
///
/// P1-D: `wtime`/`btime` selection is now based on `root_side_to_move`
/// (0=white, 1=black), matching master's time-management semantics.
/// When no explicit `movetime` is given in the `go` command and no
/// wtime/btime is present, `move_time_ms` from `setoption MoveTime` or
/// `MoveTimeMs` is used as a fallback (master's primary mechanism).
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
            depth_is_explicit: false,
            movetime_ms: None,
            node_limit: None,
            topn: None,
        };
    }

    let explicit_depth = find_i32("depth");
    let depth = explicit_depth.unwrap_or(0).max(0);
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
        } else if engine_cfg.move_time_ms > 0 {
            // Fall back to setoption MoveTime / MoveTimeMs.
            Some(engine_cfg.move_time_ms as u64)
        } else {
            None
        }
    };

    GoOptions {
        depth,
        depth_is_explicit: explicit_depth.is_some(),
        movetime_ms,
        node_limit,
        topn: find_u64("topn").map(|n| n.max(1) as usize),
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
