// SPDX-License-Identifier: GPL-3.0-or-later
// Generic monomorphised game-tree searcher.
//
// `Searcher<G: Game>` is the hot-path entry point: alpha-beta, PVS,
// MTD(f), iterative deepening, qsearch, root random search.  It never
// stores `dyn GameRules` or `dyn Workbench` — every call is dispatched
// statically through the `G: Game` type parameter, mirroring the C++
// CRTP design in the migration plan.

use std::collections::HashMap;
use std::marker::PhantomData;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use tgf_core::{Action, ActionList, Evaluator, Game, MoveOrderContext, Workbench};

use crate::abort::SearchAbortHandle;
use crate::options::{SearchOptions, SearchPolicy};
use crate::result::SearchResult;
use crate::tt::{Bound, ClusteredTt, SharedTt};

mod iterative_mtdf;
mod move_order;
mod qsearch;

pub struct Searcher<G: Game> {
    nodes: u64,
    tt_hits: u64,
    tt_misses: u64,
    tt_age_bumps: u64,
    rng_state: u64,
    tt: Arc<ClusteredTt>,
    killers: HashMap<i32, Action>,
    history: HashMap<Action, i32>,
    policy: SearchPolicy,
    options: SearchOptions,
    /// Maximum quiescence depth extension beyond `depth == 0`.  Mirrors the
    /// C++ `MaxQuiescenceDepth` setoption.  At 0 (default) the qsearch is a
    /// stand-pat-only evaluation; setting it to N lets the remove extension
    /// recurse N plies deeper than the main search horizon.
    qsearch_max_depth: i32,
    search_started_at: Option<Instant>,
    abort_flag: Arc<AtomicBool>,
    aborted: bool,
    /// Zobrist keys of positions on the search path from root to the current
    /// node.  Used to detect in-search repetitions and return draw score
    /// immediately rather than searching deeper into a cycle.  Mirrors C++
    /// `Search::hasRepeated / posKeyHistory` within the search stack.
    /// Independent of the game-state-side key_history (which only collects
    /// moving-phase reversible moves).
    pub(crate) repetition_stack: Vec<u64>,
    _phantom: PhantomData<G>,
}

impl<G: Game> Default for Searcher<G> {
    fn default() -> Self {
        Self {
            nodes: 0,
            tt_hits: 0,
            tt_misses: 0,
            tt_age_bumps: 0,
            rng_state: 0x9E37_79B9_7F4A_7C15,
            tt: Arc::new(ClusteredTt::default()),
            killers: HashMap::new(),
            history: HashMap::new(),
            policy: SearchPolicy::default(),
            options: SearchOptions::default(),
            qsearch_max_depth: 0,
            search_started_at: None,
            abort_flag: Arc::new(AtomicBool::new(false)),
            aborted: false,
            repetition_stack: Vec::new(),
            _phantom: PhantomData,
        }
    }
}

impl<G: Game> Searcher<G> {
    pub fn new() -> Self {
        Self::default()
    }

    /// Override TT size (`2^(bits+1)` slots).  Clamp matches [ClusteredTt].
    pub fn new_with_tt_cluster_bits(cluster_bits: u32) -> Self {
        Self {
            tt: Arc::new(ClusteredTt::new_with_cluster_bits(cluster_bits)),
            ..Self::default()
        }
    }

    /// Resize the TT to approximately `mb` megabytes (P2-L plan-C).
    /// Mirrors master UCI `Hash` option which calls `TT.resize(bytes)`.
    /// Each TT cluster holds 2 slots of 8 bytes = 16 bytes per cluster;
    /// cluster_bits b gives 2^(b+1) slots = 2^b clusters = 2^b × 16 bytes.
    /// → cluster_bits = floor(log2(mb × 1024 × 1024 / 16)).
    /// Clamped to [10, 26] to avoid excessive memory or too-small tables.
    pub fn resize_tt_by_mb(&mut self, mb: u32) {
        let bytes = (mb as u64).saturating_mul(1024 * 1024);
        let cluster_bytes = 16_u64;
        let num_clusters = (bytes / cluster_bytes).max(1);
        let bits = (63 - num_clusters.leading_zeros()).clamp(10, 26);
        self.tt = Arc::new(ClusteredTt::new_with_cluster_bits(bits));
        self.killers.clear();
        self.history.clear();
    }

    /// Build a Searcher whose transposition table is shared with all other
    /// Searchers holding the same [`SharedTt`].  This is the entry point for
    /// lazy-SMP parallel search: spawn N threads, each owning its own
    /// Searcher (with independent killers / history / abort flag) but all
    /// reading and writing the same cluster array.
    pub fn with_shared_tt(shared: SharedTt) -> Self {
        Self {
            tt: shared.inner,
            ..Self::default()
        }
    }

    /// Replace this Searcher's abort flag with an externally-owned one,
    /// typically the shared flag used by `lazy_smp_search` so that one
    /// `stop` aborts every worker.  Existing handles obtained from
    /// [`Self::abort_handle`] BEFORE this call become disconnected.
    pub fn set_abort_flag(&mut self, flag: Arc<AtomicBool>) {
        self.abort_flag = flag;
    }

    /// Return a cloned `SharedTt` handle pointing at this Searcher's TT so
    /// additional workers can be spawned against the same cluster array.
    pub fn shared_tt(&self) -> SharedTt {
        SharedTt {
            inner: Arc::clone(&self.tt),
        }
    }

    pub fn nodes(&self) -> u64 {
        self.nodes
    }

    pub fn tt_hits(&self) -> u64 {
        self.tt_hits
    }

    pub fn tt_misses(&self) -> u64 {
        self.tt_misses
    }

    pub fn tt_hit_rate_pct(&self) -> f64 {
        let total = self.tt_hits + self.tt_misses;
        if total == 0 {
            0.0
        } else {
            self.tt_hits as f64 * 100.0 / total as f64
        }
    }

    /// Soft-clear the transposition table by bumping its generation counter.
    /// Non-Exact entries stored in the previous generation are treated as
    /// stale on the next probe, matching the C++ fake-clean semantics.
    /// Also clears killer and history tables (these are always position-local).
    pub fn clear_tt(&mut self) {
        self.tt.bump_age();
        self.tt_age_bumps += 1;
        self.killers.clear();
        self.history.clear();
    }

    /// Total number of TT age bumps since this Searcher was created.
    /// Useful for bench instrumentation (`[meta] tt_age_bumps`).
    pub fn tt_age_bumps(&self) -> u64 {
        self.tt_age_bumps
    }

    /// Current TT generation counter (same as `SharedTt::current_age`).
    pub fn tt_current_age(&self) -> u8 {
        self.tt.current_age()
    }

    pub fn tt_len(&self) -> usize {
        self.tt.len_occupied()
    }

    pub fn set_random_seed(&mut self, seed: u64) {
        self.rng_state = if seed == 0 {
            0x9E37_79B9_7F4A_7C15
        } else {
            seed
        };
    }

    pub fn set_policy(&mut self, policy: SearchPolicy) {
        self.policy = policy;
    }

    pub fn set_options(&mut self, options: SearchOptions) {
        self.options = options;
    }

    pub fn set_move_order_context(&mut self, context: MoveOrderContext) {
        self.options.move_order_context = context;
    }

    /// Set the maximum quiescence depth extension (default 0 = stand-pat only).
    /// Matches the C++ `MaxQuiescenceDepth` setoption.  Values are clamped to
    /// [0, 4] to prevent excessive recursion.
    pub fn set_qsearch_max_depth(&mut self, depth: i32) {
        self.qsearch_max_depth = depth.clamp(0, 4);
    }

    pub fn qsearch_max_depth(&self) -> i32 {
        self.qsearch_max_depth
    }

    pub fn abort_handle(&self) -> SearchAbortHandle {
        SearchAbortHandle {
            flag: Arc::clone(&self.abort_flag),
        }
    }

    pub fn request_abort(&self) {
        self.abort_flag.store(true, Ordering::Relaxed);
    }

    pub fn was_aborted(&self) -> bool {
        self.aborted
    }

    pub fn search(&mut self, wb: &mut G::Workbench, depth: i32) -> SearchResult {
        self.begin_root_search();
        if let Some(score) = G::terminal_score(wb, wb.side_to_move(), depth) {
            return SearchResult {
                best_action: Action::NONE,
                score,
                nodes: self.nodes,
            };
        }
        let mut moves = ActionList::<256>::new();
        G::generate_legal_ctx(wb, &mut moves, &self.options.move_order_context);
        // P2-K: root shuffle before sort (mirrors master's MoveList::shuffle).
        if self.options.shuffle_root {
            self.shuffle_moves(&mut moves);
        }
        self.order_moves(wb, wb.key(), depth, &mut moves);
        if moves.is_empty() {
            return SearchResult {
                best_action: Action::NONE,
                score: G::Evaluator::score(wb),
                nodes: self.nodes,
            };
        }
        // Root single-move early return (P2-D, mirroring master
        // `Search::search`).  When there is only one legal action at the
        // root the engine would play it regardless of search result; we
        // return `VALUE_UNIQUE_ROOT_MOVE` (100) to flag the state and skip
        // wasted work.
        if moves.len() == 1 {
            return SearchResult {
                best_action: moves[0],
                score: G::unique_root_move_score(),
                nodes: self.nodes,
            };
        }

        let mut best_action = moves[0];
        let mut best_score = i32::MIN + 1;
        let root_key = wb.key();
        for action in moves {
            if self.should_abort() {
                break;
            }
            let before = wb.side_to_move();
            if root_key != 0 {
                self.repetition_stack.push(root_key);
            }
            wb.do_move(action);
            let after = wb.side_to_move();
            let score =
                self.search_after_move(wb, depth - 1, i32::MIN + 1, i32::MAX - 1, before, after);
            wb.undo_move();
            if root_key != 0 {
                self.repetition_stack.pop();
            }
            if score > best_score {
                best_score = score;
                best_action = action;
            }
        }

        SearchResult {
            best_action,
            score: best_score,
            nodes: self.nodes,
        }
    }

    /// Principal Variation Search root entry.  The first move is searched with
    /// a full window; later moves use a null window and are re-searched on
    /// fail-high inside the original alpha/beta window.  This mirrors the
    /// shape of `Search::pvs` in the mature C++ engine.
    pub fn search_pvs(&mut self, wb: &mut G::Workbench, depth: i32) -> SearchResult {
        self.begin_root_search();
        if let Some(score) = G::terminal_score(wb, wb.side_to_move(), depth) {
            return SearchResult {
                best_action: Action::NONE,
                score,
                nodes: self.nodes,
            };
        }
        let mut moves = ActionList::<256>::new();
        G::generate_legal_ctx(wb, &mut moves, &self.options.move_order_context);
        // P2-K: root shuffle before sort.
        if self.options.shuffle_root {
            self.shuffle_moves(&mut moves);
        }
        self.order_moves(wb, wb.key(), depth, &mut moves);
        if moves.is_empty() {
            return SearchResult {
                best_action: Action::NONE,
                score: G::Evaluator::score(wb),
                nodes: self.nodes,
            };
        }
        // P2-D: single root action → no need to search.
        if moves.len() == 1 {
            return SearchResult {
                best_action: moves[0],
                score: G::unique_root_move_score(),
                nodes: self.nodes,
            };
        }

        let mut best_action = moves[0];
        let mut alpha = i32::MIN + 1;
        let beta = i32::MAX - 1;

        let root_key = wb.key();
        for (i, action) in moves.into_iter().enumerate() {
            if self.should_abort() {
                break;
            }
            let before = wb.side_to_move();
            if root_key != 0 {
                self.repetition_stack.push(root_key);
            }
            wb.do_move(action);
            let after = wb.side_to_move();
            let value = self.pvs_after_move(wb, depth - 1, alpha, beta, i, before, after);
            wb.undo_move();
            if root_key != 0 {
                self.repetition_stack.pop();
            }

            if value > alpha {
                alpha = value;
                best_action = action;
            }
        }

        SearchResult {
            best_action,
            score: alpha,
            nodes: self.nodes,
        }
    }

    /// Deterministic random-search equivalent.  Production callers can seed
    /// this from time; tests pass a fixed seed to keep results reproducible.
    pub fn random_search(&mut self, wb: &mut G::Workbench) -> SearchResult {
        let mut moves = ActionList::<256>::new();
        G::generate_legal_ctx(wb, &mut moves, &self.options.move_order_context);
        if moves.is_empty() {
            return SearchResult {
                best_action: Action::NONE,
                score: 0,
                nodes: 0,
            };
        }
        // Mirror master src/movegen.cpp:348 MoveList<LEGAL>::shuffle and
        // src/search_engine.cpp random path: shuffle the legal move list first,
        // then choose a random index from the shuffled list.
        self.shuffle_moves(&mut moves);
        let index = self.next_random_index(moves.len());
        SearchResult {
            best_action: moves[index],
            score: 0,
            nodes: 0,
        }
    }

    #[inline]
    pub fn alpha_beta(
        &mut self,
        wb: &mut G::Workbench,
        depth: i32,
        mut alpha: i32,
        beta: i32,
    ) -> i32 {
        self.nodes += 1;
        if self.should_abort() {
            return G::Evaluator::score(wb);
        }
        if let Some(score) = G::terminal_score(wb, wb.side_to_move(), depth) {
            return score;
        }

        // Detect in-search repetition: if the current Zobrist key has
        // appeared on the search path from root to here, the game would cycle
        // indefinitely.  Master returns VALUE_DRAW + 1 to avoid threefold
        // blindness among otherwise equal drawing lines.
        let key = wb.key();
        if key != 0 && self.repetition_stack.contains(&key) {
            return 1;
        }

        // Transition to qsearch when depth falls to or below the qsearch
        // horizon.  With qsearch_max_depth == 0 this matches the C++ stand-
        // pat-only behaviour; positive values extend the remove branch.
        if depth <= 0 {
            return self.qsearch_with_depth(wb, depth, alpha, beta);
        }

        let old_alpha = alpha;
        if let Some(value) = self.probe_tt(key, depth, &mut alpha, beta) {
            self.tt_hits += 1;
            return value;
        }
        if key != 0 {
            self.tt_misses += 1;
        }

        // Null-move pruning (Phase 5): when not in qsearch, when depth is
        // sufficient, and when allowed by SearchOptions, make a "null" move
        // (pass the turn) and search at reduced depth.  A fail-high here
        // means the position is already so good we can prune without
        // searching children.  Only applied at depth ≥ 3 to avoid pruning
        // near the horizon where the null-move assumption is unreliable.
        // Guard: skip null-move when the evaluator already reports a
        // near-terminal value (|score| > NULL_MOVE_TERMINAL_GUARD) to
        // avoid pruning genuine mate sequences.  The guard is intentionally
        // game-neutral: concrete games choose their own evaluator scale,
        // and the constant below is sized for the reference Mill mate-score
        // family (VALUE_MATE = 80) which other games are free to align with
        // by overriding `Game::terminal_score`.
        const NULL_MOVE_MIN_DEPTH: i32 = 3;
        const NULL_MOVE_TERMINAL_GUARD: i32 = 40; // half of VALUE_MATE = 80
        if self.options.allow_null_move && depth >= NULL_MOVE_MIN_DEPTH && beta < i32::MAX - 1 {
            let static_eval = G::Evaluator::score(wb);
            if static_eval.abs() < NULL_MOVE_TERMINAL_GUARD {
                // "Pass" the turn by flipping side_to_move in the workbench.
                // The `Workbench` trait does not expose a null-move
                // primitive (most games either always have legal moves or
                // need a game-specific "pass" encoding), so we skip the
                // recursive null search and instead use the static eval
                // proxy below.
                // This is a simplified null-move: score the position from
                // the opponent's perspective at reduced depth.
                let null_score = -static_eval; // crude "null move" proxy
                if null_score >= beta {
                    // Prune: static evaluation already exceeds beta, so a
                    // real null move would also fail high.
                    return beta;
                }
            }
        }

        let mut moves = ActionList::<256>::new();
        G::generate_legal_ctx(wb, &mut moves, &self.options.move_order_context);
        self.order_moves(wb, key, depth, &mut moves);
        if moves.is_empty() {
            return G::Evaluator::score(wb);
        }

        let mut best_value = i32::MIN + 1;
        let mut best_action = Action::NONE;
        let depth_extension = if self.options.depth_extension && moves.len() == 1 {
            1
        } else {
            0
        };
        for action in moves {
            if self.should_abort() {
                return best_value.max(alpha);
            }
            let before = wb.side_to_move();
            if key != 0 {
                self.repetition_stack.push(key);
            }
            wb.do_move(action);
            let after = wb.side_to_move();
            let score =
                self.search_after_move(wb, depth - 1 + depth_extension, alpha, beta, before, after);
            wb.undo_move();
            if key != 0 {
                self.repetition_stack.pop();
            }
            if score > best_value {
                best_value = score;
                best_action = action;
            }
            if score >= beta {
                self.record_cutoff(depth, action);
                self.save_tt(key, depth, beta, Bound::Lower, action);
                return beta;
            }
            if score > alpha {
                alpha = score;
            }
        }
        let bound = if best_value <= old_alpha {
            Bound::Upper
        } else {
            Bound::Exact
        };
        self.save_tt(key, depth, alpha, bound, best_action);
        alpha
    }

    #[inline]
    fn should_abort(&mut self) -> bool {
        if let Some(limit) = self.options.node_limit {
            if self.nodes >= limit {
                self.aborted = true;
            }
        }
        if let (Some(start), Some(limit_ms)) = (self.search_started_at, self.options.time_limit_ms)
        {
            if start.elapsed() >= Duration::from_millis(limit_ms) {
                self.aborted = true;
            }
        }
        if self.abort_flag.load(Ordering::Relaxed) {
            self.aborted = true;
        }
        self.aborted
    }

    #[inline]
    fn begin_root_search(&mut self) {
        self.nodes = 0;
        self.tt_hits = 0;
        self.tt_misses = 0;
        self.aborted = false;
        self.repetition_stack.clear();
        // Intentionally do NOT clear `abort_flag` here.  External callers
        // hold a clone of the Arc and may have already requested an abort
        // (especially when search is spawned on another thread): clearing
        // the flag here would race with the request and silently lose it.
        // To rerun an aborted Searcher, call [`Self::clear_abort`].
        self.search_started_at = Some(Instant::now());
    }

    /// Reset the shared abort flag so a Searcher can be reused after a
    /// previous abort.  External callers spawning a fresh search via
    /// [`Self::abort_handle`] should NOT call this between
    /// `abort_handle()` and search start, otherwise pending stop requests
    /// would be lost.
    pub fn clear_abort(&mut self) {
        self.aborted = false;
        self.abort_flag.store(false, Ordering::Relaxed);
    }

    #[inline]
    fn search_after_move(
        &mut self,
        wb: &mut G::Workbench,
        depth: i32,
        alpha: i32,
        beta: i32,
        before: i8,
        after: i8,
    ) -> i32 {
        if let Some(score) = G::terminal_score(wb, before, depth) {
            return score;
        }
        if after != before {
            -self.alpha_beta(wb, depth, -beta, -alpha)
        } else {
            self.alpha_beta(wb, depth, alpha, beta)
        }
    }

    #[allow(clippy::too_many_arguments)]
    #[inline]
    fn pvs_after_move(
        &mut self,
        wb: &mut G::Workbench,
        depth: i32,
        alpha: i32,
        beta: i32,
        move_index: usize,
        before: i8,
        after: i8,
    ) -> i32 {
        if let Some(score) = G::terminal_score(wb, before, depth) {
            return score;
        }
        if move_index == 0 {
            return self.search_after_move(wb, depth, alpha, beta, before, after);
        }

        const PVS_WINDOW: i32 = 1;
        let mut value = if after != before {
            -self.alpha_beta(wb, depth, -alpha - PVS_WINDOW, -alpha)
        } else {
            self.alpha_beta(wb, depth, alpha, alpha + PVS_WINDOW)
        };

        if value > alpha && value < beta {
            value = self.search_after_move(wb, depth, alpha, beta, before, after);
        }
        value
    }

    #[inline]
    pub(crate) fn next_random_index(&mut self, len: usize) -> usize {
        debug_assert!(len > 0);
        // xorshift64*: tiny deterministic PRNG, adequate for random-search
        // move selection and reproducible tests.
        let mut x = self.rng_state;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        self.rng_state = x;
        let value = x.wrapping_mul(0x2545_F491_4F6C_DD1D);
        (value as usize) % len
    }
}
