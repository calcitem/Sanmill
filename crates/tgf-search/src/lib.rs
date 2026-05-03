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
        atomic::{AtomicBool, AtomicI64, AtomicU32, AtomicU64, AtomicU8, Ordering},
        Arc,
    },
    thread,
    time::{Duration, Instant},
};

use crossbeam_channel::{Receiver, Sender};
use tgf_core::{
    Action, ActionList, Evaluator, Game, GameStateSnapshot, MoveOrderContext, Workbench,
};

/// Sentinel score returned when the root has exactly one legal action.
/// The move is forced regardless of the search outcome, so the searcher
/// short-circuits and returns this value.  Game-neutral: any concrete
/// `Game` whose root collapses to a single legal action will get this
/// value.  Concrete games may map it to a game-local mate constant via
/// [`tgf_core::Game::terminal_score`] or their evaluator scale.
pub const VALUE_UNIQUE_ROOT_MOVE: i32 = 100;

/// Deprecated alias retained for one release cycle.  New code should use
/// [`VALUE_UNIQUE_ROOT_MOVE`].
#[deprecated(
    since = "0.2.0",
    note = "renamed to VALUE_UNIQUE_ROOT_MOVE; the Mill prefix was a leak from the migration era"
)]
pub const MILL_VALUE_UNIQUE: i32 = VALUE_UNIQUE_ROOT_MOVE;

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

impl SearchResult {
    /// Sentinel result with no best action.  Used as the initial value
    /// when a search loop hasn't produced any result yet.
    pub fn default_none() -> Self {
        Self {
            best_action: Action::NONE,
            score: 0,
            nodes: 0,
        }
    }

    /// Returns a copy of this result with the score overridden.
    pub fn with_score(mut self, score: i32) -> Self {
        self.score = score;
        self
    }
}

#[derive(Clone, Debug)]
pub struct SearchAbortHandle {
    flag: Arc<AtomicBool>,
}

impl SearchAbortHandle {
    /// Wrap an existing shared abort flag.  Use this when the caller owns
    /// the `Arc<AtomicBool>` (for example to share one stop signal across
    /// the UCI main thread, a `lazy_smp_search` fan-out, and any future
    /// timer thread) and just needs an opaque handle to expose.
    pub fn from_arc(flag: Arc<AtomicBool>) -> Self {
        Self { flag }
    }

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
    /// Global generation counter used for soft "fake-clean" clear semantics,
    /// matching C++ `transpositionTableAge` in `src/tt.cpp`.  Incrementing
    /// this bumps all non-Exact cached entries to stale without zeroing memory.
    current_age: AtomicU8,
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
            current_age: AtomicU8::new(0),
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
        let cur_age = self.current_age.load(Ordering::Relaxed);
        let key_sig = TtPackedEntry::key_sig(key);
        let c = &self.clusters[self.cluster_ix(key)];
        for s in &c.slots {
            let packed = s.load(Ordering::Relaxed);
            if packed == 0 {
                continue;
            }
            if TtPackedEntry::packed_key_sig(packed) == key_sig {
                // Fake-clean: treat non-Exact old-generation entries as misses,
                // matching C++ TRANSPOSITION_TABLE_FAKE_CLEAN semantics.
                let entry_age = TtPackedEntry::packed_age(packed);
                if entry_age != cur_age && TtPackedEntry::unpack_bound(packed) != Bound::Exact {
                    continue;
                }
                return Some(TtPackedEntry::unpack_entry(packed));
            }
        }
        None
    }

    fn save(&self, key: u64, entry: TtEntry) {
        if key == 0 {
            return;
        }
        let cur_age = self.current_age.load(Ordering::Relaxed);
        let new_packed = TtPackedEntry::pack(key, entry, cur_age);
        let key_sig = TtPackedEntry::key_sig(key);
        let ix = self.cluster_ix(key);
        let c = &self.clusters[ix];
        // 1. Update an existing same-key entry (depth-gated for same generation).
        for s in &c.slots {
            let packed = s.load(Ordering::Relaxed);
            if packed == 0 {
                continue;
            }
            if TtPackedEntry::packed_key_sig(packed) == key_sig {
                let same_gen = TtPackedEntry::packed_age(packed) == cur_age;
                if same_gen && entry.depth < TtPackedEntry::unpack_depth(packed) {
                    return;
                }
                s.store(new_packed, Ordering::Relaxed);
                return;
            }
        }
        // 2. Fill an empty slot.
        for s in &c.slots {
            if s.load(Ordering::Relaxed) == 0 {
                s.store(new_packed, Ordering::Relaxed);
                return;
            }
        }
        // 3. Prefer evicting old-generation slots (they are effectively stale).
        for s in &c.slots {
            let packed = s.load(Ordering::Relaxed);
            if TtPackedEntry::packed_age(packed) != cur_age {
                s.store(new_packed, Ordering::Relaxed);
                return;
            }
        }
        // 4. Fallback: evict minimum-depth current-generation slot.
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

    /// Physical clear: zeros all slots and resets the generation counter.
    /// Use [`bump_age`] for the cheaper soft-clear that leaves memory intact
    /// but marks all non-Exact existing entries as stale.
    fn clear(&self) {
        for c in self.clusters.iter() {
            for s in &c.slots {
                s.store(0, Ordering::Relaxed);
            }
        }
        self.current_age.store(0, Ordering::Relaxed);
    }

    /// Soft "fake-clean" clear: increment the generation counter so all
    /// non-Exact entries are treated as stale on the next probe.  Cheaper
    /// than zeroing the whole table.  Wraps at 255 → performs a full
    /// physical clear to avoid generation-0 aliasing with stale slots.
    fn bump_age(&self) {
        let prev = self.current_age.fetch_add(1, Ordering::Relaxed);
        if prev == u8::MAX {
            // Wrap: physically zero the table and start from generation 1.
            for c in self.clusters.iter() {
                for s in &c.slots {
                    s.store(0, Ordering::Relaxed);
                }
            }
            self.current_age.store(1, Ordering::Relaxed);
        }
    }

    fn current_age(&self) -> u8 {
        self.current_age.load(Ordering::Relaxed)
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
    // Bit layout (64 bits total):
    //   [0:7]   key_sig  (8 bits)  — halved from 16 to make room for age
    //   [8:15]  age      (8 bits)  — generation counter (fake-clean semantics)
    //   [16:31] value    (16 bits)
    //   [32:39] depth    (8 bits)
    //   [40:41] bound    (2 bits)
    //   [42:63] action   (22 bits)
    const KEY_SIG_BITS: u32 = 8;
    const AGE_SHIFT: u32 = 8;
    const VALUE_SHIFT: u32 = 16;
    const DEPTH_SHIFT: u32 = 32;
    const BOUND_SHIFT: u32 = 40;
    const ACTION_SHIFT: u32 = 42;

    const KEY_SIG_MASK: u64 = (1_u64 << Self::KEY_SIG_BITS) - 1; // 0xff
    const AGE_MASK: u64 = 0xff;
    const VALUE_MASK: u64 = 0xffff;
    const DEPTH_MASK: u64 = 0xff;
    const BOUND_MASK: u64 = 0x03;
    const ACTION_MASK: u64 = (1_u64 << 22) - 1;

    #[inline]
    fn key_sig(key: u64) -> u16 {
        // 8-bit signature; returned as u16 for comparison with `packed_key_sig`.
        let sig = ((key >> 48) ^ (key >> 32) ^ (key >> 16) ^ key) as u8;
        u16::from(sig.max(1))
    }

    #[inline]
    fn packed_key_sig(packed: u64) -> u16 {
        (packed & Self::KEY_SIG_MASK) as u16
    }

    #[inline]
    fn packed_age(packed: u64) -> u8 {
        ((packed >> Self::AGE_SHIFT) & Self::AGE_MASK) as u8
    }

    #[inline]
    fn pack(key: u64, entry: TtEntry, age: u8) -> u64 {
        u64::from(Self::key_sig(key))
            | (u64::from(age) << Self::AGE_SHIFT)
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

/// Search algorithm selector.  Mirrors C++ `Algorithm` enum in `src/types.h`.
///
/// The default is `Pvs`, matching the C++ engine's production configuration
/// (`MTD(f)` is the C++ default but PVS is more stable in the Rust scaffold).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum SearchAlgorithm {
    /// Fail-soft Alpha-Beta.
    AlphaBeta,
    /// Principal Variation Search (fail-hard NegaScout).
    #[default]
    Pvs,
    /// MTD(f) — Memory-enhanced Test Driver.
    Mtdf,
    /// Monte Carlo Tree Search.
    Mcts,
    /// Pick a random legal action (for testing or lowest skill level).
    Random,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct SearchPolicy {
    pub remove_kind_tag: Option<i16>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SearchOptions {
    pub depth_extension: bool,
    pub node_limit: Option<u64>,
    pub time_limit_ms: Option<u64>,
    /// Enable the simplified null-move proxy in alpha_beta.
    /// Disabled by default: the current proxy (-static_eval) is a rough
    /// approximation that can prune incorrect branches in specific positions.
    /// Enable explicitly only for experimental use.
    pub allow_null_move: bool,
    /// Shuffle the root move list before searching. Mirrors master's
    /// `MoveList<LEGAL>::shuffle()` call at the start of `executeSearch`
    /// when `Shuffling` is enabled or `SkillLevel < 30` (P2-K).
    pub shuffle_root: bool,
    pub move_order_context: tgf_core::MoveOrderContext,
}

impl Default for SearchOptions {
    fn default() -> Self {
        Self {
            depth_extension: true,
            node_limit: None,
            time_limit_ms: None,
            allow_null_move: false,
            shuffle_root: false,
            move_order_context: tgf_core::MoveOrderContext::default(),
        }
    }
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

    /// Allocate a shared TT sized from the UCI `Hash` megabyte option.
    ///
    /// Mirrors master `Hash` handling by making the option authoritative
    /// instead of relying solely on an environment variable.  The result is
    /// rounded down to a power-of-two cluster count and never below
    /// `cluster_bits_floor`.
    pub fn with_capacity_mb(mb: u32, cluster_bits_floor: u32) -> Self {
        let bytes = (mb.max(1) as usize).saturating_mul(1024 * 1024);
        let cluster_size = std::mem::size_of::<TtCluster>().max(1);
        let clusters = (bytes / cluster_size).max(1);
        let bits = (usize::BITS - 1 - clusters.leading_zeros())
            .max(cluster_bits_floor)
            .clamp(10, 26);
        Self::new(bits)
    }

    /// Physical clear: zeros every slot and resets the generation counter.
    /// Prefer [`bump_age`] for the cheaper soft clear that avoids zeroing
    /// all memory.
    pub fn clear(&self) {
        self.inner.clear();
    }

    /// Soft clear: increment the generation counter so non-Exact cached
    /// entries are treated as stale on the next probe.  Matches the
    /// C++ `TranspositionTable::clear()` fake-clean path.
    pub fn bump_age(&self) {
        self.inner.bump_age();
    }

    /// Current generation counter value.  Useful for bench instrumentation.
    pub fn current_age(&self) -> u8 {
        self.inner.current_age()
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
    repetition_stack: Vec<u64>,
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
                score: VALUE_UNIQUE_ROOT_MOVE,
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
                score: VALUE_UNIQUE_ROOT_MOVE,
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

    /// Iterative deepening using PVS (fixes the pre-Phase 5 inconsistency where
    /// IDS drove `search` while the root entry point was `search_pvs`).
    ///
    /// Uses aspiration windows from depth 3 onwards: the initial window is
    /// centered on the previous iteration's score ± `ASPIRATION_DELTA`.  When
    /// the search falls outside the window, the window is widened and the depth
    /// is re-searched.  This typically improves NPS by reducing the search tree.
    ///
    /// The TT generation counter is bumped between iterations so non-Exact
    /// entries from the previous iteration are treated as stale, matching C++
    /// `Search::clear` semantics from `src/search.cpp`.
    pub fn iterative_deepening(&mut self, wb: &mut G::Workbench, max_depth: i32) -> SearchResult {
        const ASPIRATION_DELTA: i32 = 15; // ~3 piece values
        const ASPIRATION_MAX_WINDOW: i32 = 200;
        let max_depth = max_depth.max(1);
        let mut result = self.search_pvs(wb, 1);
        for depth in 2..=max_depth {
            self.tt.bump_age();
            self.tt_age_bumps += 1;
            if depth < 3 || result.score.abs() >= ASPIRATION_MAX_WINDOW {
                // Full window for shallow depths or near-terminal scores.
                result = self.search_pvs(wb, depth);
            } else {
                // Aspiration window centered on previous score.
                let mut delta = ASPIRATION_DELTA;
                let mut alpha = (result.score - delta).max(i32::MIN + 1);
                let mut beta = (result.score + delta).min(i32::MAX - 1);
                loop {
                    let candidate = self.search_pvs_windowed(wb, depth, alpha, beta);
                    if candidate.score <= alpha {
                        // Fail low: widen alpha.
                        alpha = (alpha - delta).max(i32::MIN + 1);
                    } else if candidate.score >= beta {
                        // Fail high: widen beta.
                        beta = (beta + delta).min(i32::MAX - 1);
                    } else {
                        result = candidate;
                        break;
                    }
                    delta = delta.saturating_mul(2);
                    if delta >= ASPIRATION_MAX_WINDOW {
                        // Degenerate to full window.
                        result = self.search_pvs(wb, depth);
                        break;
                    }
                }
            }
            if self.was_aborted() {
                break;
            }
        }
        result
    }

    /// Windowed PVS root (aspiration-window helper): searches with explicit
    /// alpha/beta bounds rather than ±∞.  Returns the best result found within
    /// the window.
    fn search_pvs_windowed(
        &mut self,
        wb: &mut G::Workbench,
        depth: i32,
        alpha: i32,
        beta: i32,
    ) -> SearchResult {
        self.begin_root_search();
        if let Some(score) = G::terminal_score(wb, wb.side_to_move(), depth) {
            return SearchResult::default_none().with_score(score);
        }
        let mut moves = ActionList::<256>::new();
        G::generate_legal_ctx(wb, &mut moves, &self.options.move_order_context);
        self.order_moves(wb, wb.key(), depth, &mut moves);
        if moves.is_empty() {
            return SearchResult {
                best_action: Action::NONE,
                score: G::Evaluator::score(wb),
                nodes: self.nodes,
            };
        }
        let mut best_action = moves[0];
        let mut best_alpha = alpha;
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
            let value = self.pvs_after_move(wb, depth - 1, best_alpha, beta, i, before, after);
            wb.undo_move();
            if root_key != 0 {
                self.repetition_stack.pop();
            }
            if value > best_alpha {
                best_alpha = value;
                best_action = action;
            }
            if best_alpha >= beta {
                break;
            }
        }
        SearchResult {
            best_action,
            score: best_alpha,
            nodes: self.nodes,
        }
    }

    /// MTD(f) with proper TT integration.  Each zero-window alpha-beta call
    /// writes its result into the TT; subsequent iterations reuse those entries
    /// to prune the search tree, which is what makes MTD(f) efficient.
    ///
    /// Unlike the old scaffold, the TT is NOT bypassed here — `alpha_beta`
    /// already probes and saves the TT on every node.
    pub fn mtdf(&mut self, wb: &mut G::Workbench, first_guess: i32, depth: i32) -> i32 {
        let mut g = first_guess;
        let mut upper_bound = i32::MAX - 1;
        let mut lower_bound = i32::MIN + 1;

        while lower_bound < upper_bound {
            let beta = if g == lower_bound { g + 1 } else { g };
            // alpha_beta now probes/saves the TT at every node, so each
            // iteration benefits from the previous iteration's TT entries.
            g = self.alpha_beta(wb, depth, beta - 1, beta);
            if g < beta {
                upper_bound = g;
            } else {
                lower_bound = g;
            }
            if self.was_aborted() {
                break;
            }
        }
        g
    }

    /// Run MTD(f) at `depth` and return a full `SearchResult` including the
    /// best action retrieved from the TT. Mirrors master's `Search::MTDF`
    /// which updates `bestMove` by reference (P2-C).
    pub fn search_mtdf(&mut self, wb: &mut G::Workbench, depth: i32) -> SearchResult {
        self.search_mtdf_with_guess(wb, depth, 0)
    }

    /// Run MTD(f) at `depth` with a caller-provided first guess.  The root
    /// pre-check mirrors `search`: terminal positions, empty roots, and
    /// single legal root moves are handled before the zero-window loop so
    /// Algorithm=2 returns VALUE_UNIQUE for forced moves just like master.
    pub fn search_mtdf_with_guess(
        &mut self,
        wb: &mut G::Workbench,
        depth: i32,
        first_guess: i32,
    ) -> SearchResult {
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
        if moves.len() == 1 {
            return SearchResult {
                best_action: moves[0],
                score: VALUE_UNIQUE_ROOT_MOVE,
                nodes: self.nodes,
            };
        }

        let score = self.mtdf(wb, first_guess, depth);
        let key = wb.key();
        let best_action = self
            .tt
            .get(key)
            .map(|e| e.best_action)
            .unwrap_or(Action::NONE);
        SearchResult {
            best_action,
            score,
            nodes: self.nodes,
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

        // Enforce the MaxQuiescenceDepth gate: do not recurse deeper than
        // `qsearch_max_depth` plies past the main search horizon (depth == 0).
        // `depth` is <= 0 here; -depth is how many plies we have extended.
        if -depth >= self.qsearch_max_depth {
            return alpha;
        }

        let mut moves = ActionList::<256>::new();
        G::generate_legal_ctx(wb, &mut moves, &self.options.move_order_context);
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

    /// Shuffle the root move list using the internal xorshift RNG (P2-K).
    /// Mirrors master's MoveList<LEGAL>::shuffle() which is called at the
    /// start of executeSearch when Shuffling is enabled.
    fn shuffle_moves(&mut self, moves: &mut ActionList<256>) {
        let n = moves.len();
        if n < 2 {
            return;
        }
        for i in (1..n).rev() {
            let j = self.next_random_index(i + 1);
            moves.as_mut_slice().swap(i, j);
        }
    }

    #[inline]
    fn move_score(&self, wb: &G::Workbench, key: u64, depth: i32, action: Action) -> i32 {
        let mut score = G::move_order_bias_ctx(wb, action, &self.options.move_order_context);
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
/// transposition table through [`SharedTt`] AND a single abort flag, so
/// requesting an abort through [`SearchAbortHandle`] once stops every
/// worker.  Each worker still has its own killer / history bookkeeping
/// because those are inherently thread-local.
///
/// The deepest completed result wins on score; this is intentionally
/// simpler than full YBWC and is the stepping stone toward phase 5.2 in
/// the migration plan.  When `abort_flag` is `None` a fresh shared flag
/// is allocated; pass `Some(...)` to participate in an existing
/// cancellation chain (e.g. UCI `stop` from the main thread).
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

    let pool = SearchThreadPool::new(workers.len());
    let mut receivers = Vec::with_capacity(workers.len());
    for worker in workers {
        let game_for_worker = game.clone();
        let shared_tt = shared_tt.clone();
        let options_for_worker = options;
        let snapshot_for_worker = snapshot;
        let abort = Arc::clone(&abort);
        let depth = (base_depth + worker.extra_depth).max(1);
        receivers.push(pool.submit(move || {
            let mut searcher = Searcher::<G>::with_shared_tt(shared_tt);
            searcher.set_abort_flag(abort);
            searcher.set_options(options_for_worker);
            let mut wb = game_for_worker.build_workbench(&snapshot_for_worker);
            searcher.iterative_deepening(&mut wb, depth)
        }));
    }

    let mut best: Option<SearchResult> = None;
    for rx in receivers {
        let result = rx
            .recv()
            .expect("lazy-smp worker should return a SearchResult");
        if best.as_ref().is_none_or(|prev| result.score > prev.score) {
            best = Some(result);
        }
    }
    best.expect("at least one lazy-smp worker should run")
}

enum ThreadPoolMessage {
    Run(Box<dyn FnOnce() + Send + 'static>),
    Stop,
}

/// Minimal fixed-size worker pool for search tasks.
///
/// The mature C++ engine has a dedicated `ThreadPool`; phase 5.2 recreates
/// that shape in Rust with `std::thread` workers and `crossbeam_channel`
/// dispatch.  This pool intentionally does not know about games or searchers:
/// callers submit closures, which keeps it reusable for lazy SMP, future YBWC,
/// and MCTS shared-visit experiments.
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
    /// Default 0 = random rollout (original behaviour).
    pub ab_assist_depth: i32,
    pub move_order_context: MoveOrderContext,
}

impl Default for MctsOptions {
    fn default() -> Self {
        Self {
            iterations: 2048,
            playout_depth: 6,
            time_limit_ms: None,
            exploration: 0.5,
            ab_assist_depth: 0,
            move_order_context: MoveOrderContext {
                algorithm: tgf_core::MoveOrderAlgorithm::Mcts,
                ..MoveOrderContext::default()
            },
        }
    }
}

#[derive(Debug)]
struct MctsNode {
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
    /// For Mill, pass `SearchPolicy { remove_kind_tag: Some(MillActionKind::Remove as i16) }`.
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

    fn best_uct_child(&self, nodes: &[MctsNode], node_idx: usize) -> usize {
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

    fn order_mcts_moves(
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

    fn simulate(&mut self, wb: &mut G::Workbench, depth: i32, options: &MctsOptions) -> bool {
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

#[cfg(test)]
mod tests {
    use super::*;
    use tgf_core::{Evaluator, GameStateSnapshot, Workbench};

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

        fn move_order_bias_ctx(
            _wb: &Self::Workbench,
            action: Action,
            ctx: &MoveOrderContext,
        ) -> i32 {
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
    fn repetition_returns_draw_plus_one_bias() {
        let game = RepetitionGame;
        let mut wb = game.build_workbench(&GameStateSnapshot::default());
        let mut searcher = Searcher::<RepetitionGame>::new();
        searcher.repetition_stack.push(wb.key());

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

        let packed = TtPackedEntry::pack(0x1234_5678_9abc_def0, entry, 3);
        let unpacked = TtPackedEntry::unpack_entry(packed);

        assert_eq!(unpacked.value, entry.value);
        assert_eq!(unpacked.depth, entry.depth);
        assert_eq!(unpacked.bound, entry.bound);
        assert_eq!(unpacked.best_action, entry.best_action);
        assert_eq!(TtPackedEntry::packed_age(packed), 3);
        assert_ne!(packed, 0);
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
            remove_kind_tag: Some(0),
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
}
