// SPDX-License-Identifier: GPL-3.0-or-later
// Packed transposition table shared by every searcher in the crate.
//
// `ClusteredTt` is a fixed-size array of small buckets.  Each bucket holds
// several packed `AtomicU64` entries so unrelated keys that map to the same
// index do not immediately evict each other.  The atomic packing lets multiple
// `Searcher<G>` instances probe / save concurrently in lazy-SMP configurations
// (see `crate::thread_pool::lazy_smp_search`) without any locking on the hot
// path.

#[cfg(target_os = "linux")]
use std::ffi::{c_int, c_void};
use std::{
    alloc::{Layout, alloc, dealloc, handle_alloc_error},
    ops::Index,
    ptr::NonNull,
    slice,
    sync::{
        Arc,
        atomic::{AtomicU8, AtomicU16, AtomicU64, Ordering},
    },
};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Bound {
    Exact,
    Lower,
    Upper,
}

#[derive(Clone, Copy, Debug)]
pub(crate) struct TtEntry {
    pub value: i32,
    pub depth: i32,
    pub bound: Bound,
    pub tt_move: u16,
}

pub(crate) const TT_MOVE_NONE: u16 = 0;

#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct TtProbeEntry {
    pub value_bound: Option<(i32, Bound)>,
    pub tt_move: Option<u16>,
}

// ---------------------------------------------------------------------------
// Clustered TT: fixed `2^cluster_bits` packed atomic slots.
// ---------------------------------------------------------------------------

const TT_CLUSTER_ENTRY_COUNT: usize = 4;
const TT_CLUSTER_ENTRY_BITS: u32 = 2;

/// One TT bucket containing several packed entries.
///
/// Master `src/tt.h` stores a `TTEntry { value8, depth8, genBound8 }`
/// plus optional `ttMove` when `TT_MOVE_ENABLE` is compiled in.
/// The Rust packing widens the key signature to 32 bits to match
/// master's default `Key = uint32_t` (TRANSPOSITION_TABLE_64BIT_KEY
/// undefined) instead of 8 bits.  Optional TT moves live in the same
/// 64-byte bucket as the packed meta slots so probe/save touches one
/// cache line instead of a separate side array.
///
/// Entry layout:
///   * meta (u64): [key_sig:32][age:6][value:16][depth:8][bound:2]
///   * move (u16): compact Mill action codec, parallel to each meta slot
///
/// Total meta size = 32 bytes; bucket size = 64 bytes (one cache line).
/// `cluster_bits` remains a total-slot count at API boundaries.
#[repr(C, align(64))]
pub(crate) struct TtCluster {
    pub(crate) entries: [AtomicU64; TT_CLUSTER_ENTRY_COUNT],
    moves: [AtomicU16; TT_CLUSTER_ENTRY_COUNT],
}

impl TtCluster {
    #[inline]
    fn empty() -> Self {
        Self {
            entries: std::array::from_fn(|_| AtomicU64::new(0)),
            moves: std::array::from_fn(|_| AtomicU16::new(TT_MOVE_NONE)),
        }
    }

    #[inline]
    fn iter_entries(&self) -> impl Iterator<Item = &AtomicU64> {
        self.entries.iter()
    }

    #[inline]
    fn clear_slots(&self) {
        for slot in self.iter_entries() {
            slot.store(0, Ordering::Relaxed);
        }
        for mv in self.moves.iter() {
            mv.store(TT_MOVE_NONE, Ordering::Relaxed);
        }
    }
}

pub(crate) const TT_STORAGE_ALIGNMENT: usize = 4096;

pub(crate) struct TtStorage {
    ptr: NonNull<TtCluster>,
    len: usize,
    layout: Layout,
}

// The storage owns a contiguous allocation of `TtCluster`, and each cluster
// is accessed through atomics. Sharing the backing allocation across search
// threads is therefore as safe as sharing a boxed `[TtCluster]`.
unsafe impl Send for TtStorage {}
unsafe impl Sync for TtStorage {}

impl TtStorage {
    fn new(len: usize) -> Self {
        assert!(len > 0, "TT storage length must be non-zero");
        let bytes = len
            .checked_mul(std::mem::size_of::<TtCluster>())
            .expect("TT storage size overflow");
        let align = TT_STORAGE_ALIGNMENT.max(std::mem::align_of::<TtCluster>());
        debug_assert!(align.is_power_of_two());
        let layout = Layout::from_size_align(bytes, align).expect("invalid TT storage layout");
        // Match Stockfish/master's page-aligned TT allocation path while
        // keeping Sanmill's packed 8-byte slots. We explicitly construct
        // each AtomicU64 so the table is fully first-touched at allocation,
        // preserving the old Vec-backed allocation behaviour.
        let ptr = unsafe { alloc(layout) };
        let Some(ptr) = NonNull::new(ptr.cast::<TtCluster>()) else {
            handle_alloc_error(layout);
        };
        advise_huge_pages(ptr.as_ptr().cast::<u8>(), bytes);
        for i in 0..len {
            unsafe { ptr.as_ptr().add(i).write(TtCluster::empty()) };
        }
        Self { ptr, len, layout }
    }

    #[cfg(test)]
    #[inline]
    pub(crate) fn as_ptr(&self) -> *const TtCluster {
        self.ptr.as_ptr()
    }

    #[inline]
    pub(crate) fn iter(&self) -> slice::Iter<'_, TtCluster> {
        unsafe { slice::from_raw_parts(self.ptr.as_ptr(), self.len) }.iter()
    }
}

#[cfg(target_os = "linux")]
fn advise_huge_pages(ptr: *mut u8, bytes: usize) {
    const MADV_HUGEPAGE: c_int = 14;
    unsafe extern "C" {
        fn madvise(addr: *mut c_void, length: usize, advice: c_int) -> c_int;
    }
    // Transparent huge pages are an optional kernel performance hint. Failure
    // keeps the page-aligned allocation valid and must not affect TT semantics.
    let _ = unsafe { madvise(ptr.cast::<c_void>(), bytes, MADV_HUGEPAGE) };
}

#[cfg(not(target_os = "linux"))]
fn advise_huge_pages(ptr: *mut u8, bytes: usize) {
    let _ = (ptr, bytes);
}

impl Index<usize> for TtStorage {
    type Output = TtCluster;

    #[inline]
    fn index(&self, index: usize) -> &Self::Output {
        assert!(index < self.len, "TT cluster index out of bounds");
        unsafe { &*self.ptr.as_ptr().add(index) }
    }
}

impl Drop for TtStorage {
    fn drop(&mut self) {
        for i in 0..self.len {
            unsafe { self.ptr.as_ptr().add(i).drop_in_place() };
        }
        unsafe { dealloc(self.ptr.as_ptr().cast::<u8>(), self.layout) };
    }
}

pub(crate) struct ClusteredTt {
    pub(crate) clusters: TtStorage,
    tt_move_enabled: bool,
    pub(crate) cluster_mask: usize,
    /// Global generation counter used for soft "fake-clean" clear semantics,
    /// matching C++ `transpositionTableAge` in `src/tt.cpp`. Incrementing this
    /// makes every cached entry from the old generation stale without zeroing
    /// memory.
    pub(crate) current_age: AtomicU8,
}

/// Snapshot of TT occupancy and bound mix for diagnostics.
///
/// Collecting this scans the whole table, so callers should use it at
/// benchmark / logging boundaries instead of inside the node loop.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct TtStats {
    pub slots: usize,
    pub occupied: usize,
    pub current_age_occupied: usize,
    pub stale: usize,
    pub exact: usize,
    pub lower: usize,
    pub upper: usize,
    pub depth_sum: i64,
    pub max_depth: i32,
}

impl TtStats {
    #[inline]
    pub fn load_pct(&self) -> f64 {
        ratio_pct(self.occupied, self.slots)
    }

    #[inline]
    pub fn current_age_load_pct(&self) -> f64 {
        ratio_pct(self.current_age_occupied, self.slots)
    }

    #[inline]
    pub fn stale_pct_of_occupied(&self) -> f64 {
        ratio_pct(self.stale, self.occupied)
    }

    #[inline]
    pub fn average_depth(&self) -> f64 {
        if self.current_age_occupied == 0 {
            0.0
        } else {
            self.depth_sum as f64 / self.current_age_occupied as f64
        }
    }
}

#[inline]
fn ratio_pct(numerator: usize, denominator: usize) -> f64 {
    if denominator == 0 {
        0.0
    } else {
        numerator as f64 * 100.0 / denominator as f64
    }
}

impl ClusteredTt {
    /// 24 → 16 Mi packed entries (~128 MiB), matching master
    /// `TRANSPOSITION_TABLE_SIZE = 0x1000000` (16 Mi entries) in
    /// `src/tt.cpp`.  Users with constrained memory
    /// can downsize via `Searcher::resize_tt_by_mb` or the
    /// `TGF_TT_CLUSTER_BITS` environment variable.
    pub(crate) const DEFAULT_CLUSTER_BITS: u32 = 24;

    pub(crate) fn new_with_cluster_bits(bits: u32) -> Self {
        Self::new_with_cluster_bits_and_tt_move(bits, false)
    }

    pub(crate) fn new_with_cluster_bits_and_tt_move(bits: u32, enable_tt_move: bool) -> Self {
        // Permit larger TTs: master defaults to 16 Mi slots which
        // requires cluster_bits >= 23.  Cap at 26 (≈512 MiB) to keep
        // accidental misuse from immediately exhausting memory.
        let bits = bits.clamp(10, 26);
        let cluster_bits = bits.saturating_sub(TT_CLUSTER_ENTRY_BITS);
        let n = 1usize << cluster_bits;
        let mask = n - 1;
        Self {
            clusters: TtStorage::new(n),
            tt_move_enabled: enable_tt_move,
            cluster_mask: mask,
            current_age: AtomicU8::new(0),
        }
    }

    #[inline]
    pub(crate) fn tt_move_enabled(&self) -> bool {
        self.tt_move_enabled
    }

    #[inline]
    fn cluster_ix(&self, key: u64) -> usize {
        // Use both halves of the Zobrist key for indexing.  The stored
        // signature is still the low 32 bits, so index and verification draw
        // from different mixed lanes without paying a 128-bit multiply.
        ((key as usize) ^ ((key >> 32) as usize)) & self.cluster_mask
    }

    #[cfg(test)]
    #[inline]
    pub(crate) fn cluster_index_for_key(&self, key: u64) -> usize {
        self.cluster_ix(key)
    }

    #[inline]
    fn slot_count(&self) -> usize {
        self.clusters.len * TT_CLUSTER_ENTRY_COUNT
    }

    #[inline(always)]
    pub(crate) fn get(&self, key: u64) -> Option<TtEntry> {
        let cur_age = self.current_age.load(Ordering::Relaxed);
        let key_sig = TtPackedEntry::key_sig(key);
        let cluster_ix = self.cluster_ix(key);
        let cluster = &self.clusters[cluster_ix];
        for (entry_ix, slot) in cluster.entries.iter().enumerate() {
            let meta = slot.load(Ordering::Relaxed);
            if meta == 0 || TtPackedEntry::packed_key_sig(meta) != key_sig {
                continue;
            }
            // Fake-clean: master has TRANSPOSITION_TABLE_FAKE_CLEAN enabled
            // and TRANSPOSITION_TABLE_FAKE_CLEAN_NOT_EXACT_ONLY disabled, so
            // every old-generation entry is a miss, including Exact entries.
            if TtPackedEntry::packed_age(meta) == cur_age {
                let mut entry = TtPackedEntry::unpack_entry(meta);
                entry.tt_move = self.load_tt_move(cluster, entry_ix);
                return Some(entry);
            }
        }
        None
    }

    #[inline(always)]
    pub(crate) fn probe_tt_move_at_age(&self, key: u64, cur_age: u8) -> Option<u16> {
        if !self.tt_move_enabled {
            return None;
        }
        let key_sig = TtPackedEntry::key_sig(key);
        let cluster_ix = self.cluster_ix(key);
        let cluster = &self.clusters[cluster_ix];
        for (entry_ix, slot) in cluster.entries.iter().enumerate() {
            let meta = slot.load(Ordering::Relaxed);
            if meta == 0 || TtPackedEntry::packed_key_sig(meta) != key_sig {
                continue;
            }
            if TtPackedEntry::packed_age(meta) != cur_age {
                continue;
            }
            let packed = cluster.moves[entry_ix].load(Ordering::Relaxed);
            return (packed != TT_MOVE_NONE).then_some(packed);
        }
        None
    }

    #[inline(always)]
    pub(crate) fn probe_entry_at_age(&self, key: u64, depth: i32, cur_age: u8) -> TtProbeEntry {
        let key_sig = TtPackedEntry::key_sig(key);
        let cluster_ix = self.cluster_ix(key);
        let cluster = &self.clusters[cluster_ix];
        let mut tt_move = None;
        for (entry_ix, slot) in cluster.entries.iter().enumerate() {
            let meta = slot.load(Ordering::Relaxed);
            if meta == 0 || TtPackedEntry::packed_key_sig(meta) != key_sig {
                continue;
            }
            if TtPackedEntry::packed_age(meta) != cur_age {
                continue;
            }
            if tt_move.is_none() {
                let packed = self.load_tt_move(cluster, entry_ix);
                if packed != TT_MOVE_NONE {
                    tt_move = Some(packed);
                }
            }
            if TtPackedEntry::unpack_depth(meta) < depth {
                continue;
            }
            return TtProbeEntry {
                value_bound: Some((
                    TtPackedEntry::unpack_value(meta),
                    TtPackedEntry::unpack_bound(meta),
                )),
                tt_move,
            };
        }
        TtProbeEntry {
            value_bound: None,
            tt_move,
        }
    }

    #[cfg(test)]
    #[inline(always)]
    pub(crate) fn save(&self, key: u64, entry: TtEntry) {
        let cur_age = self.current_age.load(Ordering::Relaxed);
        self.save_at_age(key, entry, cur_age);
    }

    #[inline(always)]
    pub(crate) fn save_at_age(&self, key: u64, entry: TtEntry, cur_age: u8) {
        let new_meta = TtPackedEntry::pack_meta(key, &entry, cur_age);
        let key_sig = TtPackedEntry::key_sig(key);
        let cluster_ix = self.cluster_ix(key);
        let cluster = &self.clusters[cluster_ix];
        let mut replace_index = 0usize;
        let mut replace_score = i32::MAX;

        for (i, slot) in cluster.entries.iter().enumerate() {
            let meta = slot.load(Ordering::Relaxed);
            if meta == 0 {
                replace_index = i;
                break;
            }
            if TtPackedEntry::packed_key_sig(meta) == key_sig {
                let same_gen = TtPackedEntry::packed_age(meta) == cur_age;
                if same_gen {
                    let old_depth = TtPackedEntry::unpack_depth(meta);
                    let old_bound = TtPackedEntry::unpack_bound(meta);
                    if entry.depth < old_depth
                        || (entry.depth == old_depth
                            && old_bound == Bound::Exact
                            && entry.bound != Bound::Exact)
                    {
                        return;
                    }
                }
                let tt_move = if entry.tt_move != TT_MOVE_NONE {
                    entry.tt_move
                } else {
                    self.load_tt_move(cluster, i)
                };
                self.store_tt_move(cluster, i, tt_move);
                cluster.entries[i].store(new_meta, Ordering::Relaxed);
                return;
            }

            let score = replacement_score(meta, cur_age);
            if score < replace_score {
                replace_score = score;
                replace_index = i;
            }
        }
        self.store_tt_move(cluster, replace_index, entry.tt_move);
        cluster.entries[replace_index].store(new_meta, Ordering::Relaxed);
    }

    /// Physical clear: zeros all slots and resets the generation counter.
    /// Use [`bump_age`] for the cheaper soft-clear that leaves memory intact
    /// but marks all existing entries as stale.
    pub(crate) fn clear(&self) {
        for c in self.clusters.iter() {
            c.clear_slots();
        }
        self.current_age.store(0, Ordering::Relaxed);
    }

    /// Soft "fake-clean" clear: increment the generation counter so entries
    /// from older generations are treated as stale on the next probe.  Cheaper
    /// than zeroing the whole table.  Wraps at 63 (the 6-bit age field) and
    /// performs a full physical clear to avoid generation aliasing with stale
    /// slots.
    pub(crate) fn bump_age(&self) {
        let prev = self.current_age.fetch_add(1, Ordering::Relaxed);
        // Age is encoded in 6 bits (mask 0x3f); wrap at the field max.
        if prev >= 0x3f {
            for c in self.clusters.iter() {
                c.clear_slots();
            }
            self.current_age.store(1, Ordering::Relaxed);
        }
    }

    pub(crate) fn current_age(&self) -> u8 {
        self.current_age.load(Ordering::Relaxed) & 0x3f
    }

    pub(crate) fn len_occupied(&self) -> usize {
        self.clusters
            .iter()
            .flat_map(TtCluster::iter_entries)
            .filter(|slot| slot.load(Ordering::Relaxed) != 0)
            .count()
    }

    pub(crate) fn stats(&self) -> TtStats {
        let current_age = self.current_age();
        let mut stats = TtStats {
            slots: self.slot_count(),
            ..TtStats::default()
        };
        for c in self.clusters.iter() {
            for slot in c.iter_entries() {
                let meta = slot.load(Ordering::Relaxed);
                if meta == 0 {
                    continue;
                }
                stats.occupied += 1;
                if TtPackedEntry::packed_age(meta) != current_age {
                    stats.stale += 1;
                    continue;
                }
                stats.current_age_occupied += 1;
                let depth = TtPackedEntry::unpack_depth(meta);
                stats.depth_sum += i64::from(depth);
                stats.max_depth = stats.max_depth.max(depth);
                match TtPackedEntry::unpack_bound(meta) {
                    Bound::Exact => stats.exact += 1,
                    Bound::Lower => stats.lower += 1,
                    Bound::Upper => stats.upper += 1,
                }
            }
        }
        stats
    }

    /// Issue an architecture-specific prefetch hint for the cluster
    /// that `key` would land in.  Mirrors master
    /// `TranspositionTable::prefetch` (see `src/tt.cpp`) which emits a
    /// `_mm_prefetch` for the bucket address before the search visits a
    /// child node.  When `DISABLE_PREFETCH` is undefined (the master
    /// default) this can save tens of ns per node on positions where
    /// the TT spans an L2 / L3 boundary.
    ///
    /// On unsupported targets the call is a no-op so callers can wire
    /// it unconditionally.
    #[inline]
    pub(crate) fn prefetch(&self, key: u64) {
        let ix = self.cluster_ix(key);
        let slot_ptr = self.clusters[ix].entries.as_ptr() as *const i8;
        prefetch_read(slot_ptr);
    }

    #[inline]
    fn load_tt_move(&self, cluster: &TtCluster, entry_ix: usize) -> u16 {
        if !self.tt_move_enabled {
            return TT_MOVE_NONE;
        }
        cluster.moves[entry_ix].load(Ordering::Relaxed)
    }

    #[inline]
    fn store_tt_move(&self, cluster: &TtCluster, entry_ix: usize, tt_move: u16) {
        if self.tt_move_enabled {
            cluster.moves[entry_ix].store(tt_move, Ordering::Relaxed);
        }
    }
}

#[inline]
fn replacement_score(meta: u64, cur_age: u8) -> i32 {
    let depth = TtPackedEntry::unpack_depth(meta);
    let age = (cur_age.wrapping_sub(TtPackedEntry::packed_age(meta))) & 0x3f;
    let exact_bonus = if TtPackedEntry::unpack_bound(meta) == Bound::Exact {
        2
    } else {
        0
    };
    depth + exact_bonus - i32::from(age) * 8
}

/// Architecture-specific prefetch hint helper.
///
/// On x86_64 we emit `_mm_prefetch(_, _MM_HINT_T0)` so the address is
/// pulled into all cache levels closest to the core, matching the
/// master `TT.prefetch` flag set used in C++.  On AArch64 we use the
/// `prfm` PLDL1KEEP variant; on other targets the call is a no-op.
#[inline]
fn prefetch_read(addr: *const i8) {
    #[cfg(target_arch = "x86_64")]
    unsafe {
        core::arch::x86_64::_mm_prefetch(addr, core::arch::x86_64::_MM_HINT_T0);
    }
    #[cfg(target_arch = "aarch64")]
    unsafe {
        core::arch::asm!(
            "prfm pldl1keep, [{addr}]",
            addr = in(reg) addr,
            options(nostack, preserves_flags),
        );
    }
    #[cfg(not(any(target_arch = "x86_64", target_arch = "aarch64")))]
    {
        let _ = addr;
    }
}

pub(crate) struct TtPackedEntry;

impl TtPackedEntry {
    // Meta bit layout (64 bits total):
    //   [0:31]  key_sig  (32 bits)  — matches master `Key = uint32_t`
    //   [32:37] age      (6 bits)   — generation counter (fake-clean)
    //   [38:53] value    (16 bits)
    //   [54:61] depth    (8 bits)
    //   [62:63] bound    (2 bits)
    //
    // Master itself drops the move when TT_MOVE_ENABLE is undefined, which
    // only affects `MovePicker::score`'s ttMove bonus.  Rust stores the move
    // in the same 64-byte bucket as the packed meta slots when enabled.
    const KEY_SIG_MASK: u64 = 0xffff_ffff;
    const AGE_SHIFT: u32 = 32;
    const VALUE_SHIFT: u32 = 38;
    const DEPTH_SHIFT: u32 = 54;
    const BOUND_SHIFT: u32 = 62;

    const AGE_MASK: u64 = 0x3f;
    const VALUE_MASK: u64 = 0xffff;
    const DEPTH_MASK: u64 = 0xff;
    const BOUND_MASK: u64 = 0x03;
    #[inline]
    pub(crate) fn key_sig(key: u64) -> u32 {
        // Mirror master's default `Key = uint32_t`: TT indexing and equality
        // both use the low 32 bits of the Zobrist key.
        key as u32
    }

    #[inline]
    pub(crate) fn packed_key_sig(meta: u64) -> u32 {
        (meta & Self::KEY_SIG_MASK) as u32
    }

    #[inline]
    pub(crate) fn packed_age(meta: u64) -> u8 {
        ((meta >> Self::AGE_SHIFT) & Self::AGE_MASK) as u8
    }

    #[inline]
    pub(crate) fn pack_meta(key: u64, entry: &TtEntry, age: u8) -> u64 {
        u64::from(Self::key_sig(key))
            | ((u64::from(age) & Self::AGE_MASK) << Self::AGE_SHIFT)
            | (u64::from(Self::compact_value(entry.value)) << Self::VALUE_SHIFT)
            | (u64::from(Self::compact_depth(entry.depth)) << Self::DEPTH_SHIFT)
            | (u64::from(Self::pack_bound(entry.bound)) << Self::BOUND_SHIFT)
    }

    #[inline]
    pub(crate) fn unpack_entry(meta: u64) -> TtEntry {
        TtEntry {
            value: Self::unpack_value(meta),
            depth: Self::unpack_depth(meta),
            bound: Self::unpack_bound(meta),
            tt_move: TT_MOVE_NONE,
        }
    }

    #[inline]
    fn compact_value(value: i32) -> u16 {
        value.clamp(i16::MIN as i32, i16::MAX as i32) as i16 as u16
    }

    #[inline]
    fn unpack_value(meta: u64) -> i32 {
        (((meta >> Self::VALUE_SHIFT) & Self::VALUE_MASK) as u16 as i16) as i32
    }

    #[inline]
    fn compact_depth(depth: i32) -> u8 {
        depth.clamp(i8::MIN as i32, i8::MAX as i32) as i8 as u8
    }

    #[inline]
    pub(crate) fn unpack_depth(meta: u64) -> i32 {
        (((meta >> Self::DEPTH_SHIFT) & Self::DEPTH_MASK) as u8 as i8) as i32
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
    pub(crate) fn unpack_bound(meta: u64) -> Bound {
        match ((meta >> Self::BOUND_SHIFT) & Self::BOUND_MASK) as u8 {
            0 => Bound::Exact,
            1 => Bound::Lower,
            2 => Bound::Upper,
            _ => Bound::Exact,
        }
    }
}

impl Default for ClusteredTt {
    fn default() -> Self {
        Self::new_with_cluster_bits(Self::DEFAULT_CLUSTER_BITS)
    }
}

/// Reference-counted handle to a packed transposition table.  Multiple
/// `Searcher` instances built with the same `SharedTt` see and update the
/// same cluster array, which is the foundation for lazy-SMP-style parallel
/// search in phase 5.2.  The stored entries themselves use `AtomicU64`
/// slots, so writes are lock-free.
#[derive(Clone)]
pub struct SharedTt {
    pub(crate) inner: Arc<ClusteredTt>,
}

impl SharedTt {
    /// Allocate a fresh TT sized like
    /// [`crate::Searcher::new_with_tt_cluster_bits`] (`2^cluster_bits`
    /// total packed slots).
    pub fn new(cluster_bits: u32) -> Self {
        Self::new_with_tt_move(cluster_bits, false)
    }

    /// Allocate a fresh shared TT with optional in-cluster storage for compact
    /// TT move-order hints.
    pub fn new_with_tt_move(cluster_bits: u32, enable_tt_move: bool) -> Self {
        Self {
            inner: Arc::new(ClusteredTt::new_with_cluster_bits_and_tt_move(
                cluster_bits,
                enable_tt_move,
            )),
        }
    }

    /// Allocate a shared TT sized from the UCI `Hash` option.
    ///
    /// Mirrors master's effective lower bound when callers pass
    /// [`ClusteredTt::DEFAULT_CLUSTER_BITS`]: the C++ engine allocates
    /// `0x1000000` entries at startup and ignores smaller resize requests.
    /// Diagnostic callers can pass a smaller `cluster_bits_floor` to study
    /// cache locality without changing production defaults.
    pub fn with_capacity_mb(mb: u32, cluster_bits_floor: u32) -> Self {
        Self::with_capacity_mb_and_tt_move(mb, cluster_bits_floor, false)
    }

    /// Allocate a shared TT sized from the UCI `Hash` option, optionally
    /// enabling in-cluster TT move-order hints.
    pub fn with_capacity_mb_and_tt_move(
        mb: u32,
        cluster_bits_floor: u32,
        enable_tt_move: bool,
    ) -> Self {
        let bytes = (mb.max(1) as usize).saturating_mul(1024 * 1024);
        let entry_size = std::mem::size_of::<AtomicU64>().max(1);
        let slots = (bytes / entry_size).max(1);
        let bits = (usize::BITS - 1 - slots.leading_zeros())
            .max(cluster_bits_floor)
            .clamp(10, 26);
        Self::new_with_tt_move(bits, enable_tt_move)
    }

    /// Whether this TT reads and writes in-cluster TT move-order hints.
    #[inline]
    pub fn tt_move_enabled(&self) -> bool {
        self.inner.tt_move_enabled()
    }

    /// Physical clear: zeros every slot and resets the generation counter.
    /// Prefer [`bump_age`] for the cheaper soft clear that avoids zeroing
    /// all memory.
    pub fn clear(&self) {
        self.inner.clear();
    }

    /// Soft clear: increment the generation counter so cached entries from
    /// older generations are treated as stale on the next probe.  Matches the
    /// C++ `TranspositionTable::clear()` fake-clean path with exact entries
    /// also invalidated.
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

    /// Snapshot TT occupancy and current-generation bound mix.
    ///
    /// This scans the full table and is intended for diagnostics, not for
    /// per-node search accounting.
    pub fn stats(&self) -> TtStats {
        self.inner.stats()
    }

    /// Architecture-specific prefetch hint for the cluster `key` would
    /// land in.  See [`ClusteredTt::prefetch`] for the underlying
    /// semantics.
    #[inline]
    pub fn prefetch(&self, key: u64) {
        self.inner.prefetch(key);
    }
}

impl Default for SharedTt {
    fn default() -> Self {
        Self {
            inner: Arc::new(ClusteredTt::default()),
        }
    }
}
