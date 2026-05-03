// SPDX-License-Identifier: GPL-3.0-or-later
// Static move-priority tables and shuffle helpers consumed by the move
// generator and the move-picker.  These mirror the legacy C++ engine's
// `Mills::move_priority_list_shuffle` and `MovePicker` static tables.

use tgf_core::MoveOrderContext;

use super::MillVariantOptions;

pub(super) const RATING_BLOCK_ONE_MILL: i32 = 10;
pub(super) const RATING_ONE_MILL: i32 = 11;
pub(super) const RATING_STAR_SQUARE: i32 = 11;

pub(super) const PRIORITY_NO_DIAGONAL: [usize; 24] = [
    9, 11, 13, 15, 1, 3, 5, 7, 17, 19, 21, 23, 10, 12, 14, 8, 2, 4, 6, 0, 18, 20, 22, 16,
];
pub(super) const PRIORITY_DIAGONAL: [usize; 24] = [
    10, 12, 14, 8, 2, 4, 6, 0, 18, 20, 22, 16, 9, 11, 13, 15, 1, 3, 5, 7, 17, 19, 21, 23,
];
pub(super) const PRIORITY_SKILL_1: [usize; 24] = [
    17, 18, 19, 20, 21, 22, 23, 16, 9, 10, 11, 12, 13, 14, 15, 8, 1, 2, 3, 4, 5, 6, 7, 0,
];

pub(super) fn move_priority_list_for_search(
    options: &MillVariantOptions,
    ctx: &MoveOrderContext,
) -> [usize; 24] {
    let mut priority = if ctx.skill_level == 1 {
        PRIORITY_SKILL_1
    } else if options.has_diagonal_lines {
        PRIORITY_DIAGONAL
    } else {
        PRIORITY_NO_DIAGONAL
    };

    if !ctx.shuffling {
        return priority;
    }
    if ctx.skill_level == 1 {
        shuffle_priority_slice(&mut priority, ctx.shuffle_seed);
    } else {
        let mut seed = ctx.shuffle_seed;
        shuffle_priority_slice(&mut priority[0..4], seed);
        seed = splitmix64(seed);
        shuffle_priority_slice(&mut priority[4..12], seed);
        seed = splitmix64(seed);
        shuffle_priority_slice(&mut priority[12..16], seed);
        seed = splitmix64(seed);
        shuffle_priority_slice(&mut priority[16..24], seed);
    }
    priority
}

pub(super) fn default_dense_priority() -> [usize; 24] {
    std::array::from_fn(|idx| idx)
}

fn shuffle_priority_slice(slice: &mut [usize], seed: u64) {
    if slice.len() < 2 {
        return;
    }
    let mut state = if seed == 0 {
        0x9E37_79B9_7F4A_7C15
    } else {
        seed
    };
    for i in (1..slice.len()).rev() {
        state = splitmix64(state);
        let j = (state as usize) % (i + 1);
        slice.swap(i, j);
    }
}

fn splitmix64(mut value: u64) -> u64 {
    value = value.wrapping_add(0x9E37_79B9_7F4A_7C15);
    let mut z = value;
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    z ^ (z >> 31)
}

pub(super) fn is_star_square(options: &MillVariantOptions, node: usize) -> bool {
    if options.has_diagonal_lines {
        // C++ `Mills::move_priority_list_shuffle` uses legacy squares
        // SQ_17/SQ_19/SQ_21/SQ_23 for diagonal-rule star priority.
        // Those map to dense Rust nodes 10/12/14/8 respectively.
        matches!(node, 8 | 10 | 12 | 14)
    } else {
        // C++ non-diagonal star squares are legacy SQ_16/SQ_18/SQ_20/SQ_22.
        // Dense Rust node ids for those squares are 9/11/13/15.
        matches!(node, 9 | 11 | 13 | 15)
    }
}
