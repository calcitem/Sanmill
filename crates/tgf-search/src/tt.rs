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
    atomic::{AtomicU8, AtomicU32, AtomicU64, Ordering},
};

use tgf_core::Action;

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
    pub best_action: Action,
}

// ---------------------------------------------------------------------------
// Clustered TT: fixed `2 * 2^cluster_bits` packed atomic slots.
// ---------------------------------------------------------------------------

/// One slot in a cluster.
///
/// Master `src/tt.h` stores a `TTEntry { value8, depth8, genBound8 }`
/// plus optional `ttMove` (disabled by default via TT_MOVE_ENABLE).
/// The Rust packing widens the key signature to 32 bits to match
/// master's default `Key = uint32_t` (TRANSPOSITION_TABLE_64BIT_KEY
/// undefined) instead of 8 bits, eliminating the false-positive
/// hit rate caused by 1/256 signature collisions.  The action is
/// kept in a sibling atomic so callers like `Searcher::search_mtdf`
/// can still pull a best move out of the TT.
///
/// Layout (per slot):
///   * meta (u64): [key_sig:32][age:6][value:16][depth:8][bound:2]
///   * action (u32): packed Action (kind 4 / from 7 / to 7 / aux 4)
///
/// Total slot size = 12 bytes; cluster = 2 slots = 24 bytes.
pub(crate) struct TtCluster {
    pub(crate) meta: [AtomicU64; 2],
    pub(crate) action: [AtomicU32; 2],
}

impl TtCluster {
    #[inline]
    fn empty() -> Self {
        Self {
            meta: [AtomicU64::new(0), AtomicU64::new(0)],
            action: [AtomicU32::new(0), AtomicU32::new(0)],
        }
    }
}

pub(crate) struct ClusteredTt {
    pub(crate) clusters: Box<[TtCluster]>,
    pub(crate) cluster_mask: usize,
    /// Global generation counter used for soft "fake-clean" clear semantics,
    /// matching C++ `transpositionTableAge` in `src/tt.cpp`.  Incrementing
    /// this bumps all non-Exact cached entries to stale without zeroing memory.
    pub(crate) current_age: AtomicU8,
}

impl ClusteredTt {
    /// 23 → 8 Mi clusters, 16 Mi slots (~128 MiB), matching master
    /// `TRANSPOSITION_TABLE_SIZE = 0x1000000` (16 Mi entries) in
    /// `src/tt.cpp`.  Master's TTEntry is ~6 bytes vs Rust's 16-byte
    /// cluster, so the Rust default uses ~128 MiB to keep the same
    /// number of addressable slots; users with constrained memory
    /// can downsize via `Searcher::resize_tt_by_mb` or the
    /// `TGF_TT_CLUSTER_BITS` environment variable.
    pub(crate) const DEFAULT_CLUSTER_BITS: u32 = 23;

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
        let mixed = key ^ (key >> 32);
        (mixed as usize) & self.cluster_mask
    }

    pub(crate) fn get(&self, key: u64) -> Option<TtEntry> {
        if key == 0 {
            return None;
        }
        let cur_age = self.current_age.load(Ordering::Relaxed);
        let key_sig = TtPackedEntry::key_sig(key);
        let c = &self.clusters[self.cluster_ix(key)];
        for i in 0..2 {
            let meta = c.meta[i].load(Ordering::Relaxed);
            if meta == 0 {
                continue;
            }
            if TtPackedEntry::packed_key_sig(meta) == key_sig {
                // Fake-clean: treat non-Exact old-generation entries as misses,
                // matching C++ TRANSPOSITION_TABLE_FAKE_CLEAN semantics.
                let entry_age = TtPackedEntry::packed_age(meta);
                if entry_age != cur_age && TtPackedEntry::unpack_bound(meta) != Bound::Exact {
                    continue;
                }
                let action_bits = c.action[i].load(Ordering::Relaxed);
                return Some(TtPackedEntry::unpack_entry(meta, action_bits));
            }
        }
        None
    }

    pub(crate) fn save(&self, key: u64, entry: TtEntry) {
        if key == 0 {
            return;
        }
        let cur_age = self.current_age.load(Ordering::Relaxed);
        let new_meta = TtPackedEntry::pack_meta(key, &entry, cur_age);
        let new_action = TtPackedEntry::pack_action(entry.best_action);
        let key_sig = TtPackedEntry::key_sig(key);
        let ix = self.cluster_ix(key);
        let c = &self.clusters[ix];
        // 1. Update an existing same-key entry (depth-gated for same generation).
        for i in 0..2 {
            let meta = c.meta[i].load(Ordering::Relaxed);
            if meta == 0 {
                continue;
            }
            if TtPackedEntry::packed_key_sig(meta) == key_sig {
                let same_gen = TtPackedEntry::packed_age(meta) == cur_age;
                if same_gen && entry.depth < TtPackedEntry::unpack_depth(meta) {
                    return;
                }
                c.meta[i].store(new_meta, Ordering::Relaxed);
                c.action[i].store(new_action, Ordering::Relaxed);
                return;
            }
        }
        // 2. Fill an empty slot.
        for i in 0..2 {
            if c.meta[i].load(Ordering::Relaxed) == 0 {
                c.meta[i].store(new_meta, Ordering::Relaxed);
                c.action[i].store(new_action, Ordering::Relaxed);
                return;
            }
        }
        // 3. Prefer evicting old-generation slots (they are effectively stale).
        for i in 0..2 {
            let meta = c.meta[i].load(Ordering::Relaxed);
            if TtPackedEntry::packed_age(meta) != cur_age {
                c.meta[i].store(new_meta, Ordering::Relaxed);
                c.action[i].store(new_action, Ordering::Relaxed);
                return;
            }
        }
        // 4. Fallback: evict minimum-depth current-generation slot.
        let mut wi = 0_usize;
        let mut wd = TtPackedEntry::unpack_depth(c.meta[0].load(Ordering::Relaxed));
        let depth1 = TtPackedEntry::unpack_depth(c.meta[1].load(Ordering::Relaxed));
        if depth1 < wd {
            wi = 1;
            wd = depth1;
        }
        if entry.depth >= wd {
            c.meta[wi].store(new_meta, Ordering::Relaxed);
            c.action[wi].store(new_action, Ordering::Relaxed);
        }
    }

    /// Physical clear: zeros all slots and resets the generation counter.
    /// Use [`bump_age`] for the cheaper soft-clear that leaves memory intact
    /// but marks all non-Exact existing entries as stale.
    pub(crate) fn clear(&self) {
        for c in self.clusters.iter() {
            for i in 0..2 {
                c.meta[i].store(0, Ordering::Relaxed);
                c.action[i].store(0, Ordering::Relaxed);
            }
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
                for i in 0..2 {
                    c.meta[i].store(0, Ordering::Relaxed);
                    c.action[i].store(0, Ordering::Relaxed);
                }
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
            .flat_map(|c| c.meta.iter())
            .filter(|s| s.load(Ordering::Relaxed) != 0)
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
        if key == 0 {
            return;
        }
        let ix = self.cluster_ix(key);
        let cluster_ptr = self.clusters.as_ptr().wrapping_add(ix) as *const i8;
        prefetch_read(cluster_ptr);
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
    // The action lives in a sibling AtomicU32 inside the cluster so we
    // can preserve `TtEntry::best_action` without sacrificing any of
    // the new 32-bit signature.  Keeping the action also keeps
    // Searcher::search_mtdf_with_guess able to retrieve the root
    // bestmove from the TT.  Master itself drops the move when
    // TT_MOVE_ENABLE is undefined (default), which only affects
    // `MovePicker::score`'s ttMove bonus -- the Rust move-ordering path
    // intentionally leaves that bonus disabled by default.
    const KEY_SIG_MASK: u64 = 0xffff_ffff;
    const AGE_SHIFT: u32 = 32;
    const VALUE_SHIFT: u32 = 38;
    const DEPTH_SHIFT: u32 = 54;
    const BOUND_SHIFT: u32 = 62;

    const AGE_MASK: u64 = 0x3f;
    const VALUE_MASK: u64 = 0xffff;
    const DEPTH_MASK: u64 = 0xff;
    const BOUND_MASK: u64 = 0x03;
    const ACTION_MASK: u32 = (1_u32 << 22) - 1;

    #[inline]
    pub(crate) fn key_sig(key: u64) -> u32 {
        // 32-bit signature mirroring master's default `Key = u32`.
        // Mix the high 32 bits so callers using full 64-bit Zobrist keys
        // do not collapse all signatures to the lower half.  Use `.max(1)`
        // so a zero signature never aliases the empty-slot sentinel.
        let mixed = (key as u32) ^ ((key >> 32) as u32);
        mixed.max(1)
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
    pub(crate) fn unpack_entry(meta: u64, action_bits: u32) -> TtEntry {
        TtEntry {
            value: Self::unpack_value(meta),
            depth: Self::unpack_depth(meta),
            bound: Self::unpack_bound(meta),
            best_action: Self::unpack_action(action_bits),
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

    #[inline]
    pub(crate) fn pack_action(action: Action) -> u32 {
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
        let bits = u32::from(kind)
            | (u32::from(from) << 4)
            | (u32::from(to) << 11)
            | (u32::from(aux) << 18);
        bits & Self::ACTION_MASK
    }

    #[inline]
    fn unpack_action(action_bits: u32) -> Action {
        let bits = action_bits & Self::ACTION_MASK;
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
    /// [`crate::Searcher::new_with_tt_cluster_bits`] (`2 * 2^cluster_bits`
    /// slots).
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
