// SPDX-License-Identifier: GPL-3.0-or-later
// Public Mill rule-variant types: action / phase / formation / capture
// enums plus the `MillVariantOptions` aggregate.  Hosting them in their
// own file keeps `rules/mod.rs` focused on the trait implementations.

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
pub(super) enum MillActionState {
    Place = 0,
    Select = 1,
    Remove = 2,
    GameOver = 3,
}

impl MillActionState {
    pub(super) fn from_fen_token(token: &str) -> Self {
        match token {
            "p" => Self::Place,
            "s" => Self::Select,
            "r" => Self::Remove,
            _ => Self::GameOver,
        }
    }

    pub(super) fn to_fen_token(self) -> char {
        match self {
            Self::Place => 'p',
            Self::Select => 's',
            Self::Remove => 'r',
            Self::GameOver => '?',
        }
    }

    pub(super) fn from_payload(value: u8) -> Self {
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

/// Tunable weights for the Mill static evaluator.
///
/// The defaults exactly match the hard-coded constants in the legacy master
/// engine, so the search tree and eval scores are bit-identical when weights
/// are left at their defaults. Tuned weights (produced by the offline
/// perfect-DB Texel tuner) can be injected without altering any other rule
/// behaviour, and are only applied to the standard variant by convention.
///
/// Fields:
/// - `piece_value`:  per-piece material weight (master: 5 = VALUE_EACH_PIECE)
/// - `mobility`:     weight on the mobility difference term (master: 1)
/// - `mill_count`:   weight on the mill-pieces-count difference term used in
///   the RemovalBasedOnMillCounts placing-phase variant (master: 1)
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct MillEvalWeights {
    pub piece_value: i32,
    pub mobility: i32,
    pub mill_count: i32,
}

impl MillEvalWeights {
    /// The legacy hard-coded weights.  Scores are identical to the
    /// pre-parameterisation evaluator when these are used.
    pub const LEGACY: Self = Self {
        piece_value: 5,
        mobility: 1,
        mill_count: 1,
    };
}

impl Default for MillEvalWeights {
    fn default() -> Self {
        Self::LEGACY
    }
}

impl MillEvalWeights {
    /// Read `TGF_EVAL_WEIGHTS=piece_value,mobility,mill_count` from the
    /// environment.  Returns `None` when the variable is unset so callers
    /// fall back to `MillEvalWeights::LEGACY` silently.  Panics with a
    /// clear message on a malformed value so misconfigured A/B runs fail
    /// loudly rather than silently using wrong weights.
    ///
    /// Example: `TGF_EVAL_WEIGHTS=6,2,1`
    pub fn from_env() -> Option<Self> {
        let raw = std::env::var("TGF_EVAL_WEIGHTS").ok()?;
        let parts: Vec<&str> = raw.split(',').collect();
        assert!(
            parts.len() == 3,
            "TGF_EVAL_WEIGHTS must be 'piece_value,mobility,mill_count' \
             (three comma-separated integers); got: {raw}"
        );
        let parse = |s: &str, name: &str| -> i32 {
            s.trim()
                .parse::<i32>()
                .unwrap_or_else(|_| panic!("TGF_EVAL_WEIGHTS: invalid {name} value '{s}'"))
        };
        Some(Self {
            piece_value: parse(parts[0], "piece_value"),
            mobility: parse(parts[1], "mobility"),
            mill_count: parse(parts[2], "mill_count"),
        })
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
