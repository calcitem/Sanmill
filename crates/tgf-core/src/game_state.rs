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
///
/// Two-player games emit `Win(player)`; multi-player team games
/// (军棋 4 人对战, Halma 6 人 3 队 …) emit `WinTeam(team)` with the
/// team id whose payoff is +1.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum OutcomeKind {
    Ongoing,
    /// Single-player victory; payload is the winning player id (matches
    /// `GameStateSnapshot::side_to_move` numbering).
    Win(i8),
    /// Team victory (multi-player games only); payload is the winning
    /// team id from [`MultiPlayerInfo::team_of`].
    WinTeam(u8),
    Draw,
    Abandoned,
}

/// Optional multi-player metadata describing the player count and
/// team layout of a game session.  Two-player games leave this at
/// [`MultiPlayerInfo::two_player_default`] and never need to look at
/// it.
///
/// Concrete games expose this through
/// [`crate::GameRules::multi_player_info`] so the FRB layer / shell
/// can render team-aware UI (turn-order indicators, team colours,
/// `WinTeam` renderers) without per-game branches.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct MultiPlayerInfo {
    /// Number of distinct players (1..=8).
    pub player_count: u8,
    /// `team_of[i]` is the team id (0..=7) of player `i`.  Players in
    /// the same team share win/loss outcomes.  Default: every player
    /// is in its own team (`team_of[i] = i`).
    pub team_of: [u8; 8],
    /// Turn order; `turn_order[i]` is the player id that plays on the
    /// i-th ply.  Default: `[0, 1, ..., player_count - 1]`.
    pub turn_order: [u8; 8],
}

impl MultiPlayerInfo {
    /// Standard two-player free-for-all metadata.  Matches every
    /// existing game in the framework.
    #[inline]
    pub const fn two_player_default() -> Self {
        Self {
            player_count: 2,
            team_of: [0, 1, 2, 3, 4, 5, 6, 7],
            turn_order: [0, 1, 2, 3, 4, 5, 6, 7],
        }
    }

    /// Construct a free-for-all (every player in its own team) layout
    /// for `player_count` players using the default sequential turn
    /// order.
    #[inline]
    pub const fn free_for_all(player_count: u8) -> Self {
        assert!(
            player_count >= 1 && player_count <= 8,
            "player_count must be 1..=8",
        );
        Self {
            player_count,
            team_of: [0, 1, 2, 3, 4, 5, 6, 7],
            turn_order: [0, 1, 2, 3, 4, 5, 6, 7],
        }
    }

    /// True when the metadata describes a single team per player
    /// (i.e. no alliances).
    #[inline]
    pub fn is_free_for_all(&self) -> bool {
        for i in 0..self.player_count as usize {
            if self.team_of[i] != i as u8 {
                return false;
            }
        }
        true
    }

    /// Team id of `player`, or `None` when `player` is out of range.
    #[inline]
    pub fn team_of(&self, player: u8) -> Option<u8> {
        if player < self.player_count {
            Some(self.team_of[player as usize])
        } else {
            None
        }
    }
}

impl Default for MultiPlayerInfo {
    #[inline]
    fn default() -> Self {
        Self::two_player_default()
    }
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
    fn two_player_default_is_free_for_all_with_two_players() {
        let info = MultiPlayerInfo::two_player_default();
        assert_eq!(info.player_count, 2);
        assert!(info.is_free_for_all());
        assert_eq!(info.team_of(0), Some(0));
        assert_eq!(info.team_of(1), Some(1));
        assert_eq!(info.team_of(2), None);
    }

    #[test]
    fn free_for_all_constructor_assigns_unique_teams() {
        let info = MultiPlayerInfo::free_for_all(4);
        assert_eq!(info.player_count, 4);
        assert!(info.is_free_for_all());
    }

    #[test]
    fn explicit_team_assignment_is_recognised_as_non_ffa() {
        // 4 players in 2 teams (军棋 4-player layout): {0,2} vs {1,3}.
        let info = MultiPlayerInfo {
            player_count: 4,
            team_of: [0, 1, 0, 1, 0, 0, 0, 0],
            turn_order: [0, 1, 2, 3, 0, 0, 0, 0],
        };
        assert!(!info.is_free_for_all());
        assert_eq!(info.team_of(2), Some(0));
    }

    #[test]
    fn outcome_kind_win_team_round_trips() {
        let outcome = Outcome {
            kind: OutcomeKind::WinTeam(1),
            reason: "flagCaptured".to_owned(),
        };
        match outcome.kind {
            OutcomeKind::WinTeam(t) => assert_eq!(t, 1),
            _ => panic!("expected WinTeam variant"),
        }
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
