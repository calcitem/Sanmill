// SPDX-License-Identifier: GPL-3.0-or-later
// Mill game crate.

pub mod presets;
pub mod rules;
pub mod search_depth;
pub mod topology;

pub use presets::{preset_for, rules_for_preset, MillRulePreset, N_PRESETS};
pub use rules::{
    CaptureRuleConfig, MillActionKind, MillBoardFullAction, MillEvaluator,
    MillFormationActionInPlacingPhase, MillGame, MillPhase, MillRules, MillVariantOptions,
    MillWorkbench, StalemateAction,
};
pub use search_depth::{recommended_search_depth, EngineRuntimeOptions};
pub use topology::{default_mill_topology, MillTopology};
