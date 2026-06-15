// SPDX-License-Identifier: GPL-3.0-or-later
// Perfect-database lookup for Mill positions (Nine Men's Morris std only).
//
// The vendored database bridge compiles C++ and reads native files, so the
// WebAssembly build treats Perfect DB as unavailable while keeping the public
// FRB surface stable.

use tgf_core::{Action, GameStateSnapshot};
#[cfg(not(target_arch = "wasm32"))]
use tgf_core::{Game, GameRules};
use tgf_mill::MillVariantOptions;
#[cfg(not(target_arch = "wasm32"))]
use tgf_mill::{MillActionKind, MillGame, MillRules};

#[cfg(not(target_arch = "wasm32"))]
use crate::games::mill::action_codec::action_to_uci_str;
#[cfg(not(target_arch = "wasm32"))]
use crate::games::mill::search::mill_searcher_default;

/// Depth of the heuristic-search fallback used for moves with no perfect
/// database entry.  Mirrors the legacy C++ `runAnalyze` shallow search depth.
#[cfg(not(target_arch = "wasm32"))]
const FALLBACK_SEARCH_DEPTH: i32 = 4;

/// Query the vendored perfect database for a legal action matching the
/// current position.  Returns `None` when the DB is unavailable, the
/// variant is not std 9-piece, or no legal action matches the DB token.
///
/// The board-to-bitboard encoding and node-to-perfect-index mapping live in
/// `perfect_db::best_move_token_for_state`; this wrapper only matches the
/// returned token against the caller's legal action list via the shared
/// `tgf_mill::MillUciCodec`.
#[cfg(not(target_arch = "wasm32"))]
pub(crate) fn try_perfect_best_action(
    snapshot: &tgf_core::GameStateSnapshot,
    options: &MillVariantOptions,
    legal: &[Action],
) -> Option<Action> {
    let state = MillRules::decode_snapshot(*snapshot);
    let token = perfect_db::best_move_token_for_state(&state, options, snapshot.side_to_move)?;

    legal
        .iter()
        .copied()
        .find(|action| action_to_uci_str(*action) == token)
}

#[cfg(target_arch = "wasm32")]
pub(crate) fn try_perfect_best_action(
    _snapshot: &GameStateSnapshot,
    _options: &MillVariantOptions,
    _legal: &[Action],
) -> Option<Action> {
    None
}

/// Verdict for a single analysed move, expressed from the perspective of the
/// side that is to move in the position being analysed.
pub(crate) struct MoveEval {
    /// Mill UCI notation token for the move (`"a4"`, `"a1-a4"`, `"xg7"`).
    pub mv: String,
    /// `"win"` / `"draw"` / `"loss"` (perfect database) or
    /// `"advantage"` / `"disadvantage"` (heuristic-search fallback).
    pub outcome: &'static str,
    /// Win/draw/loss value (1 / 0 / -1) for database verdicts, or the raw
    /// heuristic score for the fallback, from the analysing side's view.
    pub value: i32,
    /// Distance-to-conversion step count, or a negative value when the
    /// database does not expose one (always negative for the fallback).
    pub steps: i32,
}

/// Full analysis result: one verdict per legal move plus the detected trap
/// moves (empty unless trap detection ran and found any).
pub(crate) struct AnalysisReport {
    pub moves: Vec<MoveEval>,
    pub traps: Vec<String>,
}

/// Per-move working data retained for trap detection.  Only moves with a
/// definitive perfect-database verdict participate, matching the legacy C++
/// behaviour where trap awareness is gated on the database.
#[cfg(not(target_arch = "wasm32"))]
struct TrapCandidate {
    token: String,
    to: usize,
    from: Option<usize>,
    /// Database value from the analysing side's view (1 / 0 / -1).
    value: i32,
}

/// Analyse every legal move in `snapshot`.
///
/// Each move is applied and the resulting position is evaluated: first against
/// the perfect database (win/draw/loss + step count), and — when the database
/// has no entry — with a shallow heuristic search (advantage/disadvantage).
/// All verdicts are converted back to the perspective of the side to move in
/// `snapshot` (mirroring the legacy C++ `runAnalyze`: an evaluation relative to
/// the side to move *after* the move is negated once whenever the move flips
/// the side to move).
///
/// When `trap_awareness` is set, aggressive moves (those that complete or block
/// a mill) whose database verdict is worse than an available alternative are
/// reported as traps.
#[cfg(not(target_arch = "wasm32"))]
pub(crate) fn analyze_position(
    snapshot: &GameStateSnapshot,
    options: &MillVariantOptions,
    trap_awareness: bool,
) -> AnalysisReport {
    let rules = MillRules::new(options.clone());
    let game = MillGame::new(options.clone());
    let root_side = snapshot.side_to_move;

    let mut legal = tgf_core::ActionList::<256>::default();
    rules.legal_actions(snapshot, &mut legal);

    let mut moves = Vec::new();
    let mut trap_candidates: Vec<TrapCandidate> = Vec::new();
    let mut has_win = false;
    let mut has_draw = false;
    let mut has_loss = false;

    for action in legal.as_slice().iter().copied() {
        let next = rules.apply(snapshot, action);
        let token = action_to_uci_str(action);
        let next_state = MillRules::decode_snapshot(next);

        if let Some((wdl, steps)) =
            perfect_db::evaluate_state_for(&next_state, options, next.side_to_move)
        {
            // Convert the database value to the analysing side's perspective.
            let value = if next.side_to_move != root_side {
                -wdl
            } else {
                wdl
            };
            let outcome = match value {
                v if v > 0 => {
                    has_win = true;
                    "win"
                }
                v if v < 0 => {
                    has_loss = true;
                    "loss"
                }
                _ => {
                    has_draw = true;
                    "draw"
                }
            };

            if let Some(to) = node_in_range(action.to_node) {
                let from = if action.kind_tag == MillActionKind::Move as i16 {
                    node_in_range(action.from_node)
                } else {
                    None
                };
                trap_candidates.push(TrapCandidate {
                    token: token.clone(),
                    to,
                    from,
                    value,
                });
            }

            moves.push(MoveEval {
                mv: token,
                outcome,
                value,
                steps,
            });
        } else {
            // No database entry: fall back to a shallow heuristic search, as
            // the legacy C++ `runAnalyze` did for positions outside the DB.
            let mut wb = game.build_workbench(&next);
            let mut searcher = mill_searcher_default();
            let result = searcher.search(&mut wb, FALLBACK_SEARCH_DEPTH);
            let score = if next.side_to_move != root_side {
                -result.score
            } else {
                result.score
            };
            moves.push(MoveEval {
                mv: token,
                outcome: if score >= 0 {
                    "advantage"
                } else {
                    "disadvantage"
                },
                value: score,
                steps: -1,
            });
        }
    }

    let traps = if trap_awareness {
        detect_traps(
            &rules,
            snapshot,
            root_side,
            &trap_candidates,
            (has_win, has_draw, has_loss),
        )
    } else {
        Vec::new()
    };

    AnalysisReport { moves, traps }
}

#[cfg(target_arch = "wasm32")]
pub(crate) fn analyze_position(
    _snapshot: &GameStateSnapshot,
    _options: &MillVariantOptions,
    _trap_awareness: bool,
) -> AnalysisReport {
    AnalysisReport {
        moves: Vec::new(),
        traps: Vec::new(),
    }
}

/// Detect trap moves among `candidates` (perfect-database-backed moves).
///
/// Mirrors the legacy C++ `runAnalyze` trap pass: skip detection entirely when
/// every move shares the same verdict (all draws or all losses), then flag any
/// aggressive move (one completing or blocking a mill) whose verdict is worse
/// than an available alternative.
#[cfg(not(target_arch = "wasm32"))]
fn detect_traps(
    rules: &MillRules,
    snapshot: &GameStateSnapshot,
    root_side: i8,
    candidates: &[TrapCandidate],
    verdicts: (bool, bool, bool),
) -> Vec<String> {
    let (has_win, has_draw, has_loss) = verdicts;
    let all_draw = !has_win && has_draw && !has_loss;
    let all_loss = !has_win && has_loss && !has_draw;
    if all_draw || all_loss || !(0..2).contains(&root_side) {
        return Vec::new();
    }

    let opponent = 1 - root_side;
    let state = MillRules::decode_snapshot(*snapshot);

    let mut traps = Vec::new();
    for candidate in candidates {
        let our_mills =
            rules.potential_mills_count(&state, candidate.to, root_side, candidate.from);
        let their_mills =
            rules.potential_mills_count(&state, candidate.to, opponent, candidate.from);
        let aggressive = our_mills > 0 || their_mills > 0;
        if !aggressive {
            continue;
        }
        // Worse choice: a loss while a win or draw exists, or a draw while a
        // win exists.
        let worse =
            (candidate.value < 0 && (has_win || has_draw)) || (candidate.value == 0 && has_win);
        if worse {
            traps.push(candidate.token.clone());
        }
    }
    traps
}

/// Convert an action node field to a board index, or `None` when out of range.
#[cfg(not(target_arch = "wasm32"))]
fn node_in_range(node: i16) -> Option<usize> {
    if (0..24).contains(&node) {
        Some(node as usize)
    } else {
        None
    }
}
