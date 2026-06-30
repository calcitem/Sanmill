// SPDX-License-Identifier: AGPL-3.0-or-later
// Mill game crate.

pub mod engine_config;
pub mod notation;
pub mod presets;
pub mod rules;
pub mod search_depth;
pub mod text_format;
pub mod topology;

pub use engine_config::{MillEngineRuntime, MillSearchAlgorithmKind};
pub use notation::MillUciCodec;
pub use presets::{MillRulePreset, N_PRESETS, preset_for, rules_for_preset};
pub use rules::{
    CaptureRuleConfig, MillActionKind, MillBoardFullAction, MillEvalFeatureSet, MillEvalWeights,
    MillEvaluator, MillFormationActionInPlacingPhase, MillGame, MillPhase, MillPhaseEvalWeights,
    MillRules, MillState, MillVariantOptions, MillWorkbench, StalemateAction,
};
pub use search_depth::{EngineRuntimeOptions, recommended_search_depth};
pub use text_format::MillFenFormat;
pub use topology::{MillTopology, default_mill_topology};
