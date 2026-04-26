// SPDX-License-Identifier: GPL-3.0-or-later
// Phase 5 benchmark scaffold for the generic Searcher<G: Game>.

use criterion::{criterion_group, criterion_main, Criterion};
use tgf_core::{Game, GameRules};
use tgf_mill::{MillGame, MillRules};
use tgf_search::Searcher;

fn bench_mill_depth_1(c: &mut Criterion) {
    c.bench_function("mill_search_depth_1", |b| {
        b.iter(|| {
            let rules = MillRules::default();
            let game = MillGame::default();
            let snap = rules.initial_state(&[]);
            let mut wb = game.build_workbench(&snap);
            let mut searcher = Searcher::<MillGame>::new();
            searcher.search(&mut wb, 1)
        });
    });
}

criterion_group!(benches, bench_mill_depth_1);
criterion_main!(benches);
