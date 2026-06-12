// SPDX-License-Identifier: GPL-3.0-or-later
// Rust-native Mill rules scaffold.
//
// Implemented (Iterations 2-4):
//   * piece_count, fly_piece_count, pieces_at_least_count, may_fly
//   * has_diagonal_lines (diagonal topology, adjacency, and mill lines)
//   * may_remove_from_mills_always, may_remove_multiple
//   * n_move_rule, endgame_n_move_rule
//   * may_move_in_placing_phase
//   * is_defender_move_first
//   * restrict_repeated_mills_formation
//   * one_time_use_mill
//   * stop_placing_when_two_empty_squares
//   * board_full_action (all variants)
//   * mill_formation_action_in_placing_phase (all variants at the state
//     machine level; mark-and-delay records delayed line bits without a
//     third on-board MARKED_PIECE value)
//   * stalemate_action (all variants)
//   * threefold_repetition_rule (state-side, history kept in
//     `MillState.opaque_payload[38..230]`, drawn at apply time)
//   * custodian / intervention / leap capture on square-edge, cross, and
//     diagonal lines when `has_diagonal_lines` and `on_diagonal_lines` are
//     both enabled (12MM diagonal topology).
//
// Still owned by the legacy C++ path:
//   * Flutter/Qt rendering for marked pieces and legacy notation side-effects
//
// Perfect DB and opening book intentionally remain behind the cxx
// bridge — see `crates/tgf-legacy-cxx/`.

use tgf_core::{
    Action, ActionList, BoardTopology, GameRules, GameStateSnapshot, Outcome, OutcomeKind,
};

use crate::topology::MillTopology;

mod captures;
mod evaluation;
mod fen;
mod game_impls;
mod legacy_squares;
mod legal_actions;
mod legal_apply;
mod lines;
mod move_priority;
mod rules_setup;
mod state_impl;
mod transitions;
mod types;
mod zobrist;

use types::MillActionState;
pub use types::{
    CaptureRuleConfig, MillActionKind, MillBoardFullAction, MillFormationActionInPlacingPhase,
    MillPhase, MillVariantOptions, StalemateAction,
};

use state_impl::sync_action_state;

#[cfg(test)]
use fen::position_key;

/// Recompute the cached `MillState::zobrist_key` field from scratch.
///
/// Called at the end of `MillRules::encode` (i.e. after every
/// `MillRules::apply` or setup/encode flow) so the hot-path
/// `Workbench::key()` and `Workbench::key_after()` can read the
/// cache in O(1) instead of mixing a fresh hash on every probe.
/// Mirrors master's "incremental key + final commit" pattern: the
/// per-mutation `st.key ^= Zobrist::*` updates inside C++ apply
/// keep the key correct as the state mutates; we centralise the
/// xor work in a single full-state pass at the apply boundary so
/// future commits can move the maintenance into per-mutation
/// helpers without breaking the contract.
#[inline]
pub(super) fn recompute_zobrist(state: &mut MillState) {
    state.zobrist_key = zobrist::full_state_key(state);
}

use transitions::{
    apply_removal_based_on_mill_counts, bump_ply_since_capture, clear_key_history,
    is_action_within_board_bounds, live_piece, maybe_draw_by_n_move_rule, maybe_finish_full_board,
    maybe_stop_placing_when_two_empty, maybe_transition_to_moving, note_mill_formation,
    push_key_and_check_threefold, removal_count_for_bits, sync_phase_for_may_move_in_placing,
    usable_mill_bits,
};
#[cfg(test)]
use transitions::{enter_moving_phase, repetition_signature};

#[cfg(test)]
use captures::is_all_in_mills;
use captures::{
    activate_capture_state, active_capture_lines, capture_phase_allowed,
    capture_piece_count_allowed_leap, capture_total, clear_capture_state,
    clear_capture_state_for_side, detect_custodian_targets, detect_intervention_targets,
    detect_leap_targets, find_paired_intervention_target, is_adjacent_to_side_piece,
    leap_capture_target_is_removable,
};
#[cfg(test)]
use evaluation::mobility_diff;
use lines::{DIAGONAL_MILL_LINES, STANDARD_MILL_LINES};
#[cfg(test)]
use move_priority::{
    PRIORITY_DIAGONAL, PRIORITY_NO_DIAGONAL, PRIORITY_SKILL_1, RATING_BLOCK_ONE_MILL,
    RATING_ONE_MILL, RATING_STAR_SQUARE, is_star_square,
};
use move_priority::{default_dense_priority, move_priority_list_for_search};

#[derive(Clone, Debug)]
pub struct MillRules {
    options: MillVariantOptions,
    topology: MillTopology,
}

#[derive(Clone, Debug, Default)]
pub struct MillGame {
    options: MillVariantOptions,
}

#[derive(Clone, Debug)]
pub struct MillWorkbench {
    rules: MillRules,
    state: MillState,
    undo_stack: Vec<MillState>,
}

pub struct MillEvaluator;

/// Terminal win/loss score.  Must match `VALUE_MATE = 80` from `src/types.h`
/// so that the searcher's alpha/beta windows, TT mate-distance encoding, and
/// UCI `score mate <N>` output are all numerically consistent with the legacy
/// C++ engine.  Scores in [MILL_TERMINAL_WIN_SCORE, MILL_TERMINAL_WIN_SCORE + MAX_DEPTH]
/// indicate "win in N plies"; scores in the symmetric negative range indicate
/// losses.  The static evaluator's max is ~75 (within VALUE_KNOWN_WIN = 25
/// range for material imbalance), giving a safe gap from 80.
const MILL_TERMINAL_WIN_SCORE: i32 = 80; // == VALUE_MATE

impl MillVariantOptions {
    /// Assert that the option values are in the C++-compatible ranges.
    /// Matches the setoption range definitions in `src/ucioption.cpp`.
    /// Panics on invalid configuration so errors surface immediately
    /// rather than being masked by silent clamping.
    pub fn assert_valid(&self) {
        assert!(
            (9..=12).contains(&self.piece_count),
            "piece_count {} out of range 9..=12",
            self.piece_count
        );
        assert!(
            self.pieces_at_least_count >= 3 && self.pieces_at_least_count <= self.piece_count,
            "pieces_at_least_count {} must be in 3..=piece_count ({})",
            self.pieces_at_least_count,
            self.piece_count
        );
        if self.n_move_rule > 0 {
            assert!(
                (10..=200).contains(&self.n_move_rule),
                "n_move_rule {} out of range 10..=200",
                self.n_move_rule
            );
        }
        if self.endgame_n_move_rule > 0 {
            assert!(
                (5..=200).contains(&self.endgame_n_move_rule),
                "endgame_n_move_rule {} out of range 5..=200",
                self.endgame_n_move_rule
            );
        }
        assert!(
            !self.may_fly || self.fly_piece_count >= 3,
            "fly_piece_count {} must be >= 3 when may_fly is enabled",
            self.fly_piece_count
        );
    }
}

impl MillRules {
    pub fn new(options: MillVariantOptions) -> Self {
        options.assert_valid();
        let topology = MillTopology::new(options.has_diagonal_lines);
        Self { options, topology }
    }

    /// Borrow the variant options used when this `MillRules` was constructed.
    pub fn options(&self) -> &MillVariantOptions {
        &self.options
    }

    fn decode(snapshot: &GameStateSnapshot) -> MillState {
        MillState::decode(snapshot)
    }

    /// Decode an opaque `GameStateSnapshot` back to a mutable `MillState`
    /// for setup-position editing.  Exposed publicly so the FRB setup API
    /// can decode, mutate, and re-encode without going through `GameRules`.
    pub fn decode_snapshot(snap: GameStateSnapshot) -> MillState {
        MillState::decode(&snap)
    }

    fn encode(&self, mut state: MillState) -> GameStateSnapshot {
        // Refresh the cached Zobrist key right before serialising so
        // every emitted snapshot carries an up-to-date key and the
        // hot-path `Workbench::key()` can read the cache in O(1).
        recompute_zobrist(&mut state);
        let key = state.zobrist_key;
        GameStateSnapshot {
            side_to_move: state.side_to_move,
            phase_tag: state.phase as i16,
            move_number: state.move_number,
            zobrist_key: if key == 0 { 1 } else { key },
            opaque_payload: state.encode(),
        }
    }

    /// Smoke fixture used by `crate::api::simple::native_mill_*` FRB
    /// entry points to surface a known-good remove-count from the Rust
    /// rules engine.  Not part of the production API; new code should
    /// drive its own snapshot via `MillRules::apply` instead.
    #[doc(hidden)]
    pub fn moving_mill_remove_count_smoke() -> u32 {
        let rules = MillRules::default();
        let state = MillState {
            board: {
                let mut board = [0_i8; 24];
                board[1] = 1;
                board[2] = 1;
                board[3] = 1;
                board[6] = 2;
                board[5] = 2;
                board[10] = 2;
                board
            },
            side_to_move: 0,
            phase: MillPhase::Moving,
            move_number: 18,
            pieces_in_hand: [0, 0],
            pieces_on_board: [3, 3],
            pending_removals: [0, 0],
            winner: -1,
            ..MillState::default()
        };
        let after_move = rules.apply(
            &rules.encode(state),
            Action {
                kind_tag: MillActionKind::Move as i16,
                from_node: 3,
                to_node: 0,
                aux: -1,
                payload_bits: 0,
            },
        );
        let mut actions = ActionList::<256>::new();
        rules.legal_actions(&after_move, &mut actions);
        actions
            .iter()
            .filter(|a| a.kind_tag == MillActionKind::Remove as i16)
            .count() as u32
    }

    /// Build the no-mill 18-placement moving-phase fixture used by the C++
    /// golden tests.  This is a shared midgame benchmark / differential-test
    /// position: both players have placed all nine pieces, no remove
    /// obligation is pending, and White is to move in the moving phase.
    pub fn no_mill_moving_phase_snapshot(&self) -> GameStateSnapshot {
        const SEQ: [i16; 18] = [
            1, 2, 3, 0, 7, 4, 10, 9, 8, 13, 12, 6, 18, 16, 23, 17, 20, 22,
        ];
        let mut snap = self.initial_state(&[]);
        for node in SEQ {
            snap = self.apply(
                &snap,
                Action {
                    kind_tag: MillActionKind::Place as i16,
                    from_node: -1,
                    to_node: node,
                    aux: -1,
                    payload_bits: 0,
                },
            );
        }
        snap
    }

    /// Smoke fixture used by `crate::api::simple::native_mill_*` FRB
    /// entry points: verifies that removing the third black piece in a
    /// fly-endgame ends the game with White declared the winner.  Not
    /// part of the production API.
    #[doc(hidden)]
    pub fn removal_below_three_winner_smoke() -> i32 {
        let rules = MillRules::default();
        let state = MillState {
            board: {
                let mut board = [0_i8; 24];
                board[0] = 1;
                board[1] = 1;
                board[2] = 1;
                board[6] = 2;
                board[5] = 2;
                board
            },
            side_to_move: 0,
            phase: MillPhase::Moving,
            move_number: 20,
            pieces_in_hand: [0, 0],
            pieces_on_board: [3, 2],
            pending_removals: [1, 0],
            winner: -1,
            ..MillState::default()
        };
        let after_remove = rules.apply(
            &rules.encode(state),
            Action {
                kind_tag: MillActionKind::Remove as i16,
                from_node: -1,
                to_node: 6,
                aux: -1,
                payload_bits: 0,
            },
        );
        MillRules::decode(&after_remove).winner as i32
    }
}

impl Default for MillRules {
    fn default() -> Self {
        Self::new(MillVariantOptions::default())
    }
}

impl MillGame {
    pub fn new(options: MillVariantOptions) -> Self {
        Self { options }
    }
}

impl MillWorkbench {
    /// Expose pieces-on-board counts for search heuristics (e.g. MCTS empty-board early stop).
    pub fn pieces_on_board(&self) -> [u8; 2] {
        self.state.pieces_on_board
    }

    pub fn pieces_in_hand(&self) -> [u8; 2] {
        self.state.pieces_in_hand
    }
}

/// Transition to the moving phase only after a side switch, mirroring the
/// mature C++ engine's `pieceInHandCount[sideToMove] == 0` check inside
/// `change_side_to_move()`.  If a mill is pending the side does not switch
fn move_action(from: usize, to: usize) -> Action {
    Action {
        kind_tag: MillActionKind::Move as i16,
        from_node: from as i16,
        to_node: to as i16,
        aux: -1,
        payload_bits: 0,
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MillState {
    board: [i8; 24],
    side_to_move: i8,
    phase: MillPhase,
    action: MillActionState,
    move_number: i16,
    pub(crate) pieces_in_hand: [u8; 2],
    pieces_on_board: [u8; 2],
    pending_removals: [u8; 2],
    /// Per-side flag matching the legacy C++ engine's negative
    /// `pieceToRemoveCount[c]`: when `true`, the side with `pending_removals[c] > 0`
    /// must remove a piece of *its own* colour rather than the opponent's.
    /// Currently driven by `RemovalBasedOnMillCounts` when both sides have
    /// zero mills at the placing-to-moving boundary (whiteRemove =
    /// blackRemove = -1 in C++).
    remove_own_piece: [bool; 2],
    winner: i8,
    outcome_reason: MillOutcomeReason,
    ply_since_capture: u16,
    /// Per-side `lastMillFromSquare[c]` / `lastMillToSquare[c]` from
    /// legacy `position.cpp`: index 0 = first player (White), 1 = second
    /// player (Black).  Recorded by `note_mill_formation` and consulted by
    /// `is_restricted_repeated_mill`.  `-1` when the side has not formed
    /// a mill yet (or when restrict_repeated_mills_formation is disabled).
    last_mill_from: [i8; 2],
    last_mill_to: [i8; 2],
    used_mill_lines: u32,
    delayed_marked_pieces: u32,
    /// Per-side mirror of legacy `Position::formedMillsBB[c]`: 24-bit
    /// square bitmap recording every square that has been part of a
    /// completed mill for `c`.  Populated under `oneTimeUseMill` to
    /// match master semantics — `popcount(formed_mills_bb[c])` then
    /// gives the per-side "mill piece count" consumed by
    /// [`MillEvaluator`] for the `RemovalBasedOnMillCounts` action.
    formed_mills_bb: [u32; 2],
    /// Per-side active capture-state mirrors of legacy
    /// `Position::custodianCaptureTargets[c]` and friends.
    /// Index 0 = White / first player, 1 = Black / second player.
    custodian_targets: [u32; 2],
    intervention_targets: [u32; 2],
    leap_targets: [u32; 2],
    custodian_count: [u8; 2],
    intervention_count: [u8; 2],
    leap_count: [u8; 2],
    /// UI hint, mirrors `Position::preferredRemoveTarget`.  Holds the
    /// Rust dense node id (0..23) of a square that the engine has
    /// suggested as the "best" target for the next removal, or `-1`
    /// when no preference is set.
    preferred_remove_target: i8,
    mill_available_at_removal: bool,
    stalemate_removing: bool,
    both_stalemate_removing: bool,
    /// Board-full removals are a distinct placing-end flow in master.  They
    /// are persisted for UI/FEN round-trips but must not activate stalemate
    /// adjacency filtering once Rust has transitioned the phase to Moving.
    board_full_removing: bool,
    /// Repetition signatures appended on reversible side-changing moves and
    /// cleared on Place/Remove, mirroring master's global `posKeyHistory`
    /// vector. Runtime history is capped at 256 entries; snapshots persist
    /// only the most recent 24 entries for payload compatibility.
    key_history: Vec<u64>,
    /// Number of valid entries in `key_history`, clamped to 24.
    key_history_len: usize,
    /// Cached Zobrist position key.  Mirrors master `Position::st.key`
    /// and is maintained incrementally through `MillRules::apply`
    /// (recomputed via `zobrist::full_state_key` at the end of every
    /// apply that has not yet wired per-mutation xor maintenance).
    /// `Workbench::key()` and `Workbench::key_after()` read this
    /// field directly so the search hot path is O(1).
    zobrist_key: u64,
}

impl Default for MillState {
    fn default() -> Self {
        Self {
            board: [0_i8; 24],
            side_to_move: 0,
            phase: MillPhase::Placing,
            action: MillActionState::Place,
            move_number: 0,
            pieces_in_hand: [0, 0],
            pieces_on_board: [0, 0],
            pending_removals: [0, 0],
            remove_own_piece: [false, false],
            winner: -1,
            outcome_reason: MillOutcomeReason::Ongoing,
            ply_since_capture: 0,
            last_mill_from: [-1, -1],
            last_mill_to: [-1, -1],
            used_mill_lines: 0,
            delayed_marked_pieces: 0,
            formed_mills_bb: [0, 0],
            custodian_targets: [0, 0],
            intervention_targets: [0, 0],
            leap_targets: [0, 0],
            custodian_count: [0, 0],
            intervention_count: [0, 0],
            leap_count: [0, 0],
            preferred_remove_target: -1,
            mill_available_at_removal: false,
            stalemate_removing: false,
            both_stalemate_removing: false,
            board_full_removing: false,
            key_history: Vec::new(),
            key_history_len: 0,
            zobrist_key: 0,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
#[repr(u8)]
enum MillOutcomeReason {
    #[default]
    Ongoing = 0,
    LoseFewerThanThree = 1,
    /// Retained for backward-compatibility with serialised snapshots; new
    /// code uses `DrawFiftyMove` or `DrawEndgameFiftyMove`.
    DrawNMoveRule = 2,
    DrawFullBoard = 3,
    LoseFullBoard = 4,
    /// Threefold-repetition draw (string: "drawThreefoldRepetition").
    DrawThreefold = 5,
    LoseNoLegalMoves = 6,
    /// Stalemate draw (string: "drawStalemateCondition").
    DrawStalemate = 7,
    /// Regular n_move_rule draw (string: "drawFiftyMove").
    DrawFiftyMove = 8,
    /// Endgame-specific endgame_n_move_rule draw (string: "drawEndgameFiftyMove").
    DrawEndgameFiftyMove = 9,
}

fn formed_mill_bits_at(
    state: &MillState,
    options: &MillVariantOptions,
    node: usize,
    side_to_move: i8,
) -> u32 {
    let mut bits = 0_u32;
    for (line_idx, line) in mill_lines(options).iter().enumerate() {
        if line.contains(&node)
            && line
                .iter()
                .all(|idx| live_piece(state, *idx) == side_to_move + 1)
        {
            bits |= 1_u32 << line_idx;
        }
    }
    bits
}

/// Mirrors `Position::potential_mills_count` from `src/position.cpp`: counts
/// lines through `to` whose other two squares already hold `side`'s pieces,
/// optionally pretending the square at `from` (the source for a Move) is
/// empty.  Used by MovePicker-style ordering heuristics.
///
/// Honours `oneTimeUseMill`: when set, master `potential_mills_count` skips
/// every mill line whose three squares already sit in the per-side
/// `formedMillsBB[c]` (i.e. the line has already been activated for a
/// removal previously, so it is no longer counted as a potential mill).
fn potential_mills_count_at(
    state: &MillState,
    options: &MillVariantOptions,
    to: usize,
    side: i8,
    from: Option<usize>,
) -> u32 {
    let target = side + 1;
    let one_time_use = options.one_time_use_mill;
    let formed_bb = if (0..2).contains(&side) {
        state.formed_mills_bb[side as usize]
    } else {
        0
    };
    let mut count = 0_u32;
    for line in mill_lines(options) {
        if !line.contains(&to) {
            continue;
        }
        let mut all_color = true;
        for &idx in line {
            if idx == to {
                continue;
            }
            if from == Some(idx) {
                all_color = false;
                break;
            }
            if state.board[idx] != target {
                all_color = false;
                break;
            }
        }
        if !all_color {
            continue;
        }
        if one_time_use {
            // Skip lines whose three squares are already recorded as a
            // historically-formed mill for this side.
            let line_bb = node_bit(line[0]) | node_bit(line[1]) | node_bit(line[2]);
            if (line_bb & formed_bb) == line_bb {
                continue;
            }
        }
        count += 1;
    }
    count
}

fn is_piece_in_mill(state: &MillState, options: &MillVariantOptions, node: usize) -> bool {
    let piece = live_piece(state, node);
    if piece == 0 {
        return false;
    }
    mill_lines_for_node(options, node)
        .iter()
        .any(|line| line.iter().all(|idx| live_piece(state, *idx) == piece))
}

fn mill_lines_for_node(options: &MillVariantOptions, node: usize) -> Vec<[usize; 3]> {
    mill_lines(options)
        .iter()
        .copied()
        .filter(|line| line.contains(&node))
        .collect()
}

fn mill_lines(options: &MillVariantOptions) -> &'static [[usize; 3]] {
    if options.has_diagonal_lines {
        DIAGONAL_MILL_LINES
    } else {
        STANDARD_MILL_LINES
    }
}

fn node_bit(node: usize) -> u32 {
    1_u32 << node
}

#[cfg(test)]
mod tests;
