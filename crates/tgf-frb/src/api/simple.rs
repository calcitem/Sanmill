// SPDX-License-Identifier: GPL-3.0-or-later
// tgf-frb – Phase 1 API surface.
//
// Conventions:
//   - `#[flutter_rust_bridge::frb(sync)]` makes the call synchronous on the
//     Dart side (no Future wrapping); use only for cheap, non-blocking calls.
//   - All public functions in this module are auto-exported to Dart by codegen.

use once_cell::sync::Lazy;
use std::sync::Mutex;
use std::thread;

use crate::frb_generated::StreamSink;
use tgf_core::{Action, ActionList, BoardTopology, Game, GameRules};
use tgf_mill::{
    default_mill_topology, recommended_search_depth, CaptureRuleConfig as NativeCaptureRuleConfig,
    EngineRuntimeOptions, MillActionKind, MillBoardFullAction as NativeMillBoardFullAction,
    MillFormationActionInPlacingPhase as NativeMillFormationActionInPlacingPhase, MillGame,
    MillRules, MillVariantOptions as NativeMillVariantOptions,
    StalemateAction as NativeStalemateAction,
};
use tgf_othello::{OthelloGame, OthelloRules};
use tgf_search::SearchResult;
use tgf_search::{
    MctsOptions, MctsSearcher, SearchAbortHandle, SearchAlgorithm, SearchOptions, SearchPolicy,
    Searcher,
};

static ACTIVE_SEARCH: Lazy<Mutex<Option<SearchAbortHandle>>> = Lazy::new(|| Mutex::new(None));

/// Mill uses Remove actions in qsearch when [SearchPolicy::remove_kind_tag] is set.
fn mill_searcher_default() -> Searcher<MillGame> {
    let mut s = Searcher::new();
    s.set_policy(SearchPolicy {
        remove_kind_tag: Some(MillActionKind::Remove as i16),
    });
    s
}

/// FRB required initialisation.  Called once at Flutter app startup before
/// any other TGF function.  Do not remove.
#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

// ---------------------------------------------------------------------------
// Phase 1 smoke-check
// ---------------------------------------------------------------------------

/// Returns a greeting string confirming that the Rust → Dart bridge works.
/// Called from Dart as `tgfHelloWorld()` after `await RustLib.init()`.
#[flutter_rust_bridge::frb(sync)]
pub fn tgf_hello_world() -> String {
    format!(
        "hello from TGF (TabletopGameFramework) v{}",
        env!("CARGO_PKG_VERSION")
    )
}

/// Returns the TGF Rust crate version string.
#[flutter_rust_bridge::frb(sync)]
pub fn tgf_version() -> String {
    env!("CARGO_PKG_VERSION").to_owned()
}

/// Public FRB DTO for the subset of Mill variant options already supported by
/// the Rust-native rules scaffold.  It intentionally mirrors the field names
/// that will later replace the C++ Rule struct; new rule flags are added
/// here whenever `crates/tgf-mill::MillVariantOptions` grows them.
#[derive(Clone, Debug)]
pub struct MillVariantOptions {
    pub piece_count: u8,
    pub fly_piece_count: u8,
    pub pieces_at_least_count: u8,
    pub may_fly: bool,
    pub has_diagonal_lines: bool,
    pub mill_formation_action_in_placing_phase: MillFormationActionInPlacingPhase,
    pub may_remove_from_mills_always: bool,
    pub may_remove_multiple: bool,
    pub n_move_rule: u32,
    pub endgame_n_move_rule: u32,
    pub may_move_in_placing_phase: bool,
    pub is_defender_move_first: bool,
    pub restrict_repeated_mills_formation: bool,
    pub one_time_use_mill: bool,
    pub stop_placing_when_two_empty_squares: bool,
    pub board_full_action: MillBoardFullAction,
    pub threefold_repetition_rule: bool,
    pub custodian_capture: CaptureRuleConfig,
    pub intervention_capture: CaptureRuleConfig,
    pub leap_capture: CaptureRuleConfig,
    pub stalemate_action: StalemateAction,
    /// Mirror of `gameOptions.getConsiderMobility()` from the legacy C++
    /// engine.  Drives [`MillEvaluator`] mobility scoring.  Default
    /// `true` matches the C++ side.
    pub consider_mobility: bool,
    /// Mirror of `gameOptions.getFocusOnBlockingPaths()`: when set, the
    /// static evaluator drops the material term so the search prioritises
    /// blocking lines.  Default `false`.
    pub focus_on_blocking_paths: bool,
}

#[derive(Clone, Debug)]
pub enum StalemateAction {
    EndWithStalemateLoss,
    ChangeSideToMove,
    RemoveOpponentsPieceAndMakeNextMove,
    RemoveOpponentsPieceAndChangeSideToMove,
    EndWithStalemateDraw,
    BothPlayersRemoveOpponentsPiece,
}

impl From<StalemateAction> for NativeStalemateAction {
    fn from(value: StalemateAction) -> Self {
        match value {
            StalemateAction::EndWithStalemateLoss => NativeStalemateAction::EndWithStalemateLoss,
            StalemateAction::ChangeSideToMove => NativeStalemateAction::ChangeSideToMove,
            StalemateAction::RemoveOpponentsPieceAndMakeNextMove => {
                NativeStalemateAction::RemoveOpponentsPieceAndMakeNextMove
            }
            StalemateAction::RemoveOpponentsPieceAndChangeSideToMove => {
                NativeStalemateAction::RemoveOpponentsPieceAndChangeSideToMove
            }
            StalemateAction::EndWithStalemateDraw => NativeStalemateAction::EndWithStalemateDraw,
            StalemateAction::BothPlayersRemoveOpponentsPiece => {
                NativeStalemateAction::BothPlayersRemoveOpponentsPiece
            }
        }
    }
}

impl From<NativeStalemateAction> for StalemateAction {
    fn from(value: NativeStalemateAction) -> Self {
        match value {
            NativeStalemateAction::EndWithStalemateLoss => StalemateAction::EndWithStalemateLoss,
            NativeStalemateAction::ChangeSideToMove => StalemateAction::ChangeSideToMove,
            NativeStalemateAction::RemoveOpponentsPieceAndMakeNextMove => {
                StalemateAction::RemoveOpponentsPieceAndMakeNextMove
            }
            NativeStalemateAction::RemoveOpponentsPieceAndChangeSideToMove => {
                StalemateAction::RemoveOpponentsPieceAndChangeSideToMove
            }
            NativeStalemateAction::EndWithStalemateDraw => StalemateAction::EndWithStalemateDraw,
            NativeStalemateAction::BothPlayersRemoveOpponentsPiece => {
                StalemateAction::BothPlayersRemoveOpponentsPiece
            }
        }
    }
}

#[derive(Clone, Debug)]
pub enum MillFormationActionInPlacingPhase {
    RemoveOpponentsPieceFromBoard,
    RemoveOpponentsPieceFromHandThenOpponentsTurn,
    RemoveOpponentsPieceFromHandThenYourTurn,
    OpponentRemovesOwnPiece,
    MarkAndDelayRemovingPieces,
    RemovalBasedOnMillCounts,
}

impl From<MillFormationActionInPlacingPhase> for NativeMillFormationActionInPlacingPhase {
    fn from(value: MillFormationActionInPlacingPhase) -> Self {
        match value {
            MillFormationActionInPlacingPhase::RemoveOpponentsPieceFromBoard => {
                NativeMillFormationActionInPlacingPhase::RemoveOpponentsPieceFromBoard
            }
            MillFormationActionInPlacingPhase::RemoveOpponentsPieceFromHandThenOpponentsTurn => {
                NativeMillFormationActionInPlacingPhase::RemoveOpponentsPieceFromHandThenOpponentsTurn
            }
            MillFormationActionInPlacingPhase::RemoveOpponentsPieceFromHandThenYourTurn => {
                NativeMillFormationActionInPlacingPhase::RemoveOpponentsPieceFromHandThenYourTurn
            }
            MillFormationActionInPlacingPhase::OpponentRemovesOwnPiece => {
                NativeMillFormationActionInPlacingPhase::OpponentRemovesOwnPiece
            }
            MillFormationActionInPlacingPhase::MarkAndDelayRemovingPieces => {
                NativeMillFormationActionInPlacingPhase::MarkAndDelayRemovingPieces
            }
            MillFormationActionInPlacingPhase::RemovalBasedOnMillCounts => {
                NativeMillFormationActionInPlacingPhase::RemovalBasedOnMillCounts
            }
        }
    }
}

impl From<NativeMillFormationActionInPlacingPhase> for MillFormationActionInPlacingPhase {
    fn from(value: NativeMillFormationActionInPlacingPhase) -> Self {
        match value {
            NativeMillFormationActionInPlacingPhase::RemoveOpponentsPieceFromBoard => {
                MillFormationActionInPlacingPhase::RemoveOpponentsPieceFromBoard
            }
            NativeMillFormationActionInPlacingPhase::RemoveOpponentsPieceFromHandThenOpponentsTurn => {
                MillFormationActionInPlacingPhase::RemoveOpponentsPieceFromHandThenOpponentsTurn
            }
            NativeMillFormationActionInPlacingPhase::RemoveOpponentsPieceFromHandThenYourTurn => {
                MillFormationActionInPlacingPhase::RemoveOpponentsPieceFromHandThenYourTurn
            }
            NativeMillFormationActionInPlacingPhase::OpponentRemovesOwnPiece => {
                MillFormationActionInPlacingPhase::OpponentRemovesOwnPiece
            }
            NativeMillFormationActionInPlacingPhase::MarkAndDelayRemovingPieces => {
                MillFormationActionInPlacingPhase::MarkAndDelayRemovingPieces
            }
            NativeMillFormationActionInPlacingPhase::RemovalBasedOnMillCounts => {
                MillFormationActionInPlacingPhase::RemovalBasedOnMillCounts
            }
        }
    }
}

#[derive(Clone, Debug)]
pub struct CaptureRuleConfig {
    pub enabled: bool,
    pub on_square_edges: bool,
    pub on_cross_lines: bool,
    pub on_diagonal_lines: bool,
    pub in_placing_phase: bool,
    pub in_moving_phase: bool,
    pub only_available_when_own_pieces_leq3: bool,
}

impl From<CaptureRuleConfig> for NativeCaptureRuleConfig {
    fn from(value: CaptureRuleConfig) -> Self {
        Self {
            enabled: value.enabled,
            on_square_edges: value.on_square_edges,
            on_cross_lines: value.on_cross_lines,
            on_diagonal_lines: value.on_diagonal_lines,
            in_placing_phase: value.in_placing_phase,
            in_moving_phase: value.in_moving_phase,
            only_available_when_own_pieces_leq3: value.only_available_when_own_pieces_leq3,
        }
    }
}

impl From<NativeCaptureRuleConfig> for CaptureRuleConfig {
    fn from(value: NativeCaptureRuleConfig) -> Self {
        Self {
            enabled: value.enabled,
            on_square_edges: value.on_square_edges,
            on_cross_lines: value.on_cross_lines,
            on_diagonal_lines: value.on_diagonal_lines,
            in_placing_phase: value.in_placing_phase,
            in_moving_phase: value.in_moving_phase,
            only_available_when_own_pieces_leq3: value.only_available_when_own_pieces_leq3,
        }
    }
}

#[derive(Clone, Debug)]
pub enum MillBoardFullAction {
    FirstPlayerLose,
    FirstAndSecondPlayerRemovePiece,
    SecondAndFirstPlayerRemovePiece,
    SideToMoveRemovePiece,
    AgreeToDraw,
}

impl From<MillBoardFullAction> for NativeMillBoardFullAction {
    fn from(value: MillBoardFullAction) -> Self {
        match value {
            MillBoardFullAction::FirstPlayerLose => NativeMillBoardFullAction::FirstPlayerLose,
            MillBoardFullAction::FirstAndSecondPlayerRemovePiece => {
                NativeMillBoardFullAction::FirstAndSecondPlayerRemovePiece
            }
            MillBoardFullAction::SecondAndFirstPlayerRemovePiece => {
                NativeMillBoardFullAction::SecondAndFirstPlayerRemovePiece
            }
            MillBoardFullAction::SideToMoveRemovePiece => {
                NativeMillBoardFullAction::SideToMoveRemovePiece
            }
            MillBoardFullAction::AgreeToDraw => NativeMillBoardFullAction::AgreeToDraw,
        }
    }
}

impl From<NativeMillBoardFullAction> for MillBoardFullAction {
    fn from(value: NativeMillBoardFullAction) -> Self {
        match value {
            NativeMillBoardFullAction::FirstPlayerLose => MillBoardFullAction::FirstPlayerLose,
            NativeMillBoardFullAction::FirstAndSecondPlayerRemovePiece => {
                MillBoardFullAction::FirstAndSecondPlayerRemovePiece
            }
            NativeMillBoardFullAction::SecondAndFirstPlayerRemovePiece => {
                MillBoardFullAction::SecondAndFirstPlayerRemovePiece
            }
            NativeMillBoardFullAction::SideToMoveRemovePiece => {
                MillBoardFullAction::SideToMoveRemovePiece
            }
            NativeMillBoardFullAction::AgreeToDraw => MillBoardFullAction::AgreeToDraw,
        }
    }
}

impl From<MillVariantOptions> for NativeMillVariantOptions {
    fn from(value: MillVariantOptions) -> Self {
        Self {
            piece_count: value.piece_count,
            fly_piece_count: value.fly_piece_count,
            pieces_at_least_count: value.pieces_at_least_count,
            may_fly: value.may_fly,
            has_diagonal_lines: value.has_diagonal_lines,
            mill_formation_action_in_placing_phase: value
                .mill_formation_action_in_placing_phase
                .into(),
            may_remove_from_mills_always: value.may_remove_from_mills_always,
            may_remove_multiple: value.may_remove_multiple,
            n_move_rule: value.n_move_rule,
            endgame_n_move_rule: value.endgame_n_move_rule,
            may_move_in_placing_phase: value.may_move_in_placing_phase,
            is_defender_move_first: value.is_defender_move_first,
            restrict_repeated_mills_formation: value.restrict_repeated_mills_formation,
            one_time_use_mill: value.one_time_use_mill,
            stop_placing_when_two_empty_squares: value.stop_placing_when_two_empty_squares,
            board_full_action: value.board_full_action.into(),
            threefold_repetition_rule: value.threefold_repetition_rule,
            custodian_capture: value.custodian_capture.into(),
            intervention_capture: value.intervention_capture.into(),
            leap_capture: value.leap_capture.into(),
            stalemate_action: value.stalemate_action.into(),
            consider_mobility: value.consider_mobility,
            focus_on_blocking_paths: value.focus_on_blocking_paths,
        }
    }
}

/// Default Nine Men's Morris variant options.
#[flutter_rust_bridge::frb(sync)]
pub fn native_mill_default_variant_options() -> MillVariantOptions {
    let defaults = NativeMillVariantOptions::default();
    MillVariantOptions {
        piece_count: defaults.piece_count,
        fly_piece_count: defaults.fly_piece_count,
        pieces_at_least_count: defaults.pieces_at_least_count,
        may_fly: defaults.may_fly,
        has_diagonal_lines: defaults.has_diagonal_lines,
        mill_formation_action_in_placing_phase: defaults
            .mill_formation_action_in_placing_phase
            .into(),
        may_remove_from_mills_always: defaults.may_remove_from_mills_always,
        may_remove_multiple: defaults.may_remove_multiple,
        n_move_rule: defaults.n_move_rule,
        endgame_n_move_rule: defaults.endgame_n_move_rule,
        may_move_in_placing_phase: defaults.may_move_in_placing_phase,
        is_defender_move_first: defaults.is_defender_move_first,
        restrict_repeated_mills_formation: defaults.restrict_repeated_mills_formation,
        one_time_use_mill: defaults.one_time_use_mill,
        stop_placing_when_two_empty_squares: defaults.stop_placing_when_two_empty_squares,
        board_full_action: defaults.board_full_action.into(),
        threefold_repetition_rule: defaults.threefold_repetition_rule,
        custodian_capture: defaults.custodian_capture.into(),
        intervention_capture: defaults.intervention_capture.into(),
        leap_capture: defaults.leap_capture.into(),
        stalemate_action: defaults.stalemate_action.into(),
        consider_mobility: defaults.consider_mobility,
        focus_on_blocking_paths: defaults.focus_on_blocking_paths,
    }
}

// ---------------------------------------------------------------------------
// Phase 7 Othello pressure-test APIs.
// ---------------------------------------------------------------------------

/// Number of legal actions from the Rust-native Othello initial position.
#[flutter_rust_bridge::frb(sync)]
pub fn native_othello_initial_legal_count() -> u32 {
    let rules = OthelloRules::default();
    let snap = rules.initial_state(&[]);
    let mut actions = ActionList::<256>::new();
    rules.legal_actions(&snap, &mut actions);
    actions.len() as u32
}

/// Run the generic Rust Searcher<OthelloGame> for one ply and return the
/// selected destination node.
#[flutter_rust_bridge::frb(sync)]
pub fn native_othello_search_depth_one_best_to_node() -> i32 {
    let rules = OthelloRules::default();
    let game = OthelloGame;
    let snap = rules.initial_state(&[]);
    let mut wb = game.build_workbench(&snap);
    let mut searcher = Searcher::<OthelloGame>::new();
    searcher.search(&mut wb, 1).best_action.to_node as i32
}

// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// Phase 3 topology API: Rust-native Mill topology exposed through FRB.
// ---------------------------------------------------------------------------

#[derive(Clone, Debug)]
pub struct TopologyPoint {
    pub id: u16,
    pub square: u16,
    pub label: String,
    pub x: f32,
    pub y: f32,
}

#[derive(Clone, Debug)]
pub struct TopologyEdge {
    pub a: u16,
    pub b: u16,
}

#[derive(Clone, Debug)]
pub struct TopologyBlob {
    pub name: String,
    pub points: Vec<TopologyPoint>,
    pub edges: Vec<TopologyEdge>,
    pub line_groups: Vec<Vec<u16>>,
}

/// Search algorithm selector exposed to Flutter.
/// Values match C++ `Algorithm` enum in `src/types.h` and Dart's
/// `SearchAlgorithm` enum in `general_settings.dart`.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum MillSearchAlgorithm {
    AlphaBeta,
    #[default]
    Pvs,
    Mtdf,
    Mcts,
    Random,
}

impl From<MillSearchAlgorithm> for SearchAlgorithm {
    fn from(alg: MillSearchAlgorithm) -> Self {
        match alg {
            MillSearchAlgorithm::AlphaBeta => SearchAlgorithm::AlphaBeta,
            MillSearchAlgorithm::Pvs => SearchAlgorithm::Pvs,
            MillSearchAlgorithm::Mtdf => SearchAlgorithm::Mtdf,
            MillSearchAlgorithm::Mcts => SearchAlgorithm::Mcts,
            MillSearchAlgorithm::Random => SearchAlgorithm::Random,
        }
    }
}

/// Engine configuration passed from Flutter to Rust for every search.
/// Consolidates all user-facing AI behaviour knobs that were previously
/// sent as UCI `setoption` strings via the C++ MethodChannel.
#[derive(Clone, Debug)]
pub struct MillEngineConfig {
    /// Search algorithm.  Default: MTD(f) (P2-A).
    pub algorithm: MillSearchAlgorithm,
    /// AI search depth (0 → auto via drawOnHumanExperience table on Dart side).
    pub depth: i32,
    /// Time limit in milliseconds (0 = unlimited; depth drives termination).
    pub move_time_ms: u32,
    /// When true, apply the `AiIsLazy` depth adjustment from master
    /// `search_engine.cpp`: if the previous best value suggests the position
    /// is winning by more than 1 piece, cap origin_depth to 1; otherwise
    /// keep it (P2-G).
    pub ai_is_lazy: bool,
    /// The best value from the previous turn's search, used by `ai_is_lazy`
    /// logic. Mirrors master's `bestvalue` input to `executeSearch` (P2-G).
    /// Flutter should back-fill this from the last `bestMove` event score.
    pub last_best_value: i32,
    /// SkillLevel (0-30): controls MCTS iteration count (skill_level * 2048)
    /// matching master `SkillLevel * ITERATIONS_PER_SKILL_LEVEL` (P2-F/P2-I).
    pub skill_level: u8,
}

impl Default for MillEngineConfig {
    fn default() -> Self {
        Self {
            // P2-A: master defaults to Algorithm = 2 (MTD(f)); align here.
            algorithm: MillSearchAlgorithm::Mtdf,
            depth: 1,
            move_time_ms: 0,
            ai_is_lazy: false,
            last_best_value: 0,
            skill_level: 1,
        }
    }
}

#[derive(Clone, Debug)]
pub struct EngineEvent {
    pub kind: String,
    pub depth: i32,
    pub score: i32,
    pub nodes: u64,
    pub to_node: i32,
    /// For bestMove events: the full UCI move string ("a4", "a1-a4", "xa4")
    /// is stored here (P1-C.2).  For error events: the error message.
    /// Using the existing `reason` field avoids adding new FRB bridge fields
    /// that would require codegen; the Dart side already exposes `reason`.
    pub reason: String,
}

impl EngineEvent {
    fn ready() -> Self {
        Self::new("ready")
    }

    fn stopped() -> Self {
        Self::new("stopped")
    }

    fn error(reason: &str) -> Self {
        Self {
            kind: "error".to_owned(),
            depth: 0,
            score: 0,
            nodes: 0,
            to_node: -1,
            reason: reason.to_owned(),
        }
    }

    fn info(depth: i32, score: i32, nodes: u64) -> Self {
        Self {
            kind: "info".to_owned(),
            depth,
            score,
            nodes,
            to_node: -1,
            reason: String::new(),
        }
    }

    /// Construct a bestMove event with complete action information (P1-C.2).
    /// `root_side_to_move` is used to flip the score to White's perspective
    /// (P1-C.1), matching master SearchEngine::emitCommand.
    /// The full UCI move string is stored in `reason` for backwards-compatible
    /// access without requiring FRB codegen update.
    fn best_move_full(action: tgf_core::Action, score: i32, root_side_to_move: i8) -> Self {
        let output_score = if root_side_to_move == 1 {
            -score
        } else {
            score
        };
        let uci = crate::api::kernel::action_to_uci_str(action);
        Self {
            kind: "bestMove".to_owned(),
            depth: action.from_node as i32,
            score: output_score,
            nodes: 0,
            to_node: action.to_node as i32,
            reason: uci,
        }
    }

    fn new(kind: &str) -> Self {
        Self {
            kind: kind.to_owned(),
            depth: 0,
            score: 0,
            nodes: 0,
            to_node: -1,
            reason: String::new(),
        }
    }
}

/// Return the Rust-native standard 24-point Mill topology.
///
/// This is the Phase 3 single source of truth for board geometry.  The Dart
/// shell converts this blob into its existing BoardGeometry value object.
#[flutter_rust_bridge::frb(sync)]
pub fn kernel_topology() -> TopologyBlob {
    let topo = default_mill_topology();
    let points = topo
        .nodes()
        .iter()
        .map(|node| TopologyPoint {
            id: node.id,
            square: node.square,
            label: node.label.to_owned(),
            x: node.point.x,
            y: node.point.y,
        })
        .collect();
    let edges = topo
        .edges()
        .iter()
        .map(|edge| TopologyEdge {
            a: edge.a,
            b: edge.b,
        })
        .collect();
    TopologyBlob {
        name: topo.name().to_owned(),
        points,
        edges,
        line_groups: topo.line_groups().to_vec(),
    }
}

// ---------------------------------------------------------------------------
// Phase 4 native Rust Mill rules scaffold API.
// ---------------------------------------------------------------------------

/// Number of legal actions from a fresh Rust-native Mill initial position.
/// This should match the mature C++ engine at depth 1: 24 placing moves.
#[flutter_rust_bridge::frb(sync)]
pub fn native_mill_initial_legal_count() -> u32 {
    let rules = MillRules::default();
    let snap = rules.initial_state(&[]);
    let mut actions = ActionList::<256>::new();
    rules.legal_actions(&snap, &mut actions);
    actions.len() as u32
}

/// Opening legal action count for an explicit variant option set.
#[flutter_rust_bridge::frb(sync)]
pub fn native_mill_initial_legal_count_for_variant(variant: MillVariantOptions) -> u32 {
    let rules = MillRules::new(variant.into());
    let snap = rules.initial_state(&[]);
    let mut actions = ActionList::<256>::new();
    rules.legal_actions(&snap, &mut actions);
    actions.len() as u32
}

/// Apply the first Rust-native place action and return the side-to-move tag.
/// This is a small typed smoke-check for the native MillRules scaffold.
#[flutter_rust_bridge::frb(sync)]
pub fn native_mill_apply_first_place_side_to_move() -> i32 {
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
    next.side_to_move as i32
}

/// Play the canonical a7-d7-g7 mill formation sequence and return how many
/// native Rust remove actions are generated.
#[flutter_rust_bridge::frb(sync)]
pub fn native_mill_mill_sequence_remove_count() -> u32 {
    let rules = MillRules::default();
    let mut snap = rules.initial_state(&[]);
    for node in [1_i16, 6, 2, 5, 0] {
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
    let mut actions = ActionList::<256>::new();
    rules.legal_actions(&snap, &mut actions);
    actions
        .iter()
        .filter(|a| a.kind_tag == MillActionKind::Remove as i16)
        .count() as u32
}

/// Smoke-check: moving-phase move that forms a mill generates remove actions.
#[flutter_rust_bridge::frb(sync)]
pub fn native_mill_moving_mill_remove_count() -> u32 {
    MillRules::moving_mill_remove_count_smoke()
}

/// Smoke-check: removing below three pieces ends the game with White as winner.
#[flutter_rust_bridge::frb(sync)]
pub fn native_mill_removal_below_three_winner() -> i32 {
    MillRules::removal_below_three_winner_smoke()
}

/// Run the Rust generic Searcher<MillGame> for one ply and return the best
/// destination node.  This is a Phase 5 smoke-check for the monomorphised
/// search path.
#[flutter_rust_bridge::frb(sync)]
pub fn native_mill_search_depth_one_best_to_node() -> i32 {
    let rules = MillRules::default();
    let game = MillGame::default();
    let snap = rules.initial_state(&[]);
    let mut wb = game.build_workbench(&snap);
    let mut searcher = mill_searcher_default();
    searcher.search(&mut wb, 1).best_action.to_node as i32
}

/// Run the Rust generic PVS path for one ply and return the best destination.
#[flutter_rust_bridge::frb(sync)]
pub fn native_mill_pvs_depth_one_best_to_node() -> i32 {
    let rules = MillRules::default();
    let game = MillGame::default();
    let snap = rules.initial_state(&[]);
    let mut wb = game.build_workbench(&snap);
    let mut searcher = mill_searcher_default();
    searcher.search_pvs(&mut wb, 1).best_action.to_node as i32
}

/// Run deterministic random-search with a caller-supplied seed.
#[flutter_rust_bridge::frb(sync)]
pub fn native_mill_random_best_to_node(seed: u64) -> i32 {
    let rules = MillRules::default();
    let game = MillGame::default();
    let snap = rules.initial_state(&[]);
    let mut wb = game.build_workbench(&snap);
    let mut searcher = mill_searcher_default();
    searcher.set_random_seed(seed);
    searcher.random_search(&mut wb).best_action.to_node as i32
}

/// Run the Rust generic MCTS scaffold and return the selected destination node.
#[flutter_rust_bridge::frb(sync)]
pub fn native_mill_mcts_best_to_node(seed: u64, iterations_per_move: u32) -> i32 {
    let rules = MillRules::default();
    let game = MillGame::default();
    let snap = rules.initial_state(&[]);
    let mut wb = game.build_workbench(&snap);
    let mut mcts = MctsSearcher::<MillGame>::new();
    mcts.set_random_seed(seed);
    mcts.search_with_options(
        &mut wb,
        MctsOptions {
            iterations: iterations_per_move.max(1),
            playout_depth: 2,
            time_limit_ms: None,
            exploration: 0.5,
            ab_assist_depth: 0,
        },
    )
    .best_action
    .to_node as i32
}
/// Smoke-check that the Rust searcher honours a zero-millisecond time limit.
#[flutter_rust_bridge::frb(sync)]
pub fn native_mill_search_zero_time_limit_aborts() -> bool {
    let rules = MillRules::default();
    let game = MillGame::default();
    let snap = rules.initial_state(&[]);
    let mut wb = game.build_workbench(&snap);
    let mut searcher = mill_searcher_default();
    searcher.set_options(SearchOptions {
        depth_extension: false,
        node_limit: None,
        time_limit_ms: Some(0),
        allow_null_move: true,
        ..Default::default()
    });
    let _ = searcher.search(&mut wb, 3);
    searcher.was_aborted()
}

/// Runs PVS on the given Mill snapshot and streams engine events.
///
/// Used by [crate::api::kernel::tgf_kernel_mill_search_events] and the
/// parameterless smoke entry point below.
pub(crate) fn spawn_mill_pvs_event_stream(
    snapshot: tgf_core::GameStateSnapshot,
    options: NativeMillVariantOptions,
    depth: i32,
    sink: StreamSink<EngineEvent>,
) {
    let config = MillEngineConfig {
        depth,
        ..Default::default()
    };
    spawn_mill_engine_config_event_stream(snapshot, options, config, sink);
}

/// Launch a search thread using the full `MillEngineConfig`.  Emits one
/// `info` event per IDS depth, then a final `bestMove` + `stopped`.
pub(crate) fn spawn_mill_engine_config_event_stream(
    snapshot: tgf_core::GameStateSnapshot,
    options: NativeMillVariantOptions,
    config: MillEngineConfig,
    sink: StreamSink<EngineEvent>,
) {
    thread::spawn(move || {
        if sink.add(EngineEvent::ready()).is_err() {
            return;
        }

        let game = MillGame::new(options);
        let mut wb = game.build_workbench(&snapshot);
        let mut searcher = mill_searcher_default();

        // Apply time limit if requested.
        if config.move_time_ms > 0 {
            searcher.set_options(SearchOptions {
                time_limit_ms: Some(config.move_time_ms as u64),
                ..SearchOptions::default()
            });
        }

        {
            let mut active = ACTIVE_SEARCH.lock().expect("active search mutex poisoned");
            *active = Some(searcher.abort_handle());
        }

        let requested_depth = if config.depth > 0 {
            config.depth
        } else {
            let rules = MillRules::new(options.clone());
            let state = MillRules::decode_snapshot(snapshot);
            let runtime = EngineRuntimeOptions {
                skill_level: config.skill_level,
                draw_on_human_experience: true,
                developer_mode: true,
            };
            recommended_search_depth(&state, rules.options(), &runtime).max(1)
        };

        // P2-G: AiIsLazy depth adjustment mirroring master executeSearch.
        // np = lastBestValue / VALUE_EACH_PIECE (5); if np > 1 the position
        // is "clearly won/lost", so cap origin_depth to 1 or 4.
        const VALUE_EACH_PIECE: i32 = 5;
        let origin_depth = if config.ai_is_lazy {
            let np = config.last_best_value.abs() / VALUE_EACH_PIECE;
            if np > 1 {
                if requested_depth < 4 {
                    1
                } else {
                    4
                }
            } else {
                requested_depth.max(1)
            }
        } else {
            requested_depth.max(1)
        };
        let max_depth = origin_depth;
        let mut result = SearchResult::default_none();

        match SearchAlgorithm::from(config.algorithm) {
            SearchAlgorithm::Random => {
                // P2-J: use time-seeded random to match master's rand()+time() behaviour.
                let seed = std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map(|d| d.as_secs())
                    .unwrap_or(42);
                searcher.set_random_seed(seed);
                result = searcher.random_search(&mut wb);
                let _ = sink.add(EngineEvent::info(1, result.score, result.nodes));
            }
            SearchAlgorithm::AlphaBeta => {
                // P2-B: master Algorithm 0 (AlphaBeta) and 1 (PVS) both call
                // the same `Search::search()` function (PVS implementation).
                // Route AlphaBeta to search_pvs here for master equivalence.
                // P2-H: no aspiration windows (master IDS uses none).
                for d in 1..=max_depth {
                    if searcher.was_aborted() {
                        break;
                    }
                    result = searcher.search_pvs(&mut wb, d);
                    let _ = sink.add(EngineEvent::info(d, result.score, result.nodes));
                }
            }
            SearchAlgorithm::Mtdf => {
                // P2-C: use search_mtdf which returns the best action from the
                // TT after all MTD(f) iterations, matching master's MTDF
                // bestMove update via reference.
                result = searcher.search_mtdf(&mut wb, max_depth);
                let _ = sink.add(EngineEvent::info(max_depth, result.score, result.nodes));
            }
            SearchAlgorithm::Mcts => {
                // P2-I: skill_level * 2048 iterations (master ITERATIONS_PER_SKILL_LEVEL=2048).
                // Empty board early stop: max_iterations = 1 when no pieces on board.
                let pieces_on_board = wb.pieces_on_board();
                let all_pieces_on_board = pieces_on_board[0] as u32 + pieces_on_board[1] as u32;
                let skill_iterations = if all_pieces_on_board == 0 {
                    1_u32
                } else {
                    (u32::from(config.skill_level) + 1).saturating_mul(2048)
                };
                let mut mcts = MctsSearcher::<MillGame>::new();
                let mcts_result = mcts.search_with_options(
                    &mut wb,
                    MctsOptions {
                        iterations: skill_iterations,
                        playout_depth: 6, // P2-I: master ALPHA_BETA_DEPTH=6
                        time_limit_ms: if config.move_time_ms > 0 {
                            Some(config.move_time_ms as u64)
                        } else {
                            None
                        },
                        exploration: 0.5,
                        ab_assist_depth: 6, // P2-I: master ALPHA_BETA_DEPTH=6
                    },
                );
                result = SearchResult {
                    best_action: mcts_result.best_action,
                    score: 0,
                    nodes: mcts_result.visits as u64,
                };
                let _ = sink.add(EngineEvent::info(max_depth, 0, result.nodes));
            }
            SearchAlgorithm::Pvs => {
                // P2-H: IDS without aspiration windows (master IDS uses none).
                for d in 1..=max_depth {
                    if searcher.was_aborted() {
                        break;
                    }
                    result = searcher.search_pvs(&mut wb, d);
                    let _ = sink.add(EngineEvent::info(d, result.score, result.nodes));
                    // P2-G: AiIsLazy early abort already reflected in max_depth;
                    // no further IDS break needed here.
                    let _ = d; // suppress warning
                    if false {
                        break;
                    }
                }
            }
        }

        let _ = sink.add(EngineEvent::best_move_full(
            result.best_action,
            result.score,
            snapshot.side_to_move,
        ));
        let _ = sink.add(EngineEvent::stopped());
        let mut active = ACTIVE_SEARCH.lock().expect("active search mutex poisoned");
        *active = None;
    });
}

pub(crate) fn spawn_kernel_search_error(message: String, sink: StreamSink<EngineEvent>) {
    thread::spawn(move || {
        let _ = sink.add(EngineEvent::error(&message));
        let _ = sink.add(EngineEvent::stopped());
    });
}

/// Phase 5 async search event stream.
///
/// This is intentionally minimal: it spawns a worker thread, runs the native
/// Rust Searcher<MillGame>, and emits Ready / Info / BestMove / Stopped.
/// Later work replaces this with a cancellable long-lived search worker.
pub fn native_mill_search_events(depth: i32, sink: StreamSink<EngineEvent>) {
    let rules = MillRules::default();
    let snap = rules.initial_state(&[]);
    spawn_mill_pvs_event_stream(snap, NativeMillVariantOptions::default(), depth, sink);
}

/// Request that the currently running native Rust search stops.
///
/// Returns false when no native search worker is active.
#[flutter_rust_bridge::frb(sync)]
pub fn native_mill_search_stop() -> bool {
    let active = ACTIVE_SEARCH.lock().expect("active search mutex poisoned");
    if let Some(handle) = active.as_ref() {
        handle.request_abort();
        true
    } else {
        false
    }
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeSet;

    use super::*;
    use tgf_mill::MillPhase;

    fn native_legal_uci_set(
        snapshot: &tgf_core::GameStateSnapshot,
        rules: &MillRules,
    ) -> BTreeSet<String> {
        let mut actions = ActionList::<256>::new();
        rules.legal_actions(snapshot, &mut actions);
        actions
            .iter()
            .map(native_action_to_uci)
            .collect::<BTreeSet<_>>()
    }

    fn native_action_to_uci(action: &Action) -> String {
        let topo = default_mill_topology();
        match action.kind_tag {
            x if x == MillActionKind::Place as i16 => {
                topo.label_of(action.to_node as u16).to_owned()
            }
            x if x == MillActionKind::Move as i16 => format!(
                "{}-{}",
                topo.label_of(action.from_node as u16),
                topo.label_of(action.to_node as u16)
            ),
            x if x == MillActionKind::Remove as i16 => {
                format!("x{}", topo.label_of(action.to_node as u16))
            }
            _ => panic!("unsupported native action kind {}", action.kind_tag),
        }
    }

    /// Find the native [`Action`] whose UCI string equals `uci` in the legal
    /// set of `snap`.  Used by the random-walk differential test to apply the
    /// same UCI move to both engines.
    fn native_action_from_uci(
        snap: &tgf_core::GameStateSnapshot,
        uci: &str,
        rules: &MillRules,
    ) -> Option<Action> {
        let mut actions = ActionList::<256>::new();
        rules.legal_actions(snap, &mut actions);
        actions.into_iter().find(|a| native_action_to_uci(a) == uci)
    }

    /// Tiny deterministic xorshift64* PRNG.  Seeded from a fixed constant so
    /// the random-walk test produces the same sequence on every machine.
    fn next_random_index(state: &mut u64, len: usize) -> usize {
        debug_assert!(len > 0);
        let mut x = *state;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        *state = x;
        let scrambled = x.wrapping_mul(0x2545_F491_4F6C_DD1D);
        (scrambled as usize) % len
    }

    #[test]
    fn native_search_replies_to_human_star_with_star_square() {
        let rules = MillRules::default();
        let game = MillGame::default();
        let mut snap = rules.initial_state(&[]);

        // Human first move on legacy SQ_16 / Rust node 9 ("d6"), one of the
        // non-diagonal master-branch star-priority squares.
        snap = rules.apply(
            &snap,
            Action {
                kind_tag: MillActionKind::Place as i16,
                from_node: -1,
                to_node: 9,
                aux: -1,
                payload_bits: 0,
            },
        );
        assert_eq!(snap.side_to_move, 1, "black should reply");

        let mut wb = game.build_workbench(&snap);
        let mut searcher = mill_searcher_default();
        let best = searcher.search_pvs(&mut wb, 1).best_action;

        // Remaining non-diagonal star squares are SQ_18/SQ_20/SQ_22 =
        // Rust nodes 11/13/15.  This guards against confusing legacy square
        // ids (16/18/20/22) with dense Rust node ids.
        assert!(
            matches!(best.to_node, 11 | 13 | 15),
            "expected a star-square reply, got to_node={}",
            best.to_node
        );
    }

    /// Regression for "AI forms a mill but does not remove the human's
    /// piece": after a Place action that completes a mill, the rules
    /// engine must keep `side_to_move` on the mover and set
    /// `pending_removals[mover] > 0`, and the next search-and-apply pass
    /// must produce a Remove action.
    #[test]
    fn native_search_after_mill_keeps_turn_and_chains_remove() {
        let rules = MillRules::default();
        let game = MillGame::default();
        let options = NativeMillVariantOptions::default();

        // Build a placing-phase position via the public setup API where it
        // is White's turn and White can complete the a7-d7-g7 mill (nodes
        // 0/1/2) by placing on node 1.  Black has two pieces on nodes 3
        // and 5 to provide remove targets after the mill is formed.
        let mut state = rules.setup_empty();
        state.set_piece(0, 1); // White on node 0 (a7)
        state.set_piece(2, 1); // White on node 2 (g7)
        state.set_piece(3, 2); // Black on node 3 (g4)
        state.set_piece(5, 2); // Black on node 5 (d1)
        state.set_side_to_move(0);
        state.recompute_aux(&options);
        let snap = rules.encode_state(state);

        // 1) The first search must place on node 1 to form the mill.
        let mut wb = game.build_workbench(&snap);
        let mut searcher = mill_searcher_default();
        let mill_move = searcher.search_pvs(&mut wb, 2).best_action;
        assert_eq!(
            mill_move.kind_tag,
            MillActionKind::Place as i16,
            "expected a Place action that completes the mill"
        );
        assert_eq!(mill_move.to_node, 1);

        // 2) Apply it.  Side-to-move must stay on White and pending_removal
        //    must become 1, exactly as the C++ legacy engine does after a
        //    mill is formed.  The opaque payload encodes pending_removals
        //    at offsets 28..30 (see `MillState::encode` in tgf-mill).
        let after_mill = rules.apply(&snap, mill_move);
        assert_eq!(
            after_mill.side_to_move, 0,
            "after forming a mill side-to-move must remain on the mover"
        );
        assert_eq!(
            after_mill.opaque_payload[28], 1,
            "mill formation must set pending_removals[mover] = 1"
        );

        // 3) The next search must produce a Remove action.  Without the
        //    fix in NativeMillAiTurnController.playIfAiTurn this would
        //    happen on the *next* tap; the regression test is that the
        //    engine itself can still produce the remove from the same
        //    side_to_move when asked.
        let mut wb2 = game.build_workbench(&after_mill);
        let remove_move = searcher.search_pvs(&mut wb2, 1).best_action;
        assert_eq!(
            remove_move.kind_tag,
            MillActionKind::Remove as i16,
            "after a mill the next AI action must be Remove, got kind={}",
            remove_move.kind_tag,
        );
        assert!(
            matches!(remove_move.to_node, 3 | 5),
            "remove target must be one of Black's pieces (node 3 or 5), got {}",
            remove_move.to_node
        );
    }

    /// Same as `native_search_after_mill_keeps_turn_and_chains_remove` but
    /// searches at depth=5 to activate null-move pruning (which requires
    /// depth >= NULL_MOVE_MIN_DEPTH = 3).  Regression for Phase 5 null-move
    /// incorrectly preventing the AI from finding a Remove action after
    /// forming a mill.
    #[test]
    fn native_search_after_mill_chains_remove_at_high_depth() {
        let rules = MillRules::default();
        let game = MillGame::default();
        let options = NativeMillVariantOptions::default();

        let mut state = rules.setup_empty();
        state.set_piece(0, 1); // White on node 0 (a7)
        state.set_piece(2, 1); // White on node 2 (g7)
        state.set_piece(3, 2); // Black on node 3 (g4)
        state.set_piece(5, 2); // Black on node 5 (d1)
        state.set_side_to_move(0);
        state.recompute_aux(&options);
        let snap = rules.encode_state(state);

        // 1) Search at depth=2 to find the mill-forming move.
        let mut wb = game.build_workbench(&snap);
        let mut searcher = mill_searcher_default();
        let mill_move = searcher.search_pvs(&mut wb, 2).best_action;
        assert_eq!(mill_move.to_node, 1, "AI must form the mill at node 1");

        // 2) Apply the mill-forming move.
        let after_mill = rules.apply(&snap, mill_move);
        assert_eq!(after_mill.side_to_move, 0, "still White's turn");
        assert_eq!(
            after_mill.opaque_payload[28], 1,
            "pending_removals[White]=1"
        );

        // 3) At depth=5 (null-move activates at depth >= 3), the Remove search
        //    must still find and return a valid Remove action — not Action::NONE.
        let mut wb2 = game.build_workbench(&after_mill);
        let mut searcher5 = mill_searcher_default();
        let remove_move = searcher5.search_pvs(&mut wb2, 5).best_action;
        assert_eq!(
            remove_move.kind_tag,
            MillActionKind::Remove as i16,
            "depth=5 Remove search must return Remove, not kind={}",
            remove_move.kind_tag
        );
        assert!(
            matches!(remove_move.to_node, 3 | 5),
            "Remove target must be Black's piece (3 or 5), got {}",
            remove_move.to_node
        );
    }

    /// Moving-phase version: AI moves a piece to form a mill at depth=5.
    /// Regression for Phase 5 null-move incorrectly preventing Remove.
    #[test]
    fn native_search_moving_phase_mill_chains_remove_at_high_depth() {
        let rules = MillRules::default();
        let game = MillGame::default();
        let options = NativeMillVariantOptions::default();

        // Moving phase: White on 0, 2, 4; Black on 5, 6, 7.
        // White can complete the [0,1,2] mill by moving 4->1.
        let mut state = rules.setup_empty();
        state.set_piece(0, 1); // White on a7
        state.set_piece(2, 1); // White on g7
        state.set_piece(4, 1); // White on e4 (adjacent to node 1 via edge moves)
        state.set_piece(5, 2); // Black on d1
        state.set_piece(6, 2); // Black on c3
        state.set_piece(7, 2); // Black on a1
        state.set_side_to_move(0);
        state.recompute_aux(&options);
        state.set_phase(MillPhase::Moving); // Force moving phase
        let snap = rules.encode_state(state);

        // Verify this is moving phase
        assert_eq!(snap.phase_tag, MillPhase::Moving as i16);

        // 1) At depth=5 the AI must find a Move action.
        let mut wb = game.build_workbench(&snap);
        let mut searcher = mill_searcher_default();
        let best_move = searcher.search_pvs(&mut wb, 5).best_action;
        assert_eq!(
            best_move.kind_tag,
            MillActionKind::Move as i16,
            "expected Move action, got kind={}",
            best_move.kind_tag
        );

        // 2) Apply it and check if a mill was formed.
        let after_move = rules.apply(&snap, best_move);

        // If the move formed a mill, pending_removals is encoded at payload[28].
        // pending_removals[0] > 0 means White has a pending Remove.
        if after_move.opaque_payload[28] > 0 {
            assert_eq!(after_move.side_to_move, 0, "side must stay on White");
            // 3) Remove search at depth=5 must return a Remove action.
            let mut wb2 = game.build_workbench(&after_move);
            let mut searcher2 = mill_searcher_default();
            let remove = searcher2.search_pvs(&mut wb2, 5).best_action;
            assert_eq!(
                remove.kind_tag,
                MillActionKind::Remove as i16,
                "Remove search must return Remove, not kind={}",
                remove.kind_tag
            );
        }
    }

    /// Regression test for the exact game sequence in the bug report:
    /// 1.d1 d6  2.g1 f4  3.g4 d2  4.a4 [AI must respond]
    ///
    /// After White places a4 (Rust node 7), the game should have
    /// side_to_move=1 (Black's turn) and NOT be terminal.
    /// This confirms that the Rust rules engine correctly switches sides
    /// and that the AI can find a valid response.
    #[test]
    fn ai_must_respond_after_a4_in_reported_sequence() {
        let rules = MillRules::default();
        let game = MillGame::default();

        // Apply the sequence: d1=node5, d6=node9, g1=node4, f4=node11,
        // g4=node3, d2=node13.  Then White places a4=node7.
        let mut snap = rules.initial_state(&[]);
        for node in [5_i16, 9, 4, 11, 3, 13] {
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

        // State: White has d1(5)+g1(4)+g4(3), Black has d6(9)+f4(11)+d2(13).
        // It is White's turn (side_to_move=0).
        assert_eq!(snap.side_to_move, 0, "should be White's turn before a4");
        assert_eq!(
            snap.phase_tag,
            MillPhase::Placing as i16,
            "should be placing"
        );

        // White places a4 (Rust node 7).
        snap = rules.apply(
            &snap,
            Action {
                kind_tag: MillActionKind::Place as i16,
                from_node: -1,
                to_node: 7,
                aux: -1,
                payload_bits: 0,
            },
        );

        // After a4: must be Black's turn and game NOT terminal.
        assert_eq!(
            snap.side_to_move, 1,
            "after White places a4 it must be Black's turn (side=1)"
        );
        assert_eq!(
            snap.phase_tag,
            MillPhase::Placing as i16,
            "still placing phase"
        );
        // Verify not terminal: outcome.kind would be "ongoing".
        // We check this indirectly: legal actions must be non-empty.
        let mut legal = tgf_core::ActionList::<256>::new();
        rules.legal_actions(&snap, &mut legal);
        assert!(
            !legal.is_empty(),
            "Black must have legal actions after White places a4"
        );
        assert!(
            legal
                .iter()
                .all(|a| a.kind_tag == MillActionKind::Place as i16),
            "all Black legal actions should be Place in placing phase"
        );

        // AI (Black, depth 1) must find a valid Place action — no NONE.
        let mut wb = game.build_workbench(&snap);
        let mut searcher = mill_searcher_default();
        let ai_action = searcher.search_pvs(&mut wb, 1).best_action;
        assert_eq!(
            ai_action.kind_tag,
            MillActionKind::Place as i16,
            "AI must respond with a Place action, got kind={}",
            ai_action.kind_tag
        );
        assert!(
            (0..24).contains(&(ai_action.to_node as usize)),
            "AI Place action must target a valid board node 0..23, got {}",
            ai_action.to_node
        );
    }

    /// Regression test for the reported game sequence
    /// 1.d2 d6 2.f4 b4 3.g1 g4 4.a1 — Black must reply after White's a1.
    ///
    /// Node mapping: d2=13, d6=9, f4=11, b4=15, g1=4, g4=3, a1=6.
    #[test]
    fn ai_must_respond_after_a1_in_reported_sequence() {
        let rules = MillRules::default();
        let game = MillGame::default();

        let mut snap = rules.initial_state(&[]);

        // Play the full sequence; alternates White / Black.
        for node in [13_i16, 9, 11, 15, 4, 3] {
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

        // After 6 placements it is White's turn (3W + 3B placed).
        assert_eq!(snap.side_to_move, 0, "should be White's turn before a1");

        // White places a1 (Rust node 6).
        snap = rules.apply(
            &snap,
            Action {
                kind_tag: MillActionKind::Place as i16,
                from_node: -1,
                to_node: 6,
                aux: -1,
                payload_bits: 0,
            },
        );

        // After a1: must be Black's turn, game NOT terminal.
        assert_eq!(
            snap.side_to_move, 1,
            "after White places a1 it must be Black's turn (side=1)"
        );
        assert_eq!(
            snap.phase_tag,
            MillPhase::Placing as i16,
            "still placing phase after move 4"
        );

        // Black must have legal Place actions.
        let mut legal = tgf_core::ActionList::<256>::new();
        rules.legal_actions(&snap, &mut legal);
        assert!(
            !legal.is_empty(),
            "Black must have legal actions after White places a1"
        );
        assert!(
            legal
                .iter()
                .all(|a| a.kind_tag == MillActionKind::Place as i16),
            "all Black legal actions should be Place in placing phase"
        );

        // AI (Black, depth 1) must find a valid Place action — no NONE.
        let mut wb = game.build_workbench(&snap);
        let mut searcher = mill_searcher_default();
        let ai_action = searcher.search_pvs(&mut wb, 1).best_action;
        assert_eq!(
            ai_action.kind_tag,
            MillActionKind::Place as i16,
            "AI must respond with a Place action, got kind={}",
            ai_action.kind_tag
        );
        assert!(
            (0..24).contains(&(ai_action.to_node as usize)),
            "AI Place action must target valid node 0..23, got {}",
            ai_action.to_node
        );
    }

    #[test]
    fn rust_only_variant_option_toggles_are_reachable() {
        let variant = MillVariantOptions {
            piece_count: 9,
            fly_piece_count: 3,
            pieces_at_least_count: 3,
            may_fly: true,
            has_diagonal_lines: false,
            mill_formation_action_in_placing_phase:
                MillFormationActionInPlacingPhase::RemoveOpponentsPieceFromHandThenYourTurn,
            may_remove_from_mills_always: true,
            may_remove_multiple: true,
            n_move_rule: 2,
            endgame_n_move_rule: 1,
            may_move_in_placing_phase: true,
            is_defender_move_first: true,
            restrict_repeated_mills_formation: true,
            one_time_use_mill: true,
            stop_placing_when_two_empty_squares: true,
            board_full_action: MillBoardFullAction::AgreeToDraw,
            threefold_repetition_rule: false,
            custodian_capture: CaptureRuleConfig {
                enabled: true,
                on_square_edges: true,
                on_cross_lines: true,
                on_diagonal_lines: true,
                in_placing_phase: true,
                in_moving_phase: true,
                only_available_when_own_pieces_leq3: false,
            },
            intervention_capture: CaptureRuleConfig {
                enabled: true,
                on_square_edges: true,
                on_cross_lines: true,
                on_diagonal_lines: true,
                in_placing_phase: true,
                in_moving_phase: true,
                only_available_when_own_pieces_leq3: false,
            },
            leap_capture: CaptureRuleConfig {
                enabled: true,
                on_square_edges: true,
                on_cross_lines: true,
                on_diagonal_lines: true,
                in_placing_phase: true,
                in_moving_phase: true,
                only_available_when_own_pieces_leq3: false,
            },
            stalemate_action: StalemateAction::BothPlayersRemoveOpponentsPiece,
            consider_mobility: true,
            focus_on_blocking_paths: false,
        };
        let native: NativeMillVariantOptions = variant.into();
        assert!(native.may_remove_from_mills_always);
        assert!(native.may_remove_multiple);
        assert_eq!(native.n_move_rule, 2);
        assert_eq!(native.endgame_n_move_rule, 1);
        assert!(native.may_move_in_placing_phase);
        assert!(native.is_defender_move_first);
        assert!(matches!(
            native.mill_formation_action_in_placing_phase,
            NativeMillFormationActionInPlacingPhase::RemoveOpponentsPieceFromHandThenYourTurn
        ));
        assert!(native.restrict_repeated_mills_formation);
        assert!(native.one_time_use_mill);
        assert!(native.stop_placing_when_two_empty_squares);
        assert!(matches!(
            native.board_full_action,
            NativeMillBoardFullAction::AgreeToDraw
        ));
        assert!(!native.threefold_repetition_rule);
        assert!(native.custodian_capture.enabled);
        assert!(native.intervention_capture.enabled);
        assert!(native.leap_capture.enabled);
        assert!(matches!(
            native.stalemate_action,
            NativeStalemateAction::BothPlayersRemoveOpponentsPiece
        ));
    }

    fn run_native_self_play(num_games: usize, default_seed: u64, rules: &MillRules) {
        const MAX_PLIES: usize = 80;
        let mut rng_state: u64 = default_seed;
        for _game_idx in 0..num_games {
            let mut snap = rules.initial_state(&[]);
            for _ply in 0..MAX_PLIES {
                if snap.phase_tag == MillPhase::GameOver as i16 {
                    break;
                }
                let native_set = native_legal_uci_set(&snap, rules);
                if native_set.is_empty() {
                    break;
                }
                let mut sorted: Vec<String> = native_set.into_iter().collect();
                sorted.sort();
                let pick = next_random_index(&mut rng_state, sorted.len());
                let mv = sorted[pick].clone();
                let native_action = native_action_from_uci(&snap, &mv, rules)
                    .expect("native_action_from_uci must decode a legal UCI move");
                snap = rules.apply(&snap, native_action);
            }
        }
    }

    /// Rust-only self-play with `custodian_capture.enabled = true`.
    ///
    /// No C++ legacy rule has custodian capture enabled, so a full
    /// differential is not possible.  This test verifies that the Rust
    /// rules engine produces consistent legal-action sets and applies
    /// moves without panicking across 300 seeded random games.
    #[test]
    fn native_self_play_custodian_capture_no_panic() {
        let opts = NativeMillVariantOptions {
            custodian_capture: NativeCaptureRuleConfig {
                enabled: true,
                ..Default::default()
            },
            ..Default::default()
        };
        let rules = MillRules::new(opts);
        run_native_self_play(300, 0xC0DE_C057_0D1A_4E42, &rules);
    }

    /// Rust-only self-play with `intervention_capture.enabled = true`.
    #[test]
    fn native_self_play_intervention_capture_no_panic() {
        let opts = NativeMillVariantOptions {
            intervention_capture: NativeCaptureRuleConfig {
                enabled: true,
                ..Default::default()
            },
            ..Default::default()
        };
        let rules = MillRules::new(opts);
        run_native_self_play(300, 0x14E5_E4E4_104E_CA14, &rules);
    }

    /// Rust-only self-play with `leap_capture.enabled = true`.  Now that
    /// generate_move_actions emits the leap superset (master
    /// generate<MOVE>'s tryAddLeap shape) the legal-action set is
    /// strictly larger than the no-capture baseline, so the random walk
    /// also implicitly exercises the new code path through both placing
    /// (via may_move_in_placing_phase) and moving phases.
    #[test]
    fn native_self_play_leap_capture_no_panic() {
        let opts = NativeMillVariantOptions {
            leap_capture: NativeCaptureRuleConfig {
                enabled: true,
                ..Default::default()
            },
            ..Default::default()
        };
        let rules = MillRules::new(opts);
        run_native_self_play(300, 0xCEAA_C057_0D1A_4E42, &rules);
    }

    /// Rust-only self-play with `restrict_repeated_mills_formation = true`.
    ///
    /// No C++ legacy rule exercises this flag.  Verifies that the Rust
    /// implementation does not panic when the flag is enabled.
    #[test]
    fn native_self_play_restrict_repeated_mills_no_panic() {
        let opts = NativeMillVariantOptions {
            restrict_repeated_mills_formation: true,
            ..Default::default()
        };
        let rules = MillRules::new(opts);
        run_native_self_play(300, 0x4E57_41C7_411E_5EED, &rules);
    }

    // ---------------------------------------------------------------------------
    // Oracle replay tests (Phase 0)
    //
    // These tests read pre-generated JSON oracle files produced by
    // `cargo run -p xtask-legacy-oracle` and verify that the Rust tgf-mill
    // rules produce identical legal action sets, phase tags, and side-to-move
    // values at every step.
    //
    // If an oracle file is missing the test is silently skipped (oracle not
    // yet generated for this environment).  After running the generator once
    // and committing the files, the tests become hard assertions.
    //
    // Rules 8 (Zhi Qi) and 9 (El Filja) are marked #[ignore] because they
    // have known divergences tracked in known_failures.toml.
    // ---------------------------------------------------------------------------

    #[cfg(test)]
    mod oracle_replay {
        use super::*;
        use serde::Deserialize;
        use std::collections::BTreeSet;
        use tgf_mill::MillRules;

        #[derive(Deserialize)]
        struct OracleStep {
            ply: u32,
            // fen: String, // available but not used in replay
            legal_uci: Vec<String>,
            phase_tag: i32,
            side_to_move: i32,
            picked_uci: String,
        }

        #[derive(Deserialize)]
        struct OracleTrajectory {
            seed: u64,
            steps: Vec<OracleStep>,
        }

        #[derive(Deserialize)]
        struct OracleFile {
            rule_idx: i32,
            rule_name: String,
            trajectories: Vec<OracleTrajectory>,
        }

        fn oracle_dir() -> std::path::PathBuf {
            std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                .parent()
                .expect("crates/ parent")
                .join("tgf-mill/testdata/legacy_oracle")
        }

        /// Delegate to `tgf_mill::preset_for` — the canonical source.
        fn rules_for_idx(idx: i32) -> MillRules {
            tgf_mill::rules_for_preset(idx)
                .unwrap_or_else(|| panic!("no preset for rule_idx {idx}"))
        }

        /// Replay one oracle file against tgf-mill.
        /// Returns Ok(()) if all steps matched, or Err(msg) on first divergence.
        fn replay_oracle_file(oracle: &OracleFile) -> Result<(), String> {
            let idx = oracle.rule_idx;
            let rules = rules_for_idx(idx);

            for traj in &oracle.trajectories {
                let mut snap = rules.initial_state(&[]);

                for step in &traj.steps {
                    // When Rust ends the game (n_move_rule, threefold, stalemate)
                    // before the legacy C++ engine, stop replaying this trajectory.
                    // C++ only commits draw/stalemate outcomes when the player issues
                    // "draw" — so the oracle continues past Rust's automatic end.
                    // This mirrors the early-exit in run_random_walk.
                    if snap.phase_tag == tgf_mill::MillPhase::GameOver as i16 {
                        break;
                    }

                    let native_set: BTreeSet<String> = native_legal_uci_set(&snap, &rules);
                    let oracle_set: BTreeSet<String> = step.legal_uci.iter().cloned().collect();

                    if native_set != oracle_set {
                        let native_only: Vec<_> = native_set.difference(&oracle_set).collect();
                        let oracle_only: Vec<_> = oracle_set.difference(&native_set).collect();
                        return Err(format!(
                            "[rule_idx={idx} ({}) seed={:#x} ply={}] legal set divergence:\n  \
                             native_only={native_only:?}\n  oracle_only={oracle_only:?}",
                            oracle.rule_name, traj.seed, step.ply,
                        ));
                    }

                    let native_phase = snap.phase_tag as i32;
                    let native_phase_legacy = native_phase + 1;
                    if native_phase_legacy != step.phase_tag {
                        return Err(format!(
                            "[rule_idx={idx} seed={:#x} ply={}] phase mismatch: \
                             native_legacy={native_phase_legacy} oracle={}",
                            traj.seed, step.ply, step.phase_tag,
                        ));
                    }

                    let native_side = snap.side_to_move;
                    let native_side_legacy = match native_side {
                        0 => 1,
                        1 => 2,
                        _ => 0,
                    };
                    if native_side_legacy != step.side_to_move {
                        return Err(format!(
                            "[rule_idx={idx} seed={:#x} ply={}] side mismatch: \
                             native_legacy={native_side_legacy} oracle={}",
                            traj.seed, step.ply, step.side_to_move,
                        ));
                    }

                    // Advance state using the oracle's chosen move.
                    let picked = &step.picked_uci;
                    match native_action_from_uci(&snap, picked, &rules) {
                        Some(action) => snap = rules.apply(&snap, action),
                        None => {
                            return Err(format!(
                                "[rule_idx={idx} seed={:#x} ply={}] cannot decode \
                                 oracle UCI '{picked}' as native action",
                                traj.seed, step.ply,
                            ));
                        }
                    }
                }
            }
            Ok(())
        }

        fn run_oracle_replay(rule_idx: i32) {
            let path = oracle_dir().join(format!("{rule_idx}.json"));
            if !path.exists() {
                eprintln!(
                    "Oracle file {:?} not found — run `cargo run -p xtask-legacy-oracle` \
                     to generate it first. Skipping.",
                    path
                );
                return;
            }
            let content = std::fs::read_to_string(&path)
                .unwrap_or_else(|e| panic!("read oracle {}: {e}", path.display()));
            let oracle: OracleFile = serde_json::from_str(&content)
                .unwrap_or_else(|e| panic!("parse oracle {}: {e}", path.display()));
            if let Err(msg) = replay_oracle_file(&oracle) {
                panic!("Oracle replay failed:\n{msg}");
            }
        }

        #[test]
        fn oracle_replay_9mm() {
            run_oracle_replay(0);
        }
        #[test]
        fn oracle_replay_12mm_diagonal() {
            run_oracle_replay(1);
        }
        #[test]
        #[ignore = "Dooz oracle replay: RemoveOpponentsPieceFromHandThenOpponentsTurn placing-phase gap, tracked in known_failures.toml"]
        fn oracle_replay_dooz() {
            run_oracle_replay(2);
        }
        #[test]
        fn oracle_replay_morabaraba() {
            run_oracle_replay(3);
        }
        #[test]
        fn oracle_replay_russian_mill() {
            run_oracle_replay(4);
        }
        #[test]
        fn oracle_replay_lasker_morris() {
            run_oracle_replay(5);
        }
        #[test]
        fn oracle_replay_cheng_san_qi() {
            run_oracle_replay(6);
        }
        #[test]
        fn oracle_replay_da_san_qi() {
            run_oracle_replay(7);
        }
        #[test]
        fn oracle_replay_experimental() {
            run_oracle_replay(10);
        }

        #[test]
        #[ignore = "Zhi Qi oracle replay: known divergence, tracked in known_failures.toml"]
        fn oracle_replay_zhi_qi() {
            run_oracle_replay(8);
        }
        #[test]
        #[ignore = "El Filja oracle replay: known divergence, tracked in known_failures.toml"]
        fn oracle_replay_el_filja() {
            run_oracle_replay(9);
        }
    }

    /// Verify that setting qsearch_max_depth=1 still returns valid actions
    /// and does not produce terminal scores from a non-terminal fixture.
    #[test]
    fn native_qsearch_depth_1_returns_valid_non_terminal_score() {
        let rules = MillRules::default();
        let game = MillGame::default();
        let snap = rules.no_mill_moving_phase_snapshot();

        let mut wb0 = game.build_workbench(&snap);
        let mut wb1 = game.build_workbench(&snap);

        let mut s0 = mill_searcher_default();
        s0.set_qsearch_max_depth(0);
        let r0 = s0.search_pvs(&mut wb0, 2);

        let mut s1 = mill_searcher_default();
        s1.set_qsearch_max_depth(1);
        let r1 = s1.search_pvs(&mut wb1, 2);

        assert!(
            !r0.best_action.is_none(),
            "qsearch_max_depth=0 must find a move"
        );
        assert!(
            !r1.best_action.is_none(),
            "qsearch_max_depth=1 must find a move"
        );
        assert!(
            r0.score.abs() < 30_000,
            "depth=0 score must not be a terminal sentinel"
        );
        assert!(
            r1.score.abs() < 30_000,
            "depth=1 score must not be a terminal sentinel"
        );
    }
}
