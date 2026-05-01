// SPDX-License-Identifier: GPL-3.0-or-later
// Phase 1 scaffold – GameStateSnapshot and Outcome.

/// Immutable, game-neutral state snapshot.  Concrete games store their own
/// bitboards / counters in the opaque_payload byte array.  This type is
/// `repr(C)` and trivially copyable to keep FRB crossing cheap.
///
/// Capacity (`OPAQUE_PAYLOAD_LEN = 320`) is intentionally generous so that
/// games with rich state (Mill carries per-side last-mill, capture-target
/// bitmaps for three capture rules, formed-mill square bitmaps, marked
/// pieces, key-history ring buffer, etc.) can serialise everything they
/// need without pressure to repack.
#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct GameStateSnapshot {
    /// 0 = first player, 1 = second, -1 = none (game over).
    pub side_to_move: i8,
    /// Per-game phase tag; 0 = default "only" phase.
    pub phase_tag: i16,
    /// Plies played from the initial position.
    pub move_number: i16,
    /// Zobrist key; 0 when the game does not use a transposition table.
    pub zobrist_key: u64,
    /// Game-defined snapshot data (board bitmaps, piece counts, …).
    pub opaque_payload: [u8; OPAQUE_PAYLOAD_LEN],
}

/// Size of the opaque per-game payload.  Exposed as a `pub const` so
/// concrete game crates can size their encode buffers identically.
pub const OPAQUE_PAYLOAD_LEN: usize = 320;

impl Default for GameStateSnapshot {
    fn default() -> Self {
        Self {
            side_to_move: 0,
            phase_tag: 0,
            move_number: 0,
            zobrist_key: 0,
            opaque_payload: [0; OPAQUE_PAYLOAD_LEN],
        }
    }
}

/// Coarse game outcome renderable by the shared shell UI.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum OutcomeKind {
    Ongoing,
    Win(i8), // winning player index
    Draw,
    Abandoned,
}

/// Full outcome including a stable reason token the shell maps to l10n text.
#[derive(Clone, Debug)]
pub struct Outcome {
    pub kind: OutcomeKind,
    /// Stable English token, e.g. "loseFewerThanThree", "stalemate".
    /// Never a user-facing literal.
    pub reason: String,
}
