// SPDX-License-Identifier: AGPL-3.0-or-later
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
    CaptureRuleConfig as NativeCaptureRuleConfig, MillActionKind,
    MillBoardFullAction as NativeMillBoardFullAction,
    MillFormationActionInPlacingPhase as NativeMillFormationActionInPlacingPhase, MillGame,
    MillRules, MillVariantOptions as NativeMillVariantOptions,
    StalemateAction as NativeStalemateAction, default_mill_topology,
};
use tgf_search::{MctsOptions, MctsSearcher, SearchOptions};

use tgf_mill::MillSearchAlgorithmKind;

use crate::games::mill::human_db as mill_human_db;
use crate::games::mill::perfect as mill_perfect;
use crate::games::mill::search::{
    MillEngineConfigPlan, mcts_move_order_context, mill_searcher_default,
    request_abort_active_search,
    spawn_mill_engine_config_event_stream as spawn_mill_engine_config_event_stream_internal,
    spawn_mill_pvs_event_stream as spawn_mill_pvs_event_stream_internal,
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
// Bridge smoke-check APIs.
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

/// Public FRB DTO for Mill variant options. It mirrors
/// `tgf_mill::rules::MillVariantOptions`; new rule flags should be added here
/// whenever the Rust rules crate grows them.
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
// Othello pressure-test APIs.
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
// Rust-native Mill topology exposed through FRB.
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
    /// Per-game edge classification (see `tgf_core::Edge::kind_tag`).
    /// `0` = default/generic.  Used by games with multi-modal edges
    /// (军棋: railroad vs ordinary connections).
    pub kind_tag: u16,
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

impl From<MillSearchAlgorithm> for MillSearchAlgorithmKind {
    fn from(alg: MillSearchAlgorithm) -> Self {
        match alg {
            MillSearchAlgorithm::AlphaBeta => MillSearchAlgorithmKind::AlphaBeta,
            MillSearchAlgorithm::Pvs => MillSearchAlgorithmKind::Pvs,
            MillSearchAlgorithm::Mtdf => MillSearchAlgorithmKind::Mtdf,
            MillSearchAlgorithm::Mcts => MillSearchAlgorithmKind::Mcts,
            MillSearchAlgorithm::Random => MillSearchAlgorithmKind::Random,
        }
    }
}

impl From<MillEngineConfig> for MillEngineConfigPlan {
    fn from(cfg: MillEngineConfig) -> Self {
        Self {
            algorithm: cfg.algorithm.into(),
            depth: cfg.depth,
            move_time_ms: cfg.move_time_ms,
            ai_is_lazy: cfg.ai_is_lazy,
            last_best_value: cfg.last_best_value,
            skill_level: cfg.skill_level,
            use_perfect_database: cfg.use_perfect_database,
            shuffling: cfg.shuffling,
            use_lazy_smp: cfg.use_lazy_smp,
            engine_threads: cfg.engine_threads,
            multi_pv: cfg.multi_pv,
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
    /// When true, query the perfect database after search and prefer its move
    /// when the active rule variant has matching database assets.
    pub use_perfect_database: bool,
    /// When true, randomise the order of equally-ranked root moves so the AI
    /// does not always play the same line (master `Shuffling` UCI option).
    /// Flutter forwards `GeneralSettings.shufflingEnabled`; disable for
    /// deterministic play.  Also drives the per-rollout move ordering in the
    /// MCTS path.
    pub shuffling: bool,
    /// Enable multi-threaded native search where supported.  Multi-threading is
    /// ignored when `shuffling` is false so deterministic play still returns a
    /// stable best move for a fixed position.
    pub use_lazy_smp: bool,
    /// Requested worker/thread count for multi-threaded search.  The engine
    /// clamps the value to a conservative range.
    pub engine_threads: u32,
    /// Requested MultiPV line count.  `1` keeps the legacy stream shape and
    /// avoids extra work; values greater than one ask the engine to emit
    /// additional root candidate events when the selected search path already
    /// has root move summaries available.
    pub multi_pv: u8,
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
            use_perfect_database: false,
            shuffling: true,
            use_lazy_smp: false,
            engine_threads: 4,
            multi_pv: 1,
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

/// Availability summary for one Perfect Database variant in a directory.
#[derive(Clone, Debug)]
pub struct MillPerfectDatabaseVariantStatus {
    /// Legacy database variant name: `std`, `lask`, or `mora`.
    pub name: String,
    /// Piece count associated with the variant.
    pub piece_count: u8,
    /// Number of sector ids listed by the `.secval` file.
    pub sector_count: u32,
    /// Number of listed sectors whose `.sec2` files are present.
    pub available_sector_count: u32,
}

/// Perfect Database directory status used for setup diagnostics.
#[derive(Clone, Debug)]
pub struct MillPerfectDatabaseStatus {
    /// Whether the directory could be read and parsed.
    pub readable: bool,
    /// Parse/read error message when `readable` is false; empty otherwise.
    pub error: String,
    /// Whether any supported `.secval` metadata was found.
    pub has_metadata: bool,
    /// Whether any supported variant has at least one available `.sec2` file.
    pub has_available_sectors: bool,
    /// Status for every supported variant found in the directory.
    pub variants: Vec<MillPerfectDatabaseVariantStatus>,
}

/// Initialize the Mill perfect database directory from `path`.
/// The directory may contain `std`, `lask`, and/or `mora` database files; the
/// active Mill rules select the concrete variant at query time.
#[flutter_rust_bridge::frb(sync)]
pub fn mill_perfect_db_init(path: String) -> bool {
    mill_perfect::init_database_path(path)
}

/// Inspect the Mill perfect database directory without initializing it.
#[flutter_rust_bridge::frb(sync)]
pub fn mill_perfect_db_status(path: String) -> MillPerfectDatabaseStatus {
    #[cfg(target_arch = "wasm32")]
    {
        let _ = path;
        return MillPerfectDatabaseStatus {
            readable: false,
            error: "Perfect Database is not available on Web".to_owned(),
            has_metadata: false,
            has_available_sectors: false,
            variants: Vec::new(),
        };
    }

    #[cfg(not(target_arch = "wasm32"))]
    match perfect_db::supported_variants(&path) {
        Ok(supported) => {
            let variants = supported
                .iter()
                .map(|supported| MillPerfectDatabaseVariantStatus {
                    name: supported.variant.name.to_owned(),
                    piece_count: supported.variant.piece_count,
                    sector_count: supported.sector_count() as u32,
                    available_sector_count: supported.available_sector_count() as u32,
                })
                .collect::<Vec<_>>();
            MillPerfectDatabaseStatus {
                readable: true,
                error: String::new(),
                has_metadata: !supported.is_empty(),
                has_available_sectors: variants
                    .iter()
                    .any(|variant| variant.available_sector_count > 0),
                variants,
            }
        }
        Err(err) => MillPerfectDatabaseStatus {
            readable: false,
            error: err.to_string(),
            has_metadata: false,
            has_available_sectors: false,
            variants: Vec::new(),
        },
    }
}

/// Release perfect-database resources for the current process.
#[flutter_rust_bridge::frb(sync)]
pub fn mill_perfect_db_deinit() {
    mill_perfect::deinit_database();
}

/// Runtime status for an optional human-game SQLite database.
#[derive(Clone, Debug)]
pub struct MillHumanDatabaseStatus {
    /// Whether the SQLite file could be opened and passed schema checks.
    pub readable: bool,
    /// Whether this exact file is currently initialized for queries.
    pub initialized: bool,
    /// Read/schema error when `readable` is false; empty otherwise.
    pub error: String,
    /// Source database schema version from the metadata table.
    pub schema_version: String,
    /// Source database build date from the metadata table.
    pub build_date: String,
    /// Number of games indexed by the database builder.
    pub total_games: u32,
    /// Number of indexed canonical positions.
    pub position_count: u32,
    /// Number of indexed move rows.
    pub move_count: u32,
}

impl From<mill_human_db::HumanDatabaseStatus> for MillHumanDatabaseStatus {
    fn from(value: mill_human_db::HumanDatabaseStatus) -> Self {
        Self {
            readable: value.readable,
            initialized: value.initialized,
            error: value.error,
            schema_version: value.schema_version,
            build_date: value.build_date,
            total_games: value.total_games,
            position_count: value.position_count,
            move_count: value.move_count,
        }
    }
}

/// One Human Database move candidate mapped back into the current board orientation.
#[derive(Clone, Debug)]
pub struct MillHumanDatabaseMove {
    /// Move notation (`"a4"`, `"a1-a4"`, or complete `"a4xb6"`).
    pub notation: String,
    pub wins: u32,
    pub losses: u32,
    pub draws: u32,
    pub total: u32,
    /// Raw human-game win percentage for the side to move.
    pub win_pct: f64,
    /// Confidence-weighted delta in the range [-0.5, 0.5].
    pub score_delta: f64,
}

impl From<mill_human_db::HumanDatabaseMove> for MillHumanDatabaseMove {
    fn from(value: mill_human_db::HumanDatabaseMove) -> Self {
        Self {
            notation: value.notation,
            wins: value.wins,
            losses: value.losses,
            draws: value.draws,
            total: value.total,
            win_pct: value.win_pct,
            score_delta: value.score_delta,
        }
    }
}

/// Human Database query result for the current Mill FEN.
#[derive(Clone, Debug)]
pub struct MillHumanDatabaseQuery {
    pub available: bool,
    pub state_key: String,
    pub error: String,
    pub moves: Vec<MillHumanDatabaseMove>,
}

impl From<mill_human_db::HumanDatabaseQuery> for MillHumanDatabaseQuery {
    fn from(value: mill_human_db::HumanDatabaseQuery) -> Self {
        Self {
            available: value.available,
            state_key: value.state_key,
            error: value.error,
            moves: value.moves.into_iter().map(Into::into).collect(),
        }
    }
}

/// Initialize a read-only human-game SQLite database.
#[flutter_rust_bridge::frb(sync)]
pub fn mill_human_db_init(path: String) -> bool {
    mill_human_db::init_database_path(path)
}

/// Inspect a human-game SQLite database without requiring a query.
#[flutter_rust_bridge::frb(sync)]
pub fn mill_human_db_status(path: String) -> MillHumanDatabaseStatus {
    mill_human_db::database_status(path).into()
}

/// Query candidate moves for a Mill FEN from the initialized Human Database.
#[flutter_rust_bridge::frb(sync)]
pub fn mill_human_db_query(
    fen: String,
    max_moves: u32,
    min_samples: u32,
) -> MillHumanDatabaseQuery {
    mill_human_db::query_moves(fen, max_moves, min_samples).into()
}

/// Release Human Database resources for the current process.
#[flutter_rust_bridge::frb(sync)]
pub fn mill_human_db_deinit() {
    mill_human_db::deinit_database();
}

/// Status of the loaded lightweight "error patch" file (see
/// `docs/` mining-pipeline design notes). Unlike the Perfect Database this
/// file is small enough to bundle as a Flutter asset and never touches the
/// multi-gigabyte `.sec2` sector files it was mined from.
#[derive(Clone, Debug)]
pub struct MillPatchStatus {
    pub loaded: bool,
    pub entry_count: u32,
    pub error: String,
}

impl From<crate::games::mill::patch::PatchStatus> for MillPatchStatus {
    fn from(value: crate::games::mill::patch::PatchStatus) -> Self {
        Self {
            loaded: value.loaded,
            entry_count: value.entry_count,
            error: value.error,
        }
    }
}

/// Load a lightweight error-patch file from `path`. Returns `false` when the
/// file is missing, unreadable, or fails the format/engine-fingerprint
/// checks.
#[flutter_rust_bridge::frb(sync)]
pub fn mill_patch_init(path: String) -> bool {
    crate::games::mill::patch::init_patch_path(path)
}

/// Inspect the currently loaded patch, if any.
#[flutter_rust_bridge::frb(sync)]
pub fn mill_patch_status() -> MillPatchStatus {
    crate::games::mill::patch::patch_status().into()
}

/// Release the loaded patch's resources for the current process.
#[flutter_rust_bridge::frb(sync)]
pub fn mill_patch_deinit() {
    crate::games::mill::patch::deinit_patch();
}

/// Perfect-database verdict for one legal move, used by the analysis overlay.
///
/// `value` and `outcome` are expressed from the perspective of the side that
/// is to move in the analysed position (`"win"` / `"draw"` / `"loss"` and
/// `1` / `0` / `-1`).  `steps` is the distance-to-conversion step count, or a
/// negative value when the database does not expose one.
#[derive(Clone, Debug)]
pub struct MillMoveAnalysis {
    /// Mill UCI notation token (`"a4"`, `"a1-a4"`, `"xg7"`).
    pub mv: String,
    /// `"win"`, `"draw"` or `"loss"` for the analysing side.
    pub outcome: String,
    /// Win/draw/loss value for the analysing side (1 / 0 / -1).
    pub value: i32,
    /// Distance-to-conversion step count; negative when unavailable.
    pub steps: i32,
}

/// Full analysis result for a position: one verdict per legal move plus the
/// detected trap moves (empty unless trap detection ran and found any).
#[derive(Clone, Debug)]
pub struct MillAnalysisReport {
    /// One verdict per legal move.
    pub moves: Vec<MillMoveAnalysis>,
    /// Notation tokens of moves flagged as traps.
    pub traps: Vec<String>,
}

/// Return the Rust-native standard 24-point Mill topology.
///
/// This is the single source of truth for Mill board geometry.  The Dart
/// shell converts this blob into its existing BoardGeometry value object.
///
/// Generic callers that already hold a kernel handle should prefer
/// [`tgf_kernel_topology`] instead — it routes through the same
/// `BoardTopology` trait every game implements, so it works for
/// Othello / Checkers / future games without an extra entry point.
#[flutter_rust_bridge::frb(sync)]
pub fn native_mill_topology() -> TopologyBlob {
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
            kind_tag: edge.kind_tag,
        })
        .collect();
    TopologyBlob {
        name: topo.name().to_owned(),
        points,
        edges,
        line_groups: topo.line_groups().to_vec(),
    }
}

/// Backwards-compatible alias for [`native_mill_topology`].  Deprecated
/// because the name implies kernel awareness while the implementation
/// always returns the default Mill topology regardless of any kernel
/// state.  Will be removed one release after every Dart call site
/// migrates.
#[flutter_rust_bridge::frb(sync)]
pub fn kernel_topology() -> TopologyBlob {
    native_mill_topology()
}

/// Game-neutral topology accessor: routes the call through the kernel
/// session's `BoardTopology` so each game ships its own geometry
/// without needing a bespoke FRB entry.  The `square` field of every
/// emitted [`TopologyPoint`] mirrors the node id for games that have
/// no separate legacy square space (i.e. everything except Mill);
/// Mill's square space is exposed through [`native_mill_topology`].
#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_topology(handle: u32) -> Result<TopologyBlob, String> {
    crate::session_registry::with_kernel(handle, |kernel| {
        let topo = kernel.topology();
        let n = topo.node_count();
        let points: Vec<TopologyPoint> = (0..n)
            .map(|id| {
                let pt = topo.coordinate_of(id);
                TopologyPoint {
                    id,
                    square: id,
                    label: topo.label_of(id).to_owned(),
                    x: pt.x,
                    y: pt.y,
                }
            })
            .collect();
        let edges = topo
            .edges()
            .iter()
            .map(|edge| TopologyEdge {
                a: edge.a,
                b: edge.b,
                kind_tag: edge.kind_tag,
            })
            .collect();
        TopologyBlob {
            name: topo.name().to_owned(),
            points,
            edges,
            line_groups: topo.line_groups().to_vec(),
        }
    })
}

/// Multi-player metadata mirroring [`tgf_core::MultiPlayerInfo`] for
/// the FRB boundary.  Two-player games (Mill, Othello) emit
/// `player_count = 2` and the standard sequential turn order; team
/// games (军棋, Halma) populate `team_of` to advertise alliances so
/// the shell can render team UI / colour palettes accordingly.
#[derive(Clone, Debug)]
pub struct PlayerInfoBlob {
    pub player_count: u8,
    pub team_of: Vec<u8>,
    pub turn_order: Vec<u8>,
}

/// Game-neutral player-info accessor: routes the call through the
/// kernel session's `GameRules::multi_player_info` so each game ships
/// its own player layout without a bespoke FRB entry.  The shell uses
/// this to decide turn-order indicators, team colour palettes, and
/// `WinTeam` rendering paths at session start.
#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_player_info(handle: u32) -> Result<PlayerInfoBlob, String> {
    crate::session_registry::with_kernel(handle, |kernel| {
        let info = kernel.multi_player_info();
        let count = info.player_count as usize;
        PlayerInfoBlob {
            player_count: info.player_count,
            team_of: info.team_of[..count].to_vec(),
            turn_order: info.turn_order[..count].to_vec(),
        }
    })
}

// ---------------------------------------------------------------------------
// Native Rust Mill rules smoke APIs.
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
/// This is a small typed smoke-check for the native MillRules implementation.
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
/// destination node. This is a smoke-check for the monomorphised search path.
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

/// Run the Rust generic MCTS path and return the selected destination node.
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
            num_threads: Some(1),
            move_order_context: mcts_move_order_context(1, true),
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
    root_repetition_history: Vec<u64>,
    root_position_resets_repetition: bool,
    options: NativeMillVariantOptions,
    depth: i32,
    sink: StreamSink<EngineEvent>,
) {
    spawn_mill_pvs_event_stream_internal(
        snapshot,
        root_repetition_history,
        root_position_resets_repetition,
        options,
        depth,
        sink,
    );
}

/// Launch a search thread using the full `MillEngineConfig`.  Emits one
/// `info` event per IDS depth, then a final `bestMove` + `stopped`.
/// Implementation lives in `crate::games::mill::search`.
pub(crate) fn spawn_mill_engine_config_event_stream(
    snapshot: tgf_core::GameStateSnapshot,
    root_repetition_history: Vec<u64>,
    root_position_resets_repetition: bool,
    options: NativeMillVariantOptions,
    config: MillEngineConfig,
    sink: StreamSink<EngineEvent>,
) {
    let internal_cfg: MillEngineConfigPlan = config.into();
    spawn_mill_engine_config_event_stream_internal(
        snapshot,
        root_repetition_history,
        root_position_resets_repetition,
        options,
        internal_cfg,
        sink,
    );
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
    spawn_mill_pvs_event_stream_internal(
        snap,
        Vec::new(),
        false,
        NativeMillVariantOptions::default(),
        depth,
        sink,
    );
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
