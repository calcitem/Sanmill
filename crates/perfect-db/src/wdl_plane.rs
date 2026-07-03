// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

//! Compact 2-bit-per-position WDL ("win/draw/loss") planes.
//!
//! A full `.sec2` sector stores a 3-byte `(key1, key2)` pair per position
//! (game-theoretic value plus distance-to-conversion). For the mining
//! pipeline's cheap "is this move safe" pre-filter we only need the coarse
//! outcome, not the exact step count, so a sector's eval array can be
//! losslessly reduced (for this purpose) to 2 bits per position: Loss(-1),
//! Draw(0), Win(1), all from the perspective of the sector's own side to
//! move (matching [`crate::database::PerfectQuery::sector_and_board`]'s
//! "mover is always sector-white" convention).
//!
//! This typically shrinks a sector by ~12x (3 bytes -> 0.25 bytes) and, once
//! built, turns every query into a couple of array-index operations instead
//! of a symmetry-aware disk probe -- the WDL plane is meant to be queried
//! millions of times per mining run.

use std::collections::{BTreeMap, VecDeque};
use std::path::PathBuf;

use crate::database::{DatabaseError, DatabaseProvider, DatabaseVariant, PerfectQuery};
use crate::file_format::{ParseError, RawEvalKind, SecValTable, SectorFile, SectorId};
use crate::index::PerfectHasher;
use crate::index::symmetry::transform48;

/// A packed WDL plane for one sector: 2 bits per position, 4 positions per
/// byte, in hash-index order.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct WdlPlane {
    hash_count: usize,
    bits: Vec<u8>,
}

const PLANE_MAGIC: [u8; 4] = *b"SMWD";
const PLANE_VERSION: u8 = 1;
const PLANE_HEADER_LEN: usize = PLANE_MAGIC.len() + 1 + 8;

impl WdlPlane {
    pub fn hash_count(&self) -> usize {
        self.hash_count
    }

    /// WDL (`-1`/`0`/`1`) at `index`, from the sector's own side-to-move
    /// perspective.
    pub fn wdl_at(&self, index: usize) -> i8 {
        assert!(index < self.hash_count, "WDL plane index out of range");
        let byte = self.bits[index / 4];
        let shift = (index % 4) * 2;
        match (byte >> shift) & 0b11 {
            0 => -1,
            1 => 0,
            2 => 1,
            other => unreachable!("packed WDL code must be 0..=2, got {other}"),
        }
    }

    fn set(&mut self, index: usize, wdl: i8) {
        let code: u8 = match wdl {
            -1 => 0,
            0 => 1,
            1 => 2,
            other => panic!("WDL plane value must be -1, 0, or 1, got {other}"),
        };
        let byte_index = index / 4;
        let shift = (index % 4) * 2;
        self.bits[byte_index] &= !(0b11 << shift);
        self.bits[byte_index] |= code << shift;
    }

    /// Build a plane from a whole sector-file buffer.
    ///
    /// Uses [`SectorFile::decode_all_from_bytes`] (a tight, allocation-light
    /// loop over `bytes`) rather than repeated [`SectorFile::eval_at`] calls:
    /// `eval_at` is designed for lazy random-access probing through a
    /// `Box<dyn Read + Seek>` and pays a `Seek` + dynamic dispatch per call,
    /// which dominates build time once a sector has hundreds of millions of
    /// slots. `Symmetry` redirects are resolved via `hasher.inverse_board`
    /// (the redirect target's index is only recoverable from the *board*,
    /// not from the slot index alone -- see [`PerfectHasher::inverse_board`])
    /// followed by a second, in-memory array index -- no further I/O.
    pub fn build(
        bytes: &[u8],
        hasher: &PerfectHasher,
        sector_value: i16,
        sec_vals: &SecValTable,
    ) -> Result<Self, ParseError> {
        let hash_count = hasher.hash_count();
        let raw_evals = SectorFile::decode_all_from_bytes(bytes, hash_count)?;
        let mut plane = Self {
            hash_count,
            bits: vec![0_u8; hash_count.div_ceil(4)],
        };
        let virt_win = i32::from(sec_vals.virt_win_val());
        let virt_loss = i32::from(sec_vals.virt_loss_val());

        for index in 0..hash_count {
            let mut raw = raw_evals[index];
            if let RawEvalKind::Symmetry { operation } = raw.kind() {
                let board = hasher.inverse_board(index);
                let redirected_board = transform48(operation, board);
                let redirected_index = hasher.direct_hash_index(redirected_board);
                raw = raw_evals[redirected_index];
                assert!(
                    !matches!(raw.kind(), RawEvalKind::Symmetry { .. }),
                    "Perfect DB symmetry redirects must resolve to a concrete eval"
                );
            }
            let absolute = raw.key1 + i32::from(sector_value);
            let wdl: i8 = if absolute == virt_win {
                1
            } else if absolute == virt_loss {
                -1
            } else {
                0
            };
            plane.set(index, wdl);
        }
        Ok(plane)
    }

    pub fn to_bytes(&self) -> Vec<u8> {
        let mut out = Vec::with_capacity(PLANE_HEADER_LEN + self.bits.len());
        out.extend_from_slice(&PLANE_MAGIC);
        out.push(PLANE_VERSION);
        out.extend_from_slice(&(self.hash_count as u64).to_le_bytes());
        out.extend_from_slice(&self.bits);
        out
    }

    pub fn from_bytes(bytes: &[u8]) -> Result<Self, ParseError> {
        if bytes.len() < PLANE_HEADER_LEN || bytes[0..4] != PLANE_MAGIC {
            return Err(ParseError::InvalidHeader {
                message: "not a Sanmill WDL plane cache file".to_owned(),
            });
        }
        if bytes[4] != PLANE_VERSION {
            return Err(ParseError::InvalidHeader {
                message: format!("unsupported WDL plane cache version {}", bytes[4]),
            });
        }
        let hash_count = u64::from_le_bytes(bytes[5..13].try_into().expect("8 bytes")) as usize;
        let expected_len = PLANE_HEADER_LEN + hash_count.div_ceil(4);
        if bytes.len() != expected_len {
            return Err(ParseError::InvalidLength {
                expected: expected_len,
                actual: bytes.len(),
            });
        }
        Ok(Self {
            hash_count,
            bits: bytes[PLANE_HEADER_LEN..].to_vec(),
        })
    }
}

/// Pack `(sector, slot)` into a single `u64` mining/runtime canonical key.
///
/// This is exactly the database's own indexing (mover-folded sector id +
/// 16-symmetry-canonical hash slot), so two concrete boards that are
/// symmetric or color-mirror images of each other always pack to the same
/// key. `SectorId` fields are always `<= 12` for every supported Mill
/// variant; 8 bits per field leaves generous headroom, and the remaining 32
/// bits comfortably cover the largest sector's hash count (hundreds of
/// millions of slots).
pub fn pack_canonical_key(id: SectorId, slot: usize) -> u64 {
    const FIELD_BITS: u32 = 8;
    const SLOT_BITS: u32 = 64 - 4 * FIELD_BITS;
    let slot = slot as u64;
    assert!(
        slot < (1_u64 << SLOT_BITS),
        "Perfect DB canonical key slot index does not fit in {SLOT_BITS} bits"
    );
    (u64::from(id.white_on_board) << (SLOT_BITS + 3 * FIELD_BITS))
        | (u64::from(id.black_on_board) << (SLOT_BITS + 2 * FIELD_BITS))
        | (u64::from(id.white_in_hand) << (SLOT_BITS + FIELD_BITS))
        | (u64::from(id.black_in_hand) << SLOT_BITS)
        | slot
}

/// Tag bit for [`crate::mill::mid_removal_key`]'s key space. A
/// [`pack_canonical_key`] result never sets it (sector piece counts are
/// always `<= 12`, so the packed value never reaches bit 63), so callers
/// that hold an opaque `u64` key can cheaply tell the two spaces apart
/// without needing to know which one produced it -- in particular,
/// [`unpack_canonical_key`] and [`PatchFile::lookup`](crate::patch::PatchFile::lookup)
/// are only meaningful for keys where this bit is clear.
pub const MID_REMOVAL_KEY_TAG: u64 = 1_u64 << 63;

/// Inverse of [`pack_canonical_key`], mainly for diagnostics/tests. Only
/// meaningful for keys with [`MID_REMOVAL_KEY_TAG`] clear; see that
/// constant's docs.
pub fn unpack_canonical_key(key: u64) -> (SectorId, usize) {
    debug_assert_eq!(
        key & MID_REMOVAL_KEY_TAG,
        0,
        "unpack_canonical_key called on a mid-removal-tagged key"
    );
    const FIELD_BITS: u32 = 8;
    const SLOT_BITS: u32 = 64 - 4 * FIELD_BITS;
    const FIELD_MASK: u64 = (1 << FIELD_BITS) - 1;
    const SLOT_MASK: u64 = (1 << SLOT_BITS) - 1;
    let white_on_board = ((key >> (SLOT_BITS + 3 * FIELD_BITS)) & FIELD_MASK) as u8;
    let black_on_board = ((key >> (SLOT_BITS + 2 * FIELD_BITS)) & FIELD_MASK) as u8;
    let white_in_hand = ((key >> (SLOT_BITS + FIELD_BITS)) & FIELD_MASK) as u8;
    let black_in_hand = ((key >> SLOT_BITS) & FIELD_MASK) as u8;
    let slot = (key & SLOT_MASK) as usize;
    (
        SectorId::new(white_on_board, black_on_board, white_in_hand, black_in_hand),
        slot,
    )
}

#[derive(Clone, Debug, Default)]
pub struct WdlPlaneCacheOptions {
    /// Maximum number of sector planes held in memory at once (LRU
    /// eviction). `None` means unbounded.
    pub plane_cache_capacity: Option<usize>,
    /// Optional directory for persisting built planes as `.wdl2` files so a
    /// later run (or another process) can skip rebuilding them from the raw
    /// `.sec2` sector. Best-effort: a write failure is silently ignored, and
    /// planes are always rebuildable from the source database.
    pub cache_dir: Option<PathBuf>,
}

/// Builds and caches [`WdlPlane`]s on demand, backed by a [`DatabaseProvider`]
/// for the raw sector bytes.
///
/// Sector hashers are cached without eviction (they are needed to compute
/// canonical keys even for sectors whose plane has been evicted, and are
/// cheap relative to a plane); planes are LRU-bounded since a single large
/// sector's plane can be tens of megabytes.
pub struct WdlPlaneCache<P> {
    provider: P,
    variant: DatabaseVariant,
    sec_vals: SecValTable,
    options: WdlPlaneCacheOptions,
    hashers: BTreeMap<SectorId, PerfectHasher>,
    planes: BTreeMap<SectorId, WdlPlane>,
    plane_load_order: VecDeque<SectorId>,
}

impl<P: DatabaseProvider> WdlPlaneCache<P> {
    pub fn new(provider: P, variant: DatabaseVariant) -> Result<Self, DatabaseError> {
        Self::with_options(provider, variant, WdlPlaneCacheOptions::default())
    }

    pub fn with_options(
        provider: P,
        variant: DatabaseVariant,
        options: WdlPlaneCacheOptions,
    ) -> Result<Self, DatabaseError> {
        let sec_vals = crate::database::read_secval(&provider, variant)?;
        Ok(Self {
            provider,
            variant,
            sec_vals,
            options,
            hashers: BTreeMap::new(),
            planes: BTreeMap::new(),
            plane_load_order: VecDeque::new(),
        })
    }

    pub fn variant(&self) -> DatabaseVariant {
        self.variant
    }

    pub fn sec_vals(&self) -> &SecValTable {
        &self.sec_vals
    }

    pub fn loaded_plane_count(&self) -> usize {
        self.planes.len()
    }

    pub fn cached_hasher_count(&self) -> usize {
        self.hashers.len()
    }

    fn hasher_for(&mut self, id: SectorId) -> &mut PerfectHasher {
        self.hashers
            .entry(id)
            .or_insert_with(|| PerfectHasher::new(id.white_on_board, id.black_on_board))
    }

    fn cache_file_name(&self, id: SectorId) -> String {
        format!(
            "{}_{}_{}_{}_{}.wdl2",
            self.variant.name,
            id.white_on_board,
            id.black_on_board,
            id.white_in_hand,
            id.black_in_hand
        )
    }

    fn plane_for(&mut self, id: SectorId) -> Result<&WdlPlane, DatabaseError> {
        if !self.planes.contains_key(&id) {
            let plane = self.load_or_build_plane(id)?;
            if let Some(capacity) = self.options.plane_cache_capacity {
                assert!(capacity > 0, "WDL plane cache capacity must be positive");
                while self.planes.len() >= capacity {
                    let evicted = self
                        .plane_load_order
                        .pop_front()
                        .expect("plane load order must track cached planes");
                    assert!(
                        self.planes.remove(&evicted).is_some(),
                        "plane load order must not contain uncached sectors"
                    );
                }
            }
            self.planes.insert(id, plane);
            self.plane_load_order.push_back(id);
        }
        Ok(self
            .planes
            .get(&id)
            .expect("plane must be present after insertion"))
    }

    fn load_or_build_plane(&mut self, id: SectorId) -> Result<WdlPlane, DatabaseError> {
        if let Some(dir) = &self.options.cache_dir {
            let path = dir.join(self.cache_file_name(id));
            if let Ok(bytes) = std::fs::read(&path)
                && let Ok(plane) = WdlPlane::from_bytes(&bytes)
            {
                return Ok(plane);
            }
        }

        let sector_value = self
            .sec_vals
            .value(id)
            .ok_or(DatabaseError::MissingSectorValue { id })?;
        let name = self.variant.sector_file_name(id);
        let bytes = self.provider.read(&name)?;
        self.hasher_for(id);
        let hasher = self.hashers.get(&id).expect("hasher cached above");
        let plane = WdlPlane::build(&bytes, hasher, sector_value, &self.sec_vals)
            .map_err(|source| DatabaseError::Parse { name, source })?;

        if let Some(dir) = &self.options.cache_dir {
            let _ = std::fs::create_dir_all(dir);
            let _ = std::fs::write(dir.join(self.cache_file_name(id)), plane.to_bytes());
        }
        Ok(plane)
    }

    /// Fast WDL lookup for a single query. `None` for mid-removal queries
    /// (mirrors [`crate::database::Database::evaluate`], which has no direct
    /// entry for those either) and for sectors the underlying provider does
    /// not have (propagated as `Ok(None)` only when the error is a missing
    /// asset; other I/O errors are returned as `Err`).
    pub fn wdl_for_query(&mut self, query: PerfectQuery) -> Result<Option<i8>, DatabaseError> {
        if query.only_stone_taking {
            return Ok(None);
        }
        let (id, board) = query.sector_and_board();
        let index = self.hasher_for(id).hash_probe(board).index;
        match self.plane_for(id) {
            Ok(plane) => Ok(Some(plane.wdl_at(index))),
            Err(err) if err.is_missing_asset() => Ok(None),
            Err(err) => Err(err),
        }
    }

    /// Canonical mining/runtime key for `query`'s position, folding both the
    /// mover-is-sector-white convention and the 16-way board symmetry. See
    /// [`pack_canonical_key`].
    pub fn canonical_key_for_query(&mut self, query: PerfectQuery) -> u64 {
        let (id, board) = query.sector_and_board();
        let index = self.hasher_for(id).hash_probe(board).index;
        pack_canonical_key(id, index)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::database::{Database, DatabaseOptions, FileDatabaseProvider};
    use crate::file_format::SectorId;

    fn asset_root() -> std::path::PathBuf {
        std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../src/ui/flutter_app/assets/databases")
    }

    /// Regression guard for an earlier accidental-O(n^2) bug: resolving a
    /// `Symmetry` redirect called `PerfectHasher::hash_count()`, which used
    /// to recompute `canonical_white_count()` by scanning the whole
    /// `white_lookup` map (see the fix in `index/hash.rs`). That turned
    /// building a plane for a ~3.6M-slot sector into minutes of work instead
    /// of about a second. A generous bound (still a wide safety margin over
    /// the ~1s this takes on dev hardware in an unoptimized `cargo test`
    /// build) is enough to catch a return of the quadratic behavior without
    /// making the test flaky on slower machines.
    #[test]
    fn build_stays_near_linear_for_the_largest_bundled_sector() {
        use std::time::{Duration, Instant};
        let provider = FileDatabaseProvider::new(asset_root());
        let variant = DatabaseVariant::STANDARD;
        let db = Database::open_variant_with_options(
            provider.clone(),
            variant,
            DatabaseOptions::with_sector_cache_capacity(1),
        )
        .unwrap();
        let available = db.available_sector_ids().unwrap();
        let mut biggest: Option<(SectorId, usize)> = None;
        for id in available {
            let hasher = PerfectHasher::new(id.white_on_board, id.black_on_board);
            let hc = hasher.hash_count();
            if biggest.is_none_or(|(_, best)| hc > best) {
                biggest = Some((id, hc));
            }
        }
        let (id, hash_count) = biggest.expect("bundled assets must include at least one sector");
        assert!(
            hash_count > 1_000_000,
            "expected a multi-million-slot bundled sector to exercise this bound, got {hash_count}"
        );

        let name = variant.sector_file_name(id);
        let bytes = provider.read(&name).unwrap();
        let hasher = PerfectHasher::new(id.white_on_board, id.black_on_board);
        let sec_vals = crate::database::read_secval(&provider, variant).unwrap();
        let sector_value = sec_vals.value(id).unwrap();

        let start = Instant::now();
        let _plane = WdlPlane::build(&bytes, &hasher, sector_value, &sec_vals).unwrap();
        let elapsed = start.elapsed();
        assert!(
            elapsed < Duration::from_secs(10),
            "building the WDL plane for {id:?} ({hash_count} slots) took {elapsed:?}, \
             expected near-linear scaling (~1s); this usually means an O(n^2) regression \
             was reintroduced somewhere in the per-slot symmetry-redirect path"
        );
    }

    #[test]
    fn canonical_key_round_trips() {
        let id = SectorId::new(3, 4, 1, 2);
        let key = pack_canonical_key(id, 123_456);
        assert_eq!(unpack_canonical_key(key), (id, 123_456));
    }

    #[test]
    fn plane_matches_precise_database_for_bundled_sectors() {
        // Cross-check every *small* bundled asset sector exhaustively, and
        // every larger one on a bounded sample: the fast 2-bit plane must
        // agree with the precise (steps-carrying) database on every slot's
        // WDL. This is the correctness anchor for the whole mining
        // pipeline's tier-2 pre-filter. Larger sectors (millions of slots)
        // are deliberately capped so this stays a fast unit test; building
        // a plane for a genuinely huge sector is exercised by the mining
        // tool's own tests / the M1 density-report run against the full
        // external database, not here.
        const SMALL_SECTOR_HASH_COUNT: usize = 20_000;
        const SAMPLE_CAP: usize = 500;

        let provider = FileDatabaseProvider::new(asset_root());
        let variant = DatabaseVariant::STANDARD;
        let mut db = Database::open_variant_with_options(
            provider.clone(),
            variant,
            DatabaseOptions::with_sector_cache_capacity(8),
        )
        .unwrap();
        let mut planes = WdlPlaneCache::new(provider, variant).unwrap();

        let available = db.available_sector_ids().unwrap();
        assert!(!available.is_empty());
        let mut checked_small_sector = false;
        for id in available {
            let hasher = PerfectHasher::new(id.white_on_board, id.black_on_board);
            let is_small = hasher.hash_count() <= SMALL_SECTOR_HASH_COUNT;
            checked_small_sector |= is_small;
            let sample_limit = if is_small {
                hasher.hash_count()
            } else {
                SAMPLE_CAP
            };
            for index in 0..sample_limit {
                let board = hasher.inverse_board(index);
                let white_bits = (board & 0x00ff_ffff) as u32;
                let black_bits = ((board >> 24) & 0x00ff_ffff) as u32;
                let query = PerfectQuery::new(
                    white_bits,
                    black_bits,
                    id.white_in_hand,
                    id.black_in_hand,
                    0,
                    false,
                );
                let precise = db
                    .evaluate_outcome(query)
                    .unwrap()
                    .expect("bundled sector query must resolve")
                    .wdl();
                let fast = planes
                    .wdl_for_query(query)
                    .unwrap()
                    .expect("plane query must resolve for the same position");
                assert_eq!(
                    precise,
                    i32::from(fast),
                    "WDL plane disagrees with precise DB for sector {id:?} index {index}"
                );
            }
        }
        assert!(
            checked_small_sector,
            "expected at least one bundled sector small enough to check exhaustively"
        );
    }

    #[test]
    fn plane_serialization_round_trips() {
        let provider = FileDatabaseProvider::new(asset_root());
        let mut planes = WdlPlaneCache::new(provider, DatabaseVariant::STANDARD).unwrap();
        let id = SectorId::new(0, 1, 9, 8);
        // One white-to-move query (black_bits has exactly 1 bit, matching
        // this sector's (white=0, black=1) shape) to pin down a concrete
        // slot to cross-check after the round trip.
        let query = PerfectQuery::new(0, 1, 9, 8, 0, false);
        let expected = planes.wdl_for_query(query).unwrap().unwrap();

        let hash_count = planes.hasher_for(id).hash_count();
        let plane = planes.plane_for(id).unwrap().clone();
        assert_eq!(plane.hash_count(), hash_count);
        let bytes = plane.to_bytes();
        let restored = WdlPlane::from_bytes(&bytes).unwrap();
        assert_eq!(restored, plane);
        let index = planes.hasher_for(id).hash_probe(1_u64 << 24).index;
        assert_eq!(restored.wdl_at(index), expected);
    }

    #[test]
    fn plane_cache_persists_to_disk_cache_dir() {
        let tmp =
            std::env::temp_dir().join(format!("sanmill_wdl_plane_test_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&tmp);
        let provider = FileDatabaseProvider::new(asset_root());
        let options = WdlPlaneCacheOptions {
            plane_cache_capacity: None,
            cache_dir: Some(tmp.clone()),
        };
        let query = PerfectQuery::new(0, 0, 9, 9, 0, false);
        {
            let mut planes = WdlPlaneCache::with_options(
                provider.clone(),
                DatabaseVariant::STANDARD,
                options.clone(),
            )
            .unwrap();
            assert_eq!(planes.wdl_for_query(query).unwrap(), Some(0));
        }
        let cache_file = tmp.join("std_0_0_9_9.wdl2");
        assert!(
            cache_file.is_file(),
            "plane build must persist a .wdl2 cache file"
        );
        let cached_bytes = std::fs::read(&cache_file).unwrap();
        let cached_plane = WdlPlane::from_bytes(&cached_bytes).unwrap();
        assert_eq!(cached_plane.wdl_at(0), 0, "empty board is a known draw");

        // A fresh cache instance (same provider, but starting cold) must load
        // the disk-cached plane and answer the same query.
        let mut reloaded =
            WdlPlaneCache::with_options(provider, DatabaseVariant::STANDARD, options).unwrap();
        assert_eq!(reloaded.wdl_for_query(query).unwrap(), Some(0));

        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn plane_cache_capacity_bounds_loaded_planes() {
        let provider = FileDatabaseProvider::new(asset_root());
        let options = WdlPlaneCacheOptions {
            plane_cache_capacity: Some(1),
            cache_dir: None,
        };
        let mut planes =
            WdlPlaneCache::with_options(provider, DatabaseVariant::STANDARD, options).unwrap();
        assert_eq!(planes.loaded_plane_count(), 0);
        planes
            .wdl_for_query(PerfectQuery::new(0, 0, 9, 9, 0, false))
            .unwrap();
        assert_eq!(planes.loaded_plane_count(), 1);
        planes
            .wdl_for_query(PerfectQuery::new(1, 0, 8, 9, 1, false))
            .unwrap();
        assert_eq!(planes.loaded_plane_count(), 1);
    }
}
