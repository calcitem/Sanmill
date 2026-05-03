// SPDX-License-Identifier: GPL-3.0-or-later
// Monte-Carlo tree search scaffold.
//
// `MctsSearcher<G>` is monomorphised over the same `Game` trait family
// as `Searcher<G>` so its hot path stays statically dispatched.
// Optional α-β-assisted simulation (see `MctsOptions::ab_assist_depth`)
// shares this crate's `Searcher` and TT for higher-quality rollouts.

use std::collections::HashMap;
use std::marker::PhantomData;
use std::sync::atomic::{AtomicI64, AtomicU32, Ordering};
use std::time::{Duration, Instant};

use tgf_core::{
    Action, ActionList, Evaluator, Game, GameStateSnapshot, MoveOrderContext, Workbench,
};

use crate::options::SearchPolicy;
use crate::searcher::Searcher;
use crate::thread_pool::SearchThreadPool;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct MctsResult {
    pub best_action: Action,
    pub visits: u32,
    pub wins: u32,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct MctsOptions {
    pub iterations: u32,
    pub playout_depth: i32,
    pub time_limit_ms: Option<u64>,
    pub exploration: f64,
    /// When > 0, the simulation phase uses a shallow α-β search instead of
    /// random rollout.  The value is the depth passed to `Searcher::search`.
    ///
    /// The default mirrors master `mcts.h` `ALPHA_BETA_DEPTH = 6`:
    /// `simulate` always evaluates leaves with a depth-6 alpha-beta
    /// search, never a random rollout.  Callers that prefer the
    /// classical random rollout can explicitly set this to `0` (kept
    /// supported so `tgf selfplay --algorithm pvs` and unit tests
    /// stay deterministic).
    pub ab_assist_depth: i32,
    /// Number of independent worker threads.  `None` resolves to
    /// `std::thread::available_parallelism()` matching master
    /// `monte_carlo_tree_search` (which uses `hardware_concurrency`).
    /// `Some(1)` forces single-threaded operation (deterministic;
    /// required by selfplay regression tests).  Master splits
    /// `iterations` across workers, so each worker sees
    /// `iterations / num_threads` rollouts; we follow the same
    /// convention.
    pub num_threads: Option<u32>,
    pub move_order_context: MoveOrderContext,
}

impl Default for MctsOptions {
    fn default() -> Self {
        Self {
            iterations: 2048,
            playout_depth: 6,
            time_limit_ms: None,
            exploration: 0.5,
            // Master `mcts.h` `ALPHA_BETA_DEPTH = 6` -- master never does a
            // random rollout, every simulate() runs a depth-6 alpha-beta
            // evaluation.  Default to the same here so MCTS calls without
            // explicit overrides match master signal quality.  Tests / the
            // selfplay PVS path explicitly opt out via `ab_assist_depth: 0`
            // when they need pure-MCTS rollout for determinism.
            ab_assist_depth: 6,
            num_threads: None,
            move_order_context: MoveOrderContext {
                algorithm: tgf_core::MoveOrderAlgorithm::Mcts,
                ..MoveOrderContext::default()
            },
        }
    }
}

#[derive(Debug)]
pub(crate) struct MctsNode {
    action: Action,
    children: Vec<usize>,
    untried: Vec<Action>,
    visits: AtomicU32,
    wins: AtomicI64,
    move_index: usize,
}

impl MctsNode {
    fn root(untried: Vec<Action>) -> Self {
        Self {
            action: Action::NONE,
            children: Vec::new(),
            untried,
            visits: AtomicU32::new(0),
            wins: AtomicI64::new(0),
            move_index: 0,
        }
    }

    fn child(_parent: usize, action: Action, untried: Vec<Action>, move_index: usize) -> Self {
        Self {
            action,
            children: Vec::new(),
            untried,
            visits: AtomicU32::new(0),
            wins: AtomicI64::new(0),
            move_index,
        }
    }

    fn visits(&self) -> u32 {
        self.visits.load(Ordering::Relaxed)
    }

    fn wins(&self) -> i64 {
        self.wins.load(Ordering::Relaxed)
    }

    fn record_simulation(&self, win: bool) {
        self.visits.fetch_add(1, Ordering::Relaxed);
        if win {
            self.wins.fetch_add(1, Ordering::Relaxed);
        }
    }

    fn win_score(&self) -> f64 {
        let visits = self.visits();
        if visits == 0 {
            0.0
        } else {
            self.wins() as f64 / visits as f64
        }
    }
}

pub struct MctsSearcher<G: Game> {
    rng_state: u64,
    exploration: f64,
    policy: SearchPolicy,
    _phantom: PhantomData<G>,
}

impl<G: Game> Default for MctsSearcher<G> {
    fn default() -> Self {
        Self {
            rng_state: 0xD1B5_4A32_D192_ED03,
            exploration: 0.5,
            policy: SearchPolicy::default(),
            _phantom: PhantomData,
        }
    }
}

impl<G: Game> MctsSearcher<G> {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn set_random_seed(&mut self, seed: u64) {
        self.rng_state = if seed == 0 {
            0xD1B5_4A32_D192_ED03
        } else {
            seed
        };
    }

    pub fn set_exploration(&mut self, exploration: f64) {
        self.exploration = exploration.max(0.0);
    }

    /// Set the search policy forwarded to the α-β sub-searcher used during
    /// the simulation phase when `MctsOptions::ab_assist_depth > 0`.
    /// For Mill, pass `SearchPolicy { quiescence_kind_tag: Some(MillActionKind::Remove as i16), ..Default::default() }`.
    pub fn set_policy(&mut self, policy: SearchPolicy) {
        self.policy = policy;
    }

    /// Monte-Carlo Tree Search scaffold using UCT selection, expansion,
    /// random playout, and backpropagation.  This is still single-threaded and
    /// does not yet include the optional C++ alpha-beta assisted simulation, but
    /// unlike the first scaffold it maintains a real tree of node statistics.
    pub fn search(
        &mut self,
        wb: &mut G::Workbench,
        iterations_per_move: u32,
        playout_depth: i32,
    ) -> MctsResult {
        self.search_with_options(
            wb,
            MctsOptions {
                iterations: iterations_per_move.max(1),
                playout_depth,
                time_limit_ms: None,
                exploration: self.exploration,
                ab_assist_depth: 0,
                num_threads: Some(1),
                move_order_context: MoveOrderContext {
                    algorithm: tgf_core::MoveOrderAlgorithm::Mcts,
                    ..MoveOrderContext::default()
                },
            },
        )
    }

    pub fn search_with_options(
        &mut self,
        wb: &mut G::Workbench,
        options: MctsOptions,
    ) -> MctsResult {
        self.set_exploration(options.exploration);
        let started_at = Instant::now();
        let mut root_moves = ActionList::<256>::new();
        G::generate_legal_ctx(wb, &mut root_moves, &options.move_order_context);
        self.order_mcts_moves(wb, &options.move_order_context, &mut root_moves);
        if root_moves.is_empty() {
            return MctsResult {
                best_action: Action::NONE,
                visits: 0,
                wins: 0,
            };
        }

        let root_untried = root_moves.into_iter().collect::<Vec<_>>();
        let total_iterations = options.iterations.max(1) as usize;
        let mut nodes = vec![MctsNode::root(root_untried)];

        for i in 0..total_iterations {
            if let Some(limit_ms) = options.time_limit_ms {
                if i > 0 && started_at.elapsed() >= Duration::from_millis(limit_ms) {
                    break;
                }
            }
            let mut node_idx = 0_usize;
            let mut path = vec![0_usize];
            let mut applied_moves = 0_usize;

            // Selection: descend by UCT while fully expanded.
            while nodes[node_idx].untried.is_empty() && !nodes[node_idx].children.is_empty() {
                let child_idx = self.best_uct_child(&nodes, node_idx);
                let action = nodes[child_idx].action;
                wb.do_move(action);
                applied_moves += 1;
                node_idx = child_idx;
                path.push(node_idx);
            }

            // Expansion mirrors master MCTS: sort all legal moves, expand all
            // children at once, and continue simulation from the first child.
            if !nodes[node_idx].untried.is_empty() {
                let actions = std::mem::take(&mut nodes[node_idx].untried);
                let first_child_idx = nodes.len();
                for action in actions {
                    wb.do_move(action);
                    let mut child_moves = ActionList::<256>::new();
                    G::generate_legal_ctx(wb, &mut child_moves, &options.move_order_context);
                    self.order_mcts_moves(wb, &options.move_order_context, &mut child_moves);
                    wb.undo_move();
                    let move_index = nodes[node_idx].children.len();
                    let child_idx = nodes.len();
                    nodes.push(MctsNode::child(
                        node_idx,
                        action,
                        child_moves.into_iter().collect(),
                        move_index,
                    ));
                    nodes[node_idx].children.push(child_idx);
                }
                let action = nodes[first_child_idx].action;
                wb.do_move(action);
                applied_moves += 1;
                node_idx = first_child_idx;
                path.push(node_idx);
            }

            let mut win = self.simulate(wb, options.playout_depth, &options);

            for _ in 0..applied_moves {
                wb.undo_move();
            }

            // Backpropagate.  Alternate win perspective at each parent, matching
            // the mature C++ implementation.
            for idx in path.into_iter().rev() {
                nodes[idx].record_simulation(win);
                win = !win;
            }
        }

        let Some(best_child) = nodes[0]
            .children
            .iter()
            .copied()
            .max_by_key(|idx| nodes[*idx].visits())
        else {
            return MctsResult {
                best_action: Action::NONE,
                visits: 0,
                wins: 0,
            };
        };

        MctsResult {
            best_action: nodes[best_child].action,
            visits: nodes[best_child].visits(),
            wins: nodes[best_child].wins().max(0) as u32,
        }
    }

    pub(crate) fn best_uct_child(&self, nodes: &[MctsNode], node_idx: usize) -> usize {
        let parent_visits = nodes[node_idx].visits().max(1) as f64;
        *nodes[node_idx]
            .children
            .iter()
            .max_by(|a, b| {
                let av = self.uct_value(&nodes[**a], parent_visits);
                let bv = self.uct_value(&nodes[**b], parent_visits);
                av.partial_cmp(&bv).unwrap_or(std::cmp::Ordering::Equal)
            })
            .expect("node has children")
    }

    pub(crate) fn order_mcts_moves(
        &self,
        wb: &G::Workbench,
        context: &MoveOrderContext,
        moves: &mut ActionList<256>,
    ) {
        moves
            .as_mut_slice()
            .sort_by_key(|action| -G::move_order_bias_ctx(wb, *action, context));
    }

    fn uct_value(&self, node: &MctsNode, parent_visits: f64) -> f64 {
        let visits = node.visits();
        if visits == 0 {
            return f64::INFINITY;
        }
        let mean = node.win_score();
        let exploration = self.exploration * (2.0 * parent_visits.ln() / visits as f64).sqrt();
        let variance = ((mean * (1.0 - mean)) / visits as f64).sqrt();
        let bias = 0.05 * (256.0 - node.move_index as f64);
        mean + exploration + variance + bias
    }

    pub(crate) fn simulate(
        &mut self,
        wb: &mut G::Workbench,
        depth: i32,
        options: &MctsOptions,
    ) -> bool {
        // α-β assisted simulation: when ab_assist_depth > 0 use a shallow
        // α-β search instead of random rollout so the Monte-Carlo signal is
        // higher quality.  A fresh Searcher is constructed per simulation to
        // keep MCTS state independent; this is intentionally simple —
        // production callers can share TTs if they need higher throughput.
        if options.ab_assist_depth > 0 && !wb.is_terminal() {
            let mut sub = Searcher::<G>::new();
            sub.set_policy(self.policy);
            sub.set_move_order_context(options.move_order_context);
            let result = sub.search(wb, options.ab_assist_depth);
            return result.score > 0;
        }

        if depth <= 0 || wb.is_terminal() {
            return G::Evaluator::score(wb) > 0;
        }
        let mut moves = ActionList::<256>::new();
        G::generate_legal_ctx(wb, &mut moves, &options.move_order_context);
        self.order_mcts_moves(wb, &options.move_order_context, &mut moves);
        if moves.is_empty() {
            return G::Evaluator::score(wb) > 0;
        }
        let idx = self.next_random_index(moves.len());
        wb.do_move(moves[idx]);
        let win = !self.simulate(wb, depth - 1, options);
        wb.undo_move();
        win
    }

    fn next_random_index(&mut self, len: usize) -> usize {
        debug_assert!(len > 0);
        let mut x = self.rng_state;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        self.rng_state = x;
        let value = x.wrapping_mul(0x2545_F491_4F6C_DD1D);
        (value as usize) % len
    }
}

/// Multi-threaded MCTS driver mirroring master `monte_carlo_tree_search`.
///
/// Master spawns `std::thread::hardware_concurrency()` workers that
/// each run their own root MCTS for `iterations / num_threads`
/// rollouts; the per-move visits / wins are then aggregated through a
/// `ThreadSafeNodeVisits` struct and the move with the most total
/// visits wins.  The Rust port follows the same shape:
///
///   * each worker constructs its own `MctsSearcher` with a distinct
///     PRNG seed (xorshift cannot collapse to zero, hence the `i + 1`
///     seed mix);
///   * each worker builds its own `Workbench` from `snapshot` so the
///     shared `Game` can be reused across threads;
///   * the per-action visits / wins are summed in atomic maps and the
///     final best action is the one with the highest total visit
///     count, matching master `best_move_index` selection.
///
/// `MctsOptions::num_threads` controls the worker count:
///   * `Some(n)` forces `n` workers (use `Some(1)` for deterministic
///     selfplay regression testing);
///   * `None` defaults to `available_parallelism().map(NonZero::get)`
///     and falls back to 1 when the platform refuses to report.
pub fn mcts_search_parallel<G>(
    game: &G,
    snapshot: GameStateSnapshot,
    options: MctsOptions,
    base_seed: u64,
) -> MctsResult
where
    G: Game + Clone + Send + Sync + 'static,
    G::Workbench: 'static,
{
    let num_threads = options
        .num_threads
        .map(|n| n.max(1))
        .unwrap_or_else(default_num_threads);
    if num_threads <= 1 {
        let mut searcher = MctsSearcher::<G>::new();
        searcher.set_random_seed(base_seed.max(1));
        let mut wb = game.build_workbench(&snapshot);
        return searcher.search_with_options(&mut wb, options);
    }

    // Split iterations across workers (master semantics: each worker
    // sees iterations/num_threads).
    let per_worker = options.iterations.max(num_threads) / num_threads;

    let pool = SearchThreadPool::new(num_threads as usize);
    let mut receivers = Vec::with_capacity(num_threads as usize);
    for w in 0..num_threads {
        let game = game.clone();
        let mut local_options = options;
        local_options.iterations = per_worker.max(1);
        local_options.num_threads = Some(1);
        // Distinct non-zero seed per worker so xorshift cannot
        // collapse to the all-zero attractor and worker rollouts
        // diverge.
        let worker_seed = base_seed
            .wrapping_add(0x9E37_79B9_7F4A_7C15_u64.wrapping_mul(u64::from(w) + 1))
            .max(1);
        receivers.push(pool.submit(move || {
            let mut searcher = MctsSearcher::<G>::new();
            searcher.set_random_seed(worker_seed);
            let mut wb = game.build_workbench(&snapshot);
            // Collect per-action visits / wins from this worker.
            collect_worker_root_stats::<G>(&mut searcher, &mut wb, local_options)
        }));
    }

    // Aggregate visits / wins per action across workers.
    let mut visits_total: HashMap<Action, u64> = HashMap::new();
    let mut wins_total: HashMap<Action, u64> = HashMap::new();
    for rx in receivers {
        let stats = rx.recv().expect("MCTS worker must return per-action stats");
        for (action, (visits, wins)) in stats {
            *visits_total.entry(action).or_insert(0) += u64::from(visits);
            *wins_total.entry(action).or_insert(0) += wins;
        }
    }

    let Some((best_action, best_visits)) = visits_total
        .iter()
        .max_by_key(|(_, v)| *v)
        .map(|(a, v)| (*a, *v))
    else {
        return MctsResult {
            best_action: Action::NONE,
            visits: 0,
            wins: 0,
        };
    };
    let best_wins = wins_total.get(&best_action).copied().unwrap_or(0);
    MctsResult {
        best_action,
        visits: best_visits.min(u32::MAX as u64) as u32,
        wins: best_wins.min(u32::MAX as u64) as u32,
    }
}

/// Resolve `available_parallelism()` to a concrete worker count,
/// defaulting to 1 if the platform refuses to report.
fn default_num_threads() -> u32 {
    std::thread::available_parallelism()
        .map(|n| u32::try_from(n.get()).unwrap_or(u32::MAX))
        .unwrap_or(1)
        .max(1)
}

/// Run a single MCTS root search on the supplied workbench and
/// return a per-action `(visits, wins)` stats vector for aggregation.
fn collect_worker_root_stats<G>(
    searcher: &mut MctsSearcher<G>,
    wb: &mut G::Workbench,
    options: MctsOptions,
) -> Vec<(Action, (u32, u64))>
where
    G: Game,
{
    // We piggy-back on `search_with_options`: it already maintains the
    // per-root-child visits / wins.  Mirror its bookkeeping here so we
    // can return *all* root-children stats rather than only the best
    // child.  This keeps the worker self-contained and matches master
    // `mcts_worker` returning every child to the shared aggregator.
    searcher.set_exploration(options.exploration);
    let started_at = Instant::now();
    let mut root_moves = ActionList::<256>::new();
    G::generate_legal_ctx(wb, &mut root_moves, &options.move_order_context);
    searcher.order_mcts_moves(wb, &options.move_order_context, &mut root_moves);
    if root_moves.is_empty() {
        return Vec::new();
    }
    let root_untried = root_moves.into_iter().collect::<Vec<_>>();
    let total_iterations = options.iterations.max(1) as usize;
    let mut nodes = vec![MctsNode::root(root_untried)];

    for i in 0..total_iterations {
        if let Some(limit_ms) = options.time_limit_ms {
            if i > 0 && started_at.elapsed() >= Duration::from_millis(limit_ms) {
                break;
            }
        }
        let mut node_idx = 0_usize;
        let mut path = vec![0_usize];
        let mut applied_moves = 0_usize;
        while nodes[node_idx].untried.is_empty() && !nodes[node_idx].children.is_empty() {
            let child_idx = searcher.best_uct_child(&nodes, node_idx);
            let action = nodes[child_idx].action;
            wb.do_move(action);
            applied_moves += 1;
            node_idx = child_idx;
            path.push(node_idx);
        }
        if !nodes[node_idx].untried.is_empty() {
            let actions = std::mem::take(&mut nodes[node_idx].untried);
            let first_child_idx = nodes.len();
            for action in actions {
                wb.do_move(action);
                let mut child_moves = ActionList::<256>::new();
                G::generate_legal_ctx(wb, &mut child_moves, &options.move_order_context);
                searcher.order_mcts_moves(wb, &options.move_order_context, &mut child_moves);
                wb.undo_move();
                let move_index = nodes[node_idx].children.len();
                let child_idx = nodes.len();
                nodes.push(MctsNode::child(
                    node_idx,
                    action,
                    child_moves.into_iter().collect(),
                    move_index,
                ));
                nodes[node_idx].children.push(child_idx);
            }
            let action = nodes[first_child_idx].action;
            wb.do_move(action);
            applied_moves += 1;
            node_idx = first_child_idx;
            path.push(node_idx);
        }
        let mut win = searcher.simulate(wb, options.playout_depth, &options);
        for _ in 0..applied_moves {
            wb.undo_move();
        }
        for idx in path.into_iter().rev() {
            nodes[idx].record_simulation(win);
            win = !win;
        }
    }

    // Collect per-root-child (visits, wins).
    nodes[0]
        .children
        .iter()
        .map(|&idx| {
            let n = &nodes[idx];
            (n.action, (n.visits(), n.wins().max(0) as u64))
        })
        .collect()
}
