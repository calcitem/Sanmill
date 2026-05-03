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
    Action, ActionList, BoardTopology, Evaluator, Game, GameRules, GameStateSnapshot, Outcome,
    OutcomeKind, Workbench, OPAQUE_PAYLOAD_LEN,
};

use crate::topology::MillTopology;

mod captures;
mod evaluation;
mod fen;
mod legacy_squares;
mod lines;
mod move_priority;
mod transitions;

use fen::{append_capture_field, parse_capture_field, position_key};
use transitions::{
    apply_removal_based_on_mill_counts, bump_ply_since_capture, clear_key_history,
    enter_moving_phase, is_action_within_board_bounds, is_marked, live_piece,
    maybe_draw_by_n_move_rule, maybe_finish_full_board, maybe_stop_placing_when_two_empty,
    maybe_transition_to_moving, note_mill_formation, push_key_and_check_threefold,
    removal_count_for_bits, repetition_signature, sync_phase_for_may_move_in_placing,
    usable_mill_bits,
};

#[cfg(test)]
use evaluation::is_all_surrounded;
use evaluation::{
    gameover_value, mills_pieces_count_difference, mobility_diff, remove_move_score,
    should_consider_mobility, should_focus_on_blocking_paths, surrounded_pieces_count,
};

#[cfg(test)]
use captures::is_all_in_mills;
use captures::{
    activate_capture_state, active_capture_lines, capture_phase_allowed,
    capture_piece_count_allowed_leap, capture_total, clear_capture_state,
    clear_capture_state_for_side, detect_custodian_targets, detect_intervention_targets,
    detect_leap_targets, find_paired_intervention_target, is_adjacent_to_side_piece,
    leap_capture_target_is_removable,
};
use legacy_squares::{
    legacy_square_bb_to_node_bb, legacy_square_to_node_signed, node_bb_to_legacy_square_bb,
    node_to_legacy_square,
};
use lines::{DIAGONAL_MILL_LINES, STANDARD_MILL_LINES};
use move_priority::{
    default_dense_priority, is_star_square, move_priority_list_for_search, RATING_BLOCK_ONE_MILL,
    RATING_ONE_MILL, RATING_STAR_SQUARE,
};
#[cfg(test)]
use move_priority::{PRIORITY_DIAGONAL, PRIORITY_NO_DIAGONAL, PRIORITY_SKILL_1};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(i16)]
pub enum MillActionKind {
    Place = 0,
    Move = 1,
    Remove = 2,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(i16)]
pub enum MillPhase {
    Ready = 0,
    Placing = 1,
    Moving = 2,
    GameOver = 3,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
enum MillActionState {
    Place = 0,
    Select = 1,
    Remove = 2,
    GameOver = 3,
}

impl MillActionState {
    fn from_fen_token(token: &str) -> Self {
        match token {
            "p" => Self::Place,
            "s" => Self::Select,
            "r" => Self::Remove,
            _ => Self::GameOver,
        }
    }

    fn to_fen_token(self) -> char {
        match self {
            Self::Place => 'p',
            Self::Select => 's',
            Self::Remove => 'r',
            Self::GameOver => '?',
        }
    }

    fn from_payload(value: u8) -> Self {
        match value {
            0 => Self::Place,
            1 => Self::Select,
            2 => Self::Remove,
            3 => Self::GameOver,
            _ => Self::Place,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(i16)]
pub enum MillBoardFullAction {
    FirstPlayerLose = 0,
    FirstAndSecondPlayerRemovePiece = 1,
    SecondAndFirstPlayerRemovePiece = 2,
    SideToMoveRemovePiece = 3,
    AgreeToDraw = 4,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(i16)]
pub enum MillFormationActionInPlacingPhase {
    RemoveOpponentsPieceFromBoard = 0,
    RemoveOpponentsPieceFromHandThenOpponentsTurn = 1,
    RemoveOpponentsPieceFromHandThenYourTurn = 2,
    OpponentRemovesOwnPiece = 3,
    MarkAndDelayRemovingPieces = 4,
    RemovalBasedOnMillCounts = 5,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(i16)]
pub enum StalemateAction {
    EndWithStalemateLoss = 0,
    ChangeSideToMove = 1,
    RemoveOpponentsPieceAndMakeNextMove = 2,
    RemoveOpponentsPieceAndChangeSideToMove = 3,
    EndWithStalemateDraw = 4,
    BothPlayersRemoveOpponentsPiece = 5,
}

#[derive(Clone, Debug)]
pub struct CaptureRuleConfig {
    pub enabled: bool,
    pub on_square_edges: bool,
    pub on_cross_lines: bool,
    /// When true with `MillVariantOptions.has_diagonal_lines`, diagonal
    /// three-point lines participate in custodian / intervention / leap
    /// detection (same geometry as `MillTopology::with_diagonals`).
    pub on_diagonal_lines: bool,
    pub in_placing_phase: bool,
    pub in_moving_phase: bool,
    pub only_available_when_own_pieces_leq3: bool,
}

impl Default for CaptureRuleConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            on_square_edges: true,
            on_cross_lines: true,
            on_diagonal_lines: true,
            in_placing_phase: true,
            in_moving_phase: true,
            only_available_when_own_pieces_leq3: false,
        }
    }
}

#[derive(Clone, Debug)]
pub struct MillVariantOptions {
    pub piece_count: u8,
    pub fly_piece_count: u8,
    pub pieces_at_least_count: u8,
    pub may_fly: bool,
    pub has_diagonal_lines: bool,
    pub mill_formation_action_in_placing_phase: MillFormationActionInPlacingPhase,
    /// When true a player capturing a piece may target a piece sitting in
    /// an opponent mill even if non-mill alternatives exist.  Mirrors
    /// `Rule::mayRemoveFromMillsAlways` in the legacy C++ engine.
    pub may_remove_from_mills_always: bool,
    /// When true forming two mills at once entitles the active player to
    /// two captures.  Mirrors `Rule::mayRemoveMultiple`.
    pub may_remove_multiple: bool,
    /// Soft draw counter: when both players exceed this many plies
    /// without a mill or capture, the game ends in a draw.  0 disables
    /// the rule (mirrors `Rule::nMoveRule`).  Currently only checked at
    /// the moving phase boundary; capture extends the counter back to 0.
    pub n_move_rule: u32,
    pub endgame_n_move_rule: u32,
    pub may_move_in_placing_phase: bool,
    pub is_defender_move_first: bool,
    pub restrict_repeated_mills_formation: bool,
    pub one_time_use_mill: bool,
    pub stop_placing_when_two_empty_squares: bool,
    pub board_full_action: MillBoardFullAction,
    /// Enable the FIDE-style threefold-repetition draw rule: when the
    /// same moving-phase position recurs three times the engine sets
    /// `phase=GameOver` and `outcome=Draw{drawThreefoldRepetition}`.  Default is
    /// `true`, matching the C++ engine's `rule.threefoldRepetitionRule`.
    pub threefold_repetition_rule: bool,
    pub custodian_capture: CaptureRuleConfig,
    pub intervention_capture: CaptureRuleConfig,
    pub leap_capture: CaptureRuleConfig,
    pub stalemate_action: StalemateAction,
    /// Mirror of `gameOptions.getConsiderMobility()` from the legacy C++
    /// engine.  When true [`MillEvaluator`] adds a mobility-difference
    /// term in the placing/moving phases.  Default `true` matches
    /// `gameOptions` initialisation in `option.h`.
    pub consider_mobility: bool,
    /// Mirror of `gameOptions.getFocusOnBlockingPaths()` from the legacy
    /// C++ engine.  When true the static evaluator drops the material
    /// difference from the score so the search prioritises mobility-only
    /// blocking lines (only meaningful in the moving phase / fly endgame).
    pub focus_on_blocking_paths: bool,
}

impl Default for MillVariantOptions {
    fn default() -> Self {
        Self {
            piece_count: 9,
            fly_piece_count: 3,
            pieces_at_least_count: 3,
            may_fly: true,
            has_diagonal_lines: false,
            mill_formation_action_in_placing_phase:
                MillFormationActionInPlacingPhase::RemoveOpponentsPieceFromBoard,
            may_remove_from_mills_always: false,
            may_remove_multiple: false,
            n_move_rule: 100,
            endgame_n_move_rule: 100,
            may_move_in_placing_phase: false,
            is_defender_move_first: false,
            restrict_repeated_mills_formation: false,
            one_time_use_mill: false,
            stop_placing_when_two_empty_squares: false,
            board_full_action: MillBoardFullAction::FirstPlayerLose,
            threefold_repetition_rule: true,
            custodian_capture: CaptureRuleConfig::default(),
            intervention_capture: CaptureRuleConfig::default(),
            leap_capture: CaptureRuleConfig::default(),
            stalemate_action: StalemateAction::EndWithStalemateLoss,
            consider_mobility: true,
            focus_on_blocking_paths: false,
        }
    }
}

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

    fn encode(&self, state: MillState) -> GameStateSnapshot {
        GameStateSnapshot {
            side_to_move: state.side_to_move,
            phase_tag: state.phase as i16,
            move_number: state.move_number,
            zobrist_key: position_key(&state),
            opaque_payload: state.encode(),
        }
    }

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

impl Workbench for MillWorkbench {
    fn snapshot(&self) -> GameStateSnapshot {
        self.rules.encode(self.state.clone())
    }

    fn key(&self) -> u64 {
        position_key(&self.state)
    }

    fn side_to_move(&self) -> i8 {
        self.state.side_to_move
    }

    fn is_terminal(&self) -> bool {
        self.state.phase == MillPhase::GameOver
    }

    fn do_move(&mut self, a: Action) {
        self.undo_stack.push(self.state.clone());
        let next = self.rules.apply(&self.snapshot(), a);
        self.state = MillRules::decode(&next);
    }

    fn undo_move(&mut self) {
        if let Some(prev) = self.undo_stack.pop() {
            self.state = prev;
        }
    }
}

impl Evaluator<MillWorkbench> for MillEvaluator {
    /// Static evaluator translated from `src/evaluate.cpp::Evaluation::value`
    /// in the legacy C++ engine.
    ///
    /// The constants are scaled to the same units as `VALUE_EACH_PIECE`
    /// (`PieceValue = 5`) and `VALUE_MATE = 80`, so search scores stay
    /// numerically compatible with the legacy `MTDF` aspiration windows.
    /// A perspective swap at the end mirrors C++ "value from the side to
    /// move" convention.
    fn score(wb: &MillWorkbench) -> i32 {
        const VALUE_EACH_PIECE: i32 = 5;
        const VALUE_MATE: i32 = 80;
        const VALUE_DRAW: i32 = 0;

        let state = &wb.state;
        let options = &wb.rules.options;
        let mut value: i32 = 0;

        let removals_diff =
            i32::from(state.pending_removals[0]) - i32::from(state.pending_removals[1]);
        let in_hand_diff = i32::from(state.pieces_in_hand[0]) - i32::from(state.pieces_in_hand[1]);
        let on_board_diff =
            i32::from(state.pieces_on_board[0]) - i32::from(state.pieces_on_board[1]);
        let action_is_remove = state.pending_removals[0] > 0 || state.pending_removals[1] > 0;

        match state.phase {
            MillPhase::Ready => {}
            MillPhase::Placing
                if matches!(
                    options.mill_formation_action_in_placing_phase,
                    MillFormationActionInPlacingPhase::RemovalBasedOnMillCounts
                ) =>
            {
                if action_is_remove {
                    value += VALUE_EACH_PIECE * removals_diff;
                } else {
                    value += mills_pieces_count_difference(state, options);
                }
            }
            MillPhase::Placing | MillPhase::Moving => {
                if should_consider_mobility(options) {
                    value += mobility_diff(state, options);
                }
                if !should_focus_on_blocking_paths(state, options) {
                    value += VALUE_EACH_PIECE * in_hand_diff;
                    value += VALUE_EACH_PIECE * on_board_diff;
                    if action_is_remove {
                        value += VALUE_EACH_PIECE * removals_diff;
                    }
                }
            }
            MillPhase::GameOver => {
                value = gameover_value(state, options, VALUE_MATE, VALUE_DRAW);
            }
        }

        if state.side_to_move == 1 {
            value = -value;
        }
        value
    }
}

impl Game for MillGame {
    type Workbench = MillWorkbench;
    type Evaluator = MillEvaluator;

    fn build_workbench(&self, snap: &GameStateSnapshot) -> Self::Workbench {
        let rules = MillRules::new(self.options.clone());
        let state = MillRules::decode(snap);
        MillWorkbench {
            rules,
            state,
            undo_stack: Vec::new(),
        }
    }

    fn generate_legal(wb: &Self::Workbench, out: &mut ActionList<256>) {
        wb.rules.legal_actions(&wb.snapshot(), out);
    }

    fn generate_legal_ctx(
        wb: &Self::Workbench,
        out: &mut ActionList<256>,
        ctx: &tgf_core::MoveOrderContext,
    ) {
        wb.rules.legal_actions_ctx(&wb.state, out, ctx);
    }

    /// MovePicker-style move ordering bonus translated from
    /// `src/movepick.cpp::score()`.  Combines mill formation, mill blocking,
    /// star-square opening preference, and capture-target preference.  The
    /// numeric weights match `RATING_*` constants in `src/types.h`; killer /
    /// history / TT bonuses are still applied in `Searcher::move_score`.
    #[inline]
    fn move_order_bias_ctx(
        wb: &Self::Workbench,
        action: Action,
        ctx: &tgf_core::MoveOrderContext,
    ) -> i32 {
        let to = action.to_node as usize;
        if to >= 24 {
            return 0;
        }
        let state = &wb.state;
        let options = &wb.rules.options;
        let kind = action.kind_tag;

        if kind == MillActionKind::Remove as i16 {
            return remove_move_score(state, options, to);
        }

        if kind != MillActionKind::Place as i16 && kind != MillActionKind::Move as i16 {
            return 0;
        }

        let side = state.side_to_move;
        let opponent = side ^ 1;
        let from = if kind == MillActionKind::Move as i16 {
            Some(action.from_node as usize)
        } else {
            None
        };

        let our_mills = potential_mills_count_at(state, options, to, side, from) as i32;
        let mut score = 0_i32;
        if our_mills > 0 {
            score += RATING_ONE_MILL * our_mills;
        } else if state.phase == MillPhase::Placing && !options.may_move_in_placing_phase {
            let their_mills = potential_mills_count_at(state, options, to, opponent, from) as i32;
            score += RATING_BLOCK_ONE_MILL * their_mills;
        } else if state.phase == MillPhase::Moving
            || (state.phase == MillPhase::Placing && options.may_move_in_placing_phase)
        {
            let their_mills = potential_mills_count_at(state, options, to, opponent, from) as i32;
            if their_mills > 0 {
                let (_, theirs, _) = surrounded_pieces_count(state, options, to);
                let parity_match = if to.is_multiple_of(2) {
                    theirs == 3
                } else {
                    theirs == 2
                };
                if parity_match {
                    score += RATING_BLOCK_ONE_MILL * their_mills;
                }
            }
        }

        if state.phase == MillPhase::Placing
            && side == 1
            && state.board.iter().filter(|&&p| p == 2).count() < 2
            && (options.has_diagonal_lines || ctx.algorithm == tgf_core::MoveOrderAlgorithm::Mcts)
            && is_star_square(options, to)
        {
            score += RATING_STAR_SQUARE;
        }

        score
    }

    #[inline]
    fn terminal_score(wb: &Self::Workbench, perspective: i8, depth: i32) -> Option<i32> {
        if wb.state.phase != MillPhase::GameOver {
            return None;
        }
        if wb.state.winner == 2 {
            return Some(0);
        }
        let distance = depth.max(0);
        if wb.state.winner == perspective {
            Some(MILL_TERMINAL_WIN_SCORE + distance)
        } else {
            Some(-MILL_TERMINAL_WIN_SCORE - distance)
        }
    }
}

impl GameRules for MillRules {
    fn game_id(&self) -> &str {
        "mill"
    }

    fn topology(&self) -> &dyn BoardTopology {
        &self.topology
    }

    fn initial_state(&self, _variant_options: &[u8]) -> GameStateSnapshot {
        let state = MillState {
            board: [0; 24],
            side_to_move: 0,
            phase: MillPhase::Placing,
            move_number: 0,
            pieces_in_hand: [self.options.piece_count, self.options.piece_count],
            pieces_on_board: [0, 0],
            pending_removals: [0, 0],
            winner: -1,
            ..MillState::default()
        };
        self.encode(state)
    }

    fn legal_actions(&self, snap: &GameStateSnapshot, out: &mut ActionList<256>) {
        let state = Self::decode(snap);
        match state.action_for_legal_generation() {
            MillActionState::Remove => {
                if state.pending_removals[state.side_to_move as usize] > 0 {
                    self.generate_remove_actions(&state, out, &default_dense_priority());
                }
            }
            MillActionState::Place => {
                if state.pieces_in_hand[state.side_to_move as usize] > 0 {
                    for (node, piece) in state.board.iter().enumerate() {
                        if *piece == 0 {
                            out.push(Action {
                                kind_tag: MillActionKind::Place as i16,
                                from_node: -1,
                                to_node: node as i16,
                                aux: -1,
                                payload_bits: 0,
                            });
                        }
                    }
                }
                if self.options.may_move_in_placing_phase {
                    self.generate_move_actions(&state, out, false);
                }
            }
            MillActionState::Select => {
                if state.phase == MillPhase::Moving {
                    self.generate_move_actions(&state, out, true);
                }
            }
            MillActionState::GameOver => {}
        }
    }

    fn apply(&self, snap: &GameStateSnapshot, action: Action) -> GameStateSnapshot {
        // Memory-safety guard: even on the "unchecked" apply path the
        // caller may have supplied an out-of-range `from_node` or
        // `to_node` (see FRB `tgf_kernel_apply_unchecked`).  Reject such
        // actions up-front by returning the input snapshot unchanged so
        // we never index `state.board[..]` out of bounds.  Game-level
        // legality (mill formation, side-to-move, phase, capture
        // policies, …) is still the caller's responsibility — the
        // `*_unchecked` contract is "skip the slow legal-action lookup",
        // not "open up a memory-safety hole".
        if !is_action_within_board_bounds(&action) {
            return *snap;
        }
        let mut state = Self::decode(snap);
        match action.kind_tag {
            x if x == MillActionKind::Place as i16 => {
                let to = action.to_node as usize;
                debug_assert!(state.board[to] == 0);
                let side = state.side_to_move as usize;
                state.board[to] = state.side_to_move + 1;
                state.pieces_in_hand[side] = state.pieces_in_hand[side].saturating_sub(1);
                state.pieces_on_board[side] += 1;
                state.move_number += 1;
                state.ply_since_capture = 0;
                // Placing a new piece is irreversible: any rolling
                // repetition history accumulated in the moving phase
                // becomes irrelevant.
                clear_key_history(&mut state);
                let custodian = detect_custodian_targets(&state, &self.options, to);
                let intervention = detect_intervention_targets(&state, &self.options, to);
                let mill_bits = formed_mill_bits_at(&state, &self.options, to, state.side_to_move);
                let usable_bits = usable_mill_bits(&state, &self.options, mill_bits);
                if usable_bits != 0 {
                    let removals = removal_count_for_bits(usable_bits, &self.options);
                    match self.options.mill_formation_action_in_placing_phase {
                        MillFormationActionInPlacingPhase::RemoveOpponentsPieceFromHandThenOpponentsTurn
                        | MillFormationActionInPlacingPhase::RemoveOpponentsPieceFromHandThenYourTurn => {
                            let opponent = side ^ 1;
                            let hand_removed = removals.min(state.pieces_in_hand[opponent]);
                            state.pieces_in_hand[opponent] -= hand_removed;
                            let remaining = removals - hand_removed;
                            if remaining > 0 {
                                state.pending_removals[side] = remaining;
                                state.mill_available_at_removal = true;
                                sync_action_state(&mut state);
                            } else {
                                state.side_to_move = if matches!(
                                    self.options.mill_formation_action_in_placing_phase,
                                    MillFormationActionInPlacingPhase::RemoveOpponentsPieceFromHandThenOpponentsTurn
                                ) {
                                    (side ^ 1) as i8
                                } else {
                                    side as i8
                                };
                                maybe_transition_to_moving(&mut state, &self.options);
                                sync_phase_for_may_move_in_placing(&mut state, &self.options);
                                maybe_finish_full_board(&mut state, &self.options);
                                sync_action_state(&mut state);
                            }
                            clear_capture_state(&mut state);
                        }
                        MillFormationActionInPlacingPhase::OpponentRemovesOwnPiece => {
                            let opponent = side ^ 1;
                            state.side_to_move = opponent as i8;
                            state.pending_removals[opponent] = removals;
                            state.mill_available_at_removal = false;
                            clear_capture_state(&mut state);
                            sync_action_state(&mut state);
                        }
                        MillFormationActionInPlacingPhase::MarkAndDelayRemovingPieces => {
                            // Same shape as the standard "remove opponent's
                            // piece from board" branch: pending_removals is
                            // armed and the opponent waits until the active
                            // side picks a target.  The Remove handler then
                            // diverts to marking instead of physical removal,
                            // and `maybe_transition_to_moving` sweeps every
                            // marked square at the placing-to-moving boundary
                            // (mirrors Position::remove_marked_pieces).
                            state.pending_removals[side] = removals;
                            state.mill_available_at_removal = true;
                            activate_capture_state(&mut state, custodian, intervention, 0);
                            if self.options.may_remove_multiple {
                                state.pending_removals[side] = state.pending_removals[side]
                                    .saturating_add(capture_total(&state));
                            }
                            sync_action_state(&mut state);
                        }
                        MillFormationActionInPlacingPhase::RemovalBasedOnMillCounts => {
                            clear_capture_state(&mut state);
                            if state.pieces_in_hand[0] == 0 && state.pieces_in_hand[1] == 0 {
                                apply_removal_based_on_mill_counts(&mut state, &self.options);
                            } else {
                                state.side_to_move ^= 1;
                            }
                            maybe_transition_to_moving(&mut state, &self.options);
                            sync_phase_for_may_move_in_placing(&mut state, &self.options);
                            maybe_finish_full_board(&mut state, &self.options);
                            sync_action_state(&mut state);
                        }
                        MillFormationActionInPlacingPhase::RemoveOpponentsPieceFromBoard => {
                            state.pending_removals[side] = removals;
                            state.mill_available_at_removal = true;
                            activate_capture_state(&mut state, custodian, intervention, 0);
                            if self.options.may_remove_multiple {
                                state.pending_removals[side] =
                                    state.pending_removals[side].saturating_add(capture_total(&state));
                            }
                            sync_action_state(&mut state);
                        }
                    }
                    note_mill_formation(&mut state, side, -1, to as i8, usable_bits, &self.options);
                } else if custodian != 0 || intervention != 0 {
                    activate_capture_state(&mut state, custodian, intervention, 0);
                    state.pending_removals[side] = capture_total(&state);
                    state.mill_available_at_removal = false;
                    sync_action_state(&mut state);
                } else {
                    clear_capture_state(&mut state);
                    // Mirror master src/position.cpp:1217 put_piece:
                    // StopPlacingWhenTwoEmptySquares is checked only after
                    // the no-mill/no-capture placing path has been selected.
                    // Mill formation and capture obligations must keep the
                    // remaining hand counts intact until their removal flow
                    // completes.
                    maybe_stop_placing_when_two_empty(&mut state, &self.options);
                    state.side_to_move ^= 1;
                    maybe_transition_to_moving(&mut state, &self.options);
                    sync_phase_for_may_move_in_placing(&mut state, &self.options);
                    maybe_finish_full_board(&mut state, &self.options);
                    sync_action_state(&mut state);
                }
            }
            x if x == MillActionKind::Move as i16 => {
                let from = action.from_node as usize;
                let to = action.to_node as usize;
                debug_assert_eq!(state.board[from], state.side_to_move + 1);
                debug_assert_eq!(state.board[to], 0);
                state.board[from] = 0;
                state.board[to] = state.side_to_move + 1;
                state.move_number += 1;
                let side = state.side_to_move as usize;
                bump_ply_since_capture(&mut state, &self.options);
                let custodian = detect_custodian_targets(&state, &self.options, to);
                let intervention = detect_intervention_targets(&state, &self.options, to);
                let leap = detect_leap_targets(&state, &self.options, from, to);
                let mill_bits = formed_mill_bits_at(&state, &self.options, to, state.side_to_move);
                let usable_bits = usable_mill_bits(&state, &self.options, mill_bits);
                if leap != 0 {
                    activate_capture_state(&mut state, 0, 0, leap);
                    state.pending_removals[side] = 1;
                    state.mill_available_at_removal = false;
                    sync_action_state(&mut state);
                } else if usable_bits != 0 {
                    state.pending_removals[side] =
                        removal_count_for_bits(usable_bits, &self.options);
                    state.mill_available_at_removal = true;
                    activate_capture_state(&mut state, custodian, intervention, 0);
                    if self.options.may_remove_multiple {
                        state.pending_removals[side] =
                            state.pending_removals[side].saturating_add(capture_total(&state));
                    }
                    note_mill_formation(
                        &mut state,
                        side,
                        from as i8,
                        to as i8,
                        usable_bits,
                        &self.options,
                    );
                    sync_action_state(&mut state);
                } else if custodian != 0 || intervention != 0 {
                    activate_capture_state(&mut state, custodian, intervention, 0);
                    state.pending_removals[side] = capture_total(&state);
                    state.mill_available_at_removal = false;
                    sync_action_state(&mut state);
                } else {
                    clear_capture_state(&mut state);
                    // Clear the per-side last-mill record when no mill was
                    // formed.  Mirrors C++ position.cpp's
                    // `lastMillFromSquare[c] = SQ_NONE` / `lastMillToSquare[c] = SQ_NONE`
                    // in the non-mill branch of do_move().  Without this clear,
                    // `restrict_repeated_mills_formation` incorrectly blocks a
                    // later re-formation of the same mill even after the mover
                    // has made an intermediate non-mill move.
                    state.last_mill_from[side] = -1;
                    state.last_mill_to[side] = -1;
                    state.side_to_move ^= 1;
                    // Record this side-changing reversible move into the
                    // repetition history *before* deciding whether the
                    // n-move rule fires; threefold takes precedence and
                    // sets GameOver itself, after which the n-move check
                    // becomes a no-op (it inspects `state.phase`).
                    push_key_and_check_threefold(&mut state, &self.options);
                    maybe_draw_by_n_move_rule(&mut state, &self.options);
                    // Mirror C++ set_side_to_move phase sync for
                    // may_move_in_placing_phase variant.
                    sync_phase_for_may_move_in_placing(&mut state, &self.options);
                    sync_action_state(&mut state);
                }
            }
            x if x == MillActionKind::Remove as i16 => {
                let to = action.to_node as usize;
                let side = state.side_to_move as usize;
                let opponent = (state.side_to_move ^ 1) as usize;
                let removing_own = side < 2 && state.remove_own_piece[side];
                let target_color_index = if removing_own { side } else { opponent };
                debug_assert_eq!(state.board[to], target_color_index as i8 + 1);
                debug_assert!(state.pending_removals[side] > 0);
                let mask = node_bit(to);
                let is_custodian =
                    (state.custodian_targets[side] & mask) != 0 && state.custodian_count[side] > 0;
                let is_intervention = (state.intervention_targets[side] & mask) != 0
                    && state.intervention_count[side] > 0;
                let is_leap = (state.leap_targets[side] & mask) != 0 && state.leap_count[side] > 0;
                let cap_total = capture_total(&state);
                let remaining_before = state.pending_removals[side];

                if is_intervention {
                    state.mill_available_at_removal = false;
                    state.custodian_targets[side] = 0;
                    state.custodian_count[side] = 0;
                    state.leap_targets[side] = 0;
                    state.leap_count[side] = 0;
                    state.pending_removals[side] = state.intervention_count[side];
                } else if is_custodian {
                    state.mill_available_at_removal = false;
                    state.intervention_targets[side] = 0;
                    state.intervention_count[side] = 0;
                    state.leap_targets[side] = 0;
                    state.leap_count[side] = 0;
                    state.pending_removals[side] = 1;
                } else if is_leap {
                    state.mill_available_at_removal = false;
                    state.custodian_targets[side] = 0;
                    state.custodian_count[side] = 0;
                    state.intervention_targets[side] = 0;
                    state.intervention_count[side] = 0;
                    state.pending_removals[side] = 1;
                } else if state.mill_available_at_removal && cap_total > 0 {
                    if self.options.may_remove_multiple && remaining_before > cap_total {
                        state.pending_removals[side] = remaining_before.saturating_sub(cap_total);
                    }
                    clear_capture_state_for_side(&mut state, side);
                    state.mill_available_at_removal = true;
                } else {
                    debug_assert!(
                        cap_total == 0 || state.mill_available_at_removal,
                        "capture obligation must remove a capture target"
                    );
                }

                let mark_pending = matches!(
                    self.options.mill_formation_action_in_placing_phase,
                    MillFormationActionInPlacingPhase::MarkAndDelayRemovingPieces
                ) && state.phase == MillPhase::Placing
                    && !removing_own;
                if mark_pending {
                    // Preserve the original colour in `state.board` so that
                    // the UI can render the X overlay; flag the square in
                    // `delayed_marked_pieces` so every rule predicate
                    // (`live_piece`, `is_marked`) treats the cell as empty
                    // until the placing-to-moving sweep clears it.
                    state.delayed_marked_pieces |= mask;
                } else {
                    state.board[to] = 0;
                }
                state.pieces_on_board[target_color_index] =
                    state.pieces_on_board[target_color_index].saturating_sub(1);
                state.pending_removals[side] = state.pending_removals[side].saturating_sub(1);
                if is_custodian {
                    state.custodian_targets[side] &= !mask;
                    state.custodian_count[side] = state.custodian_count[side].saturating_sub(1);
                    if state.custodian_count[side] == 0 {
                        state.custodian_targets[side] = 0;
                    }
                }
                if is_intervention {
                    state.intervention_targets[side] &= !mask;
                    state.intervention_count[side] =
                        state.intervention_count[side].saturating_sub(1);
                    if state.intervention_count[side] == 0 {
                        state.intervention_targets[side] = 0;
                    } else {
                        state.intervention_targets[side] = find_paired_intervention_target(
                            to,
                            state.intervention_targets[side] | mask,
                            &self.options,
                        );
                    }
                }
                if is_leap {
                    state.leap_targets[side] &= !mask;
                    state.leap_count[side] = state.leap_count[side].saturating_sub(1);
                    if state.leap_count[side] == 0 {
                        state.leap_targets[side] = 0;
                    }
                }
                state.ply_since_capture = 0;
                // Capturing changes material — restart the rolling
                // repetition window.
                clear_key_history(&mut state);
                // P0-B.1: Mirror master remove_piece L1834-1838 which checks
                // `pieceOnBoardCount[them] + pieceInHandCount[them] < piecesAtLeastCount`
                // WITHOUT a phase guard. The original Rust code only checked
                // in Moving phase and omitted in-hand count; both are fixed here.
                let pieces_total = u32::from(state.pieces_on_board[target_color_index])
                    + u32::from(state.pieces_in_hand[target_color_index]);
                if state.pieces_in_hand == [0, 0]
                    && pieces_total < u32::from(self.options.pieces_at_least_count)
                {
                    state.phase = MillPhase::GameOver;
                    state.winner = if removing_own {
                        opponent as i8
                    } else {
                        state.side_to_move
                    };
                    state.outcome_reason = MillOutcomeReason::LoseFewerThanThree;
                    state.side_to_move = -1;
                } else if state.pending_removals[side] == 0 {
                    clear_capture_state_for_side(&mut state, side);
                    if removing_own {
                        // Negative pieceToRemoveCount cleared its quota; flip
                        // the flag so the next removal (if scheduled) reverts
                        // to opponent-targeting semantics.
                        state.remove_own_piece[side] = false;
                    }
                    if state.stalemate_removing {
                        state.stalemate_removing = false;
                    } else {
                        state.side_to_move ^= 1;
                    }
                    if state.both_stalemate_removing && state.pending_removals == [0, 0] {
                        state.both_stalemate_removing = false;
                    }
                    if state.board_full_removing && state.pending_removals == [0, 0] {
                        state.board_full_removing = false;
                    }
                    maybe_transition_to_moving(&mut state, &self.options);
                    sync_phase_for_may_move_in_placing(&mut state, &self.options);
                    maybe_finish_full_board(&mut state, &self.options);
                    sync_action_state(&mut state);
                }
            }
            _ => {}
        }
        self.maybe_handle_stalemate(&mut state);
        self.encode(state)
    }

    fn outcome(&self, snap: &GameStateSnapshot) -> Outcome {
        let state = Self::decode(snap);
        if state.phase == MillPhase::GameOver {
            if state.winner == 2 {
                return Outcome {
                    kind: OutcomeKind::Draw,
                    reason: match state.outcome_reason {
                        MillOutcomeReason::DrawFullBoard => "drawFullBoard",
                        // Legacy value kept for deserialized snapshots.
                        MillOutcomeReason::DrawNMoveRule => "drawFiftyMove",
                        MillOutcomeReason::DrawFiftyMove => "drawFiftyMove",
                        MillOutcomeReason::DrawEndgameFiftyMove => "drawEndgameFiftyMove",
                        MillOutcomeReason::DrawThreefold => "drawThreefoldRepetition",
                        MillOutcomeReason::DrawStalemate => "drawStalemateCondition",
                        _ => "draw",
                    }
                    .to_owned(),
                };
            }
            Outcome {
                kind: OutcomeKind::Win(state.winner),
                reason: match state.outcome_reason {
                    MillOutcomeReason::LoseFullBoard => "loseFullBoard",
                    MillOutcomeReason::LoseFewerThanThree => "loseFewerThanThree",
                    MillOutcomeReason::LoseNoLegalMoves => "loseNoLegalMoves",
                    _ => "loseFewerThanThree",
                }
                .to_owned(),
            }
        } else {
            Outcome {
                kind: OutcomeKind::Ongoing,
                reason: "ongoing".to_owned(),
            }
        }
    }
}

impl MillRules {
    fn legal_actions_ctx(
        &self,
        state: &MillState,
        out: &mut ActionList<256>,
        ctx: &tgf_core::MoveOrderContext,
    ) {
        let priority = move_priority_list_for_search(&self.options, ctx);
        match state.action_for_legal_generation() {
            MillActionState::Remove => {
                if state.pending_removals[state.side_to_move as usize] > 0 {
                    self.generate_remove_actions(state, out, &priority);
                }
            }
            MillActionState::Place => {
                if state.pieces_in_hand[state.side_to_move as usize] > 0 {
                    for &node in &priority {
                        if state.board[node] == 0 {
                            out.push(Action {
                                kind_tag: MillActionKind::Place as i16,
                                from_node: -1,
                                to_node: node as i16,
                                aux: -1,
                                payload_bits: 0,
                            });
                        }
                    }
                }
                if self.options.may_move_in_placing_phase {
                    self.generate_move_actions_with_priority(state, out, false, &priority);
                }
            }
            MillActionState::Select => {
                if state.phase == MillPhase::Moving {
                    self.generate_move_actions_with_priority(state, out, true, &priority);
                }
            }
            MillActionState::GameOver => {}
        }
    }

    fn has_legal_move(&self, state: &MillState) -> bool {
        if state.phase != MillPhase::Moving {
            return true;
        }
        let mut actions = ActionList::<256>::new();
        self.generate_move_actions(state, &mut actions, true);
        !actions.is_empty()
    }

    fn maybe_handle_stalemate(&self, state: &mut MillState) {
        if state.phase != MillPhase::Moving
            || state.side_to_move < 0
            || state.pending_removals[state.side_to_move as usize] != 0
            || self.has_legal_move(state)
        {
            return;
        }

        match self.options.stalemate_action {
            StalemateAction::EndWithStalemateLoss => {
                state.phase = MillPhase::GameOver;
                state.winner = state.side_to_move ^ 1;
                state.outcome_reason = MillOutcomeReason::LoseNoLegalMoves;
                state.side_to_move = -1;
            }
            StalemateAction::ChangeSideToMove => {
                state.side_to_move ^= 1;
            }
            StalemateAction::RemoveOpponentsPieceAndMakeNextMove => {
                let side = state.side_to_move as usize;
                state.pending_removals[side] = 1;
                state.stalemate_removing = true;
                state.mill_available_at_removal = false;
                clear_capture_state(state);
            }
            StalemateAction::RemoveOpponentsPieceAndChangeSideToMove => {
                let side = state.side_to_move as usize;
                state.pending_removals[side] = 1;
                state.mill_available_at_removal = false;
                clear_capture_state(state);
            }
            StalemateAction::EndWithStalemateDraw => {
                state.phase = MillPhase::GameOver;
                state.winner = 2;
                state.outcome_reason = MillOutcomeReason::DrawStalemate;
                state.side_to_move = -1;
            }
            StalemateAction::BothPlayersRemoveOpponentsPiece => {
                let side = state.side_to_move as usize;
                state.pending_removals[side] = 1;
                state.pending_removals[side ^ 1] = 1;
                state.both_stalemate_removing = true;
                state.mill_available_at_removal = false;
                clear_capture_state(state);
            }
        }
    }

    fn check_if_game_is_over(&self, state: &mut MillState) {
        if state.phase == MillPhase::GameOver || state.side_to_move < 0 {
            return;
        }
        // Mirror master src/position.cpp:2069 Position::check_if_game_is_over:
        // terminal conditions are evaluated after FEN import just as they are
        // after normal moves.
        maybe_finish_full_board(state, &self.options);
        if state.phase == MillPhase::GameOver {
            return;
        }
        maybe_draw_by_n_move_rule(state, &self.options);
        if state.phase == MillPhase::GameOver {
            return;
        }
        if state.phase == MillPhase::Moving {
            for side in 0..2 {
                let pieces_total =
                    u32::from(state.pieces_on_board[side]) + u32::from(state.pieces_in_hand[side]);
                if pieces_total < u32::from(self.options.pieces_at_least_count) {
                    state.phase = MillPhase::GameOver;
                    state.winner = (side ^ 1) as i8;
                    state.outcome_reason = MillOutcomeReason::LoseFewerThanThree;
                    state.side_to_move = -1;
                    return;
                }
            }
        }
        self.maybe_handle_stalemate(state);
    }

    fn generate_move_actions(&self, state: &MillState, out: &mut ActionList<256>, allow_fly: bool) {
        let priority = default_dense_priority();
        self.generate_move_actions_with_priority(state, out, allow_fly, &priority);
    }

    fn generate_move_actions_with_priority(
        &self,
        state: &MillState,
        out: &mut ActionList<256>,
        allow_fly: bool,
        priority: &[usize; 24],
    ) {
        let side = state.side_to_move as usize;
        // Mirror master src/movegen.cpp:87 generate<MOVE> and
        // src/movegen.cpp:157 generate<LEGAL>: movement, including
        // Lasker-style leap and fly moves, is only generated when the active
        // side has no pieces left in hand.
        let no_pieces_in_hand = state.pieces_in_hand[side] == 0;
        let can_fly = allow_fly
            && self.options.may_fly
            && no_pieces_in_hand
            && state.pieces_on_board[side] <= self.options.fly_piece_count;
        let opponent_color = (state.side_to_move ^ 1) + 1;
        // Leap moves are emitted *in addition to* regular adjacency moves
        // (mirrors master generate<MOVE>'s `tryAddLeap` superset).  They
        // require leap_capture.enabled, the active phase to be allowed,
        // and — when in placing — that may_move_in_placing_phase opens
        // movement.  In fly state, every empty square is already
        // reachable so the leap superset is redundant.
        // Use capture_piece_count_allowed_leap (not the generic variant) so that
        // onlyAvailableWhenOwnPiecesLeq3 is enforced in placing phase too,
        // matching master's checkLeapCapture which checks the condition outside
        // any phase guard.
        let leap_enabled = !can_fly
            && no_pieces_in_hand
            && self.options.leap_capture.enabled
            && capture_phase_allowed(&self.options.leap_capture, state.phase)
            && capture_piece_count_allowed_leap(&self.options.leap_capture, state)
            && (state.phase == MillPhase::Moving
                || (state.phase == MillPhase::Placing
                    && self.options.may_move_in_placing_phase
                    && self.options.leap_capture.in_placing_phase));
        for &from in priority.iter().rev() {
            // Use live_piece() rather than the raw board value so that
            // mark-and-delay MARKED_PIECE squares are treated as empty
            // (not movable) — mirrors C++ generate<MOVE>'s byColorBB filter.
            if live_piece(state, from) != state.side_to_move + 1 {
                continue;
            }
            if can_fly {
                for to in 0_usize..24 {
                    if state.board[to] == 0 && !self.is_restricted_repeated_mill(state, from, to) {
                        out.push(move_action(from, to));
                    }
                }
                continue;
            }
            for &to in self.topology.neighbors(from as u16) {
                let to = to as usize;
                if state.board[to] == 0 && !self.is_restricted_repeated_mill(state, from, to) {
                    out.push(move_action(from, to));
                }
            }
            if leap_enabled {
                // For every three-point line with `from` at one end, jumping
                // over an opponent in the middle to the empty far end is a
                // legal leap move.  master generate<MOVE> calls checkLeapCapture
                // which also validates that the captured middle piece is actually
                // removable under mill-protection rules (P0-A.2). We replicate
                // that check here via leap_capture_target_is_removable.
                for line in active_capture_lines(&self.options.leap_capture, &self.options) {
                    let (a, mid, b) = (line[0], line[1], line[2]);
                    let jumps_from_a =
                        from == a && state.board[b] == 0 && state.board[mid] == opponent_color;
                    let jumps_from_b =
                        from == b && state.board[a] == 0 && state.board[mid] == opponent_color;
                    if jumps_from_a {
                        if !self.is_restricted_repeated_mill(state, from, b)
                            && leap_capture_target_is_removable(state, &self.options, mid)
                        {
                            out.push(move_action(from, b));
                        }
                    } else if jumps_from_b
                        && !self.is_restricted_repeated_mill(state, from, a)
                        && leap_capture_target_is_removable(state, &self.options, mid)
                    {
                        out.push(move_action(from, a));
                    }
                }
            }
        }
    }

    fn is_restricted_repeated_mill(&self, state: &MillState, from: usize, to: usize) -> bool {
        if !self.options.restrict_repeated_mills_formation {
            return false;
        }
        // Per-side last-mill tracking, matching C++ position.cpp
        // `lastMillFromSquare[c]` / `lastMillToSquare[c]`.
        let side = state.side_to_move as usize;
        if side >= 2 {
            return false;
        }
        let last_from = state.last_mill_from[side];
        let last_to = state.last_mill_to[side];
        if last_from < 0 || last_to < 0 {
            return false;
        }
        if from != last_to as usize || to != last_from as usize {
            return false;
        }
        // Mirror master src/position.cpp:1068 / potential_mills_count:
        // restrict only when `from` currently counts as a usable mill and
        // moving back to `to` would form another usable mill.  Under
        // oneTimeUseMill, potential_mills_count filters out lines already
        // recorded in formedMillsBB, so an already consumed mill must not
        // keep the reverse move restricted.
        if potential_mills_count_at(state, &self.options, from, state.side_to_move, None) == 0 {
            return false;
        }
        potential_mills_count_at(state, &self.options, to, state.side_to_move, Some(from)) > 0
    }

    fn generate_remove_actions(
        &self,
        state: &MillState,
        out: &mut ActionList<256>,
        priority: &[usize; 24],
    ) {
        let us = state.side_to_move as usize;
        let capture_targets = if us < 2 {
            state.custodian_targets[us] | state.intervention_targets[us] | state.leap_targets[us]
        } else {
            0
        };
        if capture_targets != 0 {
            self.generate_capture_remove_actions(state, out, capture_targets);
            // Mirror master generate<REMOVE>'s `totalRemovals <= captureCount`
            // cutoff (P0-A.1): when pending removals are fully covered by
            // capture obligations, only capture targets are legal this turn.
            if us >= 2 || state.pending_removals[us] <= capture_total(state) {
                return;
            }
            // pending_removals[us] > capture_total: the current player formed
            // a mill simultaneously with a capture, so also generate the
            // regular mill-remove targets below (excluding capture targets
            // already emitted above).
        }

        if us < 2 && state.remove_own_piece[us] {
            // Mirror master src/position.cpp:1773 remove_piece:
            // negative pieceToRemoveCount switches the target colour to the
            // mover's own pieces, then the common stalemate and mill
            // protection filters at lines 1793-1801 still run.
            self.generate_regular_remove_actions_for_piece(
                state,
                out,
                state.side_to_move + 1,
                0,
                priority,
            );
            return;
        }

        let opponent_piece = (state.side_to_move ^ 1) + 1;
        self.generate_regular_remove_actions_for_piece(
            state,
            out,
            opponent_piece,
            capture_targets,
            priority,
        );
    }

    fn generate_regular_remove_actions_for_piece(
        &self,
        state: &MillState,
        out: &mut ActionList<256>,
        target_piece: i8,
        excluded_targets: u32,
        priority: &[usize; 24],
    ) {
        // When `may_remove_from_mills_always` is set the rule simplifies:
        // every target-colour piece is legal, regardless of whether
        // it sits in a mill.  Otherwise we mirror the C++ default (and
        // the FIDE Mill rule): mill pieces can only be removed when no
        // non-mill alternative exists.  Capture targets already emitted
        // above are skipped to avoid duplicate Remove actions, mirroring
        // master generate<REMOVE>'s `if (combinedTargets & square_bb(s)) continue;`.
        // Marked pieces are filtered out via `live_piece` to mirror
        // legacy `removeColorPiece` matching against `byColorBB[c]`,
        // which excludes MARKED_PIECE squares.
        let has_non_mill_target = (0_usize..24).any(|idx| {
            live_piece(state, idx) == target_piece && !is_piece_in_mill(state, &self.options, idx)
        });

        for &node in priority.iter().rev() {
            if live_piece(state, node) != target_piece {
                continue;
            }
            if (excluded_targets & node_bit(node)) != 0 {
                continue;
            }
            if self.is_stalemate_removal_context(state)
                && !is_adjacent_to_side_piece(state, &self.topology, node)
            {
                continue;
            }
            if !self.options.may_remove_from_mills_always
                && has_non_mill_target
                && is_piece_in_mill(state, &self.options, node)
            {
                continue;
            }
            out.push(Action {
                kind_tag: MillActionKind::Remove as i16,
                from_node: -1,
                to_node: node as i16,
                aux: -1,
                payload_bits: 0,
            });
        }
    }

    fn generate_capture_remove_actions(
        &self,
        state: &MillState,
        out: &mut ActionList<256>,
        targets: u32,
    ) {
        let opponent_piece = (state.side_to_move ^ 1) + 1;
        for node in 0..24_usize {
            if (targets & node_bit(node)) == 0 || state.board[node] != opponent_piece {
                continue;
            }
            out.push(Action {
                kind_tag: MillActionKind::Remove as i16,
                from_node: -1,
                to_node: node as i16,
                aux: -1,
                payload_bits: 0,
            });
        }
    }

    fn is_stalemate_removal_context(&self, state: &MillState) -> bool {
        if state.stalemate_removing || state.both_stalemate_removing {
            return true;
        }
        // Mirror master src/position.cpp:3475 is_board_full_removal_at_placing_phase_end:
        // the board-full branch is only a placing-phase predicate. Rust arms
        // the removals after transitioning to Moving, so board_full_removing
        // is persisted only as UI/FEN metadata and never enables stalemate
        // adjacency filtering.
        matches!(
            self.options.stalemate_action,
            StalemateAction::RemoveOpponentsPieceAndMakeNextMove
                | StalemateAction::RemoveOpponentsPieceAndChangeSideToMove
                | StalemateAction::BothPlayersRemoveOpponentsPiece
        ) && state.phase == MillPhase::Moving
            && state.side_to_move >= 0
            && state.pending_removals[state.side_to_move as usize] > 0
            && !self.has_legal_move(state)
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
    pub pieces_in_hand: [u8; 2],
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

impl MillState {
    fn sync_action_after_transition(&mut self) {
        self.action = if self.phase == MillPhase::GameOver {
            MillActionState::GameOver
        } else if self.side_to_move >= 0 && self.pending_removals[self.side_to_move as usize] > 0 {
            MillActionState::Remove
        } else {
            match self.phase {
                MillPhase::Placing | MillPhase::Ready => MillActionState::Place,
                MillPhase::Moving => MillActionState::Select,
                MillPhase::GameOver => MillActionState::GameOver,
            }
        };
    }

    fn action_for_legal_generation(&self) -> MillActionState {
        if self.action == MillActionState::Place
            && (self.phase != MillPhase::Placing
                || (self.side_to_move >= 0
                    && self.pending_removals[self.side_to_move as usize] > 0))
        {
            let mut normalized = self.clone();
            normalized.sync_action_after_transition();
            normalized.action
        } else {
            self.action
        }
    }
}

fn sync_action_state(state: &mut MillState) {
    state.sync_action_after_transition();
}

impl MillState {
    fn encode(self) -> [u8; OPAQUE_PAYLOAD_LEN] {
        let mut payload = [0_u8; OPAQUE_PAYLOAD_LEN];
        for (i, piece) in self.board.iter().enumerate() {
            payload[i] = *piece as u8;
        }
        payload[24] = self.pieces_in_hand[0];
        payload[25] = self.pieces_in_hand[1];
        payload[26] = self.pieces_on_board[0];
        payload[27] = self.pieces_on_board[1];
        payload[28] = self.pending_removals[0];
        payload[29] = self.pending_removals[1];
        payload[30] = self.winner as u8;
        payload[279] = self.action as u8;
        payload[31] = (self.ply_since_capture & 0xff) as u8;
        payload[32] = (self.ply_since_capture >> 8) as u8;
        payload[33] = self.last_mill_from[0] as u8;
        payload[34] = self.last_mill_to[0] as u8;
        payload[35..39].copy_from_slice(&self.used_mill_lines.to_le_bytes());
        payload[39..43].copy_from_slice(&self.delayed_marked_pieces.to_le_bytes());
        payload[43] = self.outcome_reason as u8;
        // 44..=235: serialized key_history window (24 × 8 bytes,
        // little-endian). Runtime history is a Vec capped at 256 to mirror
        // master; snapshots persist the most recent 24 keys for compatibility.
        let start = self.key_history.len().saturating_sub(24);
        let history_window = &self.key_history[start..];
        for (slot_idx, key) in history_window.iter().enumerate() {
            let base = 44 + slot_idx * 8;
            payload[base..base + 8].copy_from_slice(&key.to_le_bytes());
        }
        // 236: serialized key_history_len (clamped to the payload window).
        payload[236] = history_window.len().min(24) as u8;
        payload[237..241].copy_from_slice(&self.custodian_targets[0].to_le_bytes());
        payload[241..245].copy_from_slice(&self.intervention_targets[0].to_le_bytes());
        payload[245..249].copy_from_slice(&self.leap_targets[0].to_le_bytes());
        payload[249] = self.custodian_count[0];
        payload[250] = self.intervention_count[0];
        payload[251] = self.leap_count[0];
        // Pack loose bool flags into a single byte (bits 0-5).
        let flags: u8 = u8::from(self.mill_available_at_removal)
            | (u8::from(self.stalemate_removing) << 1)
            | (u8::from(self.both_stalemate_removing) << 2)
            | (u8::from(self.remove_own_piece[0]) << 3)
            | (u8::from(self.remove_own_piece[1]) << 4)
            | (u8::from(self.board_full_removing) << 5);
        payload[252] = flags;
        payload[253] = self.last_mill_from[1] as u8;
        payload[254] = self.last_mill_to[1] as u8;
        payload[255] = self.preferred_remove_target as u8;
        // 256..263: per-side `formed_mills_bb` (matches legacy
        // Position::formedMillsBB[c]).  Each side stores a 24-bit
        // little-endian square bitmap.  Aligned so byte 256/260 starts
        // a fresh 4-byte slot in the extended 320-byte payload.
        payload[256..260].copy_from_slice(&self.formed_mills_bb[0].to_le_bytes());
        payload[260..264].copy_from_slice(&self.formed_mills_bb[1].to_le_bytes());
        payload[264..268].copy_from_slice(&self.custodian_targets[1].to_le_bytes());
        payload[268..272].copy_from_slice(&self.intervention_targets[1].to_le_bytes());
        payload[272..276].copy_from_slice(&self.leap_targets[1].to_le_bytes());
        payload[276] = self.custodian_count[1];
        payload[277] = self.intervention_count[1];
        payload[278] = self.leap_count[1];
        payload
    }

    fn decode(snapshot: &GameStateSnapshot) -> Self {
        let payload = snapshot.opaque_payload;
        let mut board = [0_i8; 24];
        for (i, slot) in board.iter_mut().enumerate() {
            *slot = payload[i] as i8;
        }
        let history_len = usize::from(payload[236].min(24));
        let mut key_history = Vec::with_capacity(history_len);
        for slot_idx in 0..history_len {
            let base = 44 + slot_idx * 8;
            let mut bytes = [0_u8; 8];
            bytes.copy_from_slice(&payload[base..base + 8]);
            key_history.push(u64::from_le_bytes(bytes));
        }
        let read_u32 = |offset: usize| {
            let mut bytes = [0_u8; 4];
            bytes.copy_from_slice(&payload[offset..offset + 4]);
            u32::from_le_bytes(bytes)
        };
        Self {
            board,
            side_to_move: snapshot.side_to_move,
            phase: match snapshot.phase_tag {
                x if x == MillPhase::Ready as i16 => MillPhase::Ready,
                x if x == MillPhase::Moving as i16 => MillPhase::Moving,
                x if x == MillPhase::GameOver as i16 => MillPhase::GameOver,
                _ => MillPhase::Placing,
            },
            move_number: snapshot.move_number,
            pieces_in_hand: [payload[24], payload[25]],
            pieces_on_board: [payload[26], payload[27]],
            pending_removals: [payload[28], payload[29]],
            winner: payload[30] as i8,
            action: MillActionState::from_payload(payload[279]),
            ply_since_capture: u16::from(payload[31]) | (u16::from(payload[32]) << 8),
            last_mill_from: [payload[33] as i8, payload[253] as i8],
            last_mill_to: [payload[34] as i8, payload[254] as i8],
            used_mill_lines: read_u32(35),
            delayed_marked_pieces: read_u32(39),
            outcome_reason: match payload[43] {
                x if x == MillOutcomeReason::LoseFewerThanThree as u8 => {
                    MillOutcomeReason::LoseFewerThanThree
                }
                x if x == MillOutcomeReason::DrawNMoveRule as u8 => {
                    MillOutcomeReason::DrawNMoveRule
                }
                x if x == MillOutcomeReason::DrawFullBoard as u8 => {
                    MillOutcomeReason::DrawFullBoard
                }
                x if x == MillOutcomeReason::LoseFullBoard as u8 => {
                    MillOutcomeReason::LoseFullBoard
                }
                x if x == MillOutcomeReason::DrawThreefold as u8 => {
                    MillOutcomeReason::DrawThreefold
                }
                x if x == MillOutcomeReason::LoseNoLegalMoves as u8 => {
                    MillOutcomeReason::LoseNoLegalMoves
                }
                x if x == MillOutcomeReason::DrawStalemate as u8 => {
                    MillOutcomeReason::DrawStalemate
                }
                x if x == MillOutcomeReason::DrawFiftyMove as u8 => {
                    MillOutcomeReason::DrawFiftyMove
                }
                x if x == MillOutcomeReason::DrawEndgameFiftyMove as u8 => {
                    MillOutcomeReason::DrawEndgameFiftyMove
                }
                _ => MillOutcomeReason::Ongoing,
            },
            key_history,
            key_history_len: history_len,
            custodian_targets: [read_u32(237), read_u32(264)],
            intervention_targets: [read_u32(241), read_u32(268)],
            leap_targets: [read_u32(245), read_u32(272)],
            custodian_count: [payload[249], payload[276]],
            intervention_count: [payload[250], payload[277]],
            leap_count: [payload[251], payload[278]],
            mill_available_at_removal: (payload[252] & 0x01) != 0,
            stalemate_removing: (payload[252] & 0x02) != 0,
            both_stalemate_removing: (payload[252] & 0x04) != 0,
            remove_own_piece: [(payload[252] & 0x08) != 0, (payload[252] & 0x10) != 0],
            board_full_removing: (payload[252] & 0x20) != 0,
            preferred_remove_target: payload[255] as i8,
            formed_mills_bb: [read_u32(256), read_u32(260)],
        }
    }
}

// ---------------------------------------------------------------------------
// Setup-position editing API
// ---------------------------------------------------------------------------

impl MillState {
    /// Build an empty board ready for setup-position editing.
    ///
    /// `pieces_in_hand` is initialised from `options.piece_count` (matching
    /// the freshly-constructed placing-phase state), so `recompute_aux` is
    /// not needed after `empty()` alone — only after piece edits.
    pub fn empty(options: &MillVariantOptions) -> Self {
        Self {
            pieces_in_hand: [options.piece_count, options.piece_count],
            ..Self::default()
        }
    }

    /// Place or clear one piece at `node`.
    ///
    /// `owner`: `1` = first player (White), `2` = second player (Black),
    /// anything else = clear.  Callers must follow up with `recompute_aux`
    /// before encoding the snapshot.
    pub fn set_piece(&mut self, node: u16, owner: i8) {
        if let Some(slot) = self.board.get_mut(node as usize) {
            *slot = if owner == 1 || owner == 2 { owner } else { 0 };
        }
    }

    pub fn set_side_to_move(&mut self, side: i8) {
        self.side_to_move = if side == 0 || side == 1 { side } else { 0 };
    }

    pub fn set_phase(&mut self, phase: MillPhase) {
        self.phase = phase;
    }

    pub fn phase(&self) -> MillPhase {
        self.phase
    }

    pub fn pieces_on_board(&self) -> [u8; 2] {
        self.pieces_on_board
    }

    /// Set the winner field directly.  Used by setup-position tools that
    /// need to mark an immediate-GameOver position (e.g. fewer than
    /// pieces_at_least_count pieces after `setup_finish`).
    pub fn set_winner(&mut self, winner: i8) {
        self.winner = winner;
        self.side_to_move = -1;
    }

    /// Mark the position as lost due to too few pieces (mirrors C++
    /// `GameOverReason::loseFewerThanThree`).  Only valid to call after
    /// `set_phase(GameOver)`.
    pub fn set_outcome_reason_fewer_than_threshold(&mut self) {
        self.outcome_reason = MillOutcomeReason::LoseFewerThanThree;
    }

    /// Check whether either side has fewer than `options.pieces_at_least_count`
    /// pieces on board (only meaningful after both hands are empty).  Returns
    /// `Some(winner)` where winner is the side that still has enough pieces,
    /// or `None` if neither side is below the threshold.  When BOTH sides are
    /// short the side with more pieces on board wins; in a tie, black (1) wins.
    /// Used by `setup_finish` to detect immediate-GameOver positions.
    pub fn check_pieces_at_least(&self, options: &MillVariantOptions) -> Option<i8> {
        let min = options.pieces_at_least_count;
        let w_short = self.pieces_on_board[0] < min;
        let b_short = self.pieces_on_board[1] < min;
        if !w_short && !b_short {
            return None;
        }
        // The side with more pieces wins; if equal, black (1) wins by convention.
        let winner = if self.pieces_on_board[0] >= self.pieces_on_board[1] {
            0_i8 // white wins
        } else {
            1_i8 // black wins
        };
        Some(winner)
    }

    pub fn set_pending_removal(&mut self, side_idx: usize, count: u8) {
        if side_idx < 2 {
            self.pending_removals[side_idx] = count;
        }
    }

    /// Recompute auxiliary fields from the board array so the snapshot is
    /// self-consistent after a series of `set_piece` calls.
    ///
    /// Updates: `pieces_on_board`, `pieces_in_hand` (clamped to piece_count),
    /// `winner` (reset to -1), `outcome_reason`, `key_history`, and clears
    /// all capture-target bitmasks.
    pub fn recompute_aux(&mut self, options: &MillVariantOptions) {
        let mut on_board = [0u8; 2];
        for &piece in &self.board {
            if piece == 1 {
                on_board[0] += 1;
            } else if piece == 2 {
                on_board[1] += 1;
            }
        }
        self.pieces_on_board = on_board;
        self.pieces_in_hand = [
            options.piece_count.saturating_sub(on_board[0]),
            options.piece_count.saturating_sub(on_board[1]),
        ];
        self.winner = -1;
        self.outcome_reason = MillOutcomeReason::Ongoing;
        self.ply_since_capture = 0;
        self.last_mill_from = [-1, -1];
        self.last_mill_to = [-1, -1];
        self.used_mill_lines = 0;
        self.delayed_marked_pieces = 0;
        self.formed_mills_bb = [0, 0];
        self.custodian_targets = [0, 0];
        self.intervention_targets = [0, 0];
        self.leap_targets = [0, 0];
        self.custodian_count = [0, 0];
        self.intervention_count = [0, 0];
        self.leap_count = [0, 0];
        self.preferred_remove_target = -1;
        self.mill_available_at_removal = false;
        self.stalemate_removing = false;
        self.both_stalemate_removing = false;
        self.remove_own_piece = [false, false];
        self.key_history.clear();
        self.key_history_len = 0;
    }
}

// ---------------------------------------------------------------------------
// MillRules setup-position helpers (used by the FRB kernel API)
// ---------------------------------------------------------------------------

impl MillRules {
    /// Return a fresh setup-editing state backed by this rule set's options.
    pub fn setup_empty(&self) -> MillState {
        MillState::empty(&self.options)
    }

    /// Encode an externally-edited `MillState` into a `GameStateSnapshot`
    /// suitable for `GameKernel::replace_state`.
    pub fn encode_state(&self, state: MillState) -> GameStateSnapshot {
        self.encode(state)
    }

    /// Parse a Mill FEN string (compatible with the legacy Dart/C++ engine)
    /// and return the resulting `MillState`.
    ///
    /// FEN format (17+ whitespace-separated fields):
    /// `<board> <side> <phase> <act> <w_on> <w_hand> <b_on> <b_hand>
    ///  <w_remove> <b_remove> <w_from> <w_to> <b_from> <b_to>
    ///  <mills_mask> <rule50> <fullmove>`
    ///
    /// `board` = `inner8/middle8/outer8`; pieces: `O`=white, `@`=black, `*`=empty.
    ///
    /// Mills-bitmask and last-mill-from/to fields are parsed but ignored; the
    /// returned state has those auxiliary fields at their defaults so that
    /// `encode_state` + `decode_snapshot` round-trips cleanly.
    pub fn set_from_fen(&self, fen: &str) -> Result<MillState, String> {
        let trimmed = fen.trim();
        // Split FEN into the 17 mandatory whitespace-separated fields plus
        // an optional trailing extension block that holds c:/i:/l:/p:/s:
        // tokens introduced for custodian/intervention/leap captures and
        // the preferred-remove / stalemate flags.
        let mut all_fields: Vec<&str> = trimmed.split_whitespace().collect();
        if all_fields.len() < 17 {
            return Err(format!("FEN needs >= 17 fields, got {}", all_fields.len()));
        }
        let extension_tokens: Vec<&str> = all_fields.split_off(17);
        let fields = all_fields;

        // FEN board position index -> Rust board node index.
        // FEN position i corresponds to legacy square (i + 8), then uses
        // the same fixed legacySquareToNode permutation as Flutter's
        // MillBoardCoordinateMaps.  This is not a simple reversed range.
        const FEN_TO_NODE: [usize; 24] = [
            17, 18, 19, 20, 21, 22, 23, 16, 9, 10, 11, 12, 13, 14, 15, 8, 1, 2, 3, 4, 5, 6, 7, 0,
        ];

        let board_str = fields[0];
        let ranks: Vec<&str> = board_str.split('/').collect();
        if ranks.len() != 3 || ranks.iter().any(|r| r.len() != 8) {
            return Err("FEN board must be three 8-character ranks separated by '/'".to_owned());
        }
        let all_chars: String = ranks.join("");
        let mut board = [0_i8; 24];
        let mut delayed_marked_pieces = 0_u32;
        for (i, c) in all_chars.chars().enumerate() {
            let node = FEN_TO_NODE[i];
            board[node] = if c == 'O' {
                1
            } else if c == '@' {
                2
            } else if c == '*' {
                0
            } else if c == 'X' {
                // MARKED_PIECE in the legacy engine: keep it on the board
                // visually but flag the square so live_piece treats it as
                // empty (matches Position::set_fen handling).
                delayed_marked_pieces |= node_bit(node);
                0
            } else {
                return Err(format!("unexpected piece character '{c}' in FEN"));
            };
        }

        let side_to_move: i8 = match fields[1] {
            "w" => 0,
            "b" => 1,
            s => return Err(format!("invalid side '{s}' in FEN")),
        };

        // Accept every phase token Position::fen emits.  Both 'r' (ready)
        // and 'n' (none) share the placing-phase semantics in Rust because
        // MillPhase has no separate Ready/None variants.
        let phase = match fields[2] {
            "r" | "p" | "n" => MillPhase::Placing,
            "m" => MillPhase::Moving,
            "o" => MillPhase::GameOver,
            s => return Err(format!("invalid phase '{s}' in FEN")),
        };
        // Mirror master src/position.cpp:set FEN action parsing: phase and
        // action are independent tokens in legacy FEN.
        if fields[3].len() != 1 {
            return Err(format!("invalid action token '{}' in FEN", fields[3]));
        }
        let fen_action = MillActionState::from_fen_token(fields[3]);
        let action_is_remove = fen_action == MillActionState::Remove;

        let parse_u8 = |s: &str| -> Result<u8, String> {
            s.parse::<u8>()
                .map_err(|_| format!("cannot parse '{s}' as u8"))
        };
        let parse_i8 = |s: &str| -> Result<i8, String> {
            s.parse::<i8>()
                .map_err(|_| format!("cannot parse '{s}' as i8"))
        };
        let parse_u16 = |s: &str| -> Result<u16, String> {
            s.parse::<u16>()
                .map_err(|_| format!("cannot parse '{s}' as u16"))
        };

        let on_board_w = parse_u8(fields[4])?;
        let in_hand_w = parse_u8(fields[5])?;
        let on_board_b = parse_u8(fields[6])?;
        let in_hand_b = parse_u8(fields[7])?;
        // pieceToRemoveCount[c] is signed in the legacy engine: a negative
        // value flags "remove your own piece" (RemovalBasedOnMillCounts
        // double-zero branch).  Rust models the sign via remove_own_piece
        // and stores the absolute count.
        let signed_remove_w = parse_i8(fields[8])?;
        let signed_remove_b = parse_i8(fields[9])?;
        let remove_w = signed_remove_w.unsigned_abs();
        let remove_b = signed_remove_b.unsigned_abs();
        let remove_own = [signed_remove_w < 0, signed_remove_b < 0];

        // Fields 10..14: last-mill from/to per side.  Master stores them as
        // legacy Square ids; 0 means "none".
        let last_w_from_sq = parse_u8(fields[10])?;
        let last_w_to_sq = parse_u8(fields[11])?;
        let last_b_from_sq = parse_u8(fields[12])?;
        let last_b_to_sq = parse_u8(fields[13])?;
        let last_mill_from = [
            legacy_square_to_node_signed(last_w_from_sq),
            legacy_square_to_node_signed(last_b_from_sq),
        ];
        let last_mill_to = [
            legacy_square_to_node_signed(last_w_to_sq),
            legacy_square_to_node_signed(last_b_to_sq),
        ];

        // Field 14: 64-bit formedMillsBB with per-side per-square mill
        // bitmaps.  Layout matches Position::fen():
        //   ((white_bb_24bits) << 32) | black_bb_24bits
        // The legacy engine uses 32-bit Bitboard slots even though only
        // bits 8..32 are populated (legacy Square ids).  Translate each
        // side's square bitmap from legacy ids into Rust dense node ids
        // before storing.
        let formed_mills_bb_raw = fields[14].parse::<u64>().unwrap_or(0);
        let formed_white_legacy_bb = ((formed_mills_bb_raw >> 32) & 0xFFFF_FFFF) as u32;
        let formed_black_legacy_bb = (formed_mills_bb_raw & 0xFFFF_FFFF) as u32;
        let formed_mills_bb = [
            legacy_square_bb_to_node_bb(formed_white_legacy_bb),
            legacy_square_bb_to_node_bb(formed_black_legacy_bb),
        ];

        let rule50 = parse_u16(fields[15])?;
        let full_move: i32 = fields[16].parse::<i32>().unwrap_or(1).max(1);

        // Reconstruct game ply (move_number) from full-move counter, matching
        // the Dart Position.setFen formula:
        //   gamePly = max(2*(fullMove-1), 0) + (side==black ? 1 : 0)
        let side_is_black = i16::from(side_to_move == 1);
        let move_number = (2_i32 * (full_move - 1)).max(0) as i16 + side_is_black;

        // Trailing extension tokens: c:/i:/l:/p:/s:.
        let mut custodian_targets = [0_u32; 2];
        let mut custodian_count = [0_u8; 2];
        let mut intervention_targets = [0_u32; 2];
        let mut intervention_count = [0_u8; 2];
        let mut leap_targets = [0_u32; 2];
        let mut leap_count = [0_u8; 2];
        let mut stalemate_removing = false;
        let mut both_stalemate_removing = false;
        let mut preferred_remove_target: i8 = -1;
        for token in &extension_tokens {
            if token.len() < 2 || token.as_bytes()[1] != b':' {
                continue;
            }
            let value = &token[2..];
            match token.as_bytes()[0] {
                b'c' => parse_capture_field(value, &mut custodian_targets, &mut custodian_count),
                b'i' => {
                    parse_capture_field(value, &mut intervention_targets, &mut intervention_count)
                }
                b'l' => parse_capture_field(value, &mut leap_targets, &mut leap_count),
                b'p' => {
                    // Mirror Position::set_fen: parse `p:NN` (legacy
                    // Square id) into preferred_remove_target as a Rust
                    // dense node id (or -1 for SQ_NONE / out of range).
                    if let Ok(legacy_sq) = value.parse::<i32>() {
                        if (8..32).contains(&legacy_sq) {
                            preferred_remove_target = legacy_square_to_node_signed(legacy_sq as u8);
                        }
                    }
                }
                b's' => {
                    if let Ok(flag) = value.parse::<i32>() {
                        stalemate_removing = flag == 1;
                        both_stalemate_removing = flag == 2;
                    }
                }
                _ => {}
            }
        }

        // P0-E.1: If the action token is 'r' (remove) but the piece-to-remove
        // count for the active side is 0, infer a single pending removal.  This
        // handles FENs where the action token is the authoritative source for
        // the next expected action (matching master's Action::remove semantics).
        let side_usize = side_to_move as usize;
        let (final_remove_w, final_remove_b) = if action_is_remove
            && remove_w == 0
            && remove_b == 0
            && custodian_count[side_usize] == 0
            && intervention_count[side_usize] == 0
            && leap_count[side_usize] == 0
        {
            if side_usize == 0 {
                (1_u8, 0_u8)
            } else {
                (0_u8, 1_u8)
            }
        } else {
            (remove_w, remove_b)
        };

        let mut state = MillState {
            board,
            side_to_move,
            phase,
            move_number,
            pieces_on_board: [on_board_w, on_board_b],
            pieces_in_hand: [in_hand_w, in_hand_b],
            pending_removals: [final_remove_w, final_remove_b],
            remove_own_piece: remove_own,
            ply_since_capture: rule50,
            last_mill_from,
            last_mill_to,
            delayed_marked_pieces,
            custodian_targets,
            custodian_count,
            intervention_targets,
            intervention_count,
            leap_targets,
            leap_count,
            stalemate_removing,
            both_stalemate_removing,
            action: fen_action,
            mill_available_at_removal: (final_remove_w > 0 || final_remove_b > 0)
                && !(custodian_count[side_usize] > 0
                    || intervention_count[side_usize] > 0
                    || leap_count[side_usize] > 0),
            formed_mills_bb,
            preferred_remove_target,
            winner: -1,
            ..MillState::default()
        };
        // Mirror master src/position.cpp:2069 Position::check_if_game_is_over:
        // importing a FEN immediately runs the same terminal checks as a
        // freshly reached position.  Game-over FENs keep their encoded phase
        // untouched because the FEN format does not carry a winner token.
        if state.phase != MillPhase::GameOver {
            self.check_if_game_is_over(&mut state);
        }
        Ok(state)
    }

    /// Serialize a `MillState` into a Mill FEN string compatible with the
    /// legacy Dart/C++ engine.
    ///
    /// Output covers every parsed field: board layout (with 'X' for
    /// marked pieces), side-to-move, phase ('r/p/m/o'), action token
    /// (`p`/`s`/`r`/`?` matching `Position::fen`), piece-on-board /
    /// piece-in-hand / piece-to-remove counts (negative when
    /// `remove_own_piece` is set), per-side last-mill from/to, the
    /// mills bitmask placeholder (always `0` because Rust tracks
    /// per-line use rather than per-square), rule50, full-move number,
    /// and the trailing `c:/i:/l:/p:/s:` extension block when active.
    pub fn export_fen(&self, state: &MillState) -> String {
        // Rust board node index → FEN board position index (inverse of FEN_TO_NODE).
        const NODE_TO_FEN_POS: [usize; 24] = [
            23, 16, 17, 18, 19, 20, 21, 22, 15, 8, 9, 10, 11, 12, 13, 14, 7, 0, 1, 2, 3, 4, 5, 6,
        ];

        let mut fenchars = [b'*'; 26];
        fenchars[8] = b'/';
        fenchars[17] = b'/';
        for (node, &pos) in NODE_TO_FEN_POS.iter().enumerate() {
            let slot = if pos < 8 {
                pos
            } else if pos < 16 {
                pos + 1
            } else {
                pos + 2
            };
            fenchars[slot] = if is_marked(state, node) {
                b'X'
            } else {
                match state.board[node] {
                    1 => b'O',
                    2 => b'@',
                    _ => b'*',
                }
            };
        }
        let board_str = std::str::from_utf8(&fenchars).unwrap_or("????????/????????/????????");

        let side = if state.side_to_move == 1 { 'b' } else { 'w' };
        let phase = match state.phase {
            MillPhase::Placing => 'p',
            MillPhase::Moving => 'm',
            MillPhase::GameOver => 'o',
            MillPhase::Ready => 'r',
        };
        let side_is_black = i32::from(state.side_to_move == 1);
        let full_move = (1 + (i32::from(state.move_number) - side_is_black) / 2).max(1);

        let action_token = state.action.to_fen_token();

        // Encode signed pieceToRemoveCount mirroring legacy semantics.
        let signed_remove = |idx: usize| -> i32 {
            let abs = i32::from(state.pending_removals[idx]);
            if state.remove_own_piece[idx] {
                -abs
            } else {
                abs
            }
        };

        // Field 14: legacy formedMillsBB packed as
        //   ((white_legacy_bb_24bit) << 32) | black_legacy_bb_24bit
        // Translate per-side dense node bitmaps back to legacy square
        // bitmaps so master-style Position::set_fen can re-load them.
        let formed_white_legacy = u64::from(node_bb_to_legacy_square_bb(state.formed_mills_bb[0]));
        let formed_black_legacy = u64::from(node_bb_to_legacy_square_bb(state.formed_mills_bb[1]));
        let formed_mills_field = (formed_white_legacy << 32) | formed_black_legacy;

        let mut out = format!(
            "{} {} {} {} {} {} {} {} {} {} {} {} {} {} {} {} {}",
            board_str,
            side,
            phase,
            action_token,
            state.pieces_on_board[0],
            state.pieces_in_hand[0],
            state.pieces_on_board[1],
            state.pieces_in_hand[1],
            signed_remove(0),
            signed_remove(1),
            node_to_legacy_square(state.last_mill_from[0]),
            node_to_legacy_square(state.last_mill_to[0]),
            node_to_legacy_square(state.last_mill_from[1]),
            node_to_legacy_square(state.last_mill_to[1]),
            formed_mills_field,
            state.ply_since_capture,
            full_move,
        );

        // Trailing extension fields.  Rust keeps single (active-side)
        // capture-state bitmaps because the legacy engine only ever
        // populates the side currently owing the removal; attribute the
        // payload to whichever colour is to move.
        append_capture_field(
            &mut out,
            'c',
            state.custodian_targets,
            state.custodian_count,
        );
        append_capture_field(
            &mut out,
            'i',
            state.intervention_targets,
            state.intervention_count,
        );
        append_capture_field(&mut out, 'l', state.leap_targets, state.leap_count);
        if state.preferred_remove_target >= 0 {
            out.push_str(&format!(
                " p:{}",
                node_to_legacy_square(state.preferred_remove_target)
            ));
        }
        if state.stalemate_removing {
            out.push_str(" s:1");
        } else if state.both_stalemate_removing {
            out.push_str(" s:2");
        }
        out
    }
}

/// Parse a capture field shaped like `w-N-sq.sq|b-N-sq.sq` into per-side

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

/// Mirrors `Position::surrounded_pieces_count`: counts adjacent pieces around

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
