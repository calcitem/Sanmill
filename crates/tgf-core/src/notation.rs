// SPDX-License-Identifier: AGPL-3.0-or-later
// Generic notation codec trait shared by every game with textual
// move recording (UCI, SAN, SGF, GTP, …).
//
// `NotationCodec` is intentionally object-safe so callers may store
// `Box<dyn NotationCodec>` without templating, but it remains a
// boundary trait — the search hot path never invokes it.  PGN/SGF
// exporters, debugger UIs, CLI adapters and FRB best-move events
// route through `encode` / `decode` so games gain notation support
// without per-call-site `match action.kind_tag` branches.
//
// Each game ships at least one codec implementation.  Mill ships
// `MillUciCodec` (UCI-style "a4", "a1-a4", "xa4"); future games may
// add additional codecs (e.g. `ChessSanCodec`, `GoSgfCodec`) for the
// same `Action` POD.

use crate::action::Action;
use crate::game_state::GameStateSnapshot;

/// Two-way notation codec.  Implementations are typically zero-sized
/// types backed by topology lookups.
pub trait NotationCodec: Send + Sync {
    /// Stable identifier for the notation flavour, e.g. `"uci"`,
    /// `"san"`, `"sgf"`, `"gtp"`.  Used by tooling that needs to pick
    /// the right codec at runtime.
    fn dialect(&self) -> &str;

    /// Encode `action` against `snap`'s context (some notations need
    /// disambiguation against the position; UCI does not).
    fn encode(&self, snap: &GameStateSnapshot, action: Action) -> String;

    /// Parse `text` into an [`Action`].  Returns `None` for malformed
    /// or unknown input so callers can decide how to surface the error
    /// (UI feedback, log line, fallback to brute-force search …).
    fn decode(&self, snap: &GameStateSnapshot, text: &str) -> Option<Action>;
}
