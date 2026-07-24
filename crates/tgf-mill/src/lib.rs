// SPDX-License-Identifier: AGPL-3.0-or-later
// Mill game crate.

pub mod engine_config;
pub mod feedback;
pub mod human_db_codec;
pub mod logical_turn;
pub mod notation;
pub mod opening_book_symmetry;
pub mod presets;
pub mod rules;
pub mod search_depth;
pub mod text_format;
pub mod topology;

pub use engine_config::{MillEngineRuntime, MillSearchAlgorithmKind};
pub use feedback::{
    MillFeedbackCandidate, MillFeedbackEvidence, MillFeedbackReport, MoveContextAssessment,
    RuleStrategyProfile, assess_move_feedback,
};
pub use logical_turn::{
    LogicalTurnError, MillLogicalTurn, MillPlyCount, legal_logical_turns, logical_turn_completed,
};
pub use notation::MillUciCodec;
pub use opening_book_symmetry::{
    OPENING_BOOK_SYMMETRY_COUNT, canonical_opening_book_fen, inverse_opening_book_transform,
    normalize_opening_book_fen, transform_opening_book_fen, transform_opening_book_node,
    transform_opening_book_notation,
};
pub use presets::{MillRulePreset, N_PRESETS, preset_for, rules_for_preset};
pub use rules::{
    CaptureRuleConfig, MillActionKind, MillBoardFullAction, MillEvalFeatureSet, MillEvalWeights,
    MillEvaluator, MillFormationActionInPlacingPhase, MillGame, MillPhase, MillPhaseEvalWeights,
    MillRules, MillState, MillVariantOptions, MillWorkbench, StalemateAction,
};
pub use search_depth::{EngineRuntimeOptions, recommended_search_depth};
pub use text_format::MillFenFormat;
pub use topology::{MillTopology, default_mill_topology};
