// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

//! Blocker tests for the HumanDB aggregation. Every test runs against a
//! purpose-built sqlite fixture and the deterministic [`TableOracle`]
//! (production canonical-key and sign computation; only WDL *values* are
//! injected) -- no test opens a real `human_db.sqlite` or scans a Perfect
//! DB for positions.

use std::sync::atomic::{AtomicUsize, Ordering};

use rusqlite::Connection;
use tgf_core::GameRules;
use tgf_mill::human_db_codec::{
    HumanTurn, SYM_INVERSE, fen_from_state_key, parse_human_turn_notation, state_key_from_fen,
    transform_notation,
};

use super::super::recompute::{TableOracle, WdlOracle};
use super::*;

static FIXTURE_COUNTER: AtomicUsize = AtomicUsize::new(0);

fn rules() -> MillRules {
    MillRules::new(MillVariantOptions::default())
}

fn options() -> MillVariantOptions {
    MillVariantOptions::default()
}

/// Write a `moves` table fixture and return its path.
fn fixture_db(rows: &[(&str, &str, i64)]) -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!(
        "sanmill_human_weight_test_{}_{}",
        std::process::id(),
        FIXTURE_COUNTER.fetch_add(1, Ordering::Relaxed)
    ));
    std::fs::create_dir_all(&dir).expect("fixture dir");
    let path = dir.join("human.sqlite");
    let _ = std::fs::remove_file(&path);
    let conn = Connection::open(&path).expect("fixture sqlite");
    conn.execute_batch(
        "CREATE TABLE moves (state_key TEXT NOT NULL, notation TEXT NOT NULL, \
         total INTEGER NOT NULL, extra TEXT)",
    )
    .expect("fixture schema");
    for (state_key, notation, total) in rows {
        conn.execute(
            "INSERT INTO moves (state_key, notation, total) VALUES (?1, ?2, ?3)",
            rusqlite::params![state_key, notation, total],
        )
        .expect("fixture row");
    }
    path
}

/// The initial position's state_key (verified against the human database
/// builder's convention in the codec tests).
const INITIAL_KEY: &str = "........................|W|place|0|0|0|0";

/// Apply scripted human-notation moves from the initial position.
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

/// Canonical key of the position reached by `tokens` from the start.
fn key_after(rules: &MillRules, oracle: &mut TableOracle, tokens: &[&str]) -> u64 {
    let snap = play(rules, tokens);
    oracle.key_of(&MillRules::decode_snapshot(snap), &options())
}

/// Build a database row for the position reached by `tokens`: its
/// state_key plus `notation` transformed from the concrete orientation
/// into the key's canonical frame (a row's notation always lives in the
/// same D4 orientation as its `state_key`).
///
/// Two round-trip assertions pin the transform direction: the inverse
/// symmetry must map the framed notation back to the original, and the
/// framed notation must actually parse against the state decoded from the
/// state_key itself.
fn db_row_for(rules: &MillRules, tokens: &[&str], notation: &str) -> (String, String) {
    let snap = play(rules, tokens);
    let state = MillRules::decode_snapshot(snap);
    let fen = rules.export_fen(&state);
    let (state_key, sym_idx) = state_key_from_fen(&fen).expect("scripted state must key");
    let framed = transform_notation(notation, sym_idx).expect("notation must transform");

    let back = transform_notation(&framed, SYM_INVERSE[sym_idx])
        .expect("framed notation must transform back");
    assert_eq!(
        back, notation,
        "transform_notation direction is wrong: inverse symmetry must restore the original"
    );
    let key_fen = fen_from_state_key(&state_key).expect("state_key must decode");
    let key_state = rules.set_from_fen(&key_fen).expect("state_key FEN parses");
    let key_snap = rules.encode_state(key_state);
    assert!(
        parse_human_turn_notation(rules, &key_snap, &framed).is_ok(),
        "framed notation {framed:?} must be legal in the state_key's own frame"
    );
    (state_key, framed)
}

#[test]
fn load_aggregates_settled_endpoints_with_calibrated_signs() {
    let rules = rules();
    let mut oracle = TableOracle::new();
    oracle.default_value = Some(0);

    let db = fixture_db(&[(INITIAL_KEY, "d2", 6), (INITIAL_KEY, "b2", 4)]);
    let weights = load_human_weights(
        &db,
        &rules,
        &options(),
        &mut oracle,
        HumanWeightConfig::default(),
    )
    .expect("clean fixture must load");

    let parent_key = key_after(&rules, &mut oracle, &[]);
    let responses = weights.turn.get(&parent_key).expect("parent aggregated");
    assert_eq!(responses.scored_total(), 10);
    assert_eq!(responses.unresolved_total, 0);
    assert_eq!(weights.stats.rows, 2);
    assert_eq!(weights.stats.turn_scored_weight, 10);
    assert_eq!(weights.stats.step_scored_weight, 0);
    assert_eq!(weights.stats.decodable_weight, 10);

    // Explicit sign chain for the d2 endpoint: direct == raw == 0 =>
    // sign_vs_reached = +1; the placement hands the move to black (flip
    // -1); stored sign must be -1.
    let d2_snap = play(&rules, &["d2"]);
    let d2_key = key_after(&rules, &mut oracle, &["d2"]);
    let direct = oracle
        .direct_wdl(&rules, &d2_snap, &options())
        .expect("value planted");
    let raw = oracle.raw_wdl_by_key(d2_key).expect("value planted");
    assert_eq!(direct, 0);
    assert_eq!(raw, 0);
    assert_eq!(combine_sign(direct, raw), 1);

    let b2_key = key_after(&rules, &mut oracle, &["b2"]);
    assert_eq!(
        responses.targets.get(&ResponseTarget::Key {
            key: d2_key,
            sign_to_parent: -1,
        }),
        Some(&6)
    );
    assert_eq!(
        responses.targets.get(&ResponseTarget::Key {
            key: b2_key,
            sign_to_parent: -1,
        }),
        Some(&4)
    );
}

/// The plane may store a reached position under the opposite perspective
/// (`raw == -direct`); the stored sign must absorb that flip. A real
/// database may or may not exercise this branch, so it is pinned here with
/// a planted override instead of scavenged data.
#[test]
fn load_calibrates_the_negated_plane_perspective_branch() {
    let rules = rules();
    let mut oracle = TableOracle::new();
    oracle.default_value = Some(0);

    let d2_snap = play(&rules, &["d2"]);
    let d2_key = key_after(&rules, &mut oracle, &["d2"]);
    // direct (own side) says -1, the plane's folded slot says +1.
    oracle.own_value_by_key.insert(d2_key, -1);
    oracle.raw_override_by_key.insert(d2_key, 1);

    // Explicit chain: direct = -1, raw = +1, sign_vs_reached = -1, flip =
    // -1 (side handed over), sign_to_parent = +1, and the reply value read
    // back through that sign is sign * raw = +1.
    let direct = oracle
        .direct_wdl(&rules, &d2_snap, &options())
        .expect("value planted");
    let raw = oracle.raw_wdl_by_key(d2_key).expect("value planted");
    assert_eq!(direct, -1);
    assert_eq!(raw, 1);
    assert_eq!(combine_sign(direct, raw), -1);

    let db = fixture_db(&[(INITIAL_KEY, "d2", 5)]);
    let weights = load_human_weights(
        &db,
        &rules,
        &options(),
        &mut oracle,
        HumanWeightConfig {
            min_samples: 1,
            min_coverage: 0.0,
            shrinkage_k: 0.0,
            allow_lossy: false,
        },
    )
    .expect("clean fixture must load");

    let parent_key = key_after(&rules, &mut oracle, &[]);
    let responses = weights.turn.get(&parent_key).expect("parent aggregated");
    let stored_sign = 1_i8;
    assert_eq!(
        responses.targets.get(&ResponseTarget::Key {
            key: d2_key,
            sign_to_parent: stored_sign,
        }),
        Some(&5),
        "flip (-1) * sign_vs_reached (-1) must store sign_to_parent +1"
    );
    assert_eq!(
        stored_sign * raw,
        1,
        "reply value in the parent's perspective"
    );

    // Consumption: reply +1 against best +1 is severity 0, so the human
    // density must be exactly 0. A wrongly stored sign (-1) would read the
    // reply as -1 (severity 2) and produce density 1.0 instead.
    let density = weights
        .behavior_density(parent_key, 1, 0.0, &mut oracle)
        .expect("gates pass with min_samples 1");
    assert_eq!(density, 0.0);
}

#[test]
fn combine_sign_accepts_the_three_conventions_and_rejects_drift() {
    assert_eq!(combine_sign(1, 1), 1);
    assert_eq!(combine_sign(0, 0), 1);
    assert_eq!(combine_sign(1, -1), -1);
    assert_eq!(combine_sign(-1, 1), -1);
    let broke = std::panic::catch_unwind(|| combine_sign(1, 0));
    assert!(broke.is_err(), "direct 1 vs raw 0 must fail loudly");
}

#[test]
fn load_buckets_every_failure_mode_without_scoring_them() {
    let rules = rules();
    let mut oracle = TableOracle::new();
    oracle.default_value = Some(0);

    let mill_tokens = ["d6", "b4", "d5", "b2"];
    let (mill_key, mill_missing_capture) = db_row_for(&rules, &mill_tokens, "d7");
    let (_, mill_bad_capture) = {
        // `d7xg1` captures an empty point: legal base, invalid capture. The
        // helper's parse round-trip would reject it, so frame it manually
        // through the same symmetry as a valid row of that state_key.
        let (key, framed_good) = db_row_for(&rules, &mill_tokens, "d7xb4");
        let _ = framed_good;
        let snap = play(&rules, &mill_tokens);
        let state = MillRules::decode_snapshot(snap);
        let fen = rules.export_fen(&state);
        let (_, sym_idx) = state_key_from_fen(&fen).expect("scripted state must key");
        (
            key,
            transform_notation("d7xg1", sym_idx).expect("transformable"),
        )
    };

    let db = fixture_db(&[
        (INITIAL_KEY, "d2", 60),               // scored
        (INITIAL_KEY, "z9", 1),                // base invalid
        (INITIAL_KEY, "d6xb4", 1),             // unexpected capture (no mill)
        (INITIAL_KEY, "xd6", 1),               // bare capture on settled parent
        (INITIAL_KEY, "d2", 0),                // non-positive total
        (INITIAL_KEY, "d2", -3),               // non-positive total
        ("garbage-key", "d2", 1),              // undecodable state_key
        (&mill_key, &mill_missing_capture, 1), // mill formed, capture missing
        (&mill_key, &mill_bad_capture, 1),     // capture segment invalid
    ]);
    let weights = load_human_weights(
        &db,
        &rules,
        &options(),
        &mut oracle,
        HumanWeightConfig {
            allow_lossy: true, // invalid share is large by construction
            ..HumanWeightConfig::default()
        },
    )
    .expect("allow_lossy fixture must load");

    let s = &weights.stats;
    assert_eq!(s.rows, 9);
    assert_eq!(s.non_positive_total_rows, 2);
    assert_eq!(s.state_key_undecodable_rows, 1);
    assert_eq!(s.state_key_undecodable_weight, 1);
    assert_eq!(s.base_invalid_rows, 1);
    assert_eq!(s.capture_invalid_rows, 1);
    assert_eq!(s.unexpected_capture_rows, 2, "d6xb4 and xd6 both land here");
    assert_eq!(s.missing_capture_rows, 1);
    assert_eq!(s.missing_capture_weight, 1);
    assert_eq!(s.turn_scored_weight, 60, "only the clean row scores");
    assert_eq!(s.step_scored_weight, 0);
    // decodable weight excludes the undecodable row and non-positive rows.
    assert_eq!(s.decodable_weight, 65);
}

/// Bad external data is an `Err`, not a panic: the CLI reports it and
/// exits nonzero instead of presenting a crash.
#[test]
fn load_returns_err_when_parser_invalid_share_exceeds_the_hard_limit() {
    let rules = rules();
    let mut oracle = TableOracle::new();
    oracle.default_value = Some(0);

    // 10% of the decodable weight fails parsing (limit is 5%).
    let rows = [(INITIAL_KEY, "d2", 90_i64), (INITIAL_KEY, "z9", 10)];

    let strict = load_human_weights(
        &fixture_db(&rows),
        &rules,
        &options(),
        &mut oracle,
        HumanWeightConfig::default(),
    );
    let err = strict.err().expect("above-limit share must be an Err");
    assert!(
        err.contains("failed notation parsing"),
        "unexpected error: {err}"
    );
    assert!(
        err.contains("--allow-human-db-lossy"),
        "the error must point at the escape hatch: {err}"
    );

    // The explicit escape hatch proceeds and keeps the diagnostics.
    let lossy = load_human_weights(
        &fixture_db(&rows),
        &rules,
        &options(),
        &mut oracle,
        HumanWeightConfig {
            allow_lossy: true,
            ..HumanWeightConfig::default()
        },
    )
    .expect("allow_lossy must proceed");
    assert_eq!(lossy.stats.base_invalid_rows, 1);
    assert_eq!(lossy.stats.base_invalid_weight, 10);
    assert_eq!(lossy.stats.turn_scored_weight, 90);
}

#[test]
fn load_returns_err_on_missing_file_and_missing_columns() {
    let rules = rules();
    let mut oracle = TableOracle::new();

    let missing = std::env::temp_dir().join("sanmill_human_weight_does_not_exist.sqlite");
    let err = load_human_weights(
        &missing,
        &rules,
        &options(),
        &mut oracle,
        HumanWeightConfig::default(),
    )
    .err()
    .expect("missing file must be an Err");
    assert!(err.contains("does not exist"), "unexpected error: {err}");

    // A `moves` table without the `total` column.
    let dir = std::env::temp_dir().join(format!(
        "sanmill_human_weight_badschema_{}",
        std::process::id()
    ));
    std::fs::create_dir_all(&dir).expect("fixture dir");
    let path = dir.join("human.sqlite");
    let _ = std::fs::remove_file(&path);
    let conn = Connection::open(&path).expect("fixture sqlite");
    conn.execute_batch("CREATE TABLE moves (state_key TEXT, notation TEXT)")
        .expect("schema");
    drop(conn);
    let err = load_human_weights(
        &path,
        &rules,
        &options(),
        &mut oracle,
        HumanWeightConfig::default(),
    )
    .err()
    .expect("missing column must be an Err");
    assert!(
        err.contains("missing required column `total`"),
        "unexpected error: {err}"
    );
}

#[test]
fn load_records_compound_turns_into_both_maps() {
    let rules = rules();
    let mut oracle = TableOracle::new();
    oracle.default_value = Some(0);

    let mill_tokens = ["d6", "b4", "d5", "b2"];
    let (mill_key, framed_compound) = db_row_for(&rules, &mill_tokens, "d7xb4");
    let db = fixture_db(&[(&mill_key, &framed_compound, 7)]);
    let weights = load_human_weights(
        &db,
        &rules,
        &options(),
        &mut oracle,
        HumanWeightConfig::default(),
    )
    .expect("clean fixture must load");

    let parent_key = key_after(&rules, &mut oracle, &mill_tokens);
    let reached_key = key_after(&rules, &mut oracle, &["d6", "b4", "d5", "b2", "d7xb4"]);
    let turn_responses = weights.turn.get(&parent_key).expect("turn map entry");
    assert_eq!(
        turn_responses.targets.get(&ResponseTarget::Key {
            key: reached_key,
            sign_to_parent: -1,
        }),
        Some(&7),
        "full-turn endpoint keyed under the settled parent"
    );
    assert_eq!(weights.stats.compound_rows, 1);
    assert_eq!(weights.stats.compound_decodable_weight, 7);
    assert_eq!(weights.stats.compound_scored_weight, 7);
    assert_eq!(weights.stats.turn_scored_weight, 7);
    assert_eq!(weights.stats.step_scored_weight, 7);
    assert!((weights.stats.compound_turn_weight_share() - 1.0).abs() < 1e-12);

    // The capture segment is also recorded under the synthesized
    // mid-removal parent (canonical across orientations, so deriving it
    // from the concrete frame matches the loader's canonical frame).
    let mill_snap = play(&rules, &mill_tokens);
    let HumanTurn::BaseThenCapture { base, .. } =
        parse_human_turn_notation(&rules, &mill_snap, "d7xb4").expect("mill turn")
    else {
        panic!("d7xb4 must be compound");
    };
    let mid_state = MillRules::decode_snapshot(rules.apply(&mill_snap, base));
    let mid_key = perfect_db::mid_removal_key(&mid_state).expect("pending removal key");
    let step_responses = weights.step.get(&mid_key).expect("step map entry");
    assert_eq!(step_responses.scored_total(), 7);
}

#[test]
fn load_counts_unresolvable_endpoints_into_the_unresolved_bucket() {
    let rules = rules();
    let mut oracle = TableOracle::new();
    // No default value: the reached endpoint has no WDL coverage.
    let db = fixture_db(&[(INITIAL_KEY, "d2", 8)]);
    let weights = load_human_weights(
        &db,
        &rules,
        &options(),
        &mut oracle,
        HumanWeightConfig::default(),
    )
    .expect("clean fixture must load");

    let parent_key = key_after(&rules, &mut oracle, &[]);
    let responses = weights.turn.get(&parent_key).expect("parent aggregated");
    assert_eq!(responses.scored_total(), 0);
    assert_eq!(responses.unresolved_total, 8);
    assert_eq!(weights.stats.turn_unresolved_rows, 1);
    assert_eq!(weights.stats.turn_unresolved_weight, 8);
}

#[test]
fn behavior_density_gates_on_min_samples_and_coverage() {
    let mut oracle = TableOracle::new();
    let config = HumanWeightConfig {
        min_samples: 10,
        min_coverage: 0.8,
        shrinkage_k: 0.0,
        allow_lossy: false,
    };
    let mut weights = HumanWeights {
        turn: HashMap::new(),
        step: HashMap::new(),
        parent_snap_by_key: HashMap::new(),
        config,
        stats: HumanWeightStats::default(),
    };

    // 9 scored samples < min_samples 10.
    weights.turn.insert(
        1,
        HumanResponses {
            targets: HashMap::from([(ResponseTarget::Terminal(-1), 9_u64)]),
            unresolved_total: 0,
        },
    );
    assert!(weights.behavior_density(1, 1, 0.0, &mut oracle).is_none());

    // 12 scored but 8 unresolved: coverage 12/20 = 0.6 < 0.8.
    weights.turn.insert(
        2,
        HumanResponses {
            targets: HashMap::from([(ResponseTarget::Terminal(-1), 12_u64)]),
            unresolved_total: 8,
        },
    );
    assert!(weights.behavior_density(2, 1, 0.0, &mut oracle).is_none());

    // 12 scored, 1 unresolved: gates pass; all replies lose by 2 against
    // best +1 => density 12*2 / (2*12) = 1.0.
    weights.turn.insert(
        3,
        HumanResponses {
            targets: HashMap::from([(ResponseTarget::Terminal(-1), 12_u64)]),
            unresolved_total: 1,
        },
    );
    let density = weights
        .behavior_density(3, 1, 0.0, &mut oracle)
        .expect("gates pass");
    assert!((density - 1.0).abs() < 1e-12);

    // A missing parent key is simply ungated data.
    assert!(weights.behavior_density(99, 1, 0.0, &mut oracle).is_none());
}

#[test]
fn raw_ev_from_replies_gates_and_reports_coverage() {
    let replies = [(1, 6_u64), (-1, 4_u64)];

    assert!(
        raw_ev_from_replies(&replies, 0, 11, 0.0).is_none(),
        "10 scored samples should fail a min-samples gate of 11"
    );
    assert!(
        raw_ev_from_replies(&replies, 5, 1, 0.8).is_none(),
        "coverage 10/15 should fail an 80% coverage gate"
    );

    let ev = raw_ev_from_replies(&replies, 2, 1, 0.8).expect("sample gates pass");
    assert_eq!(ev.n_scored, 10);
    assert_eq!(ev.n_raw, 12);
    assert!((ev.coverage - (10.0 / 12.0)).abs() < 1e-12);
    assert!((ev.value - 0.2).abs() < 1e-12);
}

#[test]
fn raw_ev_resolves_terminal_and_key_targets_without_shrinkage() {
    let mut oracle = TableOracle::new();
    oracle.raw_override_by_key.insert(0x42, 1);
    oracle.raw_override_by_key.insert(0x43, -1);

    let config = HumanWeightConfig {
        min_samples: 1,
        min_coverage: 0.0,
        shrinkage_k: 1_000.0,
        allow_lossy: false,
    };
    let mut weights = HumanWeights {
        turn: HashMap::new(),
        step: HashMap::new(),
        parent_snap_by_key: HashMap::new(),
        config,
        stats: HumanWeightStats::default(),
    };
    weights.turn.insert(
        11,
        HumanResponses {
            targets: HashMap::from([
                (ResponseTarget::Terminal(1), 2_u64),
                (
                    ResponseTarget::Key {
                        key: 0x42,
                        sign_to_parent: -1,
                    },
                    3_u64,
                ),
                (
                    ResponseTarget::Key {
                        key: 0x43,
                        sign_to_parent: -1,
                    },
                    5_u64,
                ),
            ]),
            unresolved_total: 4,
        },
    );

    assert_eq!(
        reply_value_from_target(
            ResponseTarget::Key {
                key: 0x42,
                sign_to_parent: -1,
            },
            &mut oracle,
        ),
        -1
    );
    assert_eq!(
        reply_value_from_target(
            ResponseTarget::Key {
                key: 0x43,
                sign_to_parent: -1,
            },
            &mut oracle,
        ),
        1
    );

    let ev = weights.raw_ev(11, &mut oracle).expect("sample gates pass");
    assert_eq!(ev.n_scored, 10);
    assert_eq!(ev.n_raw, 14);
    assert!((ev.coverage - (10.0 / 14.0)).abs() < 1e-12);
    // Raw EV is (2*1 + 3*(-1) + 5*1) / 10 = 0.4. The huge
    // shrinkage_k above must not affect replay EV.
    assert!((ev.value - 0.4).abs() < 1e-12);

    let stats = weights.sample_stats(11).expect("stats exist");
    assert_eq!(stats.n_scored, ev.n_scored);
    assert_eq!(stats.n_raw, ev.n_raw);
    assert_eq!(stats.coverage, ev.coverage);
}

#[test]
fn raw_ev_matches_the_weighted_density_identity() {
    // When all human replies are no better than `best_value`, the raw
    // parent-perspective EV and the weighted blunder density are linked by
    // EV = best - 2*density. This pins the replay metric to the same
    // severity convention used by the packer while keeping it unshrunken.
    let best_value = 1;
    let replies = [(1, 4_u64), (0, 2_u64), (-1, 4_u64)];

    let ev = raw_ev_from_replies(&replies, 0, 1, 0.0)
        .expect("identity fixture has full coverage")
        .value;
    let density = weighted_blunder_density(best_value, &replies);

    assert!((ev - 0.0).abs() < 1e-12);
    assert!((density - 0.5).abs() < 1e-12);
    assert!((ev - (f64::from(best_value) - 2.0 * density)).abs() < 1e-12);
}

#[test]
fn behavior_density_resolves_key_targets_through_the_stored_sign() {
    let mut oracle = TableOracle::new();
    oracle.raw_override_by_key.insert(0x42, 1);
    // Explicit: the plane's raw value for the slot both targets share.
    let raw = oracle.raw_wdl_by_key(0x42).expect("planted");
    assert_eq!(raw, 1);

    let config = HumanWeightConfig {
        min_samples: 1,
        min_coverage: 0.0,
        shrinkage_k: 0.0,
        allow_lossy: false,
    };
    let mut weights = HumanWeights {
        turn: HashMap::new(),
        step: HashMap::new(),
        parent_snap_by_key: HashMap::new(),
        config,
        stats: HumanWeightStats::default(),
    };
    // Two targets on the same plane slot with opposite stored signs:
    // reply values must read sign * raw = +1 (severity 0 against best +1)
    // and -1 (severity 2).
    weights.turn.insert(
        7,
        HumanResponses {
            targets: HashMap::from([
                (
                    ResponseTarget::Key {
                        key: 0x42,
                        sign_to_parent: 1,
                    },
                    5_u64,
                ),
                (
                    ResponseTarget::Key {
                        key: 0x42,
                        sign_to_parent: -1,
                    },
                    5_u64,
                ),
            ]),
            unresolved_total: 0,
        },
    );
    let sign_pos = 1_i8;
    let sign_neg = -1_i8;
    assert_eq!(sign_pos * raw, 1, "first target's reply value");
    assert_eq!(sign_neg * raw, -1, "second target's reply value");
    let density = weights
        .behavior_density(7, 1, 0.0, &mut oracle)
        .expect("gates pass");
    // weighted severity = 5 * 2 from the -1 reply only, denominator 2*10.
    assert!((density - 0.5).abs() < 1e-12);
}

#[test]
fn shrinkage_pulls_toward_the_uniform_density() {
    // n = 10, k = 30: blended = (10 * 1.0 + 30 * 0.2) / 40 = 0.4.
    assert!((shrunk_density(1.0, 0.2, 10, 30.0) - 0.4).abs() < 1e-12);
    // k = 0 disables shrinkage entirely.
    assert!((shrunk_density(1.0, 0.2, 10, 0.0) - 1.0).abs() < 1e-12);
}

#[test]
fn weighted_blunder_density_ignores_improving_replies() {
    // best 0; replies: -1 (severity 1, weight 3), 0 (severity 0, weight
    // 5), +1 ("improving", clamped to 0, weight 2).
    let density = weighted_blunder_density(0, &[(-1, 3), (0, 5), (1, 2)]);
    assert!((density - 3.0 / 20.0).abs() < 1e-12);
}

/// Directed key probe: for each of the four representative positions the
/// aggregation must file its data under exactly the canonical key that
/// perfect-db derives for the same position -- the packer's density pass
/// looks child keys up in these maps, so a single frame/phase/hand-count
/// mismatch in the state_key decode would silently zero the behavior
/// signal (hit rates against a real database can only be *interpreted*
/// through this equivalence, never assumed).
#[test]
fn human_db_parent_keys_match_perfect_db_canonical_keys() {
    let rules = rules();
    let mut oracle = TableOracle::new();
    oracle.default_value = Some(0);

    let probes: [&[&str]; 3] = [
        &[],           // startpos, white to place
        &["d2"],       // black to place
        &["d2", "d6"], // white to place again
    ];
    let mut rows: Vec<(String, String, i64)> = Vec::new();
    for tokens in probes {
        let follow_up = if tokens.len() == 1 { "d6" } else { "b2" };
        let (state_key, framed) = db_row_for(&rules, tokens, follow_up);
        rows.push((state_key, framed, 3));
    }
    // Compound probe for the synthesized mid-removal parent.
    let mill_tokens = ["d6", "b4", "d5", "b2"];
    let (mill_state_key, framed_compound) = db_row_for(&rules, &mill_tokens, "d7xb4");
    rows.push((mill_state_key, framed_compound, 3));

    let fixture_rows: Vec<(&str, &str, i64)> = rows
        .iter()
        .map(|(k, n, t)| (k.as_str(), n.as_str(), *t))
        .collect();
    let db = fixture_db(&fixture_rows);
    let weights = load_human_weights(
        &db,
        &rules,
        &options(),
        &mut oracle,
        HumanWeightConfig::default(),
    )
    .expect("probe fixture must load");

    for tokens in probes {
        let perfect_key = key_after(&rules, &mut oracle, tokens);
        let aggregated = weights.turn.contains_key(&perfect_key);
        eprintln!(
            "[probe] tokens={tokens:?} perfect_db canonical key={perfect_key:#018x} \
             turn-map hit={aggregated}"
        );
        assert!(
            aggregated,
            "HumanDB aggregation for {tokens:?} must be keyed by the perfect-db canonical \
             key {perfect_key:#x}; a miss means the state_key decode / canonicalization \
             diverged"
        );
    }
    let mill_snap = play(&rules, &mill_tokens);
    let HumanTurn::BaseThenCapture { base, .. } =
        parse_human_turn_notation(&rules, &mill_snap, "d7xb4").expect("mill turn")
    else {
        panic!("d7xb4 must be compound");
    };
    let mid_state = MillRules::decode_snapshot(rules.apply(&mill_snap, base));
    let mid_key = perfect_db::mid_removal_key(&mid_state).expect("pending removal");
    eprintln!(
        "[probe] compound mid-removal perfect_db key={mid_key:#018x} step-map hit={}",
        weights.step.contains_key(&mid_key)
    );
    assert!(
        weights.step.contains_key(&mid_key),
        "the step map must be keyed by perfect_db::mid_removal_key"
    );
}

/// Terminal endpoints are valued from the game outcome alone -- no
/// canonicalization, no plane lookup (the oracle here has no values at
/// all, so any WDL touch would fail to resolve and land in `None`).
#[test]
fn response_target_scores_terminal_endpoints_from_the_outcome() {
    let rules = rules();
    let mut oracle = TableOracle::new();
    assert!(oracle.own_value_by_key.is_empty() && oracle.default_value.is_none());

    // Ground truth first, from the rules' own outcome (not FEN mental
    // math): white totals 1 on board + 1 in hand = 2 < 3, so the import is
    // a finished game won by BLACK (side 1).
    let terminal_fen = "********/@@@*O*@@/******** b m s 1 1 5 4 0 0 -1 -1 -1 -1 0 0 1 ids:nodes";
    let terminal_state = rules.set_from_fen(terminal_fen).expect("terminal FEN");
    let terminal_snap = rules.encode_state(terminal_state);
    let winner = match rules.outcome(&terminal_snap).kind {
        OutcomeKind::Win(winner) => winner,
        other => panic!("fixture must be a decided game, got {other:?}"),
    };
    assert_eq!(i16::from(winner), 1, "black must be the recorded winner");

    // From a white-to-move parent the losing side's win reads -1...
    let white_parent = MillRules::decode_snapshot(rules.initial_state(&[]));
    assert_eq!(white_parent.side_to_move(), 0);
    let target_white = response_target(
        &white_parent,
        &terminal_snap,
        &rules,
        &options(),
        &mut oracle,
    )
    .expect("terminal targets always resolve");
    assert_eq!(target_white, ResponseTarget::Terminal(-1));

    // ...and from a black-to-move parent, +1.
    let black_parent = MillRules::decode_snapshot(play(&rules, &["d6"]));
    assert_eq!(black_parent.side_to_move(), 1);
    let target_black = response_target(
        &black_parent,
        &terminal_snap,
        &rules,
        &options(),
        &mut oracle,
    )
    .expect("terminal targets always resolve");
    assert_eq!(target_black, ResponseTarget::Terminal(1));
}
