// SPDX-License-Identifier: GPL-3.0-or-later

#[cfg(feature = "cpp-oracle")]
use perfect_db::database::PerfectOutcome;
use perfect_db::database::{Database, FileDatabaseProvider, PerfectQuery};
use perfect_db::{
    best_move_choice_for_rust_database, best_move_choice_rust_database,
    best_move_choice_with_database, best_move_token_rust_database, best_move_token_with_database,
    deinit_rust_database, evaluate, evaluate_rust_database, evaluate_state_for_rust_database, init,
    init_rust_database, is_rust_database_initialized, snapshot_from_perfect_query,
};
#[cfg(feature = "cpp-oracle")]
use perfect_db::{
    best_move_token, best_move_token_for_state, evaluate_state_for,
    evaluate_state_outcome_with_database, evaluate_state_with_database,
};
use tgf_core::{ActionList, BoardTopology, GameRules, GameStateSnapshot};
use tgf_mill::notation::MillUciCodec;
use tgf_mill::{MillRules, MillVariantOptions, default_mill_topology};

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

fn perfect_bits(labels: &[&str]) -> u32 {
    const PERFECT_LABELS: [&str; 24] = [
        "a4", "a7", "d7", "g7", "g4", "g1", "d1", "a1", "b4", "b6", "d6", "f6", "f4", "f2", "d2",
        "b2", "c4", "c5", "d5", "e5", "e4", "e3", "d3", "c3",
    ];

    labels.iter().fold(0u32, |bits, label| {
        let idx = PERFECT_LABELS
            .iter()
            .position(|candidate| candidate == label)
            .unwrap_or_else(|| panic!("missing perfect label {label}"));
        bits | (1u32 << idx)
    })
}

fn set_piece_by_label(state: &mut tgf_mill::rules::MillState, label: &str, owner: i8) {
    let topo = default_mill_topology();
    let node = topo
        .node_from_label(label)
        .unwrap_or_else(|| panic!("missing node label {label}"));
    state.set_piece(node, owner);
}

fn pending_removal_snapshot(rules: &MillRules, options: &MillVariantOptions) -> GameStateSnapshot {
    let mut state = rules.setup_empty();
    for label in ["a4", "a7", "d7"] {
        set_piece_by_label(&mut state, label, 1);
    }
    for label in ["g7", "g4"] {
        set_piece_by_label(&mut state, label, 2);
    }
    state.recompute_aux(options);
    state.set_side_to_move(0);
    state.set_pending_removal(0, 1);
    rules.encode_state(state)
}

#[cfg(feature = "cpp-oracle")]
struct OracleCase {
    name: &'static str,
    labels: &'static [&'static str],
    expected_eval: Option<(i32, i32)>,
}

#[cfg(feature = "cpp-oracle")]
struct ParityCase {
    name: &'static str,
    labels: &'static [&'static str],
}

#[test]
fn perfect_query_snapshot_preserves_counts_and_removal() {
    let rules = MillRules::default();
    let options = MillVariantOptions::default();
    let query = PerfectQuery::new(
        perfect_bits(&["a4", "a7", "d7"]),
        perfect_bits(&["g7", "g4"]),
        5,
        6,
        0,
        true,
    );
    let snap = snapshot_from_perfect_query(&rules, &options, query);
    let state = MillRules::decode_snapshot(snap);
    let topo = default_mill_topology();

    for label in ["a4", "a7", "d7"] {
        let node = topo.node_from_label(label).unwrap();
        assert_eq!(state.board()[node as usize], 1, "{label} must be white");
    }
    for label in ["g7", "g4"] {
        let node = topo.node_from_label(label).unwrap();
        assert_eq!(state.board()[node as usize], 2, "{label} must be black");
    }
    assert_eq!(state.pieces_in_hand(), [5, 6]);
    assert_eq!(state.pending_removals(), [1, 0]);
}

#[cfg(feature = "cpp-oracle")]
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
        assert_eq!(
            evaluate_state_outcome_with_database(&mut rust_db, &state, &options, side as i8)
                .unwrap()
                .map(PerfectOutcome::to_wdl_steps),
            case.expected_eval,
            "{} structured outcome must match the tuple API",
            case.name
        );
        let token = best_move_token_for_state(&state, &options, side as i8)
            .unwrap_or_else(|| panic!("{} must return a best move token", case.name));
        assert_best_move_is_legal(&rules, &snap, &token);

        let rust_choice = best_move_choice_with_database(&mut rust_db, &rules, &snap, &options)
            .unwrap()
            .unwrap_or_else(|| panic!("{} must return a Rust best move choice", case.name));
        assert_best_move_is_legal(&rules, &snap, &rust_choice.token);
        assert_eq!(
            best_move_token_with_database(&mut rust_db, &rules, &snap, &options).unwrap(),
            Some(rust_choice.token),
            "{} token wrapper must match structured choice",
            case.name
        );
        assert!(
            rust_choice.outcome.default_rank() >= 0,
            "{} stable vectors should not choose a losing Rust move",
            case.name
        );
    }

    let parity_cases = [
        ParityCase {
            name: "after_a4_g7",
            labels: &["a4", "g7"],
        },
        ParityCase {
            name: "after_a4_g7_d7",
            labels: &["a4", "g7", "d7"],
        },
        ParityCase {
            name: "after_a4_g7_d7_a1",
            labels: &["a4", "g7", "d7", "a1"],
        },
        ParityCase {
            name: "after_a4_g7_d7_a1_g1",
            labels: &["a4", "g7", "d7", "a1", "g1"],
        },
        ParityCase {
            name: "after_a4_g7_d7_a1_g1_d1",
            labels: &["a4", "g7", "d7", "a1", "g1", "d1"],
        },
        ParityCase {
            name: "after_a4_g7_d7_a1_g1_d1_b6",
            labels: &["a4", "g7", "d7", "a1", "g1", "d1", "b6"],
        },
        ParityCase {
            name: "after_a4_g7_d7_a1_g1_d1_b6_f6",
            labels: &["a4", "g7", "d7", "a1", "g1", "d1", "b6", "f6"],
        },
    ];

    for case in parity_cases {
        let snap = apply_sequence(&rules, case.labels);
        let state = MillRules::decode_snapshot(snap);
        let side = case.labels.len() % 2;
        let cpp_eval = evaluate_state_for(&state, &options, side as i8);
        let rust_eval =
            evaluate_state_with_database(&mut rust_db, &state, &options, side as i8).unwrap();
        assert!(
            cpp_eval.is_some(),
            "{} must be covered by the bundled C++ perfect DB assets",
            case.name
        );
        assert_eq!(
            rust_eval, cpp_eval,
            "{} must match between C++ oracle and Rust loader",
            case.name
        );
    }

    // Do not call deinit here: the current C++ bridge has fragile sector-hash
    // shutdown behavior. The Rust rewrite should make shutdown deterministic,
    // but these oracle vectors only need process-lifetime resources.
}

#[test]
fn rust_best_move_expands_removal_continuations() {
    let rules = MillRules::default();
    let options = MillVariantOptions::default();
    let snap = pending_removal_snapshot(&rules, &options);
    let mut rust_db = Database::open(FileDatabaseProvider::new(db_path())).unwrap();

    let choice = best_move_choice_with_database(&mut rust_db, &rules, &snap, &options)
        .unwrap()
        .expect("pending removal state must produce a Rust best move choice");

    assert!(
        choice.token.starts_with('x'),
        "pending removal best move must be a removal token, got {}",
        choice.token
    );
    assert_best_move_is_legal(&rules, &snap, &choice.token);
    assert_eq!(
        best_move_token_with_database(&mut rust_db, &rules, &snap, &options).unwrap(),
        Some(choice.token),
        "pending removal token wrapper must match structured choice"
    );
}

#[test]
fn rust_process_global_database_evaluates_state() {
    deinit_rust_database();
    assert!(!is_rust_database_initialized());
    init_rust_database(db_path()).unwrap();
    assert!(is_rust_database_initialized());
    assert!(
        init(db_path()),
        "pd_init_std must succeed for bitboard parity checks"
    );

    let rules = MillRules::default();
    let options = MillVariantOptions::default();
    let snap = rules.initial_state(&[]);
    let state = MillRules::decode_snapshot(snap);

    assert_eq!(
        evaluate_state_for_rust_database(&state, &options, 0).unwrap(),
        Some((0, 2))
    );
    assert_eq!(
        evaluate_rust_database(0, 0, 9, 9, 0, false).unwrap(),
        evaluate(0, 0, 9, 9, 0, false)
    );
    assert_eq!(
        evaluate_rust_database(1, 0, 8, 9, 1, false).unwrap(),
        evaluate(1, 0, 8, 9, 1, false)
    );
    let choice = best_move_choice_for_rust_database(&rules, &snap, &options)
        .unwrap()
        .expect("global Rust DB must return an opening choice");
    assert_best_move_is_legal(&rules, &snap, &choice.token);
    assert_eq!(
        best_move_choice_rust_database(0, 0, 9, 9, 0, false)
            .unwrap()
            .map(|choice| choice.token),
        best_move_token_rust_database(0, 0, 9, 9, 0, false).unwrap(),
        "bitboard choice and token wrappers must match"
    );
    let opening_token = best_move_token_rust_database(0, 0, 9, 9, 0, false)
        .unwrap()
        .expect("bitboard Rust DB must return an opening move");
    assert_best_move_is_legal(&rules, &snap, &opening_token);

    let after_a4 = apply_sequence(&rules, &["a4"]);
    let after_a4_token = best_move_token_rust_database(perfect_bits(&["a4"]), 0, 8, 9, 1, false)
        .unwrap()
        .expect("bitboard Rust DB must return a move after a4");
    assert_best_move_is_legal(&rules, &after_a4, &after_a4_token);

    let removal_snap = pending_removal_snapshot(&rules, &options);
    let removal_token = best_move_token_rust_database(
        perfect_bits(&["a4", "a7", "d7"]),
        perfect_bits(&["g7", "g4"]),
        6,
        7,
        0,
        true,
    )
    .unwrap()
    .expect("bitboard Rust DB must return a pending-removal move");
    assert!(
        removal_token.starts_with('x'),
        "pending-removal token must be a removal, got {removal_token}"
    );
    assert_best_move_is_legal(&rules, &removal_snap, &removal_token);

    deinit_rust_database();
    assert!(!is_rust_database_initialized());
    assert_eq!(
        evaluate_state_for_rust_database(&state, &options, 0).unwrap(),
        None
    );
}
