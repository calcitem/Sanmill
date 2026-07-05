// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

//! Blocker tests for the v4 proof/steering derivation. Everything here is
//! deterministic and offline: canonical keys come from the tiny bundled
//! `std.secval` (sector metadata only), every WDL value comes from the
//! injected [`TableOracle`] table -- no test scans a real Perfect DB or
//! HumanDB hunting for positions with the right shape.

use perfect_db::patch::nibble_at;
use tgf_core::GameRules;
use tgf_mill::human_db_codec::{HumanTurn, parse_human_turn_notation};

use super::*;
use crate::mill_mine::entry::MineEntry;
use crate::mill_pack::human_weight::HumanSampleStats;

fn rules() -> MillRules {
    MillRules::new(MillVariantOptions::default())
}

fn options() -> MillVariantOptions {
    MillVariantOptions::default()
}

fn steering_entry(fen: &str, key: u64, best_child: u64) -> MineEntry {
    MineEntry {
        key,
        best_child,
        severity: 0,
        trap_score: 0,
        mass: 1.0,
        fen: fen.to_string(),
        depth_used: 0,
    }
}

/// Apply a sequence of human-notation moves from the initial position.
fn play(rules: &MillRules, tokens: &[&str]) -> tgf_core::GameStateSnapshot {
    let mut snap = rules.initial_state(&[]);
    for token in tokens {
        let turn = parse_human_turn_notation(rules, &snap, token).expect("scripted move");
        snap = match turn {
            HumanTurn::BaseOnly(action) => rules.apply(&snap, action),
            HumanTurn::BaseThenCapture { base, capture } => {
                let mid = rules.apply(&snap, base);
                rules.apply(&mid, capture)
            }
            HumanTurn::CaptureOnly(action) => rules.apply(&snap, action),
        };
    }
    snap
}

/// Sorted distinct child canonical keys of `snap`, mirroring the
/// derivation's BTreeMap ordering (index in this list == mask bit index).
fn child_keys_in_mask_order(
    rules: &MillRules,
    snap: &tgf_core::GameStateSnapshot,
    oracle: &mut TableOracle,
) -> Vec<u64> {
    let mut actions = tgf_core::ActionList::<256>::new();
    rules.legal_actions(snap, &mut actions);
    let mut keys: Vec<u64> = actions
        .as_slice()
        .iter()
        .filter_map(|&action| {
            let child = MillRules::decode_snapshot(rules.apply(snap, action));
            oracle.keys().canonical_key(&child, &options())
        })
        .collect();
    keys.sort_unstable();
    keys.dedup();
    keys
}

/// Plant `loser_value` behind the first `distinct_losers` distinct
/// grandchild canonical keys of `child_snap`. Because symmetric replies
/// fold to one key, a single planted key can cover several concrete
/// actions; the return value is the number of *actions* affected, which is
/// what the per-action density formula sees.
fn plant_replies(
    rules: &MillRules,
    child_snap: &tgf_core::GameStateSnapshot,
    oracle: &mut TableOracle,
    distinct_losers: usize,
    loser_value: i8,
) -> usize {
    let mut actions = tgf_core::ActionList::<256>::new();
    rules.legal_actions(child_snap, &mut actions);
    let mut planted: Vec<u64> = Vec::new();
    for &action in actions.as_slice() {
        let grandchild = MillRules::decode_snapshot(rules.apply(child_snap, action));
        let key = oracle.key_of(&grandchild, &options());
        if planted.len() < distinct_losers && !planted.contains(&key) {
            oracle.own_value_by_key.insert(key, loser_value);
        }
        if !planted.contains(&key) && oracle.own_value_by_key.get(&key) == Some(&loser_value) {
            planted.push(key);
        }
    }
    assert!(
        planted.len() >= distinct_losers,
        "position has too few distinct replies to plant"
    );
    // Count the actions whose grandchild key carries the planted value.
    actions
        .as_slice()
        .iter()
        .filter(|&&action| {
            let grandchild = MillRules::decode_snapshot(rules.apply(child_snap, action));
            let key = oracle.key_of(&grandchild, &options());
            oracle.own_value_by_key.get(&key) == Some(&loser_value)
        })
        .count()
}

#[test]
fn quantize_floors_positive_densities_at_one_and_clamps_at_fifteen() {
    assert_eq!(quantize(0.0), 0);
    assert_eq!(quantize(0.0001), 1, "tiny positive densities survive as 1");
    assert_eq!(quantize(0.5), 8);
    assert_eq!(quantize(1.0), 15);
    assert_eq!(quantize(2.5), 15, "densities above 1.0 clamp");
}

#[test]
#[should_panic(expected = "non-negative")]
fn quantize_rejects_negative_densities() {
    let _ = quantize(-0.1);
}

#[test]
fn encode_trap_scores_orders_by_score_then_key_and_evicts_beyond_sixteen() {
    let mut stats = RecomputeStats::default();
    // 20 positive scores on child indices 0..20: scores 1..=15 cycling, so
    // several ties exercise the key-ascending tie break.
    let scored: Vec<(u8, u64, usize)> = (0..20_usize)
        .map(|i| (((i % 15) + 1) as u8, 1000 + i as u64, i))
        .collect();
    let (mask, nibbles) = encode_trap_scores(scored.clone(), &mut stats);
    assert_eq!(stats.top16_evictions, 4);
    assert_eq!(mask.count_ones(), 16);

    // Expected survivors: sort by (score desc, key asc), keep 16.
    let mut expected = scored;
    expected.sort_by(|a, b| b.0.cmp(&a.0).then(a.1.cmp(&b.1)));
    expected.truncate(16);
    for &(nibble, _, index) in &expected {
        assert_ne!(mask & (1 << index), 0, "survivor index {index} must be set");
        let rank = trap_rank(mask, index).unwrap();
        assert_eq!(nibble_at(nibbles, rank), nibble);
    }
    // The evicted four (lowest scores, then highest keys) must be absent.
    let survivor_indices: std::collections::HashSet<usize> =
        expected.iter().map(|&(_, _, i)| i).collect();
    for index in 0..20 {
        assert_eq!(
            mask & (1 << index) != 0,
            survivor_indices.contains(&index),
            "index {index} presence must match the expected survivor set"
        );
    }
}

#[test]
fn density_memo_computes_the_uniform_formula_and_caches_by_key() {
    let rules = rules();
    let mut oracle = TableOracle::new();
    oracle.default_value = Some(0);

    // Child position: black to move after white places d6. Plant losing
    // replies (grandchild own-side value +1 => from black's side -1, best
    // stays 0): density = affected_actions / (2 * reply_count).
    let child_snap = play(&rules, &["d6"]);
    let child_state = MillRules::decode_snapshot(child_snap);
    let child_key = oracle.key_of(&child_state, &options());
    let affected = plant_replies(&rules, &child_snap, &mut oracle, 3, 1);
    assert!(affected >= 3, "at least the planted keys' actions");

    let mut actions = tgf_core::ActionList::<256>::new();
    rules.legal_actions(&child_snap, &mut actions);
    let reply_count = actions.as_slice().len() as f64;

    let mut memo = DensityMemo::new();
    let (density, best) = memo
        .density_and_best(child_key, &child_snap, &rules, &options(), &mut oracle)
        .expect("fully covered position");
    assert_eq!(best, 0, "best reply keeps the draw");
    assert!((density - affected as f64 / (2.0 * reply_count)).abs() < 1e-12);

    // Second call must be served from the memo.
    let again = memo
        .density_and_best(child_key, &child_snap, &rules, &options(), &mut oracle)
        .expect("cached");
    assert_eq!(again.0, density);
    assert_eq!(memo.hits, 1);
    assert_eq!(memo.misses, 1);
}

#[test]
fn density_memo_caches_coverage_gaps_as_none() {
    let rules = rules();
    let mut oracle = TableOracle::new(); // default_value: None => gaps
    let child_snap = play(&rules, &["d6"]);
    let child_state = MillRules::decode_snapshot(child_snap);
    let child_key = oracle.key_of(&child_state, &options());

    let mut memo = DensityMemo::new();
    assert!(
        memo.density_and_best(child_key, &child_snap, &rules, &options(), &mut oracle)
            .is_none()
    );
    assert!(
        memo.density_and_best(child_key, &child_snap, &rules, &options(), &mut oracle)
            .is_none()
    );
    assert_eq!(memo.hits, 1, "the None outcome is memoized too");
}

/// The main deterministic proof test on the initial position: 24 placing
/// children (all side-flipping), all draws => all optimal; three children
/// get distinguishable steering signals (planted density, stronger planted
/// density, fusion from a deduplicated child entry).
#[test]
fn derive_child_proof_scores_optimal_children_from_planted_values() {
    let rules = rules();
    let opts = options();
    let mut oracle = TableOracle::new();
    oracle.default_value = Some(0);

    let parent_snap = rules.initial_state(&[]);
    let parent_state = MillRules::decode_snapshot(parent_snap);
    let parent_key = oracle.key_of(&parent_state, &opts);
    let child_keys = child_keys_in_mask_order(&rules, &parent_snap, &mut oracle);
    // Symmetry folding collapses the 24 placements into a handful of
    // canonical children (corner / edge-mid / cross classes).
    assert!(child_keys.len() >= 3, "need at least three child classes");

    // Choose three distinct canonical children via concrete placements.
    let child_a = {
        let snap = play(&rules, &["d6"]);
        (
            snap,
            oracle.key_of(&MillRules::decode_snapshot(snap), &opts),
        )
    };
    let child_b = {
        let snap = play(&rules, &["a7"]);
        (
            snap,
            oracle.key_of(&MillRules::decode_snapshot(snap), &opts),
        )
    };
    let child_c = {
        let snap = play(&rules, &["b6"]);
        (
            snap,
            oracle.key_of(&MillRules::decode_snapshot(snap), &opts),
        )
    };
    assert_ne!(child_a.1, child_b.1);
    assert_ne!(child_a.1, child_c.1);
    assert_ne!(child_b.1, child_c.1);

    // Child A: 3 losing reply keys; child B: 8 losing reply keys (higher
    // density); child C: no density but a fused engine trap score.
    let affected_a = plant_replies(&rules, &child_a.0, &mut oracle, 3, 1);
    let affected_b = plant_replies(&rules, &child_b.0, &mut oracle, 8, 1);
    let mut trap_score_by_key = HashMap::new();
    trap_score_by_key.insert(child_c.1, 200_u8);
    let expected_nibble_c = u8_trap_score_to_nibble_for_fusion(200);
    assert!(
        expected_nibble_c >= 1,
        "a strong u8 score must survive fusion"
    );

    let entry = steering_entry(&rules.export_fen(&parent_state), parent_key, child_a.1);
    let mut memo = DensityMemo::new();
    let mut stats = RecomputeStats::default();
    let (proof, _) = derive_child_proof(
        &entry,
        &rules,
        &opts,
        &mut oracle,
        &trap_score_by_key,
        None,
        RiskGateConfig::default(),
        &mut memo,
        &mut RiskMemo::new(),
        &mut stats,
    );

    assert_eq!(proof.child_count as usize, child_keys.len());
    assert_eq!(
        proof.optimal_mask,
        (1_u64 << child_keys.len()) - 1,
        "all children are draws, so all are optimal"
    );
    assert_eq!(stats.same_side_children_zeroed, 0);

    // Reply counts for expected densities.
    let reply_count = |snap: &tgf_core::GameStateSnapshot| -> f64 {
        let mut actions = tgf_core::ActionList::<256>::new();
        rules.legal_actions(snap, &mut actions);
        actions.as_slice().len() as f64
    };
    let index_of = |key: u64| child_keys.iter().position(|&k| k == key).unwrap();
    let expected_nibble_a = quantize(affected_a as f64 / (2.0 * reply_count(&child_a.0)));
    let expected_nibble_b = quantize(affected_b as f64 / (2.0 * reply_count(&child_b.0)));

    for (key, expected) in [
        (child_a.1, expected_nibble_a),
        (child_b.1, expected_nibble_b),
        (child_c.1, expected_nibble_c),
    ] {
        let index = index_of(key);
        assert_ne!(
            proof.trap_score_mask & (1 << index),
            0,
            "child {key:#x} must carry a trap score"
        );
        let rank = trap_rank(proof.trap_score_mask, index).unwrap();
        assert_eq!(nibble_at(proof.optimal_trap_nibbles, rank), expected);
    }
    assert!(stats.fusion_won >= 1, "child C's nibble came from fusion");
    // Children without any signal stay out of the mask; every mask bit is
    // inside the optimal mask by construction.
    assert_eq!(
        proof.trap_score_mask & !proof.optimal_mask,
        0,
        "trap mask must be a subset of the optimal mask"
    );
}

/// A mill-forming placement keeps the mover on turn (pending removal):
/// that child may be optimal, but it must never carry a trap score, even
/// when a fused engine signal exists for it.
#[test]
fn derive_child_proof_zeroes_same_side_children_on_every_signal() {
    let rules = rules();
    let opts = options();
    let mut oracle = TableOracle::new();
    oracle.default_value = Some(0);

    // White d6, d5 placed; black b4, b2; white to place. d7 closes the
    // d5-d6-d7 mill -> same-side (mid-removal) child.
    let parent_snap = play(&rules, &["d6", "b4", "d5", "b2"]);
    let parent_state = MillRules::decode_snapshot(parent_snap);
    let parent_key = oracle.key_of(&parent_state, &opts);

    let mill_turn = parse_human_turn_notation(&rules, &parent_snap, "d7xb4").expect("mill move");
    let HumanTurn::BaseThenCapture { base, .. } = mill_turn else {
        panic!("d7 must form a mill");
    };
    let mill_child_snap = rules.apply(&parent_snap, base);
    let mill_child_state = MillRules::decode_snapshot(mill_child_snap);
    assert_eq!(
        mill_child_state.side_to_move(),
        parent_state.side_to_move(),
        "the mill child must keep the mover on turn"
    );
    let mill_child_key = oracle.key_of(&mill_child_state, &opts);

    // Make the mill child a win for white (own side) and every settled
    // child a draw, so the mill child is the unique optimal child.
    oracle.own_value_by_key.insert(mill_child_key, 1);
    // Fused signal for the mill child that must be ignored.
    let mut trap_score_by_key = HashMap::new();
    trap_score_by_key.insert(mill_child_key, 255_u8);

    let entry = steering_entry(&rules.export_fen(&parent_state), parent_key, mill_child_key);
    let mut memo = DensityMemo::new();
    let mut stats = RecomputeStats::default();
    let (proof, _) = derive_child_proof(
        &entry,
        &rules,
        &opts,
        &mut oracle,
        &trap_score_by_key,
        None,
        RiskGateConfig::default(),
        &mut memo,
        &mut RiskMemo::new(),
        &mut stats,
    );

    let child_keys = child_keys_in_mask_order(&rules, &parent_snap, &mut oracle);
    let mill_index = child_keys
        .iter()
        .position(|&k| k == mill_child_key)
        .expect("mill child is among the children");
    assert_eq!(
        proof.optimal_mask,
        1_u64 << mill_index,
        "the winning mill child is the only optimal child"
    );
    assert_eq!(
        proof.trap_score_mask, 0,
        "a same-side child never carries a trap score, fused signal or not"
    );
    assert!(stats.same_side_children_zeroed >= 1);
    assert_eq!(stats.fusion_won, 0);
    assert_eq!(
        stats.empty_trap_mask_records, 1,
        "an all-zero mask on a record with optimal children is counted"
    );
}

/// Human behavior weighting flows into the nibble via
/// `HumanWeights::behavior_density`, and the divergence histogram tracks
/// the shift against the uniform nibble.
#[test]
fn derive_child_proof_blends_behavior_density_when_gates_pass() {
    use super::super::human_weight::{
        HumanResponses, HumanWeightConfig, HumanWeightStats, HumanWeights, ResponseTarget,
    };

    let rules = rules();
    let opts = options();
    let mut oracle = TableOracle::new();
    oracle.default_value = Some(0);

    let parent_snap = rules.initial_state(&[]);
    let parent_state = MillRules::decode_snapshot(parent_snap);
    let parent_key = oracle.key_of(&parent_state, &opts);

    let child_snap = play(&rules, &["d6"]);
    let child_state = MillRules::decode_snapshot(child_snap);
    let child_key = oracle.key_of(&child_state, &opts);

    // Uniform density 0 (all replies draw). Human data: black's observed
    // replies overwhelmingly land on a grandchild that is LOST for black
    // (own value -1 => severity 2 from the child's best 0... best is 0,
    // reply from black's view = -1 -> severity 1). Wait: severity =
    // best_value_C - reply_value where both are from black's (the child's
    // mover's) perspective; reply key's raw own value -1 with
    // sign_to_parent -1 gives reply +1? Keep it simple: encode the reply
    // value directly through a Terminal target.
    let mut turn = HashMap::new();
    turn.insert(
        child_key,
        HumanResponses {
            targets: HashMap::from([(ResponseTarget::Terminal(-1), 40_u64)]),
            unresolved_total: 0,
        },
    );
    let human = HumanWeights {
        turn,
        step: HashMap::new(),
        parent_snap_by_key: HashMap::new(),
        config: HumanWeightConfig {
            min_samples: 10,
            min_coverage: 0.8,
            shrinkage_k: 0.0, // no shrinkage: blended == human density
            allow_lossy: false,
        },
        stats: HumanWeightStats::default(),
    };

    let entry = steering_entry(&rules.export_fen(&parent_state), parent_key, child_key);
    let mut memo = DensityMemo::new();
    let mut stats = RecomputeStats::default();
    let (proof, _) = derive_child_proof(
        &entry,
        &rules,
        &opts,
        &mut oracle,
        &HashMap::new(),
        Some(&human),
        RiskGateConfig::default(),
        &mut memo,
        &mut RiskMemo::new(),
        &mut stats,
    );

    // best_value_C = 0 (draws), human replies all -1 => severity 1 on all
    // 40 samples: density_human = 40 / (2 * 40) = 0.5 => nibble 8.
    let child_keys = child_keys_in_mask_order(&rules, &parent_snap, &mut oracle);
    let index = child_keys.iter().position(|&k| k == child_key).unwrap();
    let rank = trap_rank(proof.trap_score_mask, index).expect("behavior child is scored");
    assert_eq!(nibble_at(proof.optimal_trap_nibbles, rank), 8);
    assert_eq!(stats.nibble_from_behavior, 1);
    // Divergence bucket: behavior 8 - uniform 0 = +8.
    assert_eq!(stats.divergence[(8 + 15) as usize], 1);
}

/// A/B proof: packing the same entry with and without behavior weighting
/// must change the encoded nibbles in BOTH directions -- upward when
/// humans blunder more than geometry suggests (covered by the blend test
/// above) and downward to the point of dropping the child from the mask
/// when observed human replies are clean. This is the wiring guarantee;
/// hit rates on a real database are a separate, statistical question.
#[test]
fn behavior_weighting_changes_nibbles_against_the_uniform_pack() {
    use super::super::human_weight::{
        HumanResponses, HumanWeightConfig, HumanWeightStats, HumanWeights, ResponseTarget,
    };

    let rules = rules();
    let opts = options();
    let mut oracle = TableOracle::new();
    oracle.default_value = Some(0);

    let parent_snap = rules.initial_state(&[]);
    let parent_state = MillRules::decode_snapshot(parent_snap);
    let parent_key = oracle.key_of(&parent_state, &opts);
    let child_snap = play(&rules, &["d6"]);
    let child_state = MillRules::decode_snapshot(child_snap);
    let child_key = oracle.key_of(&child_state, &opts);

    // Geometry says the child is trappy (planted losing replies)...
    plant_replies(&rules, &child_snap, &mut oracle, 6, 1);
    let entry = steering_entry(&rules.export_fen(&parent_state), parent_key, child_key);

    // A: uniform-only pack.
    let mut memo_a = DensityMemo::new();
    let mut stats_a = RecomputeStats::default();
    let (proof_a, _) = derive_child_proof(
        &entry,
        &rules,
        &opts,
        &mut oracle,
        &HashMap::new(),
        None,
        RiskGateConfig::default(),
        &mut memo_a,
        &mut RiskMemo::new(),
        &mut stats_a,
    );
    let child_keys = child_keys_in_mask_order(&rules, &parent_snap, &mut oracle);
    let index = child_keys.iter().position(|&k| k == child_key).unwrap();
    assert_ne!(
        proof_a.trap_score_mask & (1 << index),
        0,
        "uniform pack must score the geometrically trappy child"
    );

    // B: behavior data says observed humans never blunder there (all
    // replies draw), with no shrinkage -- the blended density collapses
    // to 0 and the child must drop out of the mask entirely.
    let mut turn = HashMap::new();
    turn.insert(
        child_key,
        HumanResponses {
            targets: HashMap::from([(ResponseTarget::Terminal(0), 40_u64)]),
            unresolved_total: 0,
        },
    );
    let human = HumanWeights {
        turn,
        step: HashMap::new(),
        parent_snap_by_key: HashMap::new(),
        config: HumanWeightConfig {
            min_samples: 10,
            min_coverage: 0.8,
            shrinkage_k: 0.0,
            allow_lossy: false,
        },
        stats: HumanWeightStats::default(),
    };
    let mut memo_b = DensityMemo::new();
    let mut stats_b = RecomputeStats::default();
    let (proof_b, _) = derive_child_proof(
        &entry,
        &rules,
        &opts,
        &mut oracle,
        &HashMap::new(),
        Some(&human),
        RiskGateConfig::default(),
        &mut memo_b,
        &mut RiskMemo::new(),
        &mut stats_b,
    );
    assert_eq!(
        proof_b.trap_score_mask & (1 << index),
        0,
        "behavior evidence of clean human play must drop the child from the mask"
    );
    assert_ne!(
        proof_a, proof_b,
        "the A/B packs must differ when behavior data contradicts geometry"
    );
    assert_eq!(stats_b.nibble_from_behavior, 1);
    // The divergence histogram records the downward shift.
    let negative_shift: u64 = stats_b.divergence[..15].iter().sum();
    assert_eq!(negative_shift, 1, "shift must land in a negative bucket");
}

/// The packer-side steering gate: severity>0 corrections always pass;
/// severity-0 entries need >= 2 side-flipping optimal candidates AND a
/// full-vector nibble gap of at least `min_gap`.
#[test]
fn steering_gate_drops_uninformative_severity_zero_entries() {
    let diag = |flipped: u32, gap: u8| SteeringDiag {
        flipped_optimal: flipped,
        nibble_gap: gap,
    };
    // Blunders pass regardless of shape.
    assert_eq!(steering_gate(1, diag(0, 0), 3), Ok(()));
    assert_eq!(steering_gate(2, diag(1, 0), 15), Ok(()));
    // Structural half: fewer than two side-flipping candidates.
    assert_eq!(
        steering_gate(0, diag(0, 0), 0),
        Err(SteeringDrop::FewFlippedCandidates)
    );
    assert_eq!(
        steering_gate(0, diag(1, 5), 0),
        Err(SteeringDrop::FewFlippedCandidates)
    );
    // Gap half: flat vectors cannot steer under strictly-greater.
    assert_eq!(steering_gate(0, diag(2, 2), 3), Err(SteeringDrop::LowGap));
    assert_eq!(steering_gate(0, diag(2, 3), 3), Ok(()));
    assert_eq!(steering_gate(0, diag(4, 0), 0), Ok(()));
}

/// The gap diagnostics come from the FULL side-flipping candidate vector,
/// including zero-nibble candidates that never enter the packed mask.
#[test]
fn derive_child_proof_reports_full_vector_gap_diagnostics() {
    let rules = rules();
    let opts = options();
    let mut oracle = TableOracle::new();
    oracle.default_value = Some(0);

    let parent_snap = rules.initial_state(&[]);
    let parent_state = MillRules::decode_snapshot(parent_snap);
    let parent_key = oracle.key_of(&parent_state, &opts);
    let child_keys = child_keys_in_mask_order(&rules, &parent_snap, &mut oracle);

    // One trappy child, everything else flat zero: the gap must span the
    // whole vector (max nibble - 0), not just the masked survivors.
    let trappy = play(&rules, &["d6"]);
    plant_replies(&rules, &trappy, &mut oracle, 8, 1);
    let trappy_key = oracle.key_of(&MillRules::decode_snapshot(trappy), &opts);

    let entry = steering_entry(&rules.export_fen(&parent_state), parent_key, trappy_key);
    let mut memo = DensityMemo::new();
    let mut stats = RecomputeStats::default();
    let (proof, diag) = derive_child_proof(
        &entry,
        &rules,
        &opts,
        &mut oracle,
        &HashMap::new(),
        None,
        RiskGateConfig::default(),
        &mut memo,
        &mut RiskMemo::new(),
        &mut stats,
    );
    assert_eq!(
        diag.flipped_optimal as usize,
        child_keys.len(),
        "every placing child flips the side and is optimal here"
    );
    let index = child_keys.iter().position(|&k| k == trappy_key).unwrap();
    let rank = trap_rank(proof.trap_score_mask, index).expect("trappy child is masked");
    let trappy_nibble = nibble_at(proof.optimal_trap_nibbles, rank);
    assert_eq!(
        diag.nibble_gap, trappy_nibble,
        "gap = trappy nibble - flat zero, measured over the full vector"
    );
}

#[test]
fn derive_child_proof_counts_unresolved_children_without_scoring_them() {
    let rules = rules();
    let opts = options();
    // No default value: every child's replies are coverage gaps, so
    // densities are unresolvable; children themselves still get root
    // values planted so the optimal mask exists.
    let mut oracle = TableOracle::new();

    let parent_snap = rules.initial_state(&[]);
    let parent_state = MillRules::decode_snapshot(parent_snap);
    let parent_key = oracle.key_of(&parent_state, &opts);
    let child_keys = child_keys_in_mask_order(&rules, &parent_snap, &mut oracle);
    for &key in &child_keys {
        oracle.own_value_by_key.insert(key, 0);
    }

    let entry = steering_entry(&rules.export_fen(&parent_state), parent_key, child_keys[0]);
    let mut memo = DensityMemo::new();
    let mut stats = RecomputeStats::default();
    let (proof, _) = derive_child_proof(
        &entry,
        &rules,
        &opts,
        &mut oracle,
        &HashMap::new(),
        None,
        RiskGateConfig::default(),
        &mut memo,
        &mut RiskMemo::new(),
        &mut stats,
    );
    assert_eq!(proof.trap_score_mask, 0);
    assert_eq!(
        stats.best_value_unresolved_parent_count,
        child_keys.len() as u64,
        "every optimal child's density was unresolvable"
    );
}

#[test]
fn risk_gate_decision_covers_both_modes_and_every_bucket() {
    let gate = |mode, lambda, min_ply| RiskGateConfig {
        mode,
        lambda,
        min_placing_ply_proxy: min_ply,
    };
    let none = gate(RiskGateMode::None, 1.0, 0);
    let absolute = gate(RiskGateMode::Absolute, 2.0, 0);
    let sibling = gate(RiskGateMode::SiblingDelta, 1.0, 0);

    // Inert mode passes anything once past the ply floor.
    assert_eq!(
        risk_gate_decision(none, 0, None, None, None, None),
        GateDecision::Pass
    );
    // The ply-proxy floor fires first, regardless of mode or risk data.
    assert_eq!(
        risk_gate_decision(gate(RiskGateMode::None, 1.0, 6), 5, None, None, None, None),
        GateDecision::FilteredByPlyProxy
    );
    assert_eq!(
        risk_gate_decision(
            gate(RiskGateMode::Absolute, 1.0, 6),
            5,
            None,
            Some(1.0),
            None,
            None
        ),
        GateDecision::FilteredByPlyProxy
    );

    // Absolute: boundary equality passes, excess risk fails, a candidate
    // with zero resolved own-risk samples is filtered as unresolved.
    assert_eq!(
        risk_gate_decision(absolute, 9, Some(0.2), Some(0.1), None, None),
        GateDecision::Pass
    );
    assert_eq!(
        risk_gate_decision(absolute, 9, Some(0.2001), Some(0.1), None, None),
        GateDecision::FilteredByRisk
    );
    assert_eq!(
        risk_gate_decision(absolute, 9, None, Some(0.5), None, None),
        GateDecision::FilteredUnresolved
    );
    // Unresolved trap density scores the trap term as 0: only zero risk
    // passes.
    assert_eq!(
        risk_gate_decision(absolute, 9, Some(0.01), None, None, None),
        GateDecision::FilteredByRisk
    );
    assert_eq!(
        risk_gate_decision(absolute, 9, Some(0.0), None, None, None),
        GateDecision::Pass
    );

    // Sibling-delta: excess risk over the safest sibling must be covered
    // by lambda times the excess trap over the least-trappy sibling.
    assert_eq!(
        risk_gate_decision(sibling, 9, Some(0.3), Some(0.5), Some(0.1), Some(0.2)),
        GateDecision::Pass,
        "0.2 excess risk <= 1.0 * 0.3 excess trap"
    );
    assert_eq!(
        risk_gate_decision(sibling, 9, Some(0.5), Some(0.25), Some(0.1), Some(0.2)),
        GateDecision::FilteredByRisk,
        "0.4 excess risk > 1.0 * 0.05 excess trap"
    );
    assert_eq!(
        risk_gate_decision(sibling, 9, Some(0.3), Some(0.4), Some(0.1), Some(0.2)),
        GateDecision::Pass,
        "boundary equality passes"
    );
    // The safest sibling itself always passes (zero excess risk), even
    // with nothing measurable on the trap side.
    assert_eq!(
        risk_gate_decision(sibling, 9, Some(0.1), None, Some(0.1), None),
        GateDecision::Pass
    );
    // No resolved sibling trap minimum: trap_delta is 0, so positive
    // excess risk fails -- an unresolved sibling never anchors a 0 min.
    assert_eq!(
        risk_gate_decision(sibling, 9, Some(0.2), Some(0.9), Some(0.1), None),
        GateDecision::FilteredByRisk
    );
    // A trap density below the sibling minimum clamps to zero excess.
    assert_eq!(
        risk_gate_decision(sibling, 9, Some(0.2), Some(0.1), Some(0.1), Some(0.2)),
        GateDecision::FilteredByRisk
    );
    assert_eq!(
        risk_gate_decision(sibling, 9, None, Some(0.5), Some(0.0), Some(0.0)),
        GateDecision::FilteredUnresolved
    );
}

#[test]
fn net_nibble_charges_risk_on_the_quantized_scale() {
    // No risk: the gain passes through untouched.
    assert_eq!(net_nibble(8, 0.0, 1.0), 8);
    // 0.2 * 15 = 3 quanta of risk cost.
    assert_eq!(net_nibble(8, 0.2, 1.0), 5);
    // Lambda scales the cost: 0.2 * 15 * 2 = 6.
    assert_eq!(net_nibble(8, 0.2, 2.0), 2);
    // Half-down rounding: exactly half a quantum (0.5) is not charged...
    assert_eq!(net_nibble(8, 0.5 / 15.0, 1.0), 8);
    // ...but anything strictly above half a quantum is.
    assert_eq!(net_nibble(8, 0.51 / 15.0, 1.0), 7);
    // The cost saturates at zero instead of going negative.
    assert_eq!(net_nibble(3, 1.0, 1.0), 0);
    // Zero-gain candidates stay zero regardless of risk.
    assert_eq!(net_nibble(0, 0.7, 1.0), 0);
}

#[test]
fn net_gate_decision_buckets_and_stored_values() {
    let gate = |lambda: f64, min_ply: u32| RiskGateConfig {
        mode: RiskGateMode::Net,
        lambda,
        min_placing_ply_proxy: min_ply,
    };
    // Ply floor fires first and stores nothing.
    assert_eq!(
        net_gate_decision(gate(1.0, 6), 5, 8, Some(0.0)),
        (GateDecision::FilteredByPlyProxy, 0)
    );
    // Unresolved own-risk (zero resolved samples) filters.
    assert_eq!(
        net_gate_decision(gate(1.0, 0), 9, 8, None),
        (GateDecision::FilteredUnresolved, 0)
    );
    // A surviving net is stored as the (possibly rewritten) value.
    assert_eq!(
        net_gate_decision(gate(1.0, 0), 9, 8, Some(0.2)),
        (GateDecision::Pass, 5)
    );
    assert_eq!(
        net_gate_decision(gate(1.0, 0), 9, 8, Some(0.0)),
        (GateDecision::Pass, 8)
    );
    // A net consumed entirely by the risk cost is a risk filter.
    assert_eq!(
        net_gate_decision(gate(1.0, 0), 9, 2, Some(0.5)),
        (GateDecision::FilteredByRisk, 0)
    );
}

#[test]
fn net_mode_rewrites_stored_values_and_keeps_the_runtime_rule_baseline_relative() {
    let rules = rules();
    let opts = options();
    let mut oracle = TableOracle::new();
    oracle.default_value = Some(0);
    let (entry, child_a, child_c) = risky_and_safe_trappy_children(&rules, &opts, &mut oracle);

    let risk_c = measured_risk(&rules, &opts, &mut oracle, &play(&rules, &["b6"]))
        .expect("C's continuations are covered");
    assert!(risk_c > 0.0);

    // Deterministic high gain for C through the fusion channel (255 maps
    // to nibble 15), leaving its replies -- and thus its own-turn risk --
    // untouched.
    let mut trap_map = HashMap::new();
    trap_map.insert(child_c, 255_u8);

    let parent_snap = rules.initial_state(&[]);
    let child_keys = child_keys_in_mask_order(&rules, &parent_snap, &mut oracle);
    let index_of = |key: u64| child_keys.iter().position(|&k| k == key).unwrap();
    let nibble_of = |proof: &ChildProof, key: u64| -> Option<u8> {
        trap_rank(proof.trap_score_mask, index_of(key))
            .map(|rank| nibble_at(proof.optimal_trap_nibbles, rank))
    };

    // Reference gains from the inert pipeline.
    let mut stats_off = RecomputeStats::default();
    let (proof_off, _) = derive_child_proof(
        &entry,
        &rules,
        &opts,
        &mut oracle,
        &trap_map,
        None,
        RiskGateConfig::default(),
        &mut DensityMemo::new(),
        &mut RiskMemo::new(),
        &mut stats_off,
    );
    let gain_a = nibble_of(&proof_off, child_a).expect("A is trappy");
    let gain_c = nibble_of(&proof_off, child_c).expect("C is trappy");
    assert_eq!(gain_c, 15, "fusion 255 pins C's gain to the nibble max");

    // Pick lambda so C's risk cost rewrites its value without zeroing it:
    // cost of exactly 1 quantum needs lambda * risk_c * 15 in (0.5, 1.5].
    let lambda = 1.0 / (risk_c * 15.0);
    let expected_c = net_nibble(gain_c, risk_c, lambda);
    assert!(
        expected_c >= 1 && expected_c < gain_c,
        "one-quantum rewrite"
    );

    let gate = RiskGateConfig {
        mode: RiskGateMode::Net,
        lambda,
        min_placing_ply_proxy: 0,
    };
    let mut stats_net = RecomputeStats::default();
    let (proof_net, _) = derive_child_proof(
        &entry,
        &rules,
        &opts,
        &mut oracle,
        &trap_map,
        None,
        gate,
        &mut DensityMemo::new(),
        &mut RiskMemo::new(),
        &mut stats_net,
    );
    assert_eq!(
        nibble_of(&proof_net, child_a),
        Some(gain_a),
        "a risk-free candidate's stored value is its unchanged gain"
    );
    assert_eq!(
        nibble_of(&proof_net, child_c),
        Some(expected_c),
        "a risky candidate's stored value is its net"
    );
    assert_eq!(stats_net.gate_net_value_rewrites, 1);
    assert_eq!(stats_net.gate_passed_positive, 2);
    assert_eq!(proof_net.optimal_mask, proof_off.optimal_mask);

    // A large lambda zeroes C's net out of the mask entirely.
    let gate_hard = RiskGateConfig {
        mode: RiskGateMode::Net,
        lambda: f64::from(gain_c) / (risk_c * 15.0) + 1.0,
        min_placing_ply_proxy: 0,
    };
    let mut stats_hard = RecomputeStats::default();
    let (proof_hard, _) = derive_child_proof(
        &entry,
        &rules,
        &opts,
        &mut oracle,
        &trap_map,
        None,
        gate_hard,
        &mut DensityMemo::new(),
        &mut RiskMemo::new(),
        &mut stats_hard,
    );
    assert_eq!(
        nibble_of(&proof_hard, child_c),
        None,
        "net 0 leaves the mask"
    );
    assert_eq!(stats_hard.gate_filtered_by_risk, 1);
}

#[test]
fn active_gate_reports_the_post_gate_gap_not_the_pre_gate_one() {
    let rules = rules();
    let opts = options();
    let mut oracle = TableOracle::new();
    oracle.default_value = Some(0);
    let (entry, _, child_c) = risky_and_safe_trappy_children(&rules, &opts, &mut oracle);

    // Boost C's gain through the FUSION channel (external signal, does
    // not touch C's replies or own-turn risk): the pre-gate gap is then
    // dominated by C, so filtering C must shrink the gap.
    let mut trap_map = HashMap::new();
    trap_map.insert(child_c, 255_u8);

    let parent_snap = rules.initial_state(&[]);
    let child_keys = child_keys_in_mask_order(&rules, &parent_snap, &mut oracle);
    let index_of = |key: u64| child_keys.iter().position(|&k| k == key).unwrap();

    let mut stats_off = RecomputeStats::default();
    let (proof_off, diag_off) = derive_child_proof(
        &entry,
        &rules,
        &opts,
        &mut oracle,
        &trap_map,
        None,
        RiskGateConfig::default(),
        &mut DensityMemo::new(),
        &mut RiskMemo::new(),
        &mut stats_off,
    );
    let rank_c = trap_rank(proof_off.trap_score_mask, index_of(child_c)).expect("C masked");
    let gain_c = nibble_at(proof_off.optimal_trap_nibbles, rank_c);

    // Absolute gate with lambda 0 filters every positive-risk candidate
    // (C) while zero-risk A survives: the post-gate vector loses C.
    let gate = RiskGateConfig {
        mode: RiskGateMode::Absolute,
        lambda: 0.0,
        min_placing_ply_proxy: 0,
    };
    let mut stats_on = RecomputeStats::default();
    let (proof_on, diag_on) = derive_child_proof(
        &entry,
        &rules,
        &opts,
        &mut oracle,
        &trap_map,
        None,
        gate,
        &mut DensityMemo::new(),
        &mut RiskMemo::new(),
        &mut stats_on,
    );
    assert_eq!(proof_on.trap_score_mask & (1 << index_of(child_c)), 0);
    assert_eq!(
        diag_off.nibble_gap, gain_c,
        "pre-gate gap is C's gain over the flat-zero siblings"
    );
    assert!(
        diag_on.nibble_gap < diag_off.nibble_gap,
        "post-gate gap must reflect the filtered vector \
         (pre {}, post {})",
        diag_off.nibble_gap,
        diag_on.nibble_gap
    );
    assert_eq!(
        diag_on.flipped_optimal, diag_off.flipped_optimal,
        "the structural candidate count is not gap-dependent"
    );
}

#[test]
#[should_panic(expected = "resolved candidate implies a resolved sibling risk minimum")]
fn sibling_delta_asserts_when_a_resolved_candidate_has_no_risk_minimum() {
    let gate = RiskGateConfig {
        mode: RiskGateMode::SiblingDelta,
        lambda: 1.0,
        min_placing_ply_proxy: 0,
    };
    let _ = risk_gate_decision(gate, 9, Some(0.1), Some(0.1), None, None);
}

#[test]
fn empty_mask_drop_applies_to_active_gate_severity_zero_only() {
    assert!(drop_steering_for_empty_mask(true, 0, 0));
    assert!(
        !drop_steering_for_empty_mask(true, 0, 0b100),
        "a surviving mask keeps the record"
    );
    assert!(
        !drop_steering_for_empty_mask(true, 1, 0),
        "severity > 0 corrections are never dropped for an empty mask"
    );
    assert!(
        !drop_steering_for_empty_mask(false, 0, 0),
        "an inactive gate must not change the existing empty-mask behavior"
    );
}

#[test]
fn placing_ply_proxy_counts_placements_and_saturates_in_moving_phase() {
    let rules = rules();
    let opts = options();
    let initial = MillRules::decode_snapshot(rules.initial_state(&[]));
    assert_eq!(placing_ply_proxy(&initial, &opts), 0);
    let after_three = MillRules::decode_snapshot(play(&rules, &["d6", "b4", "d5"]));
    assert_eq!(placing_ply_proxy(&after_three, &opts), 3);
    // Import-adapter override to a moving-phase hand count: the proxy
    // saturates at 2 * piece_count, so any threshold up to 18 passes.
    let mut moving = MillRules::decode_snapshot(play(&rules, &["d6", "b4", "d5"]));
    moving.set_pieces_in_hand([0, 0], &opts);
    assert_eq!(placing_ply_proxy(&moving, &opts), 18);
}

/// Legal-action count of a snapshot (own-risk samples are per action, not
/// per canonical class).
fn legal_count(rules: &MillRules, snap: &tgf_core::GameStateSnapshot) -> usize {
    let mut actions = tgf_core::ActionList::<256>::new();
    rules.legal_actions(snap, &mut actions);
    actions.as_slice().len()
}

#[test]
fn own_turn_risk_means_over_our_turn_nodes_and_memoizes() {
    let rules = rules();
    let opts = options();
    let mut oracle = TableOracle::new();
    oracle.default_value = Some(0);

    // Child: black to move after white d6 (parent side = white/0). Every
    // black reply preserves the draw and hands the turn back to white.
    let child_snap = play(&rules, &["d6"]);
    let child_key = oracle.key_of(&MillRules::decode_snapshot(child_snap), &opts);

    // Plant a positive density under the d5-reply node. Symmetric black
    // replies fold to the same canonical node key and (through the
    // canonical grandchild keys) see the same density, so the expected
    // mean weighs the planted density by its reply-class size.
    let d5_node = {
        let turn = parse_human_turn_notation(&rules, &child_snap, "d5").expect("legal reply");
        let HumanTurn::BaseOnly(action) = turn else {
            panic!("a plain placement");
        };
        rules.apply(&child_snap, action)
    };
    let d5_node_key = oracle.key_of(&MillRules::decode_snapshot(d5_node), &opts);
    plant_replies(&rules, &d5_node, &mut oracle, 4, 1);

    let reply_count = legal_count(&rules, &child_snap);
    let mut class_size = 0_usize;
    {
        let mut actions = tgf_core::ActionList::<256>::new();
        rules.legal_actions(&child_snap, &mut actions);
        for &action in actions.as_slice() {
            let node = MillRules::decode_snapshot(rules.apply(&child_snap, action));
            if oracle.key_of(&node, &opts) == d5_node_key {
                class_size += 1;
            }
        }
    }
    assert!(class_size >= 1);
    let d5_density = {
        let mut probe = DensityMemo::new();
        probe
            .density_and_best(d5_node_key, &d5_node, &rules, &opts, &mut oracle)
            .expect("fully covered")
            .0
    };
    assert!(
        d5_density > 0.0,
        "the planted node must be measurably risky"
    );
    let expected_mean = class_size as f64 * d5_density / reply_count as f64;

    let mut memo = DensityMemo::new();
    let mut risk_memo = RiskMemo::new();
    let mut stats = RecomputeStats::default();
    let risk = risk_memo.own_turn_risk(
        child_key,
        &child_snap,
        0,
        &rules,
        &opts,
        &mut oracle,
        &mut memo,
        &mut stats,
    );
    assert_eq!(risk.resolved_samples as usize, reply_count);
    assert_eq!(risk.unresolved_samples, 0);
    assert_eq!(risk.terminal_samples, 0);
    let mean = risk.mean.expect("resolved samples exist");
    assert!((mean - expected_mean).abs() < 1e-12);
    assert_eq!(stats.own_risk_resolved_samples as usize, reply_count);

    // Second use is a memo hit and must NOT re-report samples (the
    // counters are unique cache-miss samples, not per-candidate-use).
    let again = risk_memo.own_turn_risk(
        child_key,
        &child_snap,
        0,
        &rules,
        &opts,
        &mut oracle,
        &mut memo,
        &mut stats,
    );
    assert_eq!(again, risk);
    assert_eq!(risk_memo.hits, 1);
    assert_eq!(stats.own_risk_resolved_samples as usize, reply_count);
}

#[test]
fn own_turn_risk_is_bitwise_invariant_across_symmetric_orientations() {
    // d6 and b4 are 90-degree rotations of each other: the same canonical
    // child reached through two concrete orientations that enumerate
    // replies (and thus sum densities) in different orders. The pack's
    // memo serves whichever orientation got there first while the audit
    // recomputes cold from its own entry's orientation, so the mean must
    // be a pure function of the canonical position -- bit for bit.
    let rules = rules();
    let opts = options();
    let mut oracle = TableOracle::new();
    oracle.default_value = Some(0);

    let snap_a = play(&rules, &["d6"]);
    let snap_b = play(&rules, &["b4"]);
    let key_a = oracle.key_of(&MillRules::decode_snapshot(snap_a), &opts);
    let key_b = oracle.key_of(&MillRules::decode_snapshot(snap_b), &opts);
    assert_eq!(key_a, key_b, "rotations must fold to one canonical child");

    // Distinct fractional densities under several reply classes of the
    // d6 orientation (canonical grandchild keys are shared with b4's).
    let mut planted = 0_usize;
    let mut actions = tgf_core::ActionList::<256>::new();
    rules.legal_actions(&snap_a, &mut actions);
    for (nth, &action) in actions.as_slice().iter().enumerate() {
        if nth % 5 != 0 || planted >= 4 {
            continue;
        }
        planted += 1;
        let node = rules.apply(&snap_a, action);
        plant_replies(&rules, &node, &mut oracle, 1 + planted, 1);
    }
    assert_eq!(planted, 4);

    let risk_of = |snap: &tgf_core::GameStateSnapshot, oracle: &mut TableOracle| {
        RiskMemo::new().own_turn_risk(
            key_a,
            snap,
            0,
            &rules,
            &opts,
            oracle,
            &mut DensityMemo::new(),
            &mut RecomputeStats::default(),
        )
    };
    let risk_a = risk_of(&snap_a, &mut oracle);
    let risk_b = risk_of(&snap_b, &mut oracle);
    assert!(risk_a.mean.expect("covered") > 0.0);
    assert_eq!(risk_a, risk_b, "orientation must not leak into the mean");
}

#[test]
fn own_turn_risk_walks_the_opponent_removal_layer_back_to_our_turn() {
    let rules = rules();
    let opts = options();
    let mut oracle = TableOracle::new();
    oracle.default_value = Some(0);

    // Child: black to move with b4+b6 placed and b2 open (parent side =
    // white). The b2 reply forms the b2-b4-b6 mill and keeps black on
    // turn for exactly one removal layer over white's d6/d5/a1.
    let child_snap = play(&rules, &["d6", "b4", "d5", "b6", "a1"]);
    let child_key = oracle.key_of(&MillRules::decode_snapshot(child_snap), &opts);
    let reply_count = legal_count(&rules, &child_snap);

    let mut memo = DensityMemo::new();
    let mut risk_memo = RiskMemo::new();
    let mut stats = RecomputeStats::default();
    let risk = risk_memo.own_turn_risk(
        child_key,
        &child_snap,
        0,
        &rules,
        &opts,
        &mut oracle,
        &mut memo,
        &mut stats,
    );
    // Every reply preserves the draw: the mill reply contributes one
    // sample per preserving removal (3 white targets), every other reply
    // contributes its own-turn node directly.
    assert_eq!(risk.terminal_samples, 0);
    assert_eq!(risk.unresolved_samples, 0);
    assert_eq!(risk.resolved_samples as usize, (reply_count - 1) + 3);
    assert_eq!(risk.mean, Some(0.0), "no planted losers anywhere");
}

#[test]
fn own_turn_risk_counts_terminal_removals_without_scoring_them() {
    let rules = rules();
    let opts = options();
    let mut oracle = TableOracle::new();
    oracle.default_value = Some(0);

    // Same shape as the removal-layer test, but white has nothing left in
    // hand (import-adapter override): any removal drops white below three
    // total pieces and ends the game inside the walk.
    let mut child_state = MillRules::decode_snapshot(play(&rules, &["d6", "b4", "d5", "b6", "a1"]));
    child_state.set_pieces_in_hand([0, 7], &opts);
    let child_snap = rules.encode_state(child_state.clone());
    let child_key = oracle.key_of(&child_state, &opts);
    let reply_count = legal_count(&rules, &child_snap);

    let mut memo = DensityMemo::new();
    let mut risk_memo = RiskMemo::new();
    let mut stats = RecomputeStats::default();
    let risk = risk_memo.own_turn_risk(
        child_key,
        &child_snap,
        0,
        &rules,
        &opts,
        &mut oracle,
        &mut memo,
        &mut stats,
    );
    assert_eq!(
        risk.terminal_samples, 3,
        "each of the three removals ends the game and is counted, never scored"
    );
    assert_eq!(risk.resolved_samples as usize, reply_count - 1);
    assert_eq!(risk.unresolved_samples, 0);
    assert_eq!(stats.own_risk_terminal_samples, 3);
}

#[test]
fn own_turn_risk_with_zero_resolved_samples_reports_none() {
    let rules = rules();
    let opts = options();
    // No default value: cover the opponent's reply layer explicitly (the
    // preserving set must be knowable) but leave every our-turn node's
    // continuation a coverage gap.
    let mut oracle = TableOracle::new();
    let child_snap = play(&rules, &["d6"]);
    let child_key = oracle.key_of(&MillRules::decode_snapshot(child_snap), &opts);
    let reply_count = legal_count(&rules, &child_snap);
    {
        let mut actions = tgf_core::ActionList::<256>::new();
        rules.legal_actions(&child_snap, &mut actions);
        for &action in actions.as_slice() {
            let node = MillRules::decode_snapshot(rules.apply(&child_snap, action));
            let key = oracle.key_of(&node, &opts);
            oracle.own_value_by_key.insert(key, 0);
        }
    }

    let mut memo = DensityMemo::new();
    let mut risk_memo = RiskMemo::new();
    let mut stats = RecomputeStats::default();
    let risk = risk_memo.own_turn_risk(
        child_key,
        &child_snap,
        0,
        &rules,
        &opts,
        &mut oracle,
        &mut memo,
        &mut stats,
    );
    assert_eq!(risk.mean, None, "zero resolved samples");
    assert_eq!(risk.resolved_samples, 0);
    assert_eq!(risk.unresolved_samples as usize, reply_count);
    assert_eq!(stats.own_risk_unresolved_samples as usize, reply_count);
}

#[test]
#[should_panic(expected = "perspective-filter leak")]
fn own_turn_risk_rejects_same_side_candidates() {
    let rules = rules();
    let opts = options();
    let mut oracle = TableOracle::new();
    oracle.default_value = Some(0);

    // White d7 closes d5-d6-d7: the child keeps white (the parent side)
    // on turn.
    let parent_snap = play(&rules, &["d6", "b4", "d5", "b2"]);
    let mill_turn = parse_human_turn_notation(&rules, &parent_snap, "d7xb4").expect("mill move");
    let HumanTurn::BaseThenCapture { base, .. } = mill_turn else {
        panic!("d7 must form a mill");
    };
    let mill_child_snap = rules.apply(&parent_snap, base);
    let mill_child_key = oracle.key_of(&MillRules::decode_snapshot(mill_child_snap), &opts);

    let mut memo = DensityMemo::new();
    let mut risk_memo = RiskMemo::new();
    let mut stats = RecomputeStats::default();
    let _ = risk_memo.own_turn_risk(
        mill_child_key,
        &mill_child_snap,
        0,
        &rules,
        &opts,
        &mut oracle,
        &mut memo,
        &mut stats,
    );
}

/// Shared fixture for the derive-level gate wiring tests: the initial
/// position with two trappy children -- A (d6 class) with zero own-turn
/// risk, C (b6 class) with strictly positive own-turn risk (losers
/// planted one level deeper under one of its preserving reply nodes).
/// Returns (entry, child_a, child_c) with their canonical keys.
fn risky_and_safe_trappy_children(
    rules: &MillRules,
    opts: &MillVariantOptions,
    oracle: &mut TableOracle,
) -> (MineEntry, u64, u64) {
    let parent_snap = rules.initial_state(&[]);
    let parent_state = MillRules::decode_snapshot(parent_snap);
    let parent_key = oracle.key_of(&parent_state, opts);

    let child_a_snap = play(rules, &["d6"]);
    let child_a = oracle.key_of(&MillRules::decode_snapshot(child_a_snap), opts);
    let child_c_snap = play(rules, &["b6"]);
    let child_c = oracle.key_of(&MillRules::decode_snapshot(child_c_snap), opts);
    assert_ne!(child_a, child_c);

    plant_replies(rules, &child_a_snap, oracle, 3, 1);
    plant_replies(rules, &child_c_snap, oracle, 3, 1);

    // Make C risky: pick one of its PRESERVING replies (grandchild value
    // still 0) and plant losers under that node -- our side's blunders
    // once the turn comes back.
    let risky_node = {
        let mut actions = tgf_core::ActionList::<256>::new();
        rules.legal_actions(&child_c_snap, &mut actions);
        let action = actions
            .as_slice()
            .iter()
            .copied()
            .find(|&action| {
                let grandchild = MillRules::decode_snapshot(rules.apply(&child_c_snap, action));
                oracle
                    .own_value_by_key
                    .get(&oracle.keys.canonical_key(&grandchild, opts).unwrap())
                    != Some(&1)
            })
            .expect("a preserving reply exists");
        rules.apply(&child_c_snap, action)
    };
    plant_replies(rules, &risky_node, oracle, 4, 1);

    let entry = steering_entry(&rules.export_fen(&parent_state), parent_key, child_a);
    (entry, child_a, child_c)
}

/// Measured own-turn risk mean of one child, through fresh memos.
fn measured_risk(
    rules: &MillRules,
    opts: &MillVariantOptions,
    oracle: &mut TableOracle,
    child_snap: &tgf_core::GameStateSnapshot,
) -> Option<f64> {
    let child_key = oracle.key_of(&MillRules::decode_snapshot(*child_snap), opts);
    RiskMemo::new()
        .own_turn_risk(
            child_key,
            child_snap,
            0,
            rules,
            opts,
            oracle,
            &mut DensityMemo::new(),
            &mut RecomputeStats::default(),
        )
        .mean
}

#[test]
fn absolute_risk_gate_filters_risky_candidates_from_the_mask_only() {
    let rules = rules();
    let opts = options();
    let mut oracle = TableOracle::new();
    oracle.default_value = Some(0);
    let (entry, child_a, child_c) = risky_and_safe_trappy_children(&rules, &opts, &mut oracle);

    // Fixture preconditions (deterministic; no key collisions between the
    // planted layers may leak risk onto A).
    let risk_a = measured_risk(&rules, &opts, &mut oracle, &play(&rules, &["d6"]))
        .expect("A's continuations are covered");
    let risk_c = measured_risk(&rules, &opts, &mut oracle, &play(&rules, &["b6"]))
        .expect("C's continuations are covered");
    assert_eq!(risk_a, 0.0, "A must be risk-free by construction");
    assert!(risk_c > 0.0, "C must carry planted own-turn risk");

    // Gate off: both trappy children are in the mask.
    let parent_snap = rules.initial_state(&[]);
    let child_keys = child_keys_in_mask_order(&rules, &parent_snap, &mut oracle);
    let index_of = |key: u64| child_keys.iter().position(|&k| k == key).unwrap();
    let mut stats_off = RecomputeStats::default();
    let (proof_off, _) = derive_child_proof(
        &entry,
        &rules,
        &opts,
        &mut oracle,
        &HashMap::new(),
        None,
        RiskGateConfig::default(),
        &mut DensityMemo::new(),
        &mut RiskMemo::new(),
        &mut stats_off,
    );
    assert_eq!(
        proof_off.trap_score_mask.count_ones(),
        2,
        "exactly A and C are trappy in this fixture"
    );
    assert_eq!(
        stats_off.gate_seen_positive, 0,
        "inactive gate counts nothing"
    );
    let nibble_of = |proof: &ChildProof, key: u64| -> u8 {
        let rank = trap_rank(proof.trap_score_mask, index_of(key)).expect("masked");
        nibble_at(proof.optimal_trap_nibbles, rank)
    };
    let nibble_a_off = nibble_of(&proof_off, child_a);

    // Gate on (absolute, lambda 0): only zero-risk candidates survive; C
    // falls out of the mask, A's nibble VALUE is untouched.
    let gate = RiskGateConfig {
        mode: RiskGateMode::Absolute,
        lambda: 0.0,
        min_placing_ply_proxy: 0,
    };
    let mut stats_on = RecomputeStats::default();
    let (proof_on, _) = derive_child_proof(
        &entry,
        &rules,
        &opts,
        &mut oracle,
        &HashMap::new(),
        None,
        gate,
        &mut DensityMemo::new(),
        &mut RiskMemo::new(),
        &mut stats_on,
    );
    assert_ne!(proof_on.trap_score_mask & (1 << index_of(child_a)), 0);
    assert_eq!(proof_on.trap_score_mask & (1 << index_of(child_c)), 0);
    assert_eq!(nibble_of(&proof_on, child_a), nibble_a_off);
    assert_eq!(proof_on.optimal_mask, proof_off.optimal_mask);
    assert_eq!(stats_on.gate_seen_positive, 2);
    assert_eq!(stats_on.gate_passed_positive, 1);
    assert_eq!(stats_on.gate_filtered_positive, 1);
    assert_eq!(stats_on.gate_filtered_by_risk, 1);
    assert_eq!(stats_on.gate_filtered_by_ply_proxy, 0);
    assert_eq!(stats_on.gate_filtered_unresolved, 0);
}

#[test]
fn sibling_delta_gate_filters_uncovered_excess_risk() {
    let rules = rules();
    let opts = options();
    let mut oracle = TableOracle::new();
    oracle.default_value = Some(0);
    let (entry, child_a, child_c) = risky_and_safe_trappy_children(&rules, &opts, &mut oracle);

    let risk_c = measured_risk(&rules, &opts, &mut oracle, &play(&rules, &["b6"]))
        .expect("C's continuations are covered");
    let trap_c = {
        let child_c_snap = play(&rules, &["b6"]);
        let key = oracle.key_of(&MillRules::decode_snapshot(child_c_snap), &opts);
        DensityMemo::new()
            .density_and_best(key, &child_c_snap, &rules, &opts, &mut oracle)
            .expect("covered")
            .0
    };
    // Sibling minima are 0 here (zero-risk / zero-trap siblings exist),
    // so C's deltas are its absolute values. Pick lambda between the two
    // verdicts: strict lambda filters C, generous lambda keeps it.
    let strict = 0.5 * risk_c / trap_c;
    let generous = 2.0 * risk_c / trap_c;
    assert!(risk_c > strict * trap_c && risk_c <= generous * trap_c);

    let parent_snap = rules.initial_state(&[]);
    let child_keys = child_keys_in_mask_order(&rules, &parent_snap, &mut oracle);
    let index_of = |key: u64| child_keys.iter().position(|&k| k == key).unwrap();
    let mut run = |lambda: f64| -> (ChildProof, RecomputeStats) {
        let gate = RiskGateConfig {
            mode: RiskGateMode::SiblingDelta,
            lambda,
            min_placing_ply_proxy: 0,
        };
        let mut stats = RecomputeStats::default();
        let (proof, _) = derive_child_proof(
            &entry,
            &rules,
            &opts,
            &mut oracle,
            &HashMap::new(),
            None,
            gate,
            &mut DensityMemo::new(),
            &mut RiskMemo::new(),
            &mut stats,
        );
        (proof, stats)
    };

    let (proof_strict, stats_strict) = run(strict);
    assert_ne!(
        proof_strict.trap_score_mask & (1 << index_of(child_a)),
        0,
        "the risk-free sibling has zero excess risk and always passes"
    );
    assert_eq!(
        proof_strict.trap_score_mask & (1 << index_of(child_c)),
        0,
        "C's excess risk is not covered by lambda * its trap edge"
    );
    assert_eq!(stats_strict.gate_filtered_by_risk, 1);

    let (proof_generous, stats_generous) = run(generous);
    assert_ne!(proof_generous.trap_score_mask & (1 << index_of(child_c)), 0);
    assert_eq!(stats_generous.gate_filtered_positive, 0);
    assert_eq!(stats_generous.gate_passed_positive, 2);
}

#[test]
fn ply_proxy_floor_empties_the_mask_and_the_post_gate_gap_reports_it() {
    let rules = rules();
    let opts = options();
    let mut oracle = TableOracle::new();
    oracle.default_value = Some(0);
    let (entry, _, _) = risky_and_safe_trappy_children(&rules, &opts, &mut oracle);

    // The initial position has placing_ply_proxy 0: a floor of 5 filters
    // every positive candidate even with mode none (the floor alone
    // activates the gate).
    let gate = RiskGateConfig {
        mode: RiskGateMode::None,
        lambda: 1.0,
        min_placing_ply_proxy: 5,
    };
    assert!(gate.active());
    let mut stats = RecomputeStats::default();
    let (proof, diag) = derive_child_proof(
        &entry,
        &rules,
        &opts,
        &mut oracle,
        &HashMap::new(),
        None,
        gate,
        &mut DensityMemo::new(),
        &mut RiskMemo::new(),
        &mut stats,
    );
    assert_eq!(proof.trap_score_mask, 0);
    assert_eq!(stats.gate_seen_positive, 2);
    assert_eq!(stats.gate_filtered_by_ply_proxy, 2);
    assert_eq!(
        diag.nibble_gap, 0,
        "with an ACTIVE gate the gap is measured post-gate: an emptied \
         mask has nothing left to steer with, and the diagnostics must \
         say so instead of overstating the pre-gate gain shape"
    );
    assert!(diag.flipped_optimal >= 2, "structural count remains");
    assert!(
        drop_steering_for_empty_mask(gate.active(), entry.severity, proof.trap_score_mask),
        "a severity-0 record emptied by the active gate is then dropped"
    );
}

/// Offline net-gate replay over the frozen gate-matrix baseline: walk the
/// C-group (ungated make-traps) patchtrap trace, rebuild every traced
/// parent's candidate table from the ungated pack's stored gain nibbles
/// plus freshly computed own-turn risks, and simulate the runtime's
/// strictly-greater tie-break under net scores for a lambda sweep --
/// WITHOUT building a single pack or playing a single game.
///
/// Per traced switch and lambda this reports whether the switch would
/// have been suppressed (baseline kept), redirected (a different target
/// wins on net), or kept as-is, plus the own-risk of the v4-chosen child
/// against the net-chosen one. The recomputed gain nibbles are asserted
/// against the nibbles the engine logged at play time, so a drifted pack
/// or misaligned index space fails loudly instead of skewing estimates.
///
///   SANMILL_STRONG_DB=... SANMILL_TRACE_DIR=... SANMILL_UNGATED_PACK=...
///   SANMILL_NET_REPLAY_OUT=...
///   cargo test -p tgf-cli --release mill_pack::recompute::tests::net_gate_replay_over_trace -- --ignored --nocapture
#[test]
#[ignore = "requires the external strong DB, the archived baseline pack, and its captured trace"]
fn net_gate_replay_over_trace() {
    use perfect_db::database::{DatabaseVariant, FileDatabaseProvider};
    use perfect_db::wdl_plane::{MID_REMOVAL_KEY_TAG, WdlPlaneCache, unpack_canonical_key};

    let env_or = |name: &str, default: &str| std::env::var(name).unwrap_or_else(|_| default.into());
    let workspace = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let resolve = |raw: String| -> std::path::PathBuf {
        let candidate = std::path::PathBuf::from(&raw);
        if candidate.is_absolute() {
            candidate
        } else {
            workspace.join(&raw)
        }
    };
    const BASELINE: &str = "experiments/gate_matrix_20260705_v4_riskgate_baseline";
    let db_root = env_or("SANMILL_STRONG_DB", "D:/user/Documents/strong");
    let trace_dir = resolve(env_or(
        "SANMILL_TRACE_DIR",
        &format!("{BASELINE}/c_make/trace"),
    ));
    let pack_path = resolve(env_or(
        "SANMILL_UNGATED_PACK",
        &format!("{BASELINE}/packs/ungated.mill_patch"),
    ));
    let out_path = resolve(env_or(
        "SANMILL_NET_REPLAY_OUT",
        "target/net_replay/replay.jsonl",
    ));
    std::fs::create_dir_all(out_path.parent().expect("output path has a parent"))
        .expect("output directory must be creatable");

    let options = MillVariantOptions::default();
    let rules = MillRules::new(options.clone());
    let provider = FileDatabaseProvider::new(std::path::PathBuf::from(&db_root));
    let mut planes =
        WdlPlaneCache::new(provider, DatabaseVariant::STANDARD).expect("strong DB plane cache");
    let pack_bytes = std::fs::read(&pack_path).expect("baseline ungated pack readable");
    let pack = perfect_db::patch::PatchFile::read_from(&mut &pack_bytes[..])
        .expect("baseline pack parses");

    const LAMBDAS: [f64; 5] = [0.5, 0.75, 1.0, 1.5, 2.0];
    #[derive(Default)]
    struct Agg {
        suppressed: usize,
        kept_same: usize,
        redirected: usize,
        risk_pairs: usize,
        risk_v4_sum: f64,
        risk_net_sum: f64,
    }
    let mut aggregates: Vec<Agg> = (0..LAMBDAS.len()).map(|_| Agg::default()).collect();

    let mut memo = DensityMemo::new();
    let mut risk_memo = RiskMemo::new();
    let mut probe_stats = RecomputeStats::default();
    let mut out = std::io::BufWriter::new(
        std::fs::File::create(&out_path).expect("replay output must be creatable"),
    );
    let mut rows = 0_usize;
    let mut risk_unresolved_candidates = 0_usize;

    for entry in std::fs::read_dir(&trace_dir).expect("trace dir must exist") {
        let path = entry.expect("dir entry").path();
        if path.extension().and_then(|e| e.to_str()) != Some("jsonl") {
            continue;
        }
        for line in std::fs::read_to_string(&path)
            .expect("trace file readable")
            .lines()
            .filter(|l| !l.trim().is_empty())
        {
            let row: serde_json::Value = serde_json::from_str(line).expect("valid trace JSONL");
            let fen = row["parent_fen"].as_str().expect("parent_fen");
            let mut state = rules.set_from_fen(fen).expect("trace FEN parses");
            state.reset_ply_since_capture();
            let parent_side = state.side_to_move();
            let snap = rules.encode_state(state.clone());
            let parent_key = perfect_db::canonical_key(&mut planes, &state, &options)
                .expect("traced parents are keyable");
            assert_eq!(
                parent_key,
                row["parent_key"].as_u64().expect("parent_key"),
                "replay must rebuild the exact traced parent (fen {fen})"
            );
            let record = if parent_key & MID_REMOVAL_KEY_TAG != 0 {
                let r = pack
                    .lookup_mid_removal(parent_key)
                    .expect("traced parent must be in the pack");
                (
                    r.child_count,
                    r.optimal_mask,
                    r.trap_score_mask,
                    r.optimal_trap_nibbles,
                )
            } else {
                let (sector, slot) = unpack_canonical_key(parent_key);
                let r = pack
                    .lookup(
                        sector.white_on_board,
                        sector.black_on_board,
                        sector.white_in_hand,
                        sector.black_in_hand,
                        slot as u32,
                    )
                    .expect("traced parent must be in the pack");
                (
                    r.child_count,
                    r.optimal_mask,
                    r.trap_score_mask,
                    r.optimal_trap_nibbles,
                )
            };
            let (child_count, optimal_mask, trap_score_mask, optimal_trap_nibbles) = record;
            let child_keys =
                perfect_db::patch::sorted_distinct_child_keys(&mut planes, &rules, &options, &snap);
            assert_eq!(
                child_keys.len(),
                usize::from(child_count),
                "runtime child enumeration must match the pack record (fen {fen})"
            );

            // First concrete (snapshot, side-flipped) reaching each child key.
            let mut child_snap_by_key: HashMap<u64, (tgf_core::GameStateSnapshot, bool)> =
                HashMap::new();
            let mut legal = tgf_core::ActionList::<256>::new();
            rules.legal_actions(&snap, &mut legal);
            let mut key_of_action = |action: tgf_core::Action| -> Option<u64> {
                let child_snap = rules.apply(&snap, action);
                let child_state = MillRules::decode_snapshot(child_snap);
                let key = perfect_db::canonical_key(&mut planes, &child_state, &options)?;
                child_snap_by_key
                    .entry(key)
                    .or_insert((child_snap, child_state.side_to_move() != parent_side));
                Some(key)
            };
            let mut baseline_key = None;
            let mut steering_key = None;
            for &action in legal.as_slice() {
                let token = tgf_mill::MillUciCodec::encode_action(action);
                let key = key_of_action(action);
                if Some(token.as_str()) == row["baseline_action"].as_str() {
                    baseline_key = key;
                }
                if Some(token.as_str()) == row["steering_action"].as_str() {
                    steering_key = key;
                }
            }
            let baseline_key = baseline_key.expect("traced baseline action is legal and keyable");
            let steering_key = steering_key.expect("traced steering action is legal and keyable");

            let gain_of = |key: u64| -> u8 {
                let index = child_keys.binary_search(&key).expect("keyed child");
                perfect_db::patch::trap_rank(trap_score_mask, index)
                    .map(|rank| perfect_db::patch::nibble_at(optimal_trap_nibbles, rank))
                    .unwrap_or(0)
            };
            // Cross-check the rebuilt gains against what the engine
            // logged when the switch actually happened.
            assert_eq!(
                u64::from(gain_of(baseline_key)),
                row["baseline_nibble"].as_u64().expect("baseline_nibble"),
                "rebuilt baseline gain diverged from the live trace (fen {fen})"
            );
            assert_eq!(
                u64::from(gain_of(steering_key)),
                row["steering_nibble"].as_u64().expect("steering_nibble"),
                "rebuilt steering gain diverged from the live trace (fen {fen})"
            );

            // Candidate table: flipped optimal children with positive
            // gain, each with its resolved own-turn risk (unresolved ->
            // excluded from every net mask, counted).
            struct Candidate {
                key: u64,
                gain: u8,
                risk: Option<f64>,
            }
            let mut candidates: Vec<Candidate> = Vec::new();
            for (index, &child_key) in child_keys.iter().enumerate() {
                if optimal_mask & (1_u64 << index) == 0 {
                    continue;
                }
                let (child_snap, flipped) = child_snap_by_key
                    .get(&child_key)
                    .copied()
                    .expect("every keyed child has a snapshot");
                if !flipped {
                    continue;
                }
                let gain = gain_of(child_key);
                if gain == 0 && child_key != baseline_key {
                    continue;
                }
                let mut oracle = PlaneOracle {
                    planes: &mut planes,
                };
                let risk = risk_memo
                    .own_turn_risk(
                        child_key,
                        &child_snap,
                        parent_side,
                        &rules,
                        &options,
                        &mut oracle,
                        &mut memo,
                        &mut probe_stats,
                    )
                    .mean;
                if risk.is_none() {
                    risk_unresolved_candidates += 1;
                }
                candidates.push(Candidate {
                    key: child_key,
                    gain,
                    risk,
                });
            }
            let risk_of = |key: u64| -> Option<f64> {
                candidates
                    .iter()
                    .find(|c| c.key == key)
                    .and_then(|c| c.risk)
            };

            let mut per_lambda = Vec::with_capacity(LAMBDAS.len());
            for (slot, &lambda) in LAMBDAS.iter().enumerate() {
                let net_of = |c: &Candidate| -> u8 {
                    match c.risk {
                        Some(risk) => net_nibble(c.gain, risk, lambda),
                        None => 0, // packer filters unresolved candidates
                    }
                };
                let net_baseline = candidates
                    .iter()
                    .find(|c| c.key == baseline_key)
                    .map(net_of)
                    .unwrap_or(0);
                // Runtime rule: ascending-key scan, strictly greater than
                // the baseline's stored score, first max kept.
                let mut best: Option<(u8, u64)> = None;
                for candidate in &candidates {
                    if candidate.key == baseline_key {
                        continue;
                    }
                    let net = net_of(candidate);
                    if net > net_baseline && best.is_none_or(|(score, _)| net > score) {
                        best = Some((net, candidate.key));
                    }
                }
                let agg = &mut aggregates[slot];
                let verdict = match best {
                    None => {
                        agg.suppressed += 1;
                        "suppressed"
                    }
                    Some((_, target)) if target == steering_key => {
                        agg.kept_same += 1;
                        "kept_same"
                    }
                    Some(_) => {
                        agg.redirected += 1;
                        "redirected"
                    }
                };
                // Risk of what v4 actually played vs what net would play
                // (baseline when suppressed).
                let net_target = best.map(|(_, target)| target).unwrap_or(baseline_key);
                if let (Some(risk_v4), Some(risk_net)) =
                    (risk_of(steering_key), risk_of(net_target))
                {
                    agg.risk_pairs += 1;
                    agg.risk_v4_sum += risk_v4;
                    agg.risk_net_sum += risk_net;
                }
                per_lambda.push(serde_json::json!({
                    "lambda": lambda,
                    "verdict": verdict,
                    "net_baseline": net_baseline,
                    "net_target": best.map(|(net, _)| net),
                }));
            }

            use std::io::Write;
            writeln!(
                out,
                "{}",
                serde_json::json!({
                    "trace_tag": row["trace_tag"],
                    "ply": row["ply"],
                    "parent_key": parent_key,
                    "baseline_gain": gain_of(baseline_key),
                    "steering_gain": gain_of(steering_key),
                    "baseline_risk": risk_of(baseline_key),
                    "steering_risk": risk_of(steering_key),
                    "candidates": candidates.len(),
                    "per_lambda": per_lambda,
                })
            )
            .expect("replay row write");
            rows += 1;
        }
    }
    use std::io::Write;
    out.flush().expect("flush replay output");

    assert!(rows > 0, "the replay needs trace rows to analyze");
    eprintln!(
        "[net-replay] rows={rows} risk_unresolved_candidates={risk_unresolved_candidates} \
         (risk memo: {} unique, {} hits) -> {}",
        risk_memo.misses,
        risk_memo.hits,
        out_path.display()
    );
    for (slot, &lambda) in LAMBDAS.iter().enumerate() {
        let agg = &aggregates[slot];
        eprintln!(
            "[net-replay] lambda={lambda}: suppressed={} ({:.1}%) kept_same={} redirected={} | \
             mean own-risk of played child: v4={:.4} net={:.4} (over {} rows)",
            agg.suppressed,
            100.0 * agg.suppressed as f64 / rows as f64,
            agg.kept_same,
            agg.redirected,
            agg.risk_v4_sum / agg.risk_pairs.max(1) as f64,
            agg.risk_net_sum / agg.risk_pairs.max(1) as f64,
            agg.risk_pairs,
        );
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum HumanReplayCoverageBucket {
    Both,
    BaselineOnly,
    SteeringOnly,
    Neither,
    BaselineSameSide,
}

impl HumanReplayCoverageBucket {
    fn as_str(self) -> &'static str {
        match self {
            HumanReplayCoverageBucket::Both => "both",
            HumanReplayCoverageBucket::BaselineOnly => "baseline_only",
            HumanReplayCoverageBucket::SteeringOnly => "steering_only",
            HumanReplayCoverageBucket::Neither => "neither",
            HumanReplayCoverageBucket::BaselineSameSide => "baseline_same_side",
        }
    }
}

fn human_replay_bucket(
    baseline_same_side: bool,
    baseline_covered: bool,
    steering_covered: bool,
) -> HumanReplayCoverageBucket {
    if baseline_same_side {
        return HumanReplayCoverageBucket::BaselineSameSide;
    }
    match (baseline_covered, steering_covered) {
        (true, true) => HumanReplayCoverageBucket::Both,
        (true, false) => HumanReplayCoverageBucket::BaselineOnly,
        (false, true) => HumanReplayCoverageBucket::SteeringOnly,
        (false, false) => HumanReplayCoverageBucket::Neither,
    }
}

#[test]
fn human_replay_bucket_partitions_rows() {
    assert_eq!(
        human_replay_bucket(false, true, true),
        HumanReplayCoverageBucket::Both
    );
    assert_eq!(
        human_replay_bucket(false, true, false),
        HumanReplayCoverageBucket::BaselineOnly
    );
    assert_eq!(
        human_replay_bucket(false, false, true),
        HumanReplayCoverageBucket::SteeringOnly
    );
    assert_eq!(
        human_replay_bucket(false, false, false),
        HumanReplayCoverageBucket::Neither
    );
    assert_eq!(
        human_replay_bucket(true, true, true),
        HumanReplayCoverageBucket::BaselineSameSide
    );
}

#[derive(Default)]
struct HumanReplayBucketCounts {
    both: usize,
    baseline_only: usize,
    steering_only: usize,
    neither: usize,
    baseline_same_side: usize,
}

impl HumanReplayBucketCounts {
    fn add(&mut self, bucket: HumanReplayCoverageBucket) {
        match bucket {
            HumanReplayCoverageBucket::Both => self.both += 1,
            HumanReplayCoverageBucket::BaselineOnly => self.baseline_only += 1,
            HumanReplayCoverageBucket::SteeringOnly => self.steering_only += 1,
            HumanReplayCoverageBucket::Neither => self.neither += 1,
            HumanReplayCoverageBucket::BaselineSameSide => self.baseline_same_side += 1,
        }
    }

    fn total(&self) -> usize {
        self.both + self.baseline_only + self.steering_only + self.neither + self.baseline_same_side
    }
}

fn mean(values: &[f64]) -> f64 {
    assert!(!values.is_empty(), "mean requires at least one value");
    values.iter().sum::<f64>() / values.len() as f64
}

fn mean_or_nan(sum: f64, count: usize) -> f64 {
    if count == 0 {
        f64::NAN
    } else {
        sum / count as f64
    }
}

fn percentile(sorted_values: &[f64], percentile: f64) -> f64 {
    assert!(!sorted_values.is_empty(), "percentile requires values");
    assert!(
        (0.0..=1.0).contains(&percentile),
        "percentile must be in [0, 1]"
    );
    let index = ((sorted_values.len() - 1) as f64 * percentile).round() as usize;
    sorted_values[index]
}

struct HumanReplayRng {
    state: u64,
}

impl HumanReplayRng {
    fn new(seed: u64) -> Self {
        assert!(seed != 0, "xorshift state must be non-zero");
        Self { state: seed }
    }

    fn next_u64(&mut self) -> u64 {
        let mut x = self.state;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.state = x;
        x
    }

    fn index(&mut self, len: usize) -> usize {
        assert!(len > 0, "sample population must be non-empty");
        (self.next_u64() as usize) % len
    }
}

fn cluster_bootstrap_ci(
    cluster_values: &HashMap<String, Vec<f64>>,
    iterations: usize,
    seed: u64,
) -> Option<(f64, f64)> {
    if cluster_values.is_empty() {
        return None;
    }
    assert!(iterations > 0, "bootstrap iterations must be positive");
    let mut clusters: Vec<(&String, &Vec<f64>)> = cluster_values.iter().collect();
    clusters.sort_by_key(|(tag, _)| *tag);
    assert!(
        clusters.iter().all(|(_, values)| !values.is_empty()),
        "covered clusters must carry at least one row"
    );

    let mut rng = HumanReplayRng::new(seed);
    let mut sampled_means = Vec::with_capacity(iterations);
    for _ in 0..iterations {
        let mut sum = 0.0;
        let mut count = 0_usize;
        for _ in 0..clusters.len() {
            let (_, values) = clusters[rng.index(clusters.len())];
            sum += values.iter().sum::<f64>();
            count += values.len();
        }
        sampled_means.push(sum / count as f64);
    }
    sampled_means.sort_by(|a, b| a.total_cmp(b));
    Some((
        percentile(&sampled_means, 0.025),
        percentile(&sampled_means, 0.975),
    ))
}

#[test]
fn human_replay_cluster_bootstrap_is_deterministic() {
    let clusters = HashMap::from([
        ("b".to_string(), vec![0.2, 0.4]),
        ("a".to_string(), vec![0.0]),
        ("c".to_string(), vec![1.0]),
    ]);
    let first = cluster_bootstrap_ci(&clusters, 200, 0x5eed_2026).expect("CI exists");
    let second = cluster_bootstrap_ci(&clusters, 200, 0x5eed_2026).expect("CI exists");
    assert_eq!(first, second);
    assert!(first.0 <= mean(&[0.0, 0.2, 0.4, 1.0]));
    assert!(first.1 >= mean(&[0.0, 0.2, 0.4, 1.0]));
    assert!(cluster_bootstrap_ci(&HashMap::new(), 10, 1).is_none());
}

const HUMAN_REPLAY_LAMBDAS: [f64; 5] = [0.5, 0.75, 1.0, 1.5, 2.0];

#[derive(Default)]
struct HumanReplayPolicyAgg {
    suppressed: usize,
    kept_same: usize,
    redirected: usize,
    covered_rows: usize,
    ev_sum: f64,
    unified_rows: usize,
    unified_ev_sum: f64,
}

impl HumanReplayPolicyAgg {
    fn add_verdict(&mut self, verdict: &str) {
        match verdict {
            "suppressed" => self.suppressed += 1,
            "kept_same" => self.kept_same += 1,
            "redirected" => self.redirected += 1,
            other => panic!("unexpected replay verdict {other}"),
        }
    }

    fn add_policy_ev(&mut self, ev: Option<f64>) {
        if let Some(value) = ev {
            self.covered_rows += 1;
            self.ev_sum += value;
        }
    }

    fn add_unified_ev(&mut self, ev: f64) {
        self.unified_rows += 1;
        self.unified_ev_sum += ev;
    }
}

#[derive(Clone, Debug)]
struct HumanDenseChild {
    key: u64,
    action: String,
    ev: f64,
    n_scored: u64,
    coverage: f64,
}

#[derive(Clone, Debug)]
struct HumanDenseSelection {
    baseline: HumanDenseChild,
    steering: HumanDenseChild,
    delta_ev: f64,
}

fn select_human_dense_candidate(
    baseline_key: u64,
    children: &[HumanDenseChild],
) -> Option<HumanDenseSelection> {
    if children.len() < 2 {
        return None;
    }
    let baseline = children
        .iter()
        .find(|child| child.key == baseline_key)
        .cloned()
        .unwrap_or_else(|| children[0].clone());
    let steering = children
        .iter()
        .filter(|child| child.key != baseline.key)
        .max_by(|left, right| {
            left.ev
                .total_cmp(&right.ev)
                .then_with(|| right.key.cmp(&left.key))
        })?
        .clone();
    let delta_ev = steering.ev - baseline.ev;
    Some(HumanDenseSelection {
        baseline,
        steering,
        delta_ev,
    })
}

#[test]
fn human_dense_selection_uses_ranked_baseline_and_best_alternative() {
    let children = vec![
        HumanDenseChild {
            key: 10,
            action: "a".into(),
            ev: -0.4,
            n_scored: 20,
            coverage: 1.0,
        },
        HumanDenseChild {
            key: 20,
            action: "b".into(),
            ev: 0.2,
            n_scored: 20,
            coverage: 1.0,
        },
        HumanDenseChild {
            key: 30,
            action: "c".into(),
            ev: 0.1,
            n_scored: 20,
            coverage: 1.0,
        },
    ];
    let selected = select_human_dense_candidate(10, &children).expect("two covered children");
    assert_eq!(selected.baseline.key, 10);
    assert_eq!(selected.steering.key, 20);
    assert!((selected.delta_ev - 0.6).abs() < 1e-12);

    let selected = select_human_dense_candidate(20, &children).expect("two covered children");
    assert_eq!(selected.baseline.key, 20);
    assert_eq!(selected.steering.key, 30);
    assert!((selected.delta_ev + 0.1).abs() < 1e-12);
}

/// In-sample HumanDB replay over the frozen C-group make-traps trace. This
/// is intentionally offline and ignored: it does not build a pack or play
/// games. It measures whether the v4 steering decisions that actually
/// fired in H2H move into child positions where HumanDB's one-turn reply
/// distribution is better for the mover than the baseline child.
///
/// This is an investment/diagnostic signal only. It reuses the same
/// HumanDB that trained behavior nibbles, so it cannot be treated as
/// held-out product evidence.
///
///   SANMILL_STRONG_DB=... SANMILL_HUMAN_DB=... SANMILL_TRACE_DIR=...
///   SANMILL_UNGATED_PACK=... SANMILL_HUMAN_REPLAY_OUT=...
///   cargo test -p tgf-cli --release mill_pack::recompute::tests::human_replay_v1_over_trace -- --ignored --nocapture
#[test]
#[ignore = "requires the external strong DB, HumanDB, archived baseline pack, and trace"]
fn human_replay_v1_over_trace() {
    use perfect_db::database::{DatabaseVariant, FileDatabaseProvider};
    use perfect_db::wdl_plane::{MID_REMOVAL_KEY_TAG, WdlPlaneCache, unpack_canonical_key};

    let env_or = |name: &str, default: &str| std::env::var(name).unwrap_or_else(|_| default.into());
    let workspace = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let resolve = |raw: String| -> std::path::PathBuf {
        let candidate = std::path::PathBuf::from(&raw);
        if candidate.is_absolute() {
            candidate
        } else {
            workspace.join(&raw)
        }
    };

    const BASELINE: &str = "experiments/gate_matrix_20260705_v4_riskgate_baseline";
    let db_root = env_or("SANMILL_STRONG_DB", "D:/user/Documents/strong");
    let human_db = resolve(env_or(
        "SANMILL_HUMAN_DB",
        "D:/Repo/NMM_LLM/human_database/human_db.sqlite",
    ));
    let trace_dir = resolve(env_or(
        "SANMILL_TRACE_DIR",
        &format!("{BASELINE}/c_make/trace"),
    ));
    let pack_path = resolve(env_or(
        "SANMILL_UNGATED_PACK",
        &format!("{BASELINE}/packs/ungated.mill_patch"),
    ));
    let out_path = resolve(env_or(
        "SANMILL_HUMAN_REPLAY_OUT",
        "target/human_replay_v1/replay.jsonl",
    ));
    std::fs::create_dir_all(out_path.parent().expect("output path has a parent"))
        .expect("output directory must be creatable");

    let options = MillVariantOptions::default();
    let rules = MillRules::new(options.clone());
    let provider = FileDatabaseProvider::new(std::path::PathBuf::from(&db_root));
    let mut planes =
        WdlPlaneCache::new(provider, DatabaseVariant::STANDARD).expect("strong DB plane cache");
    let human = {
        let mut oracle = PlaneOracle {
            planes: &mut planes,
        };
        load_human_weights(
            &human_db,
            &rules,
            &options,
            &mut oracle,
            HumanWeightConfig::default(),
        )
        .expect("HumanDB weights load")
    };
    let pack_bytes = std::fs::read(&pack_path).expect("baseline ungated pack readable");
    let pack = perfect_db::patch::PatchFile::read_from(&mut &pack_bytes[..])
        .expect("baseline pack parses");

    let mut trace_files: Vec<_> = std::fs::read_dir(&trace_dir)
        .expect("trace dir must exist")
        .map(|entry| entry.expect("dir entry").path())
        .filter(|path| path.extension().and_then(|e| e.to_str()) == Some("jsonl"))
        .collect();
    trace_files.sort();

    let mut out = std::io::BufWriter::new(
        std::fs::File::create(&out_path).expect("human replay output must be creatable"),
    );
    let mut rows = 0_usize;
    let mut buckets = HumanReplayBucketCounts::default();
    let mut covered_delta_values: Vec<f64> = Vec::new();
    let mut covered_delta_by_trace_tag: HashMap<String, Vec<f64>> = HashMap::new();
    let mut nibble_delta_bins: BTreeMap<i64, (usize, f64)> = BTreeMap::new();
    let mut policy_aggs: Vec<HumanReplayPolicyAgg> = HUMAN_REPLAY_LAMBDAS
        .iter()
        .map(|_| HumanReplayPolicyAgg::default())
        .collect();
    let mut unified_policy_rows = 0_usize;
    let mut unified_baseline_ev_sum = 0.0_f64;
    let mut unified_v4_ev_sum = 0.0_f64;
    let mut memo = DensityMemo::new();
    let mut risk_memo = RiskMemo::new();
    let mut replay_stats = RecomputeStats::default();
    let mut risk_unresolved_candidates = 0_usize;

    for path in trace_files {
        for line in std::fs::read_to_string(&path)
            .expect("trace file readable")
            .lines()
            .filter(|l| !l.trim().is_empty())
        {
            let row: serde_json::Value = serde_json::from_str(line).expect("valid trace JSONL");
            let fen = row["parent_fen"].as_str().expect("parent_fen");
            let mut state = rules.set_from_fen(fen).expect("trace FEN parses");
            state.reset_ply_since_capture();
            let parent_side = state.side_to_move();
            if let Some(side) = row.get("side_to_move").and_then(|v| v.as_i64()) {
                assert_eq!(
                    i64::from(parent_side),
                    side,
                    "trace side_to_move must match replay state (fen {fen})"
                );
            }
            let snap = rules.encode_state(state.clone());
            let parent_key = perfect_db::canonical_key(&mut planes, &state, &options)
                .expect("traced parents are keyable");
            assert_eq!(
                parent_key,
                row["parent_key"].as_u64().expect("parent_key"),
                "replay must rebuild the exact traced parent (fen {fen})"
            );

            let record = if parent_key & MID_REMOVAL_KEY_TAG != 0 {
                let r = pack
                    .lookup_mid_removal(parent_key)
                    .expect("traced parent must be in the pack");
                (
                    r.child_count,
                    r.optimal_mask,
                    r.trap_score_mask,
                    r.optimal_trap_nibbles,
                )
            } else {
                let (sector, slot) = unpack_canonical_key(parent_key);
                let r = pack
                    .lookup(
                        sector.white_on_board,
                        sector.black_on_board,
                        sector.white_in_hand,
                        sector.black_in_hand,
                        slot as u32,
                    )
                    .expect("traced parent must be in the pack");
                (
                    r.child_count,
                    r.optimal_mask,
                    r.trap_score_mask,
                    r.optimal_trap_nibbles,
                )
            };
            let (child_count, optimal_mask, trap_score_mask, optimal_trap_nibbles) = record;
            let child_keys =
                perfect_db::patch::sorted_distinct_child_keys(&mut planes, &rules, &options, &snap);
            assert_eq!(
                child_keys.len(),
                usize::from(child_count),
                "runtime child enumeration must match the pack record (fen {fen})"
            );

            let mut legal = tgf_core::ActionList::<256>::new();
            rules.legal_actions(&snap, &mut legal);
            let mut baseline_key = None;
            let mut steering_key = None;
            let mut baseline_flipped = None;
            let mut steering_flipped = None;
            let mut child_snap_by_key: HashMap<u64, (tgf_core::GameStateSnapshot, bool)> =
                HashMap::new();
            for &action in legal.as_slice() {
                let token = tgf_mill::MillUciCodec::encode_action(action);
                let child_snap = rules.apply(&snap, action);
                let child_state = MillRules::decode_snapshot(child_snap);
                let key = perfect_db::canonical_key(&mut planes, &child_state, &options)
                    .expect("traced child actions are keyable");
                let flipped = child_state.side_to_move() != parent_side;
                child_snap_by_key
                    .entry(key)
                    .or_insert((child_snap, flipped));
                if Some(token.as_str()) == row["baseline_action"].as_str() {
                    baseline_key = Some(key);
                    baseline_flipped = Some(flipped);
                }
                if Some(token.as_str()) == row["steering_action"].as_str() {
                    steering_key = Some(key);
                    steering_flipped = Some(flipped);
                }
            }
            let baseline_key = baseline_key.expect("traced baseline action is legal");
            let steering_key = steering_key.expect("traced steering action is legal");
            let baseline_same_side = !baseline_flipped.expect("baseline child side known");
            assert!(
                steering_flipped.expect("steering child side known"),
                "same-side steering child indicates a perspective-filter leak (fen {fen})"
            );

            let gain_of = |key: u64| -> u8 {
                let index = child_keys.binary_search(&key).expect("keyed child");
                perfect_db::patch::trap_rank(trap_score_mask, index)
                    .map(|rank| perfect_db::patch::nibble_at(optimal_trap_nibbles, rank))
                    .unwrap_or(0)
            };
            assert_eq!(
                u64::from(gain_of(baseline_key)),
                row["baseline_nibble"].as_u64().expect("baseline_nibble"),
                "rebuilt baseline gain diverged from the live trace (fen {fen})"
            );
            assert_eq!(
                u64::from(gain_of(steering_key)),
                row["steering_nibble"].as_u64().expect("steering_nibble"),
                "rebuilt steering gain diverged from the live trace (fen {fen})"
            );

            struct Candidate {
                key: u64,
                gain: u8,
                risk: Option<f64>,
            }
            let mut candidates: Vec<Candidate> = Vec::new();
            for (index, &child_key) in child_keys.iter().enumerate() {
                if optimal_mask & (1_u64 << index) == 0 {
                    continue;
                }
                let (child_snap, flipped) = child_snap_by_key
                    .get(&child_key)
                    .copied()
                    .expect("every keyed child has a snapshot");
                if !flipped {
                    continue;
                }
                let gain = gain_of(child_key);
                if gain == 0 && child_key != baseline_key {
                    continue;
                }
                let mut oracle = PlaneOracle {
                    planes: &mut planes,
                };
                let risk = risk_memo
                    .own_turn_risk(
                        child_key,
                        &child_snap,
                        parent_side,
                        &rules,
                        &options,
                        &mut oracle,
                        &mut memo,
                        &mut replay_stats,
                    )
                    .mean;
                if risk.is_none() {
                    risk_unresolved_candidates += 1;
                }
                candidates.push(Candidate {
                    key: child_key,
                    gain,
                    risk,
                });
            }

            let baseline_stats = human.sample_stats(baseline_key);
            let steering_stats = human.sample_stats(steering_key);
            let baseline_raw_ev = if baseline_same_side {
                None
            } else {
                let mut oracle = PlaneOracle {
                    planes: &mut planes,
                };
                human.raw_ev(baseline_key, &mut oracle)
            };
            let steering_raw_ev = {
                let mut oracle = PlaneOracle {
                    planes: &mut planes,
                };
                human.raw_ev(steering_key, &mut oracle)
            };
            // Raw EV is returned in child side-to-move perspective. Since
            // side-flipped children give the move to the opponent, negate it
            // once to report the traced mover's perspective.
            let baseline_ev = baseline_raw_ev.map(|ev| -ev.value);
            let steering_ev = steering_raw_ev.map(|ev| -ev.value);
            let bucket = human_replay_bucket(
                baseline_same_side,
                baseline_ev.is_some(),
                steering_ev.is_some(),
            );
            buckets.add(bucket);

            let delta_ev = match (baseline_ev, steering_ev) {
                (Some(b), Some(s)) => {
                    let delta = s - b;
                    covered_delta_values.push(delta);
                    let trace_tag = row["trace_tag"].as_str().unwrap_or("untagged").to_owned();
                    covered_delta_by_trace_tag
                        .entry(trace_tag)
                        .or_default()
                        .push(delta);
                    let nibble_delta =
                        i64::from(gain_of(steering_key)) - i64::from(gain_of(baseline_key));
                    let bin = nibble_delta_bins.entry(nibble_delta).or_default();
                    bin.0 += 1;
                    bin.1 += delta;
                    Some(delta)
                }
                _ => None,
            };

            let mut per_lambda = Vec::with_capacity(HUMAN_REPLAY_LAMBDAS.len());
            let mut row_policy_evs = Vec::with_capacity(HUMAN_REPLAY_LAMBDAS.len());
            for (slot, &lambda) in HUMAN_REPLAY_LAMBDAS.iter().enumerate() {
                let net_of = |candidate: &Candidate| -> u8 {
                    match candidate.risk {
                        Some(risk) => net_nibble(candidate.gain, risk, lambda),
                        None => 0,
                    }
                };
                let net_baseline = candidates
                    .iter()
                    .find(|candidate| candidate.key == baseline_key)
                    .map(net_of)
                    .unwrap_or(0);
                let mut best: Option<(u8, u64)> = None;
                for candidate in &candidates {
                    if candidate.key == baseline_key {
                        continue;
                    }
                    let net = net_of(candidate);
                    if net > net_baseline && best.is_none_or(|(score, _)| net > score) {
                        best = Some((net, candidate.key));
                    }
                }
                let policy_child_key = best.map(|(_, key)| key).unwrap_or(baseline_key);
                let verdict = match best {
                    None => "suppressed",
                    Some((_, key)) if key == steering_key => "kept_same",
                    Some(_) => "redirected",
                };
                policy_aggs[slot].add_verdict(verdict);
                let policy_ev = if policy_child_key == baseline_key {
                    baseline_ev
                } else if policy_child_key == steering_key {
                    steering_ev
                } else {
                    let mut oracle = PlaneOracle {
                        planes: &mut planes,
                    };
                    human
                        .raw_ev(policy_child_key, &mut oracle)
                        .map(|ev| -ev.value)
                };
                if baseline_ev.is_some() && steering_ev.is_some() {
                    policy_aggs[slot].add_policy_ev(policy_ev);
                }
                row_policy_evs.push(policy_ev);
                per_lambda.push(serde_json::json!({
                    "lambda": lambda,
                    "verdict": verdict,
                    "policy_child_key": policy_child_key,
                    "policy_ev": policy_ev,
                }));
            }
            if let (Some(baseline), Some(steering)) = (baseline_ev, steering_ev)
                && row_policy_evs.iter().all(Option::is_some)
            {
                unified_policy_rows += 1;
                unified_baseline_ev_sum += baseline;
                unified_v4_ev_sum += steering;
                for (slot, ev) in row_policy_evs.iter().enumerate() {
                    policy_aggs[slot].add_unified_ev(ev.expect("checked all policy EVs"));
                }
            }

            let stats_tuple = |stats: Option<HumanSampleStats>| {
                stats.map(|s| (s.n_scored, s.coverage)).unwrap_or((0, 0.0))
            };
            let (baseline_n_scored, baseline_coverage) = stats_tuple(baseline_stats);
            let (steering_n_scored, steering_coverage) = stats_tuple(steering_stats);

            use std::io::Write;
            writeln!(
                out,
                "{}",
                serde_json::json!({
                    "trace_tag": row["trace_tag"],
                    "ply": row["ply"],
                    "parent_key": parent_key,
                    "baseline_action": row["baseline_action"],
                    "steering_action": row["steering_action"],
                    "baseline_nibble": gain_of(baseline_key),
                    "steering_nibble": gain_of(steering_key),
                    "baseline_ev": baseline_ev,
                    "steering_ev": steering_ev,
                    "baseline_n_scored": baseline_n_scored,
                    "steering_n_scored": steering_n_scored,
                    "baseline_coverage": baseline_coverage,
                    "steering_coverage": steering_coverage,
                    "delta_ev": delta_ev,
                    "coverage_bucket": bucket.as_str(),
                    "per_lambda": per_lambda,
                })
            )
            .expect("human replay row write");
            rows += 1;
        }
    }
    use std::io::Write;
    out.flush().expect("flush human replay output");
    assert!(rows > 0, "the replay needs trace rows to analyze");
    assert_eq!(
        buckets.total(),
        rows,
        "coverage buckets must partition rows"
    );
    let covered_mean = if covered_delta_values.is_empty() {
        f64::NAN
    } else {
        mean(&covered_delta_values)
    };
    let covered_ci = cluster_bootstrap_ci(&covered_delta_by_trace_tag, 1000, 0x5eed_2026);
    let (ci_low, ci_high) = covered_ci.unwrap_or((f64::NAN, f64::NAN));
    let covered_cluster_count = covered_delta_by_trace_tag.len();
    eprintln!(
        "[human-replay] rows={rows} both={} baseline_only={} steering_only={} neither={} \
         baseline_same_side={} covered_mean_delta_ev={covered_mean:.6} \
         bootstrap95=[{ci_low:.6},{ci_high:.6}] covered_clusters={} risk_unresolved={} \
         risk_cache_hits={} risk_cache_misses={} -> {}",
        buckets.both,
        buckets.baseline_only,
        buckets.steering_only,
        buckets.neither,
        buckets.baseline_same_side,
        covered_cluster_count,
        risk_unresolved_candidates,
        risk_memo.hits,
        risk_memo.misses,
        out_path.display()
    );
    for (&nibble_delta, &(count, sum)) in &nibble_delta_bins {
        eprintln!(
            "[human-replay] nibble_delta={nibble_delta} rows={count} mean_delta_ev={:.6}",
            mean_or_nan(sum, count)
        );
    }
    eprintln!(
        "[human-replay] policy unified_rows={} avoid_only_ev={:.6} v4_make_ev={:.6}",
        unified_policy_rows,
        mean_or_nan(unified_baseline_ev_sum, unified_policy_rows),
        mean_or_nan(unified_v4_ev_sum, unified_policy_rows)
    );
    for ((slot, &lambda), agg) in HUMAN_REPLAY_LAMBDAS.iter().enumerate().zip(&policy_aggs) {
        eprintln!(
            "[human-replay] policy lambda={lambda:.2} suppressed={} kept_same={} \
             redirected={} covered_rows={} mean_ev={:.6} unified_rows={} unified_ev={:.6}",
            agg.suppressed,
            agg.kept_same,
            agg.redirected,
            agg.covered_rows,
            mean_or_nan(agg.ev_sum, agg.covered_rows),
            agg.unified_rows,
            mean_or_nan(agg.unified_ev_sum, agg.unified_rows)
        );
        assert_eq!(
            agg.unified_rows, unified_policy_rows,
            "policy {slot} must use the shared unified row set"
        );
    }
}

/// Human-dense trap census v2: invert the earlier trace-driven question.
/// Instead of asking whether engine-selected trap fires have HumanDB
/// support, scan HumanDB-covered parent positions and ask whether any
/// optimal side-flipping child is better than the ranked baseline under
/// raw one-turn HumanDB EV. This is an existence test only: it does not
/// build a trap library, play games, or change runtime behavior.
///
///   SANMILL_STRONG_DB=... SANMILL_HUMAN_DB=...
///   SANMILL_HUMAN_DENSE_OUT=...
///   cargo test -p tgf-cli --release mill_pack::recompute::tests::trap_human_dense_v2_census -- --ignored --nocapture
#[test]
#[ignore = "requires the external strong DB and HumanDB"]
fn trap_human_dense_v2_census() {
    use perfect_db::database::{Database, DatabaseOptions, DatabaseVariant, FileDatabaseProvider};
    use perfect_db::wdl_plane::WdlPlaneCache;

    let env_or = |name: &str, default: &str| std::env::var(name).unwrap_or_else(|_| default.into());
    let parse_env_usize = |name: &str, default: usize| -> usize {
        match std::env::var(name) {
            Ok(value) => value
                .parse::<usize>()
                .unwrap_or_else(|err| panic!("{name} must be a non-negative integer: {err}")),
            Err(_) => default,
        }
    };
    let workspace = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let resolve = |raw: String| -> std::path::PathBuf {
        let candidate = std::path::PathBuf::from(&raw);
        if candidate.is_absolute() {
            candidate
        } else {
            workspace.join(&raw)
        }
    };

    let db_root = env_or("SANMILL_STRONG_DB", "D:/user/Documents/strong");
    let human_db = resolve(env_or(
        "SANMILL_HUMAN_DB",
        "D:/Repo/NMM_LLM/human_database/human_db.sqlite",
    ));
    let out_path = resolve(env_or(
        "SANMILL_HUMAN_DENSE_OUT",
        "target/trap_human_dense_v2/census.jsonl",
    ));
    let min_parent_raw = parse_env_usize("SANMILL_HUMAN_DENSE_MIN_PARENT_RAW", 20) as u64;
    let max_parents = parse_env_usize("SANMILL_HUMAN_DENSE_MAX_PARENTS", 0);
    std::fs::create_dir_all(out_path.parent().expect("output path has a parent"))
        .expect("output directory must be creatable");

    let options = MillVariantOptions::default();
    let rules = MillRules::new(options.clone());
    let variant = DatabaseVariant::STANDARD;
    let provider = FileDatabaseProvider::new(std::path::PathBuf::from(&db_root));
    let mut db = Database::open_variant_with_options(
        provider.clone(),
        variant,
        DatabaseOptions::with_sector_cache_capacity(64),
    )
    .unwrap_or_else(|e| panic!("[human-dense-v2] failed to open DB at {db_root:?}: {e}"));
    let mut planes = WdlPlaneCache::new(provider, variant)
        .unwrap_or_else(|e| panic!("[human-dense-v2] failed to open plane cache: {e}"));
    let human = {
        let mut oracle = PlaneOracle {
            planes: &mut planes,
        };
        load_human_weights(
            &human_db,
            &rules,
            &options,
            &mut oracle,
            HumanWeightConfig::default(),
        )
        .expect("HumanDB weights load")
    };

    let mut parents: Vec<(u64, tgf_core::GameStateSnapshot)> = human
        .parent_snap_by_key
        .iter()
        .filter_map(|(&key, &snap)| {
            let stats = human.sample_stats(key)?;
            (stats.n_raw >= min_parent_raw).then_some((key, snap))
        })
        .collect();
    parents.sort_by_key(|&(key, _)| key);
    if max_parents > 0 && parents.len() > max_parents {
        parents.truncate(max_parents);
    }

    let mut out = std::io::BufWriter::new(
        std::fs::File::create(&out_path).expect("human-dense output must be creatable"),
    );
    let mut scanned = 0_usize;
    let mut unresolved_parent_wdl = 0_usize;
    let mut no_ranked_baseline = 0_usize;
    let mut fewer_than_two_covered = 0_usize;
    let mut eligible = 0_usize;
    let mut positive = 0_usize;
    let mut eligible_delta_sum = 0.0_f64;
    let mut positive_delta_sum = 0.0_f64;
    let mut eligible_by_parent: HashMap<String, Vec<f64>> = HashMap::new();
    let mut positive_by_parent: HashMap<String, Vec<f64>> = HashMap::new();

    for (parent_key, snap) in parents {
        scanned += 1;
        let parent_state = MillRules::decode_snapshot(snap);
        let parent_side = parent_state.side_to_move();
        let move_wdl = {
            let mut oracle = PlaneOracle {
                planes: &mut planes,
            };
            move_wdl_via_oracle(&rules, &snap, &options, &mut oracle)
        };
        let Some(move_wdl) = move_wdl else {
            unresolved_parent_wdl += 1;
            continue;
        };
        if move_wdl.is_empty() {
            unresolved_parent_wdl += 1;
            continue;
        }
        let ranked = rank_children(&rules, &options, &mut db, &mut planes, &snap, &move_wdl);
        let ranked_keys: Vec<u64> = ranked.optimal.iter().map(|child| child.key).collect();
        if ranked_keys.is_empty() {
            no_ranked_baseline += 1;
            continue;
        }

        let mut legal = tgf_core::ActionList::<256>::new();
        rules.legal_actions(&snap, &mut legal);
        let mut action_by_child_key: HashMap<u64, String> = HashMap::new();
        for &action in legal.as_slice() {
            let child_snap = rules.apply(&snap, action);
            let child_state = MillRules::decode_snapshot(child_snap);
            let Some(child_key) = perfect_db::canonical_key(&mut planes, &child_state, &options)
            else {
                continue;
            };
            if child_state.side_to_move() == parent_side {
                continue;
            }
            action_by_child_key
                .entry(child_key)
                .or_insert_with(|| tgf_mill::MillUciCodec::encode_action(action));
        }

        let mut covered_children = Vec::new();
        for key in ranked_keys {
            let Some(action) = action_by_child_key.get(&key) else {
                continue;
            };
            let mut oracle = PlaneOracle {
                planes: &mut planes,
            };
            let Some(ev) = human.raw_ev(key, &mut oracle) else {
                continue;
            };
            covered_children.push(HumanDenseChild {
                key,
                action: action.clone(),
                // Child side-to-move is the opponent after a side-flipping
                // parent choice, so negate once to express EV from the
                // parent mover's perspective.
                ev: -ev.value,
                n_scored: ev.n_scored,
                coverage: ev.coverage,
            });
        }

        let baseline_key = ranked
            .optimal
            .iter()
            .find(|child| action_by_child_key.contains_key(&child.key))
            .map(|child| child.key)
            .unwrap_or_else(|| covered_children.first().map(|child| child.key).unwrap_or(0));
        let Some(selection) = select_human_dense_candidate(baseline_key, &covered_children) else {
            fewer_than_two_covered += 1;
            continue;
        };

        eligible += 1;
        eligible_delta_sum += selection.delta_ev;
        eligible_by_parent
            .entry(parent_key.to_string())
            .or_default()
            .push(selection.delta_ev);
        let is_positive = selection.delta_ev > 0.0;
        if is_positive {
            positive += 1;
            positive_delta_sum += selection.delta_ev;
            positive_by_parent
                .entry(parent_key.to_string())
                .or_default()
                .push(selection.delta_ev);
        }

        use std::io::Write;
        writeln!(
            out,
            "{}",
            serde_json::json!({
                "parent_key": parent_key,
                "parent_n_raw": human.sample_stats(parent_key).expect("filtered above").n_raw,
                "covered_children": covered_children.len(),
                "baseline_key": selection.baseline.key,
                "baseline_action": selection.baseline.action,
                "baseline_ev": selection.baseline.ev,
                "baseline_n_scored": selection.baseline.n_scored,
                "baseline_coverage": selection.baseline.coverage,
                "steering_key": selection.steering.key,
                "steering_action": selection.steering.action,
                "steering_ev": selection.steering.ev,
                "steering_n_scored": selection.steering.n_scored,
                "steering_coverage": selection.steering.coverage,
                "delta_ev": selection.delta_ev,
                "positive": is_positive,
            })
        )
        .expect("human-dense row write");
    }

    use std::io::Write;
    out.flush().expect("flush human-dense census output");
    let eligible_ci = cluster_bootstrap_ci(&eligible_by_parent, 1000, 0x5eed_2026);
    let positive_ci = cluster_bootstrap_ci(&positive_by_parent, 1000, 0x5eed_2026);
    let (eligible_low, eligible_high) = eligible_ci.unwrap_or((f64::NAN, f64::NAN));
    let (positive_low, positive_high) = positive_ci.unwrap_or((f64::NAN, f64::NAN));
    eprintln!(
        "[human-dense-v2] scanned={scanned} eligible={eligible} positive={positive} \
         fewer_than_two_covered={fewer_than_two_covered} unresolved_parent_wdl={} \
         no_ranked_baseline={} min_parent_raw={} max_parents={} -> {}",
        unresolved_parent_wdl,
        no_ranked_baseline,
        min_parent_raw,
        max_parents,
        out_path.display()
    );
    eprintln!(
        "[human-dense-v2] eligible_mean_delta_ev={:.6} bootstrap95=[{eligible_low:.6},{eligible_high:.6}] \
         clusters={}",
        mean_or_nan(eligible_delta_sum, eligible),
        eligible_by_parent.len()
    );
    eprintln!(
        "[human-dense-v2] positive_mean_delta_ev={:.6} bootstrap95=[{positive_low:.6},{positive_high:.6}] \
         clusters={}",
        mean_or_nan(positive_delta_sum, positive),
        positive_by_parent.len()
    );
}

#[test]
#[should_panic(expected = "best_child must be one of the position's children")]
fn derive_child_proof_rejects_a_foreign_best_child() {
    let rules = rules();
    let opts = options();
    let mut oracle = TableOracle::new();
    oracle.default_value = Some(0);

    let parent_snap = rules.initial_state(&[]);
    let parent_state = MillRules::decode_snapshot(parent_snap);
    let parent_key = oracle.key_of(&parent_state, &opts);

    let entry = steering_entry(
        &rules.export_fen(&parent_state),
        parent_key,
        0xdead_beef, // not a child of the initial position
    );
    let mut memo = DensityMemo::new();
    let mut stats = RecomputeStats::default();
    let _ = derive_child_proof(
        &entry,
        &rules,
        &opts,
        &mut oracle,
        &HashMap::new(),
        None,
        RiskGateConfig::default(),
        &mut memo,
        &mut RiskMemo::new(),
        &mut stats,
    );
}
