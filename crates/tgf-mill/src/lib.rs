// SPDX-License-Identifier: GPL-3.0-or-later
// Mill game crate.

pub mod topology;
pub mod rules;

pub use rules::{MillActionKind, MillPhase, MillRules, MillVariantOptions};
pub use topology::{default_mill_topology, MillTopology};
