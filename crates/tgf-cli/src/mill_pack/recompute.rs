// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

//! Re-derive each already-mined entry's `key` and `best_child` from its
//! stored FEN against a live database, decoupling a packed patch's
//! *lookup* and *recommendation* data from whichever canonicalization /
//! `rank_children` behavior was in effect when the (expensive,
//! tier-3-search-backed) blunder was originally *found*.
//!
//! Mining identifies *which* positions are critical -- that needs the full
//! engine search and is worth caching in the mined JSONL. Both the
//! position's canonical key and the recommended reply only need cheap
//! WDL-plane / DB reads, so a fix to the canonical fold (see
//! `PerfectHasher::hash_probe`) or a tuned recommendation heuristic (see
//! `mill_mine::adversary::rank_children`) can be picked up by repacking
//! existing mining output instead of re-running the whole pipeline.

use perfect_db::all_move_wdl_fast;
use perfect_db::database::{Database, DatabaseOptions, DatabaseVariant, FileDatabaseProvider};
use perfect_db::wdl_plane::WdlPlaneCache;
use tgf_mill::{MillRules, MillVariantOptions};

use crate::mill_mine::adversary::rank_children;
use crate::mill_mine::entry::MineEntry;

/// Recompute `entry.key` and `entry.best_child` from `entry.fen` against
/// the live DB at `db_path`, in place, for every entry whose FEN still
/// decodes cleanly under `options`. Entries this cannot re-derive
/// (unexpected FEN, no legal moves, DB does not cover the line) are left
/// untouched -- the packer's own audit pass independently re-verifies the
/// final records regardless, so a stale entry here is caught, not
/// silently shipped.
pub(crate) fn recompute_entries(
    entries: &mut [MineEntry],
    db_path: &std::path::Path,
    options: &MillVariantOptions,
) {
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

    let mut keys_changed = 0_usize;
    let mut children_changed = 0_usize;
    let mut unchanged = 0_usize;
    let mut skipped = 0_usize;
    for entry in entries.iter_mut() {
        let Ok(state) = rules.set_from_fen(&entry.fen) else {
            skipped += 1;
            continue;
        };
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
    }
    eprintln!(
        "[patch-pack] recompute-from-fen: {keys_changed} keys changed, {children_changed} \
         best_children changed, {unchanged} already matched, {skipped} skipped (of {} entries)",
        entries.len()
    );
}
