// SPDX-License-Identifier: AGPL-3.0-or-later
// End-to-end tests for the `puzzle-gen` pipeline, using the small Perfect DB
// subset bundled with the Flutter app.

use std::collections::HashSet;

use perfect_db::PerfectMoveChoice;
use perfect_db::database::{
    Database, DatabaseOptions, DatabaseVariant, FileDatabaseProvider, PerfectOutcome, PerfectQuery,
};
use tgf_core::{ActionList, GameRules, OutcomeKind};
use tgf_mill::{
    MillGame, MillPhase, MillRules, MillUciCodec, MillVariantOptions, default_mill_topology,
};

use super::analysis::{canonical_symmetry_key, classify_root_moves};
use super::sampler::sample_root_query;
use super::*;

fn bundled_db_root() -> std::path::PathBuf {
    std::path::Path::new(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../src/ui/flutter_app/assets/databases"
    ))
    .to_path_buf()
}

fn open_bundled_database() -> Database<FileDatabaseProvider> {
    Database::open_variant_with_options(
        FileDatabaseProvider::new(bundled_db_root()),
        DatabaseVariant::STANDARD,
        DatabaseOptions::with_sector_cache_capacity(16),
    )
    .expect("bundled Perfect DB assets must open")
}

fn permissive_test_config() -> GenConfig {
    GenConfig {
        db_path: bundled_db_root().to_string_lossy().into_owned(),
        out_path: "unused.sanmill_puzzles".to_string(),
        count: 1,
        min_depth: 1,
        max_depth: 12,
        side: SideChoice::Random,
        phase: PhaseChoice::Moving,
        // Sectors (3,3,0,0), (3,4,0,0), and (4,3,0,0) are all bundled, so
        // targeting this narrow board-size window keeps the test from
        // depending on the much larger external Perfect DB.
        min_pieces: 3,
        max_pieces: 4,
        max_solutions: 3,
        // The bundled endgame sectors are tiny lopsided wins; disable every
        // challenge filter so the pipeline mechanics stay testable offline.
        min_mistakes: 0,
        max_piece_diff: 99,
        min_solve_depth: 2,
        require_trap: false,
        sacrifice_filter: SacrificeFilter::Include,
        opponent_depth: 4,
        max_attempts: 5000,
        seed: 0xC0FF_EE00_1234_5678,
        cache_capacity: 16,
        author: "Test Author".to_string(),
        rule_variant_id: "standard_9mm",
        pack_id: String::new(),
        pack_name: String::new(),
        pack_description: String::new(),
    }
}

/// Replay every move of every solution from the puzzle's initial position
/// and assert the game genuinely ends in a win for the side to move at the
/// start -- i.e. the JSON this module produced is a real, solvable puzzle
/// and not just internally-consistent bookkeeping.
fn assert_puzzle_is_replayable(rules: &MillRules, info: &PuzzleInfoJson) {
    assert!(!info.solutions.is_empty());
    assert!(info.solutions.len() <= 3);
    assert!(info.solutions.iter().any(|s| s.is_optimal));

    let root_state = rules
        .set_from_fen(&info.initial_position)
        .expect("generated initialPosition must be a valid, re-parseable FEN");
    let root_snap = rules.encode_state(root_state);
    let solver_side = root_snap.side_to_move;

    for solution in &info.solutions {
        let mut snap = root_snap;
        assert!(!solution.moves.is_empty());
        for mv in &solution.moves {
            let mover = snap.side_to_move;
            let expected_side = if mover == 0 { "white" } else { "black" };
            assert_eq!(
                mv.side, expected_side,
                "recorded side must match the actual side to move for `{}`",
                mv.notation
            );

            let mut legal = ActionList::<256>::new();
            rules.legal_actions(&snap, &mut legal);
            let action = legal
                .as_slice()
                .iter()
                .copied()
                .find(|&a| MillUciCodec::encode_action(a) == mv.notation)
                .unwrap_or_else(|| {
                    panic!(
                        "solution move `{}` must be legal from the position it is played in",
                        mv.notation
                    )
                });
            snap = rules.apply(&snap, action);
        }

        assert_eq!(
            rules.outcome(&snap).kind,
            OutcomeKind::Win(solver_side),
            "replaying a full solution line must end in a win for the solving side"
        );
    }
}

#[test]
fn puzzle_gen_produces_a_genuinely_solvable_puzzle_from_the_bundled_db() {
    let options = MillVariantOptions::default();
    let rules = MillRules::new(options.clone());
    let game = MillGame::new(options.clone());
    let mut database = open_bundled_database();
    let cfg = permissive_test_config();
    let generated_at = "2026-01-01T00:00:00.000Z";

    let env = GenEnv {
        rules: &rules,
        game: &game,
        options: &options,
        cfg: &cfg,
    };
    let mut rng = cfg.seed;
    let mut seen_roots: HashSet<u64> = HashSet::new();
    let mut found: Option<PuzzleInfoJson> = None;
    for _ in 0..cfg.max_attempts {
        let spec = SampleSpec {
            phase: cfg.phase,
            side: cfg.side,
            min_pieces: cfg.min_pieces,
            max_pieces: cfg.max_pieces,
        };
        let query = sample_root_query(&mut rng, &spec, &options);
        if let Some(info) = try_build_puzzle(
            &mut database,
            &env,
            query,
            generated_at,
            &mut rng,
            &mut seen_roots,
        ) {
            found = Some(info);
            break;
        }
    }

    let info = found.expect(
        "the bundled 3-4 piece movement sectors must yield at least one forced-win puzzle \
         within the attempt budget; if this starts failing, the sampler, the outcome \
         enumeration, or the bundled asset set has regressed",
    );
    assert_puzzle_is_replayable(&rules, &info);
    assert_eq!(info.rule_variant_id, "standard_9mm");
    assert!(!info.is_custom);
    assert_eq!(info.version, 1);
    assert!(info.rating.is_some());
    assert!(info.hint.is_some());
    assert!(info.completion_message.is_some());
    assert!(
        info.tags.iter().any(|t| t.starts_with("solve-depth:")),
        "generated puzzles must carry the difficulty-probe tag"
    );
    assert!(
        !seen_roots.is_empty(),
        "an accepted puzzle must register its symmetry-canonical root key"
    );
}

#[test]
fn sacrifice_filter_matches_documented_truth_table() {
    assert!(SacrificeFilter::Include.accepts(true));
    assert!(SacrificeFilter::Include.accepts(false));
    assert!(!SacrificeFilter::Exclude.accepts(true));
    assert!(SacrificeFilter::Exclude.accepts(false));
    assert!(SacrificeFilter::Only.accepts(true));
    assert!(!SacrificeFilter::Only.accepts(false));

    assert_eq!(SacrificeFilter::parse("exclude"), SacrificeFilter::Exclude);
    assert_eq!(SacrificeFilter::parse("only"), SacrificeFilter::Only);
    assert_eq!(SacrificeFilter::parse("include"), SacrificeFilter::Include);
    assert_eq!(SacrificeFilter::parse("anything"), SacrificeFilter::Include);
}

#[test]
fn every_supported_variant_name_resolves_to_a_perfect_db_variant() {
    for name in ["std", "lask", "lasker", "mora", "morabaraba", "unknown"] {
        let (options, rule_variant_id) = variant_options_for(name);
        DatabaseVariant::match_mill_options(&options).unwrap_or_else(|err| {
            panic!("variant `{name}` must resolve to a Perfect DB variant: {err}")
        });
        assert!(!rule_variant_id.is_empty());
    }
}

#[test]
fn solver_material_advantage_is_signed_from_the_movers_perspective() {
    // White to move with 5 pieces against 3: +2 for the solver.
    let query = PerfectQuery::new(0b1_1111, 0b1110_0000_0000, 0, 0, 0, false);
    assert_eq!(solver_material_advantage(&query), 2);
    // Same material, Black to move: the solver is the underdog at -2.
    let query = PerfectQuery::new(0b1_1111, 0b1110_0000_0000, 0, 0, 1, false);
    assert_eq!(solver_material_advantage(&query), -2);
    // Hand pieces count toward the balance.
    let query = PerfectQuery::new(0b0111, 0b0011_0000, 3, 4, 0, false);
    assert_eq!(solver_material_advantage(&query), 0);
}

/// Build a placing-phase snapshot with White on a1+a4 (one placement away
/// from the a1-a4-a7 mill) and Black parked on the far side of the board.
fn placing_snapshot_with_open_mill(
    rules: &MillRules,
    options: &MillVariantOptions,
) -> tgf_core::GameStateSnapshot {
    let topology = default_mill_topology();
    let node_by_label = |label: &str| -> u16 {
        topology
            .nodes()
            .iter()
            .find(|n| n.label == label)
            .unwrap_or_else(|| panic!("topology must contain node `{label}`"))
            .id as u16
    };

    let mut state = rules.setup_empty();
    state.set_piece(node_by_label("a1"), 1);
    state.set_piece(node_by_label("a4"), 1);
    state.set_piece(node_by_label("g7"), 2);
    state.set_piece(node_by_label("f6"), 2);
    state.recompute_aux(options);
    state.set_pieces_in_hand([7, 7], options);
    state.set_side_to_move(0);
    state.set_phase(MillPhase::Placing);
    rules.encode_state(state)
}

#[test]
fn classify_root_moves_flags_the_tempting_mill_trap() {
    let options = MillVariantOptions::default();
    let rules = MillRules::new(options.clone());
    let snap = placing_snapshot_with_open_mill(&rules, &options);

    let mut legal = ActionList::<256>::new();
    rules.legal_actions(&snap, &mut legal);
    let mill_closing_token = "a7";
    assert!(
        legal
            .as_slice()
            .iter()
            .any(|&a| MillUciCodec::encode_action(a) == mill_closing_token),
        "placing at a7 must be legal in the crafted position"
    );

    // Scenario 1: the mill-closing placement loses, everything else wins.
    // That is the book's "the tempting mill fails" motif: the trap flag
    // must fire and the solution must start with a quiet (non-mill) move.
    let outcomes: Vec<PerfectMoveChoice> = legal
        .as_slice()
        .iter()
        .map(|&a| {
            let token = MillUciCodec::encode_action(a);
            let outcome = if token == mill_closing_token {
                PerfectOutcome::Loss { steps: 4 }
            } else {
                PerfectOutcome::Win { steps: 6 }
            };
            PerfectMoveChoice { token, outcome }
        })
        .collect();
    let breakdown = classify_root_moves(&rules, &snap, legal.as_slice(), &outcomes, 0);
    assert_eq!(breakdown.mistake_count, 1);
    assert!(breakdown.tempting_mill_mistake);
    assert!(breakdown.quiet_first_move);
    assert_eq!(breakdown.winning.len(), legal.as_slice().len() - 1);

    // Scenario 2: only the mill-closing placement wins. No trap, and the
    // first move is anything but quiet.
    let outcomes: Vec<PerfectMoveChoice> = legal
        .as_slice()
        .iter()
        .map(|&a| {
            let token = MillUciCodec::encode_action(a);
            let outcome = if token == mill_closing_token {
                PerfectOutcome::Win { steps: 2 }
            } else {
                PerfectOutcome::Loss { steps: 8 }
            };
            PerfectMoveChoice { token, outcome }
        })
        .collect();
    let breakdown = classify_root_moves(&rules, &snap, legal.as_slice(), &outcomes, 0);
    assert_eq!(breakdown.winning.len(), 1);
    assert!(!breakdown.tempting_mill_mistake);
    assert!(!breakdown.quiet_first_move);
    assert_eq!(breakdown.mistake_count, legal.as_slice().len() - 1);
}

#[test]
fn canonical_symmetry_key_is_invariant_under_board_transforms() {
    use perfect_db::index::symmetry::{SYMMETRY_COUNT, transform24};

    let base = PerfectQuery::new(0b1010_0000_0001, 0b0100_0000_0010_0000, 2, 3, 1, false);
    let base_key = canonical_symmetry_key(&base);
    for op in 0..SYMMETRY_COUNT as u8 {
        let transformed = PerfectQuery::new(
            transform24(op, base.white_bits),
            transform24(op, base.black_bits),
            base.white_in_hand,
            base.black_in_hand,
            base.side_to_move,
            false,
        );
        assert_eq!(
            canonical_symmetry_key(&transformed),
            base_key,
            "symmetry op {op} must map to the same canonical key"
        );
    }

    // Changing anything that genuinely distinguishes puzzles must change
    // the key: side to move, hand counts, or the piece arrangement.
    let other_side = PerfectQuery::new(base.white_bits, base.black_bits, 2, 3, 0, false);
    assert_ne!(canonical_symmetry_key(&other_side), base_key);
    let other_hands = PerfectQuery::new(base.white_bits, base.black_bits, 3, 3, 1, false);
    assert_ne!(canonical_symmetry_key(&other_hands), base_key);
}

/// Replay every solution line of the committed built-in puzzle asset and
/// assert each one is legal move-by-move and genuinely ends in a win for
/// the solving side. This guards the shipped `.sanmill_puzzles` file (which
/// is regenerated offline against the full external Perfect DB) against
/// corruption, stale rule changes, or a bad merge.
#[test]
fn committed_built_in_puzzle_asset_replays_to_a_win() {
    let asset_path = std::path::Path::new(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../src/ui/flutter_app/assets/puzzles/malom_perfect_db_puzzles.sanmill_puzzles"
    ));
    let raw = std::fs::read_to_string(asset_path).expect("built-in puzzle asset must exist");
    let package: serde_json::Value =
        serde_json::from_str(&raw).expect("built-in puzzle asset must be valid JSON");

    let puzzles = package["puzzles"]
        .as_array()
        .expect("built-in puzzle asset must contain a puzzles array");
    assert!(!puzzles.is_empty());

    let options = MillVariantOptions::default();
    let rules = MillRules::new(options);
    let mut ids = HashSet::new();
    for puzzle in puzzles {
        let id = puzzle["id"].as_str().expect("puzzle id must be a string");
        assert!(ids.insert(id.to_string()), "duplicate puzzle id `{id}`");
        assert_eq!(puzzle["ruleVariantId"].as_str(), Some("standard_9mm"));

        let fen = puzzle["initialPosition"]
            .as_str()
            .expect("puzzle must carry an initial position FEN");
        let root_state = rules
            .set_from_fen(fen)
            .unwrap_or_else(|err| panic!("puzzle `{id}` FEN must parse ({err}): {fen}"));
        let root_snap = rules.encode_state(root_state);
        let solver_side = root_snap.side_to_move;

        let solutions = puzzle["solutions"]
            .as_array()
            .expect("puzzle must carry solutions");
        assert!(!solutions.is_empty(), "puzzle `{id}` has no solutions");
        for solution in solutions {
            let mut snap = root_snap;
            for mv in solution["moves"].as_array().expect("moves array") {
                let notation = mv["notation"].as_str().expect("move notation");
                let mut legal = ActionList::<256>::new();
                rules.legal_actions(&snap, &mut legal);
                let action = legal
                    .as_slice()
                    .iter()
                    .copied()
                    .find(|&a| MillUciCodec::encode_action(a) == notation)
                    .unwrap_or_else(|| {
                        panic!("puzzle `{id}` move `{notation}` must be legal when reached")
                    });
                snap = rules.apply(&snap, action);
            }
            assert_eq!(
                rules.outcome(&snap).kind,
                OutcomeKind::Win(solver_side),
                "puzzle `{id}` solution must end in a win for the solving side"
            );
        }
    }
}

#[test]
fn iso8601_formatting_matches_known_reference_dates() {
    assert_eq!(
        unix_timestamp_to_iso8601(0),
        "1970-01-01T00:00:00.000Z",
        "Unix epoch"
    );
    assert_eq!(
        unix_timestamp_to_iso8601(1_704_067_200),
        "2024-01-01T00:00:00.000Z",
    );
    assert_eq!(
        unix_timestamp_to_iso8601(951_868_800),
        "2000-03-01T00:00:00.000Z",
        "day after the 2000 leap day"
    );
    assert_eq!(
        unix_timestamp_to_iso8601(946_684_799),
        "1999-12-31T23:59:59.000Z",
        "one second before Y2K"
    );
}
