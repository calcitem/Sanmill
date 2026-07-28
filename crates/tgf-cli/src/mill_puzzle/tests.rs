// SPDX-License-Identifier: AGPL-3.0-or-later
// End-to-end tests for the `puzzle-gen` pipeline, using the small Perfect DB
// subset bundled with the Flutter app.

use std::collections::HashSet;

use perfect_db::database::{
    Database, DatabaseOptions, DatabaseVariant, FileDatabaseProvider, PerfectOutcome, PerfectQuery,
};
use perfect_db::{PerfectLogicalTurnChoice, query_from_state};
use tgf_core::{Action, ActionList, GameRules, OutcomeKind};
use tgf_mill::human_db_codec::{HumanTurn, parse_human_turn_notation_with_history};
use tgf_mill::{
    MillGame, MillPhase, MillRules, MillUciCodec, MillVariantOptions, default_mill_topology,
    legal_logical_turns,
};

use super::analysis::{
    RootTurnBreakdown, canonical_solver_symmetry_key, canonical_symmetry_key, classify_root_turns,
};
use super::motifs::{PuzzleMotif, matches_required_motif};
use super::sampler::sample_root_query;
use super::*;

fn human_turn_actions(turn: HumanTurn) -> Vec<Action> {
    match turn {
        HumanTurn::BaseOnly(action) | HumanTurn::CaptureOnly(action) => vec![action],
        HumanTurn::BaseThenCapture { base, capture } => vec![base, capture],
    }
}

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

fn exclusion_queries(
    record: &str,
    source_name: &str,
    rules: &MillRules,
    options: &MillVariantOptions,
) -> Vec<PerfectQuery> {
    record
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty() && !line.starts_with('#'))
        .map(|fen| {
            let state = rules
                .set_from_fen(fen)
                .unwrap_or_else(|error| panic!("{source_name} FEN must parse ({error}): {fen}"));
            query_from_state(&state, options, state.side_to_move())
                .unwrap_or_else(|| panic!("{source_name} FEN must map to Perfect DB: {fen}"))
        })
        .collect()
}

fn permissive_test_config() -> GenConfig {
    GenConfig {
        db_path: bundled_db_root().to_string_lossy().into_owned(),
        out_path: "unused.sanmill_puzzles".to_string(),
        candidate_file: String::new(),
        mine_entry_files: String::new(),
        exclude_fens: String::new(),
        required_motif: PuzzleMotif::Any,
        candidate_discovery: None,
        count: 1,
        min_depth: 1,
        max_depth: 12,
        side: SideChoice::Random,
        phase: PhaseChoice::Moving,
        // Sectors (3,3,0,0), (3,4,0,0), and (4,3,0,0) are all bundled, so
        // targeting this narrow board-size window keeps the test from
        // depending on the much larger external Perfect DB.
        min_solver_pieces: 3,
        max_solver_pieces: 4,
        min_defender_pieces: 3,
        max_defender_pieces: 4,
        max_solutions: 3,
        max_exported_lines: super::solver::MAX_EXPORTED_SOLUTION_LINES,
        // The bundled endgame sectors are tiny lopsided wins; disable every
        // challenge filter so the pipeline mechanics stay testable offline.
        min_mistakes: 0,
        max_piece_diff: 99,
        min_solve_depth: 2,
        require_trap: false,
        require_quiet_first_move: false,
        min_non_winning_turns: 0,
        sacrifice_filter: SacrificeFilter::Include,
        max_attempts: 5000,
        seed: 0xC0FF_EE00_1234_5678,
        cache_capacity: 16,
        author: "Test Author".to_string(),
        rule_variant_id: "standard_9mm",
        pack_id: String::new(),
        pack_name: String::new(),
        pack_description: String::new(),
        is_official: false,
    }
}

#[test]
fn review_pack_metadata_is_not_marked_official() {
    let mut cfg = permissive_test_config();
    cfg.pack_id = "review-pack".to_string();
    cfg.pack_name = "Review pack".to_string();
    cfg.is_official = false;

    let metadata = build_pack_metadata(&cfg).expect("a pack id must emit metadata");
    assert!(!metadata.is_official);

    cfg.is_official = true;
    let official = build_pack_metadata(&cfg).expect("a pack id must emit metadata");
    assert!(official.is_official);
}

/// Replay every move of every solution from the puzzle's initial position
/// and assert the game genuinely ends in a win for the side to move at the
/// start -- i.e. the JSON this module produced is a real, solvable puzzle
/// and not just internally-consistent bookkeeping.
fn assert_puzzle_is_replayable(rules: &MillRules, info: &PuzzleInfoJson) {
    assert!(!info.solutions.is_empty());
    assert!(info.solutions.len() <= super::solver::MAX_EXPORTED_SOLUTION_LINES);
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
    let mut audit = GenAudit::default();
    let mut found: Option<PuzzleInfoJson> = None;
    for _ in 0..cfg.max_attempts {
        let spec = SampleSpec {
            phase: cfg.phase,
            side: cfg.side,
            min_solver_pieces: cfg.min_solver_pieces,
            max_solver_pieces: cfg.max_solver_pieces,
            min_defender_pieces: cfg.min_defender_pieces,
            max_defender_pieces: cfg.max_defender_pieces,
        };
        let query = sample_root_query(&mut rng, &spec, &options);
        let mut context = GenAttemptContext {
            generated_at,
            rng: &mut rng,
            seen_roots: &mut seen_roots,
            audit: &mut audit,
        };
        if let Some(info) = try_build_puzzle(&mut database, &env, query, None, None, &mut context) {
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

fn moving_snapshot_with_pieces(
    rules: &MillRules,
    options: &MillVariantOptions,
    white: &[&str],
    black: &[&str],
    side_to_move: i8,
) -> tgf_core::GameStateSnapshot {
    let topology = default_mill_topology();
    let node_by_label = |label: &str| -> u16 {
        topology
            .nodes()
            .iter()
            .find(|node| node.label == label)
            .unwrap_or_else(|| panic!("topology must contain node `{label}`"))
            .id as u16
    };
    let mut state = rules.setup_empty();
    for &label in white {
        state.set_piece(node_by_label(label), 1);
    }
    for &label in black {
        state.set_piece(node_by_label(label), 2);
    }
    state.recompute_aux(options);
    state.set_pieces_in_hand([0, 0], options);
    state.set_side_to_move(side_to_move);
    state.set_phase(MillPhase::Moving);
    rules.encode_state(state)
}

fn motif_outcomes_for_primary(
    rules: &MillRules,
    snapshot: &tgf_core::GameStateSnapshot,
    winning_primary: &str,
) -> (Vec<PerfectLogicalTurnChoice>, RootTurnBreakdown) {
    let logical_turns = legal_logical_turns(rules, snapshot, &[])
        .expect("crafted motif root must enumerate logical turns");
    let matching_count = logical_turns
        .iter()
        .filter(|turn| MillUciCodec::encode_action(turn.actions[0]) == winning_primary)
        .count();
    assert_eq!(
        matching_count, 1,
        "crafted motif root must identify one complete winning turn"
    );
    let outcomes = logical_turns
        .into_iter()
        .map(|turn| {
            let tokens = turn
                .actions
                .iter()
                .copied()
                .map(MillUciCodec::encode_action)
                .collect::<Vec<_>>();
            let outcome = if tokens[0] == winning_primary {
                PerfectOutcome::Win { steps: 2 }
            } else {
                PerfectOutcome::Loss { steps: 4 }
            };
            PerfectLogicalTurnChoice {
                actions: turn.actions,
                tokens,
                outcome,
            }
        })
        .collect::<Vec<_>>();
    let breakdown = classify_root_turns(rules, snapshot, &outcomes, snapshot.side_to_move);
    (outcomes, breakdown)
}

#[test]
fn strategy_derived_motifs_match_only_their_exact_structures() {
    let options = MillVariantOptions::default();
    let rules = MillRules::new(options.clone());
    let cases = [
        (
            PuzzleMotif::AllowMill,
            moving_snapshot_with_pieces(
                &rules,
                &options,
                &["g1", "d1", "b2", "e3"],
                &["a1", "a4", "g7"],
                0,
            ),
            "g1-g4",
        ),
        (
            PuzzleMotif::MobilitySqueeze,
            moving_snapshot_with_pieces(
                &rules,
                &options,
                &["g1", "e3", "c3"],
                &["d5", "d7", "f6", "b6"],
                0,
            ),
            "g1-d6",
        ),
        (
            PuzzleMotif::JunctionRelease,
            moving_snapshot_with_pieces(
                &rules,
                &options,
                &["d6", "a7", "a4", "g1"],
                &["f4", "g7", "g4", "a1"],
                0,
            ),
            "d6-f6",
        ),
        (
            PuzzleMotif::MillRecovery,
            moving_snapshot_with_pieces(
                &rules,
                &options,
                &["a1", "a4", "a7", "g7"],
                &["f4", "f2", "b2", "b6"],
                0,
            ),
            "g7-d7",
        ),
        (
            PuzzleMotif::RightAngleThreat,
            moving_snapshot_with_pieces(
                &rules,
                &options,
                &["e5", "c5", "d6", "a1"],
                &["g7", "g4", "b2", "f2"],
                0,
            ),
            "e5-d5",
        ),
        (
            PuzzleMotif::RingTransfer,
            moving_snapshot_with_pieces(
                &rules,
                &options,
                &["d7", "b6", "a1", "g1"],
                &["g7", "g4", "b2", "e3"],
                0,
            ),
            "d7-d6",
        ),
    ];

    for (motif, snapshot, winning_primary) in cases {
        let (outcomes, breakdown) = motif_outcomes_for_primary(&rules, &snapshot, winning_primary);
        assert!(
            matches_required_motif(
                motif,
                &rules,
                &snapshot,
                snapshot.side_to_move,
                &outcomes,
                &breakdown,
            ),
            "{motif:?} must match its crafted exact structure"
        );
    }
}

#[test]
fn classify_root_turns_includes_compulsory_removal_in_the_decision() {
    let options = MillVariantOptions::default();
    let rules = MillRules::new(options.clone());
    let snap = placing_snapshot_with_open_mill(&rules, &options);

    let mill_closing_token = "a7";
    let logical_turns =
        legal_logical_turns(&rules, &snap, &[]).expect("crafted root must enumerate logical turns");
    let mill_turn_count = logical_turns
        .iter()
        .filter(|turn| MillUciCodec::encode_action(turn.actions[0]) == mill_closing_token)
        .count();
    assert!(
        mill_turn_count > 1,
        "placing at a7 must branch over compulsory removal choices"
    );

    // Scenario 1: the mill-closing placement loses, everything else wins.
    // The trap flag must fire and the solution must start with a quiet
    // (non-mill) move.
    let outcomes: Vec<PerfectLogicalTurnChoice> = logical_turns
        .iter()
        .map(|turn| {
            let tokens = turn
                .actions
                .iter()
                .copied()
                .map(MillUciCodec::encode_action)
                .collect::<Vec<_>>();
            let outcome = if tokens[0] == mill_closing_token {
                PerfectOutcome::Loss { steps: 4 }
            } else {
                PerfectOutcome::Win { steps: 6 }
            };
            PerfectLogicalTurnChoice {
                actions: turn.actions.clone(),
                tokens,
                outcome,
            }
        })
        .collect();
    let breakdown = classify_root_turns(&rules, &snap, &outcomes, 0);
    assert_eq!(breakdown.non_winning_count, mill_turn_count);
    assert!(breakdown.slower_winning.is_empty());
    assert!(breakdown.tempting_mill_mistake);
    assert!(breakdown.quiet_first_move);
    assert_eq!(
        breakdown.shortest_winning.len(),
        logical_turns.len() - mill_turn_count
    );

    // Scenario 2: the same mill-forming primary action has several removal
    // continuations, but only one complete turn wins. The classifier must
    // retain that exact action pair rather than accepting every a7 capture.
    let mut winning_mill_turn_assigned = false;
    let outcomes: Vec<PerfectLogicalTurnChoice> = logical_turns
        .iter()
        .map(|turn| {
            let tokens = turn
                .actions
                .iter()
                .copied()
                .map(MillUciCodec::encode_action)
                .collect::<Vec<_>>();
            let is_first_mill_turn = tokens[0] == mill_closing_token && !winning_mill_turn_assigned;
            if is_first_mill_turn {
                winning_mill_turn_assigned = true;
            }
            let outcome = if is_first_mill_turn {
                PerfectOutcome::Win { steps: 2 }
            } else {
                PerfectOutcome::Loss { steps: 8 }
            };
            PerfectLogicalTurnChoice {
                actions: turn.actions.clone(),
                tokens,
                outcome,
            }
        })
        .collect();
    let breakdown = classify_root_turns(&rules, &snap, &outcomes, 0);
    assert_eq!(breakdown.shortest_winning.len(), 1);
    assert!(breakdown.tempting_mill_mistake);
    assert!(!breakdown.quiet_first_move);
    assert_eq!(breakdown.non_winning_count, logical_turns.len() - 1);
    assert_eq!(breakdown.non_shortest_count(), logical_turns.len() - 1);
    assert_eq!(breakdown.shortest_winning[0].actions.len(), 2);
    assert!(
        matches_required_motif(
            PuzzleMotif::CaptureChoice,
            &rules,
            &snap,
            0,
            &outcomes,
            &breakdown,
        ),
        "only one removal continuation preserves the win"
    );

    // Scenario 3: distinguish an equally legal slower forced win from both
    // the shortest solution and the non-winning alternatives.
    let mut quiet_win_index = 0usize;
    let outcomes: Vec<PerfectLogicalTurnChoice> = logical_turns
        .iter()
        .map(|turn| {
            let tokens = turn
                .actions
                .iter()
                .copied()
                .map(MillUciCodec::encode_action)
                .collect::<Vec<_>>();
            let outcome = if tokens[0] == mill_closing_token {
                PerfectOutcome::Loss { steps: 8 }
            } else {
                quiet_win_index += 1;
                match quiet_win_index {
                    1 => PerfectOutcome::Win { steps: 2 },
                    2 => PerfectOutcome::Win { steps: 4 },
                    _ => PerfectOutcome::Loss { steps: 8 },
                }
            };
            PerfectLogicalTurnChoice {
                actions: turn.actions.clone(),
                tokens,
                outcome,
            }
        })
        .collect();
    assert!(quiet_win_index >= 2);
    let breakdown = classify_root_turns(&rules, &snap, &outcomes, 0);
    assert_eq!(breakdown.shortest_winning.len(), 1);
    assert_eq!(breakdown.slower_winning.len(), 1);
    assert_eq!(breakdown.non_winning_count, logical_turns.len() - 2);
    assert_eq!(breakdown.non_shortest_count(), logical_turns.len() - 1);
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

    let colour_exchanged = PerfectQuery::new(
        base.black_bits,
        base.white_bits,
        base.black_in_hand,
        base.white_in_hand,
        0,
        false,
    );
    assert_eq!(
        canonical_solver_symmetry_key(&colour_exchanged),
        canonical_solver_symmetry_key(&base),
        "exchanging both colours and the side to move must retain the editorial key"
    );
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
    assert_eq!(
        package["puzzleCount"].as_u64(),
        Some(puzzles.len() as u64),
        "declared built-in puzzle count must match the array"
    );
    assert_eq!(
        puzzles.len(),
        167,
        "the expert-review curriculum size is intentional"
    );
    assert_eq!(
        package["metadata"]["version"].as_str(),
        Some("1.6.0-review.1"),
        "the embedded expert-review build requires its prerelease contract"
    );
    assert_eq!(
        package["metadata"]["isOfficial"].as_bool(),
        Some(false),
        "a pack containing pending specialist candidates is not yet official"
    );
    let review_batches = package["reviewBatches"]
        .as_array()
        .expect("expert-review asset must declare reviewBatches");
    assert_eq!(review_batches.len(), 2);
    let review_batch_counts = review_batches
        .iter()
        .map(|batch| {
            assert_eq!(batch["status"].as_str(), Some("expert-pending"));
            assert_eq!(
                batch["selectionProvenance"]["status"].as_str(),
                Some("OPTIMAL")
            );
            (
                batch["id"]
                    .as_str()
                    .expect("review batch must have an id")
                    .to_string(),
                batch["puzzleCount"]
                    .as_u64()
                    .expect("review batch must have a count") as usize,
            )
        })
        .collect::<std::collections::HashMap<_, _>>();
    assert_eq!(
        review_batch_counts,
        std::collections::HashMap::from([
            ("engine-blunder-review-selected-30".to_string(), 30),
            ("strategy-theme-review-selected-10".to_string(), 10),
        ])
    );

    let options = MillVariantOptions::default();
    let rules = MillRules::new(options.clone());
    let editorial_baseline_queries = exclusion_queries(
        include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/testdata/puzzle_exclusions/mill_editorial_baseline.fen"
        )),
        "editorial baseline exclusion",
        &rules,
        &options,
    );
    let editorial_baseline_roots = editorial_baseline_queries
        .iter()
        .map(canonical_symmetry_key)
        .collect::<HashSet<_>>();
    let editorial_baseline_solver_roots = editorial_baseline_queries
        .iter()
        .map(canonical_solver_symmetry_key)
        .collect::<HashSet<_>>();
    assert_eq!(
        editorial_baseline_queries.len(),
        12,
        "the editorial baseline must retain twelve raw roots"
    );
    assert_eq!(
        editorial_baseline_roots.len(),
        12,
        "the editorial baseline must retain all twelve canonical roots"
    );
    let non_replay_reference_queries = exclusion_queries(
        include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/testdata/puzzle_exclusions/mill_editorial_non_replay.fen"
        )),
        "editorial non-replay exclusion",
        &rules,
        &options,
    );
    let non_replay_reference_roots = non_replay_reference_queries
        .iter()
        .map(canonical_symmetry_key)
        .collect::<HashSet<_>>();
    let non_replay_reference_solver_roots = non_replay_reference_queries
        .iter()
        .map(canonical_solver_symmetry_key)
        .collect::<HashSet<_>>();
    assert_eq!(
        non_replay_reference_queries.len(),
        41,
        "the editorial non-replay record must retain all 41 recovered roots"
    );
    assert_eq!(
        non_replay_reference_roots.len(),
        39,
        "two study-sheet pairs intentionally share a ring-16 class"
    );
    let replay_reference_queries = exclusion_queries(
        include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/testdata/puzzle_exclusions/mill_editorial_replay.fen"
        )),
        "editorial replay presentation",
        &rules,
        &options,
    );
    let replay_reference_roots = replay_reference_queries
        .iter()
        .map(canonical_symmetry_key)
        .collect::<HashSet<_>>();
    let replay_reference_solver_roots = replay_reference_queries
        .iter()
        .map(canonical_solver_symmetry_key)
        .collect::<HashSet<_>>();
    assert_eq!(replay_reference_queries.len(), 3);
    assert_eq!(replay_reference_roots.len(), 3);
    let mut ids = HashSet::new();
    let mut canonical_roots = HashSet::new();
    let mut z3_topic_counts = std::collections::HashMap::<String, usize>::new();
    let mut replay_topic_counts = std::collections::HashMap::<String, usize>::new();
    let mut replay_distance_counts = std::collections::HashMap::<String, usize>::new();
    let mut replay_count = 0_usize;
    let mut composed_count = 0_usize;
    let mut expert_review_count = 0_usize;
    let mut expert_review_batch_counts = std::collections::HashMap::<String, usize>::new();
    let mut reference_root_overlap_count = 0_usize;
    for puzzle in puzzles {
        let id = puzzle["id"].as_str().expect("puzzle id must be a string");
        assert!(ids.insert(id.to_string()), "duplicate puzzle id `{id}`");
        assert_eq!(puzzle["ruleVariantId"].as_str(), Some("standard_9mm"));
        let tags = puzzle["tags"]
            .as_array()
            .expect("puzzle tags must be an array");
        let is_composed = tags
            .iter()
            .any(|tag| tag.as_str() == Some("source:composed"));
        let is_replay_backed = tags
            .iter()
            .any(|tag| tag.as_str() == Some("source:replay-backed"));
        assert_ne!(
            is_composed, is_replay_backed,
            "puzzle `{id}` must disclose exactly one source evidence kind"
        );
        if is_composed {
            composed_count += 1;
            assert!(
                puzzle
                    .get("provenance")
                    .is_none_or(serde_json::Value::is_null),
                "composed puzzle `{id}` must not claim replay provenance"
            );
        } else {
            replay_count += 1;
            assert!(
                tags.iter()
                    .any(|tag| { tag.as_str() == Some("solution-display:principal-variation") }),
                "replay-backed puzzle `{id}` must disclose its compact display policy"
            );
        }
        let is_pending_expert_review = tags
            .iter()
            .any(|tag| tag.as_str() == Some("review-status:expert-pending"));
        if is_pending_expert_review {
            expert_review_count += 1;
            assert!(is_composed, "review candidate `{id}` must be composed");
            assert!(
                tags.iter()
                    .any(|tag| { tag.as_str() == Some("discovery:engine-blunder-corpus") }),
                "review candidate `{id}` must retain discovery provenance"
            );
            let batch_tags = tags
                .iter()
                .filter_map(|tag| tag.as_str())
                .filter_map(|tag| tag.strip_prefix("review-batch:"))
                .collect::<Vec<_>>();
            assert_eq!(
                batch_tags.len(),
                1,
                "review candidate `{id}` must identify exactly one review batch"
            );
            assert!(
                review_batch_counts.contains_key(batch_tags[0]),
                "review candidate `{id}` names an unknown review batch"
            );
            *expert_review_batch_counts
                .entry(batch_tags[0].to_string())
                .or_default() += 1;
        }
        for prefix in ["topic:", "curriculum:", "progression:", "distance-band:"] {
            assert_eq!(
                tags.iter()
                    .filter(|tag| tag.as_str().is_some_and(|tag| tag.starts_with(prefix)))
                    .count(),
                1,
                "puzzle `{id}` must have exactly one `{prefix}` classification tag"
            );
        }
        if tags
            .iter()
            .any(|tag| tag.as_str() == Some("discovery:smt-z3"))
        {
            let topic = tags
                .iter()
                .filter_map(|tag| tag.as_str())
                .find_map(|tag| tag.strip_prefix("topic:"))
                .expect("Z3 puzzle must have a topic")
                .to_string();
            *z3_topic_counts.entry(topic).or_default() += 1;
        }
        if is_replay_backed {
            let topic = tags
                .iter()
                .filter_map(|tag| tag.as_str())
                .find(|tag| tag.starts_with("topic:"))
                .expect("replay puzzle must have a topic")
                .to_string();
            let distance = tags
                .iter()
                .filter_map(|tag| tag.as_str())
                .find(|tag| tag.starts_with("distance-band:"))
                .expect("replay puzzle must have a distance band")
                .to_string();
            *replay_topic_counts.entry(topic).or_default() += 1;
            *replay_distance_counts.entry(distance).or_default() += 1;
        }

        let fen = puzzle["initialPosition"]
            .as_str()
            .expect("puzzle must carry an initial position FEN");
        let root_state = rules
            .set_from_fen(fen)
            .unwrap_or_else(|err| panic!("puzzle `{id}` FEN must parse ({err}): {fen}"));
        let solver_side = root_state.side_to_move();
        let query = query_from_state(&root_state, &options, solver_side)
            .unwrap_or_else(|| panic!("puzzle `{id}` must map to a Perfect DB query"));
        let root_snap = rules.encode_state(root_state);
        let canonical_root = canonical_symmetry_key(&query);
        let canonical_solver_root = canonical_solver_symmetry_key(&query);
        assert!(
            canonical_roots.insert(canonical_root),
            "puzzle `{id}` duplicates another root under a board symmetry"
        );
        assert!(
            !non_replay_reference_roots.contains(&canonical_root)
                && !non_replay_reference_solver_roots.contains(&canonical_solver_root),
            "puzzle `{id}` duplicates a non-replay editorial root under ring-16 symmetry and optional colour exchange"
        );
        let matches_replay_reference = replay_reference_roots.contains(&canonical_root)
            || replay_reference_solver_roots.contains(&canonical_solver_root);
        if matches_replay_reference {
            reference_root_overlap_count += 1;
            assert!(
                is_replay_backed,
                "puzzle `{id}` matches a replay reference root but is not replay-backed"
            );
            assert!(
                !replay_reference_queries
                    .iter()
                    .any(|reference| reference == &query),
                "puzzle `{id}` reuses a recorded replay reference presentation"
            );
        }
        assert!(
            (!editorial_baseline_roots.contains(&canonical_root)
                && !editorial_baseline_solver_roots.contains(&canonical_solver_root))
                || matches_replay_reference,
            "puzzle `{id}` duplicates an editorial reference root under ring-16 symmetry and optional colour exchange"
        );
        if is_replay_backed {
            let provenance = puzzle["provenance"]
                .as_object()
                .unwrap_or_else(|| panic!("replay-backed puzzle `{id}` needs provenance"));
            assert_eq!(
                provenance["kind"].as_str(),
                Some("human-game-replay"),
                "puzzle `{id}` provenance kind"
            );
            assert_eq!(
                provenance["transformModel"].as_str(),
                Some("sanmill-ring16-v1"),
                "puzzle `{id}` transform model"
            );
            for key in ["databaseSha256", "sourceGameSha256"] {
                let hash = provenance[key]
                    .as_str()
                    .unwrap_or_else(|| panic!("puzzle `{id}` needs {key}"));
                assert!(
                    hash.len() == 64 && hash.bytes().all(|byte| byte.is_ascii_hexdigit()),
                    "puzzle `{id}` {key} must be a SHA-256"
                );
            }
            let transform = provenance["presentationTransform"]
                .as_u64()
                .expect("presentation transform");
            assert!(transform < 16, "puzzle `{id}` transform must be in 0..15");
            let replay_turns = provenance["replayHistory"]
                .as_array()
                .expect("replay history");
            assert_eq!(
                provenance["sourceLogicalPly"].as_u64(),
                Some(replay_turns.len() as u64 + 1),
                "puzzle `{id}` source ply must follow its replay prefix"
            );

            let mut replay_snap = rules.initial_state(&[]);
            let mut replay_history = Vec::new();
            for (index, raw_turn) in replay_turns.iter().enumerate() {
                let notation = raw_turn
                    .as_str()
                    .unwrap_or_else(|| panic!("puzzle `{id}` replay turn must be text"));
                let turn = parse_human_turn_notation_with_history(
                    &rules,
                    &replay_snap,
                    &replay_history,
                    notation,
                )
                .unwrap_or_else(|error| {
                    panic!(
                        "puzzle `{id}` replay turn {} `{notation}` must be legal: {error:?}",
                        index + 1
                    )
                });
                for action in human_turn_actions(turn) {
                    let before = replay_snap;
                    replay_snap = rules.apply_with_history(&before, action, &replay_history);
                    replay_history.push(before);
                }
            }
            let replay_state = MillRules::decode_snapshot(replay_snap);
            let replay_query = query_from_state(&replay_state, &options, replay_snap.side_to_move)
                .unwrap_or_else(|| panic!("puzzle `{id}` replay root must map to Perfect DB"));
            assert_eq!(
                replay_query, query,
                "puzzle `{id}` replay prefix must reach its exported root"
            );
            let recorded_turn = provenance["recordedTurn"]
                .as_str()
                .expect("recorded human turn");
            parse_human_turn_notation_with_history(
                &rules,
                &replay_snap,
                &replay_history,
                recorded_turn,
            )
            .unwrap_or_else(|error| {
                panic!(
                    "puzzle `{id}` recorded human turn `{recorded_turn}` must be legal: {error:?}"
                )
            });
        }

        let solutions = puzzle["solutions"]
            .as_array()
            .expect("puzzle must carry solutions");
        assert!(!solutions.is_empty(), "puzzle `{id}` has no solutions");
        let solution_line_limit = if is_pending_expert_review { 32 } else { 8 };
        assert!(
            solutions.len() <= solution_line_limit,
            "puzzle `{id}` exceeds its built-in solution-line limit"
        );
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
    assert_eq!(
        z3_topic_counts,
        std::collections::HashMap::from([
            ("capture-choice".to_string(), 3),
            ("dual-threat".to_string(), 3),
            ("mill-abandonment".to_string(), 3),
            ("mill-block".to_string(), 3),
            ("zugzwang".to_string(), 3),
        ]),
        "the constraint-directed pilot must stay balanced across five topics"
    );
    assert_eq!(composed_count, 154);
    assert_eq!(replay_count, 13);
    assert_eq!(expert_review_count, 40);
    assert_eq!(expert_review_batch_counts, review_batch_counts);
    assert_eq!(
        reference_root_overlap_count, 0,
        "the current 167-puzzle review curriculum has no editorial-reference overlap"
    );
    assert_eq!(
        replay_distance_counts,
        std::collections::HashMap::from([
            ("distance-band:short".to_string(), 3),
            ("distance-band:medium".to_string(), 5),
            ("distance-band:long".to_string(), 5),
        ]),
        "the replay pilot must preserve its short/medium/long progression"
    );
    assert_eq!(
        replay_topic_counts,
        std::collections::HashMap::from([
            ("topic:double-mill".to_string(), 3),
            ("topic:greedy-mill-trap".to_string(), 4),
            ("topic:immobilization".to_string(), 2),
            ("topic:quiet-move".to_string(), 2),
            ("topic:sacrifice".to_string(), 1),
            ("topic:wrong-mill-trap".to_string(), 1),
        ]),
        "the replay pilot must preserve its reviewed thematic mix"
    );
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
