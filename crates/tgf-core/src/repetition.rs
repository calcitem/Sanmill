// SPDX-License-Identifier: GPL-3.0-or-later
// Generic repetition tracker shared by every game with an
// "<n>-fold position repetition is a draw / loss" rule.
//
// Both compile-time parameters are intentional:
//
//   * `THRESHOLD` is the count that triggers the rule.  3 for chess
//     and Mill threefold repetition; 4 for some Go super-ko variants
//     used in tournament rules.
//   * `CAP` is the ring-buffer capacity — how far back we remember
//     position keys.  256 covers Mill's existing window with room to
//     spare for chess-style play; smaller buffers may be appropriate
//     for unit tests or memory-constrained ports.
//
// The tracker stores raw `u64` Zobrist-style keys and never compares
// snapshots directly, so it is `Copy`-friendly and suitable for
// embedding into game state.  All operations are `O(CAP)` worst-case
// (only triggered on `push`), with `O(1)` `clear`.  No heap allocation.
//
// This module is *not* part of the search hot path; it is consumed by
// rule code (`apply` / `is_legal`) in concrete game crates.  Even so,
// the implementation is designed to be allocation-free and avoid
// branches on the slow path so that games with frequent reversible
// moves do not pay an obvious overhead.

/// A bounded ring buffer of position keys plus a count threshold.
///
/// The ring buffer keeps the most recent `CAP` keys.  `push` returns
/// `true` exactly when the inserted key has now been seen at least
/// `THRESHOLD` times, so callers can fold draw/loss-by-repetition
/// detection into a single statement.
///
/// `clear` should be called whenever an irreversible move occurs
/// (capture / pawn push / Mill mill-break) so older history cannot
/// influence future repetition checks.
#[derive(Clone, Copy, Debug)]
pub struct RepetitionTracker<const THRESHOLD: usize, const CAP: usize> {
    keys: [u64; CAP],
    /// Number of slots actually populated, saturating at CAP.
    len: u16,
    /// Index of the next slot to overwrite (oldest entry once `len == CAP`).
    head: u16,
}

impl<const THRESHOLD: usize, const CAP: usize> Default for RepetitionTracker<THRESHOLD, CAP> {
    #[inline]
    fn default() -> Self {
        Self::new()
    }
}

impl<const THRESHOLD: usize, const CAP: usize> RepetitionTracker<THRESHOLD, CAP> {
    /// Create an empty tracker.  THRESHOLD must be >= 1; CAP must be >= 1.
    #[inline]
    pub const fn new() -> Self {
        // Compile-time bounds check: const-eval will panic if violated
        // at instantiation, surfacing the bug at the use site.
        assert!(THRESHOLD >= 1, "RepetitionTracker THRESHOLD must be >= 1");
        assert!(CAP >= 1, "RepetitionTracker CAP must be >= 1");
        Self {
            keys: [0; CAP],
            len: 0,
            head: 0,
        }
    }

    /// Number of populated slots (saturates at `CAP`).
    #[inline]
    pub fn len(&self) -> usize {
        self.len as usize
    }

    /// True when the tracker has no recorded keys.
    #[inline]
    pub fn is_empty(&self) -> bool {
        self.len == 0
    }

    /// Forget all recorded keys.  Use after irreversible moves
    /// (captures / pawn pushes / Mill mill-break / 双陆 bear-off).
    #[inline]
    pub fn clear(&mut self) {
        self.len = 0;
        self.head = 0;
    }

    /// Push `key` into the ring buffer and return whether the key has
    /// now been observed at least `THRESHOLD` times within the window.
    ///
    /// The implementation walks the buffer once, so it is `O(min(len,
    /// CAP))`; callers expecting many reversible plies in a row should
    /// keep CAP modest (256 is plenty for chess, Mill, Halma).
    #[inline]
    pub fn push(&mut self, key: u64) -> bool {
        let cap = CAP as u16;
        // Insert into the ring slot.
        let slot = self.head as usize;
        self.keys[slot] = key;
        self.head = if self.head + 1 == cap {
            0
        } else {
            self.head + 1
        };
        if (self.len as usize) < CAP {
            self.len += 1;
        }
        // Count occurrences.
        let mut count = 0_usize;
        let limit = self.len as usize;
        for i in 0..limit {
            if self.keys[i] == key {
                count += 1;
                if count >= THRESHOLD {
                    return true;
                }
            }
        }
        false
    }

    /// Number of times `key` currently appears in the window.
    #[inline]
    pub fn count(&self, key: u64) -> usize {
        let limit = self.len as usize;
        let mut count = 0_usize;
        for i in 0..limit {
            if self.keys[i] == key {
                count += 1;
            }
        }
        count
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    type Threefold = RepetitionTracker<3, 16>;

    #[test]
    fn empty_tracker_starts_empty() {
        let t = Threefold::new();
        assert!(t.is_empty());
        assert_eq!(t.len(), 0);
        assert_eq!(t.count(42), 0);
    }

    #[test]
    fn push_returns_true_on_threshold_occurrence() {
        let mut t = Threefold::new();
        assert!(!t.push(1));
        assert!(!t.push(2));
        assert!(!t.push(1));
        // Third occurrence of `1` (after 1, 2, 1): no, only second.  Add another.
        assert!(!t.push(2));
        assert!(t.push(1));
    }

    #[test]
    fn clear_resets_count_window() {
        let mut t = Threefold::new();
        t.push(7);
        t.push(7);
        t.clear();
        assert_eq!(t.count(7), 0);
        assert!(!t.push(7));
        assert!(!t.push(7));
        assert!(t.push(7));
    }

    #[test]
    fn ring_buffer_overwrites_when_capacity_exceeded() {
        type Tracker = RepetitionTracker<2, 4>;
        let mut t = Tracker::new();
        t.push(1);
        t.push(2);
        t.push(3);
        t.push(4);
        // Buffer full; pushing 5 evicts the first 1.
        assert!(!t.push(5));
        assert_eq!(t.count(1), 0, "eviction did not drop the oldest slot");
        // Pushing 5 again yields the second occurrence.
        assert!(t.push(5));
    }

    #[test]
    fn fivefold_threshold_supported_for_super_ko() {
        type Fivefold = RepetitionTracker<5, 16>;
        let mut t = Fivefold::new();
        for _ in 0..4 {
            assert!(!t.push(0xfeedface));
        }
        assert!(t.push(0xfeedface));
    }

    #[test]
    fn count_reflects_current_window_only() {
        let mut t = Threefold::new();
        t.push(0xa);
        t.push(0xb);
        t.push(0xa);
        assert_eq!(t.count(0xa), 2);
        assert_eq!(t.count(0xb), 1);
        t.clear();
        assert_eq!(t.count(0xa), 0);
    }
}
