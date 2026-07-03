// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

//! Seed the mining frontier from an NMM_LLM `human_db.sqlite` file.
//!
//! Every distinct human-reached position becomes a frontier seed, with mass
//! equal to how many recorded games passed through it -- the most direct
//! available proxy for "how likely is a real game to reach this spot".
//!
//! `positions.malom_wdl` / `moves.malom_wdl_after` are deliberately *not*
//! used here (or anywhere else in mining) even though they look like a
//! zero-cost way to learn which human moves were mistakes: spot-checking the
//! bundled file shows values that cannot be a side-to-move-perspective
//! perfect-play WDL (e.g. the empty opening board -- a known draw -- is
//! recorded as `'L'`), and neither this repository nor NMM_LLM's own schema
//! notes document the intended convention. Building trap-score priors on a
//! misread sign would be a silent correctness problem, not just a cosmetic
//! one, for a column that turned out to be easy to get wrong for no real
//! upside: [`crate::mill_mine::scoring::trap_score`] derives the same signal
//! (how enticing a mistake is) from this tool's own validated WDL-plane +
//! engine pipeline instead.

use rusqlite::{Connection, OpenFlags};
use tgf_mill::MillRules;

use crate::human_db_fen::fen_from_state_key;

pub(crate) struct HumanSeed {
    pub fen: String,
    pub mass: f64,
}

/// Which phase of `human_db.sqlite`'s recorded games to seed the frontier
/// from. `state_key` encodes phase as its third `|`-separated field
/// (`place`, `move`, or `fly`; see `docs/HUMAN_DATABASE.md`) -- filtering in
/// SQL avoids decoding and then discarding the ~1.6M rows this database
/// typically carries when only one phase is wanted.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum SeedPhase {
    /// Every recorded position, regardless of phase.
    All,
    /// Placing phase only.
    Placing,
    /// Moving and flying phase (every position past the last placement).
    Moving,
}

impl SeedPhase {
    pub(crate) fn parse(value: &str) -> Self {
        match value {
            "placing" | "place" => Self::Placing,
            "moving" | "move" | "fly" | "flying" => Self::Moving,
            _ => Self::All,
        }
    }

    fn sql_where_clause(self) -> &'static str {
        match self {
            Self::All => "1=1",
            Self::Placing => "state_key LIKE '%|place|%'",
            Self::Moving => "(state_key LIKE '%|move|%' OR state_key LIKE '%|fly|%')",
        }
    }
}

/// Load one seed per distinct position in `db_path`'s `positions` table
/// matching `phase`. Rows with a `state_key` this engine cannot decode
/// (malformed, or a position unreachable under the current rule options)
/// are skipped -- the human database is external, user-supplied data, so a
/// bad row should not abort the whole mining run.
pub(crate) fn load_seeds(db_path: &str, rules: &MillRules, phase: SeedPhase) -> Vec<HumanSeed> {
    let conn = Connection::open_with_flags(db_path, OpenFlags::SQLITE_OPEN_READ_ONLY)
        .unwrap_or_else(|e| panic!("[mill-mine] cannot open human db {db_path}: {e}"));
    let query = format!(
        "SELECT state_key, total_games FROM positions WHERE {}",
        phase.sql_where_clause()
    );
    let mut stmt = conn
        .prepare(&query)
        .expect("human DB must contain a positions table");
    let rows = stmt
        .query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, i64>(1)?))
        })
        .expect("failed to query human DB positions");

    let mut seeds = Vec::new();
    let mut skipped = 0_usize;
    for row in rows {
        let (state_key, total_games) = row.expect("failed to read human DB row");
        let Some(fen) = fen_from_state_key(&state_key) else {
            skipped += 1;
            continue;
        };
        if rules.set_from_fen(&fen).is_err() {
            skipped += 1;
            continue;
        }
        seeds.push(HumanSeed {
            fen,
            mass: total_games.max(1) as f64,
        });
    }
    eprintln!(
        "[mill-mine] human seed ({phase:?}): {} positions loaded, {skipped} skipped",
        seeds.len()
    );
    seeds
}

#[cfg(test)]
mod tests {
    use super::*;
    use tgf_mill::MillVariantOptions;

    fn human_db_path() -> String {
        "D:/Repo/NMM_LLM/human_database/human_db.sqlite".to_string()
    }

    #[test]
    fn loads_seeds_from_the_real_human_database_when_present() {
        if !std::path::Path::new(&human_db_path()).exists() {
            eprintln!("[test] human_db.sqlite not present in this environment; skipping");
            return;
        }
        let rules = MillRules::new(MillVariantOptions::default());
        let seeds = load_seeds(&human_db_path(), &rules, SeedPhase::All);
        assert!(
            !seeds.is_empty(),
            "expected at least one decodable seed from the real human database"
        );
        assert!(seeds.iter().all(|s| s.mass >= 1.0));
    }

    #[test]
    fn seed_phase_filters_restrict_which_positions_load() {
        if !std::path::Path::new(&human_db_path()).exists() {
            eprintln!("[test] human_db.sqlite not present in this environment; skipping");
            return;
        }
        let rules = MillRules::new(MillVariantOptions::default());
        let placing = load_seeds(&human_db_path(), &rules, SeedPhase::Placing);
        let moving = load_seeds(&human_db_path(), &rules, SeedPhase::Moving);
        let all = load_seeds(&human_db_path(), &rules, SeedPhase::All);

        assert!(!placing.is_empty());
        assert!(!moving.is_empty());
        // Placing and moving are disjoint phase filters, so together they
        // must not exceed (and in this dataset, should roughly match) the
        // unfiltered total.
        assert!(placing.len() + moving.len() <= all.len());
        assert!(placing.len() + moving.len() >= all.len() - 10);
    }

    #[test]
    fn seed_phase_parses_expected_aliases() {
        assert_eq!(SeedPhase::parse("placing"), SeedPhase::Placing);
        assert_eq!(SeedPhase::parse("place"), SeedPhase::Placing);
        assert_eq!(SeedPhase::parse("moving"), SeedPhase::Moving);
        assert_eq!(SeedPhase::parse("fly"), SeedPhase::Moving);
        assert_eq!(SeedPhase::parse("all"), SeedPhase::All);
        assert_eq!(SeedPhase::parse("garbage"), SeedPhase::All);
    }
}
