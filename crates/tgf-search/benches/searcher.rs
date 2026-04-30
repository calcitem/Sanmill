// SPDX-License-Identifier: GPL-3.0-or-later
// Generic searcher benchmarks.
//
// These benchmarks lock in concrete numbers for the Rust hot path so the
// migration plan's "≤5% NPS regression" gate has something to compare
// against.  They are deliberately scoped to be cheap (every iteration
// completes in well under 1 ms on a developer laptop) so CI can run the
// full set on every PR without timeouts.
//
// Usage:
//   cargo bench -p tgf-search
//   cargo bench -p tgf-search -- mill_search_depth_2
//
// The bench results live under `target/criterion/` and are also
// summarised by `cargo run --release -p tgf-cli -- bench`, which feeds
// `tests/perf_baseline.toml`-compatible TOML to
// `scripts/check_perf_baseline.py`.

use criterion::{criterion_group, criterion_main, Criterion};
use tgf_core::{Game, GameRules};
use tgf_mill::{MillGame, MillRules};
use tgf_search::{lazy_smp_search, perft, LazySmpWorker, SearchOptions, Searcher, SharedTt};

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

criterion_group!(
    benches,
    bench_mill_search_depth_1,
    bench_mill_search_depth_2,
    bench_mill_pvs_depth_3,
    bench_mill_perft_depth_2,
    bench_mill_perft_mid_depth_3,
    bench_mill_iterative_deepening_depth_3,
    bench_mill_lazy_smp_2_workers_depth_2,
);
criterion_main!(benches);
