// SPDX-License-Identifier: GPL-3.0-or-later
// Mill-specific searcher benchmarks.
//
// These benchmarks lock in concrete numbers for the Rust hot path so the
// migration plan's "≤5% NPS regression" gate has something to compare
// against.  They are deliberately scoped to be cheap (every iteration
// completes in well under 1 ms on a developer laptop) so CI can run the
// full set on every PR without timeouts.
//
// Usage:
//   cargo bench -p tgf-mill
//   cargo bench -p tgf-mill -- mill_search_depth_2
//
// The bench results live under `target/criterion/` and are also
// summarised by `cargo run --release -p tgf-cli -- bench`, which feeds
// `tests/perf_baseline.toml`-compatible TOML to
// `scripts/check_perf_baseline.py`.
//
// Historically these benches lived under `crates/tgf-search/benches/` and
// forced `tgf-search` to keep `tgf-mill` in `[dev-dependencies]`.  Moving
// them here keeps `tgf-search` game-neutral while still exercising the
// same hot path against a real, non-trivial game.

use criterion::{black_box, criterion_group, criterion_main, Criterion};
use tgf_core::{Action, Game, GameRules, Workbench};
use tgf_mill::{MillActionKind, MillGame, MillRules};
use tgf_search::{
    lazy_smp_search, perft, LazySmpWorker, MctsOptions, MctsSearcher, SearchOptions, SearchPolicy,
    Searcher, SharedTt,
};

fn bench_mill_search_depth_1(c: &mut Criterion) {
    c.bench_function("mill_search_depth_1", |b| {
        let rules = MillRules::default();
        let game = MillGame::default();
        let snap = rules.initial_state(&[]);

        b.iter(|| {
            let mut wb = game.build_workbench(&snap);
            let mut searcher = Searcher::<MillGame>::new();
            searcher.search(&mut wb, 1)
        });
    });
}

fn bench_mill_search_depth_2(c: &mut Criterion) {
    c.bench_function("mill_search_depth_2", |b| {
        let rules = MillRules::default();
        let game = MillGame::default();
        let snap = rules.initial_state(&[]);

        b.iter(|| {
            let mut wb = game.build_workbench(&snap);
            let mut searcher = Searcher::<MillGame>::new();
            searcher.search(&mut wb, 2)
        });
    });
}

fn bench_mill_pvs_depth_3(c: &mut Criterion) {
    c.bench_function("mill_pvs_depth_3", |b| {
        let rules = MillRules::default();
        let game = MillGame::default();
        let snap = rules.initial_state(&[]);

        b.iter(|| {
            let mut wb = game.build_workbench(&snap);
            let mut searcher = Searcher::<MillGame>::new();
            searcher.search_pvs(&mut wb, 3)
        });
    });
}

fn bench_mill_perft_depth_2(c: &mut Criterion) {
    c.bench_function("mill_perft_depth_2", |b| {
        let rules = MillRules::default();
        let game = MillGame::default();
        let snap = rules.initial_state(&[]);

        b.iter(|| {
            let mut wb = game.build_workbench(&snap);
            perft::<MillGame>(&mut wb, 2)
        });
    });
}

fn bench_mill_perft_mid_depth_3(c: &mut Criterion) {
    c.bench_function("mill_perft_mid_depth_3", |b| {
        let rules = MillRules::default();
        let game = MillGame::default();
        let snap = rules.no_mill_moving_phase_snapshot();

        b.iter(|| {
            let mut wb = game.build_workbench(&snap);
            perft::<MillGame>(&mut wb, 3)
        });
    });
}

fn bench_mill_iterative_deepening_depth_3(c: &mut Criterion) {
    c.bench_function("mill_iterative_deepening_depth_3", |b| {
        let rules = MillRules::default();
        let game = MillGame::default();
        let snap = rules.initial_state(&[]);

        b.iter(|| {
            let mut wb = game.build_workbench(&snap);
            let mut searcher = Searcher::<MillGame>::new();
            searcher.iterative_deepening(&mut wb, 3)
        });
    });
}

fn bench_mill_lazy_smp_2_workers_depth_2(c: &mut Criterion) {
    c.bench_function("mill_lazy_smp_2_workers_depth_2", |b| {
        let rules = MillRules::default();
        let game = MillGame::default();
        let snap = rules.initial_state(&[]);

        b.iter(|| {
            let shared_tt = SharedTt::new(12);
            lazy_smp_search::<MillGame>(
                game.clone(),
                snap,
                2,
                &[
                    LazySmpWorker { extra_depth: 0 },
                    LazySmpWorker { extra_depth: 1 },
                ],
                SearchOptions::default(),
                shared_tt,
                None,
            )
        });
    });
}

fn bench_mill_mcts_default(c: &mut Criterion) {
    c.bench_function("mill_mcts_default", |b| {
        let rules = MillRules::default();
        let game = MillGame::default();
        let snap = rules.initial_state(&[]);

        b.iter(|| {
            let mut wb = game.build_workbench(&snap);
            let mut mcts = MctsSearcher::<MillGame>::new();
            mcts.set_random_seed(0xCAFE_BABE);
            mcts.search_with_options(
                &mut wb,
                MctsOptions {
                    iterations: 64,
                    playout_depth: 4,
                    time_limit_ms: None,
                    exploration: 0.5,
                    ab_assist_depth: 0,
                    ..MctsOptions::default()
                },
            )
        });
    });
}

fn bench_mill_mcts_assist_depth_1(c: &mut Criterion) {
    c.bench_function("mill_mcts_assist_depth_1", |b| {
        let rules = MillRules::default();
        let game = MillGame::default();
        let snap = rules.initial_state(&[]);

        b.iter(|| {
            let mut wb = game.build_workbench(&snap);
            let mut mcts = MctsSearcher::<MillGame>::new();
            mcts.set_random_seed(0xCAFE_BABE);
            mcts.set_policy(SearchPolicy {
                quiescence_kind_tag: Some(MillActionKind::Remove as i16),
                ..Default::default()
            });
            mcts.search_with_options(
                &mut wb,
                MctsOptions {
                    iterations: 64,
                    playout_depth: 4,
                    time_limit_ms: None,
                    exploration: 0.5,
                    ab_assist_depth: 1,
                    ..MctsOptions::default()
                },
            )
        });
    });
}

/// Bench `Workbench::key()` after the Zobrist migration (commit
/// "Migrate Mill position_key to Zobrist...").  The cached fast path
/// is the dominant signal: every searcher node pays exactly one
/// `wb.key()` call, so the relative speedup vs. pre-migration FNV
/// shows up directly in NPS.
fn bench_mill_workbench_key_initial(c: &mut Criterion) {
    c.bench_function("mill_workbench_key_initial", |b| {
        let rules = MillRules::default();
        let game = MillGame::default();
        let snap = rules.initial_state(&[]);
        let wb = game.build_workbench(&snap);
        b.iter(|| {
            let k = black_box(&wb).key();
            black_box(k)
        });
    });
}

/// Bench `Workbench::key_after(action)` for a Place action.  Mirrors
/// the prefetch hot path -- the searcher emits one `key_after` per
/// candidate child before recursing.  The Zobrist override should
/// stay O(1) and well below the Place's actual `apply` cost.
fn bench_mill_workbench_key_after_place(c: &mut Criterion) {
    c.bench_function("mill_workbench_key_after_place", |b| {
        let rules = MillRules::default();
        let game = MillGame::default();
        let snap = rules.initial_state(&[]);
        let mut wb = game.build_workbench(&snap);
        let action = Action {
            kind_tag: MillActionKind::Place as i16,
            from_node: -1,
            to_node: 0,
            aux: -1,
            payload_bits: 0,
        };
        b.iter(|| {
            let k = black_box(&mut wb).key_after(black_box(action));
            black_box(k)
        });
    });
}

criterion_group!(
    benches,
    bench_mill_search_depth_1,
    bench_mill_search_depth_2,
    bench_mill_pvs_depth_3,
    bench_mill_perft_depth_2,
    bench_mill_perft_mid_depth_3,
    bench_mill_iterative_deepening_depth_3,
    bench_mill_lazy_smp_2_workers_depth_2,
    bench_mill_mcts_default,
    bench_mill_mcts_assist_depth_1,
    bench_mill_workbench_key_initial,
    bench_mill_workbench_key_after_place,
);
criterion_main!(benches);
