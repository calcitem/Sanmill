// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

//! Independent correctness audit for mined entries: re-derive each sampled
//! entry's position from its own recorded FEN (not from anything the
//! mining pipeline cached) and verify its `key`/`best_child`/`severity`
//! claims with a *fresh* database + plane query.
//!
//! This intentionally runs on the pre-packed `MineEntry` list (which still
//! carries `fen`) rather than reconstructing a representative board from a
//! packed record's bare `(sector, slot)`. `PerfectHasher::inverse_board`
//! picks *a* canonical representative for a slot, but for positions whose
//! orbit has a non-trivial internal symmetry (a repeating/symmetric piece
//! pattern) more than one representative can be equally valid, and their
//! re-derived child keys do not need to agree slot-for-slot with whichever
//! representative mining happened to visit -- both are correct, but a
//! blind reconstruction can spuriously fail to find `best_child` among
//! *its own* children. The runtime lookup never hits this ambiguity (it
//! only ever computes keys *forward* from concrete, actually-reached game
//! states, exactly like this audit does), so auditing via FEN is both more
//! reliable and closer to what actually matters.

use perfect_db::database::{Database, DatabaseProvider};
use tgf_core::GameRules;
use tgf_mill::{MillRules, MillVariantOptions};

use crate::mill_mine::entry::MineEntry;

pub(crate) struct AuditOutcome {
    pub checked: usize,
    pub failures: Vec<String>,
}

/// Deterministic pseudo-random sample of up to `sample_size` indices into
/// `total`, via a fixed-seed xorshift index permutation.
fn sample_indices(total: usize, sample_size: usize, seed: u64) -> Vec<usize> {
    if sample_size >= total {
        return (0..total).collect();
    }
    let mut state = seed | 1;
    let mut chosen = std::collections::BTreeSet::new();
    while chosen.len() < sample_size {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        chosen.insert((state % total as u64) as usize);
    }
    chosen.into_iter().collect()
}

/// Audit `sample_size` of `entries` against the live database at `db`,
/// additionally re-deriving each sampled entry's proof + steering fields
/// through the same [`super::recompute::derive_child_proof`] (with the
/// same HumanDB context and fusion signal the pack ran with) and requiring
/// an exact match -- a divergence is a blocking failure, not a diagnostic.
#[allow(clippy::too_many_arguments)]
pub(crate) fn audit_entries<P: DatabaseProvider + Clone>(
    entries: &[&MineEntry],
    provider: P,
    options: &MillVariantOptions,
    sample_size: usize,
    seed: u64,
    proofs: &std::collections::HashMap<u64, super::recompute::ChildProof>,
    trap_score_by_key: &std::collections::HashMap<u64, u8>,
    human: Option<&super::human_weight::HumanWeights>,
) -> AuditOutcome {
    let rules = MillRules::new(options.clone());
    let variant = perfect_db::database::DatabaseVariant::from_mill_options(options)
        .expect("audit must run against a supported Perfect DB variant");
    // Sampled entries are spread across many distinct sectors by design (the
    // whole mined range), so the plane/sector caches need enough headroom to
    // avoid rebuilding a multi-second plane on every other sample.
    const AUDIT_CACHE_CAPACITY: usize = 200;
    let mut db = Database::open_variant_with_options(
        provider.clone(),
        variant,
        perfect_db::database::DatabaseOptions::with_sector_cache_capacity(AUDIT_CACHE_CAPACITY),
    )
    .expect("audit failed to open the live database");
    let mut planes = perfect_db::wdl_plane::WdlPlaneCache::with_options(
        provider,
        variant,
        perfect_db::wdl_plane::WdlPlaneCacheOptions {
            plane_cache_capacity: Some(AUDIT_CACHE_CAPACITY),
            cache_dir: None,
        },
    )
    .expect("audit failed to open the live database (plane cache)");

    let mut indices = sample_indices(entries.len(), sample_size.min(entries.len()), seed);
    // Sort by the entry's own (sector-carrying) key so consecutive samples
    // tend to share a sector, keeping the bounded plane/DB caches warm
    // instead of thrashing across the whole mined range in random order.
    indices.sort_by_key(|&index| entries[index].key);
    let mut failures = Vec::new();
    let mut memo = super::recompute::DensityMemo::new();
    let mut rederive_stats = super::recompute::RecomputeStats::default();
    for index in &indices {
        let entry = entries[*index];
        if let Err(message) = audit_one(&rules, options, &mut db, &mut planes, entry) {
            failures.push(message);
            continue;
        }
        // Re-derive the proof in the same context the pack used; the
        // packed fields were already full-scanned against `proofs`, so a
        // proof match here transitively validates the file. (The steering
        // diagnostics are gate inputs, not packed data -- entries in the
        // retained set already passed the gate.)
        let (rederived, _steering_diag) = {
            let mut oracle = super::recompute::PlaneOracle {
                planes: &mut planes,
            };
            super::recompute::derive_child_proof(
                entry,
                &rules,
                options,
                &mut oracle,
                trap_score_by_key,
                human,
                &mut memo,
                &mut rederive_stats,
            )
        };
        match proofs.get(&entry.key) {
            None => failures.push(format!(
                "entry fen {:?}: no proof recorded for key {:#x}",
                entry.fen, entry.key
            )),
            Some(recorded) if *recorded != rederived => failures.push(format!(
                "entry fen {:?}: proof re-derivation diverged (recorded {recorded:?}, \
                 rederived {rederived:?})",
                entry.fen
            )),
            Some(_) => {}
        }
    }
    AuditOutcome {
        checked: indices.len(),
        failures,
    }
}

fn audit_one<P: DatabaseProvider>(
    rules: &MillRules,
    options: &MillVariantOptions,
    db: &mut Database<P>,
    planes: &mut perfect_db::wdl_plane::WdlPlaneCache<P>,
    entry: &MineEntry,
) -> Result<(), String> {
    let mut state = rules
        .set_from_fen(&entry.fen)
        .map_err(|e| format!("entry fen {:?} failed to parse: {e}", entry.fen))?;
    // Same history-free frame as `recompute_entries` and the runtime
    // correction: a live inactivity counter must not make quiet children
    // spuriously terminal while their values are audited.
    state.reset_ply_since_capture();
    let snap = rules.encode_state(state.clone());

    let key = perfect_db::canonical_key(planes, &state, options)
        .ok_or_else(|| format!("entry fen {:?}: root has no canonical key", entry.fen))?;
    if key != entry.key {
        return Err(format!(
            "entry fen {:?}: recomputed key {key} != stored key {}",
            entry.fen, entry.key
        ));
    }

    let root_wdl = perfect_db::resolve_wdl_with_plane(planes, rules, &snap, options)
        .map_err(|e| format!("entry fen {:?}: plane error resolving root: {e}", entry.fen))?
        .ok_or_else(|| format!("entry fen {:?}: root has no plane entry", entry.fen))?;
    // Cross-check the fast plane against the precise database too, so a
    // `WdlPlane::build` regression cannot hide behind this audit.
    let side = state.side_to_move();
    if let Some(query) = perfect_db::query_from_state(&state, options, side)
        && let Ok(Some(precise)) = db.evaluate_outcome(query)
        && i32::from(root_wdl) != precise.wdl()
    {
        return Err(format!(
            "entry fen {:?}: WDL plane ({root_wdl}) disagrees with the precise database ({})",
            entry.fen,
            precise.wdl()
        ));
    }

    let move_wdl = perfect_db::all_move_wdl_fast(planes, rules, &snap, options)
        .map_err(|e| {
            format!(
                "entry fen {:?}: plane error enumerating moves: {e}",
                entry.fen
            )
        })?
        .ok_or_else(|| {
            format!(
                "entry fen {:?}: moves not fully covered by the plane",
                entry.fen
            )
        })?;
    let best_value = move_wdl
        .iter()
        .map(|&(_, v)| v)
        .max()
        .ok_or_else(|| format!("entry fen {:?}: no legal moves (terminal)", entry.fen))?;
    if i32::from(best_value) != i32::from(root_wdl) {
        return Err(format!(
            "entry fen {:?}: best legal move value ({best_value}) != root plane value ({root_wdl})",
            entry.fen
        ));
    }

    let mut best_child_seen = false;
    let mut best_value_matches = false;
    for (action, value) in move_wdl {
        let child_snap = rules.apply(&snap, action);
        let child_state = MillRules::decode_snapshot(child_snap);
        let Some(child_key) = perfect_db::canonical_key(planes, &child_state, options) else {
            continue;
        };
        if child_key == entry.best_child {
            best_child_seen = true;
            best_value_matches = i32::from(value) == i32::from(best_value);
        }
    }
    if !best_child_seen {
        return Err(format!(
            "entry fen {:?}: best_child {} is not a legal reply",
            entry.fen, entry.best_child
        ));
    }
    if !best_value_matches {
        return Err(format!(
            "entry fen {:?}: best_child {} does not preserve the root's value",
            entry.fen, entry.best_child
        ));
    }
    // Severity 0 is a legitimate steering entry (Phase 2's --emit-steering
    // output): it carries no correction urgency, only trap-steering data,
    // and the best_child / optimal-mask consistency checks above plus the
    // caller's proof re-derivation are exactly its audit. Anything outside
    // 0..=2 is corrupt.
    if !(0..=2).contains(&entry.severity) {
        return Err(format!(
            "entry fen {:?}: severity {} outside the expected 0..=2 range",
            entry.fen, entry.severity
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use perfect_db::database::FileDatabaseProvider;

    fn asset_root() -> std::path::PathBuf {
        std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../src/ui/flutter_app/assets/databases")
    }

    #[test]
    fn audit_passes_on_a_freshly_mined_entry() {
        let dir =
            std::env::temp_dir().join(format!("sanmill_mill_audit_test_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let out = dir.join("entries.jsonl");
        let checkpoint = dir.join("checkpoint.json");
        let db = asset_root().to_string_lossy().into_owned();

        crate::mill_mine::run_mill_mine(&[
            "--db".to_string(),
            db.clone(),
            "--out".to_string(),
            out.to_str().unwrap().to_string(),
            "--checkpoint".to_string(),
            checkpoint.to_str().unwrap().to_string(),
            "--max-depth-plies".to_string(),
            "3".to_string(),
            "--budget-engine-calls".to_string(),
            "30".to_string(),
            "--workers".to_string(),
            "2".to_string(),
            "--depth".to_string(),
            "3".to_string(),
        ]);

        let text = std::fs::read_to_string(&out).unwrap();
        assert!(
            !text.trim().is_empty(),
            "expected at least one mined entry to audit"
        );
        let mut entries: Vec<MineEntry> = text
            .lines()
            .map(|line| serde_json::from_str(line).unwrap())
            .collect();

        // Recast the first few mined blunders as severity-0 steering
        // entries (severity 0, placeholder trap_score 0 -- exactly what
        // `mill mine --emit-steering` writes; best_child comes from the
        // same rank_children pick). The audit must admit whichever survive
        // the steering gate: steering entries have no "a losing move must
        // exist" requirement, only the best_child-preserves-value and
        // proof re-derivation checks. min_gap 0 keeps the gate to its
        // structural half (>= 2 side-flipping optimal candidates), which
        // not every recast blunder position satisfies -- hence several.
        let recast = entries.len().min(5);
        for entry in entries.iter_mut().take(recast) {
            entry.severity = 0;
            entry.trap_score = 0;
        }

        // Mirror production: derive proofs through the recompute pipeline
        // (uniform density only -- no HumanDB in this smoke test), then
        // audit the deduplicated survivors against those proofs.
        let options = MillVariantOptions::default();
        let outcome = super::super::recompute::recompute_entries(
            entries,
            &asset_root(),
            &options,
            None,
            super::super::human_weight::HumanWeightConfig::default(),
            0,
        )
        .expect("no human db configured, recompute cannot fail on external data");
        let refs: Vec<&MineEntry> = outcome.entries.iter().collect();
        assert!(
            refs.iter().any(|e| e.severity == 0),
            "at least one severity-0 steering entry must survive the gate to be audited \
             (kept={} dropped_few={} dropped_gap={})",
            outcome.stats.steering_kept,
            outcome.stats.steering_dropped_few_candidates,
            outcome.stats.steering_dropped_low_gap,
        );
        let audited = audit_entries(
            &refs,
            FileDatabaseProvider::new(asset_root()),
            &options,
            refs.len(),
            42,
            &outcome.proofs,
            &outcome.trap_score_by_key,
            outcome.human.as_ref(),
        );
        assert!(
            audited.failures.is_empty(),
            "expected no audit failures (severity-0 must be admitted), got: {:?}",
            audited.failures
        );
        assert_eq!(audited.checked, refs.len());

        let _ = std::fs::remove_dir_all(&dir);
    }
}
