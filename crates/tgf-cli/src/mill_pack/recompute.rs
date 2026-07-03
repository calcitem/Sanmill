// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

//! Re-derive each already-mined entry's `key`, `best_child`, and
//! optimal-set proof from its stored FEN against a live database,
//! decoupling a packed patch's *lookup*, *recommendation*, and *proof*
//! data from whichever canonicalization / `rank_children` behavior was in
//! effect when the (expensive, tier-3-search-backed) blunder was
//! originally *found*.
//!
//! Mining identifies *which* positions are critical -- that needs the full
//! engine search and is worth caching in the mined JSONL. The position's
//! canonical key, the recommended reply, and the per-child optimal-set
//! mask (see [`perfect_db::patch::PackedRecord::optimal_mask`]) only need
//! cheap WDL-plane / DB reads, so a fix to the canonical fold (see
//! `PerfectHasher::hash_probe`) or a tuned recommendation heuristic (see
//! `mill_mine::adversary::rank_children`) can be picked up by repacking
//! existing mining output instead of re-running the whole pipeline.
//!
//! This pass is mandatory since patch format v3: every packed record must
//! carry the optimal-set proof that gates runtime corrections on the
//! chosen move being *provably* value-dropping, and that proof can only be
//! computed against the live database. Entries whose proof cannot be
//! re-derived (unparseable FEN, DB coverage gap) are reported and dropped
//! by the caller.

use std::collections::{BTreeMap, HashMap};

use perfect_db::all_move_wdl_fast;
use perfect_db::database::{Database, DatabaseOptions, DatabaseVariant, FileDatabaseProvider};
use perfect_db::wdl_plane::WdlPlaneCache;
use tgf_core::GameRules;
use tgf_mill::{MillRules, MillVariantOptions};

use crate::mill_mine::adversary::rank_children;
use crate::mill_mine::entry::MineEntry;

/// Per-entry optimal-set proof destined for
/// [`perfect_db::patch::PackedRecord::child_count`] /
/// [`perfect_db::patch::PackedRecord::optimal_mask`].
#[derive(Clone, Copy, Debug)]
pub(crate) struct ChildProof {
    pub child_count: u8,
    pub optimal_mask: u64,
}

/// Recompute `entry.key` / `entry.best_child` from `entry.fen` against the
/// live DB at `db_path`, in place, and derive each entry's optimal-set
/// proof. Returns the proofs keyed by the (re-derived) entry key; entries
/// this cannot re-derive (unexpected FEN, no legal moves, DB does not
/// cover the line) get no proof and must be dropped by the caller -- a
/// v3 record without its proof could never legitimately fire.
pub(crate) fn recompute_entries(
    entries: &mut [MineEntry],
    db_path: &std::path::Path,
    options: &MillVariantOptions,
) -> HashMap<u64, ChildProof> {
    let variant = DatabaseVariant::match_mill_options(options)
        .expect("default MillVariantOptions must match the standard Perfect DB variant");
    let rules = MillRules::new(options.clone());
    let provider = FileDatabaseProvider::new(db_path.to_path_buf());
    let mut db = Database::open_variant_with_options(
        provider.clone(),
        variant,
        DatabaseOptions::with_sector_cache_capacity(64),
    )
    .unwrap_or_else(|e| panic!("[patch-pack] failed to open DB at {db_path:?}: {e}"));
    let mut planes = WdlPlaneCache::new(provider, variant).unwrap_or_else(|e| {
        panic!("[patch-pack] failed to open DB (plane cache) at {db_path:?}: {e}")
    });

    let mut proofs: HashMap<u64, ChildProof> = HashMap::new();
    let mut keys_changed = 0_usize;
    let mut children_changed = 0_usize;
    let mut unchanged = 0_usize;
    let mut skipped = 0_usize;
    for entry in entries.iter_mut() {
        let Ok(mut state) = rules.set_from_fen(&entry.fen) else {
            skipped += 1;
            continue;
        };
        // Work in the same history-free frame the runtime correction uses
        // (see `PatchLookup::correct_action`): a mined FEN can carry a live
        // `ply_since_capture` close to the `n_move_rule` limit, which would
        // make quiet children spuriously terminal here -- dropping them
        // from the child-key list and mis-valuing them as draws -- while
        // the runtime's sanitized replica sees them as ordinary children.
        state.reset_ply_since_capture();
        let Some(key) = perfect_db::canonical_key(&mut planes, &state, options) else {
            skipped += 1;
            continue;
        };
        let snap = rules.encode_state(state);
        let Ok(Some(move_wdl)) = all_move_wdl_fast(&mut planes, &rules, &snap, options) else {
            skipped += 1;
            continue;
        };
        if move_wdl.is_empty() {
            skipped += 1;
            continue;
        }
        let ranked = rank_children(&rules, options, &mut db, &mut planes, &snap, &move_wdl);
        let Some(best) = ranked.optimal.first() else {
            skipped += 1;
            continue;
        };
        let mut any_change = false;
        if key != entry.key {
            entry.key = key;
            keys_changed += 1;
            any_change = true;
        }
        if best.key != entry.best_child {
            entry.best_child = best.key;
            children_changed += 1;
            any_change = true;
        }
        if !any_change {
            unchanged += 1;
        }

        // Optimal-set proof: per distinct child canonical key (ascending --
        // the exact index space `PatchLookup::correct_action` rebuilds via
        // `perfect_db::patch::sorted_distinct_child_keys`), mark the
        // children whose DB value equals the position's best value.
        let best_value = move_wdl
            .iter()
            .map(|&(_, value)| value)
            .max()
            .expect("move_wdl is non-empty");
        let mut value_by_child_key: BTreeMap<u64, i8> = BTreeMap::new();
        for &(action, value) in &move_wdl {
            let child_snap = rules.apply(&snap, action);
            let child_state = MillRules::decode_snapshot(child_snap);
            if let Some(child_key) = perfect_db::canonical_key(&mut planes, &child_state, options)
                && let Some(previous) = value_by_child_key.insert(child_key, value)
            {
                assert_eq!(
                    previous, value,
                    "two actions reaching the same canonical child must share one \
                     DB value (fen {})",
                    entry.fen
                );
            }
        }
        assert!(
            value_by_child_key.len() <= 64,
            "optimal mask only holds 64 distinct children, got {} (fen {})",
            value_by_child_key.len(),
            entry.fen
        );
        let mut optimal_mask = 0_u64;
        for (index, value) in value_by_child_key.values().enumerate() {
            if *value == best_value {
                optimal_mask |= 1_u64 << index;
            }
        }
        let best_child_index = value_by_child_key
            .keys()
            .position(|&child_key| child_key == entry.best_child)
            .unwrap_or_else(|| {
                panic!(
                    "recorded best_child must be one of the position's children (fen {})",
                    entry.fen
                )
            });
        assert!(
            optimal_mask & (1_u64 << best_child_index) != 0,
            "recorded best_child must itself be proven optimal (fen {})",
            entry.fen
        );
        proofs.insert(
            entry.key,
            ChildProof {
                child_count: value_by_child_key.len() as u8,
                optimal_mask,
            },
        );
    }
    eprintln!(
        "[patch-pack] recompute-from-fen: {keys_changed} keys changed, {children_changed} \
         best_children changed, {unchanged} already matched, {skipped} skipped (of {} entries); \
         {} optimal-set proofs derived",
        entries.len(),
        proofs.len()
    );
    proofs
}
