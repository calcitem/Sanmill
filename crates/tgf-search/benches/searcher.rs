// SPDX-License-Identifier: GPL-3.0-or-later
// Game-neutral searcher benchmarks.
//
// These benches exercise the generic searcher hot path against a tiny
// mock game so the `tgf-search` crate stays game-agnostic.  The richer,
// production-flavoured numbers are produced by `tgf-mill`'s benches and
// the `tgf-cli` bench subcommand.
//
// Usage:
//   cargo bench -p tgf-search

use criterion::{Criterion, criterion_group, criterion_main};
use tgf_core::{Action, ActionList, Evaluator, Game, GameStateSnapshot, Workbench};
use tgf_search::{Searcher, perft};

#[derive(Clone, Copy, Debug)]
struct BenchWorkbench {
    ply: u8,
    side: i8,
}

impl Workbench for BenchWorkbench {
    fn snapshot(&self) -> GameStateSnapshot {
        GameStateSnapshot::default()
    }

    fn key(&self) -> u64 {
        100 + u64::from(self.ply)
    }

    fn side_to_move(&self) -> i8 {
        self.side
    }

    fn is_terminal(&self) -> bool {
        self.ply >= 4
    }

    fn do_move(&mut self, _: Action) {
        self.ply += 1;
        self.side ^= 1;
    }

    fn undo_move(&mut self) {
        self.ply -= 1;
        self.side ^= 1;
    }
}

struct BenchEvaluator;

impl Evaluator<BenchWorkbench> for BenchEvaluator {
    fn score(wb: &BenchWorkbench) -> i32 {
        i32::from(wb.ply) * 10
    }
}

#[derive(Clone)]
struct BenchGame;

impl Game for BenchGame {
    type Workbench = BenchWorkbench;
    type Evaluator = BenchEvaluator;

    fn build_workbench(&self, _snap: &GameStateSnapshot) -> Self::Workbench {
        BenchWorkbench { ply: 0, side: 0 }
    }

    fn generate_legal(wb: &Self::Workbench, out: &mut ActionList<256>) {
        if wb.is_terminal() {
            return;
        }
        for to in 0..4_i16 {
            out.push(Action {
                kind_tag: 0,
                from_node: -1,
                to_node: to,
                aux: -1,
                payload_bits: 0,
            });
        }
    }
}

fn bench_search_depth_2(c: &mut Criterion) {
    c.bench_function("generic_search_depth_2", |b| {
        let game = BenchGame;
        b.iter(|| {
            let mut wb = game.build_workbench(&GameStateSnapshot::default());
            let mut searcher = Searcher::<BenchGame>::new();
            searcher.search(&mut wb, 2)
        });
    });
}

fn bench_search_depth_3(c: &mut Criterion) {
    c.bench_function("generic_search_depth_3", |b| {
        let game = BenchGame;
        b.iter(|| {
            let mut wb = game.build_workbench(&GameStateSnapshot::default());
            let mut searcher = Searcher::<BenchGame>::new();
            searcher.search(&mut wb, 3)
        });
    });
}

fn bench_perft_depth_3(c: &mut Criterion) {
    c.bench_function("generic_perft_depth_3", |b| {
        let game = BenchGame;
        b.iter(|| {
            let mut wb = game.build_workbench(&GameStateSnapshot::default());
            perft::<BenchGame>(&mut wb, 3)
        });
    });
}

criterion_group!(
    benches,
    bench_search_depth_2,
    bench_search_depth_3,
    bench_perft_depth_3,
);
criterion_main!(benches);
