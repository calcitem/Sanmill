// SPDX-License-Identifier: GPL-3.0-or-later
// Generic monomorphised game-tree searcher.
//
// `Searcher<G: Game>` is the hot-path entry point: alpha-beta, PVS,
// MTD(f), iterative deepening, qsearch, root random search.  It never
// stores `dyn GameRules` or `dyn Workbench` — every call is dispatched
// statically through the `G: Game` type parameter, mirroring the C++
// CRTP design in the migration plan.

use std::marker::PhantomData;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

use tgf_core::{Action, Evaluator, Game, MoveOrderContext, SearchActionList, Workbench};

use crate::abort::SearchAbortHandle;
use crate::options::{SearchOptions, SearchPolicy};
use crate::result::SearchResult;
use crate::searcher::qsearch::TtProbe;
use crate::tt::{Bound, ClusteredTt, SharedTt};

mod iterative_mtdf;
mod move_order;
mod qsearch;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct DebugTtEntry {
    pub value: i32,
    pub depth: i32,
    pub bound: &'static str,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RootProbeRow {
    pub action: Action,
    pub child_key: u64,
    pub value: i32,
    pub nodes: u64,
    pub cutoff: bool,
    pub child_tt: Option<DebugTtEntry>,
}

pub type RootProbeRows = Vec<RootProbeRow>;

pub struct Searcher<G: Game> {
    /// Per-search-instance node counter.
    ///
    /// Diff 11.2 alignment: master's `Search::search` uses
    /// `static uint64_t nodeCounter` (src/search.cpp:312, 50) which
    /// is a single global shared by every thread.  The C++ MCTS
    /// driver spawns `hardware_concurrency()` workers that all bump
    /// this static counter without synchronisation, so the
    /// time-out check fires at non-deterministic intervals (a
    /// known TODO in the master source).  The Rust port deliberately
    /// keeps `nodes` per-Searcher: lazy-SMP / parallel MCTS workers
    /// each get their own counter and their own timeout cadence,
    /// which is correct.  No master alignment work is required for
    /// this difference; the master behaviour is the bug.
    nodes: u64,
    tt_hits: u64,
    tt_misses: u64,
    repetition_cuts: u64,
    tt_age_bumps: u64,
    rng_state: u64,
    tt: Arc<ClusteredTt>,
    policy: SearchPolicy,
    options: SearchOptions,
    /// Maximum quiescence depth extension beyond `depth == 0`.  Mirrors the
    /// C++ `MaxQuiescenceDepth` setoption.  At 0 (default) the qsearch is a
    /// stand-pat-only evaluation; setting it to N lets the remove extension
    /// recurse N plies deeper than the main search horizon.
    qsearch_max_depth: i32,
    search_started_at: Option<Instant>,
    fixed_depth_no_budget: bool,
    abort_flag: Arc<AtomicBool>,
    aborted: bool,
    /// Zobrist keys of positions on the search path from root to the current
    /// node, plus whether the action that reached that ancestor reset
    /// repetition history.  This mirrors master `ss[i].move`: the barrier is
    /// attached to the ancestor itself, not to the outgoing child edge.
    pub(crate) repetition_stack: Vec<(u64, bool)>,
    repetition_current_incoming_reset: bool,
    _phantom: PhantomData<G>,
}

impl<G: Game> Default for Searcher<G> {
    fn default() -> Self {
        Self::with_tt_arc(Arc::new(ClusteredTt::default()))
    }
}

impl<G: Game> Searcher<G> {
    fn with_tt_arc(tt: Arc<ClusteredTt>) -> Self {
        Self {
            nodes: 0,
            tt_hits: 0,
            tt_misses: 0,
            repetition_cuts: 0,
            tt_age_bumps: 0,
            rng_state: 0x9E37_79B9_7F4A_7C15,
            tt,
            policy: SearchPolicy::default(),
            options: SearchOptions::default(),
            qsearch_max_depth: 0,
            search_started_at: None,
            fixed_depth_no_budget: false,
            abort_flag: Arc::new(AtomicBool::new(false)),
            aborted: false,
            repetition_stack: Vec::with_capacity(128),
            repetition_current_incoming_reset: false,
            _phantom: PhantomData,
        }
    }

    pub fn new() -> Self {
        Self::default()
    }

    /// Override TT size (`2^bits` direct slots).  Clamp matches [ClusteredTt].
    pub fn new_with_tt_cluster_bits(cluster_bits: u32) -> Self {
        Self::with_tt_arc(Arc::new(ClusteredTt::new_with_cluster_bits(cluster_bits)))
    }

    /// Resize the TT from the UCI `Hash` option while preserving the supplied
    /// lower bound.  Production callers pass [`ClusteredTt::DEFAULT_CLUSTER_BITS`],
    /// matching master: the C++ engine starts with 16 Mi direct entries and
    /// `TT.resize(value)` ignores any value below that entry count.  Diagnostic
    /// callers may pass a smaller floor to study cache locality without changing
    /// production defaults.
    pub fn resize_tt_by_mb_with_floor(&mut self, mb: u32, floor_bits: u32) {
        let bytes = (mb as u64).saturating_mul(1024 * 1024);
        let cluster_bytes = 8_u64;
        let num_clusters = (bytes / cluster_bytes).max(1);
        let bits = (63 - num_clusters.leading_zeros())
            .max(floor_bits)
            .clamp(10, 26);
        self.tt = Arc::new(ClusteredTt::new_with_cluster_bits(bits));
    }

    pub fn resize_tt_by_mb(&mut self, mb: u32) {
        self.resize_tt_by_mb_with_floor(mb, ClusteredTt::DEFAULT_CLUSTER_BITS);
    }

    /// Build a Searcher whose transposition table is shared with all other
    /// Searchers holding the same [`SharedTt`].  This is the entry point for
    /// lazy-SMP parallel search: spawn N threads, each owning its own
    /// Searcher (with an independent abort flag) but all reading and writing
    /// the same cluster array.
    pub fn with_shared_tt(shared: SharedTt) -> Self {
        Self::with_tt_arc(shared.inner)
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

    pub fn repetition_cuts(&self) -> u64 {
        self.repetition_cuts
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
    pub fn clear_tt(&mut self) {
        self.tt.bump_age();
        self.tt_age_bumps += 1;
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

    pub fn debug_tt_entry_for_key(&self, key: u64) -> Option<DebugTtEntry> {
        self.tt.get(key).map(|entry| DebugTtEntry {
            value: entry.value,
            depth: entry.depth,
            bound: match entry.bound {
                Bound::Exact => "exact",
                Bound::Lower => "lower",
                Bound::Upper => "upper",
            },
        })
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
        self.begin_root_search_at(wb);
        if let Some(score) = G::terminal_score(wb, wb.side_to_move(), depth) {
            return SearchResult {
                best_action: Action::NONE,
                score,
                nodes: self.nodes,
                draw_reason: None,
            };
        }
        let mut moves = SearchActionList::new();
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
                draw_reason: None,
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
                draw_reason: None,
            };
        }

        let mut best_action = moves[0];
        let mut best_score = i32::MIN + 1;
        let root_key = wb.key();
        for action in moves.iter().copied() {
            if self.should_abort() {
                break;
            }
            let before = wb.side_to_move();
            let previous_incoming_reset = self.push_repetition_ancestor(root_key, action);
            wb.do_move(action);
            let after = wb.side_to_move();
            let score =
                self.search_after_move(wb, depth - 1, i32::MIN + 1, i32::MAX - 1, before, after);
            wb.undo_move();
            self.pop_repetition_ancestor(root_key, previous_incoming_reset);
            // Keep the FIRST move on ties, matching master `Search::search`'s
            // strict `value > bestValue` root update (src/search.cpp): the
            // best move only changes on a strict score improvement.
            if score > best_score {
                best_score = score;
                best_action = action;
            }
        }

        SearchResult {
            best_action,
            score: best_score,
            nodes: self.nodes,
            draw_reason: None,
        }
    }

    /// Principal Variation Search root entry.  The first move is searched with
    /// a full window; later moves use a null window and are re-searched on
    /// fail-high inside the original alpha/beta window.  This mirrors the
    /// shape of `Search::pvs` in the mature C++ engine.
    ///
    /// # Divergence from master
    ///
    /// `origin/master`'s `Search::pvs` is *defined* but only consumed by
    /// `tests/test_search.cpp`; the production root in
    /// `SearchEngine::executeSearch` is `Search::search` (plain alpha-beta).
    /// The Rust implementation uses PVS here because the null-window +
    /// re-search pattern produces the same bestmove as plain alpha-beta on
    /// terminal-deterministic Mill positions while pruning more nodes
    /// (validated by the `tgf-cli selfplay` deterministic regression
    /// baselines).  Callers that need the master-equivalent shape should
    /// invoke `Self::search` (plain alpha-beta) instead.
    pub fn search_pvs(&mut self, wb: &mut G::Workbench, depth: i32) -> SearchResult {
        self.begin_root_search_at(wb);
        if let Some(score) = G::terminal_score(wb, wb.side_to_move(), depth) {
            return SearchResult {
                best_action: Action::NONE,
                score,
                nodes: self.nodes,
                draw_reason: None,
            };
        }
        let mut moves = SearchActionList::new();
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
                draw_reason: None,
            };
        }
        // P2-D: single root action → no need to search.
        if moves.len() == 1 {
            return SearchResult {
                best_action: moves[0],
                score: G::unique_root_move_score(),
                nodes: self.nodes,
                draw_reason: None,
            };
        }

        let mut best_action = moves[0];
        let mut alpha = i32::MIN + 1;
        let beta = i32::MAX - 1;

        let root_key = wb.key();
        for (i, action) in moves.iter().copied().enumerate() {
            if self.should_abort() {
                break;
            }
            let before = wb.side_to_move();
            let previous_incoming_reset = self.push_repetition_ancestor(root_key, action);
            wb.do_move(action);
            let after = wb.side_to_move();
            let value = self.pvs_after_move(wb, depth - 1, alpha, beta, i, before, after);
            wb.undo_move();
            self.pop_repetition_ancestor(root_key, previous_incoming_reset);

            // Keep the FIRST move on ties (strict `value > alpha`), matching
            // master's root update where the best move only changes on a
            // strict improvement.
            if value > alpha {
                alpha = value;
                best_action = action;
            }
        }

        SearchResult {
            best_action,
            score: alpha,
            nodes: self.nodes,
            draw_reason: None,
        }
    }

    /// Diagnostic root probe used by engine-parity tooling.  It runs one
    /// root alpha-beta pass with the supplied window, preserves the TT across
    /// separate calls on the same `Searcher`, and returns per-root-action
    /// values in the order they were searched.
    pub fn debug_root_probe(
        &mut self,
        wb: &mut G::Workbench,
        depth: i32,
        mut alpha: i32,
        beta: i32,
    ) -> (i32, Action, RootProbeRows) {
        self.begin_root_search_at(wb);
        let root_key = wb.key();
        let old_alpha = alpha;
        let mut moves = SearchActionList::new();
        G::generate_legal_ctx(wb, &mut moves, &self.options.move_order_context);
        self.order_moves(wb, root_key, depth, &mut moves);
        let mut best_value = i32::MIN + 1;
        let mut best_action = Action::NONE;
        let mut best_local = Action::NONE;
        let mut rows = Vec::with_capacity(moves.len());
        for action in moves.iter().copied() {
            let nodes_before = self.nodes;
            let before = wb.side_to_move();
            let previous_incoming_reset = self.push_repetition_ancestor(root_key, action);
            wb.do_move(action);
            let child_key = wb.key();
            let child_tt = self.debug_tt_entry_for_key(child_key);
            let after = wb.side_to_move();
            let value = self.search_after_move(wb, depth - 1, alpha, beta, before, after);
            wb.undo_move();
            self.pop_repetition_ancestor(root_key, previous_incoming_reset);
            let action_nodes = self.nodes.saturating_sub(nodes_before);
            let mut cutoff = false;
            if value > best_value {
                best_value = value;
                if value > alpha {
                    best_action = action;
                    best_local = action;
                    if value >= beta {
                        cutoff = true;
                    } else {
                        alpha = value;
                    }
                }
            }
            rows.push(RootProbeRow {
                action,
                child_key,
                value,
                nodes: action_nodes,
                cutoff,
                child_tt,
            });
            if cutoff {
                break;
            }
        }
        let bound = if best_value <= old_alpha {
            Bound::Upper
        } else if best_value >= beta {
            Bound::Lower
        } else {
            Bound::Exact
        };
        self.save_tt(root_key, depth, best_value, bound, best_local);
        (best_value, best_action, rows)
    }

    /// Deterministic random-search equivalent.  Production callers can seed
    /// this from time; tests pass a fixed seed to keep results reproducible.
    pub fn random_search(&mut self, wb: &mut G::Workbench) -> SearchResult {
        let mut moves = SearchActionList::new();
        G::generate_legal_ctx(wb, &mut moves, &self.options.move_order_context);
        if moves.is_empty() {
            return SearchResult {
                best_action: Action::NONE,
                score: 0,
                nodes: 0,
                draw_reason: None,
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
            draw_reason: None,
        }
    }

    #[inline]
    pub fn alpha_beta(
        &mut self,
        wb: &mut G::Workbench,
        depth: i32,
        mut alpha: i32,
        mut beta: i32,
    ) -> i32 {
        self.nodes += 1;
        if self.should_abort() {
            return G::Evaluator::score(wb);
        }

        if let Some(score) = G::terminal_score(wb, wb.side_to_move(), depth) {
            return score;
        }

        // Transition to qsearch when depth falls to or below the qsearch
        // horizon.  Master checks game-over before this branch in
        // Search::search, so keep terminal mate-distance scoring visible even
        // when a line lands exactly on the horizon.
        if depth <= 0 {
            return self.qsearch_with_depth(wb, depth, alpha, beta);
        }

        if let Some(floor) = G::search_alpha_floor(wb) {
            alpha = alpha.max(floor);
            if alpha >= beta {
                return alpha;
            }
        }

        let key = wb.key();
        let old_alpha = alpha;
        match self.probe_tt(key, depth, &mut alpha, &mut beta) {
            TtProbe::Cutoff(value) => {
                self.tt_hits += 1;
                return value;
            }
            TtProbe::HitNoCutoff => {
                self.tt_hits += 1;
            }
            TtProbe::Miss => {
                if key != 0 {
                    self.tt_misses += 1;
                }
            }
        }

        // Repetition cut, faithfully mirroring master `Search::search`
        // (src/search.cpp: after the TT probe, `if (rule.threefoldRepetition
        // Rule && depth != originDepth && pos->has_repeated(ss)) return
        // VALUE_DRAW + 1;`).
        //
        // `alpha_beta` only runs on positions reached AFTER a root move, so
        // the master `depth != originDepth` guard (skip the root) always
        // holds here.  Master `Position::has_repeated` returns true on the
        // SECOND occurrence of the position -- one prior appearance in either
        // the reversible pre-root history (`posKeyHistory`) or the in-search
        // path walked back to the last capture (`ss`, barrier = REMOVE).  It
        // then returns the small positive draw bias `VALUE_DRAW + 1` instead
        // of searching deeper into the cycle.
        //
        // Matching this EXACTLY (2nd occurrence, REMOVE-only barrier, after
        // TT, +bias) is required for deterministic move parity once the
        // moving phase is reached: it is what prunes otherwise-deeper lines
        // to a draw.  `path_repeats_since_reset` covers the search-stack half;
        // `current_repetition_count` covers the pre-root reversible history.
        if key != 0 && (self.path_repeats_since_reset(key) || wb.current_repetition_count() >= 1) {
            self.repetition_cuts += 1;
            return G::repetition_draw_bias();
        }

        // Null-move pruning: when not in qsearch, when depth is sufficient,
        // and when allowed by SearchOptions, make a "null" move
        // (pass the turn) and search at reduced depth.  A fail-high here
        // means the position is already so good we can prune without
        // searching children.  Only applied at depth ≥ 3 to avoid pruning
        // near the horizon where the null-move assumption is unreliable.
        // Guard: skip null-move when the evaluator already reports a
        // near-terminal value (|score| > Game::null_move_terminal_guard())
        // to avoid pruning genuine mate sequences.  The guard is
        // game-neutral: concrete games override
        // `Game::null_move_terminal_guard()` to align with their own
        // evaluator scale (Mill: 40 ≈ ½ × VALUE_MATE; chess-style:
        // ~10_000).
        const NULL_MOVE_MIN_DEPTH: i32 = 3;
        if self.options.allow_null_move && depth >= NULL_MOVE_MIN_DEPTH && beta < i32::MAX - 1 {
            let static_eval = G::Evaluator::score(wb);
            if static_eval.abs() < G::null_move_terminal_guard() {
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

        let mut moves = SearchActionList::new();
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
        self.prefetch_child_keys(wb, &moves);
        for action in moves.iter().copied() {
            if self.should_abort() {
                return best_value.max(alpha);
            }
            let before = wb.side_to_move();
            let previous_incoming_reset = self.push_repetition_ancestor(key, action);
            wb.do_move(action);
            let after = wb.side_to_move();
            let score =
                self.search_after_move(wb, depth - 1 + depth_extension, alpha, beta, before, after);
            wb.undo_move();
            self.pop_repetition_ancestor(key, previous_incoming_reset);
            if score > best_value {
                best_value = score;
                best_action = action;
            }
            if score >= beta {
                self.save_tt(key, depth, score, Bound::Lower, action);
                return score;
            }
            if score > alpha {
                alpha = score;
            }
        }
        let bound = if best_value <= old_alpha {
            Bound::Upper
        } else if best_value >= beta {
            Bound::Lower
        } else {
            Bound::Exact
        };
        self.save_tt(key, depth, best_value, bound, best_action);
        best_value
    }

    #[inline]
    fn should_abort(&mut self) -> bool {
        if self.aborted {
            return true;
        }
        if self.fixed_depth_no_budget {
            if (self.nodes & 1023) != 0 {
                return false;
            }
            if self.abort_flag.load(Ordering::Relaxed) {
                self.aborted = true;
            }
            return self.aborted;
        }
        self.should_abort_slow()
    }

    #[inline(never)]
    fn should_abort_slow(&mut self) -> bool {
        if let Some(limit) = self.options.node_limit
            && self.nodes >= limit
        {
            self.aborted = true;
        }
        if let (Some(start), Some(limit_ms)) = (self.search_started_at, self.options.time_limit_ms)
            && start.elapsed() >= Duration::from_millis(limit_ms)
        {
            self.aborted = true;
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
        self.repetition_cuts = 0;
        self.aborted = false;
        self.repetition_stack.clear();
        self.repetition_current_incoming_reset = false;
        self.fixed_depth_no_budget =
            self.options.node_limit.is_none() && self.options.time_limit_ms.is_none();
        // Intentionally do NOT clear `abort_flag` here.  External callers
        // hold a clone of the Arc and may have already requested an abort
        // (especially when search is spawned on another thread): clearing
        // the flag here would race with the request and silently lose it.
        // To rerun an aborted Searcher, call [`Self::clear_abort`].
        self.search_started_at = self.options.time_limit_ms.map(|_| Instant::now());
        if self.abort_flag.load(Ordering::Relaxed) {
            self.aborted = true;
        }
    }

    #[inline]
    fn begin_root_search_at(&mut self, wb: &G::Workbench) {
        self.begin_root_search();
        self.repetition_current_incoming_reset = wb.current_position_resets_repetition();
    }

    #[inline]
    fn push_repetition_ancestor(&mut self, key: u64, action_to_child: Action) -> bool {
        let previous_incoming_reset = self.repetition_current_incoming_reset;
        if key != 0 {
            self.repetition_stack.push((key, previous_incoming_reset));
        }
        self.repetition_current_incoming_reset = G::action_resets_repetition(action_to_child);
        previous_incoming_reset
    }

    #[inline]
    fn pop_repetition_ancestor(&mut self, key: u64, previous_incoming_reset: bool) {
        self.repetition_current_incoming_reset = previous_incoming_reset;
        if key != 0 {
            self.repetition_stack.pop();
        }
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

    /// Search-stack half of master `Position::has_repeated` (src/position.cpp).
    ///
    /// Master walks the search stack from the current node back toward the
    /// root, stops at the first ancestor that was reached by a capture
    /// (REMOVE), and reports a repetition on the FIRST match it finds -- i.e.
    /// the SECOND occurrence of the position.
    #[inline]
    fn path_repeats_since_reset(&self, key: u64) -> bool {
        for (ancestor_key, reset_after_action) in self.repetition_stack.iter().rev() {
            if *reset_after_action {
                break;
            }
            if *ancestor_key == key {
                return true;
            }
        }
        false
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
        if depth <= 0 {
            return self.search_after_move(wb, depth, alpha, beta, before, after);
        }
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
