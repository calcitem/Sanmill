// SPDX-License-Identifier: GPL-3.0-or-later
// Search algorithm selection and runtime options.

use tgf_core::MoveOrderContext;

/// Search algorithm selector.  Mirrors C++ `Algorithm` enum in `src/types.h`.
///
/// The default is `Pvs`, which gives the Rust engine stable pruning behavior.
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

/// Per-game search policy hooks.
///
/// All fields are optional kind-tag selectors (matching
/// `Action::kind_tag`).  The searcher consults them at well-defined
/// extension / pruning points so games can opt into quiescence-style
/// behaviour without modifying the shared `Searcher<G>` core.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct SearchPolicy {
    /// Action kind that drives the q-search "tactical" extension.
    /// Mill uses `Remove`; chess-style games typically use `Capture`.
    /// `None` disables the extension entirely.
    pub quiescence_kind_tag: Option<i16>,
    /// Action kind that, when emitted, MUST be played even if other
    /// moves are legal.  Used by games with forced chain captures
    /// (international checkers maximum-take rule, certain Mill
    /// variants).  `None` means no forced-chain enforcement.
    pub forced_chain_kind_tag: Option<i16>,
}

impl SearchPolicy {
    /// Backwards-compatible accessor — historically the only field on
    /// SearchPolicy was `remove_kind_tag`.  Keep the deprecated name as
    /// an alias so external callers can migrate without churn.
    #[deprecated(since = "0.2.0", note = "use `quiescence_kind_tag` instead")]
    #[doc(hidden)]
    #[inline]
    pub fn remove_kind_tag(&self) -> Option<i16> {
        self.quiescence_kind_tag
    }
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
    /// Issue `TT::prefetch` hints for every candidate child before
    /// iterating the move loop, mirroring master `Search::search` /
    /// `Search::qsearch` (which always emit prefetch when
    /// `DISABLE_PREFETCH` is undefined).  Default `false` because the
    /// Rust default `Workbench::key_after` is a do/undo round-trip;
    /// games with full-state hashing pay more for the round-trip than
    /// they save in cache misses.  Concrete games that override
    /// `key_after` with an O(1) xor path should enable this.
    pub enable_prefetch: bool,
    /// Wrap each iterative-deepening iteration (depth >= 3) in an
    /// aspiration window centered on the previous score ± delta.
    /// Default `false` because master `executeSearch` does not use
    /// aspiration windows -- every IDS iteration runs with the full
    /// `[-VALUE_INFINITE, VALUE_INFINITE]` window, even though
    /// `VALUE_PLACING_WINDOW` / `VALUE_MOVING_WINDOW` constants are
    /// defined in `src/types.h`.  The Rust implementation keeps aspiration
    /// available behind this flag for users who want the extra NPS
    /// boost on stable scores.
    pub enable_aspiration_window: bool,
    /// Use a per-depth killer-move table to score quiet moves that
    /// recently caused beta-cutoffs.  Default `false` because master
    /// `MovePicker::score` does not maintain a killer table -- the
    /// only quiet bonus there is `RATING_STAR_SQUARE` and the various
    /// mill-formation / mill-block heuristics.  Enable to opt into
    /// chess-style killer-heuristic move ordering.
    pub enable_killers: bool,
    /// Use the history-heuristic table (per-action accumulated
    /// fail-high bonus).  Default `false` for the same reason as
    /// `enable_killers`.
    pub enable_history: bool,
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
            enable_prefetch: false,
            // Master executeSearch does NOT use aspiration windows.
            enable_aspiration_window: false,
            // Master MovePicker has no killer / history tables.
            enable_killers: false,
            enable_history: false,
            move_order_context: MoveOrderContext::default(),
        }
    }
}
