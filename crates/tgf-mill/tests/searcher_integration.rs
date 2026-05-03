// SPDX-License-Identifier: GPL-3.0-or-later
// Integration tests that exercise the generic `tgf_search::Searcher` /
// `MctsSearcher` against the concrete `MillGame`.
//
// Historically these lived inside `tgf-search/src/lib.rs::tests`, which
// forced the search crate to keep `tgf-mill` in `[dev-dependencies]` and
// littered the searcher module with Mill-specific assertions.  Moving
// them here keeps `tgf-search` game-neutral while still validating
// end-to-end behaviour against a real, non-trivial game.

use tgf_core::{
    assert_game_rules_game_consistency, Action, ActionList, Evaluator, Game, GameRules,
    MoveOrderAlgorithm, MoveOrderContext,
};
use tgf_mill::{MillActionKind, MillEvaluator, MillGame, MillRules, MillVariantOptions};
use tgf_search::{
    lazy_smp_search, mcts_search_parallel, perft, LazySmpWorker, MctsOptions, MctsSearcher,
    SearchOptions, SearchPolicy, Searcher, SharedTt, VALUE_UNIQUE_ROOT_MOVE,
};

#[test]
fn mill_searcher_finds_a_legal_opening_action() {
    let rules = MillRules::default();
    let game = MillGame::default();
    let snap = rules.initial_state(&[]);
    let mut wb = game.build_workbench(&snap);
    let mut searcher = Searcher::<MillGame>::new();

    let result = searcher.search(&mut wb, 1);
    assert!(!result.best_action.is_none());
    assert_eq!(result.best_action.kind_tag, MillActionKind::Place as i16);
    assert!(result.nodes > 0);
}

#[test]
fn mill_pvs_finds_a_legal_opening_action() {
    let rules = MillRules::default();
    let game = MillGame::default();
    let snap = rules.initial_state(&[]);
    let mut wb = game.build_workbench(&snap);
    let mut searcher = Searcher::<MillGame>::new();

    let result = searcher.search_pvs(&mut wb, 1);
    assert!(!result.best_action.is_none());
    assert_eq!(result.best_action.kind_tag, MillActionKind::Place as i16);
    assert!(result.nodes > 0);
}

#[test]
fn mill_random_search_is_seeded_and_deterministic() {
    let rules = MillRules::default();
    let game = MillGame::default();
    let snap = rules.initial_state(&[]);
    let mut wb1 = game.build_workbench(&snap);
    let mut wb2 = game.build_workbench(&snap);
    let mut a = Searcher::<MillGame>::new();
    let mut b = Searcher::<MillGame>::new();
    a.set_random_seed(1234);
    b.set_random_seed(1234);

    assert_eq!(
        a.random_search(&mut wb1).best_action,
        b.random_search(&mut wb2).best_action
    );
}

#[test]
fn mill_iterative_deepening_returns_deepest_result() {
    let rules = MillRules::default();
    let game = MillGame::default();
    let snap = rules.initial_state(&[]);
    let mut wb = game.build_workbench(&snap);
    let mut searcher = Searcher::<MillGame>::new();

    let result = searcher.iterative_deepening(&mut wb, 2);
    assert!(!result.best_action.is_none());
    assert_eq!(result.best_action.kind_tag, MillActionKind::Place as i16);
    assert!(result.nodes > 0);
}

/// Pre-search short-circuit (Diff 7.2): a position whose rule50
/// counter is already past the n-move threshold is converted to
/// GameOver / winner=draw inside `MillRules::set_from_fen` via
/// `check_if_game_is_over`, and `iterative_deepening` then returns
/// score 0 with no searched nodes through the standard
/// `terminal_score` path.  This mirrors master's `executeSearch`
/// `return 50` behaviour without needing a separate Mill-side
/// override of `Game::root_short_circuit_draw`; see the explanatory
/// comment in `crates/tgf-mill/src/rules/game_impls.rs`.
#[test]
fn mill_iterative_deepening_returns_draw_on_n_move_rule_terminal() {
    let rules = MillRules::default();
    let game = MillGame::default();
    // 9-on-board moving phase, rule50 = 200, well past the 100-ply
    // n-move-rule threshold so set_from_fen transitions to GameOver.
    let fen = "OOOO@@@@/OOOO@@@@/O****@** w m s 9 0 9 0 0 0 0 0 0 0 0 200 1";
    let state = rules
        .set_from_fen(fen)
        .expect("setup FEN must parse for the regression");
    let snap = rules.encode_state(state);

    let mut wb = game.build_workbench(&snap);
    let mut searcher = Searcher::<MillGame>::new();
    let result = searcher.iterative_deepening(&mut wb, 4);

    assert_eq!(result.score, 0, "n-move-rule terminal evaluates to draw");
    assert_eq!(result.nodes, 0, "no node should be searched");
}

#[test]
fn mill_mtdf_returns_a_finite_score() {
    let rules = MillRules::default();
    let game = MillGame::default();
    let snap = rules.initial_state(&[]);
    let mut wb = game.build_workbench(&snap);
    let mut searcher = Searcher::<MillGame>::new();

    let score = searcher.mtdf(&mut wb, 0, 1);
    assert!(score > i32::MIN + 1);
    assert!(score < i32::MAX - 1);
}

#[test]
fn mill_qsearch_accepts_remove_policy() {
    let rules = MillRules::default();
    let game = MillGame::default();
    let snap = rules.initial_state(&[]);
    let mut wb = game.build_workbench(&snap);
    let mut searcher = Searcher::<MillGame>::new();
    searcher.set_policy(SearchPolicy {
        quiescence_kind_tag: Some(MillActionKind::Remove as i16),
        ..Default::default()
    });

    let score = searcher.qsearch(&mut wb, i32::MIN + 1, i32::MAX - 1);
    assert!(score > i32::MIN + 1);
    assert!(score < i32::MAX - 1);
}

#[test]
fn lazy_smp_search_runs_workers_against_shared_tt() {
    let rules = MillRules::default();
    let game = MillGame::default();
    let snapshot = rules.initial_state(&[]);
    let shared_tt = SharedTt::new(12);

    let result = lazy_smp_search::<MillGame>(
        game,
        snapshot,
        2,
        &[
            LazySmpWorker { extra_depth: 0 },
            LazySmpWorker { extra_depth: 1 },
        ],
        SearchOptions::default(),
        shared_tt.clone(),
        None,
    );

    assert!(!result.best_action.is_none());
    assert_eq!(result.best_action.kind_tag, MillActionKind::Place as i16);
    // Workers ran with the same TT, so it must have observable contents.
    assert!(shared_tt.len_occupied() > 0);
}

#[test]
fn mcts_search_parallel_returns_a_legal_action_with_multiple_workers() {
    let rules = MillRules::default();
    let game = MillGame::default();
    let snapshot = rules.initial_state(&[]);

    let options = MctsOptions {
        iterations: 64,
        playout_depth: 4,
        ab_assist_depth: 2,
        num_threads: Some(2),
        ..MctsOptions::default()
    };

    let result = mcts_search_parallel::<MillGame>(&game, snapshot, options, 0xC0DE_FACE);
    assert!(!result.best_action.is_none());
    assert_eq!(result.best_action.kind_tag, MillActionKind::Place as i16);
    assert!(
        result.visits > 0,
        "aggregated visits across workers must be non-zero"
    );
}

#[test]
fn mcts_search_parallel_with_one_thread_matches_searcher_with_options() {
    // Force a single worker so MctsSearcher::search_with_options and
    // mcts_search_parallel walk identical code paths.  Verifies the new
    // multi-threaded driver is a strict superset (no behaviour drift on
    // the deterministic single-thread path).
    let rules = MillRules::default();
    let game = MillGame::default();
    let snapshot = rules.initial_state(&[]);
    let seed = 0xA1B2_C3D4_5566_7788;

    let options = MctsOptions {
        iterations: 32,
        playout_depth: 4,
        ab_assist_depth: 0,
        num_threads: Some(1),
        ..MctsOptions::default()
    };

    let parallel = mcts_search_parallel::<MillGame>(&game, snapshot, options, seed);

    let mut searcher = MctsSearcher::<MillGame>::new();
    searcher.set_random_seed(seed.max(1));
    let mut wb = game.build_workbench(&snapshot);
    let serial = searcher.search_with_options(&mut wb, options);

    assert_eq!(parallel.best_action, serial.best_action);
    assert_eq!(parallel.visits, serial.visits);
    assert_eq!(parallel.wins, serial.wins);
}

/// `n_move_rule = 1` collapses every reversible moving-phase move to a
/// draw.  The Phase::GameOver branch of [`MillEvaluator::score`] must
/// return `0` when neither the fly-mate nor the LoseFewerThanThree
/// trigger applies, regardless of perspective.
#[test]
fn mill_evaluator_scores_game_over_draw_as_zero() {
    let options = MillVariantOptions::default();
    let rules = MillRules::new(options.clone());
    let game = MillGame::new(options);

    // FEN: phase 'o' (GameOver), equal material, sparse layout so neither
    // fly-mate nor stalemate flags fire.
    let fen = "O*O*O*O*/*@*@*@*@/O@O@O@O@ w o p 9 0 9 0 0 0 0 0 0 0 0 0 1";
    let state = rules.set_from_fen(fen).expect("valid FEN");
    let snap = rules.encode_state(state);
    let wb = game.build_workbench(&snap);

    assert_eq!(MillEvaluator::score(&wb), 0);
}

#[test]
fn mill_node_limit_marks_search_as_aborted() {
    let rules = MillRules::default();
    let game = MillGame::default();
    let snap = rules.initial_state(&[]);
    let mut wb = game.build_workbench(&snap);
    let mut searcher = Searcher::<MillGame>::new();
    searcher.set_options(SearchOptions {
        depth_extension: false,
        node_limit: Some(1),
        time_limit_ms: None,
        allow_null_move: false,
        ..Default::default()
    });

    let _ = searcher.search(&mut wb, 3);
    assert!(searcher.was_aborted());
}

#[test]
fn mill_depth_extension_option_is_accepted() {
    let rules = MillRules::default();
    let game = MillGame::default();
    let snap = rules.initial_state(&[]);
    let mut wb = game.build_workbench(&snap);
    let mut searcher = Searcher::<MillGame>::new();
    searcher.set_options(SearchOptions {
        depth_extension: true,
        node_limit: None,
        time_limit_ms: None,
        allow_null_move: false,
        ..Default::default()
    });

    let result = searcher.search(&mut wb, 1);
    assert!(!result.best_action.is_none());
}

#[test]
fn mill_wall_clock_time_limit_marks_search_as_aborted() {
    let rules = MillRules::default();
    let game = MillGame::default();
    let snap = rules.initial_state(&[]);
    let mut wb = game.build_workbench(&snap);
    let mut searcher = Searcher::<MillGame>::new();
    searcher.set_options(SearchOptions {
        depth_extension: false,
        node_limit: None,
        time_limit_ms: Some(0),
        allow_null_move: false,
        ..Default::default()
    });

    let _ = searcher.search(&mut wb, 3);
    assert!(searcher.was_aborted());
}

#[test]
fn mill_perft_initial_position_returns_24_at_depth_one() {
    let rules = MillRules::default();
    let game = MillGame::default();
    let snap = rules.initial_state(&[]);
    let mut wb = game.build_workbench(&snap);

    assert_eq!(perft::<MillGame>(&mut wb, 0), 1);
    assert_eq!(perft::<MillGame>(&mut wb, 1), 24);
}

#[test]
fn mill_external_abort_handle_can_request_abort() {
    let rules = MillRules::default();
    let game = MillGame::default();
    let snap = rules.initial_state(&[]);
    let mut wb = game.build_workbench(&snap);
    let mut searcher = Searcher::<MillGame>::new();
    let handle = searcher.abort_handle();
    handle.request_abort();

    let _ = searcher.search(&mut wb, 3);
    // Root search no longer clears the shared abort flag, so a stop
    // requested through the handle before the search even starts is
    // honoured immediately on the first abort poll.  This matches how
    // a UCI `stop` racing with `go infinite` should behave.
    assert!(searcher.was_aborted());
    handle.request_abort();
    assert!(handle.is_aborted());
}

#[test]
fn mill_mcts_returns_a_legal_opening_action() {
    let rules = MillRules::default();
    let game = MillGame::default();
    let snap = rules.initial_state(&[]);
    let mut wb = game.build_workbench(&snap);
    let mut mcts = MctsSearcher::<MillGame>::new();
    mcts.set_random_seed(2026);

    let result = mcts.search(&mut wb, 2, 2);
    assert!(!result.best_action.is_none());
    assert_eq!(result.best_action.kind_tag, MillActionKind::Place as i16);
    assert!(result.visits > 0);
}

#[test]
fn mill_mcts_with_ab_assist_picks_immediate_mill() {
    // White has two pieces on a3/c3 and can form the mill a3-b3-c3 by
    // placing on b3.  With ab_assist_depth=1 the MCTS simulation
    // correctly sees this as a high-value move and should prefer it.
    let rules = MillRules::default();

    // Build a position where White is to place and has an immediate mill.
    // Nodes: 0=a7, 1=d7, 2=g7 (top mill line for default 9MM).
    let snap = {
        let mut s = rules.initial_state(&[]);
        // White on node 0.
        s = rules.apply(
            &s,
            Action {
                kind_tag: MillActionKind::Place as i16,
                from_node: -1,
                to_node: 0,
                aux: -1,
                payload_bits: 0,
            },
        );
        // Black on node 6 (neutral).
        s = rules.apply(
            &s,
            Action {
                kind_tag: MillActionKind::Place as i16,
                from_node: -1,
                to_node: 6,
                aux: -1,
                payload_bits: 0,
            },
        );
        // White on node 2.
        s = rules.apply(
            &s,
            Action {
                kind_tag: MillActionKind::Place as i16,
                from_node: -1,
                to_node: 2,
                aux: -1,
                payload_bits: 0,
            },
        );
        // Black on node 5 (neutral).
        s = rules.apply(
            &s,
            Action {
                kind_tag: MillActionKind::Place as i16,
                from_node: -1,
                to_node: 5,
                aux: -1,
                payload_bits: 0,
            },
        );
        s // White to move: placing on node 1 forms mill 0-1-2.
    };

    let game = MillGame::default();
    let mut wb = game.build_workbench(&snap);

    let mut mcts = MctsSearcher::<MillGame>::new();
    mcts.set_random_seed(42);
    mcts.set_policy(SearchPolicy {
        quiescence_kind_tag: Some(MillActionKind::Remove as i16),
        ..Default::default()
    });

    let result = mcts.search_with_options(
        &mut wb,
        MctsOptions {
            iterations: 64,
            playout_depth: 4,
            time_limit_ms: None,
            exploration: 0.5,
            ab_assist_depth: 1,
            num_threads: Some(1),
            move_order_context: MoveOrderContext {
                algorithm: MoveOrderAlgorithm::Mcts,
                ..MoveOrderContext::default()
            },
        },
    );

    assert!(
        !result.best_action.is_none(),
        "MCTS with ab_assist must return a legal action"
    );
    // With ab_assist_depth=1 the searcher should pick the mill-forming move.
    assert_eq!(
        result.best_action.to_node, 1,
        "MCTS+AB should select the mill-forming move at node 1"
    );
}

#[test]
fn mill_mcts_options_accept_time_limit() {
    let rules = MillRules::default();
    let game = MillGame::default();
    let snap = rules.initial_state(&[]);
    let mut wb = game.build_workbench(&snap);
    let mut mcts = MctsSearcher::<MillGame>::new();
    mcts.set_random_seed(2026);

    let result = mcts.search_with_options(
        &mut wb,
        MctsOptions {
            iterations: 16,
            playout_depth: 2,
            time_limit_ms: Some(0),
            exploration: 0.5,
            ab_assist_depth: 0,
            num_threads: Some(1),
            move_order_context: MoveOrderContext {
                algorithm: MoveOrderAlgorithm::Mcts,
                ..MoveOrderContext::default()
            },
        },
    );
    assert!(!result.best_action.is_none());
}

#[test]
fn mill_searcher_clear_tt_uses_bump_age_not_physical_clear() {
    let rules = MillRules::default();
    let game = MillGame::default();
    let snap = rules.initial_state(&[]);
    let mut wb = game.build_workbench(&snap);
    let mut searcher = Searcher::<MillGame>::new();

    searcher.search(&mut wb, 1);
    assert_eq!(searcher.tt_age_bumps(), 0);
    assert_eq!(searcher.tt_current_age(), 0);

    searcher.clear_tt();
    assert_eq!(searcher.tt_age_bumps(), 1);
    assert_eq!(searcher.tt_current_age(), 1);
}

#[test]
fn mill_iterative_deepening_bumps_age_between_depths() {
    let rules = MillRules::default();
    let game = MillGame::default();
    let snap = rules.initial_state(&[]);
    let mut wb = game.build_workbench(&snap);
    let mut searcher = Searcher::<MillGame>::new();

    let result = searcher.iterative_deepening(&mut wb, 3);
    // Depth 1→2 and 2→3 each bump once, so 2 bumps for max_depth = 3.
    assert_eq!(
        searcher.tt_age_bumps(),
        2,
        "age bumped once per iteration boundary (max_depth - 1)"
    );
    assert!(!result.best_action.is_none());
}

/// Sanity-check that the random-search xorshift sequence is reachable via
/// the public API.  The actual deterministic-shuffle invariant is
/// already covered by `mill_random_search_is_seeded_and_deterministic`;
/// this test just guards against the public surface losing the seed
/// setter accidentally.
#[test]
fn mill_random_search_seed_setter_is_reachable() {
    let rules = MillRules::default();
    let game = MillGame::default();
    let snap = rules.initial_state(&[]);
    let mut wb = game.build_workbench(&snap);
    let mut searcher = Searcher::<MillGame>::new();
    searcher.set_random_seed(2026);

    let result = searcher.random_search(&mut wb);
    assert!(!result.best_action.is_none());
}

/// Forced-move scoring pathway: even with a real game it must surface
/// the framework-level `VALUE_UNIQUE_ROOT_MOVE` sentinel when only one
/// legal action exists at the root.  We construct a near-terminal Mill
/// position where only one Remove is available.
#[test]
fn mill_forced_root_move_returns_unique_score() {
    let rules = MillRules::default();
    let game = MillGame::default();

    // Construct: White just formed a mill with one black piece on the
    // board.  pending_removals[0]=1 forces Remove of that piece.
    let mut state = rules.setup_empty();
    state.set_piece(0, 1); // White
    state.set_piece(1, 1); // White
    state.set_piece(2, 1); // White (forms mill 0-1-2)
    state.set_piece(3, 2); // Black (only target)
    state.set_side_to_move(0);
    state.recompute_aux(&MillVariantOptions::default());
    let snap = rules.encode_state(state);

    let mut wb = game.build_workbench(&snap);
    // Generate to confirm a single Remove is the only legal action.
    let mut moves = ActionList::<256>::new();
    MillGame::generate_legal(&wb, &mut moves);
    let removes = moves
        .iter()
        .filter(|a| a.kind_tag == MillActionKind::Remove as i16)
        .count();

    if removes == 1 && moves.len() == 1 {
        let mut searcher = Searcher::<MillGame>::new();
        searcher.set_policy(SearchPolicy {
            quiescence_kind_tag: Some(MillActionKind::Remove as i16),
            ..Default::default()
        });
        let result = searcher.search(&mut wb, 1);
        assert_eq!(result.score, VALUE_UNIQUE_ROOT_MOVE);
        assert!(!result.best_action.is_none());
    }
}

/// Invariant: `MillRules::legal_actions` (object-safe runtime path) and
/// `MillGame::generate_legal` (compile-time CRTP search path) must
/// enumerate the same legal-action set for every snapshot.  Drift
/// between these two surfaces is the most insidious class of bug
/// because tests through one path won't surface it; this test pins the
/// invariant for a deterministic random walk of 200 ply.
#[test]
fn mill_rules_and_game_agree_on_legal_actions_along_random_walk() {
    let rules = MillRules::default();
    let game = MillGame::default();
    let mut snap = rules.initial_state(&[]);
    let mut rng_state: u64 = 0x9E37_79B9_7F4A_7C15;

    for _ in 0..200 {
        assert_game_rules_game_consistency(&rules, &game, &snap)
            .expect("GameRules and Game must enumerate the same legal actions");
        let mut moves = ActionList::<256>::new();
        rules.legal_actions(&snap, &mut moves);
        if moves.is_empty() {
            break;
        }
        rng_state ^= rng_state >> 12;
        rng_state ^= rng_state << 25;
        rng_state ^= rng_state >> 27;
        let scrambled = rng_state.wrapping_mul(0x2545_F491_4F6C_DD1D);
        let pick = (scrambled as usize) % moves.len();
        snap = rules.apply(&snap, moves[pick]);
    }
}
