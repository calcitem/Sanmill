// SPDX-License-Identifier: GPL-3.0-or-later
// Unit tests for the Mill UCI adapter.

use std::time::Duration;

use tgf_core::Action;

use super::*;

#[test]
fn parse_position_fen_loads_board() {
    let rules = MillRules::default();
    let state = parse_position_command(
        &rules,
        "position fen O@******/********/******** w p p 1 8 1 8 0 0 -1 -1 -1 -1 0 0 1 ids:nodes",
    )
    .state;

    // Node-id FEN board positions are already in dense node order.
    assert_eq!(state.opaque_payload[0], 1);
    assert_eq!(state.opaque_payload[1], 2);
    assert_eq!(state.side_to_move, 0);
}

#[test]
fn parse_position_fen_with_moves_applies_tail_moves() {
    let rules = MillRules::default();
    let state = parse_position_command(
        &rules,
        "position fen ********/********/******** w p p 0 9 0 9 0 0 -1 -1 -1 -1 0 0 1 ids:nodes moves d7",
    )
    .state;

    assert_eq!(state.opaque_payload[16], 1); // d7 / node 16
    assert_eq!(state.side_to_move, 1);
}

#[test]
fn setoption_accepts_legacy_piece_count_names() {
    let mut options = MillVariantOptions::default();
    let mut threads = 1;
    let mut qsearch = 0;
    let mut ecfg = EngineConfig::default();

    assert!(matches!(
        apply_setoption(
            "setoption name PiecesCount value 12",
            &mut options,
            &mut threads,
            &mut qsearch,
            &mut ecfg,
        ),
        SetoptionResult::Variant
    ));
    assert_eq!(options.piece_count, 12);

    assert!(matches!(
        apply_setoption(
            "setoption name flyPieceCount value 4",
            &mut options,
            &mut threads,
            &mut qsearch,
            &mut ecfg,
        ),
        SetoptionResult::Variant
    ));
    assert_eq!(options.fly_piece_count, 4);
}

#[test]
fn setoption_parses_perfect_database_options() {
    let mut options = MillVariantOptions::default();
    let mut threads = 1;
    let mut qsearch = 0;
    let mut ecfg = EngineConfig::default();

    assert!(matches!(
        apply_setoption(
            "setoption name UsePerfectDatabase value true",
            &mut options,
            &mut threads,
            &mut qsearch,
            &mut ecfg,
        ),
        SetoptionResult::SearchConfig
    ));
    assert!(ecfg.use_perfect_database);

    // A path with spaces must be captured in full, not truncated to one token.
    assert!(matches!(
        apply_setoption(
            "setoption name PerfectDatabasePath value /tmp/perfect db/strong",
            &mut options,
            &mut threads,
            &mut qsearch,
            &mut ecfg,
        ),
        SetoptionResult::SearchConfig
    ));
    assert_eq!(
        ecfg.perfect_db_path.as_deref(),
        Some("/tmp/perfect db/strong")
    );

    assert!(matches!(
        apply_setoption(
            "setoption name PerfectDatabaseCacheSectors value 2",
            &mut options,
            &mut threads,
            &mut qsearch,
            &mut ecfg,
        ),
        SetoptionResult::SearchConfig
    ));
    assert_eq!(ecfg.perfect_db_cache_sectors, Some(2));

    assert!(matches!(
        apply_setoption(
            "setoption name Perfect Database Cache Sectors value 0",
            &mut options,
            &mut threads,
            &mut qsearch,
            &mut ecfg,
        ),
        SetoptionResult::SearchConfig
    ));
    assert_eq!(ecfg.perfect_db_cache_sectors, None);

    assert!(matches!(
        apply_setoption(
            "setoption name UsePerfectDatabase value off",
            &mut options,
            &mut threads,
            &mut qsearch,
            &mut ecfg,
        ),
        SetoptionResult::SearchConfig
    ));
    assert!(!ecfg.use_perfect_database);
}

#[test]
fn perfect_database_runtime_config_tracks_supported_rule_variants() {
    let cfg = EngineConfig {
        perfect_db_path: Some("/tmp/perfect-db".to_owned()),
        perfect_db_cache_sectors: Some(2),
        ..EngineConfig::default()
    };
    let mut options = MillVariantOptions::default();

    let standard = cfg
        .desired_perfect_db_config(&options)
        .unwrap()
        .expect("path must produce a desired Perfect DB config");
    assert_eq!(standard.variant, DatabaseVariant::STANDARD);
    assert_eq!(standard.options.sector_cache_capacity, Some(2));

    options.piece_count = 10;
    assert_eq!(
        cfg.desired_perfect_db_config(&options),
        Err(PerfectDatabaseRuleMismatch::VariantShape {
            piece_count: 10,
            has_diagonal_lines: false,
            may_move_in_placing_phase: false,
        })
    );
    options.may_move_in_placing_phase = true;
    let lasker = cfg
        .desired_perfect_db_config(&options)
        .unwrap()
        .expect("Lasker Morris must map to a Perfect DB variant");
    assert_eq!(lasker.variant, DatabaseVariant::LASKER);

    options = MillVariantOptions {
        piece_count: 12,
        has_diagonal_lines: true,
        ..MillVariantOptions::default()
    };
    let morabaraba = cfg
        .desired_perfect_db_config(&options)
        .unwrap()
        .expect("Morabaraba must map to a Perfect DB variant");
    assert_eq!(morabaraba.variant, DatabaseVariant::MORABARABA);

    options.has_diagonal_lines = false;
    assert_eq!(
        cfg.desired_perfect_db_config(&options),
        Err(PerfectDatabaseRuleMismatch::VariantShape {
            piece_count: 12,
            has_diagonal_lines: false,
            may_move_in_placing_phase: false,
        })
    );

    options = MillVariantOptions::default();
    options.may_remove_multiple = true;
    assert_eq!(
        cfg.desired_perfect_db_config(&options),
        Err(PerfectDatabaseRuleMismatch::CommonRules)
    );

    options = MillVariantOptions::default();
    options.piece_count = 11;
    assert_eq!(
        cfg.desired_perfect_db_config(&options),
        Err(PerfectDatabaseRuleMismatch::VariantShape {
            piece_count: 11,
            has_diagonal_lines: false,
            may_move_in_placing_phase: false,
        })
    );
}

#[test]
fn perfect_database_lookup_is_noop_when_uninitialized() {
    // Without an initialized database the helper must yield None so the
    // search result is used unchanged.
    let rules = MillRules::default();
    let state = rules.initial_state(&[]);
    assert!(!perfect_db::is_initialized());
    assert!(
        try_perfect_best_action(
            &MillVariantOptions::default(),
            &state,
            perfect_db::PerfectMoveOrdering::LegacyWdl,
        )
        .is_none()
    );
}

#[test]
fn perfect_database_ordering_matches_master_random_lazy_branch() {
    assert_eq!(
        perfect_move_ordering(&EngineConfig::default()),
        perfect_db::PerfectMoveOrdering::LegacyWdl
    );
    assert_eq!(
        perfect_move_ordering(&EngineConfig {
            algorithm: 4,
            ai_is_lazy: false,
            ..EngineConfig::default()
        }),
        perfect_db::PerfectMoveOrdering::StrictSteps
    );
    assert_eq!(
        perfect_move_ordering(&EngineConfig {
            algorithm: 4,
            ai_is_lazy: true,
            ..EngineConfig::default()
        }),
        perfect_db::PerfectMoveOrdering::LegacyWdl
    );
}

#[test]
fn engine_config_algorithm_routes_search() {
    let rules = MillRules::default();
    let snap = rules.initial_state(&[]);
    let cfg = EngineConfig {
        algorithm: 4,
        shuffling: false,
        ..EngineConfig::default()
    };
    let mut searcher = mill_searcher();
    let result = run_configured_search(
        MillVariantOptions::default(),
        snap,
        Vec::new(),
        false,
        1,
        &cfg,
        &mut searcher,
    );

    assert!(
        !result.best_action.is_none(),
        "random algorithm path must still return a best move"
    );
    assert_eq!(result.score, 0, "random path returns a neutral score");
}

#[test]
fn aborted_final_ids_iteration_keeps_last_completed_result() {
    let completed = SearchResult {
        best_action: Action {
            kind_tag: MillActionKind::Place as i16,
            from_node: -1,
            to_node: 0,
            aux: -1,
            payload_bits: 0,
        },
        score: 7,
        nodes: 100,
        draw_reason: None,
    };
    let partial = SearchResult {
        best_action: Action {
            kind_tag: MillActionKind::Place as i16,
            from_node: -1,
            to_node: 1,
            aux: -1,
            payload_bits: 0,
        },
        score: -3,
        nodes: 25,
        draw_reason: None,
    };

    assert_eq!(
        select_completed_search_result(partial, completed, true),
        completed,
        "a timed-out final IDS pass must not replace the last full-depth pass"
    );
    assert_eq!(
        select_completed_search_result(partial, completed, false),
        partial,
        "a fully completed final pass should remain authoritative"
    );
    assert_eq!(
        select_completed_search_result(partial, SearchResult::default_none(), true),
        partial,
        "without any completed IDS pass, keep the only available result"
    );
}

#[test]
fn default_go_depth_uses_recommended_depth() {
    let options = MillVariantOptions::default();
    let rules = MillRules::new(options.clone());
    let snap = rules.initial_state(&[]);
    let cfg = EngineConfig {
        skill_level: 5,
        draw_on_human_experience: false,
        developer_mode: false,
        ..EngineConfig::default()
    };

    let go = parse_go_options("go", snap.side_to_move, &cfg);
    assert_eq!(go.depth, 0, "missing depth is represented as auto");
    let depth = effective_search_depth(&options, &snap, go.depth, &cfg);
    assert_eq!(depth, 5);
}

#[test]
fn ai_is_lazy_uses_signed_previous_score() {
    let options = MillVariantOptions::default();
    let rules = MillRules::new(options.clone());
    let snap = rules.initial_state(&[]);
    let lazy_ahead = EngineConfig {
        ai_is_lazy: true,
        last_best_value: 15,
        ..EngineConfig::default()
    };
    let lazy_behind = EngineConfig {
        ai_is_lazy: true,
        last_best_value: -15,
        ..EngineConfig::default()
    };

    assert_eq!(effective_search_depth(&options, &snap, 6, &lazy_ahead), 4);
    assert_eq!(effective_search_depth(&options, &snap, 6, &lazy_behind), 6);
}

#[test]
fn clear_hash_button_does_not_require_value() {
    let mut options = MillVariantOptions::default();
    let mut threads = 1;
    let mut qsearch = 0;
    let mut ecfg = EngineConfig::default();

    assert_eq!(
        apply_setoption(
            "setoption name Clear Hash",
            &mut options,
            &mut threads,
            &mut qsearch,
            &mut ecfg,
        ),
        SetoptionResult::ClearHash
    );
}

#[test]
fn lazy_smp_requires_explicit_option() {
    let mut cfg = EngineConfig::default();
    assert!(!cfg.use_lazy_smp);

    let mut options = MillVariantOptions::default();
    let mut threads = 1;
    let mut qsearch = 0;
    assert_eq!(
        apply_setoption(
            "setoption name UseLazySmp value true",
            &mut options,
            &mut threads,
            &mut qsearch,
            &mut cfg,
        ),
        SetoptionResult::SearchConfig
    );
    assert!(cfg.use_lazy_smp);
}

#[test]
fn print_board_ascii_switches_diagonal_template() {
    let rules = MillRules::default();
    let snap = rules.initial_state(&[]);
    let standard = board_ascii_lines(&snap, false).join("\n");
    let diagonal = board_ascii_lines(&snap, true).join("\n");

    assert!(standard.contains("|       |       |"));
    assert!(diagonal.contains(r"\     |     /"));
}

#[test]
fn active_search_try_take_finished_updates_last_best_value() {
    let (tx, rx) = mpsc::channel();
    let handle = thread::spawn(move || {
        tx.send(SpawnResult {
            depth: 1,
            result: SearchResult {
                best_action: Action {
                    kind_tag: MillActionKind::Place as i16,
                    from_node: -1,
                    to_node: 0,
                    aux: -1,
                    payload_bits: 0,
                },
                score: 5,
                nodes: 1,
                draw_reason: None,
            },
            root_side_to_move: 0,
        })
        .unwrap();
    });
    let mut active = Some(ActiveSearch {
        handle,
        abort_handle: SearchAbortHandle::from_arc(Arc::new(AtomicBool::new(false))),
        receiver: rx,
    });

    let mut cfg = EngineConfig::default();
    for _ in 0..100 {
        if let Some(spawn) = take_finished_search(&mut active) {
            update_last_best_value(&mut cfg, &spawn);
            break;
        }
        thread::sleep(Duration::from_millis(1));
    }

    assert!(active.is_none(), "finished search must be drained");
    assert_eq!(cfg.last_best_value, 5);
}

#[test]
fn format_spawn_result_prints_draw_bestmove_for_draw_short_circuit() {
    let spawn = SpawnResult {
        depth: 2,
        result: SearchResult::draw_short_circuit("draw"),
        root_side_to_move: -1,
    };

    assert_eq!(
        format_spawn_result(&spawn),
        "info depth 2 score cp 0 nodes 0 bestmove draw"
    );
}
