// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

//! Stages 1-4 of the v4 packing pipeline: re-derive every entry's `key`,
//! `best_child`, and optimal-set proof from its stored FEN against a live
//! database, deduplicate, and derive the per-record trap-steering nibbles
//! (uniform blunder density, optionally blended with HumanDB behavior
//! weighting, fused with deduplicated child-entry trap scores).
//!
//! The stage order is load-bearing and must not be shuffled:
//!
//! 1. per entry: re-derive `key` / `best_child` (and overwrite severity-0
//!    `trap_score` from the position's own density);
//! 2. drop underivable entries, then deduplicate by key through the single
//!    authoritative [`dedup_entries`];
//! 3. freeze `trap_score_by_key` from the deduplicated, pre-budget set --
//!    entries dropped later (budget) still contribute their signal here;
//! 4. per unique entry: derive the packed proof + steering fields via
//!    [`derive_child_proof`] -- the one derivation the packer, the packed
//!    -field validation, and the audit's re-derivation all share.
//!
//! WDL access goes through the [`WdlOracle`] trait so the blocker unit
//! tests can drive the exact same derivation with a deterministic value
//! table instead of hunting real databases for lucky positions; production
//! code uses [`PlaneOracle`] over the live [`WdlPlaneCache`].

use std::collections::{BTreeMap, HashMap};
use std::path::Path;

use perfect_db::database::{Database, DatabaseOptions, DatabaseVariant, FileDatabaseProvider};
use perfect_db::patch::{
    MAX_TRAP_SCORED_CHILDREN, nibble_to_u8, trap_rank, u8_trap_score_to_nibble_for_fusion,
};
use perfect_db::wdl_plane::WdlPlaneCache;
use tgf_core::{Action, GameRules, GameStateSnapshot};
use tgf_mill::rules::MillState;
use tgf_mill::{MillRules, MillVariantOptions};

use super::human_weight::{HumanWeightConfig, HumanWeights, load_human_weights};
use crate::mill_mine::adversary::rank_children;
use crate::mill_mine::entry::MineEntry;

/// Per-entry proof + steering data destined for the packed record fields.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct ChildProof {
    pub child_count: u8,
    pub optimal_mask: u64,
    pub trap_score_mask: u64,
    pub optimal_trap_nibbles: u64,
}

/// Canonical-key derivation. This trait is deliberately implemented
/// exactly once -- the blanket impl over a real [`WdlPlaneCache`] below,
/// which delegates to [`perfect_db::canonical_key`] (and, transitively,
/// `mid_removal_key`). Tests must never substitute their own key
/// semantics: a mock that folds positions differently from production
/// would validate the pipeline against a world that does not exist. What
/// tests *may* inject is WDL values (see [`WdlOracle`]).
pub(crate) trait CanonicalKeys {
    fn canonical_key(&mut self, state: &MillState, options: &MillVariantOptions) -> Option<u64>;
}

impl<P: perfect_db::database::DatabaseProvider> CanonicalKeys for WdlPlaneCache<P> {
    fn canonical_key(&mut self, state: &MillState, options: &MillVariantOptions) -> Option<u64> {
        perfect_db::canonical_key(self, state, options)
    }
}

/// The one small boundary where the packing derivation touches WDL data.
///
/// Production uses [`PlaneOracle`] (a live plane cache serves both keys
/// and values); tests use `TableOracle`, which keeps production key
/// semantics (a real secval-backed plane cache behind [`CanonicalKeys`])
/// but injects every WDL *value* from a fixed table, so blocker cases
/// (losing replies, sign flips, coverage gaps) are constructed
/// deterministically instead of scavenged from real databases. Everything
/// that can be a pure function ([`quantize`], [`weighted_blunder_density`],
/// [`shrunk_density`], [`encode_trap_scores`], `combine_sign`) stays out
/// of this trait.
pub(crate) trait WdlOracle {
    /// The production-semantics canonical-key derivation backing this
    /// oracle (always a real plane cache; see [`CanonicalKeys`]).
    fn keys(&mut self) -> &mut dyn CanonicalKeys;
    /// WDL of `snap` from its own side to move, `None` on coverage gaps.
    fn direct_wdl(
        &mut self,
        rules: &MillRules,
        snap: &GameStateSnapshot,
        options: &MillVariantOptions,
    ) -> Option<i8>;
    /// The plane's stored value behind a settled canonical key (its own
    /// folded perspective), `None` on coverage gaps.
    fn raw_wdl_by_key(&mut self, key: u64) -> Option<i8>;
}

/// Production oracle over the live plane cache.
pub(crate) struct PlaneOracle<'a, P: perfect_db::database::DatabaseProvider> {
    pub planes: &'a mut WdlPlaneCache<P>,
}

impl<P: perfect_db::database::DatabaseProvider> WdlOracle for PlaneOracle<'_, P> {
    fn keys(&mut self) -> &mut dyn CanonicalKeys {
        self.planes
    }

    fn direct_wdl(
        &mut self,
        rules: &MillRules,
        snap: &GameStateSnapshot,
        options: &MillVariantOptions,
    ) -> Option<i8> {
        match perfect_db::resolve_wdl_with_plane(self.planes, rules, snap, options) {
            Ok(value) => value,
            Err(err) => panic!("[patch-pack] plane WDL resolution failed: {err}"),
        }
    }

    fn raw_wdl_by_key(&mut self, key: u64) -> Option<i8> {
        self.planes.wdl_by_canonical_key(key).unwrap_or_else(|err| {
            panic!("[patch-pack] plane lookup for key {key:#x} failed: {err}")
        })
    }
}

/// Pipeline diagnostics (stderr summary; the behavior-gate rates that
/// matter are total-weighted inside `HumanWeightStats`).
#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct RecomputeStats {
    pub keys_changed: usize,
    pub children_changed: usize,
    pub unchanged: usize,
    pub skipped: usize,
    pub deduped_away: usize,
    pub same_side_children_zeroed: u64,
    pub empty_trap_mask_records: u64,
    pub top16_evictions: u64,
    pub nibble_from_behavior: u64,
    pub nibble_from_uniform: u64,
    pub fusion_won: u64,
    pub best_value_unresolved_parent_count: u64,
    /// Histogram of `nibble_behavior - nibble_uniform` in [-15, 15],
    /// indexed by `diff + 15`.
    pub divergence: [u64; 31],
}

pub(crate) struct RecomputeOutcome {
    pub entries: Vec<MineEntry>,
    pub proofs: HashMap<u64, ChildProof>,
    pub stats: RecomputeStats,
    /// Kept alive for the audit's re-derivation in the same context.
    pub human: Option<HumanWeights>,
    /// The frozen stage-3 fusion signal, for the audit's re-derivation.
    pub trap_score_by_key: HashMap<u64, u8>,
}

/// The single authoritative same-key deduplication: severity > 0 always
/// beats a severity-0 steering entry, higher severity beats lower, higher
/// mass breaks the remaining ties. `build_patch_file` consumes this
/// function's output and asserts key uniqueness instead of re-deduping
/// with its own rules.
pub(crate) fn dedup_entries(entries: Vec<MineEntry>) -> Vec<MineEntry> {
    let mut by_key: HashMap<u64, MineEntry> = HashMap::with_capacity(entries.len());
    for entry in entries {
        match by_key.entry(entry.key) {
            std::collections::hash_map::Entry::Vacant(slot) => {
                slot.insert(entry);
            }
            std::collections::hash_map::Entry::Occupied(mut slot) => {
                let incumbent = slot.get();
                let candidate_rank = ((entry.severity > 0) as u8, entry.severity, entry.mass);
                let incumbent_rank = (
                    (incumbent.severity > 0) as u8,
                    incumbent.severity,
                    incumbent.mass,
                );
                if candidate_rank
                    .partial_cmp(&incumbent_rank)
                    .expect("entry mass must be finite")
                    .is_gt()
                {
                    slot.insert(entry);
                }
            }
        }
    }
    let mut deduped: Vec<MineEntry> = by_key.into_values().collect();
    // Deterministic order regardless of hash-map iteration.
    deduped.sort_by_key(|entry| entry.key);
    deduped
}

/// Uniform (step-level) blunder density of one position, memoized by its
/// canonical key: `sum(max(0, best - reply)) / (2 * reply_count)` over the
/// position's own legal actions, plus the DB-perfect `best_value` the
/// behavior weighting must baseline against. `None` when the oracle cannot
/// score the position's replies.
///
/// Memoizing by canonical key is sound because equal keys are the same
/// abstract position (same side-to-move after folding); the per-snapshot
/// direction of a *reply* is never cached here -- that lives in
/// `sign_to_parent`, computed per concrete row at aggregation time.
pub(crate) struct DensityMemo {
    by_key: HashMap<u64, Option<(f64, i8)>>,
    hits: u64,
    misses: u64,
}

impl DensityMemo {
    pub(crate) fn new() -> Self {
        Self {
            by_key: HashMap::new(),
            hits: 0,
            misses: 0,
        }
    }

    pub(crate) fn density_and_best(
        &mut self,
        key: u64,
        snap: &GameStateSnapshot,
        rules: &MillRules,
        options: &MillVariantOptions,
        oracle: &mut dyn WdlOracle,
    ) -> Option<(f64, i8)> {
        if let Some(cached) = self.by_key.get(&key) {
            self.hits += 1;
            return *cached;
        }
        self.misses += 1;
        let computed = move_wdl_via_oracle(rules, snap, options, oracle).and_then(|move_wdl| {
            if move_wdl.is_empty() {
                return None;
            }
            let best_value = move_wdl
                .iter()
                .map(|&(_, value)| value)
                .max()
                .expect("non-empty");
            let mut severity_sum = 0.0_f64;
            for &(_, value) in &move_wdl {
                let severity = i32::from(best_value) - i32::from(value);
                if severity > 0 {
                    severity_sum += f64::from(severity);
                }
            }
            Some((severity_sum / (2.0 * move_wdl.len() as f64), best_value))
        });
        self.by_key.insert(key, computed);
        computed
    }
}

/// Root-side move values through the oracle (mirrors
/// `perfect_db::all_move_wdl_fast`'s perspective conversion): `None` when
/// any child is uncoverable.
pub(crate) fn move_wdl_via_oracle(
    rules: &MillRules,
    snap: &GameStateSnapshot,
    options: &MillVariantOptions,
    oracle: &mut dyn WdlOracle,
) -> Option<Vec<(Action, i8)>> {
    let root_side = snap.side_to_move;
    if root_side != 0 && root_side != 1 {
        return None;
    }
    let mut actions = tgf_core::ActionList::<256>::new();
    rules.legal_actions(snap, &mut actions);
    let mut results = Vec::with_capacity(actions.as_slice().len());
    for &action in actions.as_slice() {
        let child_snap = rules.apply(snap, action);
        let child_wdl = oracle.direct_wdl(rules, &child_snap, options)?;
        let value = if child_snap.side_to_move == root_side {
            child_wdl
        } else {
            -child_wdl
        };
        results.push((action, value));
    }
    Some(results)
}

/// Quantize a density into the 4-bit nibble scale with a nonzero floor:
/// any strictly positive density survives as at least 1 (the strictly
/// -greater switch rule handles the noise), zero stays zero.
pub(crate) fn quantize(density: f64) -> u8 {
    assert!(density >= 0.0, "densities are non-negative by construction");
    if density <= 0.0 {
        0
    } else {
        ((density * 15.0).round() as u8).clamp(1, 15)
    }
}

/// Derive one entry's packed proof + steering fields. This is the single
/// derivation shared by the packing pipeline, the packed-field full-scan
/// validation, and the audit's sampled re-derivation -- there must never
/// be a second nibble implementation to drift against.
#[allow(clippy::too_many_arguments)]
pub(crate) fn derive_child_proof(
    entry: &MineEntry,
    rules: &MillRules,
    options: &MillVariantOptions,
    oracle: &mut dyn WdlOracle,
    trap_score_by_key: &HashMap<u64, u8>,
    human: Option<&HumanWeights>,
    memo: &mut DensityMemo,
    stats: &mut RecomputeStats,
) -> ChildProof {
    let mut state = rules
        .set_from_fen(&entry.fen)
        .expect("proof derivation runs on stage-1 survivors");
    state.reset_ply_since_capture();
    let parent_side = state.side_to_move();
    let snap = rules.encode_state(state);
    let move_wdl =
        move_wdl_via_oracle(rules, &snap, options, oracle).expect("stage-1 survivors are covered");
    assert!(!move_wdl.is_empty(), "stage-1 survivors have legal moves");
    let best_value = move_wdl
        .iter()
        .map(|&(_, value)| value)
        .max()
        .expect("non-empty");

    // Per distinct child canonical key: the DB value (for the optimal
    // mask) and, when the turn hands the move over, the child snapshot to
    // score. Same-side children are recorded value-wise but their steering
    // score is hard 0 on every signal.
    let mut value_by_child_key: BTreeMap<u64, i8> = BTreeMap::new();
    let mut child_snap_by_key: HashMap<u64, (GameStateSnapshot, bool)> = HashMap::new();
    for &(action, value) in &move_wdl {
        let child_snap = rules.apply(&snap, action);
        let child_state = MillRules::decode_snapshot(child_snap);
        let Some(child_key) = oracle.keys().canonical_key(&child_state, options) else {
            continue;
        };
        if let Some(previous) = value_by_child_key.insert(child_key, value) {
            assert_eq!(
                previous, value,
                "two actions reaching the same canonical child must share one DB value (fen {})",
                entry.fen
            );
        }
        let side_flipped = child_state.side_to_move() != parent_side;
        child_snap_by_key.insert(child_key, (child_snap, side_flipped));
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

    // Score every proven-optimal, side-flipping child.
    let mut scored: Vec<(u8, u64, usize)> = Vec::new();
    let mut optimal_children = 0_u64;
    for (index, (&child_key, _)) in value_by_child_key.iter().enumerate() {
        if optimal_mask & (1_u64 << index) == 0 {
            continue;
        }
        optimal_children += 1;
        let (child_snap, side_flipped) = child_snap_by_key
            .get(&child_key)
            .expect("every keyed child has a snapshot");
        if !side_flipped {
            stats.same_side_children_zeroed += 1;
            continue;
        }
        let uniform = memo.density_and_best(child_key, child_snap, rules, options, oracle);
        let (density_uniform, child_best_value) = match uniform {
            Some(pair) => pair,
            None => {
                stats.best_value_unresolved_parent_count += 1;
                (0.0, 0)
            }
        };
        let nibble_uniform = quantize(density_uniform);
        let nibble_behavior = match (human, uniform.is_some()) {
            (Some(weights), true) => {
                match weights.behavior_density(child_key, child_best_value, density_uniform, oracle)
                {
                    Some(blended) => {
                        let nibble = quantize(blended);
                        let diff = i32::from(nibble) - i32::from(nibble_uniform) + 15;
                        stats.divergence[diff as usize] += 1;
                        stats.nibble_from_behavior += 1;
                        nibble
                    }
                    None => {
                        stats.nibble_from_uniform += 1;
                        nibble_uniform
                    }
                }
            }
            _ => {
                stats.nibble_from_uniform += 1;
                nibble_uniform
            }
        };
        let fusion = trap_score_by_key
            .get(&child_key)
            .copied()
            .map(u8_trap_score_to_nibble_for_fusion)
            .unwrap_or(0);
        let nibble = if fusion > nibble_behavior {
            stats.fusion_won += 1;
            fusion
        } else {
            nibble_behavior
        };
        if nibble >= 1 {
            scored.push((nibble, child_key, index));
        }
    }

    let (trap_score_mask, optimal_trap_nibbles) = encode_trap_scores(scored, stats);
    if trap_score_mask == 0 && optimal_children > 0 {
        stats.empty_trap_mask_records += 1;
    }

    ChildProof {
        child_count: value_by_child_key.len() as u8,
        optimal_mask,
        trap_score_mask,
        optimal_trap_nibbles,
    }
}

/// Keep the positive top-16 scored children by (score desc, child_key asc)
/// and encode them into the packed `(trap_score_mask,
/// optimal_trap_nibbles)` pair. `scored` holds `(nibble, child_key,
/// child_index)` triples with `nibble >= 1`.
pub(crate) fn encode_trap_scores(
    mut scored: Vec<(u8, u64, usize)>,
    stats: &mut RecomputeStats,
) -> (u64, u64) {
    scored.sort_by(|a, b| b.0.cmp(&a.0).then(a.1.cmp(&b.1)));
    if scored.len() > MAX_TRAP_SCORED_CHILDREN as usize {
        stats.top16_evictions += (scored.len() - MAX_TRAP_SCORED_CHILDREN as usize) as u64;
        scored.truncate(MAX_TRAP_SCORED_CHILDREN as usize);
    }
    let mut trap_score_mask = 0_u64;
    for &(_, _, index) in &scored {
        trap_score_mask |= 1_u64 << index;
    }
    let mut optimal_trap_nibbles = 0_u64;
    for &(nibble, _, index) in &scored {
        assert!(nibble >= 1, "only positive scores may be encoded");
        let rank = trap_rank(trap_score_mask, index).expect("bit set above");
        optimal_trap_nibbles |= u64::from(nibble) << (u32::from(rank) * 4);
    }
    (trap_score_mask, optimal_trap_nibbles)
}

/// Run stages 0-4. `Err` means broken *external inputs* (today: a
/// configured-but-unusable HumanDB); the CLI caller reports it and exits
/// nonzero. Internal invariant violations still panic.
pub(crate) fn recompute_entries(
    entries: Vec<MineEntry>,
    db_path: &Path,
    options: &MillVariantOptions,
    human_db: Option<&Path>,
    human_config: HumanWeightConfig,
) -> Result<RecomputeOutcome, String> {
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

    // Stage 0: HumanDB behavior weighting (fully skipped when disabled; a
    // configured-but-broken database is a hard error, never a silent
    // fallback to uniform density).
    let human = match human_db {
        Some(path) => {
            let started = std::time::Instant::now();
            let mut oracle = PlaneOracle {
                planes: &mut planes,
            };
            let weights = load_human_weights(path, &rules, options, &mut oracle, human_config)?;
            eprintln!(
                "[patch-pack] human weighting loaded in {:.1}s: {} turn parents, {} step parents",
                started.elapsed().as_secs_f64(),
                weights.turn.len(),
                weights.step.len()
            );
            weights.print_stats();
            Some(weights)
        }
        None => {
            eprintln!("[patch-pack] human weighting NOT enabled (uniform density only)");
            None
        }
    };

    let mut stats = RecomputeStats::default();
    let mut memo = DensityMemo::new();

    // Stage 1: re-derive key / best_child per entry; overwrite severity-0
    // trap scores from the position's own density (steering entries write
    // a 0 placeholder in mining and never call scoring::trap_score).
    let mut derived: Vec<MineEntry> = Vec::with_capacity(entries.len());
    for mut entry in entries {
        let Ok(mut state) = rules.set_from_fen(&entry.fen) else {
            stats.skipped += 1;
            continue;
        };
        // Work in the same history-free frame the runtime correction uses:
        // a mined FEN can carry a live `ply_since_capture` close to the
        // `n_move_rule` limit, which would make quiet children spuriously
        // terminal here while the runtime's sanitized replica sees them as
        // ordinary children.
        state.reset_ply_since_capture();
        let Some(key) = perfect_db::canonical_key(&mut planes, &state, options) else {
            stats.skipped += 1;
            continue;
        };
        let snap = rules.encode_state(state);
        let Ok(Some(move_wdl)) = perfect_db::all_move_wdl_fast(&mut planes, &rules, &snap, options)
        else {
            stats.skipped += 1;
            continue;
        };
        if move_wdl.is_empty() {
            stats.skipped += 1;
            continue;
        }
        let ranked = rank_children(&rules, options, &mut db, &mut planes, &snap, &move_wdl);
        let Some(best) = ranked.optimal.first() else {
            stats.skipped += 1;
            continue;
        };
        let mut any_change = false;
        if key != entry.key {
            entry.key = key;
            stats.keys_changed += 1;
            any_change = true;
        }
        if best.key != entry.best_child {
            entry.best_child = best.key;
            stats.children_changed += 1;
            any_change = true;
        }
        if !any_change {
            stats.unchanged += 1;
        }
        if entry.severity == 0 {
            let mut oracle = PlaneOracle {
                planes: &mut planes,
            };
            let self_density = memo
                .density_and_best(key, &snap, &rules, options, &mut oracle)
                .map(|(density, _)| density)
                .unwrap_or(0.0);
            entry.trap_score = nibble_to_u8(quantize(self_density));
        }
        derived.push(entry);
    }

    // Stage 2: single authoritative dedup.
    let before_dedup = derived.len();
    let deduped = dedup_entries(derived);
    stats.deduped_away = before_dedup - deduped.len();

    // Stage 3: fusion signal from the deduplicated, pre-budget set. This
    // map is frozen here on purpose: entries dropped by the budget later
    // still contribute their engine-specific trap signal to parents.
    let trap_score_by_key: HashMap<u64, u8> = deduped
        .iter()
        .map(|entry| (entry.key, entry.trap_score))
        .collect();

    // Stage 4: proofs + steering nibbles per unique entry, through the
    // exact derivation the audit re-runs on its samples.
    let mut proofs: HashMap<u64, ChildProof> = HashMap::with_capacity(deduped.len());
    for entry in &deduped {
        let mut oracle = PlaneOracle {
            planes: &mut planes,
        };
        let proof = derive_child_proof(
            entry,
            &rules,
            options,
            &mut oracle,
            &trap_score_by_key,
            human.as_ref(),
            &mut memo,
            &mut stats,
        );
        proofs.insert(entry.key, proof);
    }

    eprintln!(
        "[patch-pack] recompute: {} keys changed, {} best_children changed, {} already matched, \
         {} skipped, {} deduplicated away; {} proofs derived (density memo: {} unique, {} hits)",
        stats.keys_changed,
        stats.children_changed,
        stats.unchanged,
        stats.skipped,
        stats.deduped_away,
        proofs.len(),
        memo.misses,
        memo.hits,
    );
    eprintln!(
        "[patch-pack] steering: same_side_zeroed={} empty_trap_mask={} top16_evictions={} \
         nibble_sources(behavior={} uniform={} fusion_won={}) best_value_unresolved={}",
        stats.same_side_children_zeroed,
        stats.empty_trap_mask_records,
        stats.top16_evictions,
        stats.nibble_from_behavior,
        stats.nibble_from_uniform,
        stats.fusion_won,
        stats.best_value_unresolved_parent_count,
    );
    if stats.divergence.iter().any(|&n| n > 0) {
        let rendered: Vec<String> = stats
            .divergence
            .iter()
            .enumerate()
            .filter(|(_, n)| **n > 0)
            .map(|(i, n)| format!("{}:{n}", i as i32 - 15))
            .collect();
        eprintln!(
            "[patch-pack] behavior-uniform nibble divergence histogram: {}",
            rendered.join(" ")
        );
    }

    Ok(RecomputeOutcome {
        entries: deduped,
        proofs,
        stats,
        human,
        trap_score_by_key,
    })
}

/// Test-only oracle: canonical keys come from a secval-backed hasher (the
/// bundled ~6.5KB `std.secval` is sector metadata, not position data), but
/// every WDL value comes from an injected table so blocker tests construct
/// losing replies, sign flips, and coverage gaps deterministically.
#[cfg(test)]
pub(crate) struct TableOracle {
    pub keys: WdlPlaneCache<perfect_db::database::MemoryDatabaseProvider>,
    /// Own-side WDL by canonical key (what `direct_wdl` returns for a
    /// settled position).
    pub own_value_by_key: HashMap<u64, i8>,
    /// Plane-perspective value by canonical key; defaults to the own-side
    /// value (sign +1) unless a test plants a flipped entry.
    pub raw_override_by_key: HashMap<u64, i8>,
    /// Own-side value for keys absent from `own_value_by_key`; `None`
    /// models a coverage gap.
    pub default_value: Option<i8>,
}

#[cfg(test)]
impl TableOracle {
    pub(crate) fn new() -> Self {
        let secval = std::fs::read(
            std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("../../src/ui/flutter_app/assets/databases/std.secval"),
        )
        .expect("bundled std.secval");
        let provider = perfect_db::database::MemoryDatabaseProvider::from_files([(
            "std.secval".to_string(),
            secval,
        )]);
        Self {
            keys: WdlPlaneCache::new(provider, DatabaseVariant::STANDARD)
                .expect("secval-only key cache"),
            own_value_by_key: HashMap::new(),
            raw_override_by_key: HashMap::new(),
            default_value: None,
        }
    }

    pub(crate) fn key_of(&mut self, state: &MillState, options: &MillVariantOptions) -> u64 {
        perfect_db::canonical_key(&mut self.keys, state, options).expect("keyable state")
    }
}

#[cfg(test)]
impl WdlOracle for TableOracle {
    fn keys(&mut self) -> &mut dyn CanonicalKeys {
        &mut self.keys
    }

    fn direct_wdl(
        &mut self,
        rules: &MillRules,
        snap: &GameStateSnapshot,
        options: &MillVariantOptions,
    ) -> Option<i8> {
        // Terminal positions resolve from the outcome exactly like the
        // production plane resolver does.
        match rules.outcome(snap).kind {
            tgf_core::OutcomeKind::Win(winner) => {
                let side = snap.side_to_move;
                return Some(if i16::from(winner) == i16::from(side) {
                    1
                } else {
                    -1
                });
            }
            tgf_core::OutcomeKind::Draw => return Some(0),
            tgf_core::OutcomeKind::Ongoing => {}
            other @ (tgf_core::OutcomeKind::WinTeam(_) | tgf_core::OutcomeKind::Abandoned) => {
                panic!("Mill outcomes never produce {other:?}")
            }
        }
        let state = MillRules::decode_snapshot(*snap);
        let key = perfect_db::canonical_key(&mut self.keys, &state, options)?;
        self.own_value_by_key
            .get(&key)
            .copied()
            .or(self.default_value)
    }

    fn raw_wdl_by_key(&mut self, key: u64) -> Option<i8> {
        assert!(
            key & perfect_db::wdl_plane::MID_REMOVAL_KEY_TAG == 0,
            "raw plane values only exist for settled keys"
        );
        self.raw_override_by_key
            .get(&key)
            .or_else(|| self.own_value_by_key.get(&key))
            .copied()
            .or(self.default_value)
    }
}

#[cfg(test)]
#[path = "recompute_tests.rs"]
mod tests;
