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

/// Steering-gate diagnostics computed alongside a proof: the *full* score
/// vector's shape over side-flipping optimal candidates (including
/// candidates whose nibble is 0 or who fell outside the top-16 mask;
/// same-side children are excluded because their score is a hard 0 by
/// perspective rule, not by measurement).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(crate) struct SteeringDiag {
    /// Number of side-flipping, proven-optimal children.
    pub flipped_optimal: u32,
    /// `max - min` over those children's fused nibbles (0 when fewer than
    /// two candidates exist).
    pub nibble_gap: u8,
}

/// Why a severity-0 steering entry was dropped by the packer's gate.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum SteeringDrop {
    /// Fewer than two side-flipping optimal candidates: the runtime's
    /// trap-aware reordering would have no choice to make.
    FewFlippedCandidates,
    /// The full score vector is too flat (`gap < --steering-min-gap`):
    /// with the strictly-greater switch rule such a record can never
    /// steer, so it would be dead weight in the asset.
    LowGap,
}

/// The steering gate itself (severity > 0 entries always pass -- they are
/// corrections first, steering second).
pub(crate) fn steering_gate(
    severity: i8,
    diag: SteeringDiag,
    min_gap: u8,
) -> Result<(), SteeringDrop> {
    if severity > 0 {
        return Ok(());
    }
    if diag.flipped_optimal < 2 {
        return Err(SteeringDrop::FewFlippedCandidates);
    }
    if diag.nibble_gap < min_gap {
        return Err(SteeringDrop::LowGap);
    }
    Ok(())
}

/// Experimental steering risk-gate mode (`--steering-risk-gate`). The gate
/// filters candidates OUT of `trap_score_mask` only -- the nibble formula
/// itself is never touched, so an A/B pack diff is purely a mask diff.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(crate) enum RiskGateMode {
    /// No risk filtering (production default; byte-identical packs).
    #[default]
    None,
    /// Keep a candidate iff `own_risk <= lambda * trap_density`.
    Absolute,
    /// Keep a candidate iff its own-risk EXCESS over the safest sibling is
    /// covered by its trap-density excess over the least-trappy sibling:
    /// `risk - min_risk <= lambda * max(0, trap - min_trap)`, minima taken
    /// over the parent's side-flipping optimal children with *resolved*
    /// values only.
    SiblingDelta,
}

impl RiskGateMode {
    pub(crate) fn name(self) -> &'static str {
        match self {
            RiskGateMode::None => "none",
            RiskGateMode::Absolute => "absolute",
            RiskGateMode::SiblingDelta => "sibling-delta",
        }
    }
}

/// Experimental risk-gate configuration. `Default` is the inert
/// production configuration (mode none, no ply floor).
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct RiskGateConfig {
    pub mode: RiskGateMode,
    /// Risk budget multiplier; both modes compare risk against
    /// `lambda * trap` terms. Must be finite and >= 0.
    pub lambda: f64,
    /// Positions with fewer than this many pieces already placed carry no
    /// steering mask at all (see [`placing_ply_proxy`]). 0 disables.
    pub min_placing_ply_proxy: u32,
}

impl Default for RiskGateConfig {
    fn default() -> Self {
        Self {
            mode: RiskGateMode::None,
            lambda: 1.0,
            min_placing_ply_proxy: 0,
        }
    }
}

impl RiskGateConfig {
    /// The gate is active as soon as ANY of its filters can fire: a mode,
    /// or a bare ply-proxy floor with mode none. Activation is what arms
    /// the severity-0 empty-mask drop
    /// ([`drop_steering_for_empty_mask`]).
    pub(crate) fn active(&self) -> bool {
        self.mode != RiskGateMode::None || self.min_placing_ply_proxy > 0
    }
}

/// Placing-phase progress proxy of one position: pieces already placed
/// (`2 * piece_count - total still in hand`).
///
/// This deliberately is NOT the real game ply (mined FENs carry none):
/// during the placing phase it counts placements only (removal plies are
/// not counted, so it undercounts by the number of captures so far), and
/// in the moving phase it saturates at `2 * piece_count` (18 for std),
/// where any `--steering-min-placing-ply-proxy` threshold up to that
/// value always passes.
pub(crate) fn placing_ply_proxy(state: &MillState, options: &MillVariantOptions) -> u32 {
    let in_hand = state.pieces_in_hand();
    2 * u32::from(options.piece_count) - u32::from(in_hand[0]) - u32::from(in_hand[1])
}

/// One candidate's risk-gate verdict; the caller maps variants onto the
/// `gate_*` counters.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum GateDecision {
    Pass,
    FilteredByPlyProxy,
    FilteredByRisk,
    /// The candidate has ZERO resolved own-risk samples (see [`OwnRisk`]).
    /// Partial unresolvedness (some samples resolved, some not) still
    /// gates on the resolved mean and is NOT this variant.
    FilteredUnresolved,
}

/// The pure per-candidate gate decision, shared by the packer, the
/// audit's re-derivation, and the unit tests. `own_risk` is the resolved
/// own-turn risk mean (`None` = zero resolved samples); `trap_density` is
/// the candidate's uniform density (`None` = unresolved, treated as 0 --
/// a positive nibble over an unresolved density can only come from
/// fusion, which the caller counts separately). The sibling minima are
/// only consulted in sibling-delta mode and must come from *resolved*
/// siblings only -- an unresolved sibling must never anchor a 0 minimum.
pub(crate) fn risk_gate_decision(
    gate: RiskGateConfig,
    placing_ply_proxy: u32,
    own_risk: Option<f64>,
    trap_density: Option<f64>,
    min_sibling_risk: Option<f64>,
    min_sibling_trap: Option<f64>,
) -> GateDecision {
    if placing_ply_proxy < gate.min_placing_ply_proxy {
        return GateDecision::FilteredByPlyProxy;
    }
    match gate.mode {
        RiskGateMode::None => GateDecision::Pass,
        RiskGateMode::Absolute => {
            let Some(risk) = own_risk else {
                return GateDecision::FilteredUnresolved;
            };
            if risk <= gate.lambda * trap_density.unwrap_or(0.0) {
                GateDecision::Pass
            } else {
                GateDecision::FilteredByRisk
            }
        }
        RiskGateMode::SiblingDelta => {
            let Some(risk) = own_risk else {
                return GateDecision::FilteredUnresolved;
            };
            // The candidate itself is a resolved sibling, so the resolved
            // minimum always exists here.
            let min_risk = min_sibling_risk
                .expect("a resolved candidate implies a resolved sibling risk minimum");
            let risk_delta = risk - min_risk;
            let trap_delta = match min_sibling_trap {
                Some(min_trap) => (trap_density.unwrap_or(0.0) - min_trap).max(0.0),
                // No sibling has a resolved trap density: no relative trap
                // edge is measurable, so only zero excess risk passes.
                None => 0.0,
            };
            if risk_delta <= gate.lambda * trap_delta {
                GateDecision::Pass
            } else {
                GateDecision::FilteredByRisk
            }
        }
    }
}

/// With an ACTIVE gate, a severity-0 steering record whose final mask
/// came out empty can never steer under the strictly-greater switch rule
/// and is dead weight: drop it (and count). Severity > 0 corrections are
/// never dropped for an empty mask -- their avoid-value stands on its
/// own.
pub(crate) fn drop_steering_for_empty_mask(
    gate_active: bool,
    severity: i8,
    trap_score_mask: u64,
) -> bool {
    gate_active && severity == 0 && trap_score_mask == 0
}

/// Corrected own-turn risk of steering into one side-flipping child: the
/// blunder density OUR side faces once the turn actually returns to us.
///
/// Sample walk, per opponent value-preserving reply at the child:
/// * reply flips the side back -> our-turn node, one sample;
/// * reply keeps the opponent on turn (they formed a mill and owe a
///   removal) -> walk their value-preserving removals one layer deep;
///   under standard rules the turn MUST return to us after that single
///   removal layer (asserted), each preserving removal contributing one
///   sample;
/// * a terminal node (game over before we ever move) is counted, never
///   scored -- there is no move of ours left to blunder;
/// * an our-turn node whose density is uncoverable is an unresolved
///   sample.
///
/// The mean is over resolved samples only. `mean == None` (zero resolved
/// samples) is the candidate-level "unresolved" the gate filters on;
/// partial unresolvedness gates on the resolved mean and is only
/// reported.
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct OwnRisk {
    pub mean: Option<f64>,
    pub resolved_samples: u32,
    pub unresolved_samples: u32,
    pub terminal_samples: u32,
}

/// Memoized own-turn risk, keyed by `(canonical_key, side_to_move,
/// phase)`. Settled canonical keys fold the mover into the sector and
/// mid-removal keys are opaque hashes, so the key alone *should* never
/// collide across side or phase -- but rather than depending on those
/// internals the memo keys on the full tuple outright.
pub(crate) struct RiskMemo {
    by_key: HashMap<(u64, i8, u8), OwnRisk>,
    pub hits: u64,
    pub misses: u64,
}

impl RiskMemo {
    pub(crate) fn new() -> Self {
        Self {
            by_key: HashMap::new(),
            hits: 0,
            misses: 0,
        }
    }

    /// See [`OwnRisk`]. The `own_risk_*_samples` stats count unique
    /// cache-miss computations only (a memo hit re-reports nothing), so
    /// they are per-position sample counters, not per-candidate-use.
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn own_turn_risk(
        &mut self,
        child_key: u64,
        child_snap: &GameStateSnapshot,
        parent_side: i8,
        rules: &MillRules,
        options: &MillVariantOptions,
        oracle: &mut dyn WdlOracle,
        density_memo: &mut DensityMemo,
        stats: &mut RecomputeStats,
    ) -> OwnRisk {
        let child_state = MillRules::decode_snapshot(*child_snap);
        let child_side = child_state.side_to_move();
        assert_ne!(
            child_side, parent_side,
            "own-turn risk is only defined for side-flipping steering candidates; \
             a same-side candidate reaching the gate is a perspective-filter leak"
        );
        let memo_key = (child_key, child_side, child_state.phase() as u8);
        if let Some(cached) = self.by_key.get(&memo_key) {
            self.hits += 1;
            return *cached;
        }
        self.misses += 1;
        let computed = compute_own_turn_risk(
            child_snap,
            child_side,
            parent_side,
            rules,
            options,
            oracle,
            density_memo,
        );
        stats.own_risk_resolved_samples += u64::from(computed.resolved_samples);
        stats.own_risk_unresolved_samples += u64::from(computed.unresolved_samples);
        stats.own_risk_terminal_samples += u64::from(computed.terminal_samples);
        self.by_key.insert(memo_key, computed);
        computed
    }
}

/// Where one opponent reply landed, for the own-risk walk.
enum ReachedNode {
    Terminal,
    OurTurn(GameStateSnapshot),
    OpponentRemoval(GameStateSnapshot),
}

fn compute_own_turn_risk(
    child_snap: &GameStateSnapshot,
    child_side: i8,
    parent_side: i8,
    rules: &MillRules,
    options: &MillVariantOptions,
    oracle: &mut dyn WdlOracle,
    density_memo: &mut DensityMemo,
) -> OwnRisk {
    // The opponent's full reply values determine the preserving set; if
    // they are not fully covered the set itself is unknowable and the
    // candidate has no samples at all.
    let Some(replies) = move_wdl_via_oracle(rules, child_snap, options, oracle) else {
        return OwnRisk {
            mean: None,
            resolved_samples: 0,
            unresolved_samples: 0,
            terminal_samples: 0,
        };
    };
    assert!(
        !replies.is_empty(),
        "a canonically keyed (non-terminal) child must have opponent replies"
    );
    let best = replies.iter().map(|&(_, v)| v).max().expect("non-empty");

    let classify = |snap: &GameStateSnapshot| -> ReachedNode {
        if !matches!(rules.outcome(snap).kind, tgf_core::OutcomeKind::Ongoing) {
            return ReachedNode::Terminal;
        }
        if snap.side_to_move == child_side {
            ReachedNode::OpponentRemoval(*snap)
        } else {
            assert_eq!(
                snap.side_to_move, parent_side,
                "an ongoing node after the opponent's turn must belong to one of the two sides"
            );
            ReachedNode::OurTurn(*snap)
        }
    };

    let mut terminal = 0_u32;
    let mut unresolved = 0_u32;
    let mut our_turn_nodes: Vec<GameStateSnapshot> = Vec::new();
    for &(action, value) in &replies {
        if value != best {
            continue;
        }
        match classify(&rules.apply(child_snap, action)) {
            ReachedNode::Terminal => terminal += 1,
            ReachedNode::OurTurn(snap) => our_turn_nodes.push(snap),
            ReachedNode::OpponentRemoval(pending) => {
                // The opponent formed a mill and still owes a removal.
                let Some(removals) = move_wdl_via_oracle(rules, &pending, options, oracle) else {
                    unresolved += 1;
                    continue;
                };
                assert!(
                    !removals.is_empty(),
                    "an ongoing pending-removal node must have legal removals"
                );
                let removal_best = removals.iter().map(|&(_, v)| v).max().expect("non-empty");
                for &(removal, removal_value) in &removals {
                    if removal_value != removal_best {
                        continue;
                    }
                    match classify(&rules.apply(&pending, removal)) {
                        ReachedNode::Terminal => terminal += 1,
                        ReachedNode::OurTurn(snap) => our_turn_nodes.push(snap),
                        ReachedNode::OpponentRemoval(_) => panic!(
                            "standard rules must hand the turn back after one removal layer; \
                             a second same-side layer means the variant options are not the \
                             ones this gate was specified for"
                        ),
                    }
                }
            }
        }
    }

    let mut resolved = 0_u32;
    let mut sum = 0.0_f64;
    for node in &our_turn_nodes {
        let node_state = MillRules::decode_snapshot(*node);
        let Some(node_key) = oracle.keys().canonical_key(&node_state, options) else {
            unresolved += 1;
            continue;
        };
        match density_memo.density_and_best(node_key, node, rules, options, oracle) {
            Some((density, _)) => {
                resolved += 1;
                sum += density;
            }
            None => unresolved += 1,
        }
    }
    OwnRisk {
        mean: (resolved > 0).then(|| sum / f64::from(resolved)),
        resolved_samples: resolved,
        unresolved_samples: unresolved,
        terminal_samples: terminal,
    }
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
    /// Records whose FINAL `trap_score_mask` is empty despite having
    /// optimal children. Under an ACTIVE risk gate this includes records
    /// the gate itself emptied, so the figure is NOT comparable against
    /// an ungated pack's -- always read it together with
    /// `risk_gated_empty_steering_records`.
    pub empty_trap_mask_records: u64,
    pub top16_evictions: u64,
    pub nibble_from_behavior: u64,
    pub nibble_from_uniform: u64,
    pub fusion_won: u64,
    pub best_value_unresolved_parent_count: u64,
    /// Histogram of `nibble_behavior - nibble_uniform` in [-15, 15],
    /// indexed by `diff + 15`.
    pub divergence: [u64; 31],
    /// severity-0 entries dropped for having fewer than two side-flipping
    /// optimal candidates.
    pub steering_dropped_few_candidates: u64,
    /// severity-0 entries dropped by the `--steering-min-gap` filter.
    pub steering_dropped_low_gap: u64,
    /// severity-0 entries that survived the steering gate.
    pub steering_kept: u64,
    /// Full-vector nibble gap histogram over surviving severity-0 entries
    /// (index = gap 0..=15).
    pub steering_gap_histogram: [u64; 16],
    /// Risk-gate candidate counters (positive-nibble candidates only;
    /// counted only while the gate is ACTIVE, so an inactive pack prints
    /// none of them). The three sub-buckets partition `filtered`, and
    /// `filtered_unresolved` is a candidate-level bucket: the candidate
    /// had zero resolved own-risk samples; a candidate with partial
    /// unresolvedness still gates on its resolved mean and is never in
    /// this bucket.
    pub gate_seen_positive: u64,
    pub gate_passed_positive: u64,
    pub gate_filtered_positive: u64,
    pub gate_filtered_by_ply_proxy: u64,
    pub gate_filtered_by_risk: u64,
    pub gate_filtered_unresolved: u64,
    /// Positive-nibble candidates whose uniform trap density was
    /// unresolved (the nibble came from fusion); the gate scores their
    /// trap term as 0.
    pub gate_trap_unresolved_fusion_zeroed: u64,
    /// Own-risk SAMPLE counters, accumulated on RiskMemo cache misses
    /// only (unique positions, not per-candidate-use; see
    /// [`RiskMemo::own_turn_risk`]).
    pub own_risk_resolved_samples: u64,
    pub own_risk_unresolved_samples: u64,
    pub own_risk_terminal_samples: u64,
    /// severity-0 entries dropped because the ACTIVE gate left their
    /// final `trap_score_mask` empty (severity > 0 entries are never
    /// dropped for an empty mask -- their avoid-correction value stands).
    pub risk_gated_empty_steering_records: u64,
    /// Positive nibbles actually encoded into kept entries' masks
    /// (pre-budget; top-16 evictions are reported separately and are NOT
    /// part of the gate's own retention).
    pub packed_positive: u64,
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

/// One side-flipping optimal child, as the mask selection sees it: the
/// nibble is final (the risk gate never rewrites it), the resolved
/// uniform density doubles as the gate's trap term and the sibling-delta
/// `min_trap` input.
struct FlippedCandidate {
    index: usize,
    child_key: u64,
    child_snap: GameStateSnapshot,
    nibble: u8,
    trap_density: Option<f64>,
}

/// Derive one entry's packed proof + steering fields, plus the
/// steering-gate diagnostics over the *full* candidate vector. This is the
/// single derivation shared by the packing pipeline, the packed-field
/// full-scan validation, and the audit's sampled re-derivation -- there
/// must never be a second nibble implementation to drift against. The
/// audit must therefore also re-derive with the same [`RiskGateConfig`]
/// the pack ran with.
#[allow(clippy::too_many_arguments)]
pub(crate) fn derive_child_proof(
    entry: &MineEntry,
    rules: &MillRules,
    options: &MillVariantOptions,
    oracle: &mut dyn WdlOracle,
    trap_score_by_key: &HashMap<u64, u8>,
    human: Option<&HumanWeights>,
    gate: RiskGateConfig,
    memo: &mut DensityMemo,
    risk_memo: &mut RiskMemo,
    stats: &mut RecomputeStats,
) -> (ChildProof, SteeringDiag) {
    let mut state = rules
        .set_from_fen(&entry.fen)
        .expect("proof derivation runs on stage-1 survivors");
    state.reset_ply_since_capture();
    let parent_side = state.side_to_move();
    let parent_ply_proxy = placing_ply_proxy(&state, options);
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

    // Score every proven-optimal, side-flipping child. `flipped_nibbles`
    // is the FULL score vector for the steering gate: every side-flipping
    // optimal candidate contributes its fused nibble, including zeros,
    // candidates later evicted from the top-16 mask, and candidates the
    // risk gate filters (same-side children are excluded -- their 0 is a
    // perspective rule, not a measurement).
    let mut candidates: Vec<FlippedCandidate> = Vec::new();
    let mut flipped_nibbles: Vec<u8> = Vec::new();
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
        flipped_nibbles.push(nibble);
        candidates.push(FlippedCandidate {
            index,
            child_key,
            child_snap: *child_snap,
            nibble,
            trap_density: uniform.map(|(density, _)| density),
        });
    }

    // Mask selection: without an active gate this is exactly the old
    // "every positive nibble enters" rule (byte-identical packs); with
    // one, positive candidates must additionally pass the risk gate.
    // Either way the nibble VALUES are final -- the gate is mask-only.
    let mut scored: Vec<(u8, u64, usize)> = Vec::new();
    if !gate.active() {
        for candidate in &candidates {
            if candidate.nibble >= 1 {
                scored.push((candidate.nibble, candidate.child_key, candidate.index));
            }
        }
    } else {
        let any_positive = candidates.iter().any(|candidate| candidate.nibble >= 1);
        // Sibling-delta minima span ALL side-flipping optimal children
        // (the runtime baseline can be any of them, nibble or not), but
        // only the RESOLVED ones -- an unresolved sibling must never
        // anchor a 0 minimum.
        let mut own_risk_mean: Vec<Option<f64>> = vec![None; candidates.len()];
        if gate.mode == RiskGateMode::SiblingDelta && any_positive {
            for (slot, candidate) in candidates.iter().enumerate() {
                own_risk_mean[slot] = risk_memo
                    .own_turn_risk(
                        candidate.child_key,
                        &candidate.child_snap,
                        parent_side,
                        rules,
                        options,
                        oracle,
                        memo,
                        stats,
                    )
                    .mean;
            }
        }
        let min_of = |values: &mut dyn Iterator<Item = f64>| -> Option<f64> {
            values.fold(None, |acc: Option<f64>, value| {
                assert!(value.is_finite(), "densities and risks are finite");
                Some(match acc {
                    None => value,
                    Some(best) => best.min(value),
                })
            })
        };
        let (min_sibling_risk, min_sibling_trap) = if gate.mode == RiskGateMode::SiblingDelta {
            (
                min_of(&mut own_risk_mean.iter().copied().flatten()),
                min_of(&mut candidates.iter().filter_map(|c| c.trap_density)),
            )
        } else {
            (None, None)
        };
        for (slot, candidate) in candidates.iter().enumerate() {
            if candidate.nibble < 1 {
                continue;
            }
            stats.gate_seen_positive += 1;
            if candidate.trap_density.is_none() {
                // A positive nibble over an unresolved uniform density can
                // only come from fusion; the gate scores its trap term 0.
                stats.gate_trap_unresolved_fusion_zeroed += 1;
            }
            let own_risk = match gate.mode {
                RiskGateMode::None => None,
                RiskGateMode::SiblingDelta => own_risk_mean[slot],
                RiskGateMode::Absolute => {
                    risk_memo
                        .own_turn_risk(
                            candidate.child_key,
                            &candidate.child_snap,
                            parent_side,
                            rules,
                            options,
                            oracle,
                            memo,
                            stats,
                        )
                        .mean
                }
            };
            match risk_gate_decision(
                gate,
                parent_ply_proxy,
                own_risk,
                candidate.trap_density,
                min_sibling_risk,
                min_sibling_trap,
            ) {
                GateDecision::Pass => {
                    stats.gate_passed_positive += 1;
                    scored.push((candidate.nibble, candidate.child_key, candidate.index));
                }
                GateDecision::FilteredByPlyProxy => {
                    stats.gate_filtered_positive += 1;
                    stats.gate_filtered_by_ply_proxy += 1;
                }
                GateDecision::FilteredByRisk => {
                    stats.gate_filtered_positive += 1;
                    stats.gate_filtered_by_risk += 1;
                }
                GateDecision::FilteredUnresolved => {
                    stats.gate_filtered_positive += 1;
                    stats.gate_filtered_unresolved += 1;
                }
            }
        }
    }

    let (trap_score_mask, optimal_trap_nibbles) = encode_trap_scores(scored, stats);
    if trap_score_mask == 0 && optimal_children > 0 {
        stats.empty_trap_mask_records += 1;
    }

    let nibble_gap = match (flipped_nibbles.iter().max(), flipped_nibbles.iter().min()) {
        (Some(&max), Some(&min)) if flipped_nibbles.len() >= 2 => max - min,
        _ => 0,
    };
    let diag = SteeringDiag {
        flipped_optimal: flipped_nibbles.len() as u32,
        nibble_gap,
    };

    (
        ChildProof {
            child_count: value_by_child_key.len() as u8,
            optimal_mask,
            trap_score_mask,
            optimal_trap_nibbles,
        },
        diag,
    )
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

/// Run stages 0-5 (HumanDB load, re-derive, dedup, fusion-map freeze,
/// proof derivation, steering gate). `Err` means broken *external inputs*
/// (today: a configured-but-unusable HumanDB); the CLI caller reports it
/// and exits nonzero. Internal invariant violations still panic.
///
/// `steering_min_gap` is the packer-side gate for severity-0 entries: the
/// full score vector's `max - min` must reach it, else the record could
/// never steer under the strictly-greater switch rule and is dropped
/// (severity > 0 corrections always pass). It is deliberately NOT part of
/// the mining checkpoint fingerprint -- it changes nothing about what
/// mining emits. The same holds for `gate` (the experimental risk gate):
/// pack-time only, default inert.
pub(crate) fn recompute_entries(
    entries: Vec<MineEntry>,
    db_path: &Path,
    options: &MillVariantOptions,
    human_db: Option<&Path>,
    human_config: HumanWeightConfig,
    steering_min_gap: u8,
    gate: RiskGateConfig,
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
    let mut risk_memo = RiskMemo::new();
    if gate.active() {
        assert!(
            gate.lambda.is_finite() && gate.lambda >= 0.0,
            "--steering-risk-lambda must be a finite non-negative number"
        );
        eprintln!(
            "[patch-pack] EXPERIMENTAL risk gate active: mode={} lambda={} \
             min_placing_ply_proxy={}",
            gate.mode.name(),
            gate.lambda,
            gate.min_placing_ply_proxy
        );
    }

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
    // Stage 5 (interleaved): the steering gate -- severity-0 entries whose
    // full candidate vector cannot steer (too few side-flipping optimal
    // candidates, or a gap below `steering_min_gap`) are dropped here,
    // AFTER the fusion map froze (their self-density stays a valid parent
    // signal) and BEFORE the budget sees them.
    let mut proofs: HashMap<u64, ChildProof> = HashMap::with_capacity(deduped.len());
    let mut kept: Vec<MineEntry> = Vec::with_capacity(deduped.len());
    for entry in deduped {
        let mut oracle = PlaneOracle {
            planes: &mut planes,
        };
        let (proof, diag) = derive_child_proof(
            &entry,
            &rules,
            options,
            &mut oracle,
            &trap_score_by_key,
            human.as_ref(),
            gate,
            &mut memo,
            &mut risk_memo,
            &mut stats,
        );
        // An ACTIVE gate that empties a severity-0 record's mask leaves a
        // record that can never steer: dead weight, dropped before the
        // gap gate even looks at it (severity > 0 stays regardless).
        // Deliberate attribution consequence of this ordering: a record
        // that would ALSO have failed the low-gap / few-flipped gate is
        // counted here, so under an active gate the drop counters skew
        // toward risk_gated_empty_steering_records relative to an
        // ungated pack -- an accepted experimental accounting, not a
        // like-for-like comparison across gate configurations.
        if drop_steering_for_empty_mask(gate.active(), entry.severity, proof.trap_score_mask) {
            stats.risk_gated_empty_steering_records += 1;
            continue;
        }
        match steering_gate(entry.severity, diag, steering_min_gap) {
            Ok(()) => {
                if entry.severity == 0 {
                    stats.steering_kept += 1;
                    stats.steering_gap_histogram[usize::from(diag.nibble_gap.min(15))] += 1;
                }
                stats.packed_positive += u64::from(proof.trap_score_mask.count_ones());
                proofs.insert(entry.key, proof);
                kept.push(entry);
            }
            Err(SteeringDrop::FewFlippedCandidates) => {
                stats.steering_dropped_few_candidates += 1;
            }
            Err(SteeringDrop::LowGap) => {
                stats.steering_dropped_low_gap += 1;
            }
        }
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
    eprintln!(
        "[patch-pack] steering gate (min_gap={steering_min_gap}): kept={} \
         dropped_few_flipped_candidates={} dropped_low_gap={}",
        stats.steering_kept, stats.steering_dropped_few_candidates, stats.steering_dropped_low_gap,
    );
    if stats.steering_gap_histogram.iter().any(|&n| n > 0) {
        let rendered: Vec<String> = stats
            .steering_gap_histogram
            .iter()
            .enumerate()
            .filter(|(_, n)| **n > 0)
            .map(|(gap, n)| format!("{gap}:{n}"))
            .collect();
        eprintln!(
            "[patch-pack] steering gap histogram (kept entries): {}",
            rendered.join(" ")
        );
    }
    if gate.active() {
        assert_eq!(
            stats.gate_filtered_positive,
            stats.gate_filtered_by_ply_proxy
                + stats.gate_filtered_by_risk
                + stats.gate_filtered_unresolved,
            "gate filter sub-buckets must partition the filtered total"
        );
        let ratio = |numerator: u64, denominator: u64| -> String {
            if denominator == 0 {
                "n/a".to_string()
            } else {
                format!("{:.4}", numerator as f64 / denominator as f64)
            }
        };
        eprintln!(
            "[patch-pack] risk gate (mode={} lambda={} min_placing_ply_proxy={}): \
             gate_seen_positive={} gate_passed_positive={} gate_filtered_positive={} \
             (by_ply_proxy={} by_risk={} unresolved={}) trap_unresolved_fusion_zeroed={}",
            gate.mode.name(),
            gate.lambda,
            gate.min_placing_ply_proxy,
            stats.gate_seen_positive,
            stats.gate_passed_positive,
            stats.gate_filtered_positive,
            stats.gate_filtered_by_ply_proxy,
            stats.gate_filtered_by_risk,
            stats.gate_filtered_unresolved,
            stats.gate_trap_unresolved_fusion_zeroed,
        );
        eprintln!(
            "[patch-pack] risk gate retention: gate_candidate_retention={} \
             packed_candidate_retention={} (packed_positive={}, pre-budget; top-16 \
             evictions stay a separate counter: {})",
            ratio(stats.gate_passed_positive, stats.gate_seen_positive),
            ratio(stats.packed_positive, stats.gate_seen_positive),
            stats.packed_positive,
            stats.top16_evictions,
        );
        eprintln!(
            "[patch-pack] own-risk samples (unique cache-miss positions, not per candidate \
             use): resolved={} unresolved={} terminal={} (risk memo: {} unique, {} hits); \
             candidate-level `unresolved={}` above means ZERO resolved samples for that \
             candidate -- partial unresolvedness still gates on the resolved mean",
            stats.own_risk_resolved_samples,
            stats.own_risk_unresolved_samples,
            stats.own_risk_terminal_samples,
            risk_memo.misses,
            risk_memo.hits,
            stats.gate_filtered_unresolved,
        );
        eprintln!(
            "[patch-pack] risk-gated empty steering records dropped: {}",
            stats.risk_gated_empty_steering_records
        );
    }
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
        entries: kept,
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
