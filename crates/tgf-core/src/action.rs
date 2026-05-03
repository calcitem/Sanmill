// SPDX-License-Identifier: GPL-3.0-or-later
// Phase 1 scaffold – Game-neutral Action POD type.
// Full definition introduced in Phase 3 (tgf-mill Rust rewrite).

/// Game-neutral action encoding.  POD-trivial so it can cross the
/// FRB boundary without copy constructors.  Concrete games map their
/// own move kinds onto `kind_tag`.
#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Default)]
pub struct Action {
    /// Per-game kind (place / move / remove / fly / …).  -1 = none.
    pub kind_tag: i16,
    /// Origin node (-1 for "place from hand").
    pub from_node: i16,
    /// Destination node (-1 for "remove only").
    pub to_node: i16,
    /// Per-game auxiliary integer (promotion piece id, etc.).
    pub aux: i16,
    /// Per-game bitfield (capture mask, en-passant square, …).
    pub payload_bits: u64,
}

impl Action {
    pub const NONE: Self = Self {
        kind_tag: -1,
        from_node: -1,
        to_node: -1,
        aux: -1,
        payload_bits: 0,
    };

    #[inline]
    pub const fn is_none(&self) -> bool {
        self.kind_tag < 0
    }
}

/// Stack-allocated bounded action list.
/// 256 covers Mill / Chess / Checkers; bump the const-generic when needed.
pub type ActionList<const N: usize = 256> = arrayvec::ArrayVec<Action, N>;

/// Auxiliary "trail" data describing the intermediate hops a single
/// [`Action`] traverses.  The framework reserves this for games whose
/// rules can compose more than a single `from -> to` step into one
/// logical move:
///
///   * Chinese Checkers / Halma — chains of jumps over friendly or
///     enemy pieces (`hops` lists every intermediate square between
///     `Action::from_node` and `Action::to_node`).
///   * International Checkers — forced multi-jump captures.
///   * Chess — castling encoded as the king's `from -> to` plus a
///     trail of `[rook_from, rook_to]` so the renderer can animate the
///     rook independently.
///
/// Two design constraints shape the layout:
///
///   1. **Stack-allocated**: trails travel through the FRB boundary
///      together with `Action`, which is a `repr(C)` POD.  An inline
///      array keeps everything in a single struct so the Dart shell
///      can render trails without an extra heap-allocated DTO.
///   2. **Bounded**: 15 hops covers every commercial Halma / Chinese-
///      Checkers chain we have observed in practice (the longest
///      forced-jump path on a 121-hole board is 12 hops).
#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct ActionTrail {
    /// Number of populated hop slots (`0..=ActionTrail::MAX`).
    pub len: u8,
    /// Hop sequence between `Action::from_node` and `Action::to_node`,
    /// excluding both endpoints (those live on the parent `Action`).
    /// Unused slots are zeroed.
    pub hops: [u16; ActionTrail::MAX],
}

impl ActionTrail {
    /// Maximum number of hops a single trail can carry.
    pub const MAX: usize = 15;

    /// Empty trail (single `from -> to` step, no intermediate hops).
    pub const EMPTY: Self = Self {
        len: 0,
        hops: [0; Self::MAX],
    };

    /// True when the trail is empty (i.e. the action is a single hop).
    #[inline]
    pub const fn is_empty(&self) -> bool {
        self.len == 0
    }

    /// Number of populated hop slots.
    #[inline]
    pub const fn len(&self) -> usize {
        self.len as usize
    }

    /// Borrow the populated hop prefix.
    #[inline]
    pub fn hops(&self) -> &[u16] {
        &self.hops[..self.len as usize]
    }

    /// Append `node` to the trail.  Returns `false` if the trail is
    /// already full so callers can decide whether to surface a rule
    /// violation or silently drop the hop.
    #[inline]
    pub fn push(&mut self, node: u16) -> bool {
        if (self.len as usize) >= Self::MAX {
            return false;
        }
        self.hops[self.len as usize] = node;
        self.len += 1;
        true
    }

    /// Construct a trail from an iterator of hop node ids.  Returns
    /// `None` when the iterator yields more than [`ActionTrail::MAX`]
    /// items.
    #[inline]
    pub fn from_hops<I: IntoIterator<Item = u16>>(iter: I) -> Option<Self> {
        let mut trail = Self::EMPTY;
        for hop in iter {
            if !trail.push(hop) {
                return None;
            }
        }
        Some(trail)
    }
}

impl Default for ActionTrail {
    #[inline]
    fn default() -> Self {
        Self::EMPTY
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_trail_round_trips() {
        let trail = ActionTrail::EMPTY;
        assert!(trail.is_empty());
        assert_eq!(trail.len(), 0);
        assert!(trail.hops().is_empty());
    }

    #[test]
    fn push_appends_until_full() {
        let mut trail = ActionTrail::EMPTY;
        for i in 0..ActionTrail::MAX as u16 {
            assert!(trail.push(i));
        }
        // 16th push must be refused.
        assert!(!trail.push(99));
        assert_eq!(trail.len(), ActionTrail::MAX);
        assert_eq!(trail.hops().last(), Some(&((ActionTrail::MAX - 1) as u16)));
    }

    #[test]
    fn from_hops_caps_at_max() {
        let trail = ActionTrail::from_hops([1, 2, 3, 4]);
        assert!(trail.is_some());
        assert_eq!(trail.unwrap().hops(), &[1, 2, 3, 4]);

        // Too many hops returns None instead of silently truncating.
        let too_many = (0..(ActionTrail::MAX as u16 + 1)).collect::<Vec<_>>();
        assert!(ActionTrail::from_hops(too_many).is_none());
    }

    #[test]
    fn action_none_sentinel_is_negative_kind() {
        // Action::default() is the all-zero POD; Action::NONE is a
        // sentinel with negative tags.  Both call sites are documented
        // contracts of the FRB ABI.
        assert!(Action::NONE.is_none());
        assert!(!Action::default().is_none());
        assert_eq!(Action::NONE.kind_tag, -1);
    }
}
