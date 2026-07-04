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
    let proof = derive_child_proof(
        &entry,
        &rules,
        &opts,
        &mut oracle,
        &trap_score_by_key,
        None,
        &mut memo,
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
    let proof = derive_child_proof(
        &entry,
        &rules,
        &opts,
        &mut oracle,
        &trap_score_by_key,
        None,
        &mut memo,
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
    let proof = derive_child_proof(
        &entry,
        &rules,
        &opts,
        &mut oracle,
        &HashMap::new(),
        Some(&human),
        &mut memo,
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
    let proof_a = derive_child_proof(
        &entry,
        &rules,
        &opts,
        &mut oracle,
        &HashMap::new(),
        None,
        &mut memo_a,
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
    let proof_b = derive_child_proof(
        &entry,
        &rules,
        &opts,
        &mut oracle,
        &HashMap::new(),
        Some(&human),
        &mut memo_b,
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
    let proof = derive_child_proof(
        &entry,
        &rules,
        &opts,
        &mut oracle,
        &HashMap::new(),
        None,
        &mut memo,
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
        &mut memo,
        &mut stats,
    );
}
