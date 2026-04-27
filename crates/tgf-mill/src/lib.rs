// SPDX-License-Identifier: GPL-3.0-or-later
// Mill game crate.

pub mod rules;
pub mod topology;

pub use rules::{
    CaptureRuleConfig, MillActionKind, MillBoardFullAction, MillEvaluator, MillGame, MillPhase,
    MillRules, MillVariantOptions, MillWorkbench,
};
pub use topology::{default_mill_topology, MillTopology};
