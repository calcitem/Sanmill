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
    pub kind_tag:    i16,
    /// Origin node (-1 for "place from hand").
    pub from_node:   i16,
    /// Destination node (-1 for "remove only").
    pub to_node:     i16,
    /// Per-game auxiliary integer (promotion piece id, etc.).
    pub aux:         i16,
    /// Per-game bitfield (capture mask, en-passant square, …).
    pub payload_bits: u64,
}

impl Action {
    pub const NONE: Self = Self {
        kind_tag: -1, from_node: -1, to_node: -1, aux: -1, payload_bits: 0,
    };

    #[inline]
    pub const fn is_none(&self) -> bool { self.kind_tag < 0 }
}

/// Stack-allocated bounded action list.
/// 256 covers Mill / Chess / Checkers; bump the const-generic when needed.
pub type ActionList<const N: usize = 256> = arrayvec::ArrayVec<Action, N>;
