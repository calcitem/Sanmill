// SPDX-License-Identifier: GPL-3.0-or-later
// Packed transposition table shared by every searcher in the crate.
//
// `ClusteredTt` is a fixed-size array of two-slot clusters that are
// each backed by an `AtomicU64`.  The atomic packing lets multiple
// `Searcher<G>` instances probe / save concurrently in lazy-SMP
// configurations (see `crate::thread_pool::lazy_smp_search`) without
// any locking on the hot path.

use std::sync::{
    atomic::{AtomicU64, AtomicU8, Ordering},
    Arc,
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

pub(crate) struct TtCluster {
    pub(crate) slots: [AtomicU64; 2],
}

impl TtCluster {
    #[inline]
    fn empty() -> Self {
        Self {
            slots: [AtomicU64::new(0), AtomicU64::new(0)],
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

    pub(crate) fn save(&self, key: u64, entry: TtEntry) {
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
    pub(crate) fn clear(&self) {
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
    pub(crate) fn bump_age(&self) {
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

    pub(crate) fn current_age(&self) -> u8 {
        self.current_age.load(Ordering::Relaxed)
    }

    pub(crate) fn len_occupied(&self) -> usize {
        self.clusters
            .iter()
            .flat_map(|c| c.slots.iter())
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
    pub(crate) fn key_sig(key: u64) -> u16 {
        // 8-bit signature; returned as u16 for comparison with `packed_key_sig`.
        let sig = ((key >> 48) ^ (key >> 32) ^ (key >> 16) ^ key) as u8;
        u16::from(sig.max(1))
    }

    #[inline]
    pub(crate) fn packed_key_sig(packed: u64) -> u16 {
        (packed & Self::KEY_SIG_MASK) as u16
    }

    #[inline]
    pub(crate) fn packed_age(packed: u64) -> u8 {
        ((packed >> Self::AGE_SHIFT) & Self::AGE_MASK) as u8
    }

    #[inline]
    pub(crate) fn pack(key: u64, entry: TtEntry, age: u8) -> u64 {
        u64::from(Self::key_sig(key))
            | (u64::from(age) << Self::AGE_SHIFT)
            | (u64::from(Self::compact_value(entry.value)) << Self::VALUE_SHIFT)
            | (u64::from(Self::compact_depth(entry.depth)) << Self::DEPTH_SHIFT)
            | (u64::from(Self::pack_bound(entry.bound)) << Self::BOUND_SHIFT)
            | (u64::from(Self::pack_action(entry.best_action)) << Self::ACTION_SHIFT)
    }

    #[inline]
    pub(crate) fn unpack_entry(packed: u64) -> TtEntry {
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
    pub(crate) fn unpack_depth(packed: u64) -> i32 {
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
    pub(crate) fn unpack_bound(packed: u64) -> Bound {
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
