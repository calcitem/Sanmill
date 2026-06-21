// SPDX-License-Identifier: GPL-3.0-or-later
// Packed transposition table shared by every searcher in the crate.
//
// `ClusteredTt` is a fixed-size array of two-slot clusters that are
// each backed by an `AtomicU64`.  The atomic packing lets multiple
// `Searcher<G>` instances probe / save concurrently in lazy-SMP
// configurations (see `crate::thread_pool::lazy_smp_search`) without
// any locking on the hot path.

#[cfg(target_os = "linux")]
use std::ffi::{c_int, c_void};
use std::{
    alloc::{Layout, alloc, dealloc, handle_alloc_error},
    ops::Index,
    ptr::NonNull,
    slice,
    sync::{
        Arc,
        atomic::{AtomicU8, AtomicU64, Ordering},
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
#[repr(transparent)]
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

pub(crate) const TT_STORAGE_ALIGNMENT: usize = 4096;

/// How a [`TtStorage`] allocation is backed, so [`Drop`] frees it the right
/// way. Windows large pages come from `VirtualAlloc(MEM_LARGE_PAGES)` and must
/// be released with `VirtualFree`; every other allocation uses the global
/// allocator and is released with `dealloc`.
enum TtBacking {
    Heap,
    #[cfg(windows)]
    LargePagesWin,
}

pub(crate) struct TtStorage {
    ptr: NonNull<TtCluster>,
    len: usize,
    layout: Layout,
    backing: TtBacking,
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

        // Prefer Windows large pages for the TT backing store. The TT is the
        // dominant random-access working set in deep search; 4 KiB pages cost
        // extra dTLB misses on every probe/save, while 2 MiB large pages keep
        // the page-table walk short. This is purely a backing-store change:
        // node counts and TT semantics are identical. Falls back to the
        // page-aligned global allocator when the SeLockMemoryPrivilege is not
        // held or large pages are unsupported.
        #[cfg(windows)]
        {
            if let Some(ptr) = alloc_tt_large_pages_win(bytes) {
                for i in 0..len {
                    unsafe { ptr.as_ptr().add(i).write(TtCluster::empty()) };
                }
                return Self {
                    ptr,
                    len,
                    layout,
                    backing: TtBacking::LargePagesWin,
                };
            }
        }

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
        Self {
            ptr,
            len,
            layout,
            backing: TtBacking::Heap,
        }
    }

    #[cfg(test)]
    #[inline]
    pub(crate) fn as_ptr(&self) -> *const TtCluster {
        self.ptr.as_ptr()
    }

    #[cfg(test)]
    #[inline]
    pub(crate) fn len(&self) -> usize {
        self.len
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

/// Try to back the TT with Windows large pages. Returns `None` (so the caller
/// falls back to 4 KiB pages) when large pages are unsupported or the process
/// lacks `SeLockMemoryPrivilege`. Set `TGF_TT_LOG` to print which path ran.
#[cfg(windows)]
fn alloc_tt_large_pages_win(bytes: usize) -> Option<NonNull<TtCluster>> {
    let log = std::env::var_os("TGF_TT_LOG").is_some();
    let page = win_large_pages::large_page_size();
    if page == 0 {
        if log {
            eprintln!("info string TT large pages: unsupported on this system");
        }
        return None;
    }
    // VirtualAlloc(MEM_LARGE_PAGES) requires a multiple of the large-page size.
    let commit = bytes.div_ceil(page).checked_mul(page)?;
    let raw = win_large_pages::alloc(commit);
    match NonNull::new(raw.cast::<TtCluster>()) {
        Some(ptr) => {
            if log {
                eprintln!(
                    "info string TT large pages: ON ({} MiB, {} KiB pages)",
                    commit >> 20,
                    page >> 10
                );
            }
            Some(ptr)
        }
        None => {
            if log {
                eprintln!(
                    "info string TT large pages: VirtualAlloc failed; grant \
                     \"Lock pages in memory\" (SeLockMemoryPrivilege) to use \
                     them. Falling back to 4 KiB pages."
                );
            }
            None
        }
    }
}

/// Minimal FFI for Windows large-page TT allocation.
///
/// The transposition table is the hottest random-access region in deep
/// search; with 4 KiB pages every probe/save can miss the dTLB. Backing it
/// with large pages (typically 2 MiB) shortens the page walk. This requires
/// the process to hold `SeLockMemoryPrivilege` ("Lock pages in memory"); when
/// it is missing the allocation simply fails and the caller falls back.
#[cfg(windows)]
mod win_large_pages {
    use core::ffi::c_void;
    use core::ptr;
    use std::sync::Once;

    type Handle = *mut c_void;

    #[repr(C)]
    struct Luid {
        low_part: u32,
        high_part: i32,
    }
    #[repr(C)]
    struct LuidAndAttributes {
        luid: Luid,
        attributes: u32,
    }
    #[repr(C)]
    struct TokenPrivileges {
        privilege_count: u32,
        privileges: [LuidAndAttributes; 1],
    }

    const TOKEN_ADJUST_PRIVILEGES: u32 = 0x0020;
    const TOKEN_QUERY: u32 = 0x0008;
    const SE_PRIVILEGE_ENABLED: u32 = 0x0000_0002;
    const MEM_COMMIT: u32 = 0x0000_1000;
    const MEM_RESERVE: u32 = 0x0000_2000;
    const MEM_LARGE_PAGES: u32 = 0x2000_0000;
    const MEM_RELEASE: u32 = 0x0000_8000;
    const PAGE_READWRITE: u32 = 0x04;

    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn GetCurrentProcess() -> Handle;
        fn CloseHandle(handle: Handle) -> i32;
        fn GetLargePageMinimum() -> usize;
        fn VirtualAlloc(
            addr: *mut c_void,
            size: usize,
            alloc_type: u32,
            protect: u32,
        ) -> *mut c_void;
        fn VirtualFree(addr: *mut c_void, size: usize, free_type: u32) -> i32;
    }

    #[link(name = "advapi32")]
    unsafe extern "system" {
        fn OpenProcessToken(process: Handle, access: u32, token: *mut Handle) -> i32;
        fn LookupPrivilegeValueW(system: *const u16, name: *const u16, luid: *mut Luid) -> i32;
        fn AdjustTokenPrivileges(
            token: Handle,
            disable_all: i32,
            new_state: *const TokenPrivileges,
            buffer_len: u32,
            previous: *mut TokenPrivileges,
            return_len: *mut u32,
        ) -> i32;
    }

    /// Best-effort enable of `SeLockMemoryPrivilege` in the current process
    /// token. A no-op when the account was never granted the right (the later
    /// `VirtualAlloc` then fails and the caller falls back to 4 KiB pages).
    fn enable_lock_memory_privilege() {
        let name: Vec<u16> = "SeLockMemoryPrivilege"
            .encode_utf16()
            .chain(core::iter::once(0))
            .collect();
        unsafe {
            let mut token: Handle = ptr::null_mut();
            if OpenProcessToken(
                GetCurrentProcess(),
                TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY,
                &mut token,
            ) == 0
            {
                return;
            }
            let mut luid = Luid {
                low_part: 0,
                high_part: 0,
            };
            if LookupPrivilegeValueW(ptr::null(), name.as_ptr(), &mut luid) != 0 {
                let privileges = TokenPrivileges {
                    privilege_count: 1,
                    privileges: [LuidAndAttributes {
                        luid,
                        attributes: SE_PRIVILEGE_ENABLED,
                    }],
                };
                AdjustTokenPrivileges(token, 0, &privileges, 0, ptr::null_mut(), ptr::null_mut());
            }
            CloseHandle(token);
        }
    }

    pub(super) fn large_page_size() -> usize {
        unsafe { GetLargePageMinimum() }
    }

    pub(super) fn alloc(commit_bytes: usize) -> *mut c_void {
        static PRIVILEGE: Once = Once::new();
        PRIVILEGE.call_once(enable_lock_memory_privilege);
        unsafe {
            VirtualAlloc(
                ptr::null_mut(),
                commit_bytes,
                MEM_RESERVE | MEM_COMMIT | MEM_LARGE_PAGES,
                PAGE_READWRITE,
            )
        }
    }

    pub(super) unsafe fn free(addr: *mut c_void) {
        unsafe {
            VirtualFree(addr, 0, MEM_RELEASE);
        }
    }
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
        match self.backing {
            TtBacking::Heap => {
                for i in 0..self.len {
                    unsafe { self.ptr.as_ptr().add(i).drop_in_place() };
                }
                unsafe { dealloc(self.ptr.as_ptr().cast::<u8>(), self.layout) };
            }
            #[cfg(windows)]
            TtBacking::LargePagesWin => unsafe {
                // AtomicU64 has no Drop, so the slots need no per-element
                // teardown; release the whole large-page reservation.
                win_large_pages::free(self.ptr.as_ptr().cast());
            },
        }
    }
}

pub(crate) struct ClusteredTt {
    pub(crate) clusters: TtStorage,
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
        Self {
            clusters: TtStorage::new(n),
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
