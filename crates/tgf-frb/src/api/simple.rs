// SPDX-License-Identifier: GPL-3.0-or-later
// tgf-frb – public FRB API surface.
//
// Conventions:
//   - `#[flutter_rust_bridge::frb(sync)]` makes the call synchronous on the
//     Dart side (no Future wrapping); use only for cheap, non-blocking calls.
//   - All public functions in this module are auto-exported to Dart by codegen.
//
// The DTOs and entry points stay in this file so the generated Dart paths
// (`lib/src/rust/api/simple.dart`) remain stable.  The implementation
// behind every Mill-specific entry point lives in `crate::games::mill::*`
// so this file no longer carries Mill-specific search/codec details.

use crate::frb_generated::StreamSink;
use tgf_core::{Action, ActionList, BoardTopology, Game, GameRules};
use tgf_mill::{
    default_mill_topology, CaptureRuleConfig as NativeCaptureRuleConfig, MillActionKind,
    MillBoardFullAction as NativeMillBoardFullAction,
    MillFormationActionInPlacingPhase as NativeMillFormationActionInPlacingPhase, MillGame,
    MillRules, MillVariantOptions as NativeMillVariantOptions,
    StalemateAction as NativeStalemateAction,
};
use tgf_search::{MctsOptions, MctsSearcher, SearchOptions};

use crate::games::mill::search::{
    mcts_move_order_context, mill_searcher_default, request_abort_active_search,
    spawn_mill_engine_config_event_stream as spawn_mill_engine_config_event_stream_internal,
    spawn_mill_pvs_event_stream as spawn_mill_pvs_event_stream_internal, MillAlgorithmInternal,
    MillEngineConfigInternal,
};

// Re-export the game-neutral error helper so `crate::api::kernel` can keep
// its existing import path.
pub(crate) use crate::engine_event::spawn_kernel_search_error;

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
    crate::games::othello::initial_legal_count()
}

/// Run the generic Rust Searcher<OthelloGame> for one ply and return the
/// selected destination node.
#[flutter_rust_bridge::frb(sync)]
pub fn native_othello_search_depth_one_best_to_node() -> i32 {
    crate::games::othello::search_depth_one_best_to_node()
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

impl From<MillSearchAlgorithm> for MillAlgorithmInternal {
    fn from(alg: MillSearchAlgorithm) -> Self {
        match alg {
            MillSearchAlgorithm::AlphaBeta => MillAlgorithmInternal::AlphaBeta,
            MillSearchAlgorithm::Pvs => MillAlgorithmInternal::Pvs,
            MillSearchAlgorithm::Mtdf => MillAlgorithmInternal::Mtdf,
            MillSearchAlgorithm::Mcts => MillAlgorithmInternal::Mcts,
            MillSearchAlgorithm::Random => MillAlgorithmInternal::Random,
        }
    }
}

impl From<MillEngineConfig> for MillEngineConfigInternal {
    fn from(cfg: MillEngineConfig) -> Self {
        Self {
            algorithm: cfg.algorithm.into(),
            depth: cfg.depth,
            move_time_ms: cfg.move_time_ms,
            ai_is_lazy: cfg.ai_is_lazy,
            last_best_value: cfg.last_best_value,
            skill_level: cfg.skill_level,
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

/// Game-neutral engine event POD shipped over the FRB stream API.
///
/// This struct is the wire format Dart sees; the helper constructors and
/// spawn-and-emit logic live in `crate::engine_event` and
/// `crate::games::*` respectively so this module stays a thin ABI shim.
#[derive(Clone, Debug)]
pub struct EngineEvent {
    pub kind: String,
    pub depth: i32,
    pub score: i32,
    pub nodes: u64,
    pub to_node: i32,
    /// For bestMove events: the full notation move string ("a4", "a1-a4",
    /// "xa4" for Mill) plus auxiliary annotations such as `rawScore=N`.
    /// For error events: the human-readable error message.  The Dart side
    /// parses this loosely; new fields ride along here to avoid codegen.
    pub reason: String,
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
            move_order_context: mcts_move_order_context(1),
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
        depth_extension: true,
        node_limit: None,
        time_limit_ms: Some(0),
        allow_null_move: true,
        ..Default::default()
    });
    let _ = searcher.search(&mut wb, 3);
    searcher.was_aborted()
}

/// Runs PVS on the given Mill snapshot and streams engine events.  This
/// is a thin shim that delegates to the Mill-specific search dispatcher in
/// `crate::games::mill::search` so this module does not carry any
/// Mill-internal state.
pub(crate) fn spawn_mill_pvs_event_stream(
    snapshot: tgf_core::GameStateSnapshot,
    options: NativeMillVariantOptions,
    depth: i32,
    sink: StreamSink<EngineEvent>,
) {
    spawn_mill_pvs_event_stream_internal(snapshot, options, depth, sink);
}

/// Launch a search thread using the full `MillEngineConfig`.  Emits one
/// `info` event per IDS depth, then a final `bestMove` + `stopped`.
/// Implementation lives in `crate::games::mill::search`.
pub(crate) fn spawn_mill_engine_config_event_stream(
    snapshot: tgf_core::GameStateSnapshot,
    options: NativeMillVariantOptions,
    config: MillEngineConfig,
    sink: StreamSink<EngineEvent>,
) {
    let internal_cfg: MillEngineConfigInternal = config.into();
    spawn_mill_engine_config_event_stream_internal(snapshot, options, internal_cfg, sink);
}

/// Async search event stream rooted at the Mill initial position.
///
/// Spawns a worker thread, runs the native Rust `Searcher<MillGame>`, and
/// emits Ready / Info / BestMove / Stopped.  Used as a smoke-check entry
/// point during development; production paths go through
/// `tgf_kernel_mill_search_events*` instead.
pub fn native_mill_search_events(depth: i32, sink: StreamSink<EngineEvent>) {
    let rules = MillRules::default();
    let snap = rules.initial_state(&[]);
    spawn_mill_pvs_event_stream_internal(snap, NativeMillVariantOptions::default(), depth, sink);
}

/// Request that the currently running native Rust search stops.
///
/// Returns false when no native search worker is active.
#[flutter_rust_bridge::frb(sync)]
pub fn native_mill_search_stop() -> bool {
    request_abort_active_search()
}

#[cfg(test)]
#[path = "simple_tests.rs"]
mod tests;
