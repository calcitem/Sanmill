// SPDX-License-Identifier: GPL-3.0-or-later
// Generic UCI adapter contract used by tgf-cli sub-modules.
//
// The trait is reserved for forthcoming game adapters; the existing
// `mill_uci` module ships its own private dispatch table for now.
// Allow dead-code warnings until the trait gains its first non-test
// consumer.

#![allow(dead_code)]
//
// `mill_uci` is currently the only consumer; the trait is a contract
// for future game adapters (Othello, Junqi, …) so they can plug into a
// shared `run_uci_loop` without duplicating the parser dispatch table.
//
// The adapter is intentionally object-safe and consumed via
// `Box<dyn UciAdapter>` so callers do not need to template `main.rs`
// on a concrete game type.

use tgf_core::{Action, GameStateSnapshot};

/// One UCI command line (minus its terminator) split into adapter-
/// specific tokens.  Wrapped so the trait can evolve (e.g. parse stats)
/// without breaking existing implementations.
pub struct UciLine<'a> {
    pub raw: &'a str,
}

/// Outcome of an `apply_setoption` call.  Mirrors the mill_uci internal
/// `SetoptionResult` so future generic dispatch code can treat option
/// handling uniformly.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum UciSetoptionOutcome {
    /// Option was understood and applied (or silently ignored if the
    /// adapter does not act on it).
    Handled,
    /// Token was not a recognised setoption directive.
    UnknownOption,
    /// Option was understood but the supplied value was malformed.
    BadValue,
}

/// Minimal contract every game-specific UCI adapter must implement.
///
/// `Adapter::Options` is the per-game bag of tunables that survive across
/// commands (rule-variant flags, capture toggles, etc.).  The generic
/// loop never touches it — adapters mutate it inside their own
/// `apply_setoption` implementation.
pub trait UciAdapter {
    /// Per-game variant options struct (Mill: `MillVariantOptions`).
    type Options: Clone + Default;

    /// `id name` field reported on UCI handshake.
    fn id_name(&self) -> &str;

    /// Print all UCI options the adapter exposes for `uci` handshake.
    /// Implementations may delegate to a shared helper but the trait
    /// keeps the call here so games can emit additional `option name …`
    /// lines without touching the loop.
    fn print_uci_options(&self, opts: &Self::Options);

    /// Apply one `setoption` line.  Returns the parse outcome so the
    /// loop can log / ignore unknown options consistently.
    fn apply_setoption(&self, opts: &mut Self::Options, line: UciLine<'_>) -> UciSetoptionOutcome;

    /// Parse a `position fen ...` / `position startpos` directive.
    fn parse_position(
        &self,
        opts: &Self::Options,
        line: UciLine<'_>,
    ) -> Result<GameStateSnapshot, String>;

    /// Pretty-print the current snapshot.  Mill prints an ASCII board;
    /// other games are free to dump SGF / FEN / SAN.
    fn print_board(&self, opts: &Self::Options, snap: &GameStateSnapshot);

    /// Convert an `Action` to its UCI move string, returning `None` for
    /// actions that are not encodable in the dialect (e.g. PASS in Mill).
    fn action_to_uci(&self, action: Action) -> Option<String>;

    /// Parse a UCI move string into an `Action` against `snap`'s
    /// context.  Returns `None` for malformed or unknown inputs.
    fn action_from_uci(&self, snap: &GameStateSnapshot, mv: &str) -> Option<Action>;
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Toy adapter for Mill-less environments — used only to verify the
    /// trait is object-safe and the dispatch reads correctly.
    struct ToyAdapter;
    impl UciAdapter for ToyAdapter {
        type Options = ();

        fn id_name(&self) -> &str {
            "toy"
        }
        fn print_uci_options(&self, _opts: &Self::Options) {}
        fn apply_setoption(
            &self,
            _opts: &mut Self::Options,
            _line: UciLine<'_>,
        ) -> UciSetoptionOutcome {
            UciSetoptionOutcome::Handled
        }
        fn parse_position(
            &self,
            _opts: &Self::Options,
            _line: UciLine<'_>,
        ) -> Result<GameStateSnapshot, String> {
            Ok(GameStateSnapshot::default())
        }
        fn print_board(&self, _opts: &Self::Options, _snap: &GameStateSnapshot) {}
        fn action_to_uci(&self, _action: Action) -> Option<String> {
            None
        }
        fn action_from_uci(&self, _snap: &GameStateSnapshot, _mv: &str) -> Option<Action> {
            None
        }
    }

    #[test]
    fn trait_is_object_safe() {
        let adapter: Box<dyn UciAdapter<Options = ()>> = Box::new(ToyAdapter);
        assert_eq!(adapter.id_name(), "toy");
    }

    #[test]
    fn outcome_variants_are_distinct() {
        assert_ne!(UciSetoptionOutcome::Handled, UciSetoptionOutcome::BadValue);
        assert_ne!(
            UciSetoptionOutcome::Handled,
            UciSetoptionOutcome::UnknownOption,
        );
    }
}
