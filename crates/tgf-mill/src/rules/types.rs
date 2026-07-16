// SPDX-License-Identifier: AGPL-3.0-or-later
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
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
#[cfg_attr(feature = "serde", serde(rename_all = "camelCase"))]
#[repr(i16)]
pub enum MillBoardFullAction {
    FirstPlayerLose = 0,
    FirstAndSecondPlayerRemovePiece = 1,
    SecondAndFirstPlayerRemovePiece = 2,
    SideToMoveRemovePiece = 3,
    AgreeToDraw = 4,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
#[cfg_attr(feature = "serde", serde(rename_all = "camelCase"))]
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
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
#[cfg_attr(feature = "serde", serde(rename_all = "camelCase"))]
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
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
#[cfg_attr(feature = "serde", serde(rename_all = "camelCase"))]
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

/// Per-phase tunable weights for the Mill static evaluator.
///
/// `LEGACY` exactly matches the hard-coded constants in the retired C++
/// engine.  `TUNED` is the H2H-accepted default for the Rust/TGF engine.
/// Custom weights (produced by the offline perfect-DB Texel tuner) can still
/// be injected through `TGF_EVAL_WEIGHTS` without altering any other rule
/// behaviour.
///
/// Fields:
/// - `piece_value`:  per-piece material weight (master: 5 = VALUE_EACH_PIECE)
/// - `mobility`:     weight on the mobility difference term (master: 1)
/// - `mill_count`:   weight on the mill-pieces-count difference term used in
///   the RemovalBasedOnMillCounts placing-phase variant (master: 1)
/// - `position_value`: weight on cardinal/T/corner square occupancy.
/// - `cardinal_mill`: weight on mills formed along the four cardinal lines.
/// - `near_fly_bonus`: weight on being at the fly threshold (`3` pieces).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct MillPhaseEvalWeights {
    pub piece_value: i32,
    pub mobility: i32,
    pub mill_count: i32,
    pub position_value: i32,
    pub cardinal_mill: i32,
    pub near_fly_bonus: i32,
}

impl MillPhaseEvalWeights {
    pub const LEGACY: Self = Self {
        piece_value: 5,
        mobility: 1,
        mill_count: 1,
        position_value: 0,
        cardinal_mill: 0,
        near_fly_bonus: 0,
    };
}

/// Phase-aware Mill evaluator weights.
///
/// `placing`, `moving_open`, `pre_fly`, and `flying` deliberately share the
/// same shape so the offline tuner can fit them independently while the
/// deployed evaluator stays branch-light and integer-only.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct MillEvalWeights {
    pub placing: MillPhaseEvalWeights,
    pub moving_open: MillPhaseEvalWeights,
    pub pre_fly: MillPhaseEvalWeights,
    pub flying: MillPhaseEvalWeights,
}

/// White-perspective feature vector consumed by the static evaluator and the
/// offline Texel tuner.  Keeping this in `tgf-mill` prevents training and
/// deployment from drifting apart as features evolve.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct MillEvalFeatureSet {
    pub material_diff: i32,
    pub mobility_diff: i32,
    pub mill_count_diff: i32,
    pub position_value_diff: i32,
    pub cardinal_mill_diff: i32,
    pub near_fly_diff: i32,
}

impl MillEvalWeights {
    /// The legacy hard-coded weights.  Scores are identical to the
    /// pre-parameterisation evaluator when these are used.
    pub const LEGACY: Self = Self {
        placing: MillPhaseEvalWeights::LEGACY,
        moving_open: MillPhaseEvalWeights::LEGACY,
        pre_fly: MillPhaseEvalWeights::LEGACY,
        flying: MillPhaseEvalWeights::LEGACY,
    };

    /// H2H-accepted Rust/TGF default:
    ///
    /// - placing/pre-fly keep the legacy weights,
    /// - moving_open doubles mobility (1 -> 2),
    /// - flying disables adjacent-square mobility because flying pieces can
    ///   move to any empty square.
    ///
    /// Skill 30 / 200 ms H2H validation:
    /// - 10000 games: 51.8% +/- 1.6% (99.9% CI)
    /// - second seed partial 7528 games: 52.3% +/- 1.9% (99.9% CI)
    pub const TUNED: Self = Self {
        placing: MillPhaseEvalWeights::LEGACY,
        moving_open: MillPhaseEvalWeights {
            mobility: 2,
            ..MillPhaseEvalWeights::LEGACY
        },
        pre_fly: MillPhaseEvalWeights::LEGACY,
        flying: MillPhaseEvalWeights {
            mobility: 0,
            ..MillPhaseEvalWeights::LEGACY
        },
    };
}

impl Default for MillEvalWeights {
    fn default() -> Self {
        Self::TUNED
    }
}

impl MillEvalWeights {
    /// Read `TGF_EVAL_WEIGHTS` from the environment.
    ///
    /// Accepted formats:
    /// - `piece,mobility,mill_count` (legacy, applies to every phase)
    /// - `piece,mobility,mill_count,position,cardinal_mill,near_fly`
    ///   (single phase shape, applies to every phase)
    /// - 24 comma-separated integers, four 6-value phase blocks in order:
    ///   placing, moving-open, pre-fly, flying.
    ///
    /// Example: `TGF_EVAL_WEIGHTS=6,2,1`
    pub fn from_env() -> Option<Self> {
        let raw = std::env::var("TGF_EVAL_WEIGHTS").ok()?;
        let parts: Vec<&str> = raw.split(',').collect();
        assert!(
            matches!(parts.len(), 3 | 6 | 24),
            "TGF_EVAL_WEIGHTS must contain 3, 6, or 24 comma-separated integers; got: {raw}"
        );
        let parse = |s: &str, idx: usize| -> i32 {
            s.trim()
                .parse::<i32>()
                .unwrap_or_else(|_| panic!("TGF_EVAL_WEIGHTS: invalid value #{idx} '{s}'"))
        };
        let values: Vec<i32> = parts
            .iter()
            .enumerate()
            .map(|(idx, part)| parse(part, idx))
            .collect();
        Some(Self::from_flat_values(&values))
    }

    pub fn from_flat_values(values: &[i32]) -> Self {
        match values.len() {
            3 => {
                let phase = MillPhaseEvalWeights {
                    piece_value: values[0],
                    mobility: values[1],
                    mill_count: values[2],
                    ..MillPhaseEvalWeights::LEGACY
                };
                Self::same_for_all_phases(phase)
            }
            6 => Self::same_for_all_phases(phase_from_six(values)),
            24 => Self {
                placing: phase_from_six(&values[0..6]),
                moving_open: phase_from_six(&values[6..12]),
                pre_fly: phase_from_six(&values[12..18]),
                flying: phase_from_six(&values[18..24]),
            },
            _ => panic!("MillEvalWeights requires 3, 6, or 24 values"),
        }
    }

    pub fn same_for_all_phases(phase: MillPhaseEvalWeights) -> Self {
        Self {
            placing: phase,
            moving_open: phase,
            pre_fly: phase,
            flying: phase,
        }
    }
}

fn phase_from_six(values: &[i32]) -> MillPhaseEvalWeights {
    assert_eq!(values.len(), 6, "phase weights require six values");
    MillPhaseEvalWeights {
        piece_value: values[0],
        mobility: values[1],
        mill_count: values[2],
        position_value: values[3],
        cardinal_mill: values[4],
        near_fly_bonus: values[5],
    }
}

#[derive(Clone, Debug)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
#[cfg_attr(feature = "serde", serde(rename_all = "camelCase"))]
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
    #[cfg_attr(feature = "serde", serde(default = "serde_default_true"))]
    pub consider_mobility: bool,
    /// Mirror of `gameOptions.getFocusOnBlockingPaths()` from the legacy
    /// C++ engine.  When true the static evaluator drops the material
    /// difference from the score so the search prioritises mobility-only
    /// blocking lines (only meaningful in the moving phase / fly endgame).
    #[cfg_attr(feature = "serde", serde(default))]
    pub focus_on_blocking_paths: bool,
}

#[cfg(feature = "serde")]
const fn serde_default_true() -> bool {
    true
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
