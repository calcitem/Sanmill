// SPDX-License-Identifier: AGPL-3.0-or-later
// Mill FEN-style position text format adapter.
//
// `MillFenFormat` wraps the existing `MillRules::set_from_fen` /
// `export_fen` round-trip so generic tooling (puzzle loaders, replay
// viewers, save-game IO) can store / restore Mill positions through
// the `tgf_core::PositionTextFormat` trait.
//
// The underlying parser stays in `rules::rules_setup` because it
// touches Mill internals (`MillState`).  This file just exposes the
// trait-shaped surface and keeps `MillRules::set_from_fen` /
// `export_fen` as the single source of truth.

use tgf_core::{GameStateSnapshot, PositionTextFormat};

use crate::rules::MillRules;

/// Mill FEN-style codec.  Carries an `MillRules` value because parse
/// / write rely on the configured rule variant (capture-rule flags,
/// piece counts, …).  `Default` builds a codec around the standard
/// 9-piece variant; callers with custom variants should construct
/// from an explicit `MillRules`.
#[derive(Clone, Debug, Default)]
pub struct MillFenFormat {
    rules: MillRules,
}

impl MillFenFormat {
    /// Build a codec around an explicit Mill rule variant.
    #[inline]
    pub fn new(rules: MillRules) -> Self {
        Self { rules }
    }

    /// Borrow the rule variant the codec is parameterised on.
    #[inline]
    pub fn rules(&self) -> &MillRules {
        &self.rules
    }
}

impl PositionTextFormat for MillFenFormat {
    fn dialect(&self) -> &str {
        "mill.fen"
    }

    fn parse(&self, text: &str) -> Result<GameStateSnapshot, String> {
        let state = self.rules.set_from_fen(text)?;
        Ok(self.rules.encode_state(state))
    }

    fn write(&self, snap: &GameStateSnapshot) -> String {
        let state = MillRules::decode_snapshot(*snap);
        self.rules.export_fen(&state)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tgf_core::GameRules;

    /// Round-trip the initial position through parse + write through
    /// MillRules' default FEN, ensuring the trait-shaped helpers
    /// honour the same contract as the underlying functions.
    #[test]
    fn write_then_parse_round_trips_initial_position() {
        let rules = MillRules::default();
        let fmt = MillFenFormat::new(rules.clone());
        let initial = rules.initial_state(&[]);
        let fen = fmt.write(&initial);
        let parsed = fmt.parse(&fen).expect("FEN parse must succeed");
        assert_eq!(parsed, initial);
    }

    #[test]
    fn parse_rejects_garbage() {
        let fmt = MillFenFormat::default();
        assert!(fmt.parse("not a valid fen").is_err());
        assert!(fmt.parse("").is_err());
    }

    #[test]
    fn dialect_token_is_stable() {
        assert_eq!(MillFenFormat::default().dialect(), "mill.fen");
    }
}
