// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

use std::collections::BTreeMap;

use super::symmetry::{inverse_op, transform24, transform48};

const BOARD_POINTS: u8 = 24;
const MASK24: u64 = 0x00ff_ffff;

#[derive(Clone, Debug)]
pub struct PerfectHasher {
    white_count: u8,
    black_count: u8,
    positions_per_white: usize,
    white_lookup: BTreeMap<u32, WhiteEntry>,
    black_rank: BTreeMap<u32, usize>,
    /// `white_orbit_index -> canonical (seed) white bitboard`.  Inverse of
    /// [`WhiteEntry::index`], used by [`PerfectHasher::inverse_board`].
    white_inverse: Vec<u32>,
    /// `black_rank_index -> collapsed black bitboard`.  Inverse of
    /// `black_rank`, used by [`PerfectHasher::inverse_board`].
    black_inverse: Vec<u32>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct HashProbe {
    pub index: usize,
    pub canonical_board: u64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct WhiteEntry {
    index: usize,
    /// Bitmask over the 16 symmetry operations: bit `op` is set iff
    /// `transform24(op, white) == seed`, i.e. *every* operation mapping
    /// this white pattern onto its orbit's canonical seed -- not just one.
    ///
    /// Storing the full set matters whenever the seed has a nontrivial
    /// stabilizer (a symmetry fixing the white pattern but not the whole
    /// board): the operations then differ in what they do to the *black*
    /// pieces, and [`PerfectHasher::hash_probe`] must consider all of them
    /// to fold every symmetric presentation of a position onto one
    /// canonical board. An earlier version stored a single arbitrary
    /// ("last one wins") operation, which made `hash_probe` return
    /// *different* indices for symmetric presentations of the same
    /// position in every sector whose white patterns have stabilizers --
    /// harmless for raw database value reads (the on-disk format's
    /// `Symmetry` redirect entries give every presentation's slot a
    /// correct value) but fatal for canonical-key users like the error
    /// patch, which need one key per abstract position.
    transforms_to_canonical: u16,
}

impl PerfectHasher {
    pub fn new(white_count: u8, black_count: u8) -> Self {
        assert!(
            white_count <= BOARD_POINTS && black_count <= BOARD_POINTS,
            "piece counts must fit on the 24-point board"
        );
        assert!(
            white_count + black_count <= BOARD_POINTS,
            "white and black pieces must not exceed board size"
        );

        let (white_lookup, white_inverse) = build_white_lookup(white_count);
        let compact_points = BOARD_POINTS - white_count;
        let black_inverse = combination_masks(compact_points, black_count);
        let black_rank = black_inverse
            .iter()
            .copied()
            .enumerate()
            .map(|(index, mask)| (mask, index))
            .collect();
        let positions_per_white = binom(compact_points, black_count);

        Self {
            white_count,
            black_count,
            positions_per_white,
            white_lookup,
            black_rank,
            white_inverse,
            black_inverse,
        }
    }

    pub fn hash_count(&self) -> usize {
        self.canonical_white_count() * self.positions_per_white
    }

    /// Number of distinct white-piece orbits (== number of canonical seeds
    /// in `white_inverse`). `O(1)`: earlier code recomputed this by scanning
    /// every entry of `white_lookup` (up to 16 entries per orbit) for its
    /// max index, which turned any per-slot caller (e.g. resolving a
    /// `Symmetry` redirect for every slot of a sector while building a WDL
    /// plane) into an accidental O(hash_count * white_lookup.len()) scan.
    pub fn canonical_white_count(&self) -> usize {
        self.white_inverse.len()
    }

    pub fn hash_probe(&self, board: u64) -> HashProbe {
        let white = (board & MASK24) as u32;
        let black = ((board >> 24) & MASK24) as u32;
        assert_eq!(
            white.count_ones(),
            u32::from(self.white_count),
            "white bit count must match hasher sector"
        );
        assert_eq!(
            black.count_ones(),
            u32::from(self.black_count),
            "black bit count must match hasher sector"
        );
        assert_eq!(
            white & black,
            0,
            "white and black bitboards must not overlap"
        );

        let entry = self
            .white_lookup
            .get(&white)
            .copied()
            .expect("white bitboard with matching popcount must be indexed");
        let seed = self.white_inverse[entry.index];

        // Every operation in the set maps `white` onto the orbit seed but
        // may transform the black pieces differently (they differ by a
        // stabilizer of the seed). Taking the minimum resulting board makes
        // the fold a true invariant: all 16 symmetric presentations of a
        // position converge to the same canonical board, and hence the same
        // index. See `WhiteEntry::transforms_to_canonical`.
        let mut ops = entry.transforms_to_canonical;
        debug_assert_ne!(
            ops, 0,
            "every indexed white pattern has at least one transform"
        );
        let mut canonical = u64::MAX;
        while ops != 0 {
            let op = ops.trailing_zeros() as u8;
            ops &= ops - 1;
            let candidate = transform48(op, board);
            debug_assert_eq!(
                (candidate & MASK24) as u32,
                seed,
                "every recorded transform must map the white pattern to its orbit seed"
            );
            canonical = canonical.min(candidate);
        }

        let compact_black = collapse(canonical);
        let black_index = self
            .black_rank
            .get(&compact_black)
            .copied()
            .expect("collapsed black bitboard must be indexed");

        HashProbe {
            index: entry.index * self.positions_per_white + black_index,
            canonical_board: canonical,
        }
    }

    pub fn hash_index(&self, board: u64) -> usize {
        self.hash_probe(board).index
    }

    /// Inverse of [`Self::direct_hash_index`]: reconstruct the canonical
    /// board stored at `index`.  Mirrors legacy C++ `Hash::inv_hash`
    /// (`index/hash.cpp`), which the DD solver uses to enumerate every state
    /// in a sector.  Used by the WDL-plane bulk builder to recover the board
    /// a `Symmetry` redirect slot needs to transform, since a bare index
    /// carries no board information on its own.
    pub fn inverse_board(&self, index: usize) -> u64 {
        assert!(
            index < self.hash_count(),
            "Perfect DB inverse_board index out of range"
        );
        let white_index = index / self.positions_per_white;
        let black_index = index % self.positions_per_white;
        let white = self.white_inverse[white_index];
        let compact_black = self.black_inverse[black_index];
        uncollapse(u64::from(white) | (u64::from(compact_black) << 24))
    }

    pub fn direct_hash_index(&self, board: u64) -> usize {
        let white = (board & MASK24) as u32;
        let black = ((board >> 24) & MASK24) as u32;
        assert_eq!(
            white.count_ones(),
            u32::from(self.white_count),
            "white bit count must match hasher sector"
        );
        assert_eq!(
            black.count_ones(),
            u32::from(self.black_count),
            "black bit count must match hasher sector"
        );
        assert_eq!(
            white & black,
            0,
            "white and black bitboards must not overlap"
        );

        let white_index = self
            .white_lookup
            .get(&white)
            .map(|entry| entry.index)
            .expect("white bitboard with matching popcount must be indexed");
        let compact_black = collapse(board);
        let black_index = self
            .black_rank
            .get(&compact_black)
            .copied()
            .expect("collapsed black bitboard must be indexed");

        white_index * self.positions_per_white + black_index
    }
}

pub fn next_choose(x: u32) -> u32 {
    if x == 0 {
        return 1_u32 << BOARD_POINTS;
    }
    let c = x & x.wrapping_neg();
    let r = x + c;
    (((r ^ x) >> 2) / c) | r
}

pub fn binom(n: u8, k: u8) -> usize {
    assert!(k <= n, "binomial k must be <= n");
    let k = k.min(n - k);
    let mut result = 1_usize;
    for i in 0..k {
        result = result * usize::from(n - i) / usize::from(i + 1);
    }
    result
}

pub fn collapse(board: u64) -> u32 {
    let white = (board & MASK24) as u32;
    let mut black = ((board >> 24) & MASK24) as u32;
    let mut result = 0_u32;
    let mut compact_bit = 1_u32;
    for board_bit in (0..BOARD_POINTS).map(|index| 1_u32 << index) {
        if white & board_bit == 0 {
            result |= black & compact_bit;
            compact_bit <<= 1;
        } else {
            black >>= 1;
        }
    }
    result
}

pub fn uncollapse(board: u64) -> u64 {
    let white = (board & MASK24) as u32;
    let mut compact_black = ((board >> 24) & MASK24) as u32;
    let mut black = 0_u32;
    for board_bit in (0..BOARD_POINTS).map(|index| 1_u32 << index) {
        if white & board_bit != 0 {
            compact_black <<= 1;
        } else {
            black |= compact_black & board_bit;
        }
    }
    u64::from(white) | (u64::from(black) << 24)
}

/// Build the forward `white bitboard -> (orbit index, transforms to
/// canonical)` lookup, plus its inverse `orbit index -> canonical (seed)
/// white bitboard`.
///
/// The seed is the first `white` bitboard [`combination_masks`] produces
/// for each new orbit; it is its own canonical representative (the
/// identity operation is always in its `transforms_to_canonical` set).
/// Every operation reaching a given member from the seed contributes its
/// inverse to that member's transform set (see
/// [`WhiteEntry::transforms_to_canonical`] for why the whole set is kept).
fn build_white_lookup(white_count: u8) -> (BTreeMap<u32, WhiteEntry>, Vec<u32>) {
    let mut lookup: BTreeMap<u32, WhiteEntry> = BTreeMap::new();
    let mut inverse = Vec::new();
    let mut orbit_index = 0_usize;
    for white in combination_masks(BOARD_POINTS, white_count) {
        if lookup.contains_key(&white) {
            continue;
        }
        for op in 0_u8..16 {
            let transformed = transform24(op, white);
            let entry = lookup.entry(transformed).or_insert(WhiteEntry {
                index: orbit_index,
                transforms_to_canonical: 0,
            });
            assert_eq!(
                entry.index, orbit_index,
                "a white pattern must not appear in two orbits"
            );
            entry.transforms_to_canonical |= 1_u16 << inverse_op(op);
        }
        inverse.push(white);
        orbit_index += 1;
    }
    (lookup, inverse)
}

fn combination_masks(universe: u8, count: u8) -> Vec<u32> {
    assert!(
        universe <= BOARD_POINTS,
        "combination universe is too large"
    );
    assert!(count <= universe, "combination count must be <= universe");
    let limit = 1_u32 << universe;
    let mut result = Vec::with_capacity(binom(universe, count));
    let mut mask = if count == 0 { 0 } else { (1_u32 << count) - 1 };
    while mask < limit {
        result.push(mask);
        mask = next_choose(mask);
    }
    result
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use crate::file_format::{RawEval, RawEvalKind, SectorFile};

    use super::*;

    fn asset_path(name: &str) -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../src/ui/flutter_app/assets/databases")
            .join(name)
    }

    #[test]
    fn next_choose_matches_cxx_sequence() {
        let mut masks = Vec::new();
        let mut mask = 0b0011_u32;
        while mask < (1 << 5) {
            masks.push(mask);
            mask = next_choose(mask);
        }
        assert_eq!(
            masks,
            vec![
                0b00011, 0b00101, 0b00110, 0b01001, 0b01010, 0b01100, 0b10001, 0b10010, 0b10100,
                0b11000,
            ]
        );
    }

    #[test]
    fn collapse_round_trips_through_white_blockers() {
        let white = (1_u64 << 0) | (1_u64 << 5);
        let black = (1_u64 << 1) | (1_u64 << 23);
        let board = white | (black << 24);
        let compact = collapse(board);
        let restored = uncollapse(white | (u64::from(compact) << 24));
        assert_eq!(restored, board);
    }

    #[test]
    fn hashes_empty_board_sector() {
        let bytes = std::fs::read(asset_path("std_0_0_9_9.sec2")).unwrap();
        let hasher = PerfectHasher::new(0, 0);
        let mut sector = SectorFile::parse(&bytes, hasher.hash_count()).unwrap();

        assert_eq!(hasher.hash_count(), 1);
        assert_eq!(hasher.hash_index(0), 0);
        assert_eq!(sector.eval_at(0).unwrap(), RawEval::new(-21, 2));
    }

    #[test]
    fn hashes_single_black_stone_sector() {
        let bytes = std::fs::read(asset_path("std_0_1_9_8.sec2")).unwrap();
        let hasher = PerfectHasher::new(0, 1);
        let mut sector = SectorFile::parse(&bytes, hasher.hash_count()).unwrap();

        let first = 1_u64 << 24;
        let last = (1_u64 << 23) << 24;
        assert_eq!(hasher.hash_count(), 24);
        assert_eq!(hasher.hash_index(first), 0);
        assert_eq!(sector.eval_at(0).unwrap(), RawEval::new(18, 1));
        // Grid semantics (matching the on-disk enumeration): slot 23 is
        // the un-folded position of a black stone on point 23, and the
        // solver stored a `Symmetry` redirect there.
        assert_eq!(hasher.direct_hash_index(last), 23);
        let redirect = sector.eval_at(23).unwrap();
        assert_eq!(redirect.kind(), RawEvalKind::Symmetry { operation: 8 });
        // Probe semantics: `hash_probe` folds the same board onto its
        // orbit's canonical slot, which must carry the *resolved* eval the
        // redirect points at (the empty white pattern is stabilized by all
        // 16 operations, so the canonical fold is the minimum board over
        // the stone's whole orbit).
        let probe = hasher.hash_probe(last);
        assert!(probe.index < 23);
        assert_eq!(hasher.direct_hash_index(probe.canonical_board), probe.index);
        let folded = sector.eval_at(probe.index).unwrap();
        assert!(!matches!(folded.kind(), RawEvalKind::Symmetry { .. }));
    }

    /// The canonical-key invariant the error patch (and the mining
    /// pipeline's dedup) depend on: every symmetric presentation of a
    /// position must fold to the same probe index and the same canonical
    /// board. Regression for the "arbitrary stabilizer transform" bug,
    /// which broke this for ~21% of (4,3) boards (every white pattern
    /// whose orbit seed has a nontrivial stabilizer).
    #[test]
    fn hash_probe_is_invariant_across_all_symmetric_presentations() {
        // Small sectors exhaustively; the larger (4,3) strided so the test
        // stays fast in debug builds while still crossing many
        // stabilizer-affected orbits.
        for (white_count, black_count, stride) in [
            (0u8, 1u8, 1usize),
            (1, 1, 1),
            (2, 2, 1),
            (3, 2, 7),
            (4, 3, 97),
        ] {
            let hasher = PerfectHasher::new(white_count, black_count);
            for index in (0..hasher.hash_count()).step_by(stride) {
                let board = hasher.inverse_board(index);
                let reference = hasher.hash_probe(board);
                for op in 0_u8..16 {
                    let presented = transform48(op, board);
                    let probe = hasher.hash_probe(presented);
                    assert_eq!(
                        probe.index, reference.index,
                        "W={white_count} B={black_count} slot={index} op={op}: symmetric \
                         presentations must fold to one index"
                    );
                    assert_eq!(
                        probe.canonical_board, reference.canonical_board,
                        "W={white_count} B={black_count} slot={index} op={op}: symmetric \
                         presentations must fold to one canonical board"
                    );
                }
            }
        }
    }

    /// The concrete (4,3) pair from the arena investigation that exposed
    /// the stabilizer bug: two presentations of the same abstract position
    /// (`transform48(13, arena) == entry`) which the old code folded to
    /// the same *parent* slot only by luck while folding their children
    /// apart. They must produce identical probes.
    #[test]
    fn regression_arena_collision_pair_folds_identically() {
        let arena_board: u64 = 0x022500 | (0x001c_0000_u64 << 24);
        let entry_board: u64 = 0x002502 | (0x0000_00c1_u64 << 24);
        assert_eq!(
            transform48(13, arena_board),
            entry_board,
            "the two boards are symmetric presentations of one position"
        );
        let hasher = PerfectHasher::new(4, 3);
        let arena_probe = hasher.hash_probe(arena_board);
        let entry_probe = hasher.hash_probe(entry_board);
        assert_eq!(arena_probe.index, entry_probe.index);
        assert_eq!(arena_probe.canonical_board, entry_probe.canonical_board);
    }

    #[test]
    fn inverse_board_round_trips_direct_hash_index() {
        for (white_count, black_count) in [(0, 0), (0, 1), (1, 1), (2, 2), (3, 3)] {
            let hasher = PerfectHasher::new(white_count, black_count);
            for index in 0..hasher.hash_count() {
                let board = hasher.inverse_board(index);
                assert_eq!(
                    hasher.direct_hash_index(board),
                    index,
                    "round trip failed for W={white_count} B={black_count} index={index}"
                );
            }
        }
    }

    #[test]
    fn inverse_board_probe_is_idempotent_and_grid_consistent() {
        // `inverse_board` enumerates the on-disk *grid* (every
        // seed-white × collapsed-black combination), which is a superset
        // of `hash_probe`'s canonical representatives whenever a seed has
        // a nontrivial stabilizer: the extra grid slots are the ones the
        // solver stored `Symmetry` redirects in. Probing therefore need
        // not return the slot itself, but it must be stable: the fold of
        // a grid board is a fixed point of further folding, and its
        // canonical board sits at exactly the folded grid slot (the
        // property the redirect-resolution path in `Database::evaluate_raw`
        // relies on when it calls `direct_hash_index` afterwards).
        for (white_count, black_count) in [(1u8, 1u8), (3, 2), (4, 3)] {
            let hasher = PerfectHasher::new(white_count, black_count);
            for index in (0..hasher.hash_count()).step_by(41) {
                let board = hasher.inverse_board(index);
                let probe = hasher.hash_probe(board);
                assert_eq!(
                    hasher.direct_hash_index(probe.canonical_board),
                    probe.index,
                    "canonical board must live at the folded grid slot"
                );
                let refold = hasher.hash_probe(probe.canonical_board);
                assert_eq!(refold.index, probe.index, "folding must be idempotent");
                assert_eq!(refold.canonical_board, probe.canonical_board);
            }
        }
    }
}
