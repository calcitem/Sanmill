// SPDX-License-Identifier: GPL-3.0-or-later
// Rust-native Mill rules implementation.
//
// Implemented:
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
//   * threefold_repetition_rule (runtime history capped at 256 entries;
//     snapshots persist the compact 24-entry payload window)
//   * custodian / intervention / leap capture on square-edge, cross, and
//     diagonal lines when `has_diagonal_lines` and `on_diagonal_lines` are
//     both enabled (12MM diagonal topology).
//   * FEN import/export, setup-position editing, and search integration.
//
// The retired C++ engine is used only as a historical parity reference in
// tests and scripts.  Runtime Flutter play uses this Rust implementation.

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

#[inline(always)]
fn color_index_for_piece(piece: i8) -> Option<usize> {
    match piece {
        1 => Some(0),
        2 => Some(1),
        _ => None,
    }
}

#[inline(always)]
fn bitboards_from_board(board: &[i8; 24], delayed_marked_pieces: u32) -> [u32; 2] {
    let mut by_color = [0_u32; 2];
    for (node, &piece) in board.iter().enumerate() {
        if (delayed_marked_pieces & node_bit(node)) != 0 {
            continue;
        }
        if let Some(color) = color_index_for_piece(piece) {
            by_color[color] |= node_bit(node);
        }
    }
    by_color
}

#[inline(always)]
fn sync_bitboards_from_board(state: &mut MillState) {
    state.by_color_bb = bitboards_from_board(&state.board, state.delayed_marked_pieces);
}

#[inline(always)]
fn piece_bitboard(state: &MillState, piece: i8) -> u32 {
    color_index_for_piece(piece)
        .map(|color| state.by_color_bb[color])
        .unwrap_or(0)
}

#[inline(always)]
fn live_occupied_bitboard(state: &MillState) -> u32 {
    state.by_color_bb[0] | state.by_color_bb[1]
}

#[inline(always)]
fn board_occupied_bitboard(state: &MillState) -> u32 {
    live_occupied_bitboard(state) | state.delayed_marked_pieces
}

#[inline(always)]
fn set_board_node(state: &mut MillState, node: usize, piece: i8) {
    debug_assert!(node < 24, "Mill board node out of range");
    debug_assert!(
        (0..=2).contains(&piece),
        "Mill board piece must be 0, 1, or 2"
    );
    let mask = node_bit(node);
    if let Some(color) = color_index_for_piece(state.board[node]) {
        state.by_color_bb[color] &= !mask;
    }
    state.board[node] = piece;
    if (state.delayed_marked_pieces & mask) == 0
        && let Some(color) = color_index_for_piece(piece)
    {
        state.by_color_bb[color] |= mask;
    }
    debug_assert_eq!(
        state.by_color_bb,
        bitboards_from_board(&state.board, state.delayed_marked_pieces),
        "Mill color bitboards diverged from board state"
    );
}

#[inline(always)]
fn place_live_piece(state: &mut MillState, node: usize, side: usize) {
    debug_assert!(node < 24, "Mill board node out of range");
    debug_assert!(side < 2, "Mill side out of range");
    debug_assert_eq!(state.board[node], 0, "place target must be empty");
    debug_assert_eq!(
        state.delayed_marked_pieces & node_bit(node),
        0,
        "place target must not be marked"
    );
    let mask = node_bit(node);
    state.board[node] = side as i8 + 1;
    state.by_color_bb[side] |= mask;
    debug_assert_eq!(
        state.by_color_bb,
        bitboards_from_board(&state.board, state.delayed_marked_pieces),
        "Mill color bitboards diverged after place"
    );
}

#[inline(always)]
fn move_live_piece(state: &mut MillState, from: usize, to: usize, side: usize) {
    debug_assert!(from < 24 && to < 24, "Mill board node out of range");
    debug_assert!(side < 2, "Mill side out of range");
    debug_assert_eq!(state.board[from], side as i8 + 1, "move source mismatch");
    debug_assert_eq!(state.board[to], 0, "move target must be empty");
    debug_assert_eq!(
        state.delayed_marked_pieces & (node_bit(from) | node_bit(to)),
        0,
        "move endpoints must not be marked"
    );
    let from_mask = node_bit(from);
    let to_mask = node_bit(to);
    state.board[from] = 0;
    state.board[to] = side as i8 + 1;
    state.by_color_bb[side] = (state.by_color_bb[side] & !from_mask) | to_mask;
    debug_assert_eq!(
        state.by_color_bb,
        bitboards_from_board(&state.board, state.delayed_marked_pieces),
        "Mill color bitboards diverged after move"
    );
}

#[inline(always)]
fn clear_live_piece(state: &mut MillState, node: usize, side: usize) {
    debug_assert!(node < 24, "Mill board node out of range");
    debug_assert!(side < 2, "Mill side out of range");
    debug_assert_eq!(state.board[node], side as i8 + 1, "clear target mismatch");
    let mask = node_bit(node);
    state.board[node] = 0;
    state.by_color_bb[side] &= !mask;
    debug_assert_eq!(
        state.by_color_bb,
        bitboards_from_board(&state.board, state.delayed_marked_pieces),
        "Mill color bitboards diverged after clear"
    );
}

#[inline(always)]
fn mark_board_node_inactive(state: &mut MillState, node: usize) {
    debug_assert!(node < 24, "Mill board node out of range");
    let mask = node_bit(node);
    if let Some(color) = color_index_for_piece(state.board[node]) {
        state.by_color_bb[color] &= !mask;
    }
    state.delayed_marked_pieces |= mask;
    debug_assert_eq!(
        state.by_color_bb,
        bitboards_from_board(&state.board, state.delayed_marked_pieces),
        "Mill color bitboards diverged from marked board state"
    );
}

use transitions::{
    apply_removal_based_on_mill_counts, bump_ply_since_capture, clear_key_history,
    is_action_within_board_bounds, live_piece, maybe_draw_by_n_move_rule, maybe_finish_full_board,
    maybe_stop_placing_when_two_empty, maybe_transition_to_moving, note_mill_formation,
    push_key_and_check_threefold, push_key_and_check_threefold_with_key, removal_count_for_bits,
    sync_phase_with_active_hand, usable_mill_bits,
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
use evaluation::{calculate_mobility_diff, mobility_diff};
use evaluation::{recompute_mobility_diff, update_mobility_place, update_mobility_remove};
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
    standard_fast_path: bool,
}

#[derive(Clone, Debug, Default)]
pub struct MillGame {
    options: MillVariantOptions,
    root_repetition_history: Vec<u64>,
    root_position_resets_repetition: bool,
}

#[derive(Clone, Debug)]
pub struct MillWorkbench {
    rules: MillRules,
    state: MillState,
    undo_stack: Vec<MillUndoState>,
    root_position_resets_repetition: bool,
}

/// Search undo stack capacity, matching master `Sanmill::Stack<T, 128>`.
const MILL_SEARCH_STACK_CAPACITY: usize = 128;

pub struct MillEvaluator;

/// Terminal win/loss score.  Must match `VALUE_MATE = 80` from `src/types.h`
/// so that the searcher's alpha/beta windows, TT mate-distance encoding, and
/// UCI `score mate <N>` output are all numerically consistent with the legacy
/// C++ engine.  Scores in [MILL_TERMINAL_WIN_SCORE, MILL_TERMINAL_WIN_SCORE + MAX_DEPTH]
/// indicate "win in N plies"; scores in the symmetric negative range indicate
/// losses.  The static evaluator's max is ~75 (within VALUE_KNOWN_WIN = 25
/// range for material imbalance), giving a safe gap from 80.
const MILL_TERMINAL_WIN_SCORE: i32 = 80; // == VALUE_MATE
const MILL_REPETITION_HISTORY_CAP: usize = 256;
const MILL_REPETITION_SNAPSHOT_WINDOW: usize = 24;
const MAX_MILL_LINES_PER_NODE: usize = 3;
const NO_MILL_LINE: u8 = u8::MAX;
const STANDARD_MILL_LINE_INDICES_BY_NODE: [[u8; MAX_MILL_LINES_PER_NODE]; 24] =
    build_mill_line_indices_by_node(STANDARD_MILL_LINES);
const DIAGONAL_MILL_LINE_INDICES_BY_NODE: [[u8; MAX_MILL_LINES_PER_NODE]; 24] =
    build_mill_line_indices_by_node(DIAGONAL_MILL_LINES);
const STANDARD_MILL_LINE_PEER_MASKS_BY_NODE: [[u32; MAX_MILL_LINES_PER_NODE]; 24] =
    build_mill_line_peer_masks_by_node(STANDARD_MILL_LINES);
const DIAGONAL_MILL_LINE_PEER_MASKS_BY_NODE: [[u32; MAX_MILL_LINES_PER_NODE]; 24] =
    build_mill_line_peer_masks_by_node(DIAGONAL_MILL_LINES);
const STANDARD_MILL_LINE_MASKS: [u32; STANDARD_MILL_LINES.len()] =
    build_mill_line_masks::<{ STANDARD_MILL_LINES.len() }>(STANDARD_MILL_LINES);
const DIAGONAL_MILL_LINE_MASKS: [u32; DIAGONAL_MILL_LINES.len()] =
    build_mill_line_masks::<{ DIAGONAL_MILL_LINES.len() }>(DIAGONAL_MILL_LINES);

const fn build_mill_line_indices_by_node(
    lines: &[[usize; 3]],
) -> [[u8; MAX_MILL_LINES_PER_NODE]; 24] {
    let mut table = [[NO_MILL_LINE; MAX_MILL_LINES_PER_NODE]; 24];
    let mut counts = [0_usize; 24];
    let mut line_idx = 0_usize;
    while line_idx < lines.len() {
        let line = lines[line_idx];
        let mut offset = 0_usize;
        while offset < 3 {
            let node = line[offset];
            assert!(node < 24);
            let count = counts[node];
            assert!(count < MAX_MILL_LINES_PER_NODE);
            table[node][count] = line_idx as u8;
            counts[node] = count + 1;
            offset += 1;
        }
        line_idx += 1;
    }
    table
}

const fn build_mill_line_peer_masks_by_node(
    lines: &[[usize; 3]],
) -> [[u32; MAX_MILL_LINES_PER_NODE]; 24] {
    let mut table = [[0_u32; MAX_MILL_LINES_PER_NODE]; 24];
    let mut counts = [0_usize; 24];
    let mut line_idx = 0_usize;
    while line_idx < lines.len() {
        let line = lines[line_idx];
        let mut offset = 0_usize;
        while offset < 3 {
            let node = line[offset];
            assert!(node < 24);
            let count = counts[node];
            assert!(count < MAX_MILL_LINES_PER_NODE);
            let peer_a = line[(offset + 1) % 3];
            let peer_b = line[(offset + 2) % 3];
            table[node][count] = node_bit(peer_a) | node_bit(peer_b);
            counts[node] = count + 1;
            offset += 1;
        }
        line_idx += 1;
    }
    table
}

const fn build_mill_line_masks<const N: usize>(lines: &[[usize; 3]]) -> [u32; N] {
    assert!(lines.len() == N);
    let mut table = [0_u32; N];
    let mut line_idx = 0_usize;
    while line_idx < lines.len() {
        let line = lines[line_idx];
        let a = line[0];
        let b = line[1];
        let c = line[2];
        assert!(a < 24);
        assert!(b < 24);
        assert!(c < 24);
        table[line_idx] = node_bit(a) | node_bit(b) | node_bit(c);
        line_idx += 1;
    }
    table
}

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

fn standard_fast_path_enabled(options: &MillVariantOptions) -> bool {
    matches!(
        options.mill_formation_action_in_placing_phase,
        MillFormationActionInPlacingPhase::RemoveOpponentsPieceFromBoard
    ) && !options.has_diagonal_lines
        && !options.may_move_in_placing_phase
        && !options.may_remove_multiple
        && !options.restrict_repeated_mills_formation
        && !options.one_time_use_mill
        && !options.stop_placing_when_two_empty_squares
        && !options.custodian_capture.enabled
        && !options.intervention_capture.enabled
        && !options.leap_capture.enabled
}

impl MillRules {
    pub fn new(options: MillVariantOptions) -> Self {
        options.assert_valid();
        let standard_fast_path = standard_fast_path_enabled(&options);
        let topology = MillTopology::new(options.has_diagonal_lines);
        Self {
            options,
            topology,
            standard_fast_path,
        }
    }

    /// Borrow the variant options used when this `MillRules` was constructed.
    pub fn options(&self) -> &MillVariantOptions {
        &self.options
    }

    /// Count the mill lines through `to` (optionally treating the square at
    /// `from` as vacated) that already hold two of `side`'s pieces — i.e. the
    /// lines this move could complete.  Mirrors C++
    /// `Position::potential_mills_count` and is used by the analysis overlay's
    /// trap detection to decide whether a candidate move is "aggressive".
    pub fn potential_mills_count(
        &self,
        state: &MillState,
        to: usize,
        side: i8,
        from: Option<usize>,
    ) -> u32 {
        potential_mills_count_at(state, &self.options, to, side, from)
    }

    fn decode(snapshot: &GameStateSnapshot) -> MillState {
        MillState::decode(snapshot)
    }

    fn decode_with_options(&self, snapshot: &GameStateSnapshot) -> MillState {
        let mut state = MillState::decode(snapshot);
        recompute_mobility_diff(&mut state, &self.options);
        state
    }

    /// Decode an opaque `GameStateSnapshot` back to a mutable `MillState`
    /// for setup-position editing.  Exposed publicly so the FRB setup API
    /// can decode, mutate, and re-encode without going through `GameRules`.
    pub fn decode_snapshot(snap: GameStateSnapshot) -> MillState {
        MillState::decode(&snap)
    }

    fn encode(&self, mut state: MillState) -> GameStateSnapshot {
        sync_bitboards_from_board(&mut state);
        // Refresh the cached Zobrist key right before serialising so
        // every emitted snapshot carries an up-to-date key and the
        // hot-path `Workbench::key()` can read the cache in O(1).
        recompute_mobility_diff(&mut state, &self.options);
        recompute_zobrist(&mut state);
        GameStateSnapshot {
            side_to_move: state.side_to_move,
            phase_tag: state.phase as i16,
            move_number: state.move_number,
            zobrist_key: state.zobrist_key,
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
        Self {
            options,
            root_repetition_history: Vec::new(),
            root_position_resets_repetition: false,
        }
    }

    pub fn new_with_repetition_history(
        options: MillVariantOptions,
        root_repetition_history: Vec<u64>,
    ) -> Self {
        assert!(
            root_repetition_history.len() <= MILL_REPETITION_HISTORY_CAP,
            "root repetition history exceeds Mill cap"
        );
        Self {
            options,
            root_repetition_history,
            root_position_resets_repetition: false,
        }
    }

    pub fn new_with_repetition_context(
        options: MillVariantOptions,
        root_repetition_history: Vec<u64>,
        root_position_resets_repetition: bool,
    ) -> Self {
        assert!(
            root_repetition_history.len() <= MILL_REPETITION_HISTORY_CAP,
            "root repetition history exceeds Mill cap"
        );
        Self {
            options,
            root_repetition_history,
            root_position_resets_repetition,
        }
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
#[inline(always)]
fn move_action(from: usize, to: usize) -> Action {
    Action {
        kind_tag: MillActionKind::Move as i16,
        from_node: from as i16,
        to_node: to as i16,
        aux: -1,
        payload_bits: 0,
    }
}

/// Packed runtime flags for Mill state and undo snapshots.
///
/// These bits intentionally mirror the snapshot payload byte at offset 252.
/// Keeping the same representation in memory avoids six separate bool fields
/// in every `MillState` and every search undo entry while still making each
/// flag readable through named accessors.
#[derive(Clone, Copy, PartialEq, Eq, Default)]
struct MillStateFlags(u8);

impl MillStateFlags {
    const MILL_AVAILABLE_AT_REMOVAL: u8 = 1 << 0;
    const STALEMATE_REMOVING: u8 = 1 << 1;
    const BOTH_STALEMATE_REMOVING: u8 = 1 << 2;
    const REMOVE_OWN_FIRST: u8 = 1 << 3;
    const REMOVE_OWN_SECOND: u8 = 1 << 4;
    const BOARD_FULL_REMOVING: u8 = 1 << 5;
    const PAYLOAD_MASK: u8 = Self::MILL_AVAILABLE_AT_REMOVAL
        | Self::STALEMATE_REMOVING
        | Self::BOTH_STALEMATE_REMOVING
        | Self::REMOVE_OWN_FIRST
        | Self::REMOVE_OWN_SECOND
        | Self::BOARD_FULL_REMOVING;

    #[inline]
    fn from_payload(bits: u8) -> Self {
        debug_assert_eq!(
            bits & !Self::PAYLOAD_MASK,
            0,
            "unknown Mill state flag bits in snapshot payload"
        );
        Self(bits & Self::PAYLOAD_MASK)
    }

    #[inline]
    fn from_parts(
        remove_own_piece: [bool; 2],
        mill_available_at_removal: bool,
        stalemate_removing: bool,
        both_stalemate_removing: bool,
        board_full_removing: bool,
    ) -> Self {
        let mut flags = Self::default();
        flags.set_remove_own_pieces(remove_own_piece);
        flags.set_mill_available_at_removal(mill_available_at_removal);
        flags.set_stalemate_removing(stalemate_removing);
        flags.set_both_stalemate_removing(both_stalemate_removing);
        flags.set_board_full_removing(board_full_removing);
        flags
    }

    #[inline]
    fn payload_bits(self) -> u8 {
        self.0 & Self::PAYLOAD_MASK
    }

    #[inline]
    fn bit(self, mask: u8) -> bool {
        (self.0 & mask) != 0
    }

    #[inline]
    fn set_bit(&mut self, mask: u8, enabled: bool) {
        if enabled {
            self.0 |= mask;
        } else {
            self.0 &= !mask;
        }
    }

    #[inline]
    fn remove_own_piece(self, side: usize) -> bool {
        assert!(side < 2, "Mill remove-own side out of range");
        self.bit(if side == 0 {
            Self::REMOVE_OWN_FIRST
        } else {
            Self::REMOVE_OWN_SECOND
        })
    }

    #[inline]
    fn remove_own_pieces(self) -> [bool; 2] {
        [self.remove_own_piece(0), self.remove_own_piece(1)]
    }

    #[inline]
    fn set_remove_own_piece(&mut self, side: usize, enabled: bool) {
        assert!(side < 2, "Mill remove-own side out of range");
        let mask = if side == 0 {
            Self::REMOVE_OWN_FIRST
        } else {
            Self::REMOVE_OWN_SECOND
        };
        self.set_bit(mask, enabled);
    }

    #[inline]
    fn set_remove_own_pieces(&mut self, values: [bool; 2]) {
        self.set_remove_own_piece(0, values[0]);
        self.set_remove_own_piece(1, values[1]);
    }

    #[inline]
    fn mill_available_at_removal(self) -> bool {
        self.bit(Self::MILL_AVAILABLE_AT_REMOVAL)
    }

    #[inline]
    fn set_mill_available_at_removal(&mut self, enabled: bool) {
        self.set_bit(Self::MILL_AVAILABLE_AT_REMOVAL, enabled);
    }

    #[inline]
    fn stalemate_removing(self) -> bool {
        self.bit(Self::STALEMATE_REMOVING)
    }

    #[inline]
    fn set_stalemate_removing(&mut self, enabled: bool) {
        self.set_bit(Self::STALEMATE_REMOVING, enabled);
    }

    #[inline]
    fn both_stalemate_removing(self) -> bool {
        self.bit(Self::BOTH_STALEMATE_REMOVING)
    }

    #[inline]
    fn set_both_stalemate_removing(&mut self, enabled: bool) {
        self.set_bit(Self::BOTH_STALEMATE_REMOVING, enabled);
    }

    #[inline]
    fn board_full_removing(self) -> bool {
        self.bit(Self::BOARD_FULL_REMOVING)
    }

    #[inline]
    fn set_board_full_removing(&mut self, enabled: bool) {
        self.set_bit(Self::BOARD_FULL_REMOVING, enabled);
    }
}

impl std::fmt::Debug for MillStateFlags {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("MillStateFlags")
            .field("remove_own_piece", &self.remove_own_pieces())
            .field(
                "mill_available_at_removal",
                &self.mill_available_at_removal(),
            )
            .field("stalemate_removing", &self.stalemate_removing())
            .field("both_stalemate_removing", &self.both_stalemate_removing())
            .field("board_full_removing", &self.board_full_removing())
            .finish()
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MillState {
    board: [i8; 24],
    /// Per-side live occupancy bitboards, matching the legacy engine's
    /// `byColorBB`.  These are derived from `board` plus
    /// `delayed_marked_pieces`; marked pieces remain visible in `board`
    /// for UI rendering but are absent from this cache.
    by_color_bb: [u32; 2],
    side_to_move: i8,
    phase: MillPhase,
    action: MillActionState,
    move_number: i16,
    pub(crate) pieces_in_hand: [u8; 2],
    pieces_on_board: [u8; 2],
    mobility_diff: i32,
    pending_removals: [u8; 2],
    /// Packed removal/stalemate flags.  See `MillStateFlags`; keeping this
    /// as one byte saves space in both the live state and every undo entry.
    flags: MillStateFlags,
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
    /// Repetition signatures appended on reversible side-changing moves and
    /// cleared on Place/Remove, mirroring master's global `posKeyHistory`
    /// vector. Runtime history is capped at 256 entries; snapshots persist
    /// only the most recent 24 entries for payload compatibility.
    key_history: Vec<u64>,
    /// Runtime length of `key_history`; snapshot encoding clamps it to the
    /// compact payload window.
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
            by_color_bb: [0, 0],
            side_to_move: 0,
            phase: MillPhase::Placing,
            action: MillActionState::Place,
            move_number: 0,
            pieces_in_hand: [0, 0],
            pieces_on_board: [0, 0],
            mobility_diff: 0,
            pending_removals: [0, 0],
            flags: MillStateFlags::default(),
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
            key_history: Vec::new(),
            key_history_len: 0,
            zobrist_key: 0,
        }
    }
}

impl MillState {
    #[inline]
    fn remove_own_piece(&self, side: usize) -> bool {
        self.flags.remove_own_piece(side)
    }

    #[cfg(test)]
    #[inline]
    fn remove_own_pieces(&self) -> [bool; 2] {
        self.flags.remove_own_pieces()
    }

    #[inline]
    fn set_remove_own_piece(&mut self, side: usize, enabled: bool) {
        self.flags.set_remove_own_piece(side, enabled);
    }

    #[inline]
    fn set_remove_own_pieces(&mut self, values: [bool; 2]) {
        self.flags.set_remove_own_pieces(values);
    }

    #[inline]
    fn mill_available_at_removal(&self) -> bool {
        self.flags.mill_available_at_removal()
    }

    #[inline]
    fn set_mill_available_at_removal(&mut self, enabled: bool) {
        self.flags.set_mill_available_at_removal(enabled);
    }

    #[inline]
    fn stalemate_removing(&self) -> bool {
        self.flags.stalemate_removing()
    }

    #[inline]
    fn set_stalemate_removing(&mut self, enabled: bool) {
        self.flags.set_stalemate_removing(enabled);
    }

    #[inline]
    fn both_stalemate_removing(&self) -> bool {
        self.flags.both_stalemate_removing()
    }

    #[inline]
    fn set_both_stalemate_removing(&mut self, enabled: bool) {
        self.flags.set_both_stalemate_removing(enabled);
    }

    #[inline]
    fn board_full_removing(&self) -> bool {
        self.flags.board_full_removing()
    }

    #[inline]
    fn set_board_full_removing(&mut self, enabled: bool) {
        self.flags.set_board_full_removing(enabled);
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

#[derive(Clone, Debug)]
struct MillUndoState {
    core: MillUndoCore,
    key_history: MillKeyHistoryUndo,
}

#[derive(Clone, Debug)]
struct MillUndoCore {
    board: MillBoardUndo,
    by_color_bb: [u32; 2],
    side_to_move: i8,
    phase: MillPhase,
    action: MillActionState,
    move_number: i16,
    pieces_in_hand: [u8; 2],
    pieces_on_board: [u8; 2],
    mobility_diff: i32,
    pending_removals: [u8; 2],
    flags: MillStateFlags,
    winner: i8,
    outcome_reason: MillOutcomeReason,
    ply_since_capture: u16,
    last_mill_from: [i8; 2],
    last_mill_to: [i8; 2],
    used_mill_lines: u32,
    delayed_marked_pieces: u32,
    formed_mills_bb: [u32; 2],
    custodian_targets: [u32; 2],
    intervention_targets: [u32; 2],
    leap_targets: [u32; 2],
    custodian_count: [u8; 2],
    intervention_count: [u8; 2],
    leap_count: [u8; 2],
    preferred_remove_target: i8,
    key_history_len: usize,
    zobrist_key: u64,
}

#[derive(Clone, Debug)]
enum MillKeyHistoryUndo {
    Truncate(usize),
    Restore(Box<[u64]>),
}

impl MillUndoState {
    fn capture(state: &MillState, action: Action, options: &MillVariantOptions) -> Self {
        let clears_history = action.kind_tag == MillActionKind::Place as i16
            || action.kind_tag == MillActionKind::Remove as i16;
        let must_restore_history = state.key_history.len() == MILL_REPETITION_HISTORY_CAP
            || (clears_history && !state.key_history.is_empty());
        let key_history = if must_restore_history {
            MillKeyHistoryUndo::Restore(state.key_history.clone().into_boxed_slice())
        } else {
            MillKeyHistoryUndo::Truncate(state.key_history.len())
        };
        Self {
            core: MillUndoCore::capture(state, action, options),
            key_history,
        }
    }

    fn restore(self, state: &mut MillState) {
        match self.key_history {
            MillKeyHistoryUndo::Truncate(len) => state.key_history.truncate(len),
            MillKeyHistoryUndo::Restore(history) => state.key_history = history.into_vec(),
        }
        self.core.restore(state);
        debug_assert_eq!(
            state.key_history.len(),
            state.key_history_len,
            "undo restored inconsistent repetition history length"
        );
    }
}

impl MillUndoCore {
    fn capture(state: &MillState, action: Action, options: &MillVariantOptions) -> Self {
        Self {
            board: MillBoardUndo::capture(state, action, options),
            by_color_bb: state.by_color_bb,
            side_to_move: state.side_to_move,
            phase: state.phase,
            action: state.action,
            move_number: state.move_number,
            pieces_in_hand: state.pieces_in_hand,
            pieces_on_board: state.pieces_on_board,
            mobility_diff: state.mobility_diff,
            pending_removals: state.pending_removals,
            flags: state.flags,
            winner: state.winner,
            outcome_reason: state.outcome_reason,
            ply_since_capture: state.ply_since_capture,
            last_mill_from: state.last_mill_from,
            last_mill_to: state.last_mill_to,
            used_mill_lines: state.used_mill_lines,
            delayed_marked_pieces: state.delayed_marked_pieces,
            formed_mills_bb: state.formed_mills_bb,
            custodian_targets: state.custodian_targets,
            intervention_targets: state.intervention_targets,
            leap_targets: state.leap_targets,
            custodian_count: state.custodian_count,
            intervention_count: state.intervention_count,
            leap_count: state.leap_count,
            preferred_remove_target: state.preferred_remove_target,
            key_history_len: state.key_history_len,
            zobrist_key: state.zobrist_key,
        }
    }

    fn restore(self, state: &mut MillState) {
        self.board.restore_board(state);
        state.side_to_move = self.side_to_move;
        state.phase = self.phase;
        state.action = self.action;
        state.move_number = self.move_number;
        state.pieces_in_hand = self.pieces_in_hand;
        state.pieces_on_board = self.pieces_on_board;
        state.mobility_diff = self.mobility_diff;
        state.pending_removals = self.pending_removals;
        state.flags = self.flags;
        state.winner = self.winner;
        state.outcome_reason = self.outcome_reason;
        state.ply_since_capture = self.ply_since_capture;
        state.last_mill_from = self.last_mill_from;
        state.last_mill_to = self.last_mill_to;
        state.used_mill_lines = self.used_mill_lines;
        state.delayed_marked_pieces = self.delayed_marked_pieces;
        state.by_color_bb = self.by_color_bb;
        state.formed_mills_bb = self.formed_mills_bb;
        state.custodian_targets = self.custodian_targets;
        state.intervention_targets = self.intervention_targets;
        state.leap_targets = self.leap_targets;
        state.custodian_count = self.custodian_count;
        state.intervention_count = self.intervention_count;
        state.leap_count = self.leap_count;
        state.preferred_remove_target = self.preferred_remove_target;
        state.key_history_len = self.key_history_len;
        state.zobrist_key = self.zobrist_key;
        debug_assert_eq!(
            state.by_color_bb,
            bitboards_from_board(&state.board, state.delayed_marked_pieces),
            "undo restored inconsistent Mill color bitboards"
        );
    }
}

#[derive(Clone, Debug)]
enum MillBoardUndo {
    Delta {
        len: u8,
        cells: [(u8, i8); MillBoardUndo::MAX_DELTA_CELLS],
    },
    Full(Box<[i8; 24]>),
}

impl MillBoardUndo {
    const MAX_DELTA_CELLS: usize = 2;

    fn capture(state: &MillState, action: Action, options: &MillVariantOptions) -> Self {
        if Self::requires_full_board_snapshot(state, options) {
            return Self::Full(Box::new(state.board));
        }

        let mut cells = [(0_u8, 0_i8); Self::MAX_DELTA_CELLS];
        let mut len = 0_u8;
        Self::push_cell(&mut cells, &mut len, state, action.from_node);
        Self::push_cell(&mut cells, &mut len, state, action.to_node);
        Self::Delta { len, cells }
    }

    fn requires_full_board_snapshot(state: &MillState, options: &MillVariantOptions) -> bool {
        state.delayed_marked_pieces != 0
            || matches!(
                options.mill_formation_action_in_placing_phase,
                MillFormationActionInPlacingPhase::MarkAndDelayRemovingPieces
                    | MillFormationActionInPlacingPhase::RemovalBasedOnMillCounts
            )
            || options.custodian_capture.enabled
            || options.intervention_capture.enabled
            || options.leap_capture.enabled
    }

    fn push_cell(
        cells: &mut [(u8, i8); Self::MAX_DELTA_CELLS],
        len: &mut u8,
        state: &MillState,
        node: i16,
    ) {
        if !(0..24).contains(&node) {
            return;
        }
        let node = node as u8;
        if cells[..usize::from(*len)]
            .iter()
            .any(|(old_node, _)| *old_node == node)
        {
            return;
        }
        let idx = usize::from(*len);
        assert!(
            idx < Self::MAX_DELTA_CELLS,
            "Mill board undo delta capacity exceeded"
        );
        cells[idx] = (node, state.board[node as usize]);
        *len += 1;
    }

    fn restore_board(self, state: &mut MillState) {
        match self {
            Self::Delta { len, cells } => {
                for (node, value) in cells.into_iter().take(usize::from(len)) {
                    state.board[node as usize] = value;
                }
            }
            Self::Full(board) => {
                state.board = *board;
            }
        }
    }
}

#[inline(always)]
fn formed_mill_bits_at(
    state: &MillState,
    options: &MillVariantOptions,
    node: usize,
    side_to_move: i8,
) -> u32 {
    if state.delayed_marked_pieces == 0 {
        let Some(color) = color_index_for_piece(side_to_move + 1) else {
            return 0;
        };
        let color_bb = state.by_color_bb[color];
        if (color_bb & node_bit(node)) == 0 {
            return 0;
        }
        let mut bits = 0_u32;
        let line_indices = mill_line_indices_for_node(options, node);
        let peer_masks = mill_line_peer_masks_for_node(options, node);
        for slot in 0..MAX_MILL_LINES_PER_NODE {
            let line_idx = line_indices[slot];
            if line_idx == NO_MILL_LINE {
                break;
            }
            let peer_mask = peer_masks[slot];
            if (color_bb & peer_mask) == peer_mask {
                bits |= 1_u32 << line_idx;
            }
        }
        return bits;
    }

    let mut bits = 0_u32;
    let lines = mill_lines(options);
    for &line_idx in mill_line_indices_for_node(options, node) {
        if line_idx == NO_MILL_LINE {
            break;
        }
        let line = lines[line_idx as usize];
        if line
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
#[inline(always)]
fn potential_mills_count_at(
    state: &MillState,
    options: &MillVariantOptions,
    to: usize,
    side: i8,
    from: Option<usize>,
) -> u32 {
    let Some(color) = color_index_for_piece(side + 1) else {
        return 0;
    };
    let mut color_bb = state.by_color_bb[color];
    let one_time_use = options.one_time_use_mill;
    let formed_bb = state.formed_mills_bb[color];
    if let Some(from) = from {
        color_bb &= !node_bit(from);
    }
    let mut count = 0_u32;
    for &peer_mask in mill_line_peer_masks_for_node(options, to) {
        if peer_mask == 0 {
            break;
        }
        if (color_bb & peer_mask) != peer_mask {
            continue;
        }
        if one_time_use {
            // Skip lines whose three squares are already recorded as a
            // historically-formed mill for this side.
            let line_bb = node_bit(to) | peer_mask;
            if (line_bb & formed_bb) == line_bb {
                continue;
            }
        }
        count += 1;
    }
    count
}

#[inline(always)]
fn potential_mills_count_standard_unrestricted(
    color_bb: u32,
    to: usize,
    from: Option<usize>,
) -> u32 {
    let mut color_bb = color_bb;
    if let Some(from) = from {
        color_bb &= !node_bit(from);
    }
    let mut count = 0_u32;
    for &peer_mask in &STANDARD_MILL_LINE_PEER_MASKS_BY_NODE[to] {
        if peer_mask == 0 {
            break;
        }
        count += u32::from((color_bb & peer_mask) == peer_mask);
    }
    count
}

#[inline(always)]
fn potential_mills_count_standard_unrestricted_pair(
    our_bb: u32,
    their_bb: u32,
    to: usize,
    our_from: Option<usize>,
) -> (u32, u32) {
    let mut our_bb = our_bb;
    if let Some(our_from) = our_from {
        our_bb &= !node_bit(our_from);
    }
    let mut our_count = 0_u32;
    let mut their_count = 0_u32;
    for &peer_mask in &STANDARD_MILL_LINE_PEER_MASKS_BY_NODE[to] {
        if peer_mask == 0 {
            break;
        }
        our_count += u32::from((our_bb & peer_mask) == peer_mask);
        their_count += u32::from((their_bb & peer_mask) == peer_mask);
    }
    (our_count, their_count)
}

#[cfg(test)]
#[inline(always)]
fn is_piece_in_mill(state: &MillState, options: &MillVariantOptions, node: usize) -> bool {
    let piece = live_piece(state, node);
    if piece == 0 {
        return false;
    }
    if state.delayed_marked_pieces == 0 {
        let Some(color) = color_index_for_piece(piece) else {
            return false;
        };
        let color_bb = state.by_color_bb[color];
        return mill_line_peer_masks_for_node(options, node)
            .iter()
            .take_while(|peer_mask| **peer_mask != 0)
            .any(|peer_mask| (color_bb & *peer_mask) == *peer_mask);
    }
    let lines = mill_lines(options);
    mill_line_indices_for_node(options, node)
        .iter()
        .take_while(|line_idx| **line_idx != NO_MILL_LINE)
        .any(|line_idx| {
            lines[*line_idx as usize]
                .iter()
                .all(|idx| live_piece(state, *idx) == piece)
        })
}

#[inline(always)]
fn mill_members_mask_for_color(
    state: &MillState,
    options: &MillVariantOptions,
    color: usize,
) -> u32 {
    debug_assert!(color < 2);
    let color_bb = state.by_color_bb[color];
    let mut members = 0_u32;
    for &line_mask in mill_line_masks(options) {
        // Stockfish keeps full-line bitboards such as LineBB so repeated
        // geometry questions become set algebra.  Mill lines are only
        // three nodes, but remove/capture filtering asks the same
        // "which of this side's pieces are protected by mills?" question
        // several times per node.  Building the union once keeps the
        // unusual hex-free masks maintainable and preserves exact rules:
        // `by_color_bb` contains live pieces only, so delayed-marked
        // squares are not treated as mill members.
        if (color_bb & line_mask) == line_mask {
            members |= line_mask;
        }
    }
    members
}

#[inline(always)]
fn mill_members_mask_for_piece(state: &MillState, options: &MillVariantOptions, piece: i8) -> u32 {
    let Some(color) = color_index_for_piece(piece) else {
        return 0;
    };
    mill_members_mask_for_color(state, options, color)
}

#[inline(always)]
fn mill_line_indices_for_node(
    options: &MillVariantOptions,
    node: usize,
) -> &'static [u8; MAX_MILL_LINES_PER_NODE] {
    debug_assert!(node < 24, "node {node} out of range");
    if options.has_diagonal_lines {
        &DIAGONAL_MILL_LINE_INDICES_BY_NODE[node]
    } else {
        &STANDARD_MILL_LINE_INDICES_BY_NODE[node]
    }
}

#[inline(always)]
fn mill_line_peer_masks_for_node(
    options: &MillVariantOptions,
    node: usize,
) -> &'static [u32; MAX_MILL_LINES_PER_NODE] {
    debug_assert!(node < 24, "node {node} out of range");
    if options.has_diagonal_lines {
        &DIAGONAL_MILL_LINE_PEER_MASKS_BY_NODE[node]
    } else {
        &STANDARD_MILL_LINE_PEER_MASKS_BY_NODE[node]
    }
}

#[inline(always)]
fn mill_lines(options: &MillVariantOptions) -> &'static [[usize; 3]] {
    if options.has_diagonal_lines {
        DIAGONAL_MILL_LINES
    } else {
        STANDARD_MILL_LINES
    }
}

#[inline(always)]
fn mill_line_masks(options: &MillVariantOptions) -> &'static [u32] {
    if options.has_diagonal_lines {
        &DIAGONAL_MILL_LINE_MASKS
    } else {
        &STANDARD_MILL_LINE_MASKS
    }
}

#[inline(always)]
const fn node_bit(node: usize) -> u32 {
    1_u32 << node
}

#[cfg(test)]
mod tests;
