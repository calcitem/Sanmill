// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

//! Heuristic priority scores used to rank/select mined entries.
//!
//! Both scores are deliberately built only from signals this tool computes
//! and has already validated (WDL-plane outcomes, engine verdicts, and
//! reach-mass propagated from the frontier) -- see the module docs on
//! `human_seed` for why the human database's own `malom_wdl*` annotation
//! columns are not used here.

/// Priority for the "make traps" runtime mode: how enticing is it to lure an
/// opponent into this exact blunder-prone position?
///
/// Combines how severe the available mistake is (losing a win outright is
/// worse than slipping from a win to a draw) with how likely a real game is
/// to actually reach the position (`mass`, log-scaled since reach counts
/// span many orders of magnitude between a shared opening and a rare deep
/// line). Both terms are clamped into a shared 0..=255 budget so neither one
/// alone can saturate the score.
pub(crate) fn trap_score(severity: i8, mass: f64) -> u8 {
    assert!(
        (1..=2).contains(&severity),
        "trap_score expects the severity of an actual emitted blunder entry (1 or 2), got {severity}"
    );
    const SEVERITY_WEIGHT: f64 = 80.0;
    const MASS_WEIGHT: f64 = 15.0;
    let severity_component = f64::from(severity) * SEVERITY_WEIGHT;
    let mass_component = mass.max(1.0).ln() * MASS_WEIGHT;
    (severity_component + mass_component)
        .clamp(0.0, 255.0)
        .round() as u8
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn higher_severity_scores_higher_at_equal_mass() {
        assert!(trap_score(2, 100.0) > trap_score(1, 100.0));
    }

    #[test]
    fn higher_mass_scores_higher_at_equal_severity() {
        assert!(trap_score(1, 1_000_000.0) > trap_score(1, 1.0));
    }

    #[test]
    fn score_never_exceeds_the_u8_budget() {
        assert_eq!(trap_score(2, f64::MAX), 255);
    }
}
