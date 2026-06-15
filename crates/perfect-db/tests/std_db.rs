// SPDX-License-Identifier: GPL-3.0-or-later

use perfect_db::database::{Database, FileDatabaseProvider};
use perfect_db::{
    best_move_token, best_move_token_for_state, evaluate, evaluate_state_for,
    evaluate_state_with_database, init,
};
use tgf_core::{ActionList, GameRules, GameStateSnapshot};
use tgf_mill::notation::MillUciCodec;
use tgf_mill::{MillRules, MillVariantOptions};

fn apply_sequence(rules: &MillRules, labels: &[&str]) -> GameStateSnapshot {
    let mut snap = rules.initial_state(&[]);
    for label in labels {
        let action = MillUciCodec::decode_action(&snap, label)
            .unwrap_or_else(|| panic!("failed to decode action {label}"));
        let mut legal = ActionList::<256>::default();
        rules.legal_actions(&snap, &mut legal);
        assert!(
            legal.as_slice().contains(&action),
            "action {label} must be legal"
        );
        snap = rules.apply(&snap, action);
    }
    snap
}

fn db_path() -> &'static str {
    concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../src/ui/flutter_app/assets/databases"
    )
}

fn assert_best_move_is_legal(rules: &MillRules, snap: &GameStateSnapshot, token: &str) {
    let action = MillUciCodec::decode_action(snap, token)
        .unwrap_or_else(|| panic!("failed to decode best move token {token}"));
    let mut legal = ActionList::<256>::default();
    rules.legal_actions(snap, &mut legal);
    assert!(
        legal.as_slice().contains(&action),
        "best move token {token} must be legal"
    );
}

struct OracleCase {
    name: &'static str,
    labels: &'static [&'static str],
    expected_eval: Option<(i32, i32)>,
}

#[test]
fn std_perfect_db_oracle_vectors() {
    assert!(
        init(db_path()),
        "pd_init_std must succeed with bundled assets"
    );

    assert_eq!(
        evaluate(0, 0, 9, 9, 0, false),
        Some((0, 2)),
        "empty start position must keep the current C++ oracle value"
    );
    let token = best_move_token(0, 0, 9, 9, 0, false);
    assert!(token.is_some(), "perfect db must return an opening move");
    assert!(!token.unwrap().is_empty());

    let rules = MillRules::default();
    let options = MillVariantOptions::default();
    let mut rust_db = Database::open(FileDatabaseProvider::new(db_path())).unwrap();
    let cases = [
        OracleCase {
            name: "empty",
            labels: &[],
            expected_eval: Some((0, 2)),
        },
        OracleCase {
            name: "after_a4",
            labels: &["a4"],
            expected_eval: Some((0, 1)),
        },
    ];

    for case in cases {
        let snap = apply_sequence(&rules, case.labels);
        let state = MillRules::decode_snapshot(snap);
        let side = case.labels.len() % 2;
        assert_eq!(
            evaluate_state_for(&state, &options, side as i8),
            case.expected_eval,
            "{} must match the current C++ perfect-db oracle",
            case.name
        );
        assert_eq!(
            evaluate_state_with_database(&mut rust_db, &state, &options, side as i8).unwrap(),
            case.expected_eval,
            "{} must match the Rust-native perfect-db loader",
            case.name
        );
        let token = best_move_token_for_state(&state, &options, side as i8)
            .unwrap_or_else(|| panic!("{} must return a best move token", case.name));
        assert_best_move_is_legal(&rules, &snap, &token);
    }

    // Do not call deinit here: the current C++ bridge has fragile sector-hash
    // shutdown behavior. The Rust rewrite should make shutdown deterministic,
    // but these oracle vectors only need process-lifetime resources.
}
