// SPDX-License-Identifier: AGPL-3.0-or-later
// End-to-end tests for the `puzzle-gen` pipeline, using the small Perfect DB
// subset bundled with the Flutter app.

use perfect_db::database::{Database, DatabaseOptions, DatabaseVariant, FileDatabaseProvider};
use tgf_core::{ActionList, GameRules, OutcomeKind};
use tgf_mill::{MillGame, MillRules, MillUciCodec, MillVariantOptions};

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
        sacrifice_filter: SacrificeFilter::Include,
        opponent_depth: 4,
        max_attempts: 5000,
        seed: 0xC0FF_EE00_1234_5678,
        cache_capacity: 16,
        author: "Test Author".to_string(),
        rule_variant_id: "standard_9mm",
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
    let mut found: Option<PuzzleInfoJson> = None;
    for _ in 0..cfg.max_attempts {
        let spec = SampleSpec {
            phase: cfg.phase,
            side: cfg.side,
            min_pieces: cfg.min_pieces,
            max_pieces: cfg.max_pieces,
        };
        let query = sample_root_query(&mut rng, &spec, &options);
        if let Some(info) = try_build_puzzle(&mut database, &env, query, generated_at, &mut rng) {
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
