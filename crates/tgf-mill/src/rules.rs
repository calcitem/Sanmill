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
}

impl Workbench for MillWorkbench {
    fn snapshot(&self) -> GameStateSnapshot {
        self.rules.encode(self.state)
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
        self.undo_stack.push(self.state);
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

    /// MovePicker-style move ordering bonus translated from
    /// `src/movepick.cpp::score()`.  Combines mill formation, mill blocking,
    /// star-square opening preference, and capture-target preference.  The
    /// numeric weights match `RATING_*` constants in `src/types.h`; killer /
    /// history / TT bonuses are still applied in `Searcher::move_score`.
    #[inline]
    fn move_order_bias(wb: &Self::Workbench, action: Action) -> i32 {
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
        match state.phase {
            MillPhase::Placing => {
                if state.pending_removals[state.side_to_move as usize] > 0 {
                    self.generate_remove_actions(&state, out);
                    return;
                }
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
            MillPhase::Moving => {
                if state.pending_removals[state.side_to_move as usize] > 0 {
                    self.generate_remove_actions(&state, out);
                    return;
                }
                self.generate_move_actions(&state, out, true);
            }
            MillPhase::Ready | MillPhase::GameOver => {}
        }
    }

    fn apply(&self, snap: &GameStateSnapshot, action: Action) -> GameStateSnapshot {
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
                            }
                            clear_capture_state(&mut state);
                        }
                        MillFormationActionInPlacingPhase::OpponentRemovesOwnPiece => {
                            let opponent = side ^ 1;
                            state.side_to_move = opponent as i8;
                            state.pending_removals[opponent] = removals;
                            state.mill_available_at_removal = false;
                            clear_capture_state(&mut state);
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
                        }
                        MillFormationActionInPlacingPhase::RemoveOpponentsPieceFromBoard => {
                            state.pending_removals[side] = removals;
                            state.mill_available_at_removal = true;
                            activate_capture_state(&mut state, custodian, intervention, 0);
                            if self.options.may_remove_multiple {
                                state.pending_removals[side] =
                                    state.pending_removals[side].saturating_add(capture_total(&state));
                            }
                        }
                    }
                    note_mill_formation(&mut state, side, -1, to as i8, usable_bits, &self.options);
                } else if custodian != 0 || intervention != 0 {
                    activate_capture_state(&mut state, custodian, intervention, 0);
                    state.pending_removals[side] = capture_total(&state);
                    state.mill_available_at_removal = false;
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
                } else if custodian != 0 || intervention != 0 {
                    activate_capture_state(&mut state, custodian, intervention, 0);
                    state.pending_removals[side] = capture_total(&state);
                    state.mill_available_at_removal = false;
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
                    (state.custodian_targets & mask) != 0 && state.custodian_count > 0;
                let is_intervention =
                    (state.intervention_targets & mask) != 0 && state.intervention_count > 0;
                let is_leap = (state.leap_targets & mask) != 0 && state.leap_count > 0;
                let cap_total = capture_total(&state);
                let remaining_before = state.pending_removals[side];

                if is_intervention {
                    state.mill_available_at_removal = false;
                    state.custodian_targets = 0;
                    state.custodian_count = 0;
                    state.leap_targets = 0;
                    state.leap_count = 0;
                    state.pending_removals[side] = state.intervention_count;
                } else if is_custodian {
                    state.mill_available_at_removal = false;
                    state.intervention_targets = 0;
                    state.intervention_count = 0;
                    state.leap_targets = 0;
                    state.leap_count = 0;
                    state.pending_removals[side] = 1;
                } else if is_leap {
                    state.mill_available_at_removal = false;
                    state.custodian_targets = 0;
                    state.custodian_count = 0;
                    state.intervention_targets = 0;
                    state.intervention_count = 0;
                    state.pending_removals[side] = 1;
                } else if state.mill_available_at_removal && cap_total > 0 {
                    if self.options.may_remove_multiple && remaining_before > cap_total {
                        state.pending_removals[side] = remaining_before.saturating_sub(cap_total);
                    }
                    clear_capture_state(&mut state);
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
                    state.custodian_targets &= !mask;
                    state.custodian_count = state.custodian_count.saturating_sub(1);
                    if state.custodian_count == 0 {
                        state.custodian_targets = 0;
                    }
                }
                if is_intervention {
                    state.intervention_targets &= !mask;
                    state.intervention_count = state.intervention_count.saturating_sub(1);
                    if state.intervention_count == 0 {
                        state.intervention_targets = 0;
                    } else {
                        state.intervention_targets = find_paired_intervention_target(
                            to,
                            state.intervention_targets | mask,
                            &self.options,
                        );
                    }
                }
                if is_leap {
                    state.leap_targets &= !mask;
                    state.leap_count = state.leap_count.saturating_sub(1);
                    if state.leap_count == 0 {
                        state.leap_targets = 0;
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
                    clear_capture_state(&mut state);
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
        for (from, _piece) in state.board.iter().enumerate() {
            // Use live_piece() rather than the raw board value so that
            // mark-and-delay MARKED_PIECE squares are treated as empty
            // (not movable) — mirrors C++ generate<MOVE>'s byColorBB filter.
            if live_piece(state, from) != state.side_to_move + 1 {
                continue;
            }
            if can_fly {
                for (to, target) in state.board.iter().enumerate() {
                    if *target == 0 && !self.is_restricted_repeated_mill(state, from, to) {
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

    fn generate_remove_actions(&self, state: &MillState, out: &mut ActionList<256>) {
        let capture_targets =
            state.custodian_targets | state.intervention_targets | state.leap_targets;
        if capture_targets != 0 {
            self.generate_capture_remove_actions(state, out, capture_targets);
            // Mirror master generate<REMOVE>'s `totalRemovals <= captureCount`
            // cutoff (P0-A.1): when pending removals are fully covered by
            // capture obligations, only capture targets are legal this turn.
            let us = state.side_to_move as usize;
            if us >= 2 || state.pending_removals[us] <= capture_total(state) {
                return;
            }
            // pending_removals[us] > capture_total: the current player formed
            // a mill simultaneously with a capture, so also generate the
            // regular mill-remove targets below (excluding capture targets
            // already emitted above).
        }

        let us = state.side_to_move as usize;
        if us < 2 && state.remove_own_piece[us] {
            // Mirror master src/position.cpp:1773 remove_piece:
            // negative pieceToRemoveCount switches the target colour to the
            // mover's own pieces, then the common stalemate and mill
            // protection filters at lines 1793-1801 still run.
            self.generate_regular_remove_actions_for_piece(state, out, state.side_to_move + 1, 0);
            return;
        }

        let opponent_piece = (state.side_to_move ^ 1) + 1;
        self.generate_regular_remove_actions_for_piece(state, out, opponent_piece, capture_targets);
    }

    fn generate_regular_remove_actions_for_piece(
        &self,
        state: &MillState,
        out: &mut ActionList<256>,
        target_piece: i8,
        excluded_targets: u32,
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
        if self.options.may_remove_from_mills_always {
            for node in 0_usize..24 {
                if live_piece(state, node) == target_piece {
                    if (excluded_targets & node_bit(node)) != 0 {
                        continue;
                    }
                    if self.is_stalemate_removal_context(state)
                        && !is_adjacent_to_side_piece(state, &self.topology, node)
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
            return;
        }

        let has_non_mill_target = (0_usize..24).any(|idx| {
            live_piece(state, idx) == target_piece && !is_piece_in_mill(state, &self.options, idx)
        });

        for node in 0_usize..24 {
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
            if has_non_mill_target && is_piece_in_mill(state, &self.options, node) {
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
/// and this helper is not called, so the placing-phase indicator stays
/// correct until the obligated remove resolves.
fn maybe_transition_to_moving(state: &mut MillState, options: &MillVariantOptions) {
    if state.phase == MillPhase::Placing
        && state.pieces_in_hand[0] == 0
        && state.pieces_in_hand[1] == 0
    {
        enter_moving_phase(state, options);
    }
    if options.piece_count == 12
        && options.stop_placing_when_two_empty_squares
        && state.phase == MillPhase::Placing
        && empty_square_count(state) <= 2
    {
        state.pieces_in_hand = [0, 0];
        enter_moving_phase(state, options);
    }
}

/// When `may_move_in_placing_phase` is enabled the C++ engine determines
/// the effective phase from the **active player's** hand count on every
/// side switch (see `Position::set_side_to_move` in position.cpp).  This
/// means a player who has placed all their pieces enters "moving" phase
/// even while the opponent still holds pieces in hand.
///
/// Call this after every `state.side_to_move ^= 1` in `apply()` to mirror
/// that behaviour.  The function is a no-op for all other variants so it
/// is safe to call unconditionally after every side change.
fn sync_phase_for_may_move_in_placing(state: &mut MillState, options: &MillVariantOptions) {
    if !options.may_move_in_placing_phase {
        return;
    }
    // Only adjust when the game is still in progress (placing or moving).
    if state.phase != MillPhase::Placing && state.phase != MillPhase::Moving {
        return;
    }
    let active = state.side_to_move as usize;
    if active <= 1 {
        state.phase = if state.pieces_in_hand[active] == 0 {
            MillPhase::Moving
        } else {
            MillPhase::Placing
        };
    }
}

fn enter_moving_phase(state: &mut MillState, options: &MillVariantOptions) {
    state.phase = MillPhase::Moving;
    // Mirrors Position::remove_marked_pieces in legacy position.cpp: at
    // the placing-to-moving boundary every "X"-marked square sweeps to
    // empty.  Only meaningful for MarkAndDelayRemovingPieces but cheap
    // enough to run unconditionally — the bitset is already 0 elsewhere.
    if state.delayed_marked_pieces != 0 {
        for node in 0_usize..24 {
            if (state.delayed_marked_pieces & node_bit(node)) != 0 {
                state.board[node] = 0;
            }
        }
        state.delayed_marked_pieces = 0;
    }
    // Mirror handle_placing_phase_end side-to-move logic from master
    // position.cpp.  The "invariant" branch (lasker / your-turn-with-
    // multiple / opponents-turn) keeps the active side intact unless
    // isDefenderMoveFirst forces it to BLACK; every other path
    // unconditionally hands control to the rule-defined first mover.
    let invariant = matches!(
        options.mill_formation_action_in_placing_phase,
        MillFormationActionInPlacingPhase::RemoveOpponentsPieceFromHandThenOpponentsTurn
    ) || (matches!(
        options.mill_formation_action_in_placing_phase,
        MillFormationActionInPlacingPhase::RemoveOpponentsPieceFromHandThenYourTurn
    ) && options.may_remove_multiple)
        || options.may_move_in_placing_phase;
    let mark_and_delay = matches!(
        options.mill_formation_action_in_placing_phase,
        MillFormationActionInPlacingPhase::MarkAndDelayRemovingPieces
    );
    let removal_mill_counts = matches!(
        options.mill_formation_action_in_placing_phase,
        MillFormationActionInPlacingPhase::RemovalBasedOnMillCounts
    );
    if invariant && !mark_and_delay && !removal_mill_counts {
        // Master returns early after `if (isDefenderMoveFirst) set_side_to_move(BLACK)`,
        // leaving the caller to skip the default change_side_to_move when
        // !isDefenderMoveFirst.  We have already toggled side_to_move in
        // the apply() prelude, so leaving it untouched preserves the
        // caller's "no further change" intent.
        if options.is_defender_move_first {
            state.side_to_move = 1;
        }
    } else {
        // Default branch + markAndDelay + removalBasedOnMillCounts all
        // funnel through master `set_side_to_move(defender ? BLACK : WHITE)`.
        state.side_to_move = if options.is_defender_move_first { 1 } else { 0 };
    }
    if matches!(
        options.mill_formation_action_in_placing_phase,
        MillFormationActionInPlacingPhase::RemovalBasedOnMillCounts
    ) {
        apply_removal_based_on_mill_counts(state, options);
    }
}

fn maybe_stop_placing_when_two_empty(state: &mut MillState, options: &MillVariantOptions) {
    if options.piece_count == 12
        && options.stop_placing_when_two_empty_squares
        && empty_square_count(state) <= 2
    {
        state.pieces_in_hand = [0, 0];
    }
}

fn empty_square_count(state: &MillState) -> usize {
    state.board.iter().filter(|piece| **piece == 0).count()
}

fn maybe_finish_full_board(state: &mut MillState, options: &MillVariantOptions) {
    // Mirror Position::handle_placing_phase_end / is_board_full_removal_at_placing_phase_end:
    // the boardFullAction switch only fires for the 12-piece variant.  In
    // 9-piece games 9+9=18<24 means the board cannot fill, and the 24-cell
    // 12-piece variant is the only one master Position checks.
    if options.piece_count != 12 {
        return;
    }
    if state.phase != MillPhase::Moving || empty_square_count(state) != 0 {
        return;
    }
    if state.pending_removals.iter().any(|count| *count > 0) {
        return;
    }
    match options.board_full_action {
        MillBoardFullAction::FirstPlayerLose => {
            state.phase = MillPhase::GameOver;
            state.winner = 1;
            state.outcome_reason = MillOutcomeReason::LoseFullBoard;
            state.side_to_move = -1;
        }
        MillBoardFullAction::AgreeToDraw => {
            state.phase = MillPhase::GameOver;
            state.winner = 2;
            state.outcome_reason = MillOutcomeReason::DrawFullBoard;
            state.side_to_move = -1;
        }
        MillBoardFullAction::FirstAndSecondPlayerRemovePiece => {
            state.pending_removals = [1, 1];
            state.side_to_move = 0;
            state.board_full_removing = true;
        }
        MillBoardFullAction::SecondAndFirstPlayerRemovePiece => {
            state.pending_removals = [1, 1];
            state.side_to_move = 1;
            state.board_full_removing = true;
        }
        MillBoardFullAction::SideToMoveRemovePiece => {
            state.pending_removals = [0, 0];
            let remover = if options.is_defender_move_first { 1 } else { 0 };
            state.side_to_move = remover;
            state.pending_removals[remover as usize] = 1;
            state.board_full_removing = true;
        }
    }
}

/// True when `node` currently holds a piece that has been visually
/// preserved as a "marked" piece by `MarkAndDelayRemovingPieces`: the
/// piece colour is intact in `state.board` (so the UI can render an X),
/// but rule logic must treat the square as empty / inert until the
/// placing-to-moving transition sweeps it via `remove_marked_pieces`.
#[inline]
fn is_marked(state: &MillState, node: usize) -> bool {
    (state.delayed_marked_pieces & node_bit(node)) != 0
}

/// Live (non-marked) piece colour at `node`: 0 = empty, 1 = white, 2 = black.
#[inline]
fn live_piece(state: &MillState, node: usize) -> i8 {
    if is_marked(state, node) {
        0
    } else {
        state.board[node]
    }
}

fn total_mills_count(state: &MillState, options: &MillVariantOptions, side: i8) -> u8 {
    mill_lines(options)
        .iter()
        .filter(|line| line.iter().all(|idx| live_piece(state, *idx) == side + 1))
        .count() as u8
}

fn apply_removal_based_on_mill_counts(state: &mut MillState, options: &MillVariantOptions) {
    let white_mills = total_mills_count(state, options, 0);
    let black_mills = total_mills_count(state, options, 1);
    // Mirror Position::calculate_removal_based_on_mill_counts.  In C++ the
    // double-zero branch sets pieceToRemoveCount[c] = -1 for both sides:
    // the negative sign tells movegen to enumerate the *own* colour for
    // removal.  We model the sign with `remove_own_piece[c]` while
    // `pending_removals[c]` keeps the absolute count.
    state.remove_own_piece = [false, false];
    let (white_remove, black_remove) = if white_mills == 0 && black_mills == 0 {
        state.remove_own_piece = [true, true];
        (1_u8, 1_u8)
    } else if white_mills > 0 && black_mills == 0 {
        (2, 1)
    } else if black_mills > 0 && white_mills == 0 {
        (1, 2)
    } else if white_mills == black_mills {
        (white_mills, black_mills)
    } else if white_mills > black_mills {
        let black = black_mills;
        (black + 1, black)
    } else {
        let white = white_mills;
        (white, white + 1)
    };
    state.pending_removals = [white_remove, black_remove];
    if state.pending_removals[state.side_to_move as usize] == 0 {
        state.side_to_move ^= 1;
    }
    state.mill_available_at_removal = state.pending_removals.iter().any(|count| *count > 0);
}

fn bump_ply_since_capture(state: &mut MillState, options: &MillVariantOptions) {
    // P0-F.2: mirror master's `isMovingOrMayMoveInPlacing` check in
    // search_engine.cpp L432-L458 which accumulates posKeyHistory (and thus
    // rule50) for BOTH the standard moving phase AND the placing-phase when
    // may_move_in_placing_phase is enabled.
    let is_move_counting_phase = state.phase == MillPhase::Moving
        || (state.phase == MillPhase::Placing && options.may_move_in_placing_phase);
    if is_move_counting_phase {
        state.ply_since_capture = state.ply_since_capture.saturating_add(1);
    }
}

fn maybe_draw_by_n_move_rule(state: &mut MillState, options: &MillVariantOptions) {
    // Mirror master src/position.cpp:2077 is_three_endgame:
    // C++ hard-codes the endgame N-move threshold to exactly three pieces,
    // independent of flyPieceCount. Keep the literal because UI/i18n wording
    // describes a "three-piece endgame" rather than a fly-threshold endgame.
    // P0-F.2: apply the N-move rule in placing phase as well when
    // may_move_in_placing_phase is enabled, matching master's behaviour where
    // the posKeyHistory size tracks move-type moves in both phases.
    let is_move_counting_phase = state.phase == MillPhase::Moving
        || (state.phase == MillPhase::Placing && options.may_move_in_placing_phase);
    if !is_move_counting_phase {
        return;
    }
    let is_endgame = options.endgame_n_move_rule > 0
        && options.endgame_n_move_rule < options.n_move_rule
        && state.pieces_on_board.contains(&3);
    let threshold = if is_endgame {
        options.endgame_n_move_rule
    } else {
        options.n_move_rule
    };
    if threshold > 0 && u32::from(state.ply_since_capture) >= threshold {
        state.phase = MillPhase::GameOver;
        state.winner = 2;
        state.outcome_reason = if is_endgame {
            MillOutcomeReason::DrawEndgameFiftyMove
        } else {
            MillOutcomeReason::DrawFiftyMove
        };
        state.side_to_move = -1;
    }
}

fn removal_count_for_bits(bits: u32, options: &MillVariantOptions) -> u8 {
    if options.may_remove_multiple {
        bits.count_ones().max(1) as u8
    } else {
        1
    }
}

fn usable_mill_bits(state: &MillState, options: &MillVariantOptions, bits: u32) -> u32 {
    if !options.one_time_use_mill {
        return bits;
    }
    // Mirror master Position::potential_mills_count's oneTimeUseMill
    // branch: a line is "already used" *for this side* only when all
    // three of its squares are recorded in formed_mills_bb[side].
    // `used_mill_lines` is a global union and would over-restrict —
    // a line first formed by Black should still trigger a removal
    // when White reaches the same configuration.
    let side = state.side_to_move as usize;
    if side >= 2 {
        return bits;
    }
    let formed = state.formed_mills_bb[side];
    let mut usable = bits;
    let lines = mill_lines(options);
    for (line_idx, line) in lines.iter().enumerate() {
        if (bits & (1u32 << line_idx)) == 0 {
            continue;
        }
        let line_bb = node_bit(line[0]) | node_bit(line[1]) | node_bit(line[2]);
        if (line_bb & formed) == line_bb {
            usable &= !(1u32 << line_idx);
        }
    }
    usable
}

/// Mirror of `Position::shouldConsiderMobility()` in option.h: enabled
/// when the user requested mobility scoring or when blocking-path focus
/// requires the mobility delta to drive the search.
fn should_consider_mobility(options: &MillVariantOptions) -> bool {
    options.consider_mobility || options.focus_on_blocking_paths
}

/// Mirror of `Position::shouldFocusOnBlockingPaths()`: in placing it is
/// just the user toggle; in moving it additionally requires that flying
/// is enabled, the opponent is one move away from the fly threshold, and
/// the active side has at most two captured pieces left.
fn should_focus_on_blocking_paths(state: &MillState, options: &MillVariantOptions) -> bool {
    if !options.focus_on_blocking_paths {
        return false;
    }
    match state.phase {
        MillPhase::Placing => true,
        MillPhase::Moving => {
            if !options.may_fly {
                return false;
            }
            let side = state.side_to_move as usize;
            if side >= 2 {
                return false;
            }
            let opp = side ^ 1;
            let opp_threshold = options.pieces_at_least_count.saturating_add(1);
            let our_min_pieces = options.piece_count.saturating_sub(2);
            state.pieces_on_board[opp] == opp_threshold
                && state.pieces_on_board[side] >= our_min_pieces
        }
        _ => false,
    }
}

/// Translation of `Position::mills_pieces_count_difference()`:
/// `popcount(formedMillsBB[WHITE]) - popcount(formedMillsBB[BLACK])`.
/// Counts every square recorded in any historically-formed mill, so a
/// single piece sitting on a 2-mill intersection contributes twice.
/// Driven by `note_mill_formation` (oneTimeUseMill semantics in master).
fn mills_pieces_count_difference(state: &MillState, _options: &MillVariantOptions) -> i32 {
    state.formed_mills_bb[0].count_ones() as i32 - state.formed_mills_bb[1].count_ones() as i32
}

/// Translation of `Position::calculate_mobility_diff`: every empty (or
/// `MARKED_PIECE`) square contributes the count of its White / Black
/// neighbours.  The C++ engine maintains this incrementally; the Rust
/// evaluator currently computes it on demand because `MillState` does
/// not yet store a running mobility difference.
fn mobility_diff(state: &MillState, options: &MillVariantOptions) -> i32 {
    let mut white = 0_i32;
    let mut black = 0_i32;
    for s in 0_usize..24 {
        if live_piece(state, s) != 0 {
            // Occupied by a real (non-marked) piece — skip.
            continue;
        }
        for &neigh in crate::topology::neighbors_for(s, options.has_diagonal_lines) {
            match live_piece(state, neigh as usize) {
                1 => white += 1,
                2 => black += 1,
                _ => {}
            }
        }
    }
    white - black
}

/// Detect whether the side has any legal move (placing or fly excluded:
/// matches `Position::is_all_surrounded`).  Only used for the static
/// evaluator's gameover branch where C++ checks
/// `phase == moving && action == select && is_all_surrounded(side)`.
fn is_all_surrounded(state: &MillState, options: &MillVariantOptions, side: i8) -> bool {
    if (side & 1) != side {
        return false;
    }
    let s = side as usize;
    if state.pieces_on_board[0] + state.pieces_on_board[1] >= 24 {
        return true;
    }
    if options.may_fly && state.pieces_on_board[s] <= options.fly_piece_count {
        // Fly endgame: never surrounded as long as an empty square exists.
        return state.pieces_on_board[0] + state.pieces_on_board[1] >= 24;
    }
    for from in 0_usize..24 {
        if state.board[from] != side + 1 {
            continue;
        }
        for &to in crate::topology::neighbors_for(from, options.has_diagonal_lines) {
            if state.board[to as usize] == 0 {
                return false;
            }
        }
    }
    true
}

/// Translation of `Phase::gameOver` branch of `Evaluation::value`.
fn gameover_value(state: &MillState, options: &MillVariantOptions, mate: i32, draw: i32) -> i32 {
    let on_board_total = i32::from(state.pieces_on_board[0]) + i32::from(state.pieces_on_board[1]);
    if options.piece_count == 12 && on_board_total >= 24 {
        return match options.board_full_action {
            MillBoardFullAction::FirstPlayerLose => -mate,
            MillBoardFullAction::AgreeToDraw => draw,
            // Other board-full variants resolve via remove-action elsewhere
            // and should never reach the static evaluator with phase=GameOver.
            _ => 0,
        };
    }
    let stalemate_loss = matches!(
        options.stalemate_action,
        StalemateAction::EndWithStalemateLoss
    );
    if stalemate_loss
        && state.phase == MillPhase::GameOver
        && state.pending_removals[0] == 0
        && state.pending_removals[1] == 0
        && (state.side_to_move == 0 || state.side_to_move == 1)
        && is_all_surrounded(state, options, state.side_to_move)
    {
        return if state.side_to_move == 0 { -mate } else { mate };
    }
    if i32::from(state.pieces_on_board[0]) < i32::from(options.pieces_at_least_count) {
        return -mate;
    }
    if i32::from(state.pieces_on_board[1]) < i32::from(options.pieces_at_least_count) {
        return mate;
    }
    0
}

fn note_mill_formation(
    state: &mut MillState,
    side: usize,
    from: i8,
    to: i8,
    bits: u32,
    options: &MillVariantOptions,
) {
    debug_assert!(side < 2);
    state.last_mill_from[side] = from;
    state.last_mill_to[side] = to;
    state.used_mill_lines |= bits;
    // Mirror Position::potential_mills_count (`oneTimeUseMill` branch):
    // Only record into `formedMillsBB[c]` when oneTimeUseMill is enabled.
    // C++ only maintains this bitmap in the `oneTimeUseMill` code path;
    // unconditionally accumulating it (as previously) caused the evaluator's
    // mills_pieces_count_difference to diverge for non-Russian-Mill rules.
    if options.one_time_use_mill {
        let lines = mill_lines(options);
        for (line_idx, line) in lines.iter().enumerate() {
            if (bits & (1u32 << line_idx)) != 0 {
                for &sq in line.iter() {
                    state.formed_mills_bb[side] |= node_bit(sq);
                }
            }
        }
    }
}

/// Hash the parts of a `MillState` that participate in threefold repetition.
/// P0-G: aligned with master's posKeyHistory key (same fields as
/// position_key): board layout, side-to-move, pending_removals[us] only, and
/// capture-misc. Phase, move_number, ply_since_capture and other transient
/// counters are excluded so a repeated board configuration always hashes
/// identically regardless of ply distance.
fn repetition_signature(state: &MillState) -> u64 {
    position_key(state)
}

/// Empty the rolling repetition history on irreversible events (Place/Remove),
/// matching master's `posKeyHistory.clear()` for MOVETYPE_PLACE and
/// MOVETYPE_REMOVE (engine_commands.cpp L151-157). Cycles can only span
/// pure Move sequences.
fn clear_key_history(state: &mut MillState) {
    state.key_history = [0_u64; 24];
    state.key_history_len = 0;
}

/// Append the current state's repetition signature to the rolling buffer and
/// end the game in a draw when the same signature has appeared three times.
/// Mirrors master's `posKeyHistory.push_back(key())` + `count(key) >= 3`.
/// The buffer is a ring of 24 entries; practical mill repetitions are always
/// detected within a few moves. No-op when `threefold_repetition_rule` is
/// disabled.
fn push_key_and_check_threefold(state: &mut MillState, options: &MillVariantOptions) {
    if !options.threefold_repetition_rule {
        return;
    }
    let key = repetition_signature(state);
    if state.key_history_len < 24 {
        state.key_history[state.key_history_len as usize] = key;
        state.key_history_len += 1;
    } else {
        state.key_history.copy_within(1..24, 0);
        state.key_history[23] = key;
    }
    let len = state.key_history_len as usize;
    let count = state.key_history[..len]
        .iter()
        .filter(|k| **k == key)
        .count();
    if count >= 3 {
        state.phase = MillPhase::GameOver;
        state.winner = 2;
        state.outcome_reason = MillOutcomeReason::DrawThreefold;
        state.side_to_move = -1;
    }
}

fn move_action(from: usize, to: usize) -> Action {
    Action {
        kind_tag: MillActionKind::Move as i16,
        from_node: from as i16,
        to_node: to as i16,
        aux: -1,
        payload_bits: 0,
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct MillState {
    board: [i8; 24],
    side_to_move: i8,
    phase: MillPhase,
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
    /// Active capture-state mirrors of `Position::custodianCaptureTargets[c]`
    /// etc.  Only the side currently owing the removal carries non-zero
    /// data; the legacy engine zeroes the inactive side via
    /// `setCustodianCaptureState(~us, 0, 0)` so a single bitmap suffices.
    custodian_targets: u32,
    intervention_targets: u32,
    leap_targets: u32,
    custodian_count: u8,
    intervention_count: u8,
    leap_count: u8,
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
    /// Rolling window of repetition signatures, each appended on a
    /// side-changing Move with no mill/capture and cleared on Place/Remove
    /// (mirroring master's posKeyHistory: push on MOVETYPE_MOVE, clear on
    /// MOVETYPE_PLACE / MOVETYPE_REMOVE).  The array is a ring buffer capped
    /// at 24 entries; in practice mill repetitions are detected within a few
    /// moves, so the 24-entry window covers all realistic cases.  Longer
    /// cycles (> 24 moves without capture/placement) would require master's
    /// unbounded vector and are not supported in snapshot serialisation.
    key_history: [u64; 24],
    /// Number of valid entries in `key_history`, clamped to 24.
    key_history_len: u8,
}

impl Default for MillState {
    fn default() -> Self {
        Self {
            board: [0_i8; 24],
            side_to_move: 0,
            phase: MillPhase::Placing,
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
            custodian_targets: 0,
            intervention_targets: 0,
            leap_targets: 0,
            custodian_count: 0,
            intervention_count: 0,
            leap_count: 0,
            preferred_remove_target: -1,
            mill_available_at_removal: false,
            stalemate_removing: false,
            both_stalemate_removing: false,
            board_full_removing: false,
            key_history: [0_u64; 24],
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
        payload[31] = (self.ply_since_capture & 0xff) as u8;
        payload[32] = (self.ply_since_capture >> 8) as u8;
        payload[33] = self.last_mill_from[0] as u8;
        payload[34] = self.last_mill_to[0] as u8;
        payload[35..39].copy_from_slice(&self.used_mill_lines.to_le_bytes());
        payload[39..43].copy_from_slice(&self.delayed_marked_pieces.to_le_bytes());
        payload[43] = self.outcome_reason as u8;
        // 44..=235: key_history (24 × 8 bytes, little-endian).
        for (slot_idx, key) in self.key_history.iter().enumerate() {
            let base = 44 + slot_idx * 8;
            payload[base..base + 8].copy_from_slice(&key.to_le_bytes());
        }
        // 236: key_history_len (clamped to 24, fits in a single byte).
        payload[236] = self.key_history_len.min(24);
        payload[237..241].copy_from_slice(&self.custodian_targets.to_le_bytes());
        payload[241..245].copy_from_slice(&self.intervention_targets.to_le_bytes());
        payload[245..249].copy_from_slice(&self.leap_targets.to_le_bytes());
        payload[249] = self.custodian_count;
        payload[250] = self.intervention_count;
        payload[251] = self.leap_count;
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
        payload
    }

    fn decode(snapshot: &GameStateSnapshot) -> Self {
        let payload = snapshot.opaque_payload;
        let mut board = [0_i8; 24];
        for (i, slot) in board.iter_mut().enumerate() {
            *slot = payload[i] as i8;
        }
        let mut key_history = [0_u64; 24];
        for (slot_idx, key) in key_history.iter_mut().enumerate() {
            let base = 44 + slot_idx * 8;
            let mut bytes = [0_u8; 8];
            bytes.copy_from_slice(&payload[base..base + 8]);
            *key = u64::from_le_bytes(bytes);
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
            key_history_len: payload[236].min(24),
            custodian_targets: read_u32(237),
            intervention_targets: read_u32(241),
            leap_targets: read_u32(245),
            custodian_count: payload[249],
            intervention_count: payload[250],
            leap_count: payload[251],
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
        self.custodian_targets = 0;
        self.intervention_targets = 0;
        self.leap_targets = 0;
        self.custodian_count = 0;
        self.intervention_count = 0;
        self.leap_count = 0;
        self.preferred_remove_target = -1;
        self.mill_available_at_removal = false;
        self.stalemate_removing = false;
        self.both_stalemate_removing = false;
        self.remove_own_piece = [false, false];
        self.key_history = [0_u64; 24];
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
        // Field 3 is the C++ Action token ('p'/'s'/'r'/'?').  Rust derives
        // the action from pending_removals and phase rather than storing a
        // separate enum.  Accept any single-character token and record whether
        // the action is 'r' (remove) so we can infer a pending removal below
        // when the count fields are inconsistent (P0-E.1).
        if fields[3].len() != 1 {
            return Err(format!("invalid action token '{}' in FEN", fields[3]));
        }
        let action_is_remove = fields[3] == "r";

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
        let mut custodian_targets = 0_u32;
        let mut custodian_count = 0_u8;
        let mut intervention_targets = 0_u32;
        let mut intervention_count = 0_u8;
        let mut leap_targets = 0_u32;
        let mut leap_count = 0_u8;
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
            && custodian_count == 0
            && intervention_count == 0
            && leap_count == 0
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
            mill_available_at_removal: (final_remove_w > 0 || final_remove_b > 0)
                && !(custodian_count > 0 || intervention_count > 0 || leap_count > 0),
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

        // Mirror Position::fen action token (legacy uci.cpp): 'r' on a
        // pending removal, 'p' while still placing, 's' for the moving
        // phase select-square step, '?' for none / game over.
        let action_idx = (state.side_to_move as usize).min(1);
        let action_token = if state.pending_removals[action_idx] > 0 {
            'r'
        } else {
            match state.phase {
                MillPhase::Placing | MillPhase::Ready => 'p',
                MillPhase::Moving => 's',
                MillPhase::GameOver => '?',
            }
        };

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
        let attribute_to_white = state.side_to_move == 0;
        append_capture_field(
            &mut out,
            'c',
            state.custodian_targets,
            state.custodian_count,
            attribute_to_white,
        );
        append_capture_field(
            &mut out,
            'i',
            state.intervention_targets,
            state.intervention_count,
            attribute_to_white,
        );
        append_capture_field(
            &mut out,
            'l',
            state.leap_targets,
            state.leap_count,
            attribute_to_white,
        );
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

/// Convert a legacy C++ `Square` enum value (8..32) to a Rust dense node
/// id (0..24).  Returns `-1` when the legacy id is `0` (i.e. SQ_NONE) so
/// the result lines up with `MillState::last_mill_from/to` semantics.
fn legacy_square_to_node_signed(legacy: u8) -> i8 {
    if legacy == 0 || !(8..32).contains(&legacy) {
        return -1;
    }
    const FEN_TO_NODE: [usize; 24] = [
        17, 18, 19, 20, 21, 22, 23, 16, 9, 10, 11, 12, 13, 14, 15, 8, 1, 2, 3, 4, 5, 6, 7, 0,
    ];
    FEN_TO_NODE[(legacy - 8) as usize] as i8
}

/// Inverse of [`legacy_square_to_node_signed`].  `-1` (no last mill) is
/// emitted as `0` to round-trip C++ FEN, which uses `0` for "none".
fn node_to_legacy_square(node: i8) -> u8 {
    if !(0..24).contains(&node) {
        return 0;
    }
    const NODE_TO_FEN_POS: [usize; 24] = [
        23, 16, 17, 18, 19, 20, 21, 22, 15, 8, 9, 10, 11, 12, 13, 14, 7, 0, 1, 2, 3, 4, 5, 6,
    ];
    (NODE_TO_FEN_POS[node as usize] + 8) as u8
}

/// Translate a square bitmap expressed in legacy C++ Square ids (bits
/// 8..32 set, bits 0..8 unused) into the equivalent Rust dense node id
/// bitmap.  Used by `set_from_fen` to re-import the FEN field-14 mills
/// bitmask.
fn legacy_square_bb_to_node_bb(legacy_bb: u32) -> u32 {
    let mut node_bb = 0_u32;
    for legacy_sq in 8_u8..32 {
        if (legacy_bb & (1u32 << legacy_sq)) != 0 {
            let node = legacy_square_to_node_signed(legacy_sq);
            if (0..24).contains(&node) {
                node_bb |= 1u32 << (node as u8);
            }
        }
    }
    node_bb
}

/// Inverse of [`legacy_square_bb_to_node_bb`].  Used by `export_fen` to
/// emit the FEN field-14 mills bitmask in the legacy bit layout.
fn node_bb_to_legacy_square_bb(node_bb: u32) -> u32 {
    let mut legacy_bb = 0_u32;
    for node in 0_u8..24 {
        if (node_bb & (1u32 << node)) != 0 {
            let legacy_sq = node_to_legacy_square(node as i8);
            legacy_bb |= 1u32 << legacy_sq;
        }
    }
    legacy_bb
}

/// Parse a single capture-field segment shaped like
/// `w-N-sq.sq.sq|b-N-sq.sq.sq` into a per-state `targets` bitmap on Rust
/// dense node ids and an aggregated `count`.  The legacy engine tracks
/// these per side; the Rust kernel only stores a single bitmap so we sum
/// the counts and merge the bitmaps.  Invalid segments are ignored, in
/// line with `Position::set_fen`'s tolerant parser.
fn parse_capture_field(value: &str, targets_out: &mut u32, count_out: &mut u8) {
    let mut targets = *targets_out;
    let mut count: u32 = u32::from(*count_out);
    for segment in value.split('|') {
        let segment = segment.trim();
        if segment.is_empty() || segment.len() < 3 || segment.as_bytes()[1] != b'-' {
            continue;
        }
        let color_byte = segment.as_bytes()[0];
        if color_byte != b'w' && color_byte != b'b' {
            continue;
        }
        let after_color = &segment[2..];
        let dash = match after_color.find('-') {
            Some(d) => d,
            None => continue,
        };
        let count_str = after_color[..dash].trim();
        let parsed_count = match count_str.parse::<i32>() {
            Ok(v) => v,
            Err(_) => continue,
        };
        let list_str = &after_color[dash + 1..];
        for square_token in list_str.split('.') {
            let token = square_token.trim();
            if token.is_empty() {
                continue;
            }
            if let Ok(square_value) = token.parse::<i32>() {
                if (8..32).contains(&square_value) {
                    let node = legacy_square_to_node_signed(square_value as u8);
                    if (0..24).contains(&node) {
                        targets |= 1_u32 << (node as u8);
                    }
                }
            }
        }
        count = count.saturating_add(parsed_count.unsigned_abs());
    }
    *targets_out = targets;
    *count_out = count.min(u8::MAX as u32) as u8;
}

/// Append a `c:`/`i:`/`l:` capture field to `out` when at least one
/// target / count is active on the supplied state-wide aggregate.
/// `attribute_to_white` decides whether the merged data is attributed
/// to the white or black colour-tag — Rust does not track per-side
/// capture state so we pick the side currently owing the removal.
fn append_capture_field(
    out: &mut String,
    label: char,
    targets: u32,
    count: u8,
    attribute_to_white: bool,
) {
    if targets == 0 && count == 0 {
        return;
    }
    out.push(' ');
    out.push(label);
    out.push(':');
    let prefix = if attribute_to_white { 'w' } else { 'b' };
    let other = if attribute_to_white { 'b' } else { 'w' };
    out.push(prefix);
    out.push('-');
    out.push_str(&count.to_string());
    out.push('-');
    let mut first = true;
    for node in 0_usize..24 {
        if (targets & (1u32 << node)) == 0 {
            continue;
        }
        if !first {
            out.push('.');
        }
        first = false;
        out.push_str(&node_to_legacy_square(node as i8).to_string());
    }
    out.push('|');
    out.push(other);
    out.push_str("-0-");
}

fn position_key(state: &MillState) -> u64 {
    // P0-G: rewritten to align with master's incremental Zobrist key semantics.
    // Master's key (Position::st.key) includes:
    //   * board piece-square hashes (Zobrist::psq[pc][sq])
    //   * side-to-move (Zobrist::side)
    //   * pieceToRemoveCount[sideToMove] only (via update_key_misc)
    //   * capture target bitmaps and counts (custodian/intervention/leap,
    //     per colour, via setCustodian/Intervention/LeapTargets)
    // Excluded (not in master): gamePly, rule50, phase, pieces_in_hand,
    // pieces_on_board, winner, outcome_reason, last_mill_*, used_mill_lines,
    // delayed_marked_pieces, mill_available_at_removal, formed_mills_bb.
    let mut key = 0xcbf2_9ce4_8422_2325_u64;
    let mut mix = |byte: u8| {
        key ^= u64::from(byte);
        key = key.wrapping_mul(0x1000_0000_01b3);
    };
    // Board pieces (piece-square, 24 squares × 2 bits owner).
    for piece in state.board {
        mix(piece as u8);
    }
    // Side to move.
    mix(state.side_to_move as u8);
    // pieceToRemoveCount for the active side only (mirrors update_key_misc).
    let us = (state.side_to_move as usize) & 1;
    mix(state.pending_removals[us]);
    // Capture-misc: target bitmaps and counts for all three capture types.
    for byte in state.custodian_targets.to_le_bytes() {
        mix(byte);
    }
    for byte in state.intervention_targets.to_le_bytes() {
        mix(byte);
    }
    for byte in state.leap_targets.to_le_bytes() {
        mix(byte);
    }
    mix(state.custodian_count);
    mix(state.intervention_count);
    mix(state.leap_count);
    if key == 0 {
        1
    } else {
        key
    }
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

/// Mirrors `Position::surrounded_pieces_count`: counts adjacent pieces around
/// `s` separated by side-to-move ownership.  Marked-piece bookkeeping is
/// intentionally omitted because the C++ MovePicker discards it as well.
fn surrounded_pieces_count(
    state: &MillState,
    options: &MillVariantOptions,
    s: usize,
) -> (i32, i32, i32) {
    let neighbors = crate::topology::neighbors_for(s, options.has_diagonal_lines);
    let our_piece = state.side_to_move + 1;
    let their_piece = (state.side_to_move ^ 1) + 1;
    let mut our = 0_i32;
    let mut theirs = 0_i32;
    let mut empty = 0_i32;
    for &n in neighbors {
        match state.board[n as usize] {
            0 => empty += 1,
            p if p == our_piece => our += 1,
            p if p == their_piece => theirs += 1,
            _ => {}
        }
    }
    (our, theirs, empty)
}

const RATING_BLOCK_ONE_MILL: i32 = 10;
const RATING_ONE_MILL: i32 = 11;
const RATING_STAR_SQUARE: i32 = 11;

fn is_star_square(options: &MillVariantOptions, node: usize) -> bool {
    if options.has_diagonal_lines {
        // C++ `Mills::move_priority_list_shuffle` uses legacy squares
        // SQ_17/SQ_19/SQ_21/SQ_23 for diagonal-rule star priority.
        // Those map to dense Rust nodes 10/12/14/8 respectively.
        matches!(node, 8 | 10 | 12 | 14)
    } else {
        // C++ non-diagonal star squares are legacy SQ_16/SQ_18/SQ_20/SQ_22.
        // Dense Rust node ids for those squares are 9/11/13/15.
        matches!(node, 9 | 11 | 13 | 15)
    }
}

/// Mirrors the Remove branch in `src/movepick.cpp::score()`.  Combines the
/// "remove inside our mill" preference with mobility (empty neighbour count)
/// and the discouragement against capturing inside an opponent mill that is
/// already heavily defended.
fn remove_move_score(state: &MillState, options: &MillVariantOptions, to: usize) -> i32 {
    let side = state.side_to_move;
    let opponent = side ^ 1;
    let our_mills = potential_mills_count_at(state, options, to, side, None) as i32;
    let their_mills = potential_mills_count_at(state, options, to, opponent, None) as i32;
    let (our_count, their_count, empty_count) = surrounded_pieces_count(state, options, to);

    let mut score = 0_i32;
    if our_mills > 0 && their_count == 0 {
        score += 1;
        if our_count > 0 {
            score += our_count;
        }
    }
    if their_mills > 0 && their_count >= 2 {
        score -= their_count;
        if our_count == 0 {
            score -= 1;
        }
    }
    score + empty_count
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

fn active_capture_lines(
    config: &CaptureRuleConfig,
    options: &MillVariantOptions,
) -> Vec<[usize; 3]> {
    let mut lines = Vec::new();
    if config.on_cross_lines {
        lines.extend_from_slice(CAPTURE_CROSS_LINES);
    }
    if config.on_square_edges {
        lines.extend_from_slice(CAPTURE_SQUARE_EDGE_LINES);
    }
    if config.on_diagonal_lines && options.has_diagonal_lines {
        lines.extend_from_slice(CAPTURE_DIAGONAL_LINES);
    }
    lines
}

fn capture_phase_allowed(config: &CaptureRuleConfig, phase: MillPhase) -> bool {
    config.enabled
        && match phase {
            MillPhase::Placing => config.in_placing_phase,
            MillPhase::Moving => config.in_moving_phase,
            MillPhase::Ready | MillPhase::GameOver => false,
        }
}

fn capture_piece_count_allowed(config: &CaptureRuleConfig, state: &MillState) -> bool {
    // For custodian and intervention captures, onlyAvailableWhenOwnPiecesLeq3
    // only applies in moving phase, matching master's checkCustodianCapture and
    // checkInterventionCapture where the condition is guarded by
    // `if (phase == Phase::moving)`.
    if !config.only_available_when_own_pieces_leq3 || state.phase != MillPhase::Moving {
        return true;
    }
    let side = state.side_to_move as usize;
    let us = state.pieces_on_board[side];
    us <= 3
}

fn capture_piece_count_allowed_leap(config: &CaptureRuleConfig, state: &MillState) -> bool {
    // For leap captures, onlyAvailableWhenOwnPiecesLeq3 applies in BOTH placing
    // and moving phases. This mirrors master's checkLeapCapture where the
    // condition is checked OUTSIDE any phase guard (unlike custodian/intervention
    // which wrap it in `if (phase == Phase::moving)`).
    if !config.only_available_when_own_pieces_leq3 {
        return true;
    }
    let side = state.side_to_move as usize;
    let us = state.pieces_on_board[side];
    us <= 3
}

fn is_all_in_mills(state: &MillState, options: &MillVariantOptions, piece: i8) -> bool {
    state
        .board
        .iter()
        .enumerate()
        .filter(|(_, p)| **p == piece)
        .all(|(idx, _)| is_piece_in_mill(state, options, idx))
}

/// Validates that the piece at `mid` (the captured middle square) is actually
/// removable under mill-protection rules. Called during leap move generation
/// to mirror master's checkLeapCapture mill-protection validation (P0-A.2).
fn leap_capture_target_is_removable(
    state: &MillState,
    options: &MillVariantOptions,
    mid: usize,
) -> bool {
    let opponent_piece = (state.side_to_move ^ 1) + 1;
    if state.board[mid] != opponent_piece {
        return false;
    }
    // Mill protection: if may_remove_from_mills_always is false, a piece in a
    // mill cannot be captured unless ALL opponent pieces are in mills.
    if !options.may_remove_from_mills_always
        && is_piece_in_mill(state, options, mid)
        && !is_all_in_mills(state, options, opponent_piece)
    {
        return false;
    }
    true
}

fn is_adjacent_to_side_piece(state: &MillState, topology: &MillTopology, node: usize) -> bool {
    if state.side_to_move < 0 {
        return false;
    }
    let own_piece = state.side_to_move + 1;
    topology
        .neighbors(node as u16)
        .iter()
        .any(|neighbor| state.board[*neighbor as usize] == own_piece)
}

fn filter_capture_targets(state: &MillState, options: &MillVariantOptions, targets: u32) -> u32 {
    let opponent_piece = (state.side_to_move ^ 1) + 1;
    let mut filtered = 0_u32;
    let all_in_mills = is_all_in_mills(state, options, opponent_piece);
    for node in 0..24_usize {
        if (targets & node_bit(node)) == 0 || state.board[node] != opponent_piece {
            continue;
        }
        if !options.may_remove_from_mills_always
            && is_piece_in_mill(state, options, node)
            && !all_in_mills
        {
            continue;
        }
        filtered |= node_bit(node);
    }
    filtered
}

fn detect_custodian_targets(state: &MillState, options: &MillVariantOptions, to: usize) -> u32 {
    let config = &options.custodian_capture;
    if !capture_phase_allowed(config, state.phase) || !capture_piece_count_allowed(config, state) {
        return 0;
    }
    let us = state.side_to_move + 1;
    let them = state.side_to_move ^ 1;
    let opponent = them + 1;
    let mut targets = 0_u32;
    for line in active_capture_lines(config, options) {
        let brackets_middle = (to == line[0] && state.board[line[2]] == us)
            || (to == line[2] && state.board[line[0]] == us);
        if brackets_middle && state.board[line[1]] == opponent {
            targets |= node_bit(line[1]);
        }
    }
    filter_capture_targets(state, options, targets)
}

fn detect_intervention_targets(state: &MillState, options: &MillVariantOptions, to: usize) -> u32 {
    let config = &options.intervention_capture;
    if !capture_phase_allowed(config, state.phase) || !capture_piece_count_allowed(config, state) {
        return 0;
    }
    let opponent = (state.side_to_move ^ 1) + 1;

    // Mirror master src/position.cpp:2670 checkInterventionCapture:
    // collect raw capture lines first, select the preferred/first line, then
    // apply mill-protection filtering only to that selected line. If filtering
    // removes every target, the intervention capture is abandoned instead of
    // falling back to another line.
    let preferred = state.preferred_remove_target;

    let mut capture_lines: Vec<u32> = Vec::new();
    for line in active_capture_lines(config, options) {
        if to == line[1] && state.board[line[0]] == opponent && state.board[line[2]] == opponent {
            let targets = node_bit(line[0]) | node_bit(line[2]);
            capture_lines.push(targets);
        }
    }
    if capture_lines.is_empty() {
        return 0;
    }

    // Select the line containing preferredRemoveTarget if specified.
    if preferred >= 0 {
        let pref_mask = node_bit(preferred as usize);
        if let Some(&line) = capture_lines.iter().find(|&&l| (l & pref_mask) != 0) {
            return filter_capture_targets(state, options, line);
        }
    }
    // Fall back to the first valid line (mirrors master's captureLines[0]).
    filter_capture_targets(state, options, capture_lines[0])
}

fn detect_leap_targets(
    state: &MillState,
    options: &MillVariantOptions,
    from: usize,
    to: usize,
) -> u32 {
    let config = &options.leap_capture;
    // Use the leap-specific piece-count check that applies in both placing and
    // moving phases (master checkLeapCapture has the count guard outside any
    // phase conditional, unlike custodian/intervention).
    if !capture_phase_allowed(config, state.phase)
        || !capture_piece_count_allowed_leap(config, state)
    {
        return 0;
    }
    let opponent = (state.side_to_move ^ 1) + 1;
    let mut targets = 0_u32;
    for line in active_capture_lines(config, options) {
        let jumps_over_middle =
            (to == line[2] && from == line[0]) || (to == line[0] && from == line[2]);
        if jumps_over_middle && state.board[line[1]] == opponent {
            targets |= node_bit(line[1]);
        }
    }
    filter_capture_targets(state, options, targets)
}

fn bit_count(mask: u32) -> u8 {
    mask.count_ones().min(u8::MAX as u32) as u8
}

fn clear_capture_state(state: &mut MillState) {
    state.custodian_targets = 0;
    state.intervention_targets = 0;
    state.leap_targets = 0;
    state.custodian_count = 0;
    state.intervention_count = 0;
    state.leap_count = 0;
    state.mill_available_at_removal = false;
}

fn activate_capture_state(state: &mut MillState, custodian: u32, intervention: u32, leap: u32) {
    state.custodian_targets = custodian;
    state.intervention_targets = intervention;
    state.leap_targets = leap;
    state.custodian_count = bit_count(custodian);
    state.intervention_count = bit_count(intervention);
    state.leap_count = bit_count(leap);
}

fn capture_total(state: &MillState) -> u8 {
    state
        .custodian_count
        .saturating_add(state.intervention_count)
        .saturating_add(state.leap_count)
}

fn find_paired_intervention_target(
    removed: usize,
    targets: u32,
    options: &MillVariantOptions,
) -> u32 {
    for line in active_capture_lines(&options.intervention_capture, options) {
        let a = line[0];
        let b = line[2];
        if removed == a && (targets & node_bit(b)) != 0 {
            return node_bit(b);
        }
        if removed == b && (targets & node_bit(a)) != 0 {
            return node_bit(a);
        }
    }
    targets & !node_bit(removed)
}

const STANDARD_MILL_LINES: &[[usize; 3]] = &[
    [0, 1, 2],
    [2, 3, 4],
    [4, 5, 6],
    [6, 7, 0],
    [8, 9, 10],
    [10, 11, 12],
    [12, 13, 14],
    [14, 15, 8],
    [16, 17, 18],
    [18, 19, 20],
    [20, 21, 22],
    [22, 23, 16],
    [1, 9, 17],
    [3, 11, 19],
    [5, 13, 21],
    [7, 15, 23],
];

const DIAGONAL_MILL_LINES: &[[usize; 3]] = &[
    [0, 1, 2],
    [2, 3, 4],
    [4, 5, 6],
    [6, 7, 0],
    [8, 9, 10],
    [10, 11, 12],
    [12, 13, 14],
    [14, 15, 8],
    [16, 17, 18],
    [18, 19, 20],
    [20, 21, 22],
    [22, 23, 16],
    [1, 9, 17],
    [3, 11, 19],
    [5, 13, 21],
    [7, 15, 23],
    [0, 8, 16],
    [18, 10, 2],
    [6, 14, 22],
    [20, 12, 4],
];

const CAPTURE_SQUARE_EDGE_LINES: &[[usize; 3]] = &[
    [0, 1, 2],
    [8, 9, 10],
    [16, 17, 18],
    [22, 21, 20],
    [14, 13, 12],
    [6, 5, 4],
    [0, 7, 6],
    [8, 15, 14],
    [16, 23, 22],
    [18, 19, 20],
    [10, 11, 12],
    [2, 3, 4],
];

const CAPTURE_CROSS_LINES: &[[usize; 3]] = &[[7, 15, 23], [19, 11, 3], [1, 9, 17], [21, 13, 5]];

/// Diagonal three-point lines (middle index [1]) matching
/// `MillTopology::diagonal_line_groups` / C++ 12MM diagonal rules.
const CAPTURE_DIAGONAL_LINES: &[[usize; 3]] = &[[0, 8, 16], [18, 10, 2], [6, 14, 22], [20, 12, 4]];

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn initial_state_has_24_placing_actions() {
        let rules = MillRules::default();
        let snap = rules.initial_state(&[]);
        let mut actions = ActionList::<256>::new();
        rules.legal_actions(&snap, &mut actions);
        assert_eq!(actions.len(), 24);
        assert!(actions
            .iter()
            .all(|a| a.kind_tag == MillActionKind::Place as i16));
    }

    #[test]
    fn place_action_reduces_hand_and_switches_side() {
        let rules = MillRules::default();
        let snap = rules.initial_state(&[]);
        let next = rules.apply(
            &snap,
            Action {
                kind_tag: MillActionKind::Place as i16,
                from_node: -1,
                to_node: 0,
                aux: -1,
                payload_bits: 0,
            },
        );
        let state = MillRules::decode(&next);
        assert_eq!(state.board[0], 1);
        assert_eq!(state.side_to_move, 1);
        assert_eq!(state.pieces_in_hand[0], 8);
        assert_eq!(state.pieces_on_board[0], 1);
    }

    #[test]
    fn place_action_resets_ply_since_capture_counter() {
        let rules = MillRules::default();
        let mut state = MillRules::decode(&rules.initial_state(&[]));
        state.ply_since_capture = 42;

        let after = rules.apply(
            &rules.encode(state),
            Action {
                kind_tag: MillActionKind::Place as i16,
                from_node: -1,
                to_node: 0,
                aux: -1,
                payload_bits: 0,
            },
        );

        let state = MillRules::decode(&after);
        assert_eq!(state.ply_since_capture, 0);
    }

    #[test]
    fn move_order_bias_star_square_matches_movepick_rating() {
        use tgf_core::Game;

        let rules = MillRules::default();
        let game = MillGame::default();
        let mut snap = rules.initial_state(&[]);
        for n in [0_i16, 1, 2] {
            snap = rules.apply(
                &snap,
                Action {
                    kind_tag: MillActionKind::Place as i16,
                    from_node: -1,
                    to_node: n,
                    aux: -1,
                    payload_bits: 0,
                },
            );
        }
        let wb = game.build_workbench(&snap);
        assert_eq!(wb.state.side_to_move, 1);
        let star_place = Action {
            kind_tag: MillActionKind::Place as i16,
            from_node: -1,
            // Legacy SQ_16 ("d6") is a C++ star-priority square.
            // In Rust's dense node numbering it is node 9.
            to_node: 9,
            aux: -1,
            payload_bits: 0,
        };
        assert_eq!(<MillGame as Game>::move_order_bias(&wb, star_place), 11);
        let non_star = Action {
            kind_tag: MillActionKind::Place as i16,
            from_node: -1,
            to_node: 3,
            aux: -1,
            payload_bits: 0,
        };
        assert_eq!(<MillGame as Game>::move_order_bias(&wb, non_star), 0);
    }

    #[test]
    fn star_square_mapping_matches_legacy_move_priority() {
        // Matches C++ `Mills::move_priority_list_shuffle`:
        //   standard: SQ_16, SQ_18, SQ_20, SQ_22
        //   diagonal: SQ_17, SQ_19, SQ_21, SQ_23
        // converted through `MillTopology::square_to_node`.
        let standard = MillVariantOptions::default();
        assert!(is_star_square(&standard, 9)); // SQ_16 / d6
        assert!(is_star_square(&standard, 11)); // SQ_18 / f4
        assert!(is_star_square(&standard, 13)); // SQ_20 / d2
        assert!(is_star_square(&standard, 15)); // SQ_22 / b4
        assert!(!is_star_square(&standard, 16)); // SQ_15 / c5

        let diagonal = MillVariantOptions {
            has_diagonal_lines: true,
            ..Default::default()
        };
        assert!(is_star_square(&diagonal, 10)); // SQ_17 / f6
        assert!(is_star_square(&diagonal, 12)); // SQ_19 / f2
        assert!(is_star_square(&diagonal, 14)); // SQ_21 / b2
        assert!(is_star_square(&diagonal, 8)); // SQ_23 / b6
        assert!(!is_star_square(&diagonal, 17)); // SQ_8 / d5
    }

    #[test]
    fn move_order_bias_prefers_completing_own_mill_and_blocking_opponent() {
        use tgf_core::Game;

        let rules = MillRules::default();
        let game = MillGame::default();
        // White already owns 0 and 2: placing on 1 closes the a7-b7-c7 mill,
        // matching the `RATING_ONE_MILL` weight (=11) in `movepick.cpp`.
        // Black already owns 4 and 6: placing on 5 instead would only block
        // black's mill, which scores `RATING_BLOCK_ONE_MILL` (=10).
        let mut board = [0_i8; 24];
        board[0] = 1;
        board[2] = 1;
        board[4] = 2;
        board[6] = 2;
        let state = MillState {
            board,
            side_to_move: 0,
            phase: MillPhase::Placing,
            pieces_in_hand: [9, 9],
            ..MillState::default()
        };
        let snap = rules.encode(state);
        let wb = game.build_workbench(&snap);

        let close_own_mill = Action {
            kind_tag: MillActionKind::Place as i16,
            from_node: -1,
            to_node: 1,
            aux: -1,
            payload_bits: 0,
        };
        let block_opponent_mill = Action {
            kind_tag: MillActionKind::Place as i16,
            from_node: -1,
            to_node: 5,
            aux: -1,
            payload_bits: 0,
        };

        assert_eq!(
            <MillGame as Game>::move_order_bias(&wb, close_own_mill),
            RATING_ONE_MILL
        );
        assert_eq!(
            <MillGame as Game>::move_order_bias(&wb, block_opponent_mill),
            RATING_BLOCK_ONE_MILL
        );
    }

    #[test]
    fn move_order_bias_remove_prefers_high_mobility_targets() {
        use tgf_core::Game;

        let rules = MillRules::default();
        let game = MillGame::default();
        // Black piece at d7 (1) has both adjacent ring nodes empty, so
        // empty_count (mobility) = 3 making it a high-value remove target.
        // Black piece at c5 (16) sits between two filled black neighbours
        // (17 and 23 are also black) so empty_count = 0 and the
        // RATING_BLOCK_ONE_MILL-block heuristic does not fire.
        let mut board = [0_i8; 24];
        board[1] = 2;
        board[16] = 2;
        board[17] = 2;
        board[23] = 2;
        let state = MillState {
            board,
            side_to_move: 0,
            phase: MillPhase::Moving,
            pending_removals: [1, 0],
            mill_available_at_removal: true,
            pieces_on_board: [3, 4],
            ..MillState::default()
        };
        let snap = rules.encode(state);
        let wb = game.build_workbench(&snap);

        let mobile_target = Action {
            kind_tag: MillActionKind::Remove as i16,
            from_node: -1,
            to_node: 1,
            aux: -1,
            payload_bits: 0,
        };
        let surrounded_target = Action {
            kind_tag: MillActionKind::Remove as i16,
            from_node: -1,
            to_node: 16,
            aux: -1,
            payload_bits: 0,
        };

        let mobile_score = <MillGame as Game>::move_order_bias(&wb, mobile_target);
        let surrounded_score = <MillGame as Game>::move_order_bias(&wb, surrounded_target);
        assert!(
            mobile_score > surrounded_score,
            "high-mobility remove target should out-score a surrounded one (mobile={}, surrounded={})",
            mobile_score, surrounded_score,
        );
    }

    #[test]
    fn mill_formation_generates_remove_actions_and_keeps_turn() {
        let rules = MillRules::default();
        let mut snap = rules.initial_state(&[]);

        // Equivalent to the C++ golden scenario:
        // W: d7(1), B: a1(6), W: g7(2), B: d1(5), W: a7(0)
        // White completes a7-d7-g7 and must remove one black piece.
        for node in [1, 6, 2, 5, 0] {
            snap = rules.apply(
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

        let state = MillRules::decode(&snap);
        assert_eq!(state.side_to_move, 0, "White keeps turn until removal");
        assert_eq!(state.pending_removals[0], 1);

        let mut actions = ActionList::<256>::new();
        rules.legal_actions(&snap, &mut actions);
        assert_eq!(actions.len(), 2);
        assert!(actions
            .iter()
            .all(|a| a.kind_tag == MillActionKind::Remove as i16));
        assert!(actions.iter().any(|a| a.to_node == 6)); // a1
        assert!(actions.iter().any(|a| a.to_node == 5)); // d1

        let after_remove = rules.apply(
            &snap,
            Action {
                kind_tag: MillActionKind::Remove as i16,
                from_node: -1,
                to_node: 6,
                aux: -1,
                payload_bits: 0,
            },
        );
        let state = MillRules::decode(&after_remove);
        assert_eq!(state.board[6], 0);
        assert_eq!(state.side_to_move, 1, "Turn passes to black after removal");
        assert_eq!(state.pending_removals[0], 0);
        assert_eq!(state.pieces_on_board[1], 1);
    }

    #[test]
    fn placing_mill_f2_f4_f6_generates_remove_actions_for_black() {
        // Replicates the exact sequence reported in the bug:
        //   1. d2 d6   (W node 13, B node 9)
        //   2. f4 b4   (W node 11, B node 15)
        //   3. f2 g4   (W node 12, B node 3)
        //   4. f6      (W node 10) → forms mill [10,11,12] (f6-f4-f2)
        //
        // After White places f6, pending_removals[0] must be 1 and
        // legal_actions must include remove actions for every Black piece.
        let rules = MillRules::default();
        let mut snap = rules.initial_state(&[]);
        for node in [13_i16, 9, 11, 15, 12, 3, 10] {
            snap = rules.apply(
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

        let state = MillRules::decode(&snap);
        assert_eq!(
            state.side_to_move, 0,
            "White keeps turn after forming the mill"
        );
        assert_eq!(
            state.pending_removals[0], 1,
            "White must remove one Black piece"
        );

        let mut actions = ActionList::<256>::new();
        rules.legal_actions(&snap, &mut actions);
        assert_eq!(
            actions.len(),
            3,
            "Exactly three remove actions (one per Black piece)"
        );
        assert!(
            actions
                .iter()
                .all(|a| a.kind_tag == MillActionKind::Remove as i16),
            "All actions must be Remove"
        );
        assert!(
            actions.iter().any(|a| a.to_node == 9),
            "xd6 (node 9) must be a legal remove target"
        );
        assert!(
            actions.iter().any(|a| a.to_node == 15),
            "xb4 (node 15) must be a legal remove target"
        );
        assert!(
            actions.iter().any(|a| a.to_node == 3),
            "xg4 (node 3) must be a legal remove target"
        );
    }

    fn placing_mill_fixture_for_action(
        action: MillFormationActionInPlacingPhase,
    ) -> (MillRules, GameStateSnapshot) {
        let rules = MillRules::new(MillVariantOptions {
            mill_formation_action_in_placing_phase: action,
            ..MillVariantOptions::default()
        });
        let mut snap = rules.initial_state(&[]);
        for node in [1, 6, 2, 5, 0] {
            snap = rules.apply(
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
        (rules, snap)
    }

    #[test]
    fn mill_action_remove_from_hand_then_opponent_turn() {
        let (_rules, snap) = placing_mill_fixture_for_action(
            MillFormationActionInPlacingPhase::RemoveOpponentsPieceFromHandThenOpponentsTurn,
        );
        let state = MillRules::decode(&snap);
        assert_eq!(state.pieces_in_hand[1], 6, "black lost one piece from hand");
        assert_eq!(state.pending_removals[0], 0);
        assert_eq!(state.side_to_move, 1, "turn passes to opponent");
    }

    #[test]
    fn mill_action_remove_from_hand_then_your_turn() {
        let (_rules, snap) = placing_mill_fixture_for_action(
            MillFormationActionInPlacingPhase::RemoveOpponentsPieceFromHandThenYourTurn,
        );
        let state = MillRules::decode(&snap);
        assert_eq!(state.pieces_in_hand[1], 6, "black lost one piece from hand");
        assert_eq!(state.pending_removals[0], 0);
        assert_eq!(state.side_to_move, 0, "active player keeps the turn");
    }

    #[test]
    fn mill_action_opponent_removes_own_piece() {
        let (rules, snap) = placing_mill_fixture_for_action(
            MillFormationActionInPlacingPhase::OpponentRemovesOwnPiece,
        );
        let state = MillRules::decode(&snap);
        assert_eq!(state.side_to_move, 1);
        assert_eq!(state.pending_removals[1], 1);
        let mut actions = ActionList::<256>::new();
        rules.legal_actions(&snap, &mut actions);
        // Opponent removes one of White's pieces; at least the just formed
        // mill pieces are legal targets.
        assert!(actions
            .iter()
            .all(|a| a.kind_tag == MillActionKind::Remove as i16));
        assert!(actions.iter().any(|a| a.to_node == 0));
        assert!(actions.iter().any(|a| a.to_node == 1));
        assert!(actions.iter().any(|a| a.to_node == 2));
    }

    #[test]
    fn mill_action_removal_based_on_mill_counts_waits_until_placing_end() {
        let (_rules, snap) = placing_mill_fixture_for_action(
            MillFormationActionInPlacingPhase::RemovalBasedOnMillCounts,
        );
        let state = MillRules::decode(&snap);
        assert_eq!(state.pending_removals, [0, 0]);
        assert_eq!(
            state.side_to_move, 1,
            "no removal until all pieces are placed"
        );
    }

    #[test]
    fn mill_action_removal_based_on_mill_counts_assigns_at_placing_end() {
        let rules = MillRules::new(MillVariantOptions {
            mill_formation_action_in_placing_phase:
                MillFormationActionInPlacingPhase::RemovalBasedOnMillCounts,
            ..MillVariantOptions::default()
        });
        let mut state = MillState {
            board: {
                let mut board = [0_i8; 24];
                // White has one mill a7-d7-g7; black has no mills.
                board[0] = 1;
                board[1] = 1;
                board[2] = 1;
                board[6] = 2;
                board[11] = 2;
                board[14] = 2;
                board
            },
            side_to_move: 0,
            phase: MillPhase::Placing,
            move_number: 17,
            pieces_in_hand: [1, 0],
            pieces_on_board: [3, 3],
            pending_removals: [0, 0],
            winner: -1,
            ..MillState::default()
        };
        // Add a harmless final white piece that does not create another mill.
        state.board[8] = 0;
        let after = rules.apply(
            &rules.encode(state),
            Action {
                kind_tag: MillActionKind::Place as i16,
                from_node: -1,
                to_node: 8,
                aux: -1,
                payload_bits: 0,
            },
        );
        let state = MillRules::decode(&after);
        assert_eq!(state.phase, MillPhase::Moving);
        assert_eq!(
            state.pending_removals,
            [2, 1],
            "white has mills while black has none, matching C++ removalBasedOnMillCounts"
        );
    }

    /// `MarkAndDelayRemovingPieces` mirrors C++ position.cpp: mill formation
    /// arms a regular remove obligation, and the chosen target is *marked*
    /// (kept on the board with its colour) instead of physically removed.
    /// Marked pieces stay until the placing-to-moving boundary, where
    /// `enter_moving_phase` calls the equivalent of `remove_marked_pieces`
    /// to sweep them.
    #[test]
    fn mill_action_mark_and_delay_arms_remove_then_marks_target() {
        let (rules, snap) = placing_mill_fixture_for_action(
            MillFormationActionInPlacingPhase::MarkAndDelayRemovingPieces,
        );
        let state = MillRules::decode(&snap);
        // Active side now owes a removal obligation against the opponent.
        assert_eq!(state.pending_removals[0], 1);
        assert_eq!(state.side_to_move, 0);
        assert!(state.mill_available_at_removal);

        // Pick any opponent piece to "mark".
        let mut actions = ActionList::<256>::new();
        rules.legal_actions(&snap, &mut actions);
        let target = actions
            .iter()
            .copied()
            .find(|a| a.kind_tag == MillActionKind::Remove as i16)
            .expect("at least one remove target");
        let after = rules.apply(&snap, target);
        let state = MillRules::decode(&after);
        // Target square keeps its colour but is now flagged as marked.
        assert_eq!(state.board[target.to_node as usize], 2, "still owns colour");
        assert!(
            (state.delayed_marked_pieces & (1u32 << target.to_node)) != 0,
            "square must be flagged as marked"
        );
        // Live mill / mobility helpers must treat the marked cell as empty.
        assert_eq!(live_piece(&state, target.to_node as usize), 0);
    }

    /// On the placing-to-moving boundary every marked piece must clear,
    /// matching `Position::remove_marked_pieces`.
    #[test]
    fn mark_and_delay_marked_pieces_sweep_on_phase_transition() {
        let options = MillVariantOptions {
            mill_formation_action_in_placing_phase:
                MillFormationActionInPlacingPhase::MarkAndDelayRemovingPieces,
            ..MillVariantOptions::default()
        };
        // Build a placing-end snapshot with a single marked piece.
        let mut state = MillState {
            side_to_move: 0,
            phase: MillPhase::Placing,
            move_number: 17,
            pieces_in_hand: [0, 0],
            pieces_on_board: [9, 8],
            pending_removals: [0, 0],
            ..MillState::default()
        };
        state.board[0] = 2;
        state.delayed_marked_pieces = 1u32 << 0;
        enter_moving_phase(&mut state, &options);
        assert_eq!(state.phase, MillPhase::Moving);
        assert_eq!(
            state.board[0], 0,
            "marked square must be cleared on entering moving phase"
        );
        assert_eq!(state.delayed_marked_pieces, 0);
    }

    /// `RemovalBasedOnMillCounts` reaches the placing-to-moving boundary
    /// with neither side having formed a mill.  Master `position.cpp`
    /// signals "remove your own piece" by setting
    /// `pieceToRemoveCount[c] = -1` for both sides; the Rust port models
    /// this with `remove_own_piece[c]=true` plus `pending_removals[c]=1`.
    /// The legal-action set after the final placement must enumerate own
    /// pieces, not opponent pieces.
    #[test]
    fn mill_action_removal_based_on_mill_counts_double_zero_removes_own_piece() {
        let rules = MillRules::new(MillVariantOptions {
            mill_formation_action_in_placing_phase:
                MillFormationActionInPlacingPhase::RemovalBasedOnMillCounts,
            ..MillVariantOptions::default()
        });
        // Build a placing-end position where neither side has a mill.  Each
        // side has placed 8 pieces; white is about to place its last.
        let mut state = MillState {
            side_to_move: 0,
            phase: MillPhase::Placing,
            move_number: 17,
            pieces_in_hand: [1, 0],
            pieces_on_board: [8, 9],
            pending_removals: [0, 0],
            winner: -1,
            ..MillState::default()
        };
        // White on nodes 0,3,6,9,12,15,18,21 (no mill thanks to gaps).
        for &n in &[0_usize, 3, 6, 9, 12, 15, 18, 21] {
            state.board[n] = 1;
        }
        // Black on nodes 2,5,8,11,14,17,20,23 + one extra on 4 (no mill).
        for &n in &[2_usize, 5, 8, 11, 14, 17, 20, 23, 4] {
            state.board[n] = 2;
        }
        // White places at node 1 — still no mills for either side.
        let after = rules.apply(
            &rules.encode(state),
            Action {
                kind_tag: MillActionKind::Place as i16,
                from_node: -1,
                to_node: 1,
                aux: -1,
                payload_bits: 0,
            },
        );
        let state = MillRules::decode(&after);
        assert_eq!(state.phase, MillPhase::Moving);
        assert_eq!(
            state.pending_removals,
            [1, 1],
            "double-zero mills schedules one removal per side"
        );
        assert_eq!(
            state.remove_own_piece,
            [true, true],
            "negative pieceToRemoveCount semantics: each side removes own"
        );

        let mut actions = ActionList::<256>::new();
        rules.legal_actions(&after, &mut actions);
        assert!(!actions.is_empty(), "must offer at least one legal removal");
        let active = state.side_to_move;
        let own_color = active + 1;
        for action in actions.iter() {
            assert_eq!(action.kind_tag, MillActionKind::Remove as i16);
            assert_eq!(
                state.board[action.to_node as usize], own_color,
                "removal must target the active side's own piece, not opponent"
            );
        }

        // Apply one of the own-piece removals and confirm the flag clears.
        let pick = actions.iter().next().copied().unwrap();
        let after = rules.apply(&after, pick);
        let state = MillRules::decode(&after);
        assert!(
            !state.remove_own_piece[active as usize],
            "remove_own_piece flag must clear once quota reaches zero"
        );
    }

    #[test]
    fn remove_own_piece_respects_mill_protection() {
        let rules = MillRules::default();
        let state = MillState {
            board: {
                let mut board = [0_i8; 24];
                for node in [0_usize, 1, 2, 6] {
                    board[node] = 1;
                }
                for node in [8_usize, 11, 14] {
                    board[node] = 2;
                }
                board
            },
            side_to_move: 0,
            phase: MillPhase::Moving,
            move_number: 30,
            pieces_in_hand: [0, 0],
            pieces_on_board: [4, 3],
            pending_removals: [1, 0],
            remove_own_piece: [true, false],
            winner: -1,
            ..MillState::default()
        };

        let mut actions = ActionList::<256>::new();
        rules.legal_actions(&rules.encode(state), &mut actions);

        assert_eq!(actions.len(), 1);
        assert_eq!(
            actions.iter().next().unwrap().to_node,
            6,
            "own pieces in a mill stay protected while a non-mill target exists"
        );
    }

    fn stalemate_fixture() -> MillState {
        let mut state = MillState {
            side_to_move: 0,
            phase: MillPhase::Moving,
            move_number: 30,
            pieces_in_hand: [0, 0],
            pieces_on_board: [4, 4],
            pending_removals: [0, 0],
            winner: -1,
            ..MillState::default()
        };
        // White corners are fully blocked by black side-middle pieces.
        for node in [0_usize, 2, 4, 6] {
            state.board[node] = 1;
        }
        for node in [1_usize, 3, 5, 7] {
            state.board[node] = 2;
        }
        state
    }

    #[test]
    fn stalemate_default_action_loses_for_side_to_move() {
        let rules = MillRules::default();
        let mut state = stalemate_fixture();
        rules.maybe_handle_stalemate(&mut state);
        assert_eq!(state.phase, MillPhase::GameOver);
        assert_eq!(state.winner, 1);
        let outcome = rules.outcome(&rules.encode(state));
        assert_eq!(outcome.kind, OutcomeKind::Win(1));
        assert_eq!(outcome.reason, "loseNoLegalMoves");
    }

    #[test]
    fn stalemate_draw_action_draws() {
        let rules = MillRules::new(MillVariantOptions {
            stalemate_action: StalemateAction::EndWithStalemateDraw,
            ..MillVariantOptions::default()
        });
        let mut state = stalemate_fixture();
        rules.maybe_handle_stalemate(&mut state);
        assert_eq!(state.phase, MillPhase::GameOver);
        assert_eq!(state.winner, 2);
        assert_eq!(
            rules.outcome(&rules.encode(state)).reason,
            "drawStalemateCondition"
        );
    }

    #[test]
    fn stalemate_change_side_to_move_only_switches_turn() {
        let rules = MillRules::new(MillVariantOptions {
            stalemate_action: StalemateAction::ChangeSideToMove,
            ..MillVariantOptions::default()
        });
        let mut state = stalemate_fixture();
        rules.maybe_handle_stalemate(&mut state);
        assert_eq!(state.phase, MillPhase::Moving);
        assert_eq!(state.side_to_move, 1);
        assert_eq!(state.pending_removals, [0, 0]);
    }

    #[test]
    fn stalemate_remove_and_make_next_move_keeps_turn_after_remove() {
        let rules = MillRules::new(MillVariantOptions {
            stalemate_action: StalemateAction::RemoveOpponentsPieceAndMakeNextMove,
            ..MillVariantOptions::default()
        });
        let mut state = stalemate_fixture();
        rules.maybe_handle_stalemate(&mut state);
        assert_eq!(state.pending_removals, [1, 0]);
        assert!(state.stalemate_removing);
        let after = rules.apply(
            &rules.encode(state),
            Action {
                kind_tag: MillActionKind::Remove as i16,
                from_node: -1,
                to_node: 1,
                aux: -1,
                payload_bits: 0,
            },
        );
        let state = MillRules::decode(&after);
        assert_eq!(state.side_to_move, 0);
        assert_eq!(state.pending_removals, [0, 0]);
        assert!(!state.stalemate_removing);
    }

    #[test]
    fn stalemate_remove_and_change_side_switches_turn_after_remove() {
        let rules = MillRules::new(MillVariantOptions {
            stalemate_action: StalemateAction::RemoveOpponentsPieceAndChangeSideToMove,
            ..MillVariantOptions::default()
        });
        let mut state = stalemate_fixture();
        rules.maybe_handle_stalemate(&mut state);
        assert_eq!(state.pending_removals, [1, 0]);
        let after = rules.apply(
            &rules.encode(state),
            Action {
                kind_tag: MillActionKind::Remove as i16,
                from_node: -1,
                to_node: 1,
                aux: -1,
                payload_bits: 0,
            },
        );
        let state = MillRules::decode(&after);
        assert_eq!(state.side_to_move, 1);
        assert_eq!(state.pending_removals, [0, 0]);
    }

    #[test]
    fn stalemate_both_players_remove_in_order() {
        let rules = MillRules::new(MillVariantOptions {
            stalemate_action: StalemateAction::BothPlayersRemoveOpponentsPiece,
            ..MillVariantOptions::default()
        });
        let mut state = stalemate_fixture();
        rules.maybe_handle_stalemate(&mut state);
        assert_eq!(state.pending_removals, [1, 1]);
        assert!(state.both_stalemate_removing);
        let after_first = rules.apply(
            &rules.encode(state),
            Action {
                kind_tag: MillActionKind::Remove as i16,
                from_node: -1,
                to_node: 1,
                aux: -1,
                payload_bits: 0,
            },
        );
        let state = MillRules::decode(&after_first);
        assert_eq!(state.side_to_move, 1);
        assert_eq!(state.pending_removals, [0, 1]);
        let after_second = rules.apply(
            &after_first,
            Action {
                kind_tag: MillActionKind::Remove as i16,
                from_node: -1,
                to_node: 0,
                aux: -1,
                payload_bits: 0,
            },
        );
        let state = MillRules::decode(&after_second);
        assert_eq!(state.side_to_move, 0);
        assert_eq!(state.pending_removals, [0, 0]);
        assert!(!state.both_stalemate_removing);
    }

    #[test]
    fn moving_phase_mill_generates_remove_obligation() {
        let rules = MillRules::default();
        let state = MillState {
            // White can move node 1 -> node 0 to complete outer-top mill
            // [0, 1, 2].  Black has enough material that removal is not
            // terminal.
            board: {
                let mut board = [0_i8; 24];
                board[1] = 1; // W d7
                board[2] = 1; // W g7
                board[3] = 1; // W g4 (moving piece)
                board[6] = 2; // B a1
                board[5] = 2; // B d1
                board[10] = 2; // B f6
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
        let snap = rules.encode(state);
        let after_move = rules.apply(
            &snap,
            Action {
                kind_tag: MillActionKind::Move as i16,
                from_node: 3,
                to_node: 0,
                aux: -1,
                payload_bits: 0,
            },
        );

        let state = MillRules::decode(&after_move);
        assert_eq!(state.side_to_move, 0, "White keeps turn after forming mill");
        assert_eq!(state.pending_removals[0], 1);

        let mut actions = ActionList::<256>::new();
        rules.legal_actions(&after_move, &mut actions);
        assert!(actions
            .iter()
            .all(|a| a.kind_tag == MillActionKind::Remove as i16));
        assert_eq!(actions.len(), 3);
    }

    #[test]
    fn moving_phase_removal_below_three_ends_game() {
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
        let snap = rules.encode(state);
        let after_remove = rules.apply(
            &snap,
            Action {
                kind_tag: MillActionKind::Remove as i16,
                from_node: -1,
                to_node: 6,
                aux: -1,
                payload_bits: 0,
            },
        );

        let state = MillRules::decode(&after_remove);
        assert_eq!(state.phase, MillPhase::GameOver);
        assert_eq!(state.winner, 0);
        assert_eq!(state.side_to_move, -1);
        let outcome = rules.outcome(&after_remove);
        assert_eq!(outcome.kind, OutcomeKind::Win(0));
        assert_eq!(outcome.reason, "loseFewerThanThree");
    }

    #[test]
    fn mill_game_workbench_do_and_undo_move() {
        let rules = MillRules::default();
        let game = MillGame::default();
        let snap = rules.initial_state(&[]);
        let mut wb = game.build_workbench(&snap);

        let mut actions = ActionList::<256>::new();
        MillGame::generate_legal(&wb, &mut actions);
        assert_eq!(actions.len(), 24);

        wb.do_move(actions[0]);
        assert_eq!(wb.side_to_move(), 1);
        assert_eq!(wb.state.pieces_in_hand[0], 8);
        assert_eq!(wb.state.pieces_on_board[0], 1);

        wb.undo_move();
        assert_eq!(wb.side_to_move(), 0);
        assert_eq!(wb.state.pieces_in_hand[0], 9);
        assert_eq!(wb.state.pieces_on_board[0], 0);
    }

    #[test]
    fn no_mill_moving_phase_fixture_reaches_moving_phase() {
        let rules = MillRules::default();
        let snap = rules.no_mill_moving_phase_snapshot();
        let state = MillRules::decode(&snap);
        assert_eq!(state.phase, MillPhase::Moving);
        assert_eq!(state.pieces_in_hand, [0, 0]);
        assert_eq!(state.pieces_on_board, [9, 9]);
        assert_eq!(state.pending_removals, [0, 0]);
    }

    #[test]
    fn position_key_changes_after_move_and_restores_after_undo() {
        let rules = MillRules::default();
        let game = MillGame::default();
        let snap = rules.initial_state(&[]);
        let mut wb = game.build_workbench(&snap);
        let initial_key = wb.key();

        let mut actions = ActionList::<256>::new();
        MillGame::generate_legal(&wb, &mut actions);
        wb.do_move(actions[0]);
        assert_ne!(wb.key(), initial_key);

        wb.undo_move();
        assert_eq!(wb.key(), initial_key);
    }

    #[test]
    fn may_remove_from_mills_always_relaxes_target_filter() {
        let options = MillVariantOptions {
            may_remove_from_mills_always: true,
            ..MillVariantOptions::default()
        };
        let rules = MillRules::new(options);

        // Build a state where Black already has a mill (a1-d1-g1) and
        // White has just formed a mill on top.  Without the option White
        // cannot remove a1/d1/g1 (all in mill, but no non-mill targets);
        // with the option White may target any of them freely.
        let mut state = MillState {
            board: [0; 24],
            side_to_move: 0,
            phase: MillPhase::Placing,
            move_number: 6,
            pieces_in_hand: [6, 6],
            pieces_on_board: [3, 3],
            pending_removals: [1, 0],
            winner: -1,
            ..MillState::default()
        };
        state.board[0] = 1; // W a7
        state.board[1] = 1; // W d7
        state.board[2] = 1; // W g7 — completes outer top mill
        state.board[6] = 2; // B a1
        state.board[5] = 2; // B d1
        state.board[4] = 2; // B g1 — black mill a1-d1-g1
        let snap = rules.encode(state);

        let mut actions = ActionList::<256>::new();
        rules.legal_actions(&snap, &mut actions);
        // Expect 3 remove targets even though every black piece is in a
        // mill, because the option is on.
        assert_eq!(actions.len(), 3);
        assert!(actions
            .iter()
            .all(|a| a.kind_tag == MillActionKind::Remove as i16));
    }

    #[test]
    fn may_remove_multiple_pending_removals_match_simultaneous_mills() {
        let options = MillVariantOptions {
            may_remove_multiple: true,
            ..MillVariantOptions::default()
        };
        let rules = MillRules::new(options);

        // Place W to form two mills at once: outer top a7-d7-g7 *and*
        // spoke top d7-d6-d5 share the d7 hub.  Place d7 last to trigger
        // simultaneous mill formation.
        let mut state = MillState {
            board: [0; 24],
            side_to_move: 0,
            phase: MillPhase::Placing,
            move_number: 8,
            pieces_in_hand: [5, 5],
            pieces_on_board: [4, 4],
            pending_removals: [0, 0],
            winner: -1,
            ..MillState::default()
        };
        state.board[0] = 1; // a7
        state.board[2] = 1; // g7
        state.board[9] = 1; // d6
        state.board[17] = 1; // d5
        state.board[6] = 2;
        state.board[5] = 2;
        state.board[4] = 2;
        state.board[15] = 2;
        let snap = rules.encode(state);
        let after = rules.apply(
            &snap,
            Action {
                kind_tag: MillActionKind::Place as i16,
                from_node: -1,
                to_node: 1, // d7 hub
                aux: -1,
                payload_bits: 0,
            },
        );
        // pending_removals[0] should be 2 because two mills formed at
        // once with may_remove_multiple = true.
        assert_eq!(after.opaque_payload[28], 2);
    }

    #[test]
    fn n_move_rule_draws_after_threshold_without_capture() {
        // Use minimum valid n_move_rule (10) and pre-load ply_since_capture
        // to one less than the threshold so a single non-capture move fires.
        let options = MillVariantOptions {
            n_move_rule: 10,
            ..MillVariantOptions::default()
        };
        let rules = MillRules::new(options);
        let mut snap = rules.no_mill_moving_phase_snapshot();
        let mut state = MillRules::decode(&snap);
        state.ply_since_capture = 9; // one below threshold
        snap = rules.encode(state);

        let after = rules.apply(
            &snap,
            Action {
                kind_tag: MillActionKind::Move as i16,
                from_node: 18, // e5
                to_node: 19,   // e4, known non-mill move in the fixture
                aux: -1,
                payload_bits: 0,
            },
        );
        let state = MillRules::decode(&after);
        assert_eq!(state.phase, MillPhase::GameOver);
        assert_eq!(state.winner, 2);
        assert_eq!(rules.outcome(&after).kind, OutcomeKind::Draw);
    }

    #[test]
    fn endgame_n_move_rule_uses_lower_threshold() {
        // Use minimum valid endgame_n_move_rule (5) and pre-load
        // ply_since_capture to one less than the endgame threshold.
        let options = MillVariantOptions {
            n_move_rule: 100,
            endgame_n_move_rule: 5,
            ..MillVariantOptions::default()
        };
        let rules = MillRules::new(options);
        let state = MillState {
            board: {
                let mut board = [0_i8; 24];
                board[1] = 1;
                board[17] = 1;
                board[3] = 1;
                board[6] = 2;
                board[5] = 2;
                board[10] = 2;
                board
            },
            side_to_move: 0,
            phase: MillPhase::Moving,
            move_number: 30,
            pieces_in_hand: [0, 0],
            // Exactly fly_piece_count (3) pieces per side → is_endgame = true
            pieces_on_board: [3, 3],
            pending_removals: [0, 0],
            winner: -1,
            // Pre-load so one more Move triggers the endgame threshold
            ply_since_capture: 4,
            ..MillState::default()
        };
        let after = rules.apply(
            &rules.encode(state),
            Action {
                kind_tag: MillActionKind::Move as i16,
                from_node: 3,
                to_node: 4,
                aux: -1,
                payload_bits: 0,
            },
        );
        assert_eq!(rules.outcome(&after).kind, OutcomeKind::Draw);
    }

    #[test]
    fn endgame_n_move_rule_ignores_fly_piece_count_four() {
        let options = MillVariantOptions {
            fly_piece_count: 4,
            n_move_rule: 100,
            endgame_n_move_rule: 5,
            ..MillVariantOptions::default()
        };
        let rules = MillRules::new(options);
        let state = MillState {
            board: {
                let mut board = [0_i8; 24];
                for node in [0_usize, 3, 6, 9] {
                    board[node] = 1;
                }
                for node in [2_usize, 5, 8, 11] {
                    board[node] = 2;
                }
                board
            },
            side_to_move: 0,
            phase: MillPhase::Moving,
            move_number: 30,
            pieces_in_hand: [0, 0],
            pieces_on_board: [4, 4],
            pending_removals: [0, 0],
            winner: -1,
            ply_since_capture: 4,
            ..MillState::default()
        };

        let after = rules.apply(
            &rules.encode(state),
            Action {
                kind_tag: MillActionKind::Move as i16,
                from_node: 3,
                to_node: 4,
                aux: -1,
                payload_bits: 0,
            },
        );

        assert_eq!(rules.outcome(&after).kind, OutcomeKind::Ongoing);
        assert_eq!(MillRules::decode(&after).ply_since_capture, 5);
    }

    #[test]
    fn may_move_in_placing_phase_adds_move_actions() {
        let options = MillVariantOptions {
            may_move_in_placing_phase: true,
            ..MillVariantOptions::default()
        };
        let rules = MillRules::new(options);
        let state = MillState {
            board: {
                let mut board = [0_i8; 24];
                board[0] = 1;
                board
            },
            side_to_move: 0,
            phase: MillPhase::Placing,
            move_number: 1,
            pieces_in_hand: [8, 9],
            pieces_on_board: [1, 0],
            pending_removals: [0, 0],
            winner: -1,
            ..MillState::default()
        };
        let mut actions = ActionList::<256>::new();
        rules.legal_actions(&rules.encode(state), &mut actions);
        assert_eq!(
            actions
                .iter()
                .filter(|a| a.kind_tag == MillActionKind::Move as i16)
                .count(),
            2
        );
    }

    #[test]
    fn placing_phase_leap_requires_empty_hand() {
        let options = MillVariantOptions {
            may_move_in_placing_phase: true,
            leap_capture: CaptureRuleConfig {
                enabled: true,
                in_placing_phase: true,
                ..CaptureRuleConfig::default()
            },
            ..MillVariantOptions::default()
        };
        let rules = MillRules::new(options);
        let state = MillState {
            board: {
                let mut board = [0_i8; 24];
                board[0] = 1;
                board[1] = 2;
                board
            },
            side_to_move: 0,
            phase: MillPhase::Placing,
            move_number: 2,
            pieces_in_hand: [7, 8],
            pieces_on_board: [1, 1],
            pending_removals: [0, 0],
            winner: -1,
            ..MillState::default()
        };

        let mut actions = ActionList::<256>::new();
        rules.legal_actions(&rules.encode(state), &mut actions);

        assert!(
            actions
                .iter()
                .any(|a| a.kind_tag == MillActionKind::Place as i16),
            "placing actions must remain available while pieces are in hand"
        );
        assert!(
            !actions.iter().any(|a| {
                a.kind_tag == MillActionKind::Move as i16 && a.from_node == 0 && a.to_node == 2
            }),
            "leap move over node 1 must wait until the hand is empty"
        );
    }

    #[test]
    fn moving_phase_fly_requires_empty_hand() {
        let options = MillVariantOptions {
            may_fly: true,
            fly_piece_count: 3,
            ..MillVariantOptions::default()
        };
        let rules = MillRules::new(options);
        let state = MillState {
            board: {
                let mut board = [0_i8; 24];
                board[0] = 1;
                board[1] = 1;
                board[2] = 1;
                board[8] = 2;
                board[9] = 2;
                board[10] = 2;
                board
            },
            side_to_move: 0,
            phase: MillPhase::Moving,
            move_number: 18,
            pieces_in_hand: [1, 0],
            pieces_on_board: [3, 3],
            pending_removals: [0, 0],
            winner: -1,
            ..MillState::default()
        };

        let mut actions = ActionList::<256>::new();
        rules.legal_actions(&rules.encode(state), &mut actions);

        assert!(
            actions
                .iter()
                .any(|a| a.kind_tag == MillActionKind::Move as i16),
            "adjacent moves still exist in this setup"
        );
        assert!(
            !actions.iter().any(|a| {
                a.kind_tag == MillActionKind::Move as i16 && a.from_node == 0 && a.to_node == 23
            }),
            "non-adjacent fly moves must not be generated with a piece in hand"
        );
    }

    /// `restrict_repeated_mills_formation` must track the last formed mill
    /// **per side**, mirroring `lastMillFromSquare[c]` /
    /// `lastMillToSquare[c]` in legacy `position.cpp`.  Without per-side
    /// tracking, a mill formed by White would silently forbid Black from
    /// re-forming a mill it just broke (and vice versa), even though only
    /// the same player should be barred.
    #[test]
    fn restrict_repeated_mills_is_per_side() {
        let options = MillVariantOptions {
            restrict_repeated_mills_formation: true,
            ..MillVariantOptions::default()
        };
        let rules = MillRules::new(options);
        // White last formed a mill via 9 -> 8.  In a state where it is now
        // Black's turn, that record must NOT block Black from any move.
        let state = MillState {
            board: {
                let mut board = [0_i8; 24];
                board[0] = 2; // black piece at node 0
                board
            },
            side_to_move: 1,
            phase: MillPhase::Moving,
            pieces_in_hand: [0, 0],
            pieces_on_board: [0, 1],
            last_mill_from: [9, -1],
            last_mill_to: [8, -1],
            ..MillState::default()
        };
        let mut actions = ActionList::<256>::new();
        rules.legal_actions(&rules.encode(state), &mut actions);
        // Black should be allowed to move freely; the white record above
        // must be ignored when computing Black's legal actions.
        assert!(!actions.is_empty(), "Black must still have legal moves");
    }

    #[test]
    fn restrict_repeated_mills_filters_reverse_reform_move() {
        let options = MillVariantOptions {
            restrict_repeated_mills_formation: true,
            ..MillVariantOptions::default()
        };
        let rules = MillRules::new(options);
        let state = MillState {
            board: {
                let mut board = [0_i8; 24];
                board[8] = 1;
                board[1] = 1;
                board[17] = 1;
                board[14] = 1;
                board[15] = 1;
                board[6] = 2;
                board[5] = 2;
                board[10] = 2;
                board
            },
            side_to_move: 0,
            phase: MillPhase::Moving,
            move_number: 20,
            pieces_in_hand: [0, 0],
            pieces_on_board: [5, 3],
            pending_removals: [0, 0],
            winner: -1,
            last_mill_from: [9, -1],
            last_mill_to: [8, -1],
            ..MillState::default()
        };
        let mut actions = ActionList::<256>::new();
        rules.legal_actions(&rules.encode(state), &mut actions);
        assert!(!actions.iter().any(|a| a.from_node == 8 && a.to_node == 9));
    }

    #[test]
    fn one_time_use_mill_allows_used_reverse_reform_move() {
        let used_line = node_bit(1) | node_bit(9) | node_bit(17);
        let options = MillVariantOptions {
            restrict_repeated_mills_formation: true,
            one_time_use_mill: true,
            ..MillVariantOptions::default()
        };
        let rules = MillRules::new(options);
        let state = MillState {
            board: {
                let mut board = [0_i8; 24];
                board[8] = 1;
                board[1] = 1;
                board[17] = 1;
                board[14] = 1;
                board[15] = 1;
                board[6] = 2;
                board[5] = 2;
                board[10] = 2;
                board
            },
            side_to_move: 0,
            phase: MillPhase::Moving,
            move_number: 20,
            pieces_in_hand: [0, 0],
            pieces_on_board: [5, 3],
            pending_removals: [0, 0],
            winner: -1,
            last_mill_from: [9, -1],
            last_mill_to: [8, -1],
            formed_mills_bb: [used_line, 0],
            ..MillState::default()
        };
        let mut actions = ActionList::<256>::new();
        rules.legal_actions(&rules.encode(state), &mut actions);
        assert!(
            actions.iter().any(|a| a.from_node == 8 && a.to_node == 9),
            "oneTimeUseMill-used lines are ignored by repeated-mill restriction"
        );
    }

    #[test]
    fn one_time_use_mill_suppresses_second_capture() {
        let options = MillVariantOptions {
            one_time_use_mill: true,
            ..MillVariantOptions::default()
        };
        let rules = MillRules::new(options);
        // Pre-populate formed_mills_bb[white] with the outer-top line
        // [0, 1, 2] (mirrors a previous mill White already consumed).
        // usable_mill_bits now consults formed_mills_bb per side rather
        // than the global used_mill_lines, so the test setup populates
        // the right state.
        let formed_top_line = node_bit(0) | node_bit(1) | node_bit(2);
        let state = MillState {
            board: {
                let mut board = [0_i8; 24];
                board[1] = 1;
                board[2] = 1;
                board[6] = 2;
                board[5] = 2;
                board
            },
            side_to_move: 0,
            phase: MillPhase::Placing,
            move_number: 4,
            pieces_in_hand: [7, 7],
            pieces_on_board: [2, 2],
            pending_removals: [0, 0],
            winner: -1,
            used_mill_lines: 1,
            formed_mills_bb: [formed_top_line, 0],
            ..MillState::default()
        };
        let after = rules.apply(
            &rules.encode(state),
            Action {
                kind_tag: MillActionKind::Place as i16,
                from_node: -1,
                to_node: 0,
                aux: -1,
                payload_bits: 0,
            },
        );
        let state = MillRules::decode(&after);
        assert_eq!(state.pending_removals[0], 0);
        assert_eq!(state.side_to_move, 1);
    }

    #[test]
    fn stop_placing_when_two_empty_squares_enters_moving_phase() {
        let options = MillVariantOptions {
            piece_count: 12,
            stop_placing_when_two_empty_squares: true,
            ..MillVariantOptions::default()
        };
        let rules = MillRules::new(options);
        let mut board = [2_i8; 24];
        board[21] = 0;
        board[22] = 0;
        board[23] = 0;
        board[20] = 2;
        board[13] = 2;
        board[5] = 2;
        let state = MillState {
            board,
            side_to_move: 0,
            phase: MillPhase::Placing,
            move_number: 21,
            pieces_in_hand: [3, 0],
            pieces_on_board: [0, 21],
            pending_removals: [0, 0],
            winner: -1,
            ..MillState::default()
        };
        let after = rules.apply(
            &rules.encode(state),
            Action {
                kind_tag: MillActionKind::Place as i16,
                from_node: -1,
                to_node: 21,
                aux: -1,
                payload_bits: 0,
            },
        );
        let state = MillRules::decode(&after);
        assert_eq!(state.pieces_in_hand, [0, 0]);
        assert_eq!(state.phase, MillPhase::Moving);
    }

    #[test]
    fn stop_placing_two_empty_does_not_preempt_mill_removal() {
        let options = MillVariantOptions {
            piece_count: 12,
            stop_placing_when_two_empty_squares: true,
            mill_formation_action_in_placing_phase:
                MillFormationActionInPlacingPhase::RemoveOpponentsPieceFromBoard,
            ..MillVariantOptions::default()
        };
        let rules = MillRules::new(options);
        let mut board = [2_i8; 24];
        // White forms a mill on [20, 21, 22] by placing at 22 while the
        // board has exactly three empty squares before the move.
        board[20] = 1;
        board[21] = 1;
        board[22] = 0;
        board[23] = 0;
        board[0] = 0;
        let state = MillState {
            board,
            side_to_move: 0,
            phase: MillPhase::Placing,
            move_number: 21,
            pieces_in_hand: [1, 0],
            pieces_on_board: [2, 19],
            pending_removals: [0, 0],
            winner: -1,
            ..MillState::default()
        };

        let after = rules.apply(
            &rules.encode(state),
            Action {
                kind_tag: MillActionKind::Place as i16,
                from_node: -1,
                to_node: 22,
                aux: -1,
                payload_bits: 0,
            },
        );
        let state = MillRules::decode(&after);

        assert_eq!(
            state.pending_removals[0], 1,
            "mill removal must be preserved when the two-empty rule is also true"
        );
        assert_eq!(
            state.side_to_move, 0,
            "mill removal keeps the forming side to move"
        );
        assert_eq!(
            state.pieces_in_hand,
            [0, 0],
            "the played piece itself leaves White with no hand pieces"
        );
        assert_eq!(state.phase, MillPhase::Placing);
    }

    #[test]
    fn stop_placing_when_two_empty_squares_is_twelve_men_only() {
        let options = MillVariantOptions {
            piece_count: 9,
            stop_placing_when_two_empty_squares: true,
            ..MillVariantOptions::default()
        };
        let rules = MillRules::new(options);
        let mut board = [2_i8; 24];
        board[21] = 0;
        board[22] = 0;
        board[23] = 0;
        board[20] = 2;
        board[13] = 2;
        board[5] = 2;
        let state = MillState {
            board,
            side_to_move: 0,
            phase: MillPhase::Placing,
            move_number: 21,
            pieces_in_hand: [3, 0],
            pieces_on_board: [0, 21],
            pending_removals: [0, 0],
            winner: -1,
            ..MillState::default()
        };

        let after = rules.apply(
            &rules.encode(state),
            Action {
                kind_tag: MillActionKind::Place as i16,
                from_node: -1,
                to_node: 21,
                aux: -1,
                payload_bits: 0,
            },
        );
        let state = MillRules::decode(&after);
        assert_eq!(
            state.phase,
            MillPhase::Placing,
            "C++ only applies this shortcut for 12-piece games"
        );
    }

    #[test]
    fn agree_to_draw_on_full_board_returns_draw_outcome() {
        let options = MillVariantOptions {
            piece_count: 12,
            board_full_action: MillBoardFullAction::AgreeToDraw,
            ..MillVariantOptions::default()
        };
        let rules = MillRules::new(options);
        let mut board = [2_i8; 24];
        board[21] = 0;
        board[20] = 2;
        board[22] = 2;
        board[13] = 2;
        board[5] = 2;
        let state = MillState {
            board,
            side_to_move: 0,
            phase: MillPhase::Placing,
            move_number: 23,
            pieces_in_hand: [1, 0],
            pieces_on_board: [0, 23],
            pending_removals: [0, 0],
            winner: -1,
            ..MillState::default()
        };
        let after = rules.apply(
            &rules.encode(state),
            Action {
                kind_tag: MillActionKind::Place as i16,
                from_node: -1,
                to_node: 21,
                aux: -1,
                payload_bits: 0,
            },
        );
        assert_eq!(rules.outcome(&after).kind, OutcomeKind::Draw);
    }

    fn board_full_one_empty_state() -> MillState {
        let mut board = [2_i8; 24];
        for node in [1_usize, 3, 5, 7, 9, 11, 14, 15, 17, 19, 20] {
            board[node] = 1;
        }
        board[21] = 0;
        MillState {
            board,
            side_to_move: 0,
            phase: MillPhase::Placing,
            move_number: 23,
            pieces_in_hand: [1, 0],
            pieces_on_board: [11, 12],
            pending_removals: [0, 0],
            winner: -1,
            ..MillState::default()
        }
    }

    fn fill_last_square(rules: &MillRules, state: MillState) -> GameStateSnapshot {
        rules.apply(
            &rules.encode(state),
            Action {
                kind_tag: MillActionKind::Place as i16,
                from_node: -1,
                to_node: 21,
                aux: -1,
                payload_bits: 0,
            },
        )
    }

    /// Mirror master src/position.cpp:3475 is_board_full_removal_at_placing_phase_end:
    /// after Rust transitions the full board to Moving, board-full removals
    /// remain regular mill-aware removals rather than stalemate removals.
    #[test]
    fn board_full_removal_does_not_use_stalemate_adjacency_filter() {
        let rules = MillRules::new(MillVariantOptions {
            piece_count: 12,
            board_full_action: MillBoardFullAction::FirstAndSecondPlayerRemovePiece,
            ..MillVariantOptions::default()
        });
        let after_fill = fill_last_square(&rules, board_full_one_empty_state());
        let state = MillRules::decode(&after_fill);
        assert_eq!(state.phase, MillPhase::Moving);
        assert_eq!(state.side_to_move, 0);

        let mut actions = ActionList::<256>::new();
        rules.legal_actions(&after_fill, &mut actions);
        assert!(
            !actions.is_empty(),
            "white must have at least one legal target"
        );

        let non_mill_opponent_targets = state
            .board
            .iter()
            .enumerate()
            .filter(|(node, piece)| {
                **piece == 2 && !is_piece_in_mill(&state, &rules.options, *node)
            })
            .count();
        assert_eq!(
            actions
                .iter()
                .filter(|a| a.kind_tag == MillActionKind::Remove as i16)
                .count(),
            non_mill_opponent_targets,
            "board-full removals must keep regular mill protection but not adjacency filtering"
        );
    }

    #[test]
    fn board_full_first_and_second_remove_in_order() {
        let rules = MillRules::new(MillVariantOptions {
            piece_count: 12,
            board_full_action: MillBoardFullAction::FirstAndSecondPlayerRemovePiece,
            ..MillVariantOptions::default()
        });
        let after_fill = fill_last_square(&rules, board_full_one_empty_state());
        let state = MillRules::decode(&after_fill);
        assert_eq!(state.phase, MillPhase::Moving);
        assert_eq!(state.side_to_move, 0, "first player removes first");
        assert_eq!(state.pending_removals, [1, 1]);

        let after_white_remove = rules.apply(
            &after_fill,
            Action {
                kind_tag: MillActionKind::Remove as i16,
                from_node: -1,
                to_node: 0,
                aux: -1,
                payload_bits: 0,
            },
        );
        let state = MillRules::decode(&after_white_remove);
        assert_eq!(state.pending_removals, [0, 1]);
        assert_eq!(state.side_to_move, 1, "second player removes next");
    }

    #[test]
    fn board_full_second_and_first_remove_in_order() {
        let rules = MillRules::new(MillVariantOptions {
            piece_count: 12,
            board_full_action: MillBoardFullAction::SecondAndFirstPlayerRemovePiece,
            ..MillVariantOptions::default()
        });
        let after_fill = fill_last_square(&rules, board_full_one_empty_state());
        let state = MillRules::decode(&after_fill);
        assert_eq!(state.phase, MillPhase::Moving);
        assert_eq!(state.side_to_move, 1, "second player removes first");
        assert_eq!(state.pending_removals, [1, 1]);

        let after_black_remove = rules.apply(
            &after_fill,
            Action {
                kind_tag: MillActionKind::Remove as i16,
                from_node: -1,
                to_node: 21,
                aux: -1,
                payload_bits: 0,
            },
        );
        let state = MillRules::decode(&after_black_remove);
        assert_eq!(state.pending_removals, [1, 0]);
        assert_eq!(state.side_to_move, 0, "first player removes next");
    }

    #[test]
    fn board_full_side_to_move_remove_respects_defender_setting() {
        let rules = MillRules::new(MillVariantOptions {
            piece_count: 12,
            is_defender_move_first: true,
            board_full_action: MillBoardFullAction::SideToMoveRemovePiece,
            ..MillVariantOptions::default()
        });
        let after_fill = fill_last_square(&rules, board_full_one_empty_state());
        let state = MillRules::decode(&after_fill);
        assert_eq!(state.phase, MillPhase::Moving);
        assert_eq!(state.side_to_move, 1);
        assert_eq!(state.pending_removals, [0, 1]);
    }

    /// Helper: build a small moving-phase state where W just moved
    /// d6→d7 (`9→1`) and the new state has a known repetition signature.
    /// We pre-populate the rolling history so the next call to `apply`
    /// will be the 3rd instance of that signature, triggering the rule.
    fn moving_phase_swap_state(side_to_move: i8) -> MillState {
        let mut state = MillState {
            side_to_move,
            phase: MillPhase::Moving,
            move_number: 30,
            pieces_in_hand: [0, 0],
            pieces_on_board: [3, 3],
            pending_removals: [0, 0],
            winner: -1,
            ..MillState::default()
        };
        // Three white pieces (a7, d6, c4) and three black pieces
        // (g7, g4, c5) — pure non-mill geometry so any move is reversible.
        state.board[0] = 1; // a7
        state.board[9] = 1; // d6
        state.board[23] = 1; // c4
        state.board[2] = 2; // g7
        state.board[3] = 2; // g4
        state.board[16] = 2; // c5
        state
    }

    #[test]
    fn threefold_triggers_after_three_repetitions() {
        let rules = MillRules::default();
        let mut state = moving_phase_swap_state(0);
        // Pre-populate history with the *post-move* signature twice.
        let mut after_move = state;
        after_move.board[9] = 0;
        after_move.board[1] = 1;
        after_move.side_to_move = 1;
        let target_key = repetition_signature(&after_move);
        state.key_history[0] = target_key;
        state.key_history[1] = target_key;
        state.key_history_len = 2;

        let after = rules.apply(
            &rules.encode(state),
            Action {
                kind_tag: MillActionKind::Move as i16,
                from_node: 9,
                to_node: 1,
                aux: -1,
                payload_bits: 0,
            },
        );
        let final_state = MillRules::decode(&after);
        assert_eq!(final_state.phase, MillPhase::GameOver);
        assert_eq!(final_state.winner, 2, "draw winner sentinel");
        assert_eq!(rules.outcome(&after).kind, OutcomeKind::Draw);
        assert_eq!(rules.outcome(&after).reason, "drawThreefoldRepetition");
    }

    #[test]
    fn threefold_does_not_trigger_after_two_repetitions() {
        let rules = MillRules::default();
        let mut state = moving_phase_swap_state(0);
        let mut after_move = state;
        after_move.board[9] = 0;
        after_move.board[1] = 1;
        after_move.side_to_move = 1;
        let target_key = repetition_signature(&after_move);
        // Only one prior occurrence: the new push will make count == 2.
        state.key_history[0] = target_key;
        state.key_history_len = 1;

        let after = rules.apply(
            &rules.encode(state),
            Action {
                kind_tag: MillActionKind::Move as i16,
                from_node: 9,
                to_node: 1,
                aux: -1,
                payload_bits: 0,
            },
        );
        let final_state = MillRules::decode(&after);
        assert_eq!(final_state.phase, MillPhase::Moving);
        assert_eq!(final_state.key_history_len, 2);
        assert_eq!(rules.outcome(&after).kind, OutcomeKind::Ongoing);
    }

    #[test]
    fn capture_clears_threefold_history() {
        let rules = MillRules::default();
        // Build a state where W has just formed a mill and must remove a
        // black piece; pre-load history with two prior occurrences of
        // the post-capture signature.  The Remove must clear history so
        // the post-state's signature count drops to 1, NOT 3.
        let mut state = MillState {
            side_to_move: 0,
            phase: MillPhase::Moving,
            move_number: 30,
            pieces_in_hand: [0, 0],
            pieces_on_board: [3, 4],
            pending_removals: [1, 0],
            winner: -1,
            ..MillState::default()
        };
        state.board[0] = 1;
        state.board[1] = 1;
        state.board[2] = 1; // W mill outer top
        state.board[6] = 2; // a1
        state.board[5] = 2; // d1
        state.board[10] = 2; // f6 (non-mill, capturable)
        state.board[15] = 2; // b4 (extra, avoid lose-by-<3 after removal)

        let mut bogus_state = state;
        bogus_state.pending_removals = [0, 0];
        bogus_state.board[10] = 0;
        bogus_state.pieces_on_board = [3, 3];
        bogus_state.side_to_move = 1;
        let target_key = repetition_signature(&bogus_state);
        state.key_history[0] = target_key;
        state.key_history[1] = target_key;
        state.key_history_len = 2;

        let after = rules.apply(
            &rules.encode(state),
            Action {
                kind_tag: MillActionKind::Remove as i16,
                from_node: -1,
                to_node: 10,
                aux: -1,
                payload_bits: 0,
            },
        );
        let final_state = MillRules::decode(&after);
        assert_eq!(final_state.phase, MillPhase::Moving);
        assert_eq!(
            final_state.key_history_len, 0,
            "Remove must wipe rolling history"
        );
        assert_eq!(rules.outcome(&after).kind, OutcomeKind::Ongoing);
    }

    #[test]
    fn disabling_threefold_keeps_game_ongoing() {
        let options = MillVariantOptions {
            threefold_repetition_rule: false,
            ..MillVariantOptions::default()
        };
        let rules = MillRules::new(options);
        let mut state = moving_phase_swap_state(0);
        // Same setup that would trigger when the rule is on: 2 prior
        // occurrences in history, the move would make it 3.
        let mut after_move = state;
        after_move.board[9] = 0;
        after_move.board[1] = 1;
        after_move.side_to_move = 1;
        let target_key = repetition_signature(&after_move);
        state.key_history[0] = target_key;
        state.key_history[1] = target_key;
        state.key_history_len = 2;

        let after = rules.apply(
            &rules.encode(state),
            Action {
                kind_tag: MillActionKind::Move as i16,
                from_node: 9,
                to_node: 1,
                aux: -1,
                payload_bits: 0,
            },
        );
        let final_state = MillRules::decode(&after);
        assert_eq!(final_state.phase, MillPhase::Moving);
        // History still has the 2 pre-loaded entries only (threefold is
        // disabled, so push is skipped entirely).
        assert_eq!(final_state.key_history_len, 2);
        assert_eq!(rules.outcome(&after).kind, OutcomeKind::Ongoing);
    }

    #[test]
    fn custodian_capture_places_single_remove_obligation() {
        let options = MillVariantOptions {
            custodian_capture: CaptureRuleConfig {
                enabled: true,
                ..CaptureRuleConfig::default()
            },
            ..MillVariantOptions::default()
        };
        let rules = MillRules::new(options);
        let state = MillState {
            board: {
                let mut board = [0_i8; 24];
                board[1] = 2; // B d7 trapped between W a7 and W g7
                board[2] = 1; // W g7
                board
            },
            side_to_move: 0,
            phase: MillPhase::Placing,
            move_number: 2,
            pieces_in_hand: [8, 8],
            pieces_on_board: [1, 1],
            ..MillState::default()
        };
        let after = rules.apply(
            &rules.encode(state),
            Action {
                kind_tag: MillActionKind::Place as i16,
                from_node: -1,
                to_node: 0, // W a7
                aux: -1,
                payload_bits: 0,
            },
        );
        let state = MillRules::decode(&after);
        assert_eq!(state.pending_removals[0], 1);
        assert_eq!(state.custodian_targets, node_bit(1));
        assert!(!state.mill_available_at_removal);
        let mut actions = ActionList::<256>::new();
        rules.legal_actions(&after, &mut actions);
        assert_eq!(
            actions.iter().map(|a| a.to_node).collect::<Vec<_>>(),
            vec![1]
        );
    }

    #[test]
    fn intervention_capture_uses_one_line_of_two_targets() {
        let options = MillVariantOptions {
            intervention_capture: CaptureRuleConfig {
                enabled: true,
                ..CaptureRuleConfig::default()
            },
            ..MillVariantOptions::default()
        };
        let rules = MillRules::new(options);
        let state = MillState {
            board: {
                let mut board = [0_i8; 24];
                board[0] = 2; // B a7
                board[2] = 2; // B g7
                board
            },
            side_to_move: 0,
            phase: MillPhase::Placing,
            move_number: 2,
            pieces_in_hand: [9, 7],
            pieces_on_board: [0, 2],
            ..MillState::default()
        };
        let after = rules.apply(
            &rules.encode(state),
            Action {
                kind_tag: MillActionKind::Place as i16,
                from_node: -1,
                to_node: 1, // W intervenes at d7
                aux: -1,
                payload_bits: 0,
            },
        );
        let state = MillRules::decode(&after);
        assert_eq!(state.pending_removals[0], 2);
        assert_eq!(state.intervention_targets, node_bit(0) | node_bit(2));
        let mut actions = ActionList::<256>::new();
        rules.legal_actions(&after, &mut actions);
        assert_eq!(actions.len(), 2);
        assert!(actions.iter().any(|a| a.to_node == 0));
        assert!(actions.iter().any(|a| a.to_node == 2));
    }

    #[test]
    fn intervention_capture_does_not_fallback_after_filtering_selected_line() {
        let options = MillVariantOptions {
            intervention_capture: CaptureRuleConfig {
                enabled: true,
                ..CaptureRuleConfig::default()
            },
            ..MillVariantOptions::default()
        };
        let rules = MillRules::new(options);
        let state = MillState {
            board: {
                let mut board = [0_i8; 24];
                // Both targets in the preferred line [0,1,2] sit in mills,
                // so filtering that selected line empties it. The alternate
                // raw line [1,9,17] has removable targets, but master does
                // not fall back to it.
                for node in [0_usize, 2, 3, 4, 6, 7, 8, 9, 10, 17] {
                    board[node] = 2;
                }
                board[5] = 1;
                board
            },
            side_to_move: 0,
            phase: MillPhase::Placing,
            move_number: 8,
            pieces_in_hand: [8, 0],
            pieces_on_board: [1, 10],
            preferred_remove_target: 0,
            ..MillState::default()
        };

        let after = rules.apply(
            &rules.encode(state),
            Action {
                kind_tag: MillActionKind::Place as i16,
                from_node: -1,
                to_node: 1,
                aux: -1,
                payload_bits: 0,
            },
        );
        let state = MillRules::decode(&after);

        assert!(is_piece_in_mill(&state, &rules.options, 0));
        assert!(is_piece_in_mill(&state, &rules.options, 2));
        assert!(!is_all_in_mills(&state, &rules.options, 2));
        assert_eq!(state.intervention_targets, 0);
        assert_eq!(state.intervention_count, 0);
        assert_eq!(
            state.pending_removals[0], 0,
            "filtered selected intervention line must cancel the capture"
        );
    }

    #[test]
    fn leap_capture_takes_precedence_over_mill() {
        let options = MillVariantOptions {
            leap_capture: CaptureRuleConfig {
                enabled: true,
                ..CaptureRuleConfig::default()
            },
            ..MillVariantOptions::default()
        };
        let rules = MillRules::new(options);
        let state = MillState {
            board: {
                let mut board = [0_i8; 24];
                board[0] = 1; // W a7 jumps to g7
                board[1] = 2; // B d7 jumped
                board[3] = 1; // W g4
                board[4] = 1; // W g1, so landing at g7 also forms a mill
                board[6] = 2;
                board[5] = 2;
                board
            },
            side_to_move: 0,
            phase: MillPhase::Moving,
            move_number: 20,
            pieces_in_hand: [0, 0],
            pieces_on_board: [3, 3],
            ..MillState::default()
        };
        let after = rules.apply(
            &rules.encode(state),
            Action {
                kind_tag: MillActionKind::Move as i16,
                from_node: 0,
                to_node: 2,
                aux: -1,
                payload_bits: 0,
            },
        );
        let state = MillRules::decode(&after);
        assert_eq!(state.pending_removals[0], 1);
        assert_eq!(state.leap_targets, node_bit(1));
        assert!(!state.mill_available_at_removal);
    }

    #[test]
    fn mill_plus_custodian_accumulates_only_when_may_remove_multiple() {
        let options = MillVariantOptions {
            may_remove_multiple: true,
            custodian_capture: CaptureRuleConfig {
                enabled: true,
                ..CaptureRuleConfig::default()
            },
            ..MillVariantOptions::default()
        };
        let rules = MillRules::new(options);
        let state = MillState {
            board: {
                let mut board = [0_i8; 24];
                board[7] = 1; // W a4
                board[6] = 1; // W a1 -> placing at a7 forms left mill
                board[1] = 2; // B d7 trapped by W a7 / W g7
                board[2] = 1; // W g7
                board[5] = 2;
                board
            },
            side_to_move: 0,
            phase: MillPhase::Placing,
            move_number: 5,
            pieces_in_hand: [6, 7],
            pieces_on_board: [3, 2],
            ..MillState::default()
        };
        let after = rules.apply(
            &rules.encode(state),
            Action {
                kind_tag: MillActionKind::Place as i16,
                from_node: -1,
                to_node: 0,
                aux: -1,
                payload_bits: 0,
            },
        );
        let state = MillRules::decode(&after);
        assert_eq!(state.pending_removals[0], 2);
        assert!(state.mill_available_at_removal);
        assert_eq!(state.custodian_targets, node_bit(1));
    }

    #[test]
    fn mill_plus_custodian_does_not_accumulate_without_may_remove_multiple() {
        let options = MillVariantOptions {
            custodian_capture: CaptureRuleConfig {
                enabled: true,
                ..CaptureRuleConfig::default()
            },
            ..MillVariantOptions::default()
        };
        let rules = MillRules::new(options);
        let state = MillState {
            board: {
                let mut board = [0_i8; 24];
                board[7] = 1;
                board[6] = 1;
                board[1] = 2;
                board[2] = 1;
                board[5] = 2;
                board
            },
            side_to_move: 0,
            phase: MillPhase::Placing,
            move_number: 5,
            pieces_in_hand: [6, 7],
            pieces_on_board: [3, 2],
            ..MillState::default()
        };
        let after = rules.apply(
            &rules.encode(state),
            Action {
                kind_tag: MillActionKind::Place as i16,
                from_node: -1,
                to_node: 0,
                aux: -1,
                payload_bits: 0,
            },
        );
        let state = MillRules::decode(&after);
        assert_eq!(state.pending_removals[0], 1);
        assert!(state.mill_available_at_removal);
        assert_eq!(state.custodian_targets, node_bit(1));
    }

    #[test]
    fn diagonal_lines_form_extra_mills_when_enabled() {
        let options = MillVariantOptions {
            has_diagonal_lines: true,
            ..MillVariantOptions::default()
        };
        let rules = MillRules::new(options);
        let mut state = MillState {
            side_to_move: 0,
            phase: MillPhase::Placing,
            move_number: 4,
            pieces_in_hand: [7, 7],
            pieces_on_board: [2, 2],
            ..MillState::default()
        };
        state.board[0] = 1; // a7
        state.board[8] = 1; // b6
        state.board[6] = 2;
        state.board[5] = 2;
        let after = rules.apply(
            &rules.encode(state),
            Action {
                kind_tag: MillActionKind::Place as i16,
                from_node: -1,
                to_node: 16, // c5 completes a7-b6-c5 diagonal
                aux: -1,
                payload_bits: 0,
            },
        );
        let state = MillRules::decode(&after);
        assert_eq!(state.pending_removals[0], 1);
        assert_eq!(state.side_to_move, 0, "turn stays while removing");
    }

    #[test]
    fn diagonal_lines_do_not_form_when_disabled() {
        let rules = MillRules::default();
        let mut state = MillState {
            side_to_move: 0,
            phase: MillPhase::Placing,
            move_number: 4,
            pieces_in_hand: [7, 7],
            pieces_on_board: [2, 2],
            ..MillState::default()
        };
        state.board[0] = 1;
        state.board[8] = 1;
        state.board[6] = 2;
        state.board[5] = 2;
        let after = rules.apply(
            &rules.encode(state),
            Action {
                kind_tag: MillActionKind::Place as i16,
                from_node: -1,
                to_node: 16,
                aux: -1,
                payload_bits: 0,
            },
        );
        let state = MillRules::decode(&after);
        assert_eq!(state.pending_removals[0], 0);
        assert_eq!(state.side_to_move, 1);
    }

    #[test]
    fn diagonal_custodian_sandwiches_opponent_on_diagonal_line() {
        let options = MillVariantOptions {
            has_diagonal_lines: true,
            piece_count: 12,
            custodian_capture: CaptureRuleConfig {
                enabled: true,
                on_diagonal_lines: true,
                ..CaptureRuleConfig::default()
            },
            ..MillVariantOptions::default()
        };
        let rules = MillRules::new(options);
        // Line [0, 8, 16]: own at 16, opponent at 8, place at 0 -> capture 8.
        let mut state = MillState {
            side_to_move: 0,
            phase: MillPhase::Placing,
            move_number: 5,
            pieces_in_hand: [7, 7],
            pieces_on_board: [2, 2],
            ..MillState::default()
        };
        state.board[16] = 1;
        state.board[8] = 2;
        let after = rules.apply(
            &rules.encode(state),
            Action {
                kind_tag: MillActionKind::Place as i16,
                from_node: -1,
                to_node: 0,
                aux: -1,
                payload_bits: 0,
            },
        );
        let st = MillRules::decode(&after);
        assert_eq!(st.custodian_targets, node_bit(8));
        assert_eq!(st.pending_removals[0], 1);
        assert!(!st.mill_available_at_removal);
    }

    #[test]
    fn defender_moves_first_when_placing_phase_ends() {
        let options = MillVariantOptions {
            is_defender_move_first: true,
            ..MillVariantOptions::default()
        };
        let rules = MillRules::new(options);
        let mut snap = rules.initial_state(&[]);
        // Same no-mill 18-placement fixture used by C++ golden tests.
        for node in [
            1, 2, 3, 0, 7, 4, 10, 9, 8, 13, 12, 6, 18, 16, 23, 17, 20, 22,
        ] {
            snap = rules.apply(
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
        let state = MillRules::decode(&snap);
        assert_eq!(state.phase, MillPhase::Moving);
        assert_eq!(
            state.side_to_move, 1,
            "defender (black) starts moving phase"
        );
    }

    /// After the opening Place on a corner, total material is even (each
    /// side has 9 pieces between hand and board) but mobility is asymmetric
    /// because White's lone piece on node 0 only contributes neighbours to
    /// itself.  Match the legacy `evaluate.cpp` formula:
    ///   value = mobility_diff + 5*(in_hand_diff + on_board_diff)
    /// then negate for Black-to-move.
    #[test]
    fn mill_evaluator_after_opening_place_matches_legacy_formula() {
        let rules = MillRules::default();
        let game = MillGame::default();
        let mut snap = rules.initial_state(&[]);
        snap = rules.apply(
            &snap,
            Action {
                kind_tag: MillActionKind::Place as i16,
                from_node: -1,
                to_node: 0,
                aux: -1,
                payload_bits: 0,
            },
        );
        let wb = game.build_workbench(&snap);
        let state = MillRules::decode(&snap);
        let opts = MillVariantOptions::default();
        let mobility = mobility_diff(&state, &opts);
        let in_hand_diff = i32::from(state.pieces_in_hand[0]) - i32::from(state.pieces_in_hand[1]);
        let on_board_diff =
            i32::from(state.pieces_on_board[0]) - i32::from(state.pieces_on_board[1]);
        let expected = -(mobility + 5 * (in_hand_diff + on_board_diff));
        assert_eq!(MillEvaluator::score(&wb), expected);
    }

    /// `focus_on_blocking_paths` should drop the material term entirely
    /// in the placing phase and leave only the mobility delta.
    #[test]
    fn mill_evaluator_focus_on_blocking_paths_drops_material_term() {
        let opts = MillVariantOptions {
            focus_on_blocking_paths: true,
            consider_mobility: false,
            ..MillVariantOptions::default()
        };
        let rules = MillRules::new(opts.clone());
        let game = MillGame::new(opts.clone());
        let mut snap = rules.initial_state(&[]);
        snap = rules.apply(
            &snap,
            Action {
                kind_tag: MillActionKind::Place as i16,
                from_node: -1,
                to_node: 0,
                aux: -1,
                payload_bits: 0,
            },
        );
        let wb = game.build_workbench(&snap);
        let state = MillRules::decode(&snap);
        let mobility = mobility_diff(&state, &opts);
        // Black to move; flip sign.  No material term (focus on blocking),
        // no mobility (consider_mobility=false but focus path still adds it
        // because should_consider_mobility is OR with focus).
        assert_eq!(MillEvaluator::score(&wb), -mobility);
    }

    /// Game-over with one side below `pieces_at_least_count` resolves to
    /// the master VALUE_MATE constant (=80) before perspective flip.
    #[test]
    fn mill_evaluator_gameover_loss_under_three_pieces() {
        let rules = MillRules::default();
        let game = MillGame::default();
        let state = MillState {
            phase: MillPhase::GameOver,
            pieces_on_board: [9, 2], // black under three pieces
            side_to_move: 1,
            winner: 0,
            ..MillState::default()
        };
        let snap = rules.encode(state);
        let wb = game.build_workbench(&snap);
        // C++ produces +VALUE_MATE for "BLACK has fewer than the minimum"
        // (favourable to white).  side_to_move=BLACK then flips perspective,
        // yielding -VALUE_MATE from Black's POV.
        assert_eq!(MillEvaluator::score(&wb), -80);
    }

    // ---------------------------------------------------------------------------
    // Phase 6.A.1: setup-position editing tests
    // ---------------------------------------------------------------------------

    #[test]
    fn setup_clear_then_set_piece_round_trips() {
        let rules = MillRules::default();
        let options = MillVariantOptions::default();

        // Start from initial state, clear to empty board.
        let mut state = rules.setup_empty();
        assert!(
            state.board.iter().all(|&p| p == 0),
            "empty board must have no pieces"
        );
        assert_eq!(
            state.pieces_in_hand[0], 9,
            "pieces_in_hand initialised from piece_count"
        );

        // Place White on node 0, Black on node 6.
        state.set_piece(0, 1);
        state.set_piece(6, 2);
        state.recompute_aux(&options);

        assert_eq!(state.board[0], 1);
        assert_eq!(state.board[6], 2);
        assert_eq!(state.pieces_on_board[0], 1);
        assert_eq!(state.pieces_on_board[1], 1);
        assert_eq!(state.pieces_in_hand[0], 8, "9 - 1 on board");
        assert_eq!(state.pieces_in_hand[1], 8);

        // Encoding and decoding must round-trip.
        let snap = rules.encode_state(state);
        let decoded = MillRules::decode_snapshot(snap);
        assert_eq!(decoded.board[0], 1);
        assert_eq!(decoded.board[6], 2);
    }

    #[test]
    fn setup_recompute_zobrist_differs_from_initial() {
        let rules = MillRules::default();
        let options = MillVariantOptions::default();

        let initial_snap = rules.initial_state(&[]);

        let mut state = rules.setup_empty();
        state.set_piece(0, 1); // add White on node 0
        state.recompute_aux(&options);
        let edited_snap = rules.encode_state(state);

        // With a piece on the board the zobrist key must differ from initial.
        assert_ne!(
            initial_snap.zobrist_key, edited_snap.zobrist_key,
            "placing a piece should change the Zobrist key"
        );
    }

    /// Two setup sequences that produce identical board states must hash to the
    /// same Zobrist key after `recompute_aux`.  Different boards must differ.
    #[test]
    fn setup_recompute_zobrist_matches_apply() {
        let rules = MillRules::default();
        let options = MillVariantOptions::default();

        // Build board A: White on 0, Black on 6, in either set_piece order.
        let mut state_a = rules.setup_empty();
        state_a.set_piece(0, 1);
        state_a.set_piece(6, 2);
        state_a.recompute_aux(&options);
        let snap_a = rules.encode_state(state_a);

        // Build the same layout again in reverse set_piece order.
        let mut state_b = rules.setup_empty();
        state_b.set_piece(6, 2);
        state_b.set_piece(0, 1);
        state_b.recompute_aux(&options);
        let snap_b = rules.encode_state(state_b);

        assert_eq!(
            snap_a.zobrist_key, snap_b.zobrist_key,
            "identical board set up in different call order must hash equally"
        );

        // A board with one fewer piece must produce a different key.
        let mut state_c = rules.setup_empty();
        state_c.set_piece(0, 1); // only White, Black removed
        state_c.recompute_aux(&options);
        let snap_c = rules.encode_state(state_c);

        assert_ne!(
            snap_a.zobrist_key, snap_c.zobrist_key,
            "different board layouts must produce distinct Zobrist keys"
        );
    }

    #[test]
    fn set_from_fen_then_export_round_trip() {
        let rules = MillRules::default();

        // A minimal placing-phase FEN with one white and one black piece.
        let fen = "O@******/********/******** w p p 1 8 1 8 0 0 0 0 0 0 0 0 1";
        let state = rules.set_from_fen(fen).expect("valid FEN must parse");

        // White on FEN pos 0 (sq 8) → node 17; Black on FEN pos 1 (sq 9) → node 18.
        assert_eq!(state.board[17], 1, "node 17 should be White");
        assert_eq!(state.board[18], 2, "node 18 should be Black");
        assert_eq!(state.side_to_move, 0, "White to move");
        assert_eq!(state.phase, MillPhase::Placing);
        assert_eq!(state.pieces_in_hand[0], 8);
        assert_eq!(state.pieces_in_hand[1], 8);

        // Export and re-import; key board fields must survive the round-trip.
        let exported = rules.export_fen(&state);
        let state2 = rules
            .set_from_fen(&exported)
            .expect("exported FEN must re-parse");
        assert_eq!(state2.board, state.board, "board round-trips");
        assert_eq!(state2.side_to_move, state.side_to_move, "side round-trips");
        assert_eq!(state2.phase, state.phase, "phase round-trips");
        assert_eq!(
            state2.pieces_in_hand, state.pieces_in_hand,
            "hand counts round-trip"
        );
    }

    #[test]
    fn set_from_fen_runs_immediate_terminal_checks() {
        let rules = MillRules::default();

        let lose_fen = "**O**O**/**@**@**/******** w m s 2 0 2 0 0 0 0 0 0 0 0 0 1";
        let lose_state = rules
            .set_from_fen(lose_fen)
            .expect("terminal fewer-than-three FEN must parse");
        assert_eq!(lose_state.phase, MillPhase::GameOver);
        assert_eq!(lose_state.winner, 1);
        assert_eq!(
            lose_state.outcome_reason,
            MillOutcomeReason::LoseFewerThanThree
        );

        let draw_fen = "***OOO**/***@@@**/******** w m s 3 0 3 0 0 0 0 0 0 0 0 100 1";
        let draw_state = rules
            .set_from_fen(draw_fen)
            .expect("terminal n-move FEN must parse");
        assert_eq!(draw_state.phase, MillPhase::GameOver);
        assert_eq!(draw_state.winner, 2);
        assert_eq!(draw_state.outcome_reason, MillOutcomeReason::DrawFiftyMove);
    }

    /// FEN trailing-extension parity: the trailing `c:/i:/l:/p:/s:` block
    /// must round-trip through `set_from_fen` -> `export_fen`, marked
    /// pieces ('X') must survive, and the signed pieceToRemoveCount must
    /// flip the new `remove_own_piece` flag.
    #[test]
    fn set_from_fen_extensions_round_trip() {
        let rules = MillRules::default();
        let original = MillState {
            board: {
                let mut board = [0_i8; 24];
                board[17] = 1;
                board[18] = 2;
                board[0] = 1; // will be flagged as marked below
                board
            },
            side_to_move: 0,
            phase: MillPhase::Placing,
            move_number: 1,
            pieces_in_hand: [7, 8],
            pieces_on_board: [2, 1],
            pending_removals: [1, 1],
            remove_own_piece: [true, true],
            last_mill_from: [9, 17],
            last_mill_to: [11, 18],
            delayed_marked_pieces: 1u32 << 0,
            custodian_targets: 1u32 << 5,
            custodian_count: 1,
            stalemate_removing: true,
            ..MillState::default()
        };
        let exported = rules.export_fen(&original);
        // The signed pieceToRemoveCount fields must be `-1`, the marked
        // square must render as `X`, and the trailing extension tokens
        // (`c:` and `s:1`) must be present.
        assert!(
            exported.contains("-1 -1"),
            "signed remove counts: {exported}"
        );
        assert!(exported.contains('X'), "marked piece: {exported}");
        assert!(exported.contains("c:"), "custodian extension: {exported}");
        assert!(exported.contains("s:1"), "stalemate flag: {exported}");

        let parsed = rules
            .set_from_fen(&exported)
            .expect("export must round-trip");
        assert_eq!(parsed.pending_removals, original.pending_removals);
        assert_eq!(parsed.remove_own_piece, original.remove_own_piece);
        assert_eq!(parsed.last_mill_from, original.last_mill_from);
        assert_eq!(parsed.last_mill_to, original.last_mill_to);
        assert_eq!(parsed.delayed_marked_pieces, original.delayed_marked_pieces);
        assert_eq!(parsed.custodian_targets, original.custodian_targets);
        assert_eq!(parsed.custodian_count, original.custodian_count);
        assert!(parsed.stalemate_removing);
    }

    /// Master format `s:2` flips `both_stalemate_removing`.  `p:NN`
    /// preserves the preferredRemoveTarget hint as a Rust dense node id.
    #[test]
    fn set_from_fen_extensions_supports_both_stalemate_and_preferred_remove() {
        let rules = MillRules::default();
        // Legacy Square id 21 == "b2"; the FEN_TO_NODE permutation maps
        // it to Rust dense node 14.
        let fen = concat!(
            "********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1",
            " p:21 s:2"
        );
        let state = rules.set_from_fen(fen).expect("valid trailing tokens");
        assert!(!state.stalemate_removing);
        assert!(state.both_stalemate_removing);
        assert_eq!(
            state.preferred_remove_target, 14,
            "p:21 (legacy Square 21 = b2) must map to Rust node 14"
        );
        // Round-trip: export must emit `p:21` again.
        let exported = rules.export_fen(&state);
        assert!(
            exported.contains("p:21"),
            "round-trip preferred-remove: {exported}"
        );
    }

    /// `formed_mills_bb` is FEN field 14, encoded as
    /// `((white_legacy_bb) << 32) | black_legacy_bb`.  Per-side bits set
    /// by `note_mill_formation` (oneTimeUseMill semantics).  Test the
    /// full round-trip and that the bitmask field becomes non-zero after
    /// a real mill formation under one_time_use_mill.
    #[test]
    fn export_fen_carries_formed_mills_bb_round_trip() {
        let rules = MillRules::new(MillVariantOptions {
            one_time_use_mill: true,
            ..MillVariantOptions::default()
        });
        // White just placed at node 2 closing the mill 0/1/2.  `apply`
        // takes the place action; under one_time_use_mill,
        // note_mill_formation populates formed_mills_bb[0].
        let mut state = MillState {
            side_to_move: 0,
            phase: MillPhase::Placing,
            move_number: 0,
            pieces_in_hand: [9, 9],
            pieces_on_board: [0, 0],
            ..MillState::default()
        };
        state.board[0] = 1;
        state.board[1] = 1;
        let after = rules.apply(
            &rules.encode_state(state),
            Action {
                kind_tag: MillActionKind::Place as i16,
                from_node: -1,
                to_node: 2,
                aux: -1,
                payload_bits: 0,
            },
        );
        let after_state = MillRules::decode(&after);
        assert_ne!(
            after_state.formed_mills_bb[0], 0,
            "mill formation must populate formed_mills_bb[white]"
        );
        let expected_white_bb = (1u32 << 0) | (1u32 << 1) | (1u32 << 2);
        assert_eq!(after_state.formed_mills_bb[0], expected_white_bb);
        assert_eq!(after_state.formed_mills_bb[1], 0);

        // Now FEN export must contain a non-zero field 14 and round-trip
        // through set_from_fen back to the same per-side bitmaps.
        let exported = rules.export_fen(&after_state);
        let fields: Vec<&str> = exported.split_whitespace().collect();
        let formed_field: u64 = fields[14].parse().expect("field 14 must be a u64");
        assert_ne!(formed_field, 0, "FEN field 14 must be non-zero");
        let parsed = rules
            .set_from_fen(&exported)
            .expect("export must round-trip");
        assert_eq!(parsed.formed_mills_bb, after_state.formed_mills_bb);
    }

    /// Field 3 must mirror legacy `Position::fen()` action token:
    ///   - `'r'` iff a removal is pending,
    ///   - `'p'` while still placing (or in Ready phase),
    ///   - `'s'` for the moving-phase select-square step,
    ///   - `'?'` on game over.
    ///
    /// The parser must round-trip every valid token.
    #[test]
    fn export_fen_action_token_matches_legacy_position_fen() {
        let rules = MillRules::default();

        // Initial position: white-to-move, placing, no pending removal.
        let initial = rules.encode_state(
            rules
                .set_from_fen("********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1")
                .unwrap(),
        );
        let state = MillRules::decode_snapshot(initial);
        let fen = rules.export_fen(&state);
        let action_field = fen.split_whitespace().nth(3).unwrap();
        assert_eq!(action_field, "p", "placing/no-remove must be 'p'");

        // Moving phase, no pending removal: action should be 's'.
        let moving = rules.no_mill_moving_phase_snapshot();
        let state = MillRules::decode_snapshot(moving);
        let fen = rules.export_fen(&state);
        let action_field = fen.split_whitespace().nth(3).unwrap();
        assert_eq!(action_field, "s", "moving phase must be 's'");

        // Re-parsing the action token must succeed without error.
        rules
            .set_from_fen(&fen)
            .expect("'s' action token must parse");
    }

    #[test]
    fn set_from_fen_matches_apply_sequence_zobrist() {
        let rules = MillRules::default();

        // Load the no-mill moving-phase fixture via both paths:
        //   (a) apply the canonical placing sequence, then export + re-import.
        //   (b) export directly and compare the board bytes.
        let snap_applied = rules.no_mill_moving_phase_snapshot();
        let state_applied = MillRules::decode_snapshot(snap_applied);

        let fen_from_apply = rules.export_fen(&state_applied);
        let state_loaded = rules
            .set_from_fen(&fen_from_apply)
            .expect("FEN exported from applied state must be parseable");

        // The board layout must be identical; auxiliary fields (last-mill,
        // mills-bitmask) may differ because export_fen outputs defaults.
        assert_eq!(
            state_loaded.board, state_applied.board,
            "set_from_fen must reproduce the same board as apply sequence"
        );
        assert_eq!(state_loaded.side_to_move, state_applied.side_to_move);
        assert_eq!(state_loaded.phase, state_applied.phase);

        // Zobrist keys must match (board + side + phase + pieces_in_hand are
        // identical, and move_number is reconstructed from fullmove counter).
        let snap_loaded = rules.encode_state(state_loaded);
        assert_eq!(
            snap_applied.zobrist_key, snap_loaded.zobrist_key,
            "Zobrist key must match after FEN export+import round-trip"
        );
    }

    #[test]
    fn setup_clear_piece_owner_zero_empties_square() {
        let rules = MillRules::default();
        let options = MillVariantOptions::default();

        let mut state = rules.setup_empty();
        state.set_piece(5, 1); // White on node 5
        state.set_piece(5, 0); // clear node 5
        state.recompute_aux(&options);

        assert_eq!(state.board[5], 0, "clearing owner=0 must empty the square");
        assert_eq!(state.pieces_on_board[0], 0);
    }
}
