// SPDX-License-Identifier: GPL-3.0-or-later
// Search algorithm selection and runtime options.

use tgf_core::MoveOrderContext;

/// Search algorithm selector.  Mirrors C++ `Algorithm` enum in `src/types.h`.
///
/// The default is `Pvs`, matching the C++ engine's production configuration
/// (`MTD(f)` is the C++ default but PVS is more stable in the Rust scaffold).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum SearchAlgorithm {
    /// Fail-soft Alpha-Beta.
    AlphaBeta,
    /// Principal Variation Search (fail-hard NegaScout).
    #[default]
    Pvs,
    /// MTD(f) — Memory-enhanced Test Driver.
    Mtdf,
    /// Monte Carlo Tree Search.
    Mcts,
    /// Pick a random legal action (for testing or lowest skill level).
    Random,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct SearchPolicy {
    pub remove_kind_tag: Option<i16>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SearchOptions {
    pub depth_extension: bool,
    pub node_limit: Option<u64>,
    pub time_limit_ms: Option<u64>,
    /// Enable the simplified null-move proxy in alpha_beta.
    /// Disabled by default: the current proxy (-static_eval) is a rough
    /// approximation that can prune incorrect branches in specific positions.
    /// Enable explicitly only for experimental use.
    pub allow_null_move: bool,
    /// Shuffle the root move list before searching. Mirrors master's
    /// `MoveList<LEGAL>::shuffle()` call at the start of `executeSearch`
    /// when `Shuffling` is enabled or `SkillLevel < 30` (P2-K).
    pub shuffle_root: bool,
    pub move_order_context: MoveOrderContext,
}

impl Default for SearchOptions {
    fn default() -> Self {
        Self {
            depth_extension: true,
            node_limit: None,
            time_limit_ms: None,
            allow_null_move: false,
            shuffle_root: false,
            move_order_context: MoveOrderContext::default(),
        }
    }
}
