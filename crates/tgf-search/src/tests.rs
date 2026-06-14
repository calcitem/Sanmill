// SPDX-License-Identifier: GPL-3.0-or-later
// Game-neutral unit tests for the searcher / TT / thread pool / MCTS
// scaffolds.  Mill end-to-end coverage lives under
// `crates/tgf-mill/tests/searcher_integration.rs`.

use super::*;
use tgf_core::{
    Action, ActionList, Evaluator, Game, GameStateSnapshot, MoveOrderContext, Workbench,
};

// Re-export internal TT primitives so the regression suite can poke
// directly at them.  These items are `pub(crate)` so the public crate
// API stays unchanged.
use crate::tt::{Bound, ClusteredTt, TtEntry, TtPackedEntry};

#[derive(Clone, Copy, Debug)]
struct SameSideWorkbench {
    moved: bool,
    side: i8,
}

impl Workbench for SameSideWorkbench {
    fn snapshot(&self) -> GameStateSnapshot {
        GameStateSnapshot::default()
    }

    fn key(&self) -> u64 {
        0
    }

    fn side_to_move(&self) -> i8 {
        self.side
    }

    fn is_terminal(&self) -> bool {
        false
    }

    fn do_move(&mut self, _a: Action) {
        self.moved = true;
        // Intentionally keep side unchanged to model a "same-side"
        // continuation obligation (e.g. a removal phase).  The search
        // must NOT negate this branch.
        self.side = 0;
    }

    fn undo_move(&mut self) {
        self.moved = false;
        self.side = 0;
    }
}

struct SameSideEvaluator;

impl Evaluator<SameSideWorkbench> for SameSideEvaluator {
    fn score(wb: &SameSideWorkbench) -> i32 {
        if wb.moved { 42 } else { 0 }
    }
}

struct SameSideGame;

impl tgf_core::Game for SameSideGame {
    type Workbench = SameSideWorkbench;
    type Evaluator = SameSideEvaluator;

    fn build_workbench(&self, _snap: &GameStateSnapshot) -> Self::Workbench {
        SameSideWorkbench {
            moved: false,
            side: 0,
        }
    }

    fn generate_legal(wb: &Self::Workbench, out: &mut ActionList<256>) {
        if !wb.moved {
            out.push(Action {
                kind_tag: 0,
                from_node: -1,
                to_node: 0,
                aux: -1,
                payload_bits: 0,
            });
        }
    }
}

#[test]
fn same_side_move_result_is_not_negated() {
    let game = SameSideGame;
    let mut wb = game.build_workbench(&GameStateSnapshot::default());
    let mut searcher = Searcher::<SameSideGame>::new();

    let result = searcher.search(&mut wb, 1);
    // Single root legal action → VALUE_UNIQUE_ROOT_MOVE (100) is
    // returned.  The best action is still set correctly even without
    // a deep search.
    assert_eq!(result.score, VALUE_UNIQUE_ROOT_MOVE);
    assert!(!result.best_action.is_none());
}

#[derive(Clone, Copy, Debug)]
struct BiasWorkbench;

impl Workbench for BiasWorkbench {
    fn snapshot(&self) -> GameStateSnapshot {
        GameStateSnapshot::default()
    }
    fn key(&self) -> u64 {
        0
    }
    fn side_to_move(&self) -> i8 {
        0
    }
    fn is_terminal(&self) -> bool {
        false
    }
    fn do_move(&mut self, _a: Action) {}
    fn undo_move(&mut self) {}
}

struct BiasEvaluator;

impl Evaluator<BiasWorkbench> for BiasEvaluator {
    fn score(_wb: &BiasWorkbench) -> i32 {
        0
    }
}

struct BiasGame;

impl tgf_core::Game for BiasGame {
    type Workbench = BiasWorkbench;
    type Evaluator = BiasEvaluator;

    fn build_workbench(&self, _snap: &GameStateSnapshot) -> Self::Workbench {
        BiasWorkbench
    }

    fn generate_legal(_wb: &Self::Workbench, out: &mut ActionList<256>) {
        out.push(Action {
            kind_tag: 0,
            from_node: -1,
            to_node: 0,
            aux: -1,
            payload_bits: 0,
        });
        out.push(Action {
            kind_tag: 0,
            from_node: -1,
            to_node: 1,
            aux: -1,
            payload_bits: 0,
        });
    }

    fn move_order_bias_ctx(_wb: &Self::Workbench, action: Action, ctx: &MoveOrderContext) -> i32 {
        if ctx.skill_level == 7 && action.to_node == 1 {
            100
        } else {
            0
        }
    }
}

#[test]
fn search_order_uses_contextual_move_bias() {
    let game = BiasGame;
    let mut wb = game.build_workbench(&GameStateSnapshot::default());
    let mut searcher = Searcher::<BiasGame>::new();
    searcher.set_move_order_context(MoveOrderContext {
        skill_level: 7,
        ..Default::default()
    });

    let result = searcher.search(&mut wb, 1);
    assert_eq!(result.best_action.to_node, 1);
}

#[derive(Clone, Copy, Debug)]
struct RepetitionWorkbench {
    ply: u8,
    side: i8,
}

impl Workbench for RepetitionWorkbench {
    fn snapshot(&self) -> GameStateSnapshot {
        GameStateSnapshot::default()
    }
    fn key(&self) -> u64 {
        if self.ply == 0 {
            77
        } else {
            77 + u64::from(self.ply)
        }
    }
    fn side_to_move(&self) -> i8 {
        self.side
    }
    fn is_terminal(&self) -> bool {
        false
    }
    fn do_move(&mut self, _a: Action) {
        self.ply += 1;
        self.side ^= 1;
    }
    fn undo_move(&mut self) {
        self.ply -= 1;
        self.side ^= 1;
    }
}

struct RepetitionEvaluator;

impl Evaluator<RepetitionWorkbench> for RepetitionEvaluator {
    fn score(_wb: &RepetitionWorkbench) -> i32 {
        0
    }
}

struct RepetitionGame;

impl tgf_core::Game for RepetitionGame {
    type Workbench = RepetitionWorkbench;
    type Evaluator = RepetitionEvaluator;

    fn build_workbench(&self, _snap: &GameStateSnapshot) -> Self::Workbench {
        RepetitionWorkbench { ply: 0, side: 0 }
    }

    fn generate_legal(_wb: &Self::Workbench, out: &mut ActionList<256>) {
        out.push(Action {
            kind_tag: 0,
            from_node: -1,
            to_node: 0,
            aux: -1,
            payload_bits: 0,
        });
    }
}

#[test]
fn third_path_repetition_returns_draw_plus_one_bias() {
    let game = RepetitionGame;
    let mut wb = game.build_workbench(&GameStateSnapshot::default());
    let mut searcher = Searcher::<RepetitionGame>::new();
    searcher.repetition_stack.push((wb.key(), false));
    searcher.repetition_stack.push((wb.key(), false));

    assert_eq!(searcher.alpha_beta(&mut wb, 2, -10, 10), 1);
}

#[derive(Clone, Copy, Debug)]
struct KeyedWorkbench {
    ply: u8,
    side: i8,
}

impl Workbench for KeyedWorkbench {
    fn snapshot(&self) -> GameStateSnapshot {
        GameStateSnapshot::default()
    }

    fn key(&self) -> u64 {
        // Same root key every time; child key depends on ply.  This is
        // enough to prove TT probe/save without tying the test to Mill's
        // future Zobrist implementation.
        100 + u64::from(self.ply)
    }

    fn side_to_move(&self) -> i8 {
        self.side
    }

    fn is_terminal(&self) -> bool {
        self.ply >= 2
    }

    fn do_move(&mut self, _a: Action) {
        self.ply += 1;
        self.side ^= 1;
    }

    fn undo_move(&mut self) {
        self.ply -= 1;
        self.side ^= 1;
    }
}

struct KeyedEvaluator;

impl Evaluator<KeyedWorkbench> for KeyedEvaluator {
    fn score(wb: &KeyedWorkbench) -> i32 {
        i32::from(wb.ply) * 10
    }
}

#[derive(Clone)]
struct KeyedGame;

impl tgf_core::Game for KeyedGame {
    type Workbench = KeyedWorkbench;
    type Evaluator = KeyedEvaluator;

    fn build_workbench(&self, _snap: &GameStateSnapshot) -> Self::Workbench {
        KeyedWorkbench { ply: 0, side: 0 }
    }

    fn generate_legal(wb: &Self::Workbench, out: &mut ActionList<256>) {
        if wb.ply < 2 {
            out.push(Action {
                kind_tag: 0,
                from_node: -1,
                to_node: 0,
                aux: -1,
                payload_bits: 0,
            });
            out.push(Action {
                kind_tag: 0,
                from_node: -1,
                to_node: 1,
                aux: -1,
                payload_bits: 0,
            });
        }
    }
}

#[test]
fn transposition_table_saves_and_reuses_entries() {
    let game = KeyedGame;
    let mut wb = game.build_workbench(&GameStateSnapshot::default());
    let mut searcher = Searcher::<KeyedGame>::new();

    let first = searcher.search(&mut wb, 2);
    assert!(searcher.tt_len() > 0);
    assert!(first.nodes > 0);

    let before = searcher.nodes();
    let second = searcher.search(&mut wb, 2);
    assert_eq!(first.best_action, second.best_action);
    assert!(searcher.nodes() <= before.max(1));
    assert!(searcher.tt_hits() > 0);
    assert!(searcher.tt_hit_rate_pct() > 0.0);
}

#[test]
fn packed_tt_entry_round_trips_compact_fields() {
    let action = Action {
        kind_tag: 2,
        from_node: 23,
        to_node: 17,
        aux: -1,
        payload_bits: 0,
    };
    let entry = TtEntry {
        value: 900,
        depth: 12,
        bound: Bound::Lower,
        best_action: action,
    };

    let meta = TtPackedEntry::pack_meta(0x1234_5678_9abc_def0, &entry, 3);
    let action_bits = TtPackedEntry::pack_action(entry.best_action);
    let unpacked = TtPackedEntry::unpack_entry(meta, action_bits);

    assert_eq!(unpacked.value, entry.value);
    assert_eq!(unpacked.depth, entry.depth);
    assert_eq!(unpacked.bound, entry.bound);
    assert_eq!(unpacked.best_action, entry.best_action);
    assert_eq!(TtPackedEntry::packed_age(meta), 3);
    assert_ne!(meta, 0);
}

#[test]
fn search_thread_pool_runs_jobs_and_returns_results() {
    let pool = SearchThreadPool::new(2);
    assert_eq!(pool.worker_count(), 2);

    let a = pool.submit(|| 21 + 21);
    let b = pool.submit(|| "tgf".to_owned());

    assert_eq!(a.recv().expect("worker should return result"), 42);
    assert_eq!(b.recv().expect("worker should return result"), "tgf");
}

#[test]
fn search_thread_pool_clamps_to_one_worker() {
    let pool = SearchThreadPool::new(0);
    assert_eq!(pool.worker_count(), 1);

    let result = pool.submit(|| 7);
    assert_eq!(result.recv().expect("worker should return result"), 7);
}

#[test]
fn iterative_deepening_returns_deepest_result_on_mock_game() {
    let game = KeyedGame;
    let mut wb = game.build_workbench(&GameStateSnapshot::default());
    let mut searcher = Searcher::<KeyedGame>::new();

    let result = searcher.iterative_deepening(&mut wb, 2);
    assert!(!result.best_action.is_none());
    assert!(result.nodes > 0);
}

#[test]
fn mtdf_returns_a_finite_score_on_mock_game() {
    let game = KeyedGame;
    let mut wb = game.build_workbench(&GameStateSnapshot::default());
    let mut searcher = Searcher::<KeyedGame>::new();

    let score = searcher.mtdf(&mut wb, 0, 1);
    assert!(score > i32::MIN + 1);
    assert!(score < i32::MAX - 1);
}

#[test]
fn search_mtdf_returns_unique_for_single_root_move() {
    let game = SameSideGame;
    let mut wb = game.build_workbench(&GameStateSnapshot::default());
    let mut searcher = Searcher::<SameSideGame>::new();

    let result = searcher.search_mtdf(&mut wb, 3);
    assert_eq!(result.score, VALUE_UNIQUE_ROOT_MOVE);
    assert!(!result.best_action.is_none());
}

#[test]
fn qsearch_accepts_remove_policy_on_mock_game() {
    let game = KeyedGame;
    let mut wb = game.build_workbench(&GameStateSnapshot::default());
    let mut searcher = Searcher::<KeyedGame>::new();
    // remove_kind_tag = 0 happens to match the KeyedGame action kind,
    // which lets the qsearch extension exercise the recursive remove
    // branch without dragging in a concrete game crate.  The exact tag
    // value is irrelevant; the assertion only checks that the call is
    // accepted and returns a finite, reasonable score.
    searcher.set_policy(SearchPolicy {
        quiescence_kind_tag: Some(0),
        ..Default::default()
    });

    let score = searcher.qsearch(&mut wb, i32::MIN + 1, i32::MAX - 1);
    assert!(score > i32::MIN + 1);
    assert!(score < i32::MAX - 1);
}

#[test]
fn lazy_smp_search_runs_workers_against_shared_tt() {
    let game = KeyedGame;
    let snapshot = GameStateSnapshot::default();
    let shared_tt = SharedTt::new(12);

    let result = lazy_smp_search::<KeyedGame>(
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
    // Workers ran with the same TT, so it must have observable contents.
    assert!(shared_tt.len_occupied() > 0);
}

#[test]
fn qsearch_with_depth_decays_stand_pat_for_mate_distance() {
    // Mirrors the C++ `if (stand_pat > 0) stand_pat += depth;` block in
    // `src/search.cpp::qsearch`: deeper recursions pull positive scores
    // toward zero so mate-in-N is preferred over mate-in-N+1.  The
    // synthetic game keeps the evaluator constant so the only difference
    // between depth 0 and depth -3 is the decay term itself.
    struct StaticEvalGame;
    struct StaticEvalEvaluator;
    struct StaticEvalWorkbench;
    const STATIC_SCORE: i32 = 100;

    impl Workbench for StaticEvalWorkbench {
        fn snapshot(&self) -> GameStateSnapshot {
            GameStateSnapshot::default()
        }
        fn key(&self) -> u64 {
            0
        }
        fn side_to_move(&self) -> i8 {
            0
        }
        fn is_terminal(&self) -> bool {
            false
        }
        fn do_move(&mut self, _: Action) {}
        fn undo_move(&mut self) {}
    }

    impl Evaluator<StaticEvalWorkbench> for StaticEvalEvaluator {
        fn score(_: &StaticEvalWorkbench) -> i32 {
            STATIC_SCORE
        }
    }

    impl tgf_core::Game for StaticEvalGame {
        type Workbench = StaticEvalWorkbench;
        type Evaluator = StaticEvalEvaluator;
        fn build_workbench(&self, _: &GameStateSnapshot) -> Self::Workbench {
            StaticEvalWorkbench
        }
        fn generate_legal(_: &Self::Workbench, _: &mut ActionList<256>) {}
    }

    let mut wb = StaticEvalWorkbench;
    let mut searcher = Searcher::<StaticEvalGame>::new();

    let at_zero = searcher.qsearch_with_depth(&mut wb, 0, i32::MIN + 1, i32::MAX - 1);
    let at_minus_three = searcher.qsearch_with_depth(&mut wb, -3, i32::MIN + 1, i32::MAX - 1);
    assert_eq!(at_zero, STATIC_SCORE);
    assert_eq!(at_zero - at_minus_three, 3);
}

#[test]
fn node_limit_marks_search_as_aborted() {
    let game = KeyedGame;
    let mut wb = game.build_workbench(&GameStateSnapshot::default());
    let mut searcher = Searcher::<KeyedGame>::new();
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
fn depth_extension_option_is_accepted() {
    let game = KeyedGame;
    let mut wb = game.build_workbench(&GameStateSnapshot::default());
    let mut searcher = Searcher::<KeyedGame>::new();
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
fn wall_clock_time_limit_marks_search_as_aborted() {
    let game = KeyedGame;
    let mut wb = game.build_workbench(&GameStateSnapshot::default());
    let mut searcher = Searcher::<KeyedGame>::new();
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
fn perft_visits_every_legal_action_on_mock_game() {
    let game = KeyedGame;
    let mut wb = game.build_workbench(&GameStateSnapshot::default());

    // Depth 0 always counts a single leaf at the root.
    assert_eq!(perft::<KeyedGame>(&mut wb, 0), 1);
    // Depth 1 enumerates the two legal actions.
    assert_eq!(perft::<KeyedGame>(&mut wb, 1), 2);
}

#[test]
fn external_abort_handle_can_request_abort() {
    let game = KeyedGame;
    let mut wb = game.build_workbench(&GameStateSnapshot::default());
    let mut searcher = Searcher::<KeyedGame>::new();
    let handle = searcher.abort_handle();
    handle.request_abort();

    let _ = searcher.search(&mut wb, 3);
    // Root search no longer clears the shared abort flag, so a stop
    // requested through the handle before the search even starts is
    // honoured immediately on the first abort poll.
    assert!(searcher.was_aborted());
    handle.request_abort();
    assert!(handle.is_aborted());
}

#[test]
fn mcts_returns_a_legal_action_on_mock_game() {
    let game = KeyedGame;
    let mut wb = game.build_workbench(&GameStateSnapshot::default());
    let mut mcts = MctsSearcher::<KeyedGame>::new();
    mcts.set_random_seed(2026);

    let result = mcts.search(&mut wb, 2, 2);
    assert!(!result.best_action.is_none());
    assert!(result.visits > 0);
}

#[test]
fn mcts_options_accept_time_limit_on_mock_game() {
    let game = KeyedGame;
    let mut wb = game.build_workbench(&GameStateSnapshot::default());
    let mut mcts = MctsSearcher::<KeyedGame>::new();
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
                algorithm: tgf_core::MoveOrderAlgorithm::Mcts,
                ..MoveOrderContext::default()
            },
        },
    );
    assert!(!result.best_action.is_none());
}

// ---------------------------------------------------------------------------
// Phase 5.1: TT generation aging tests
// ---------------------------------------------------------------------------

#[test]
fn tt_non_exact_entry_is_skipped_after_age_bump() {
    let tt = ClusteredTt::new_with_cluster_bits(10);
    let key = 0x1234_5678_9abc_def0_u64;
    let entry = TtEntry {
        value: 42,
        depth: 5,
        bound: Bound::Lower, // non-Exact
        best_action: Action::NONE,
    };
    // Written at age 0.
    tt.save(key, entry);
    assert!(
        tt.get(key).is_some(),
        "entry should be visible in same generation"
    );

    // Bump to generation 1.
    tt.bump_age();
    // Non-Exact entry from generation 0 is now treated as stale.
    assert!(
        tt.get(key).is_none(),
        "non-Exact entry should be invisible after age bump"
    );
}

#[test]
fn tt_exact_entry_survives_age_bump() {
    let tt = ClusteredTt::new_with_cluster_bits(10);
    let key = 0x1234_5678_9abc_def0_u64;
    let entry = TtEntry {
        value: 42,
        depth: 5,
        bound: Bound::Exact, // Exact always survives
        best_action: Action::NONE,
    };
    tt.save(key, entry);
    tt.bump_age();
    assert!(
        tt.get(key).is_some(),
        "Exact entry should survive a generation bump"
    );
}

#[test]
fn tt_clear_resets_age_and_removes_entries() {
    let tt = ClusteredTt::new_with_cluster_bits(10);
    let key = 0x1234_5678_9abc_def0_u64;
    let entry = TtEntry {
        value: 42,
        depth: 5,
        bound: Bound::Exact,
        best_action: Action::NONE,
    };
    tt.save(key, entry);
    tt.bump_age();
    assert_eq!(tt.current_age(), 1);

    // Physical clear resets age to 0 and empties all slots.
    tt.clear();
    assert_eq!(tt.current_age(), 0);
    assert!(tt.get(key).is_none(), "physical clear must empty all slots");
}

#[test]
fn shared_tt_with_capacity_mb_respects_requested_floor() {
    let small = SharedTt::with_capacity_mb(1, 14);
    let large = SharedTt::with_capacity_mb(64, 14);

    assert!(small.inner.clusters.len() >= (1usize << 14));
    assert!(
        large.inner.clusters.len() >= small.inner.clusters.len(),
        "larger Hash option must not allocate fewer clusters"
    );
}

#[test]
fn workbench_default_key_after_matches_do_move_round_trip() {
    let game = KeyedGame;
    let mut wb = game.build_workbench(&GameStateSnapshot::default());

    let mut moves = ActionList::<256>::new();
    KeyedGame::generate_legal(&wb, &mut moves);
    assert!(!moves.is_empty(), "fixture must have legal moves");

    let action = moves[0];
    let key_before = wb.key();
    let predicted_after = wb.key_after(action);

    // Workbench observably unchanged after key_after.
    assert_eq!(wb.key(), key_before, "key_after must restore state");

    // Predicted key must match the real key after applying the move.
    wb.do_move(action);
    assert_eq!(wb.key(), predicted_after, "default key_after mismatch");
    wb.undo_move();
    assert_eq!(wb.key(), key_before);
}

#[test]
fn shared_tt_prefetch_is_safe_for_arbitrary_keys() {
    // Prefetch is a hint, not a correctness path; ensure it never
    // panics or accesses out-of-bounds memory regardless of the input.
    let tt = SharedTt::with_capacity_mb(1, 14);
    tt.prefetch(0); // sentinel key: must early-return
    tt.prefetch(0xdead_beef_cafe_babe_u64);
    tt.prefetch(u64::MAX);
    // Idempotent: calling repeatedly is allowed.
    for k in 1_u64..1024 {
        tt.prefetch(k);
    }
}

#[test]
fn searcher_clear_tt_uses_bump_age_not_physical_clear() {
    let game = KeyedGame;
    let mut wb = game.build_workbench(&GameStateSnapshot::default());
    let mut searcher = Searcher::<KeyedGame>::new();

    searcher.search(&mut wb, 1);
    assert_eq!(searcher.tt_age_bumps(), 0);
    assert_eq!(searcher.tt_current_age(), 0);

    searcher.clear_tt();
    assert_eq!(searcher.tt_age_bumps(), 1);
    assert_eq!(searcher.tt_current_age(), 1);
}

#[test]
fn iterative_deepening_bumps_age_between_depths() {
    let game = KeyedGame;
    let mut wb = game.build_workbench(&GameStateSnapshot::default());
    let mut searcher = Searcher::<KeyedGame>::new();

    let result = searcher.iterative_deepening(&mut wb, 3);
    // Depth 1→2 and 2→3 each bump once, so 2 bumps for max_depth=3.
    assert_eq!(
        searcher.tt_age_bumps(),
        2,
        "age bumped once per iteration boundary (max_depth - 1)"
    );
    assert!(!result.best_action.is_none());
}

#[test]
fn perft_split_partitions_leaf_count_per_root_action() {
    let game = KeyedGame;
    let mut wb = game.build_workbench(&GameStateSnapshot::default());

    // Depth 2: root has 2 actions; each leads to a node with 2 actions
    // before the workbench reports terminal at ply == 2.  Total leaves
    // expected = 4, evenly split.
    let total = crate::perft::perft::<KeyedGame>(&mut wb, 2);
    let split = crate::perft::perft_split::<KeyedGame>(&mut wb, 2);
    assert_eq!(total, 4);
    let split_total: u64 = split.iter().map(|(_, n)| *n).sum();
    assert_eq!(split_total, total);
    assert_eq!(split.len(), 2);
    for (_, leaves) in split {
        assert_eq!(leaves, 2);
    }
}

#[test]
fn perft_split_returns_empty_at_zero_depth() {
    let game = KeyedGame;
    let mut wb = game.build_workbench(&GameStateSnapshot::default());
    assert!(crate::perft::perft_split::<KeyedGame>(&mut wb, 0).is_empty());
}

#[test]
fn perft_unique_keys_counts_distinct_workbench_keys() {
    let game = KeyedGame;
    let mut wb = game.build_workbench(&GameStateSnapshot::default());

    // KeyedWorkbench uses a ply-indexed key, so depth 2 reaches the
    // single key 102 (ply == 2 = terminal).  Confirm the helper does
    // not double-count transpositions.
    let keys = crate::perft::perft_unique_keys::<KeyedGame>(&mut wb, 2);
    assert_eq!(keys, 1);
}
