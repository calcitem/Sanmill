// SPDX-License-Identifier: GPL-3.0-or-later

#[cfg(feature = "cpp-oracle")]
use perfect_db::database::PerfectOutcome;
use perfect_db::database::{
    Database, DatabaseError, DatabaseOptions, DatabaseVariant, FileDatabaseProvider,
    MemoryDatabaseProvider, PerfectQuery,
};
use perfect_db::file_format::SectorId;
use perfect_db::{
    best_move_choice_for_rust_database, best_move_choice_rust_database,
    best_move_choice_with_database, best_move_choices_with_database, best_move_token_rust_database,
    best_move_token_with_database, deinit_rust_database, evaluate, evaluate_rust_database,
    evaluate_state_for_rust_database, evaluate_state_with_database, init, init_rust_database,
    init_rust_database_from_provider, init_rust_database_from_provider_with_options,
    is_rust_database_initialized, loaded_sector_count_rust_database, loaded_variant_rust_database,
    snapshot_from_perfect_query,
};
#[cfg(feature = "cpp-oracle")]
use perfect_db::{
    best_move_token, best_move_token_for_state, evaluate_state_for,
    evaluate_state_outcome_with_database,
};
use std::collections::{BTreeMap, BTreeSet};
#[cfg(feature = "cpp-oracle")]
use std::sync::{LazyLock, Mutex, MutexGuard};
use tgf_core::{ActionList, BoardTopology, GameRules, GameStateSnapshot};
use tgf_mill::notation::MillUciCodec;
#[cfg(feature = "cpp-oracle")]
use tgf_mill::rules::MillState;
use tgf_mill::{MillPhase, MillRules, MillVariantOptions, default_mill_topology};

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

fn memory_provider_for(names: &[&str]) -> MemoryDatabaseProvider {
    let files = names.iter().map(|name| {
        let path = format!("{}/{}", db_path(), name);
        let bytes =
            std::fs::read(&path).unwrap_or_else(|err| panic!("failed to read {path}: {err}"));
        ((*name).to_owned(), bytes)
    });
    MemoryDatabaseProvider::from_files(files)
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

fn endgame_moving_snapshot(
    rules: &MillRules,
    options: &MillVariantOptions,
    white: &[&str],
    black: &[&str],
) -> GameStateSnapshot {
    let mut state = rules.setup_empty();
    for label in white {
        set_piece_by_label(&mut state, label, 1);
    }
    for label in black {
        set_piece_by_label(&mut state, label, 2);
    }
    state.recompute_aux(options);
    state.set_pieces_in_hand([0, 0], options);
    state.set_phase(MillPhase::Moving);
    state.set_side_to_move(0);
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

#[cfg(feature = "cpp-oracle")]
fn cpp_oracle_test_lock() -> MutexGuard<'static, ()> {
    static LOCK: LazyLock<Mutex<()>> = LazyLock::new(|| Mutex::new(()));
    LOCK.lock()
        .expect("C++ Perfect DB oracle test lock must not be poisoned")
}

#[cfg(feature = "cpp-oracle")]
fn assert_state_eval_parity(
    name: &str,
    rust_db: &mut Database<FileDatabaseProvider>,
    state: &MillState,
    options: &MillVariantOptions,
    side_to_move: i8,
) {
    let cpp_eval = evaluate_state_for(state, options, side_to_move);
    let rust_eval = evaluate_state_with_database(rust_db, state, options, side_to_move).unwrap();
    assert!(
        cpp_eval.is_some(),
        "{name} must be covered by the bundled C++ perfect DB assets"
    );
    assert_eq!(
        rust_eval, cpp_eval,
        "{name} must match between C++ oracle and Rust loader"
    );
}

#[cfg(feature = "cpp-oracle")]
fn assert_state_eval_option_parity(
    name: &str,
    rust_db: &mut Database<FileDatabaseProvider>,
    state: &MillState,
    options: &MillVariantOptions,
    side_to_move: i8,
) {
    let cpp_eval = evaluate_state_for(state, options, side_to_move);
    let rust_eval = evaluate_state_with_database(rust_db, state, options, side_to_move).unwrap();
    assert_eq!(
        rust_eval, cpp_eval,
        "{name} must match between C++ oracle and Rust loader"
    );
}

fn next_walk_index(seed: &mut u64, len: usize) -> usize {
    assert!(len > 0, "legal action list must not be empty");
    *seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1);
    ((*seed >> 32) as usize) % len
}

fn bundled_sector_ids() -> Vec<SectorId> {
    bundled_sector_ids_for("std")
}

fn bundled_sector_ids_for(prefix: &str) -> Vec<SectorId> {
    let mut ids = std::fs::read_dir(db_path())
        .expect("database asset directory must be readable")
        .map(|entry| entry.expect("database asset directory entry must be readable"))
        .filter_map(|entry| {
            let name = entry.file_name();
            parse_sector_name(
                prefix,
                name.to_str().expect("database asset name must be UTF-8"),
            )
        })
        .collect::<Vec<_>>();
    ids.sort_unstable();
    ids
}

fn parse_sector_name(prefix: &str, name: &str) -> Option<SectorId> {
    let stem = name
        .strip_prefix(prefix)?
        .strip_prefix('_')?
        .strip_suffix(".sec2")?;
    let parts = stem
        .split('_')
        .map(|part| part.parse::<u8>().ok())
        .collect::<Option<Vec<_>>>()?;
    assert_eq!(
        parts.len(),
        4,
        "std sector file names must contain four numeric fields"
    );
    Some(SectorId::new(parts[0], parts[1], parts[2], parts[3]))
}

fn sector_id_for_snapshot(snap: &GameStateSnapshot) -> Option<SectorId> {
    if snap.side_to_move != 0 && snap.side_to_move != 1 {
        return None;
    }
    let state = MillRules::decode_snapshot(*snap);
    if state.pending_removals().iter().any(|&count| count > 0) {
        return None;
    }

    let white_on_board = state.board().iter().filter(|&&owner| owner == 1).count() as u8;
    let black_on_board = state.board().iter().filter(|&&owner| owner == 2).count() as u8;
    let in_hand = state.pieces_in_hand();
    if snap.side_to_move == 0 {
        Some(SectorId::new(
            white_on_board,
            black_on_board,
            in_hand[0],
            in_hand[1],
        ))
    } else {
        Some(SectorId::new(
            black_on_board,
            white_on_board,
            in_hand[1],
            in_hand[0],
        ))
    }
}

fn record_sector_sample(
    samples: &mut BTreeMap<SectorId, GameStateSnapshot>,
    bundled: &BTreeSet<SectorId>,
    snap: GameStateSnapshot,
) {
    let Some(id) = sector_id_for_snapshot(&snap) else {
        return;
    };
    if bundled.contains(&id) {
        samples.entry(id).or_insert(snap);
    }
}

fn legal_sector_samples(
    rules: &MillRules,
    options: &MillVariantOptions,
) -> BTreeMap<SectorId, GameStateSnapshot> {
    let bundled = bundled_sector_ids().into_iter().collect::<BTreeSet<_>>();
    legal_sector_samples_for(rules, options, &bundled)
}

fn legal_sector_samples_for(
    rules: &MillRules,
    options: &MillVariantOptions,
    bundled: &BTreeSet<SectorId>,
) -> BTreeMap<SectorId, GameStateSnapshot> {
    let mut samples = BTreeMap::new();

    record_sector_sample(&mut samples, bundled, rules.initial_state(&[]));
    let no_capture_line = ["a4", "g7", "d7", "a1", "g1", "d1", "b6", "f6"];
    let mut snap = rules.initial_state(&[]);
    for label in no_capture_line {
        let action = MillUciCodec::decode_action(&snap, label)
            .unwrap_or_else(|| panic!("failed to decode action {label}"));
        let mut legal = ActionList::<256>::default();
        rules.legal_actions(&snap, &mut legal);
        if !legal.as_slice().contains(&action) {
            break;
        }
        snap = rules.apply(&snap, action);
        record_sector_sample(&mut samples, bundled, snap);
    }

    for (white, black) in [
        (&["a4", "d7", "g1"][..], &["g7", "d1", "b4"][..]),
        (&["a4", "d7", "g1"][..], &["g7", "d1", "b4", "c5"][..]),
        (&["a4", "d7", "g1", "c5"][..], &["g7", "d1", "b4"][..]),
    ] {
        record_sector_sample(
            &mut samples,
            bundled,
            endgame_moving_snapshot(rules, options, white, black),
        );
    }

    let mut seed = 0x51de_cafe_f00d_u64;
    for _ in 0..4096 {
        let mut snap = rules.initial_state(&[]);
        for _ in 0..18 {
            if samples.len() == bundled.len() {
                return samples;
            }
            let mut legal = ActionList::<256>::default();
            rules.legal_actions(&snap, &mut legal);
            if legal.is_empty() {
                break;
            }
            let idx = next_walk_index(&mut seed, legal.as_slice().len());
            snap = rules.apply(&snap, legal.as_slice()[idx]);
            record_sector_sample(&mut samples, bundled, snap);
        }
    }

    samples
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct FrozenSectorOracle {
    sector: (u8, u8, u8, u8),
    expected: (i32, i32),
}

impl FrozenSectorOracle {
    fn sector_id(self) -> SectorId {
        let (white_on_board, black_on_board, white_in_hand, black_in_hand) = self.sector;
        SectorId::new(white_on_board, black_on_board, white_in_hand, black_in_hand)
    }
}

const FROZEN_LEGAL_SECTOR_ORACLE: &[FrozenSectorOracle] = &[
    FrozenSectorOracle {
        sector: (0, 0, 9, 9),
        expected: (0, 2),
    },
    FrozenSectorOracle {
        sector: (0, 1, 9, 8),
        expected: (0, 1),
    },
    FrozenSectorOracle {
        sector: (1, 1, 8, 8),
        expected: (0, 4),
    },
    FrozenSectorOracle {
        sector: (1, 2, 8, 7),
        expected: (0, 1),
    },
    FrozenSectorOracle {
        sector: (1, 3, 7, 6),
        expected: (0, 31),
    },
    FrozenSectorOracle {
        sector: (2, 2, 7, 7),
        expected: (0, 6),
    },
    FrozenSectorOracle {
        sector: (2, 3, 6, 6),
        expected: (-1, 12),
    },
    FrozenSectorOracle {
        sector: (2, 3, 7, 6),
        expected: (0, 1),
    },
    FrozenSectorOracle {
        sector: (2, 4, 6, 5),
        expected: (0, 29),
    },
    FrozenSectorOracle {
        sector: (3, 3, 0, 0),
        expected: (1, 13),
    },
    FrozenSectorOracle {
        sector: (3, 3, 5, 5),
        expected: (-1, 38),
    },
    FrozenSectorOracle {
        sector: (3, 3, 6, 5),
        expected: (1, 55),
    },
    FrozenSectorOracle {
        sector: (3, 3, 6, 6),
        expected: (1, 53),
    },
    FrozenSectorOracle {
        sector: (3, 4, 0, 0),
        expected: (-1, -1),
    },
    FrozenSectorOracle {
        sector: (3, 4, 5, 5),
        expected: (-1, 16),
    },
    FrozenSectorOracle {
        sector: (3, 4, 6, 5),
        expected: (-1, -5),
    },
    FrozenSectorOracle {
        sector: (4, 3, 0, 0),
        expected: (-1, -1),
    },
    FrozenSectorOracle {
        sector: (4, 3, 5, 5),
        expected: (0, 30),
    },
    FrozenSectorOracle {
        sector: (4, 4, 5, 5),
        expected: (1, 33),
    },
];

const FROZEN_MORABARABA_LEGAL_SECTOR_ORACLE: &[FrozenSectorOracle] = &[
    FrozenSectorOracle {
        sector: (0, 0, 12, 12),
        expected: (1, 49),
    },
    FrozenSectorOracle {
        sector: (0, 1, 12, 11),
        expected: (0, 5),
    },
    FrozenSectorOracle {
        sector: (1, 1, 11, 11),
        expected: (1, 49),
    },
    FrozenSectorOracle {
        sector: (1, 2, 11, 10),
        expected: (1, 43),
    },
    FrozenSectorOracle {
        sector: (1, 3, 10, 9),
        expected: (-1, 36),
    },
    FrozenSectorOracle {
        sector: (2, 2, 10, 10),
        expected: (-1, 54),
    },
];

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

#[test]
fn rust_database_matches_frozen_legal_sector_oracle_samples() {
    let rules = MillRules::default();
    let options = MillVariantOptions::default();
    let mut rust_db = Database::open(FileDatabaseProvider::new(db_path())).unwrap();
    let samples = legal_sector_samples(&rules, &options);

    assert_eq!(
        samples.len(),
        FROZEN_LEGAL_SECTOR_ORACLE.len(),
        "frozen oracle samples must cover every currently bundled std sector"
    );

    for case in FROZEN_LEGAL_SECTOR_ORACLE {
        let id = case.sector_id();
        let snap = *samples
            .get(&id)
            .unwrap_or_else(|| panic!("missing legal sample for frozen sector {id:?}"));
        let state = MillRules::decode_snapshot(snap);
        let eval = evaluate_state_with_database(&mut rust_db, &state, &options, snap.side_to_move)
            .unwrap();
        assert_eq!(
            eval,
            Some(case.expected),
            "sector {id:?} must match the frozen C++ oracle sample"
        );
    }
}

#[cfg(feature = "cpp-oracle")]
#[test]
fn std_perfect_db_oracle_matches_legal_walk_samples() {
    let _guard = cpp_oracle_test_lock();
    perfect_db::set_rust_backend_enabled(false);
    assert!(
        init(db_path()),
        "pd_init_std must succeed with bundled assets"
    );

    let rules = MillRules::default();
    let options = MillVariantOptions::default();
    let mut rust_db = Database::open(FileDatabaseProvider::new(db_path())).unwrap();
    let mut seed = 0x05ee_d9db_u64;

    for walk in 0..8 {
        let mut snap = rules.initial_state(&[]);
        for ply in 0..=8 {
            let state = MillRules::decode_snapshot(snap);
            assert_state_eval_option_parity(
                &format!("walk_{walk}_ply_{ply}"),
                &mut rust_db,
                &state,
                &options,
                snap.side_to_move,
            );
            if ply == 8 {
                break;
            }

            let mut legal = ActionList::<256>::default();
            rules.legal_actions(&snap, &mut legal);
            let idx = next_walk_index(&mut seed, legal.as_slice().len());
            snap = rules.apply(&snap, legal.as_slice()[idx]);
        }
    }

    perfect_db::set_rust_backend_enabled(true);
}

#[cfg(feature = "cpp-oracle")]
#[test]
fn std_perfect_db_oracle_vectors() {
    let _guard = cpp_oracle_test_lock();
    perfect_db::set_rust_backend_enabled(false);
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
        assert_state_eval_parity(case.name, &mut rust_db, &state, &options, side as i8);
    }

    let endgame_cases = [
        (
            "endgame_3_3",
            &["a4", "d7", "g1"][..],
            &["g7", "d1", "b4"][..],
        ),
        (
            "endgame_3_4",
            &["a4", "d7", "g1"][..],
            &["g7", "d1", "b4", "c5"][..],
        ),
        (
            "endgame_4_3",
            &["a4", "d7", "g1", "c5"][..],
            &["g7", "d1", "b4"][..],
        ),
    ];
    for (name, white, black) in endgame_cases {
        let snap = endgame_moving_snapshot(&rules, &options, white, black);
        let state = MillRules::decode_snapshot(snap);
        assert_state_eval_parity(name, &mut rust_db, &state, &options, snap.side_to_move);
    }

    // Do not call deinit here: the current C++ bridge has fragile sector-hash
    // shutdown behavior. The Rust rewrite should make shutdown deterministic,
    // but these oracle vectors only need process-lifetime resources.
    perfect_db::set_rust_backend_enabled(true);
}

#[cfg(feature = "cpp-oracle")]
#[test]
fn morabaraba_perfect_db_oracle_vectors() {
    let _guard = cpp_oracle_test_lock();
    perfect_db::set_rust_backend_enabled(false);
    assert!(
        perfect_db::init_variant(db_path(), DatabaseVariant::MORABARABA),
        "C++ oracle must initialize the bundled Morabaraba assets"
    );

    let options = MillVariantOptions {
        piece_count: 12,
        has_diagonal_lines: true,
        ..MillVariantOptions::default()
    };
    let rules = MillRules::new(options.clone());
    let snap = rules.initial_state(&[]);
    let state = MillRules::decode_snapshot(snap);
    let mut rust_db = Database::open_variant(
        FileDatabaseProvider::new(db_path()),
        DatabaseVariant::MORABARABA,
    )
    .unwrap();

    let sector_ids = bundled_sector_ids_for("mora")
        .into_iter()
        .collect::<BTreeSet<_>>();
    let samples = legal_sector_samples_for(&rules, &options, &sector_ids);
    assert_eq!(
        sector_ids.len(),
        6,
        "test must cover every currently bundled Morabaraba sector asset"
    );
    assert_eq!(
        samples.keys().copied().collect::<BTreeSet<_>>(),
        sector_ids,
        "legal sample generation must reach every bundled Morabaraba sector"
    );
    for (id, sample_snap) in samples {
        let sample_state = MillRules::decode_snapshot(sample_snap);
        let name = format!("Morabaraba sector {id:?}");
        assert_state_eval_parity(
            &name,
            &mut rust_db,
            &sample_state,
            &options,
            sample_snap.side_to_move,
        );
    }

    let token = best_move_token_for_state(&state, &options, snap.side_to_move)
        .expect("Morabaraba C++ oracle must return an opening best move");
    assert_best_move_is_legal(&rules, &snap, &token);

    let choices = best_move_choices_with_database(&mut rust_db, &rules, &snap, &options)
        .unwrap()
        .expect("Rust Morabaraba loader must expose opening best choices");
    let optimal_tokens: BTreeSet<&str> =
        choices.iter().map(|choice| choice.token.as_str()).collect();
    assert!(
        optimal_tokens.contains(token.as_str()),
        "Morabaraba C++ state best move {token} must be Rust-optimal"
    );

    let raw_token = perfect_db::best_move_token_with_options(
        &PerfectQuery::new(0, 0, 12, 12, 0, false),
        &options,
        perfect_db::PerfectMoveOrdering::LegacyWdl,
    )
    .expect("raw Morabaraba C++ oracle must return an opening best move");
    assert_best_move_is_legal(&rules, &snap, &raw_token);
    assert!(
        optimal_tokens.contains(raw_token.as_str()),
        "raw Morabaraba best move {raw_token} must be Rust-optimal"
    );

    perfect_db::set_rust_backend_enabled(true);
}

#[cfg(feature = "cpp-oracle")]
#[test]
fn std_perfect_db_oracle_matches_legal_bundled_sector_samples() {
    let _guard = cpp_oracle_test_lock();
    perfect_db::set_rust_backend_enabled(false);
    assert!(
        init(db_path()),
        "pd_init_std must succeed with bundled assets"
    );

    let rules = MillRules::default();
    let options = MillVariantOptions::default();
    let mut rust_db = Database::open(FileDatabaseProvider::new(db_path())).unwrap();
    let sector_ids = bundled_sector_ids().into_iter().collect::<BTreeSet<_>>();
    let samples = legal_sector_samples(&rules, &options);
    assert_eq!(
        sector_ids.len(),
        19,
        "test must cover every currently bundled std sector asset"
    );
    assert_eq!(
        samples.keys().copied().collect::<BTreeSet<_>>(),
        sector_ids,
        "legal sample generation must reach every bundled std sector"
    );

    for (id, snap) in samples {
        let state = MillRules::decode_snapshot(snap);
        let cpp_eval = evaluate_state_for(&state, &options, snap.side_to_move);
        let rust_eval =
            evaluate_state_with_database(&mut rust_db, &state, &options, snap.side_to_move)
                .unwrap();
        assert_eq!(
            rust_eval, cpp_eval,
            "sector {id:?} legal sample must match the C++ oracle"
        );
    }

    perfect_db::set_rust_backend_enabled(true);
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
fn rust_database_returns_all_opening_optimal_choices() {
    let rules = MillRules::default();
    let options = MillVariantOptions::default();
    let snap = rules.initial_state(&[]);
    let mut rust_db = Database::open(FileDatabaseProvider::new(db_path())).unwrap();

    let choices = best_move_choices_with_database(&mut rust_db, &rules, &snap, &options)
        .unwrap()
        .expect("opening position must produce Rust best move choices");
    let single_choice = best_move_choice_with_database(&mut rust_db, &rules, &snap, &options)
        .unwrap()
        .expect("opening position must produce a Rust best move choice");

    assert_eq!(choices.len(), 24);
    assert_eq!(choices[0], single_choice);
    for choice in &choices {
        assert_best_move_is_legal(&rules, &snap, &choice.token);
        assert_eq!(choice.outcome, choices[0].outcome);
    }
}

#[test]
fn rust_database_reports_missing_moving_phase_sector() {
    let rules = MillRules::default();
    let options = MillVariantOptions::default();
    let snap = rules.no_mill_moving_phase_snapshot();
    let state = MillRules::decode_snapshot(snap);
    let mut rust_db = Database::open(FileDatabaseProvider::new(db_path())).unwrap();

    let err = evaluate_state_with_database(&mut rust_db, &state, &options, snap.side_to_move)
        .expect_err("current bundled assets do not include moving-phase sectors");
    match err {
        DatabaseError::Read { name, source } => {
            assert!(
                name.ends_with("std_9_9_0_0.sec2"),
                "unexpected missing sector: {name}"
            );
            assert_eq!(source.kind(), std::io::ErrorKind::NotFound);
        }
        other => panic!("expected missing moving-phase sector, got {other}"),
    }
    assert_eq!(
        best_move_choice_with_database(&mut rust_db, &rules, &snap, &options).unwrap(),
        None,
        "partial database coverage must not choose a best move"
    );
    assert_eq!(
        best_move_token_with_database(&mut rust_db, &rules, &snap, &options).unwrap(),
        None,
        "token wrapper must preserve missing-sector fallback semantics"
    );
}

#[test]
fn rust_database_handles_endgame_moving_phase_sectors() {
    let rules = MillRules::default();
    let options = MillVariantOptions::default();
    let mut rust_db = Database::open(FileDatabaseProvider::new(db_path())).unwrap();
    let cases = [
        (
            "std_3_3_0_0",
            &["a4", "d7", "g1"][..],
            &["g7", "d1", "b4"][..],
        ),
        (
            "std_3_4_0_0",
            &["a4", "d7", "g1"][..],
            &["g7", "d1", "b4", "c5"][..],
        ),
        (
            "std_4_3_0_0",
            &["a4", "d7", "g1", "c5"][..],
            &["g7", "d1", "b4"][..],
        ),
    ];

    for (name, white, black) in cases {
        let snap = endgame_moving_snapshot(&rules, &options, white, black);
        let state = MillRules::decode_snapshot(snap);
        assert!(
            evaluate_state_with_database(&mut rust_db, &state, &options, snap.side_to_move)
                .unwrap()
                .is_some(),
            "{name} must have a Rust database evaluation"
        );

        let choice = best_move_choice_with_database(&mut rust_db, &rules, &snap, &options)
            .unwrap()
            .unwrap_or_else(|| panic!("{name} must produce a Rust best move choice"));
        assert!(
            choice.token.contains('-'),
            "{name} best move must be a moving token, got {}",
            choice.token
        );
        assert_best_move_is_legal(&rules, &snap, &choice.token);

        let token = choice.token.clone();
        assert_eq!(
            best_move_token_with_database(&mut rust_db, &rules, &snap, &options).unwrap(),
            Some(token),
            "{name} token wrapper must match structured choice"
        );
    }
}

#[test]
fn memory_provider_handles_endgame_moving_phase_sector() {
    let rules = MillRules::default();
    let options = MillVariantOptions::default();
    let snap = endgame_moving_snapshot(&rules, &options, &["a4", "d7", "g1"], &["g7", "d1", "b4"]);
    let state = MillRules::decode_snapshot(snap);
    let mut rust_db =
        Database::open(memory_provider_for(&["std.secval", "std_3_3_0_0.sec2"])).unwrap();

    assert!(
        evaluate_state_with_database(&mut rust_db, &state, &options, snap.side_to_move)
            .unwrap()
            .is_some(),
        "memory-backed endgame sector must have a Rust database evaluation"
    );
}

#[test]
fn morabaraba_database_handles_bundled_sectors() {
    let options = MillVariantOptions {
        piece_count: 12,
        has_diagonal_lines: true,
        ..MillVariantOptions::default()
    };
    let rules = MillRules::new(options.clone());
    let mut rust_db = Database::open_variant(
        FileDatabaseProvider::new(db_path()),
        DatabaseVariant::MORABARABA,
    )
    .unwrap();

    assert_eq!(rust_db.variant(), DatabaseVariant::MORABARABA);

    let sector_ids = bundled_sector_ids_for("mora")
        .into_iter()
        .collect::<BTreeSet<_>>();
    let samples = legal_sector_samples_for(&rules, &options, &sector_ids);
    let frozen_sector_ids = FROZEN_MORABARABA_LEGAL_SECTOR_ORACLE
        .iter()
        .map(|case| case.sector_id())
        .collect::<BTreeSet<_>>();
    assert_eq!(
        sector_ids, frozen_sector_ids,
        "frozen oracle samples must cover every currently bundled Morabaraba sector"
    );
    assert_eq!(
        samples.keys().copied().collect::<BTreeSet<_>>(),
        sector_ids,
        "legal sample generation must reach every bundled Morabaraba sector"
    );

    for case in FROZEN_MORABARABA_LEGAL_SECTOR_ORACLE {
        let id = case.sector_id();
        let snap = *samples
            .get(&id)
            .unwrap_or_else(|| panic!("missing legal sample for frozen Morabaraba sector {id:?}"));
        let state = MillRules::decode_snapshot(snap);
        let eval = evaluate_state_with_database(&mut rust_db, &state, &options, snap.side_to_move)
            .unwrap();
        assert_eq!(
            eval,
            Some(case.expected),
            "Morabaraba sector {id:?} must match the frozen C++ oracle sample"
        );
    }

    let snap = rules.initial_state(&[]);
    let choice = best_move_choice_with_database(&mut rust_db, &rules, &snap, &options)
        .unwrap()
        .expect("Morabaraba opening must produce a Rust best move choice");
    assert_best_move_is_legal(&rules, &snap, &choice.token);
}

#[test]
fn rust_database_rejects_variant_mismatched_state_queries() {
    let options = MillVariantOptions {
        piece_count: 10,
        ..MillVariantOptions::default()
    };
    let rules = MillRules::new(options.clone());
    let snap = rules.initial_state(&[]);
    let state = MillRules::decode_snapshot(snap);
    let mut rust_db = Database::open(FileDatabaseProvider::new(db_path())).unwrap();

    assert_eq!(
        evaluate_state_with_database(&mut rust_db, &state, &options, snap.side_to_move).unwrap(),
        None,
        "state evaluation must not query a database for a different variant"
    );
    assert_eq!(
        best_move_choice_with_database(&mut rust_db, &rules, &snap, &options).unwrap(),
        None,
        "best move selection must not query a database for a different variant"
    );
}

#[test]
fn rust_process_global_database_evaluates_state() {
    #[cfg(feature = "cpp-oracle")]
    let _guard = cpp_oracle_test_lock();

    deinit_rust_database();
    assert!(!is_rust_database_initialized());
    init_rust_database(db_path()).unwrap();
    assert!(is_rust_database_initialized());
    assert_eq!(
        loaded_variant_rust_database(),
        Some(DatabaseVariant::STANDARD)
    );
    #[cfg(feature = "cpp-oracle")]
    perfect_db::set_rust_backend_enabled(false);
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
    #[cfg(feature = "cpp-oracle")]
    perfect_db::set_rust_backend_enabled(true);
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
    assert_eq!(loaded_variant_rust_database(), None);
    assert_eq!(
        evaluate_state_for_rust_database(&state, &options, 0).unwrap(),
        None
    );

    init_rust_database_from_provider(memory_provider_for(&["std.secval", "std_0_0_9_9.sec2"]))
        .unwrap();
    assert_eq!(
        evaluate_rust_database(0, 0, 9, 9, 0, false).unwrap(),
        Some((0, 2))
    );
    assert_eq!(loaded_sector_count_rust_database(), Some(1));
    deinit_rust_database();

    init_rust_database_from_provider_with_options(
        memory_provider_for(&["std.secval", "std_0_0_9_9.sec2", "std_0_1_9_8.sec2"]),
        DatabaseOptions::with_sector_cache_capacity(1),
    )
    .unwrap();
    assert_eq!(loaded_sector_count_rust_database(), Some(0));
    assert_eq!(
        evaluate_rust_database(0, 0, 9, 9, 0, false).unwrap(),
        Some((0, 2))
    );
    assert_eq!(loaded_sector_count_rust_database(), Some(1));
    assert_eq!(
        evaluate_rust_database(perfect_bits(&["a4"]), 0, 8, 9, 1, false).unwrap(),
        Some((0, 1))
    );
    assert_eq!(loaded_sector_count_rust_database(), Some(1));
    deinit_rust_database();
    assert_eq!(loaded_sector_count_rust_database(), None);
}
