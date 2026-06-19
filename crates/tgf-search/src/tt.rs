// SPDX-License-Identifier: GPL-3.0-or-later
// Packed transposition table shared by every searcher in the crate.
//
// `ClusteredTt` is a fixed-size array of two-slot clusters that are
// each backed by an `AtomicU64`.  The atomic packing lets multiple
// `Searcher<G>` instances probe / save concurrently in lazy-SMP
// configurations (see `crate::thread_pool::lazy_smp_search`) without
// any locking on the hot path.

use std::sync::{
    Arc,
    atomic::{AtomicU8, AtomicU64, Ordering},
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
}

// ---------------------------------------------------------------------------
// Clustered TT: fixed `2^cluster_bits` packed atomic direct slots.
// ---------------------------------------------------------------------------

/// One direct-mapped TT slot.
///
/// Master `src/tt.h` stores a `TTEntry { value8, depth8, genBound8 }`
/// plus optional `ttMove` (disabled by default via TT_MOVE_ENABLE).
/// The Rust packing widens the key signature to 32 bits to match
/// master's default `Key = uint32_t` (TRANSPOSITION_TABLE_64BIT_KEY
/// undefined) instead of 8 bits, eliminating the false-positive
/// hit rate caused by 1/256 signature collisions.  The production
/// search path mirrors master's default TT_MOVE_ENABLE-off build:
/// the best action is threaded at the root and is not stored in TT.
///
/// Layout:
///   * meta (u64): [key_sig:32][age:6][value:16][depth:8][bound:2]
///
/// Total slot size = 8 bytes.
pub(crate) struct TtCluster {
    pub(crate) meta: AtomicU64,
}

impl TtCluster {
    #[inline]
    fn empty() -> Self {
        Self {
            meta: AtomicU64::new(0),
        }
    }
}

pub(crate) struct ClusteredTt {
    pub(crate) clusters: Box<[TtCluster]>,
    pub(crate) cluster_mask: usize,
    /// Global generation counter used for soft "fake-clean" clear semantics,
    /// matching C++ `transpositionTableAge` in `src/tt.cpp`. Incrementing this
    /// makes every cached entry from the old generation stale without zeroing
    /// memory.
    pub(crate) current_age: AtomicU8,
}

impl ClusteredTt {
    /// 24 → 16 Mi direct slots (~128 MiB), matching master
    /// `TRANSPOSITION_TABLE_SIZE = 0x1000000` (16 Mi entries) in
    /// `src/tt.cpp`.  Users with constrained memory
    /// can downsize via `Searcher::resize_tt_by_mb` or the
    /// `TGF_TT_CLUSTER_BITS` environment variable.
    pub(crate) const DEFAULT_CLUSTER_BITS: u32 = 24;

    pub(crate) fn new_with_cluster_bits(bits: u32) -> Self {
        // Permit larger TTs: master defaults to 16 Mi slots which
        // requires cluster_bits >= 23.  Cap at 26 (≈1 GiB) to keep
        // accidental misuse from immediately exhausting memory.
        let bits = bits.clamp(10, 26);
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
        self.cluster_ix_from_sig(TtPackedEntry::key_sig(key))
    }

    #[inline]
    fn cluster_ix_from_sig(&self, key_sig: u32) -> usize {
        (key_sig as usize) & self.cluster_mask
    }

    #[inline(always)]
    pub(crate) fn get(&self, key: u64) -> Option<TtEntry> {
        let cur_age = self.current_age.load(Ordering::Relaxed);
        let key_sig = TtPackedEntry::key_sig(key);
        let meta = self.clusters[self.cluster_ix_from_sig(key_sig)]
            .meta
            .load(Ordering::Relaxed);
        if meta == 0 || TtPackedEntry::packed_key_sig(meta) != key_sig {
            return None;
        }
        // Fake-clean: master has TRANSPOSITION_TABLE_FAKE_CLEAN enabled and
        // TRANSPOSITION_TABLE_FAKE_CLEAN_NOT_EXACT_ONLY disabled, so every
        // old-generation entry is a miss, including Exact entries.
        let entry_age = TtPackedEntry::packed_age(meta);
        if entry_age != cur_age {
            return None;
        }
        Some(TtPackedEntry::unpack_entry(meta))
    }

    #[inline(always)]
    pub(crate) fn probe_value_bound(&self, key: u64, depth: i32) -> Option<(i32, Bound)> {
        let cur_age = self.current_age.load(Ordering::Relaxed);
        let key_sig = TtPackedEntry::key_sig(key);
        let meta = self.clusters[self.cluster_ix_from_sig(key_sig)]
            .meta
            .load(Ordering::Relaxed);
        if meta == 0 || TtPackedEntry::packed_key_sig(meta) != key_sig {
            return None;
        }
        if TtPackedEntry::packed_age(meta) != cur_age {
            return None;
        }
        if TtPackedEntry::unpack_depth(meta) < depth {
            return None;
        }
        Some((
            TtPackedEntry::unpack_value(meta),
            TtPackedEntry::unpack_bound(meta),
        ))
    }

    #[inline(always)]
    pub(crate) fn save(&self, key: u64, entry: TtEntry) {
        let cur_age = self.current_age.load(Ordering::Relaxed);
        let new_meta = TtPackedEntry::pack_meta(key, &entry, cur_age);
        let key_sig = TtPackedEntry::key_sig(key);
        let ix = self.cluster_ix_from_sig(key_sig);
        let slot = &self.clusters[ix].meta;
        let meta = slot.load(Ordering::Relaxed);
        if meta != 0 && TtPackedEntry::packed_key_sig(meta) == key_sig {
            let same_gen = TtPackedEntry::packed_age(meta) == cur_age;
            if same_gen && entry.depth < TtPackedEntry::unpack_depth(meta) {
                return;
            }
        }
        slot.store(new_meta, Ordering::Relaxed);
    }

    /// Physical clear: zeros all slots and resets the generation counter.
    /// Use [`bump_age`] for the cheaper soft-clear that leaves memory intact
    /// but marks all non-Exact existing entries as stale.
    pub(crate) fn clear(&self) {
        for c in self.clusters.iter() {
            c.meta.store(0, Ordering::Relaxed);
        }
        self.current_age.store(0, Ordering::Relaxed);
    }

    /// Soft "fake-clean" clear: increment the generation counter so all
    /// non-Exact entries are treated as stale on the next probe.  Cheaper
    /// than zeroing the whole table.  Wraps at 63 (the new 6-bit age
    /// field) → performs a full physical clear to avoid generation-0
    /// aliasing with stale slots.
    pub(crate) fn bump_age(&self) {
        let prev = self.current_age.fetch_add(1, Ordering::Relaxed);
        // Age is encoded in 6 bits (mask 0x3f); wrap at the field max.
        if prev >= 0x3f {
            for c in self.clusters.iter() {
                c.meta.store(0, Ordering::Relaxed);
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
            .filter(|c| c.meta.load(Ordering::Relaxed) != 0)
            .count()
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
        let slot_ptr = &self.clusters[ix].meta as *const AtomicU64 as *const i8;
        prefetch_read(slot_ptr);
    }
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
    // Master itself drops the move when TT_MOVE_ENABLE is undefined
    // (default), which only affects `MovePicker::score`'s ttMove bonus.
    // The Rust move-ordering path intentionally leaves that bonus disabled,
    // and MTD(f) threads its root best action outside the TT.
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
    /// direct slots).
    pub fn new(cluster_bits: u32) -> Self {
        Self {
            inner: Arc::new(ClusteredTt::new_with_cluster_bits(cluster_bits)),
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
