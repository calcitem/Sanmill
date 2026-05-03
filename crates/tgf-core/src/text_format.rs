// SPDX-License-Identifier: GPL-3.0-or-later
// Generic textual position format trait shared by every game with
// import / export of board positions (FEN for chess / Mill, SGF for
// Go, SFEN for shogi, JSON for puzzles, …).
//
// `PositionTextFormat` is intentionally object-safe so the FRB layer /
// tooling can store `Box<dyn PositionTextFormat>` without templating.
// It is a boundary trait: search code never invokes it.
//
// Each game ships at least one implementation.  Mill ships
// `MillFenFormat` covering the legacy FEN-style serialisation.
// Future games may add `ChessFenFormat`, `GoSgfFormat`, etc. for the
// same `GameStateSnapshot` surface so cross-game tooling (puzzle
// loaders, replay viewers, save-game IO) does not need per-game
// branches.

use crate::game_state::GameStateSnapshot;

/// Two-way textual position format.  Implementations are typically
/// zero-sized values backed by a parser / writer for the dialect.
pub trait PositionTextFormat: Send + Sync {
    /// Stable identifier for the dialect, e.g. `"fen"`, `"sgf"`,
    /// `"sfen"`, `"json.v1"`.  Tools that need to pick a format at
    /// runtime can match on this string.
    fn dialect(&self) -> &str;

    /// Parse `text` into a [`GameStateSnapshot`].  Implementations
    /// return a stable English error string on malformed input; the
    /// shell maps it to a localised message.
    fn parse(&self, text: &str) -> Result<GameStateSnapshot, String>;

    /// Serialise `snap` into the dialect's textual representation.
    fn write(&self, snap: &GameStateSnapshot) -> String;
}
