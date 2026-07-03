// SPDX-License-Identifier: AGPL-3.0-or-later
// Unit tests for the Mill UCI adapter.

use std::time::Duration;

use tgf_core::Action;

use super::*;

#[test]
fn tt_move_toggle_accepts_candidate_values() {
    assert!(parse_tt_move_enabled("1"));
    assert!(parse_tt_move_enabled("true"));
    assert!(parse_tt_move_enabled("on"));
    assert!(parse_tt_move_enabled("yes"));
    assert!(!parse_tt_move_enabled("0"));
    assert!(!parse_tt_move_enabled("false"));
    assert!(!parse_tt_move_enabled("off"));
    assert!(!parse_tt_move_enabled("no"));
}

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
            "setoption name PatchPath value /tmp/std.mill_patch",
            &mut options,
            &mut threads,
            &mut qsearch,
            &mut ecfg,
        ),
        SetoptionResult::SearchConfig
    ));
    assert_eq!(ecfg.patch_path.as_deref(), Some("/tmp/std.mill_patch"));

    assert!(matches!(
        apply_setoption(
            "setoption name PatchAvoidTraps value true",
            &mut options,
            &mut threads,
            &mut qsearch,
            &mut ecfg,
        ),
        SetoptionResult::SearchConfig
    ));
    assert!(ecfg.patch_avoid_traps);

    assert!(matches!(
        apply_setoption(
            "setoption name PatchMakeTraps value true",
            &mut options,
            &mut threads,
            &mut qsearch,
            &mut ecfg,
        ),
        SetoptionResult::SearchConfig
    ));
    assert!(ecfg.patch_make_traps);

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
fn eval_weights_from_env_parses_valid_triple() {
    // MillEvalWeights::from_env reads TGF_EVAL_WEIGHTS.  When unset the
    // helper returns None and the engine uses LEGACY weights.
    assert!(
        tgf_mill::MillEvalWeights::from_env().is_none(),
        "TGF_EVAL_WEIGHTS must not be set for this test to be meaningful"
    );
    // Verify parsing via std::env in a sub-scope to avoid leaking the
    // variable across parallel tests.
    {
        // SAFETY: single-threaded tests; no concurrent env reads expected.
        unsafe { std::env::set_var("TGF_EVAL_WEIGHTS", "7,3,2") };
        let weights = tgf_mill::MillEvalWeights::from_env()
            .expect("TGF_EVAL_WEIGHTS=7,3,2 must parse successfully");
        unsafe { std::env::remove_var("TGF_EVAL_WEIGHTS") };
        assert_eq!(weights.placing.piece_value, 7);
        assert_eq!(weights.placing.mobility, 3);
        assert_eq!(weights.placing.mill_count, 2);
        assert_eq!(weights.moving_open, weights.placing);
        assert_eq!(weights.pre_fly, weights.placing);
        assert_eq!(weights.flying, weights.placing);
    }
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
    assert!(
        !go.depth_is_explicit,
        "missing depth must remain distinguishable from go depth 0"
    );
    let depth = effective_search_depth(&options, &snap, go.depth, &cfg);
    assert_eq!(depth, 5);
}

#[test]
fn go_depth_marks_depth_as_explicit() {
    let rules = MillRules::new(MillVariantOptions::default());
    let snap = rules.initial_state(&[]);
    let cfg = EngineConfig::default();

    let go = parse_go_options("go depth 10", snap.side_to_move, &cfg);

    assert_eq!(go.depth, 10);
    assert!(go.depth_is_explicit);
}

#[test]
fn lazy_smp_fixed_depth_workers_do_not_stagger_depth() {
    let rules = MillRules::new(MillVariantOptions::default());
    let snap = rules.initial_state(&[]);
    let cfg = EngineConfig::default();

    let fixed_depth_go = parse_go_options("go depth 10", snap.side_to_move, &cfg);
    let fixed_workers = lazy_smp_workers_for_go(4, &fixed_depth_go, true);
    assert!(fixed_workers.iter().all(|worker| worker.extra_depth == 0));

    let no_time_cfg = EngineConfig {
        move_time_ms: 0,
        ..EngineConfig::default()
    };
    let auto_depth_go = parse_go_options("go", snap.side_to_move, &no_time_cfg);
    let auto_workers = lazy_smp_workers_for_go(4, &auto_depth_go, false);
    assert!(auto_workers.iter().all(|worker| worker.extra_depth == 0));

    let timed_auto_depth_go = parse_go_options("go", snap.side_to_move, &cfg);
    let timed_auto_workers = lazy_smp_workers_for_go(4, &timed_auto_depth_go, true);
    assert_eq!(
        timed_auto_workers
            .iter()
            .map(|worker| worker.extra_depth)
            .collect::<Vec<_>>(),
        vec![0, 1, 0, 1]
    );

    let explicit_auto_depth_go = parse_go_options("go depth 0", snap.side_to_move, &cfg);
    let explicit_auto_workers = lazy_smp_workers_for_go(4, &explicit_auto_depth_go, true);
    assert_eq!(
        explicit_auto_workers
            .iter()
            .map(|worker| worker.extra_depth)
            .collect::<Vec<_>>(),
        vec![0, 1, 0, 1]
    );
}

#[test]
fn lazy_smp_workers_diversify_move_order_seed() {
    let mut options = SearchOptions::default();
    options.move_order_context.shuffle_seed = 12345;

    let worker0 = lazy_smp_search_options_for_worker(options, 0);
    let worker1 = lazy_smp_search_options_for_worker(options, 1);
    let worker2 = lazy_smp_search_options_for_worker(options, 2);

    assert_eq!(worker0.move_order_context.shuffle_seed, 12345);
    assert_ne!(
        worker1.move_order_context.shuffle_seed,
        worker0.move_order_context.shuffle_seed
    );
    assert_ne!(
        worker2.move_order_context.shuffle_seed,
        worker1.move_order_context.shuffle_seed
    );
}

#[test]
fn lazy_smp_selection_votes_by_bestmove() {
    let shared_action = Action {
        kind_tag: MillActionKind::Move as i16,
        from_node: 0,
        to_node: 1,
        aux: -1,
        payload_bits: 0,
    };
    let outlier_action = Action {
        kind_tag: MillActionKind::Move as i16,
        from_node: 2,
        to_node: 3,
        aux: -1,
        payload_bits: 0,
    };
    let outcome = |depth, score, best_action| LazySmpWorkerOutcome {
        depth,
        result: SearchResult {
            best_action,
            score,
            nodes: 1,
            draw_reason: None,
        },
        root_moves: Vec::new(),
    };
    let outcomes = [
        outcome(8, 10, shared_action),
        outcome(8, 9, shared_action),
        outcome(9, 20, outlier_action),
    ];

    let selected = select_lazy_smp_outcome(&outcomes);

    assert_eq!(selected.result.best_action, shared_action);
    assert_eq!(selected.result.score, 10);
}

#[test]
fn lazy_smp_selection_uses_matching_root_summary_score() {
    let action = Action {
        kind_tag: MillActionKind::Move as i16,
        from_node: 0,
        to_node: 1,
        aux: -1,
        payload_bits: 0,
    };
    let outcome = |root_value| LazySmpWorkerOutcome {
        depth: 8,
        result: SearchResult {
            best_action: action,
            score: 10,
            nodes: 1,
            draw_reason: None,
        },
        root_moves: vec![RootMoveSummary {
            action,
            value: root_value,
            nodes: 1,
            cutoff: false,
        }],
    };
    let outcomes = [outcome(30), outcome(20)];

    assert_eq!(lazy_smp_outcome_vote_action(&outcomes[0]), action);
    assert_eq!(lazy_smp_vote_score(&outcomes[0]), 30);
    assert!(
        lazy_smp_thread_vote_weight(&outcomes, &outcomes[0])
            > lazy_smp_thread_vote_weight(&outcomes, &outcomes[1])
    );
}

#[test]
fn lazy_smp_selection_ignores_mismatched_root_summary_action() {
    let reported_action = Action {
        kind_tag: MillActionKind::Move as i16,
        from_node: 0,
        to_node: 1,
        aux: -1,
        payload_bits: 0,
    };
    let mismatched_root_action = Action {
        kind_tag: MillActionKind::Move as i16,
        from_node: 2,
        to_node: 3,
        aux: -1,
        payload_bits: 0,
    };
    let outcome = |best_action, root_action| LazySmpWorkerOutcome {
        depth: 8,
        result: SearchResult {
            best_action,
            score: 10,
            nodes: 1,
            draw_reason: None,
        },
        root_moves: vec![RootMoveSummary {
            action: root_action,
            value: 50,
            nodes: 1,
            cutoff: false,
        }],
    };
    let outcomes = [outcome(reported_action, mismatched_root_action)];

    assert_eq!(lazy_smp_outcome_vote_action(&outcomes[0]), reported_action);
    assert_eq!(lazy_smp_vote_score(&outcomes[0]), 10);
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
fn mtdf_initial_guess_requires_matching_side_to_move() {
    let cfg = EngineConfig {
        last_best_value: 18,
        last_best_value_side_to_move: 0,
        ..EngineConfig::default()
    };

    assert_eq!(mtdf_initial_guess(&cfg, 0), 18);
    assert_eq!(mtdf_initial_guess(&cfg, 1), 0);
}

#[test]
fn parse_mtdf_debug_command_accepts_optional_first_guess() {
    assert_eq!(parse_mtdf_debug_command("gomtdf"), (15, 0));
    assert_eq!(parse_mtdf_debug_command("gomtdf 10"), (10, 0));
    assert_eq!(parse_mtdf_debug_command("gomtdf 10 18"), (10, 18));
}

#[test]
fn setoption_movetime_stores_seconds_as_ms_and_movetimems_stores_ms_directly() {
    let mut options = MillVariantOptions::default();
    let mut threads = 1;
    let mut qsearch = 0;
    let mut ecfg = EngineConfig::default();

    // Legacy MoveTime (seconds): "5" must be stored as 5000 ms.
    assert_eq!(
        apply_setoption(
            "setoption name MoveTime value 5",
            &mut options,
            &mut threads,
            &mut qsearch,
            &mut ecfg,
        ),
        SetoptionResult::SearchConfig
    );
    assert_eq!(ecfg.move_time_ms, 5000, "MoveTime 5 must store 5000 ms");

    // MoveTimeMs (milliseconds direct): "200" must be stored as 200 ms.
    assert_eq!(
        apply_setoption(
            "setoption name MoveTimeMs value 200",
            &mut options,
            &mut threads,
            &mut qsearch,
            &mut ecfg,
        ),
        SetoptionResult::SearchConfig
    );
    assert_eq!(ecfg.move_time_ms, 200, "MoveTimeMs 200 must store 200 ms");

    // MoveTime 0 must store 0 ms (no time limit).
    apply_setoption(
        "setoption name MoveTime value 0",
        &mut options,
        &mut threads,
        &mut qsearch,
        &mut ecfg,
    );
    assert_eq!(ecfg.move_time_ms, 0);

    // MoveTimeMs out of range (> 60000) must be rejected.
    let prev = ecfg.move_time_ms;
    assert_eq!(
        apply_setoption(
            "setoption name MoveTimeMs value 60001",
            &mut options,
            &mut threads,
            &mut qsearch,
            &mut ecfg,
        ),
        SetoptionResult::Unknown
    );
    assert_eq!(
        ecfg.move_time_ms, prev,
        "out-of-range must not change value"
    );
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
    assert!(!lazy_smp_is_allowed(&cfg, 4));

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
    assert!(!lazy_smp_is_allowed(&cfg, 1));
    assert!(lazy_smp_is_allowed(&cfg, 4));
}

#[test]
fn lazy_smp_requires_move_randomly_for_bestmove_stability() {
    let mut cfg = EngineConfig {
        use_lazy_smp: true,
        shuffling: false,
        ..EngineConfig::default()
    };

    assert!(
        !lazy_smp_is_allowed(&cfg, 4),
        "Move randomly off requires deterministic single-thread search"
    );

    cfg.shuffling = true;
    assert!(lazy_smp_is_allowed(&cfg, 4));
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
            topn_request: None,
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
        topn_request: None,
    };

    assert_eq!(
        format_spawn_result(&spawn),
        "info depth 2 score cp 0 nodes 0 bestmove draw"
    );
}
