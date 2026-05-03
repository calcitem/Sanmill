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
///
/// Concrete games may emit free-form `reason` strings for game-specific
/// terminal states (Mill's `loseFewerThanThree`, `marriedMills`, …).
/// Generic engines should reach for the canonical token vocabulary in
/// [`canonical_reason`] so cross-game tooling (PGN export, l10n
/// dictionaries, replay viewers) can recognise common outcomes
/// without per-game branches.
#[derive(Clone, Debug)]
pub struct Outcome {
    pub kind: OutcomeKind,
    /// Stable English token, e.g. "loseFewerThanThree", "stalemate".
    /// Never a user-facing literal.
    pub reason: String,
}

impl Outcome {
    /// Construct an `Ongoing` outcome with the canonical reason token
    /// `"ongoing"`.
    #[inline]
    pub fn ongoing() -> Self {
        Self {
            kind: OutcomeKind::Ongoing,
            reason: canonical_reason::ONGOING.to_owned(),
        }
    }

    /// Construct a `Win(player)` outcome tagged with the given
    /// canonical reason token (use the constants in
    /// [`canonical_reason`]).
    #[inline]
    pub fn win(player: i8, reason: impl Into<String>) -> Self {
        Self {
            kind: OutcomeKind::Win(player),
            reason: reason.into(),
        }
    }

    /// Construct a `Draw` outcome tagged with the given canonical
    /// reason token.
    #[inline]
    pub fn draw(reason: impl Into<String>) -> Self {
        Self {
            kind: OutcomeKind::Draw,
            reason: reason.into(),
        }
    }
}

/// Stable terminal-reason tokens shared across games.  Mapping these
/// strings to l10n keys is the shell's responsibility; the framework
/// only guarantees that any game producing an outcome with a
/// canonical reason can be displayed by any shell that knows about
/// the vocabulary.
///
/// Games may still emit custom reason strings (the framework treats
/// `Outcome::reason` as opaque), but using these constants where
/// applicable lets cross-game tooling react uniformly.
pub mod canonical_reason {
    /// The game has not finished.
    pub const ONGOING: &str = "ongoing";
    /// Standard mate-by-rule terminal (chess, xiangqi, …).
    pub const CHECKMATE: &str = "checkmate";
    /// Side to move has no legal moves; outcome decided by per-game
    /// stalemate convention (chess: draw; xiangqi: loss; …).
    pub const STALEMATE: &str = "stalemate";
    /// Position has been seen the rule-defined number of times.
    pub const THREEFOLD_REPETITION: &str = "threefoldRepetition";
    /// Five-fold repetition mandatory draw (chess FIDE rule).
    pub const FIVEFOLD_REPETITION: &str = "fivefoldRepetition";
    /// Super-ko / position recurrence (Go).
    pub const SUPER_KO: &str = "superKo";
    /// N-move rule fired (chess 50-move, Mill 100-move, …).
    pub const N_MOVE_RULE: &str = "nMoveRule";
    /// Both sides hold insufficient mating material.
    pub const INSUFFICIENT_MATERIAL: &str = "insufficientMaterial";
    /// Score-comparison terminal (Othello / Reversi, Go area scoring).
    pub const SCORE_COMPARISON: &str = "scoreComparison";
    /// Both sides agreed to a draw via UI / protocol.
    pub const AGREED_DRAW: &str = "agreedDraw";
    /// One side resigned.
    pub const RESIGNED: &str = "resigned";
    /// One side ran out of time on the clock.
    pub const TIMEOUT: &str = "timeout";
    /// Halma / Chinese-Checkers victory: every piece sits in the goal
    /// triangle.
    pub const ALL_REACHED_GOAL: &str = "allReachedGoal";
    /// Junqi (军棋) victory: opposing flag captured.
    pub const FLAG_CAPTURED: &str = "flagCaptured";
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn outcome_helpers_round_trip_canonical_reasons() {
        let ongoing = Outcome::ongoing();
        assert_eq!(ongoing.kind, OutcomeKind::Ongoing);
        assert_eq!(ongoing.reason, canonical_reason::ONGOING);

        let win = Outcome::win(1, canonical_reason::CHECKMATE);
        assert_eq!(win.kind, OutcomeKind::Win(1));
        assert_eq!(win.reason, "checkmate");

        let draw = Outcome::draw(canonical_reason::THREEFOLD_REPETITION);
        assert_eq!(draw.kind, OutcomeKind::Draw);
        assert_eq!(draw.reason, "threefoldRepetition");
    }

    #[test]
    fn canonical_reason_tokens_are_distinct() {
        let tokens = [
            canonical_reason::ONGOING,
            canonical_reason::CHECKMATE,
            canonical_reason::STALEMATE,
            canonical_reason::THREEFOLD_REPETITION,
            canonical_reason::FIVEFOLD_REPETITION,
            canonical_reason::SUPER_KO,
            canonical_reason::N_MOVE_RULE,
            canonical_reason::INSUFFICIENT_MATERIAL,
            canonical_reason::SCORE_COMPARISON,
            canonical_reason::AGREED_DRAW,
            canonical_reason::RESIGNED,
            canonical_reason::TIMEOUT,
            canonical_reason::ALL_REACHED_GOAL,
            canonical_reason::FLAG_CAPTURED,
        ];
        let mut seen = std::collections::HashSet::new();
        for t in tokens {
            assert!(seen.insert(t), "duplicate canonical reason token {t:?}");
        }
    }
}
