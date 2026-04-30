// SPDX-License-Identifier: GPL-3.0-or-later
// Generic monomorphised game-tree searcher.
//
// The hot path is generic over `G: Game`; it never stores `dyn GameRules` or
// `dyn Workbench`.  This mirrors the C++ CRTP design in the migration plan and
// keeps do/undo/evaluate calls statically dispatchable.

use std::{
    collections::HashMap,
    marker::PhantomData,
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        Arc,
    },
    thread,
    time::{Duration, Instant},
};

use tgf_core::{Action, ActionList, Evaluator, Game, GameStateSnapshot, Workbench};

/// Game-neutral perft: counts the leaves of the legal-action tree at the
/// requested depth.  At depth 0 we count the current node as one leaf; at
/// depth 1 we count the number of immediately legal actions.  This matches
/// the standard perft contract used by the mature C++ engine for parity
/// regression testing.
pub fn perft<G: Game>(wb: &mut G::Workbench, depth: i32) -> u64 {
    if depth <= 0 || wb.is_terminal() {
        return 1;
    }
    let mut moves = ActionList::<256>::new();
    G::generate_legal(wb, &mut moves);
    if moves.is_empty() {
        return 1;
    }
    let mut nodes = 0_u64;
    for action in moves {
        wb.do_move(action);
        nodes += perft::<G>(wb, depth - 1);
        wb.undo_move();
    }
    nodes
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SearchResult {
    pub best_action: Action,
    pub score: i32,
    pub nodes: u64,
}

#[derive(Clone, Debug)]
pub struct SearchAbortHandle {
    flag: Arc<AtomicBool>,
}

impl SearchAbortHandle {
    pub fn request_abort(&self) {
        self.flag.store(true, Ordering::Relaxed);
    }

    pub fn is_aborted(&self) -> bool {
        self.flag.load(Ordering::Relaxed)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Bound {
    Exact,
    Lower,
    Upper,
}

#[derive(Clone, Copy, Debug)]
struct TtEntry {
    value: i32,
    depth: i32,
    bound: Bound,
    best_action: Action,
}

// ---------------------------------------------------------------------------
// Clustered TT: fixed `2 * 2^cluster_bits` packed atomic slots.
// ---------------------------------------------------------------------------

struct TtCluster {
    slots: [AtomicU64; 2],
}

impl TtCluster {
    #[inline]
    fn empty() -> Self {
        Self {
            slots: [AtomicU64::new(0), AtomicU64::new(0)],
        }
    }
}

struct ClusteredTt {
    clusters: Box<[TtCluster]>,
    cluster_mask: usize,
}

impl ClusteredTt {
    /// 14 → 16 Ki clusters, 32 Ki slots (~1 MiB with padding).
    const DEFAULT_CLUSTER_BITS: u32 = 14;

    fn new_with_cluster_bits(bits: u32) -> Self {
        let bits = bits.clamp(10, 18);
        let n = 1usize << bits;
        let mask = n - 1;
        let mut clusters = Vec::with_capacity(n);
        clusters.resize_with(n, TtCluster::empty);
        Self {
            clusters: clusters.into_boxed_slice(),
            cluster_mask: mask,
        }
    }

    #[inline]
    fn cluster_ix(&self, key: u64) -> usize {
        let mixed = key ^ (key >> 32);
        (mixed as usize) & self.cluster_mask
    }

    fn get(&self, key: u64) -> Option<TtEntry> {
        if key == 0 {
            return None;
        }
        let key_sig = TtPackedEntry::key_sig(key);
        let c = &self.clusters[self.cluster_ix(key)];
        for s in &c.slots {
            let packed = s.load(Ordering::Relaxed);
            if packed == 0 {
                continue;
            }
            if TtPackedEntry::packed_key_sig(packed) == key_sig {
                return Some(TtPackedEntry::unpack_entry(packed));
            }
        }
        None
    }

    fn save(&self, key: u64, entry: TtEntry) {
        if key == 0 {
            return;
        }
        let new_packed = TtPackedEntry::pack(key, entry);
        let key_sig = TtPackedEntry::key_sig(key);
        let ix = self.cluster_ix(key);
        let c = &self.clusters[ix];
        for s in &c.slots {
            let packed = s.load(Ordering::Relaxed);
            if packed == 0 {
                continue;
            }
            if TtPackedEntry::packed_key_sig(packed) == key_sig {
                if entry.depth < TtPackedEntry::unpack_depth(packed) {
                    return;
                }
                s.store(new_packed, Ordering::Relaxed);
                return;
            }
        }
        for s in &c.slots {
            if s.load(Ordering::Relaxed) == 0 {
                s.store(new_packed, Ordering::Relaxed);
                return;
            }
        }
        let mut wi = 0_usize;
        let mut wd = TtPackedEntry::unpack_depth(c.slots[0].load(Ordering::Relaxed));
        let depth1 = TtPackedEntry::unpack_depth(c.slots[1].load(Ordering::Relaxed));
        if depth1 < wd {
            wi = 1;
            wd = depth1;
        }
        if entry.depth >= wd {
            c.slots[wi].store(new_packed, Ordering::Relaxed);
        }
    }

    fn clear(&self) {
        for c in self.clusters.iter() {
            for s in &c.slots {
                s.store(0, Ordering::Relaxed);
            }
        }
    }

    fn len_occupied(&self) -> usize {
        self.clusters
            .iter()
            .flat_map(|c| c.slots.iter())
            .filter(|s| s.load(Ordering::Relaxed) != 0)
            .count()
    }
}

struct TtPackedEntry;

impl TtPackedEntry {
    const KEY_SIG_BITS: u32 = 16;
    const VALUE_SHIFT: u32 = 16;
    const DEPTH_SHIFT: u32 = 32;
    const BOUND_SHIFT: u32 = 40;
    const ACTION_SHIFT: u32 = 42;

    const KEY_SIG_MASK: u64 = (1_u64 << Self::KEY_SIG_BITS) - 1;
    const VALUE_MASK: u64 = 0xffff;
    const DEPTH_MASK: u64 = 0xff;
    const BOUND_MASK: u64 = 0x03;
    const ACTION_MASK: u64 = (1_u64 << 22) - 1;

    #[inline]
    fn key_sig(key: u64) -> u16 {
        let sig = ((key >> 48) ^ (key >> 32) ^ (key >> 16) ^ key) as u16;
        sig.max(1)
    }

    #[inline]
    fn packed_key_sig(packed: u64) -> u16 {
        (packed & Self::KEY_SIG_MASK) as u16
    }

    #[inline]
    fn pack(key: u64, entry: TtEntry) -> u64 {
        u64::from(Self::key_sig(key))
            | (u64::from(Self::compact_value(entry.value)) << Self::VALUE_SHIFT)
            | (u64::from(Self::compact_depth(entry.depth)) << Self::DEPTH_SHIFT)
            | (u64::from(Self::pack_bound(entry.bound)) << Self::BOUND_SHIFT)
            | (u64::from(Self::pack_action(entry.best_action)) << Self::ACTION_SHIFT)
    }

    #[inline]
    fn unpack_entry(packed: u64) -> TtEntry {
        TtEntry {
            value: Self::unpack_value(packed),
            depth: Self::unpack_depth(packed),
            bound: Self::unpack_bound(packed),
            best_action: Self::unpack_action(packed),
        }
    }

    #[inline]
    fn compact_value(value: i32) -> u16 {
        value.clamp(i16::MIN as i32, i16::MAX as i32) as i16 as u16
    }

    #[inline]
    fn unpack_value(packed: u64) -> i32 {
        (((packed >> Self::VALUE_SHIFT) & Self::VALUE_MASK) as u16 as i16) as i32
    }

    #[inline]
    fn compact_depth(depth: i32) -> u8 {
        depth.clamp(i8::MIN as i32, i8::MAX as i32) as i8 as u8
    }

    #[inline]
    fn unpack_depth(packed: u64) -> i32 {
        (((packed >> Self::DEPTH_SHIFT) & Self::DEPTH_MASK) as u8 as i8) as i32
    }

    #[inline]
    fn pack_bound(bound: Bound) -> u8 {
        match bound {
            Bound::Exact => 0,
            Bound::Lower => 1,
            Bound::Upper => 2,
        }
    }

    #[inline]
    fn unpack_bound(packed: u64) -> Bound {
        match ((packed >> Self::BOUND_SHIFT) & Self::BOUND_MASK) as u8 {
            0 => Bound::Exact,
            1 => Bound::Lower,
            2 => Bound::Upper,
            _ => Bound::Exact,
        }
    }

    #[inline]
    fn pack_action(action: Action) -> u32 {
        let Some(kind) = Self::pack_action_field(action.kind_tag, 4) else {
            return 0;
        };
        let Some(from) = Self::pack_action_field(action.from_node, 7) else {
            return 0;
        };
        let Some(to) = Self::pack_action_field(action.to_node, 7) else {
            return 0;
        };
        let Some(aux) = Self::pack_action_field(action.aux, 4) else {
            return 0;
        };
        u32::from(kind) | (u32::from(from) << 4) | (u32::from(to) << 11) | (u32::from(aux) << 18)
    }

    #[inline]
    fn unpack_action(packed: u64) -> Action {
        let bits = ((packed >> Self::ACTION_SHIFT) & Self::ACTION_MASK) as u32;
        if bits == 0 {
            return Action::NONE;
        }
        Action {
            kind_tag: Self::unpack_action_field((bits & 0x0f) as u8),
            from_node: Self::unpack_action_field(((bits >> 4) & 0x7f) as u8),
            to_node: Self::unpack_action_field(((bits >> 11) & 0x7f) as u8),
            aux: Self::unpack_action_field(((bits >> 18) & 0x0f) as u8),
            payload_bits: 0,
        }
    }

    #[inline]
    fn pack_action_field(value: i16, bits: u32) -> Option<u8> {
        let encoded = value.checked_add(1)?;
        if encoded < 0 || encoded >= (1_i16 << bits) {
            return None;
        }
        Some(encoded as u8)
    }

    #[inline]
    fn unpack_action_field(value: u8) -> i16 {
        i16::from(value) - 1
    }
}

impl Default for ClusteredTt {
    fn default() -> Self {
        Self::new_with_cluster_bits(Self::DEFAULT_CLUSTER_BITS)
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct SearchPolicy {
    pub remove_kind_tag: Option<i16>,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct SearchOptions {
    pub depth_extension: bool,
    pub node_limit: Option<u64>,
    pub time_limit_ms: Option<u64>,
}

/// Reference-counted handle to a packed transposition table.  Multiple
/// `Searcher` instances built with the same `SharedTt` see and update the
/// same cluster array, which is the foundation for lazy-SMP-style parallel
/// search in phase 5.2.  The stored entries themselves use `AtomicU64`
/// slots, so writes are lock-free.
#[derive(Clone)]
pub struct SharedTt {
    inner: Arc<ClusteredTt>,
}

impl SharedTt {
    /// Allocate a fresh TT sized like
    /// [`Searcher::new_with_tt_cluster_bits`] (`2 * 2^cluster_bits` slots).
    pub fn new(cluster_bits: u32) -> Self {
        Self {
            inner: Arc::new(ClusteredTt::new_with_cluster_bits(cluster_bits)),
        }
    }

    /// Drop every entry without reallocating.  Other handles to the same
    /// `SharedTt` observe the empty table immediately.
    pub fn clear(&self) {
        self.inner.clear();
    }

    /// Number of currently occupied slots across all clusters; useful for
    /// debug logging and bench instrumentation.
    pub fn len_occupied(&self) -> usize {
        self.inner.len_occupied()
    }
}

impl Default for SharedTt {
    fn default() -> Self {
        Self {
            inner: Arc::new(ClusteredTt::default()),
        }
    }
}

pub struct Searcher<G: Game> {
    nodes: u64,
    tt_hits: u64,
    tt_misses: u64,
    rng_state: u64,
    tt: Arc<ClusteredTt>,
    killers: HashMap<i32, Action>,
    history: HashMap<Action, i32>,
    policy: SearchPolicy,
    options: SearchOptions,
    search_started_at: Option<Instant>,
    abort_flag: Arc<AtomicBool>,
    aborted: bool,
    _phantom: PhantomData<G>,
}

impl<G: Game> Default for Searcher<G> {
    fn default() -> Self {
        Self {
            nodes: 0,
            tt_hits: 0,
            tt_misses: 0,
            rng_state: 0x9E37_79B9_7F4A_7C15,
            tt: Arc::new(ClusteredTt::default()),
            killers: HashMap::new(),
            history: HashMap::new(),
            policy: SearchPolicy::default(),
            options: SearchOptions::default(),
            search_started_at: None,
            abort_flag: Arc::new(AtomicBool::new(false)),
            aborted: false,
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

    pub fn clear_tt(&mut self) {
        self.tt.clear();
        self.killers.clear();
        self.history.clear();
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
        G::generate_legal(wb, &mut moves);
        self.order_moves(wb, wb.key(), depth, &mut moves);
        if moves.is_empty() {
            return SearchResult {
                best_action: Action::NONE,
                score: G::Evaluator::score(wb),
                nodes: self.nodes,
            };
        }

        let mut best_action = moves[0];
        let mut best_score = i32::MIN + 1;
        for action in moves {
            if self.should_abort() {
                break;
            }
            let before = wb.side_to_move();
            wb.do_move(action);
            let after = wb.side_to_move();
            let score =
                self.search_after_move(wb, depth - 1, i32::MIN + 1, i32::MAX - 1, before, after);
            wb.undo_move();
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
        G::generate_legal(wb, &mut moves);
        self.order_moves(wb, wb.key(), depth, &mut moves);
        if moves.is_empty() {
            return SearchResult {
                best_action: Action::NONE,
                score: G::Evaluator::score(wb),
                nodes: self.nodes,
            };
        }

        let mut best_action = moves[0];
        let mut alpha = i32::MIN + 1;
        let beta = i32::MAX - 1;

        for (i, action) in moves.into_iter().enumerate() {
            if self.should_abort() {
                break;
            }
            let before = wb.side_to_move();
            wb.do_move(action);
            let after = wb.side_to_move();
            let value = self.pvs_after_move(wb, depth - 1, alpha, beta, i, before, after);
            wb.undo_move();

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
        G::generate_legal(wb, &mut moves);
        if moves.is_empty() {
            return SearchResult {
                best_action: Action::NONE,
                score: 0,
                nodes: 0,
            };
        }
        let index = self.next_random_index(moves.len());
        SearchResult {
            best_action: moves[index],
            score: 0,
            nodes: 0,
        }
    }

    /// Simple iterative deepening scaffold.  It re-searches from depth 1 to
    /// `max_depth` and returns the deepest result.
    ///
    /// Later Phase 5 work will add time control, aspiration windows, TT reuse,
    /// and principal-variation tracking.  The important architectural point is
    /// that every iteration still stays generic over `G: Game` and does not
    /// cross a trait-object boundary.
    pub fn iterative_deepening(&mut self, wb: &mut G::Workbench, max_depth: i32) -> SearchResult {
        let max_depth = max_depth.max(1);
        let mut result = self.search(wb, 1);
        for depth in 2..=max_depth {
            result = self.search(wb, depth);
        }
        result
    }

    /// Minimal MTD(f) scaffold implemented over alpha-beta zero-window calls.
    ///
    /// This intentionally omits TT integration for now; without a TT, MTD(f)
    /// is not efficient.  The function exists so Phase 5 can grow the exact
    /// algorithmic surface area while keeping current behavior testable.
    pub fn mtdf(&mut self, wb: &mut G::Workbench, first_guess: i32, depth: i32) -> i32 {
        let mut g = first_guess;
        let mut upper_bound = i32::MAX - 1;
        let mut lower_bound = i32::MIN + 1;

        while lower_bound < upper_bound {
            let beta = if g == lower_bound { g + 1 } else { g };
            g = self.alpha_beta(wb, depth, beta - 1, beta);
            if g < beta {
                upper_bound = g;
            } else {
                lower_bound = g;
            }
        }
        g
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
        if depth <= 0 {
            return self.qsearch_with_depth(wb, depth, alpha, beta);
        }

        let old_alpha = alpha;
        let key = wb.key();
        if let Some(value) = self.probe_tt(key, depth, &mut alpha, beta) {
            self.tt_hits += 1;
            return value;
        }
        if key != 0 {
            self.tt_misses += 1;
        }

        let mut moves = ActionList::<256>::new();
        G::generate_legal(wb, &mut moves);
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
            wb.do_move(action);
            let after = wb.side_to_move();
            let score =
                self.search_after_move(wb, depth - 1 + depth_extension, alpha, beta, before, after);
            wb.undo_move();
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

    /// Quiescence search entry point preserved for external callers.  Equivalent
    /// to invoking [`Self::qsearch_with_depth`] at depth 0; alpha-beta callers
    /// should prefer the depth-aware variant so the stand-pat mate-distance
    /// decay matches `src/search.cpp::qsearch`.
    pub fn qsearch(&mut self, wb: &mut G::Workbench, alpha: i32, beta: i32) -> i32 {
        self.qsearch_with_depth(wb, 0, alpha, beta)
    }

    /// Depth-aware quiescence search mirroring `Search::qsearch` in
    /// `src/search.cpp`.  Adjusts the static stand-pat by `depth` (which is
    /// always non-positive at this entry) so deeper extensions prefer faster
    /// wins / slower losses, then extends only the action kind that the game
    /// policy identifies as a removal.  Removal candidates are ordered
    /// through the same MovePicker-style scoring used in the main search.
    pub fn qsearch_with_depth(
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
        let mut stand_pat = G::Evaluator::score(wb);
        if stand_pat > 0 {
            stand_pat = stand_pat.saturating_add(depth);
        } else {
            stand_pat = stand_pat.saturating_sub(depth);
        }
        if stand_pat >= beta {
            return beta;
        }
        if stand_pat > alpha {
            alpha = stand_pat;
        }
        if wb.is_terminal() {
            return alpha;
        }

        let Some(remove_kind_tag) = self.policy.remove_kind_tag else {
            return alpha;
        };

        let mut moves = ActionList::<256>::new();
        G::generate_legal(wb, &mut moves);
        moves.retain(|a| a.kind_tag == remove_kind_tag);
        if moves.is_empty() {
            return alpha;
        }
        let key = wb.key();
        self.order_moves(wb, key, depth, &mut moves);

        for action in moves {
            if self.should_abort() {
                return alpha;
            }
            let before = wb.side_to_move();
            wb.do_move(action);
            let after = wb.side_to_move();
            let value = if after != before {
                -self.qsearch_with_depth(wb, depth - 1, -beta, -alpha)
            } else {
                self.qsearch_with_depth(wb, depth - 1, alpha, beta)
            };
            wb.undo_move();
            if value > alpha {
                alpha = value;
                if alpha >= beta {
                    return beta;
                }
            }
        }
        alpha
    }

    #[inline]
    fn probe_tt(&self, key: u64, depth: i32, alpha: &mut i32, mut beta: i32) -> Option<i32> {
        if key == 0 {
            return None;
        }
        let entry = self.tt.get(key)?;
        if entry.depth < depth {
            return None;
        }
        match entry.bound {
            Bound::Exact => Some(entry.value),
            Bound::Lower => {
                *alpha = (*alpha).max(entry.value);
                (*alpha >= beta).then_some(entry.value)
            }
            Bound::Upper => {
                beta = beta.min(entry.value);
                (*alpha >= beta).then_some(entry.value)
            }
        }
    }

    #[inline]
    fn save_tt(&mut self, key: u64, depth: i32, value: i32, bound: Bound, best_action: Action) {
        self.tt.save(
            key,
            TtEntry {
                value,
                depth,
                bound,
                best_action,
            },
        );
    }

    #[inline]
    fn order_moves(&self, wb: &G::Workbench, key: u64, depth: i32, moves: &mut ActionList<256>) {
        moves
            .as_mut_slice()
            .sort_by_key(|m| -self.move_score(wb, key, depth, *m));
    }

    #[inline]
    fn move_score(&self, wb: &G::Workbench, key: u64, depth: i32, action: Action) -> i32 {
        let mut score = G::move_order_bias(wb, action);
        if key != 0
            && self
                .tt
                .get(key)
                .is_some_and(|entry| entry.best_action == action)
        {
            score += 1_000_000;
        }
        if self
            .killers
            .get(&depth)
            .is_some_and(|killer| *killer == action)
        {
            score += 100_000;
        }
        score.saturating_add(self.history.get(&action).copied().unwrap_or_default())
    }

    #[inline]
    fn record_cutoff(&mut self, depth: i32, action: Action) {
        self.killers.insert(depth, action);
        let bonus = depth.max(1).saturating_mul(depth.max(1));
        let entry = self.history.entry(action).or_insert(0);
        *entry = entry.saturating_add(bonus);
    }

    #[allow(dead_code)]
    fn order_moves_by_tt(&self, key: u64, moves: &mut ActionList<256>) {
        if key == 0 {
            return;
        }
        let Some(entry) = self.tt.get(key) else {
            return;
        };
        if let Some(index) = moves.iter().position(|m| *m == entry.best_action) {
            moves.as_mut_slice().swap(0, index);
        }
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
    fn next_random_index(&mut self, len: usize) -> usize {
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

/// Worker fan-out for [`lazy_smp_search`].  Each entry produces one search
/// thread; `extra_depth` lets odd-numbered workers explore one ply deeper
/// than even-numbered ones to diversify the tree, similar to Stockfish's
/// lazy-SMP staggering.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct LazySmpWorker {
    pub extra_depth: i32,
}

/// Run a Lazy-SMP-style parallel search.  All workers share one
/// transposition table through [`SharedTt`] but maintain their own
/// killer / history / abort state.  The deepest completed result wins on
/// score ties; this is intentionally simpler than full YBWC and is the
/// stepping stone toward phase 5.2 in the migration plan.
///
/// `aggregate_extra_depth` is `extra_depth` from each worker added on top
/// of `base_depth`, so workers do not all hammer the same exact tree.
pub fn lazy_smp_search<G>(
    game: G,
    snapshot: GameStateSnapshot,
    base_depth: i32,
    workers: &[LazySmpWorker],
    options: SearchOptions,
    shared_tt: SharedTt,
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

    let mut handles = Vec::with_capacity(workers.len());
    for worker in workers {
        let game_for_worker = game.clone();
        let shared_tt = shared_tt.clone();
        let options_for_worker = options;
        let snapshot_for_worker = snapshot;
        let depth = (base_depth + worker.extra_depth).max(1);
        handles.push(thread::spawn(move || {
            let mut searcher = Searcher::<G>::with_shared_tt(shared_tt);
            searcher.set_options(options_for_worker);
            let mut wb = game_for_worker.build_workbench(&snapshot_for_worker);
            searcher.iterative_deepening(&mut wb, depth)
        }));
    }

    let mut best: Option<SearchResult> = None;
    for h in handles {
        let result = h.join().expect("lazy-smp worker panicked");
        if best.as_ref().is_none_or(|prev| result.score > prev.score) {
            best = Some(result);
        }
    }
    best.expect("at least one lazy-smp worker should run")
}

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
}

impl Default for MctsOptions {
    fn default() -> Self {
        Self {
            iterations: 2048,
            playout_depth: 6,
            time_limit_ms: None,
            exploration: 0.5,
        }
    }
}

#[derive(Clone, Debug)]
struct MctsNode {
    action: Action,
    children: Vec<usize>,
    untried: Vec<Action>,
    visits: u32,
    wins: u32,
    move_index: usize,
}

impl MctsNode {
    fn root(untried: Vec<Action>) -> Self {
        Self {
            action: Action::NONE,
            children: Vec::new(),
            untried,
            visits: 0,
            wins: 0,
            move_index: 0,
        }
    }

    fn child(_parent: usize, action: Action, untried: Vec<Action>, move_index: usize) -> Self {
        Self {
            action,
            children: Vec::new(),
            untried,
            visits: 0,
            wins: 0,
            move_index,
        }
    }

    fn win_score(&self) -> f64 {
        if self.visits == 0 {
            0.0
        } else {
            self.wins as f64 / self.visits as f64
        }
    }
}

pub struct MctsSearcher<G: Game> {
    rng_state: u64,
    exploration: f64,
    _phantom: PhantomData<G>,
}

impl<G: Game> Default for MctsSearcher<G> {
    fn default() -> Self {
        Self {
            rng_state: 0xD1B5_4A32_D192_ED03,
            exploration: 0.5,
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
        G::generate_legal(wb, &mut root_moves);
        if root_moves.is_empty() {
            return MctsResult {
                best_action: Action::NONE,
                visits: 0,
                wins: 0,
            };
        }

        let root_untried = root_moves.into_iter().collect::<Vec<_>>();
        let total_iterations = options.iterations.max(1) as usize * root_untried.len().max(1);
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

            // Expansion: pick one untried action and create a child.
            if !nodes[node_idx].untried.is_empty() {
                let pick = self.next_random_index(nodes[node_idx].untried.len());
                let action = nodes[node_idx].untried.swap_remove(pick);
                wb.do_move(action);
                applied_moves += 1;

                let mut child_moves = ActionList::<256>::new();
                G::generate_legal(wb, &mut child_moves);
                let move_index = nodes[node_idx].children.len();
                let child_idx = nodes.len();
                nodes.push(MctsNode::child(
                    node_idx,
                    action,
                    child_moves.into_iter().collect(),
                    move_index,
                ));
                nodes[node_idx].children.push(child_idx);
                node_idx = child_idx;
                path.push(node_idx);
            }

            let mut win = self.simulate(wb, options.playout_depth);

            for _ in 0..applied_moves {
                wb.undo_move();
            }

            // Backpropagate.  Alternate win perspective at each parent, matching
            // the mature C++ implementation.
            for idx in path.into_iter().rev() {
                nodes[idx].visits += 1;
                if win {
                    nodes[idx].wins += 1;
                }
                win = !win;
            }
        }

        let Some(best_child) = nodes[0]
            .children
            .iter()
            .copied()
            .max_by_key(|idx| nodes[*idx].visits)
        else {
            return MctsResult {
                best_action: Action::NONE,
                visits: 0,
                wins: 0,
            };
        };

        MctsResult {
            best_action: nodes[best_child].action,
            visits: nodes[best_child].visits,
            wins: nodes[best_child].wins,
        }
    }

    fn best_uct_child(&self, nodes: &[MctsNode], node_idx: usize) -> usize {
        let parent_visits = nodes[node_idx].visits.max(1) as f64;
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

    fn uct_value(&self, node: &MctsNode, parent_visits: f64) -> f64 {
        if node.visits == 0 {
            return f64::INFINITY;
        }
        let mean = node.win_score();
        let exploration = self.exploration * (2.0 * parent_visits.ln() / node.visits as f64).sqrt();
        let variance = ((mean * (1.0 - mean)) / node.visits as f64).sqrt();
        let bias = 0.05 * (256.0 - node.move_index as f64);
        mean + exploration + variance + bias
    }

    fn simulate(&mut self, wb: &mut G::Workbench, depth: i32) -> bool {
        if depth <= 0 || wb.is_terminal() {
            return G::Evaluator::score(wb) > 0;
        }
        let mut moves = ActionList::<256>::new();
        G::generate_legal(wb, &mut moves);
        if moves.is_empty() {
            return G::Evaluator::score(wb) > 0;
        }
        let idx = self.next_random_index(moves.len());
        wb.do_move(moves[idx]);
        let win = !self.simulate(wb, depth - 1);
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

#[cfg(test)]
mod tests {
    use super::*;
    use tgf_core::{Evaluator, GameRules, GameStateSnapshot, Workbench};
    use tgf_mill::{MillActionKind, MillGame, MillRules, MillVariantOptions};

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
            // Intentionally keep side unchanged to model a mill-removal
            // obligation.  The search must NOT negate this branch.
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
            if wb.moved {
                42
            } else {
                0
            }
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
        assert_eq!(result.score, 42);
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

        let packed = TtPackedEntry::pack(0x1234_5678_9abc_def0, entry);
        let unpacked = TtPackedEntry::unpack_entry(packed);

        assert_eq!(unpacked.value, entry.value);
        assert_eq!(unpacked.depth, entry.depth);
        assert_eq!(unpacked.bound, entry.bound);
        assert_eq!(unpacked.best_action, entry.best_action);
        assert_ne!(packed, 0);
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
        );

        assert!(!result.best_action.is_none());
        assert_eq!(result.best_action.kind_tag, MillActionKind::Place as i16);
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
    fn mill_search_scores_n_move_rule_draw_as_zero() {
        let options = MillVariantOptions {
            n_move_rule: 1,
            ..MillVariantOptions::default()
        };
        let rules = MillRules::new(options.clone());
        let game = MillGame::new(options);
        let snap = rules.no_mill_moving_phase_snapshot();
        let mut wb = game.build_workbench(&snap);
        let mut searcher = Searcher::<MillGame>::new();

        let result = searcher.search(&mut wb, 1);

        assert_eq!(result.score, 0);
    }

    #[test]
    fn node_limit_marks_search_as_aborted() {
        let rules = MillRules::default();
        let game = MillGame::default();
        let snap = rules.initial_state(&[]);
        let mut wb = game.build_workbench(&snap);
        let mut searcher = Searcher::<MillGame>::new();
        searcher.set_options(SearchOptions {
            depth_extension: false,
            node_limit: Some(1),
            time_limit_ms: None,
        });

        let _ = searcher.search(&mut wb, 3);
        assert!(searcher.was_aborted());
    }

    #[test]
    fn depth_extension_option_is_accepted() {
        let rules = MillRules::default();
        let game = MillGame::default();
        let snap = rules.initial_state(&[]);
        let mut wb = game.build_workbench(&snap);
        let mut searcher = Searcher::<MillGame>::new();
        searcher.set_options(SearchOptions {
            depth_extension: true,
            node_limit: None,
            time_limit_ms: None,
        });

        let result = searcher.search(&mut wb, 1);
        assert!(!result.best_action.is_none());
    }

    #[test]
    fn wall_clock_time_limit_marks_search_as_aborted() {
        let rules = MillRules::default();
        let game = MillGame::default();
        let snap = rules.initial_state(&[]);
        let mut wb = game.build_workbench(&snap);
        let mut searcher = Searcher::<MillGame>::new();
        searcher.set_options(SearchOptions {
            depth_extension: false,
            node_limit: None,
            time_limit_ms: Some(0),
        });

        let _ = searcher.search(&mut wb, 3);
        assert!(searcher.was_aborted());
    }

    #[test]
    fn perft_initial_position_returns_24_at_depth_one() {
        let rules = MillRules::default();
        let game = MillGame::default();
        let snap = rules.initial_state(&[]);
        let mut wb = game.build_workbench(&snap);

        assert_eq!(perft::<MillGame>(&mut wb, 0), 1);
        assert_eq!(perft::<MillGame>(&mut wb, 1), 24);
    }

    #[test]
    fn external_abort_handle_can_request_abort() {
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
            },
        );
        assert!(!result.best_action.is_none());
    }
}
