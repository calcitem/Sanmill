// SPDX-License-Identifier: GPL-3.0-or-later
// Generic N-move rule counter shared by every game with a
// "no irreversible move for N plies → draw / endgame" rule.
//
// Examples:
//
//   * Chess 50-move rule: draw_threshold = 100 plies (50 full moves).
//   * Mill 100-move rule (no captures): draw_threshold = 100 plies.
//   * Mill 50-move endgame: endgame_threshold = 100 plies.
//   * Halma stall rule (some variants): draw_threshold = 60 plies.
//
// The counter intentionally exposes both `draw_threshold` and
// `endgame_threshold`: chess uses only the former while Mill / Halma
// have a soft "endgame mode" that flips on first and only later
// promotes to a draw.  Games that need only one threshold should set
// the unused one to `u32::MAX` to disable it.
//
// Like `RepetitionTracker`, this struct is allocation-free and
// `Copy`-friendly so games may embed it inside their state.  All
// operations are `O(1)` and `#[inline]`.

/// Bookkeeping for the N-move rule.
///
/// `ply_since_irreversible` increments once per *ply* (half-move).
/// Concrete games call [`Self::bump_reversible`] after every quiet
/// move and [`Self::reset_irreversible`] after every irreversible
/// move (capture / pawn push / Mill mill-break / Halma jump that
/// leaves the home base).
///
/// Two helpers expose rule activation:
///
///   * [`Self::is_draw_active`] → counter has reached `draw_threshold`
///   * [`Self::is_endgame_active`] → counter has reached
///     `endgame_threshold` (a soft state used by Mill to switch the
///     evaluator to endgame mode before the draw fires).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct NMoveRuleCounter {
    pub ply_since_irreversible: u32,
    /// Plies after which the rule mandates a draw.  Use `u32::MAX` to
    /// disable.
    pub draw_threshold: u32,
    /// Plies after which the rule's endgame mode activates.  Use
    /// `u32::MAX` to disable.
    pub endgame_threshold: u32,
}

impl NMoveRuleCounter {
    /// Construct a counter with the supplied thresholds.  Both
    /// thresholds default to `u32::MAX` (disabled) when callers
    /// configure only one rule.
    #[inline]
    pub const fn new(draw_threshold: u32, endgame_threshold: u32) -> Self {
        Self {
            ply_since_irreversible: 0,
            draw_threshold,
            endgame_threshold,
        }
    }

    /// Counter wired for the chess 50-move rule (`draw_threshold = 100`).
    #[inline]
    pub const fn chess_50_move_rule() -> Self {
        Self::new(100, u32::MAX)
    }

    /// Counter wired for Mill: 100-move draw rule + 100-move endgame.
    /// Concrete games may override either threshold via
    /// `MillVariantOptions`.
    #[inline]
    pub const fn mill_default() -> Self {
        Self::new(100, 100)
    }

    /// Increment the ply counter (call after a reversible move).
    /// Returns `true` if the increment crossed `draw_threshold`,
    /// matching the convenience signature of
    /// [`crate::repetition::RepetitionTracker::push`].
    #[inline]
    pub fn bump_reversible(&mut self) -> bool {
        self.ply_since_irreversible = self.ply_since_irreversible.saturating_add(1);
        self.is_draw_active()
    }

    /// Reset the ply counter to zero (call after an irreversible move).
    #[inline]
    pub fn reset_irreversible(&mut self) {
        self.ply_since_irreversible = 0;
    }

    /// True when the draw rule should fire.
    #[inline]
    pub fn is_draw_active(&self) -> bool {
        self.draw_threshold != u32::MAX && self.ply_since_irreversible >= self.draw_threshold
    }

    /// True when the endgame mode should activate.
    #[inline]
    pub fn is_endgame_active(&self) -> bool {
        self.endgame_threshold != u32::MAX && self.ply_since_irreversible >= self.endgame_threshold
    }
}

impl Default for NMoveRuleCounter {
    /// Defaults to the chess 50-move rule.
    #[inline]
    fn default() -> Self {
        Self::chess_50_move_rule()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_to_chess_50_move_rule() {
        let c = NMoveRuleCounter::default();
        assert_eq!(c.draw_threshold, 100);
        assert_eq!(c.endgame_threshold, u32::MAX);
        assert_eq!(c.ply_since_irreversible, 0);
        assert!(!c.is_draw_active());
    }

    #[test]
    fn bump_reversible_returns_true_at_threshold() {
        let mut c = NMoveRuleCounter::new(3, u32::MAX);
        assert!(!c.bump_reversible());
        assert!(!c.bump_reversible());
        assert!(c.bump_reversible());
    }

    #[test]
    fn reset_irreversible_clears_counter() {
        let mut c = NMoveRuleCounter::new(3, u32::MAX);
        c.bump_reversible();
        c.bump_reversible();
        c.reset_irreversible();
        assert_eq!(c.ply_since_irreversible, 0);
        assert!(!c.is_draw_active());
    }

    #[test]
    fn endgame_threshold_activates_independently() {
        let mut c = NMoveRuleCounter::new(100, 50);
        for _ in 0..49 {
            c.bump_reversible();
        }
        assert!(!c.is_endgame_active());
        c.bump_reversible();
        assert!(c.is_endgame_active());
        assert!(!c.is_draw_active());
        for _ in 0..50 {
            c.bump_reversible();
        }
        assert!(c.is_draw_active());
    }

    #[test]
    fn disabled_thresholds_never_fire() {
        let mut c = NMoveRuleCounter::new(u32::MAX, u32::MAX);
        for _ in 0..1000 {
            assert!(!c.bump_reversible());
        }
        assert!(!c.is_draw_active());
        assert!(!c.is_endgame_active());
    }

    #[test]
    fn ply_counter_saturates_instead_of_wrapping() {
        let mut c = NMoveRuleCounter::new(u32::MAX, u32::MAX);
        c.ply_since_irreversible = u32::MAX - 1;
        c.bump_reversible();
        c.bump_reversible();
        assert_eq!(c.ply_since_irreversible, u32::MAX);
    }

    #[test]
    fn mill_default_matches_documented_thresholds() {
        let c = NMoveRuleCounter::mill_default();
        assert_eq!(c.draw_threshold, 100);
        assert_eq!(c.endgame_threshold, 100);
    }
}
