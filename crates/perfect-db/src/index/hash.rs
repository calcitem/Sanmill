// SPDX-License-Identifier: GPL-3.0-or-later
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
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct WhiteEntry {
    index: usize,
    transform_to_canonical: u8,
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

        let white_lookup = build_white_lookup(white_count);
        let compact_points = BOARD_POINTS - white_count;
        let black_rank = build_rank_lookup(compact_points, black_count);
        let positions_per_white = binom(compact_points, black_count);

        Self {
            white_count,
            black_count,
            positions_per_white,
            white_lookup,
            black_rank,
        }
    }

    pub fn hash_count(&self) -> usize {
        self.canonical_white_count() * self.positions_per_white
    }

    pub fn canonical_white_count(&self) -> usize {
        self.white_lookup
            .values()
            .map(|entry| entry.index)
            .max()
            .map_or(0, |max| max + 1)
    }

    pub fn hash_index(&self, board: u64) -> usize {
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
        let canonical = transform48(entry.transform_to_canonical, board);
        let canonical_white = (canonical & MASK24) as u32;
        let canonical_entry = self
            .white_lookup
            .get(&canonical_white)
            .expect("canonical white bitboard must be indexed");
        assert_eq!(
            canonical_entry.index, entry.index,
            "canonical transform must stay in the same white orbit"
        );

        let compact_black = collapse(canonical);
        let black_index = self
            .black_rank
            .get(&compact_black)
            .copied()
            .expect("collapsed black bitboard must be indexed");

        entry.index * self.positions_per_white + black_index
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

fn build_white_lookup(white_count: u8) -> BTreeMap<u32, WhiteEntry> {
    let mut lookup = BTreeMap::new();
    let mut orbit_index = 0_usize;
    for white in combination_masks(BOARD_POINTS, white_count) {
        if lookup.contains_key(&white) {
            continue;
        }
        for op in 0_u8..16 {
            let transformed = transform24(op, white);
            lookup.insert(
                transformed,
                WhiteEntry {
                    index: orbit_index,
                    transform_to_canonical: inverse_op(op),
                },
            );
        }
        orbit_index += 1;
    }
    lookup
}

fn build_rank_lookup(universe: u8, count: u8) -> BTreeMap<u32, usize> {
    combination_masks(universe, count)
        .into_iter()
        .enumerate()
        .map(|(index, mask)| (mask, index))
        .collect()
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
        let sector = SectorFile::parse(&bytes, hasher.hash_count()).unwrap();

        assert_eq!(hasher.hash_count(), 1);
        assert_eq!(hasher.hash_index(0), 0);
        assert_eq!(sector.eval_at(0).unwrap(), RawEval::new(-21, 2));
    }

    #[test]
    fn hashes_single_black_stone_sector() {
        let bytes = std::fs::read(asset_path("std_0_1_9_8.sec2")).unwrap();
        let hasher = PerfectHasher::new(0, 1);
        let sector = SectorFile::parse(&bytes, hasher.hash_count()).unwrap();

        let first = 1_u64 << 24;
        let last = (1_u64 << 23) << 24;
        assert_eq!(hasher.hash_count(), 24);
        assert_eq!(hasher.hash_index(first), 0);
        assert_eq!(sector.eval_at(0).unwrap(), RawEval::new(18, 1));
        assert_eq!(hasher.hash_index(last), 23);
        let redirect = sector.eval_at(23).unwrap();
        assert_eq!(redirect.kind(), RawEvalKind::Symmetry { operation: 8 });
    }
}
