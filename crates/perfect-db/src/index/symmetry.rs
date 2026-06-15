// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

//! Symmetry transforms in Perfect Database index space.
//!
//! The Flutter setup-position editor also has 16 board transforms, but its
//! maps are expressed in legacy square order. These maps are the database
//! perfect-index equivalents used by the historical C++ `sym24_transform`.

pub const SYMMETRY_COUNT: usize = 16;
pub const IDENTITY_OP: u8 = 15;

const INVERSE_OPS: [u8; SYMMETRY_COUNT] = [2, 1, 0, 3, 4, 5, 6, 7, 10, 9, 8, 11, 12, 13, 14, 15];

const MAPS: [[u8; 24]; SYMMETRY_COUNT] = [
    [
        2, 3, 4, 5, 6, 7, 0, 1, 10, 11, 12, 13, 14, 15, 8, 9, 18, 19, 20, 21, 22, 23, 16, 17,
    ],
    [
        4, 5, 6, 7, 0, 1, 2, 3, 12, 13, 14, 15, 8, 9, 10, 11, 20, 21, 22, 23, 16, 17, 18, 19,
    ],
    [
        6, 7, 0, 1, 2, 3, 4, 5, 14, 15, 8, 9, 10, 11, 12, 13, 22, 23, 16, 17, 18, 19, 20, 21,
    ],
    [
        4, 3, 2, 1, 0, 7, 6, 5, 12, 11, 10, 9, 8, 15, 14, 13, 20, 19, 18, 17, 16, 23, 22, 21,
    ],
    [
        0, 7, 6, 5, 4, 3, 2, 1, 8, 15, 14, 13, 12, 11, 10, 9, 16, 23, 22, 21, 20, 19, 18, 17,
    ],
    [
        2, 1, 0, 7, 6, 5, 4, 3, 10, 9, 8, 15, 14, 13, 12, 11, 18, 17, 16, 23, 22, 21, 20, 19,
    ],
    [
        6, 5, 4, 3, 2, 1, 0, 7, 14, 13, 12, 11, 10, 9, 8, 15, 22, 21, 20, 19, 18, 17, 16, 23,
    ],
    [
        16, 17, 18, 19, 20, 21, 22, 23, 8, 9, 10, 11, 12, 13, 14, 15, 0, 1, 2, 3, 4, 5, 6, 7,
    ],
    [
        18, 19, 20, 21, 22, 23, 16, 17, 10, 11, 12, 13, 14, 15, 8, 9, 2, 3, 4, 5, 6, 7, 0, 1,
    ],
    [
        20, 21, 22, 23, 16, 17, 18, 19, 12, 13, 14, 15, 8, 9, 10, 11, 4, 5, 6, 7, 0, 1, 2, 3,
    ],
    [
        22, 23, 16, 17, 18, 19, 20, 21, 14, 15, 8, 9, 10, 11, 12, 13, 6, 7, 0, 1, 2, 3, 4, 5,
    ],
    [
        20, 19, 18, 17, 16, 23, 22, 21, 12, 11, 10, 9, 8, 15, 14, 13, 4, 3, 2, 1, 0, 7, 6, 5,
    ],
    [
        16, 23, 22, 21, 20, 19, 18, 17, 8, 15, 14, 13, 12, 11, 10, 9, 0, 7, 6, 5, 4, 3, 2, 1,
    ],
    [
        18, 17, 16, 23, 22, 21, 20, 19, 10, 9, 8, 15, 14, 13, 12, 11, 2, 1, 0, 7, 6, 5, 4, 3,
    ],
    [
        22, 21, 20, 19, 18, 17, 16, 23, 14, 13, 12, 11, 10, 9, 8, 15, 6, 5, 4, 3, 2, 1, 0, 7,
    ],
    [
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23,
    ],
];

pub fn inverse_op(op: u8) -> u8 {
    assert!(
        (op as usize) < SYMMETRY_COUNT,
        "symmetry operation out of range"
    );
    INVERSE_OPS[op as usize]
}

pub fn transform_index(op: u8, index: u8) -> u8 {
    assert!(
        (op as usize) < SYMMETRY_COUNT,
        "symmetry operation out of range"
    );
    assert!(index < 24, "perfect index out of range");
    MAPS[op as usize][index as usize]
}

pub fn transform24(op: u8, bits: u32) -> u32 {
    assert!(
        bits & !0x00ff_ffff == 0,
        "Perfect DB bitboards must fit in 24 bits"
    );
    let mut result = 0_u32;
    for index in 0_u8..24 {
        if bits & (1_u32 << index) != 0 {
            result |= 1_u32 << transform_index(op, index);
        }
    }
    result
}

pub fn transform48(op: u8, board: u64) -> u64 {
    assert!(
        board & !0x0000_ffff_ffff_ffff == 0,
        "Perfect DB board must fit in 48 bits"
    );
    let white = transform24(op, (board & 0x00ff_ffff) as u32) as u64;
    let black = transform24(op, ((board >> 24) & 0x00ff_ffff) as u32) as u64;
    white | (black << 24)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn identity_is_cxx_operation_15() {
        let all_bits = 0x00ff_ffff;
        assert_eq!(transform24(IDENTITY_OP, all_bits), all_bits);
        for index in 0_u8..24 {
            assert_eq!(transform_index(IDENTITY_OP, index), index);
        }
    }

    #[test]
    fn single_bit_maps_match_cxx_slow_tables() {
        assert_eq!(transform_index(0, 0), 2);
        assert_eq!(transform_index(0, 22), 16);
        assert_eq!(transform_index(3, 0), 4);
        assert_eq!(transform_index(4, 0), 0);
        assert_eq!(transform_index(7, 0), 16);
        assert_eq!(transform_index(14, 0), 22);
    }

    #[test]
    fn inverse_operations_restore_bitboards() {
        let bits = (1_u32 << 0) | (1_u32 << 9) | (1_u32 << 23);
        for op in 0_u8..SYMMETRY_COUNT as u8 {
            let transformed = transform24(op, bits);
            assert_eq!(transform24(inverse_op(op), transformed), bits);
        }
    }
}
