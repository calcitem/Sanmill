// SPDX-License-Identifier: GPL-3.0-or-later
// Common search result POD.

use tgf_core::Action;

/// Sentinel score returned when the root has exactly one legal action.
/// The move is forced regardless of the search outcome, so the searcher
/// short-circuits and returns this value.  Game-neutral: any concrete
/// `Game` whose root collapses to a single legal action will get this
/// value.  Concrete games may map it to a game-local mate constant via
/// [`tgf_core::Game::terminal_score`] or their evaluator scale.
pub const VALUE_UNIQUE_ROOT_MOVE: i32 = 100;

/// Deprecated alias retained for one release cycle.  New code should use
/// [`VALUE_UNIQUE_ROOT_MOVE`].
#[deprecated(
    since = "0.2.0",
    note = "renamed to VALUE_UNIQUE_ROOT_MOVE; the Mill prefix was a leak from the migration era"
)]
pub const MILL_VALUE_UNIQUE: i32 = VALUE_UNIQUE_ROOT_MOVE;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SearchResult {
    pub best_action: Action,
    pub score: i32,
    pub nodes: u64,
}

impl SearchResult {
    /// Sentinel result with no best action.  Used as the initial value
    /// when a search loop hasn't produced any result yet.
    pub fn default_none() -> Self {
        Self {
            best_action: Action::NONE,
            score: 0,
            nodes: 0,
        }
    }

    /// Returns a copy of this result with the score overridden.
    pub fn with_score(mut self, score: i32) -> Self {
        self.score = score;
        self
    }
}
