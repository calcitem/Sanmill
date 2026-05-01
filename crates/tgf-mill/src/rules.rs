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
    OutcomeKind, Workbench,
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
    /// `phase=GameOver` and `outcome=Draw{drawThreefold}`.  Default is
    /// `true`, matching the C++ engine's `rule.threefoldRepetitionRule`.
    pub threefold_repetition_rule: bool,
    pub custodian_capture: CaptureRuleConfig,
    pub intervention_capture: CaptureRuleConfig,
    pub leap_capture: CaptureRuleConfig,
    pub stalemate_action: StalemateAction,
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

const MILL_TERMINAL_WIN_SCORE: i32 = 30_000;

impl MillRules {
    pub fn new(options: MillVariantOptions) -> Self {
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
    fn score(wb: &MillWorkbench) -> i32 {
        let white = wb.state.pieces_on_board[0] as i32 + wb.state.pieces_in_hand[0] as i32;
        let black = wb.state.pieces_on_board[1] as i32 + wb.state.pieces_in_hand[1] as i32;
        let score = (white - black) * 100;
        if wb.state.side_to_move == 0 {
            score
        } else {
            -score
        }
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
                // Placing a new piece is irreversible: any rolling
                // repetition history accumulated in the moving phase
                // becomes irrelevant.
                clear_key_history(&mut state);
                maybe_stop_placing_when_two_empty(&mut state, &self.options);
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
                            state.delayed_marked_pieces |= usable_bits;
                            state.side_to_move ^= 1;
                            clear_capture_state(&mut state);
                            maybe_transition_to_moving(&mut state, &self.options);
                            sync_phase_for_may_move_in_placing(&mut state, &self.options);
                            maybe_finish_full_board(&mut state, &self.options);
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
                    note_mill_formation(&mut state, -1, to as i8, usable_bits);
                } else if custodian != 0 || intervention != 0 {
                    activate_capture_state(&mut state, custodian, intervention, 0);
                    state.pending_removals[side] = capture_total(&state);
                    state.mill_available_at_removal = false;
                } else {
                    clear_capture_state(&mut state);
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
                bump_ply_since_capture(&mut state);
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
                    note_mill_formation(&mut state, from as i8, to as i8, usable_bits);
                } else if custodian != 0 || intervention != 0 {
                    activate_capture_state(&mut state, custodian, intervention, 0);
                    state.pending_removals[side] = capture_total(&state);
                    state.mill_available_at_removal = false;
                } else {
                    clear_capture_state(&mut state);
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
                debug_assert_eq!(state.board[to], opponent as i8 + 1);
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

                state.board[to] = 0;
                state.pieces_on_board[opponent] = state.pieces_on_board[opponent].saturating_sub(1);
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
                if state.phase == MillPhase::Moving
                    && state.pieces_on_board[opponent] < self.options.pieces_at_least_count
                {
                    state.phase = MillPhase::GameOver;
                    state.winner = state.side_to_move;
                    state.outcome_reason = MillOutcomeReason::LoseFewerThanThree;
                    state.side_to_move = -1;
                } else if state.pending_removals[side] == 0 {
                    clear_capture_state(&mut state);
                    if state.stalemate_removing {
                        state.stalemate_removing = false;
                    } else {
                        state.side_to_move ^= 1;
                    }
                    if state.both_stalemate_removing && state.pending_removals == [0, 0] {
                        state.both_stalemate_removing = false;
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
                        MillOutcomeReason::DrawNMoveRule => "drawNMoveRule",
                        MillOutcomeReason::DrawThreefold => "drawThreefold",
                        MillOutcomeReason::DrawStalemate => "drawStalemate",
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

    fn generate_move_actions(&self, state: &MillState, out: &mut ActionList<256>, allow_fly: bool) {
        let side = state.side_to_move as usize;
        let can_fly = allow_fly
            && self.options.may_fly
            && state.pieces_on_board[side] <= self.options.fly_piece_count;
        for (from, piece) in state.board.iter().enumerate() {
            if *piece != state.side_to_move + 1 {
                continue;
            }
            if can_fly {
                for (to, target) in state.board.iter().enumerate() {
                    if *target == 0 && !self.is_restricted_repeated_mill(state, from, to) {
                        out.push(move_action(from, to));
                    }
                }
            } else {
                for &to in self.topology.neighbors(from as u16) {
                    let to = to as usize;
                    if state.board[to] == 0 && !self.is_restricted_repeated_mill(state, from, to) {
                        out.push(move_action(from, to));
                    }
                }
            }
        }
    }

    fn is_restricted_repeated_mill(&self, state: &MillState, from: usize, to: usize) -> bool {
        if !self.options.restrict_repeated_mills_formation {
            return false;
        }
        if state.last_mill_from < 0 || state.last_mill_to < 0 {
            return false;
        }
        if from != state.last_mill_to as usize || to != state.last_mill_from as usize {
            return false;
        }
        let mut candidate = *state;
        candidate.board[from] = 0;
        candidate.board[to] = state.side_to_move + 1;
        count_mills_at(&candidate, &self.options, to, state.side_to_move) > 0
    }

    fn generate_remove_actions(&self, state: &MillState, out: &mut ActionList<256>) {
        let capture_targets =
            state.custodian_targets | state.intervention_targets | state.leap_targets;
        if capture_targets != 0 && !state.mill_available_at_removal {
            self.generate_capture_remove_actions(state, out, capture_targets);
            return;
        }

        if capture_targets != 0 {
            self.generate_capture_remove_actions(state, out, capture_targets);
        }

        let opponent_piece = (state.side_to_move ^ 1) + 1;

        // When `may_remove_from_mills_always` is set the rule simplifies:
        // every opponent piece is a legal target, regardless of whether
        // it sits in a mill.  Otherwise we mirror the C++ default (and
        // the FIDE Mill rule): mill pieces can only be removed when no
        // non-mill alternative exists.
        if self.options.may_remove_from_mills_always {
            for (node, piece) in state.board.iter().enumerate() {
                if *piece == opponent_piece {
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

        let has_non_mill_target = state.board.iter().enumerate().any(|(idx, piece)| {
            *piece == opponent_piece && !is_piece_in_mill(state, &self.options, idx)
        });

        for (node, piece) in state.board.iter().enumerate() {
            if *piece != opponent_piece {
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
    state.side_to_move = if options.is_defender_move_first { 1 } else { 0 };
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
        }
        MillBoardFullAction::SecondAndFirstPlayerRemovePiece => {
            state.pending_removals = [1, 1];
            state.side_to_move = 1;
        }
        MillBoardFullAction::SideToMoveRemovePiece => {
            state.pending_removals = [0, 0];
            let remover = if options.is_defender_move_first { 1 } else { 0 };
            state.side_to_move = remover;
            state.pending_removals[remover as usize] = 1;
        }
    }
}

fn total_mills_count(state: &MillState, options: &MillVariantOptions, side: i8) -> u8 {
    mill_lines(options)
        .iter()
        .filter(|line| line.iter().all(|idx| state.board[*idx] == side + 1))
        .count() as u8
}

fn apply_removal_based_on_mill_counts(state: &mut MillState, options: &MillVariantOptions) {
    let white_mills = total_mills_count(state, options, 0);
    let black_mills = total_mills_count(state, options, 1);
    let (white_remove, black_remove) = if white_mills == 0 && black_mills == 0 {
        (0, 0)
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

fn bump_ply_since_capture(state: &mut MillState) {
    if state.phase == MillPhase::Moving {
        state.ply_since_capture = state.ply_since_capture.saturating_add(1);
    }
}

fn maybe_draw_by_n_move_rule(state: &mut MillState, options: &MillVariantOptions) {
    if state.phase != MillPhase::Moving {
        return;
    }
    let threshold = if options.endgame_n_move_rule > 0
        && options.endgame_n_move_rule < options.n_move_rule
        && state.pieces_on_board.iter().any(|count| *count <= 3)
    {
        options.endgame_n_move_rule
    } else {
        options.n_move_rule
    };
    if threshold > 0 && u32::from(state.ply_since_capture) >= threshold {
        state.phase = MillPhase::GameOver;
        state.winner = 2;
        state.outcome_reason = MillOutcomeReason::DrawNMoveRule;
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
    if options.one_time_use_mill {
        bits & !state.used_mill_lines
    } else {
        bits
    }
}

fn note_mill_formation(state: &mut MillState, from: i8, to: i8, bits: u32) {
    state.last_mill_from = from;
    state.last_mill_to = to;
    state.used_mill_lines |= bits;
}

/// Hash the parts of a `MillState` that participate in threefold
/// repetition: board layout, side to move, phase, pending-removals.
/// Excludes counters that change each ply (`move_number`,
/// `ply_since_capture`, etc.) so a repeated board genuinely hashes the
/// same on every visit.
fn repetition_signature(state: &MillState) -> u64 {
    let mut key = 0xcbf2_9ce4_8422_2325_u64;
    let mut mix = |byte: u8| {
        key ^= u64::from(byte);
        key = key.wrapping_mul(0x1000_0000_01b3);
    };
    for piece in state.board {
        mix(piece as u8);
    }
    mix(state.side_to_move as u8);
    mix(state.phase as u8);
    mix(state.pending_removals[0]);
    mix(state.pending_removals[1]);
    if key == 0 {
        1
    } else {
        key
    }
}

/// Empty the rolling repetition history.  Called on irreversible events
/// (a Place into hand drains, a Remove that captures a piece) so cycles
/// only span pure Move sequences.
fn clear_key_history(state: &mut MillState) {
    state.key_history = [0_u64; 24];
    state.key_history_len = 0;
}

/// Append the current state's repetition signature to the rolling
/// buffer (FIFO, max 24 entries) and end the game in a draw when the
/// same signature has occurred three times.  No-op when
/// `threefold_repetition_rule` is disabled.
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
    winner: i8,
    outcome_reason: MillOutcomeReason,
    ply_since_capture: u16,
    last_mill_from: i8,
    last_mill_to: i8,
    used_mill_lines: u32,
    delayed_marked_pieces: u32,
    custodian_targets: u32,
    intervention_targets: u32,
    leap_targets: u32,
    custodian_count: u8,
    intervention_count: u8,
    leap_count: u8,
    mill_available_at_removal: bool,
    stalemate_removing: bool,
    both_stalemate_removing: bool,
    /// Ring buffer of repetition-only Zobrist signatures (board + side +
    /// phase + pending removals) collected at moving-phase ply boundaries.
    /// Cleared on Place / Remove so only reversible Move events count.
    key_history: [u64; 24],
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
            winner: -1,
            outcome_reason: MillOutcomeReason::Ongoing,
            ply_since_capture: 0,
            last_mill_from: -1,
            last_mill_to: -1,
            used_mill_lines: 0,
            delayed_marked_pieces: 0,
            custodian_targets: 0,
            intervention_targets: 0,
            leap_targets: 0,
            custodian_count: 0,
            intervention_count: 0,
            leap_count: 0,
            mill_available_at_removal: false,
            stalemate_removing: false,
            both_stalemate_removing: false,
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
    DrawNMoveRule = 2,
    DrawFullBoard = 3,
    LoseFullBoard = 4,
    DrawThreefold = 5,
    LoseNoLegalMoves = 6,
    DrawStalemate = 7,
}

impl MillState {
    fn encode(self) -> [u8; 256] {
        let mut payload = [0_u8; 256];
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
        payload[33] = self.last_mill_from as u8;
        payload[34] = self.last_mill_to as u8;
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
        payload[252] = u8::from(self.mill_available_at_removal);
        payload[253] = u8::from(self.stalemate_removing);
        payload[254] = u8::from(self.both_stalemate_removing);
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
            last_mill_from: payload[33] as i8,
            last_mill_to: payload[34] as i8,
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
            mill_available_at_removal: payload[252] != 0,
            stalemate_removing: payload[253] != 0,
            both_stalemate_removing: payload[254] != 0,
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
        self.last_mill_from = -1;
        self.last_mill_to = -1;
        self.used_mill_lines = 0;
        self.delayed_marked_pieces = 0;
        self.custodian_targets = 0;
        self.intervention_targets = 0;
        self.leap_targets = 0;
        self.custodian_count = 0;
        self.intervention_count = 0;
        self.leap_count = 0;
        self.mill_available_at_removal = false;
        self.stalemate_removing = false;
        self.both_stalemate_removing = false;
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
        // Strip optional custodian/intervention/etc. suffixes that begin with
        // ` c:`, ` i:`, ` l:`, ` p:`, ` s:`.
        let core = if let Some(pos) = fen.find(['c', 'i', 'l']).and_then(|p| {
            if p > 0 && &fen[p - 1..p] == " " {
                Some(p - 1)
            } else {
                None
            }
        }) {
            fen[..pos].trim()
        } else {
            fen.trim()
        };

        let fields: Vec<&str> = core.split_whitespace().collect();
        if fields.len() < 17 {
            return Err(format!("FEN needs >= 17 fields, got {}", fields.len()));
        }

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
        for (i, c) in all_chars.chars().enumerate() {
            board[FEN_TO_NODE[i]] = if c == 'O' {
                1
            } else if c == '@' {
                2
            } else if c == '*' || c == 'X' {
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

        let phase = match fields[2] {
            "r" | "p" => MillPhase::Placing,
            "m" => MillPhase::Moving,
            "o" => MillPhase::GameOver,
            s => return Err(format!("invalid phase '{s}' in FEN")),
        };

        let parse_u8 = |s: &str| -> Result<u8, String> {
            s.parse::<u8>()
                .map_err(|_| format!("cannot parse '{s}' as u8"))
        };
        let parse_u16 = |s: &str| -> Result<u16, String> {
            s.parse::<u16>()
                .map_err(|_| format!("cannot parse '{s}' as u16"))
        };

        let on_board_w = parse_u8(fields[4])?;
        let in_hand_w = parse_u8(fields[5])?;
        let on_board_b = parse_u8(fields[6])?;
        let in_hand_b = parse_u8(fields[7])?;
        let remove_w = parse_u8(fields[8])?;
        let remove_b = parse_u8(fields[9])?;
        // Fields 10-14 (last-mill positions, mills bitmask) are ignored;
        // defaults (0 / no-mills) are used for the returned state.
        let rule50 = parse_u16(fields[15])?;
        let full_move: i32 = fields[16].parse::<i32>().unwrap_or(1).max(1);

        // Reconstruct game ply (move_number) from full-move counter, matching
        // the Dart Position.setFen formula:
        //   gamePly = max(2*(fullMove-1), 0) + (side==black ? 1 : 0)
        let side_is_black = i16::from(side_to_move == 1);
        let move_number = (2_i32 * (full_move - 1)).max(0) as i16 + side_is_black;

        Ok(MillState {
            board,
            side_to_move,
            phase,
            move_number,
            pieces_on_board: [on_board_w, on_board_b],
            pieces_in_hand: [in_hand_w, in_hand_b],
            pending_removals: [remove_w, remove_b],
            ply_since_capture: rule50,
            winner: -1,
            ..MillState::default()
        })
    }

    /// Serialize a `MillState` into a Mill FEN string compatible with the
    /// legacy Dart/C++ engine.
    ///
    /// The mills-bitmask and last-mill-from/to fields are always output as
    /// `0`; the round-trip guarantee is that `set_from_fen(export_fen(s))`
    /// produces a state with the same board, side, phase, and piece counts.
    pub fn export_fen(&self, state: &MillState) -> String {
        // Rust board node index → FEN board position index (inverse of FEN_TO_NODE).
        const NODE_TO_FEN_POS: [usize; 24] = [
            23, 16, 17, 18, 19, 20, 21, 22, 15, 8, 9, 10, 11, 12, 13, 14, 7, 0, 1, 2, 3, 4, 5, 6,
        ];

        // Build the 24-character board section (split into 3×8 with '/').
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
            fenchars[slot] = match state.board[node] {
                1 => b'O',
                2 => b'@',
                _ => b'*',
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

        format!(
            "{} {} {} p {} {} {} {} {} {} 0 0 0 0 0 {} {}",
            board_str,
            side,
            phase,
            state.pieces_on_board[0],
            state.pieces_in_hand[0],
            state.pieces_on_board[1],
            state.pieces_in_hand[1],
            state.pending_removals[0],
            state.pending_removals[1],
            state.ply_since_capture,
            full_move,
        )
    }
}

fn position_key(state: &MillState) -> u64 {
    // Stable FNV-1a style position key.  This is not the final incremental
    // Zobrist implementation, but unlike the Phase 4 zero key it gives the
    // Rust transposition table distinct keys for distinct Mill positions.
    let mut key = 0xcbf2_9ce4_8422_2325_u64;
    let mut mix = |byte: u8| {
        key ^= u64::from(byte);
        key = key.wrapping_mul(0x1000_0000_01b3);
    };
    for piece in state.board {
        mix(piece as u8);
    }
    mix(state.side_to_move as u8);
    mix(state.phase as u8);
    mix((state.move_number & 0xff) as u8);
    mix(((state.move_number >> 8) & 0xff) as u8);
    mix(state.pieces_in_hand[0]);
    mix(state.pieces_in_hand[1]);
    mix(state.pieces_on_board[0]);
    mix(state.pieces_on_board[1]);
    mix(state.pending_removals[0]);
    mix(state.pending_removals[1]);
    mix(state.winner as u8);
    mix(state.outcome_reason as u8);
    mix((state.ply_since_capture & 0xff) as u8);
    mix((state.ply_since_capture >> 8) as u8);
    mix(state.last_mill_from as u8);
    mix(state.last_mill_to as u8);
    for byte in state.used_mill_lines.to_le_bytes() {
        mix(byte);
    }
    for byte in state.delayed_marked_pieces.to_le_bytes() {
        mix(byte);
    }
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
    mix(u8::from(state.mill_available_at_removal));
    if key == 0 {
        1
    } else {
        key
    }
}

/// Number of mill lines passing through `node` that are now all owned by
/// `side_to_move`.  Used by `apply` to honour `may_remove_multiple`.
fn count_mills_at(
    state: &MillState,
    options: &MillVariantOptions,
    node: usize,
    side_to_move: i8,
) -> usize {
    formed_mill_bits_at(state, options, node, side_to_move).count_ones() as usize
}

fn formed_mill_bits_at(
    state: &MillState,
    options: &MillVariantOptions,
    node: usize,
    side_to_move: i8,
) -> u32 {
    let mut bits = 0_u32;
    for (line_idx, line) in mill_lines(options).iter().enumerate() {
        if line.contains(&node) && line.iter().all(|idx| state.board[*idx] == side_to_move + 1) {
            bits |= 1_u32 << line_idx;
        }
    }
    bits
}

/// Mirrors `Position::potential_mills_count` from `src/position.cpp`: counts
/// lines through `to` whose other two squares already hold `side`'s pieces,
/// optionally pretending the square at `from` (the source for a Move) is
/// empty.  Used by MovePicker-style ordering heuristics.
fn potential_mills_count_at(
    state: &MillState,
    options: &MillVariantOptions,
    to: usize,
    side: i8,
    from: Option<usize>,
) -> u32 {
    let target = side + 1;
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
        if all_color {
            count += 1;
        }
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
    let piece = state.board[node];
    if piece == 0 {
        return false;
    }
    mill_lines_for_node(options, node)
        .iter()
        .any(|line| line.iter().all(|idx| state.board[*idx] == piece))
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
    if !config.only_available_when_own_pieces_leq3 || state.phase != MillPhase::Moving {
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
    for line in active_capture_lines(config, options) {
        if to == line[1] && state.board[line[0]] == opponent && state.board[line[2]] == opponent {
            let targets = node_bit(line[0]) | node_bit(line[2]);
            let filtered = filter_capture_targets(state, options, targets);
            if filtered != 0 {
                return filtered;
            }
        }
    }
    0
}

fn detect_leap_targets(
    state: &MillState,
    options: &MillVariantOptions,
    from: usize,
    to: usize,
) -> u32 {
    let config = &options.leap_capture;
    if !capture_phase_allowed(config, state.phase) || !capture_piece_count_allowed(config, state) {
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

    #[test]
    fn mill_action_mark_and_delay_records_mill_bits_without_immediate_removal() {
        let (_rules, snap) = placing_mill_fixture_for_action(
            MillFormationActionInPlacingPhase::MarkAndDelayRemovingPieces,
        );
        let state = MillRules::decode(&snap);
        assert_eq!(state.pending_removals, [0, 0]);
        assert_ne!(state.delayed_marked_pieces, 0);
        assert_eq!(state.side_to_move, 1);
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
        assert_eq!(rules.outcome(&rules.encode(state)).reason, "drawStalemate");
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
        let options = MillVariantOptions {
            n_move_rule: 2,
            ..MillVariantOptions::default()
        };
        let rules = MillRules::new(options);
        let mut snap = rules.no_mill_moving_phase_snapshot();
        let mut state = MillRules::decode(&snap);
        state.ply_since_capture = 1;
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
        let options = MillVariantOptions {
            n_move_rule: 100,
            endgame_n_move_rule: 1,
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
            pieces_on_board: [3, 3],
            pending_removals: [0, 0],
            winner: -1,
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
            last_mill_from: 9,
            last_mill_to: 8,
            ..MillState::default()
        };
        let mut actions = ActionList::<256>::new();
        rules.legal_actions(&rules.encode(state), &mut actions);
        assert!(!actions.iter().any(|a| a.from_node == 8 && a.to_node == 9));
    }

    #[test]
    fn one_time_use_mill_suppresses_second_capture() {
        let options = MillVariantOptions {
            one_time_use_mill: true,
            ..MillVariantOptions::default()
        };
        let rules = MillRules::new(options);
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
            used_mill_lines: 1, // outer-top [0,1,2] already consumed
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
        assert_eq!(rules.outcome(&after).reason, "drawThreefold");
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
        // History still grew (the disable check happens inside the helper,
        // but we explicitly skip both push and check when off).
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

    #[test]
    fn mill_evaluator_scores_piece_material_from_side_to_move() {
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
        // Material is equal (white has 8 in hand + 1 on board, black has 9 in
        // hand), so score is zero from black-to-move perspective.
        assert_eq!(MillEvaluator::score(&wb), 0);
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
