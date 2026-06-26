// SPDX-License-Identifier: GPL-3.0-or-later
// Generic worker pool and lazy-SMP fan-out for the searcher.
//
// `SearchThreadPool` is intentionally game-agnostic: it accepts any
// `FnOnce() + Send` job and wires up `crossbeam_channel` dispatch.  The
// `SearchThreadPool` remains available for callers that need a reusable
// closure pool.  `lazy_smp_search` uses direct JoinHandles because it
// dispatches exactly one job per worker and can avoid channel/box overhead.

use std::sync::Arc;
use std::sync::atomic::AtomicBool;
use std::thread;

use crossbeam_channel::{Receiver, Sender};
use tgf_core::{Game, GameStateSnapshot};

use crate::options::SearchOptions;
use crate::result::SearchResult;
use crate::searcher::Searcher;
use crate::tt::SharedTt;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct LazySmpWorker {
    pub extra_depth: i32,
}

/// Run a Lazy-SMP-style parallel search.  All workers share one
/// transposition table through [`SharedTt`] AND a single abort flag, so
/// requesting an abort through [`SearchAbortHandle`] once stops every
/// worker.
///
/// The highest configured depth wins, with score as a tie-breaker; this is
/// intentionally simpler than full YBWC.  Returned node count is the sum of
/// all workers so bench output reflects the parallel work performed.  When
/// `abort_flag` is `None` a fresh shared flag is allocated; pass `Some(...)`
/// to participate in an existing cancellation chain (e.g. UCI `stop` from the
/// main thread).
pub fn lazy_smp_search<G>(
    game: G,
    snapshot: GameStateSnapshot,
    base_depth: i32,
    workers: &[LazySmpWorker],
    options: SearchOptions,
    shared_tt: SharedTt,
    abort_flag: Option<Arc<AtomicBool>>,
) -> SearchResult
where
    G: Game + Clone + Send + 'static,
    G::Workbench: 'static,
{
    let workers = if workers.is_empty() {
        &[LazySmpWorker { extra_depth: 0 }][..]
    } else {
        workers
    };
    let abort = abort_flag.unwrap_or_else(|| Arc::new(AtomicBool::new(false)));

    let mut handles = Vec::with_capacity(workers.len());
    for worker in workers.iter().copied() {
        let game_for_worker = game.clone();
        let shared_tt = shared_tt.clone();
        let options_for_worker = options;
        let snapshot_for_worker = snapshot;
        let abort = Arc::clone(&abort);
        let depth = (base_depth + worker.extra_depth).max(1);
        handles.push(thread::spawn(move || {
            let mut searcher = Searcher::<G>::with_shared_tt(shared_tt);
            searcher.set_abort_flag(abort);
            searcher.set_options(options_for_worker);
            let mut wb = game_for_worker.build_workbench(&snapshot_for_worker);
            (depth, searcher.iterative_deepening(&mut wb, depth))
        }));
    }

    let mut best: Option<(i32, SearchResult)> = None;
    let mut total_nodes = 0_u64;
    for handle in handles {
        let (depth, result) = handle
            .join()
            .expect("lazy-smp worker should return a SearchResult");
        total_nodes = total_nodes.saturating_add(result.nodes);
        if best
            .as_ref()
            .is_none_or(|prev| lazy_smp_result_is_better((depth, &result), (prev.0, &prev.1)))
        {
            best = Some((depth, result));
        }
    }
    let (_, mut result) = best.expect("at least one lazy-smp worker should run");
    result.nodes = total_nodes;
    result
}

fn lazy_smp_result_is_better(
    candidate: (i32, &SearchResult),
    current: (i32, &SearchResult),
) -> bool {
    let candidate_valid = !candidate.1.best_action.is_none() || candidate.1.draw_reason.is_some();
    let current_valid = !current.1.best_action.is_none() || current.1.draw_reason.is_some();
    if candidate_valid != current_valid {
        return candidate_valid;
    }
    if candidate.0 != current.0 {
        return candidate.0 > current.0;
    }
    candidate.1.score > current.1.score
}

enum ThreadPoolMessage {
    Run(Box<dyn FnOnce() + Send + 'static>),
    Stop,
}

/// Minimal fixed-size worker pool for search tasks.
///
/// This pool intentionally does not know about games or searchers: callers
/// submit closures, which keeps it reusable for lazy SMP, future YBWC, and
/// MCTS shared-visit experiments.
pub struct SearchThreadPool {
    sender: Sender<ThreadPoolMessage>,
    workers: Vec<thread::JoinHandle<()>>,
}

impl SearchThreadPool {
    pub fn new(worker_count: usize) -> Self {
        let worker_count = worker_count.max(1);
        let (sender, receiver) = crossbeam_channel::unbounded::<ThreadPoolMessage>();
        let mut workers = Vec::with_capacity(worker_count);
        for _ in 0..worker_count {
            let receiver = receiver.clone();
            workers.push(thread::spawn(move || {
                while let Ok(message) = receiver.recv() {
                    match message {
                        ThreadPoolMessage::Run(job) => job(),
                        ThreadPoolMessage::Stop => break,
                    }
                }
            }));
        }
        Self { sender, workers }
    }

    pub fn worker_count(&self) -> usize {
        self.workers.len()
    }

    pub fn execute<F>(&self, job: F)
    where
        F: FnOnce() + Send + 'static,
    {
        self.sender
            .send(ThreadPoolMessage::Run(Box::new(job)))
            .expect("search thread pool workers stopped unexpectedly");
    }

    pub fn submit<F, R>(&self, job: F) -> Receiver<R>
    where
        F: FnOnce() -> R + Send + 'static,
        R: Send + 'static,
    {
        let (tx, rx) = crossbeam_channel::bounded(1);
        self.execute(move || {
            let result = job();
            let _ = tx.send(result);
        });
        rx
    }
}

impl Drop for SearchThreadPool {
    fn drop(&mut self) {
        for _ in &self.workers {
            let _ = self.sender.send(ThreadPoolMessage::Stop);
        }
        for worker in self.workers.drain(..) {
            worker.join().expect("search thread pool worker panicked");
        }
    }
}
