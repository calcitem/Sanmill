// SPDX-License-Identifier: GPL-3.0-or-later
// Game-neutral Action POD type plus auxiliary metadata
// (`ActionTrail` for chained moves, `action_kind` canonical tags).

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

/// Canonical [`Action::kind_tag`] values shared across games.
///
/// Concrete games still own their kind-tag namespace, but games that
/// pick these defaults gain compatible move-classification across
/// generic tooling (PGN export, search heuristics keyed on capture
/// kinds, debugger UIs, …).
///
/// The numeric values are stable; new tags must be appended at the
/// end so existing transposition-table fingerprints stay valid.
///
/// Mill currently uses 0 = Place, 1 = Move, 2 = Remove which match
/// the canonical PLACE / MOVE / REMOVE constants.  Othello uses 0 =
/// Place, also aligned.
pub mod action_kind {
    /// Place a piece from the hand / supply onto the board.
    pub const PLACE: i16 = 0;
    /// Move a piece between two existing board nodes.
    pub const MOVE: i16 = 1;
    /// Remove an opponent piece from the board.
    pub const REMOVE: i16 = 2;
    /// Capture-style move that performs an implicit removal as part
    /// of the same Action (Othello flips, leap-capture moves).  Use
    /// MOVE when the captured pieces are tracked separately via a
    /// remove action; use CAPTURE when the move + capture are atomic.
    pub const CAPTURE: i16 = 3;
    /// Promote a piece (chess pawn promotion, checkers king).
    pub const PROMOTE: i16 = 4;
    /// Pass / skip turn (Othello forced pass, Go pass).
    pub const PASS: i16 = 5;
    /// Drop a piece from the hand back onto the board (Shogi /
    /// Crazyhouse).
    pub const DROP: i16 = 6;
    /// Castling (chess) — encoded as the king's move, with the trail
    /// recording the rook displacement.
    pub const CASTLE: i16 = 7;
    /// Resign (concede the game).
    pub const RESIGN: i16 = 8;
    /// Multi-hop chained move (Chinese Checkers chain of jumps,
    /// International Checkers forced multi-jump capture).  Detail
    /// lives in `ActionTrail`.
    pub const HOP_CHAIN: i16 = 9;
    /// Reveal a hidden piece (军棋 撞子 reveal-on-encounter).
    pub const REVEAL: i16 = 10;
    /// Stochastic chance outcome (双陆 dice roll, card draw).
    pub const CHANCE: i16 = 11;
}

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
    fn canonical_action_kind_constants_are_distinct() {
        let tags = [
            action_kind::PLACE,
            action_kind::MOVE,
            action_kind::REMOVE,
            action_kind::CAPTURE,
            action_kind::PROMOTE,
            action_kind::PASS,
            action_kind::DROP,
            action_kind::CASTLE,
            action_kind::RESIGN,
            action_kind::HOP_CHAIN,
            action_kind::REVEAL,
            action_kind::CHANCE,
        ];
        let mut seen = std::collections::HashSet::new();
        for tag in tags {
            assert!(seen.insert(tag), "duplicate canonical kind tag {tag}");
        }
    }

    #[test]
    fn place_move_remove_match_mill_existing_layout() {
        // Mill currently encodes 0 = Place, 1 = Move, 2 = Remove on
        // its kind_tag namespace.  Document the alignment with a test
        // so accidental drift surfaces immediately.
        assert_eq!(action_kind::PLACE, 0);
        assert_eq!(action_kind::MOVE, 1);
        assert_eq!(action_kind::REMOVE, 2);
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
