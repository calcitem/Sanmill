// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

//! HumanDB behavior weighting for the v4 trap nibbles: aggregate the
//! `moves` table (per-position human reply frequencies) into canonical-key
//! indexed response maps the packer's density pass can consult.
//!
//! Frequencies come from the human database; correctness of every reply
//! still comes from the WDL plane (the database's own `malom_wdl*` columns
//! are untrusted -- see `crate::mill_mine::human_seed`'s module docs).
//!
//! Loading walks raw rows (no SQL-side aggregation: `SUM/GROUP BY` would
//! swallow the `total <= 0` rows this loader must bucket), decodes each
//! `state_key` in its own D4 orientation, parses the notation there via
//! the shared `tgf_mill::human_db_codec`, applies the full turn, and only
//! then canonicalizes the reached target. A combined mill turn
//! (`d6-d7xa4`) feeds **both** maps: the full-turn endpoint into
//! [`HumanWeights::turn`] (so a "good base + bad capture" human mistake is
//! visible at the settled parent), and the capture segment into
//! [`HumanWeights::step`] under the synthesized pending-removal key (the
//! database has no `state_key` for mid-removal positions; the key is
//! derived by applying the base move).

use std::collections::HashMap;
use std::path::Path;

use rusqlite::{Connection, OpenFlags};
use tgf_core::{GameRules, GameStateSnapshot, OutcomeKind};
use tgf_mill::human_db_codec::{
    HumanTurn, HumanTurnError, fen_from_state_key, parse_human_turn_notation,
};
use tgf_mill::rules::MillState;
use tgf_mill::{MillRules, MillVariantOptions};

use super::recompute::WdlOracle;

/// Where a human reply landed, from the queried parent's point of view.
///
/// This is a pack-time aggregation type only: it never enters the patch
/// file format (v4 records store just `trap_score_mask` +
/// `optimal_trap_nibbles`).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub(crate) enum ResponseTarget {
    /// A live settled position. `sign_to_parent` calibrates the plane's
    /// folded-perspective WDL back to the parent's side to move:
    /// `reply_value = sign_to_parent * wdl_by_canonical_key(key)`.
    Key { key: u64, sign_to_parent: i8 },
    /// The turn ended the game; the value is already from the parent's
    /// side to move.
    Terminal(i8),
}

/// Aggregated human replies for one parent position.
#[derive(Clone, Debug, Default)]
pub(crate) struct HumanResponses {
    pub targets: HashMap<ResponseTarget, u64>,
    /// Weight of replies that applied fine but whose endpoint could not be
    /// scored (no canonical key / missing plane sector). Counts into
    /// `n_raw` but never into `n_scored`.
    pub unresolved_total: u64,
}

impl HumanResponses {
    pub fn scored_total(&self) -> u64 {
        self.targets.values().copied().sum()
    }

    pub fn raw_total(&self) -> u64 {
        self.scored_total() + self.unresolved_total
    }
}

/// Raw one-turn human expected value for a parent, in that parent's
/// side-to-move perspective. This is intentionally not shrinkage-blended
/// or quantized; the replay validator uses it to measure the behavior
/// signal as observed in HumanDB.
#[cfg(test)]
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct HumanExpectedValue {
    pub value: f64,
    pub n_scored: u64,
    pub n_raw: u64,
    pub coverage: f64,
}

#[cfg(test)]
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct HumanSampleStats {
    pub n_scored: u64,
    pub n_raw: u64,
    pub coverage: f64,
}

/// Tuning knobs for the behavior weighting (see the packer CLI flags).
#[derive(Clone, Copy, Debug)]
pub(crate) struct HumanWeightConfig {
    pub min_samples: u64,
    pub min_coverage: f64,
    pub shrinkage_k: f64,
    pub allow_lossy: bool,
}

impl Default for HumanWeightConfig {
    fn default() -> Self {
        Self {
            min_samples: 10,
            min_coverage: 0.8,
            shrinkage_k: 30.0,
            allow_lossy: false,
        }
    }
}

/// Load-time diagnostics (row counts are secondary; every rate that gates
/// behavior is weighted by `total`).
///
/// Coverage is tracked per aggregation map: `turn_*` counts each decodable
/// row at most once (so `turn_scored_weight + turn_unresolved_weight`
/// plus the failure buckets exactly partitions `decodable_weight`), while
/// `step_*` counts only the capture segments of compound rows re-recorded
/// under their synthesized mid-removal parents -- a deliberate second
/// booking of that weight, reported separately so neither map's coverage
/// can exceed the decodable total.
#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct HumanWeightStats {
    pub rows: u64,
    pub non_positive_total_rows: u64,
    pub state_key_undecodable_rows: u64,
    pub state_key_undecodable_weight: u64,
    pub base_invalid_rows: u64,
    pub base_invalid_weight: u64,
    pub capture_invalid_rows: u64,
    pub capture_invalid_weight: u64,
    pub unexpected_capture_rows: u64,
    pub unexpected_capture_weight: u64,
    pub missing_capture_rows: u64,
    pub missing_capture_weight: u64,
    pub turn_unresolved_rows: u64,
    pub turn_unresolved_weight: u64,
    pub step_unresolved_rows: u64,
    pub step_unresolved_weight: u64,
    pub compound_rows: u64,
    /// Weight of every decodable compound (mill + capture) row, scored or
    /// not.
    pub compound_decodable_weight: u64,
    /// Weight of compound rows whose full-turn endpoint actually scored
    /// into the turn map (the numerator of `compound_turn_weight_share`).
    pub compound_scored_weight: u64,
    pub turn_scored_weight: u64,
    pub step_scored_weight: u64,
    pub decodable_weight: u64,
}

impl HumanWeightStats {
    pub fn parser_invalid_weight(&self) -> u64 {
        self.base_invalid_weight + self.capture_invalid_weight + self.unexpected_capture_weight
    }

    /// Parser-invalid share among rows whose position decoded, weighted by
    /// `total` -- the hard-failure gate for a systematically broken
    /// notation parser or coordinate mapping.
    pub fn parser_invalid_rate(&self) -> f64 {
        if self.decodable_weight == 0 {
            0.0
        } else {
            self.parser_invalid_weight() as f64 / self.decodable_weight as f64
        }
    }

    /// Share of the turn-scored weight contributed by combined mill turns
    /// (scored weight over scored weight, so invalid/unresolved compound
    /// rows never inflate the numerator) -- the first lead when behavior
    /// weighting moves (or fails to move) the nibbles.
    pub fn compound_turn_weight_share(&self) -> f64 {
        if self.turn_scored_weight == 0 {
            0.0
        } else {
            self.compound_scored_weight as f64 / self.turn_scored_weight as f64
        }
    }

    /// Internal invariant: the turn-side buckets exactly partition the
    /// decodable weight, and each map's coverage stays within its feed.
    /// Panics on violation (this is bookkeeping, not external data).
    pub fn assert_partition(&self) {
        let turn_partition = self.parser_invalid_weight()
            + self.missing_capture_weight
            + self.turn_scored_weight
            + self.turn_unresolved_weight;
        assert_eq!(
            turn_partition, self.decodable_weight,
            "turn-side buckets must exactly partition the decodable weight"
        );
        assert!(
            self.turn_scored_weight <= self.decodable_weight
                && self.step_scored_weight <= self.decodable_weight,
            "per-map scored coverage can never exceed the decodable weight"
        );
        assert!(
            self.compound_scored_weight <= self.compound_decodable_weight,
            "scored compound weight is a subset of decodable compound weight"
        );
        assert!(
            self.step_scored_weight + self.step_unresolved_weight <= self.compound_scored_weight,
            "step-side coverage cannot exceed the compound weight that feeds it"
        );
    }
}

/// The aggregated behavior data, or the reason it is disabled.
pub(crate) struct HumanWeights {
    /// Full-turn endpoints per settled parent canonical key.
    pub turn: HashMap<u64, HumanResponses>,
    /// Capture-segment endpoints per synthesized mid-removal parent key.
    pub step: HashMap<u64, HumanResponses>,
    /// A concrete HumanDB-frame representative for each settled parent.
    /// This is test-only: offline validators need to enumerate a parent
    /// position's legal optimal children, while production pack scoring
    /// only needs the response maps above.
    #[cfg(test)]
    pub parent_snap_by_key: HashMap<u64, GameStateSnapshot>,
    pub config: HumanWeightConfig,
    pub stats: HumanWeightStats,
}

const PARSER_INVALID_HARD_LIMIT: f64 = 0.05;

/// Column-level schema validation: the scan below reads exactly these
/// columns, so their absence must fail before any row work starts.
fn validate_moves_schema(conn: &Connection, db_path: &Path) -> Result<(), String> {
    let mut stmt = conn
        .prepare("PRAGMA table_info(moves)")
        .map_err(|e| format!("human db {db_path:?}: cannot inspect schema: {e}"))?;
    let columns: Vec<String> = stmt
        .query_map([], |row| row.get::<_, String>(1))
        .map_err(|e| format!("human db {db_path:?}: cannot list columns: {e}"))?
        .collect::<Result<_, _>>()
        .map_err(|e| format!("human db {db_path:?}: cannot read columns: {e}"))?;
    for required in ["state_key", "notation", "total"] {
        if !columns.iter().any(|c| c == required) {
            return Err(format!(
                "human db {db_path:?}: `moves` table is missing required column `{required}` \
                 (found: {columns:?})"
            ));
        }
    }
    Ok(())
}

/// Aggregate `db_path`'s `moves` table.
///
/// Broken *external data* -- a missing file, unreadable database, wrong
/// schema, or a parser-invalid share above the hard limit -- is an `Err`
/// (the CLI caller reports it and exits nonzero): a configured but
/// unusable database must never silently degrade to uniform density, and
/// must not present as an engine crash either. Panics/asserts inside the
/// aggregation remain reserved for internal invariant violations (e.g. a
/// broken plane perspective convention).
pub(crate) fn load_human_weights(
    db_path: &Path,
    rules: &MillRules,
    options: &MillVariantOptions,
    oracle: &mut dyn WdlOracle,
    config: HumanWeightConfig,
) -> Result<HumanWeights, String> {
    if !db_path.is_file() {
        return Err(format!(
            "human db does not exist: {db_path:?} (unset SANMILL_HUMAN_DB or pass \
             --disable-human-weighting to run without behavior weighting)"
        ));
    }
    let conn = Connection::open_with_flags(db_path, OpenFlags::SQLITE_OPEN_READ_ONLY)
        .map_err(|e| format!("cannot open human db {db_path:?}: {e}"))?;
    validate_moves_schema(&conn, db_path)?;

    let mut stmt = conn
        .prepare("SELECT state_key, notation, total FROM moves")
        .map_err(|e| format!("human db {db_path:?}: cannot prepare scan: {e}"))?;
    let rows = stmt
        .query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, i64>(2)?,
            ))
        })
        .map_err(|e| format!("human db {db_path:?}: scan failed: {e}"))?;

    let mut weights = HumanWeights {
        turn: HashMap::new(),
        step: HashMap::new(),
        #[cfg(test)]
        parent_snap_by_key: HashMap::new(),
        config,
        stats: HumanWeightStats::default(),
    };
    // Decoded parent states repeat heavily (one row per notation); cache
    // the expensive state_key -> state decoding per distinct key string.
    let mut parent_cache: HashMap<String, Option<(GameStateSnapshot, u64)>> = HashMap::new();

    for row in rows {
        let (state_key, notation, total) =
            row.unwrap_or_else(|e| panic!("[patch-pack] human db row read failed: {e}"));
        weights.stats.rows += 1;
        if total <= 0 {
            weights.stats.non_positive_total_rows += 1;
            continue;
        }
        let total = u64::try_from(total).expect("positive i64 fits u64");

        let parent = match parent_cache.get(&state_key) {
            Some(cached) => *cached,
            None => {
                let decoded = (|| {
                    let fen = fen_from_state_key(&state_key)?;
                    let state = rules.set_from_fen(&fen).ok()?;
                    let snap = rules.encode_state(state.clone());
                    let key = oracle.keys().canonical_key(&state, options)?;
                    Some((snap, key))
                })();
                parent_cache.insert(state_key.clone(), decoded);
                decoded
            }
        };
        let Some((parent_snap, parent_key)) = parent else {
            weights.stats.state_key_undecodable_rows += 1;
            weights.stats.state_key_undecodable_weight =
                checked_add(weights.stats.state_key_undecodable_weight, total);
            continue;
        };
        weights.stats.decodable_weight = checked_add(weights.stats.decodable_weight, total);
        #[cfg(test)]
        weights
            .parent_snap_by_key
            .entry(parent_key)
            .or_insert(parent_snap);
        let parent_state = MillRules::decode_snapshot(parent_snap);

        // Routing table (see the plan): HumanDB parents are never
        // pending-removal, so a bare capture row can only be unexpected.
        if notation.trim().starts_with('x') {
            weights.stats.unexpected_capture_rows += 1;
            weights.stats.unexpected_capture_weight =
                checked_add(weights.stats.unexpected_capture_weight, total);
            continue;
        }

        match parse_human_turn_notation(rules, &parent_snap, &notation) {
            Err(HumanTurnError::BaseInvalid) => {
                weights.stats.base_invalid_rows += 1;
                weights.stats.base_invalid_weight =
                    checked_add(weights.stats.base_invalid_weight, total);
            }
            Err(HumanTurnError::CaptureInvalid) => {
                weights.stats.capture_invalid_rows += 1;
                weights.stats.capture_invalid_weight =
                    checked_add(weights.stats.capture_invalid_weight, total);
            }
            Err(HumanTurnError::UnexpectedCapture) => {
                weights.stats.unexpected_capture_rows += 1;
                weights.stats.unexpected_capture_weight =
                    checked_add(weights.stats.unexpected_capture_weight, total);
            }
            Ok(HumanTurn::CaptureOnly(_)) => {
                // Unreachable for non-pending parents (the `x` prefix is
                // routed above), kept for completeness.
                weights.stats.unexpected_capture_rows += 1;
                weights.stats.unexpected_capture_weight =
                    checked_add(weights.stats.unexpected_capture_weight, total);
            }
            Ok(HumanTurn::BaseOnly(base)) => {
                let reached = rules.apply(&parent_snap, base);
                let reached_state = MillRules::decode_snapshot(reached);
                let side = reached_state.side_to_move();
                if side >= 0
                    && side == parent_state.side_to_move()
                    && reached_state.pending_removals()[side as usize] > 0
                {
                    // A mill formed but the database row carries no capture
                    // segment: the human's actual removal is unknown, and
                    // attributing the best removal would hide exactly the
                    // capture mistakes this weighting exists to see.
                    weights.stats.missing_capture_rows += 1;
                    weights.stats.missing_capture_weight =
                        checked_add(weights.stats.missing_capture_weight, total);
                    continue;
                }
                record_response(
                    &mut weights.turn,
                    &mut weights.stats,
                    ResponseScope::Turn,
                    parent_key,
                    &parent_state,
                    &reached,
                    total,
                    rules,
                    options,
                    oracle,
                );
            }
            Ok(HumanTurn::BaseThenCapture { base, capture }) => {
                weights.stats.compound_rows += 1;
                weights.stats.compound_decodable_weight =
                    checked_add(weights.stats.compound_decodable_weight, total);
                let mid_snap = rules.apply(&parent_snap, base);
                let mid_state = MillRules::decode_snapshot(mid_snap);
                let mid_key = perfect_db::mid_removal_key(&mid_state)
                    .expect("a pending-removal state must produce a mid-removal key");
                let reached = rules.apply(&mid_snap, capture);

                // Full-turn endpoint for the settled parent...
                let scored = record_response(
                    &mut weights.turn,
                    &mut weights.stats,
                    ResponseScope::Turn,
                    parent_key,
                    &parent_state,
                    &reached,
                    total,
                    rules,
                    options,
                    oracle,
                );
                // ...and the capture segment for the synthesized
                // mid-removal parent (Phase 2's steering data; aggregated
                // now so the maps stay complete). Only rows whose turn
                // endpoint scored feed the step map, so its coverage is
                // bounded by `compound_scored_weight`.
                if scored {
                    weights.stats.compound_scored_weight =
                        checked_add(weights.stats.compound_scored_weight, total);
                    let _ = record_response(
                        &mut weights.step,
                        &mut weights.stats,
                        ResponseScope::Step,
                        mid_key,
                        &mid_state,
                        &reached,
                        total,
                        rules,
                        options,
                        oracle,
                    );
                }
            }
        }
    }
    weights.stats.assert_partition();

    let rate = weights.stats.parser_invalid_rate();
    if rate > PARSER_INVALID_HARD_LIMIT {
        if !weights.config.allow_lossy {
            return Err(format!(
                "human db {db_path:?}: {:.2}% of the decodable move weight failed notation \
                 parsing (limit {:.0}%) -- the parser or coordinate mapping is likely broken; \
                 pass --allow-human-db-lossy to proceed anyway",
                rate * 100.0,
                PARSER_INVALID_HARD_LIMIT * 100.0
            ));
        }
        eprintln!(
            "[patch-pack] WARNING: proceeding with lossy human db (parser-invalid rate {:.2}%)",
            rate * 100.0
        );
    }
    Ok(weights)
}

/// Which aggregation map a response is being recorded into; keeps the
/// coverage bookkeeping per map so neither side can double-count into a
/// shared total.
#[derive(Clone, Copy)]
enum ResponseScope {
    Turn,
    Step,
}

/// Value a reached snapshot from `parent_state`'s side and record it under
/// `parent_key`. Returns whether the endpoint was scorable.
#[allow(clippy::too_many_arguments)]
fn record_response(
    map: &mut HashMap<u64, HumanResponses>,
    stats: &mut HumanWeightStats,
    scope: ResponseScope,
    parent_key: u64,
    parent_state: &MillState,
    reached: &GameStateSnapshot,
    total: u64,
    rules: &MillRules,
    options: &MillVariantOptions,
    oracle: &mut dyn WdlOracle,
) -> bool {
    let entry = map.entry(parent_key).or_default();
    match response_target(parent_state, reached, rules, options, oracle) {
        Some(target) => {
            let slot = entry.targets.entry(target).or_insert(0);
            *slot = checked_add(*slot, total);
            match scope {
                ResponseScope::Turn => {
                    stats.turn_scored_weight = checked_add(stats.turn_scored_weight, total);
                }
                ResponseScope::Step => {
                    stats.step_scored_weight = checked_add(stats.step_scored_weight, total);
                }
            }
            true
        }
        None => {
            entry.unresolved_total = checked_add(entry.unresolved_total, total);
            match scope {
                ResponseScope::Turn => {
                    stats.turn_unresolved_rows += 1;
                    stats.turn_unresolved_weight = checked_add(stats.turn_unresolved_weight, total);
                }
                ResponseScope::Step => {
                    stats.step_unresolved_rows += 1;
                    stats.step_unresolved_weight = checked_add(stats.step_unresolved_weight, total);
                }
            }
            false
        }
    }
}

/// Classify a reached snapshot as a [`ResponseTarget`], calibrating the
/// plane-perspective sign for live positions.
///
/// The sign algorithm is fixed (do not "simplify" it by guessing the
/// plane's folding convention):
/// 1. `direct` = the reached position's WDL from its own side to move
///    (`resolve_wdl_with_plane`);
/// 2. `raw` = the plane value stored behind the reached position's
///    canonical key;
/// 3. `direct == raw` -> `sign_vs_reached = +1`; `direct == -raw` with
///    `raw != 0` -> `-1`; both zero -> `+1`; anything else means the
///    perspective convention broke and must fail loudly;
/// 4. `flip` = `+1` when the reached side to move equals the parent's,
///    else `-1`;
/// 5. `sign_to_parent = flip * sign_vs_reached`.
fn response_target(
    parent_state: &MillState,
    reached: &GameStateSnapshot,
    rules: &MillRules,
    options: &MillVariantOptions,
    oracle: &mut dyn WdlOracle,
) -> Option<ResponseTarget> {
    let parent_side = parent_state.side_to_move();
    match rules.outcome(reached).kind {
        OutcomeKind::Win(winner) => {
            let value = if i16::from(winner) == i16::from(parent_side) {
                1
            } else {
                -1
            };
            return Some(ResponseTarget::Terminal(value));
        }
        OutcomeKind::Draw => return Some(ResponseTarget::Terminal(0)),
        OutcomeKind::Ongoing => {}
        other @ (OutcomeKind::WinTeam(_) | OutcomeKind::Abandoned) => {
            panic!("Mill outcomes never produce {other:?}")
        }
    }

    let reached_state = MillRules::decode_snapshot(*reached);
    let key = oracle.keys().canonical_key(&reached_state, options)?;
    if key & perfect_db::wdl_plane::MID_REMOVAL_KEY_TAG != 0 {
        // Mid-removal endpoints only occur for missing-capture rows, which
        // the caller already bucketed; a tagged key here is a routing bug.
        unreachable!("turn endpoints are settled positions or terminal");
    }
    let direct = oracle.direct_wdl(rules, reached, options)?;
    let raw = oracle.raw_wdl_by_key(key)?;
    let sign_vs_reached = combine_sign(direct, raw);
    let flip = if reached_state.side_to_move() == parent_side {
        1_i8
    } else {
        -1_i8
    };
    Some(ResponseTarget::Key {
        key,
        sign_to_parent: flip * sign_vs_reached,
    })
}

/// Step 3 of the sign calibration: relate the reached position's own-side
/// WDL (`direct`) to the plane's stored value for its canonical key
/// (`raw`). Any combination other than equal / negated / both-zero means
/// the perspective convention broke somewhere and must fail loudly rather
/// than ship a silently flipped trap signal.
pub(crate) fn combine_sign(direct: i8, raw: i8) -> i8 {
    if direct == raw {
        1
    } else if raw != 0 && direct == -raw {
        -1
    } else {
        panic!("[patch-pack] plane perspective convention broke: direct {direct} vs raw {raw}");
    }
}

/// Pure density core: weighted blunder density of a reply distribution,
/// `sum(weight * max(0, best - reply)) / (2 * sum(weight))`, with every
/// value already in the parent's side-to-move perspective.
pub(crate) fn weighted_blunder_density(best_value: i8, replies: &[(i8, u64)]) -> f64 {
    let total: u64 = replies.iter().map(|&(_, weight)| weight).sum();
    assert!(total > 0, "caller gates on a non-empty scored sample");
    let severity_sum: f64 = replies
        .iter()
        .map(|&(value, weight)| {
            let severity = i32::from(best_value) - i32::from(value);
            if severity > 0 {
                weight as f64 * f64::from(severity)
            } else {
                0.0
            }
        })
        .sum();
    severity_sum / (2.0 * total as f64)
}

/// Pure shrinkage blend: pull the observed human density toward the
/// uniform density by `k` pseudo-samples.
pub(crate) fn shrunk_density(
    density_human: f64,
    density_uniform: f64,
    n_scored: u64,
    k: f64,
) -> f64 {
    assert!(
        k >= 0.0,
        "shrinkage strength is a non-negative sample count"
    );
    (n_scored as f64 * density_human + k * density_uniform) / (n_scored as f64 + k)
}

fn checked_add(a: u64, b: u64) -> u64 {
    a.checked_add(b)
        .expect("human db weight accumulation overflowed u64")
}

impl HumanWeights {
    /// Raw one-turn expected value for `parent_key`, in the side-to-move
    /// perspective of that parent. Returns `None` when the parent has no
    /// HumanDB rows or fails the same sample/coverage gates used by
    /// behavior weighting.
    #[cfg(test)]
    pub(crate) fn raw_ev(
        &self,
        parent_key: u64,
        oracle: &mut dyn WdlOracle,
    ) -> Option<HumanExpectedValue> {
        let responses = self.responses_for(parent_key)?;
        let replies = self.scored_replies(responses, oracle);
        raw_ev_from_replies(
            &replies,
            responses.unresolved_total,
            self.config.min_samples,
            self.config.min_coverage,
        )
    }

    #[cfg(test)]
    pub(crate) fn sample_stats(&self, parent_key: u64) -> Option<HumanSampleStats> {
        sample_stats_from_responses(self.responses_for(parent_key)?)
    }

    /// Print the load-time diagnostics block.
    pub fn print_stats(&self) {
        let s = &self.stats;
        eprintln!(
            "[patch-pack] human weighting: rows={} decodable_weight={} | turn: scored={} \
             unresolved={} | step: scored={} unresolved={} | compound: decodable={} scored={} \
             share_of_turn={:.3}",
            s.rows,
            s.decodable_weight,
            s.turn_scored_weight,
            s.turn_unresolved_weight,
            s.step_scored_weight,
            s.step_unresolved_weight,
            s.compound_decodable_weight,
            s.compound_scored_weight,
            s.compound_turn_weight_share()
        );
        eprintln!(
            "[patch-pack] human buckets: total<=0 rows={} | state_key undecodable rows={} w={} | \
             base_invalid rows={} w={} | capture_invalid rows={} w={} | unexpected_capture \
             rows={} w={} | missing_capture rows={} w={} | turn_unresolved rows={} | \
             step_unresolved rows={} | parser_invalid_rate={:.4}",
            s.non_positive_total_rows,
            s.state_key_undecodable_rows,
            s.state_key_undecodable_weight,
            s.base_invalid_rows,
            s.base_invalid_weight,
            s.capture_invalid_rows,
            s.capture_invalid_weight,
            s.unexpected_capture_rows,
            s.unexpected_capture_weight,
            s.missing_capture_rows,
            s.missing_capture_weight,
            s.turn_unresolved_rows,
            s.step_unresolved_rows,
            s.parser_invalid_rate()
        );
        if s.decodable_weight > 0
            && s.missing_capture_weight as f64 / s.decodable_weight as f64 > 0.02
        {
            eprintln!(
                "[patch-pack] WARNING (high priority): missing_capture weight share {:.2}% -- \
                 mill-forming turns are being systematically dropped from the behavior signal; \
                 inspect the human database's notation conventions",
                s.missing_capture_weight as f64 / s.decodable_weight as f64 * 100.0
            );
        }
    }

    /// Behavior-weighted density for the position keyed by `parent_key`
    /// (the side to move there is the "opponent" being lured), given that
    /// position's DB-perfect `best_value` and its uniform step-level
    /// density. Returns the blended density, or `None` when the sample
    /// gates fail (callers then use the uniform density unchanged).
    pub fn behavior_density(
        &self,
        parent_key: u64,
        best_value: i8,
        density_uniform: f64,
        oracle: &mut dyn WdlOracle,
    ) -> Option<f64> {
        let responses = self.responses_for(parent_key)?;
        let n_scored = responses.scored_total();
        let n_raw = responses.raw_total();
        if n_scored < self.config.min_samples {
            return None;
        }
        if (n_scored as f64) < self.config.min_coverage * n_raw as f64 {
            return None;
        }

        // The only oracle touch-point: resolve Key targets to values in
        // the parent's perspective; the math below is pure.
        let replies = self.scored_replies(responses, oracle);
        let density_human = weighted_blunder_density(best_value, &replies);
        Some(shrunk_density(
            density_human,
            density_uniform,
            n_scored,
            self.config.shrinkage_k,
        ))
    }

    fn responses_for(&self, parent_key: u64) -> Option<&HumanResponses> {
        let map = if parent_key & perfect_db::wdl_plane::MID_REMOVAL_KEY_TAG != 0 {
            &self.step
        } else {
            &self.turn
        };
        map.get(&parent_key)
    }

    fn scored_replies(
        &self,
        responses: &HumanResponses,
        oracle: &mut dyn WdlOracle,
    ) -> Vec<(i8, u64)> {
        responses
            .targets
            .iter()
            .map(|(target, weight)| (reply_value_from_target(*target, oracle), *weight))
            .collect()
    }
}

#[cfg(test)]
fn sample_stats_from_responses(responses: &HumanResponses) -> Option<HumanSampleStats> {
    let n_scored = responses.scored_total();
    let n_raw = responses.raw_total();
    if n_raw == 0 {
        return None;
    }
    Some(HumanSampleStats {
        n_scored,
        n_raw,
        coverage: n_scored as f64 / n_raw as f64,
    })
}

pub(crate) fn reply_value_from_target(target: ResponseTarget, oracle: &mut dyn WdlOracle) -> i8 {
    match target {
        ResponseTarget::Terminal(value) => value,
        ResponseTarget::Key {
            key,
            sign_to_parent,
        } => {
            let raw = oracle
                .raw_wdl_by_key(key)
                .expect("scored targets resolved at aggregation time");
            sign_to_parent * raw
        }
    }
}

#[cfg(test)]
pub(crate) fn raw_ev_from_replies(
    replies: &[(i8, u64)],
    unresolved_total: u64,
    min_samples: u64,
    min_coverage: f64,
) -> Option<HumanExpectedValue> {
    let n_scored: u64 = replies.iter().map(|&(_, weight)| weight).sum();
    let n_raw = n_scored
        .checked_add(unresolved_total)
        .expect("human EV sample totals overflowed u64");
    if n_scored < min_samples {
        return None;
    }
    assert!(n_raw > 0, "scored samples imply non-zero raw samples");
    let coverage = n_scored as f64 / n_raw as f64;
    if coverage < min_coverage {
        return None;
    }
    let weighted_sum: f64 = replies
        .iter()
        .map(|&(value, weight)| f64::from(value) * weight as f64)
        .sum();
    Some(HumanExpectedValue {
        value: weighted_sum / n_scored as f64,
        n_scored,
        n_raw,
        coverage,
    })
}

#[cfg(test)]
#[path = "human_weight_tests.rs"]
mod tests;
