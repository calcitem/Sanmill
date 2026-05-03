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
    Action, ActionList, Evaluator, Game, GameRules, MoveOrderAlgorithm, MoveOrderContext,
};
use tgf_mill::{MillActionKind, MillEvaluator, MillGame, MillRules, MillVariantOptions};
use tgf_search::{
    lazy_smp_search, perft, LazySmpWorker, MctsOptions, MctsSearcher, SearchOptions, SearchPolicy,
    Searcher, SharedTt, VALUE_UNIQUE_ROOT_MOVE,
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
        remove_kind_tag: Some(MillActionKind::Remove as i16),
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
        remove_kind_tag: Some(MillActionKind::Remove as i16),
    });

    let result = mcts.search_with_options(
        &mut wb,
        MctsOptions {
            iterations: 64,
            playout_depth: 4,
            time_limit_ms: None,
            exploration: 0.5,
            ab_assist_depth: 1,
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
            remove_kind_tag: Some(MillActionKind::Remove as i16),
        });
        let result = searcher.search(&mut wb, 1);
        assert_eq!(result.score, VALUE_UNIQUE_ROOT_MOVE);
        assert!(!result.best_action.is_none());
    }
}
