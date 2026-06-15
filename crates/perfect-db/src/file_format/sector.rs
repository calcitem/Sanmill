// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

use std::collections::BTreeMap;

use super::{ParseError, ParseResult, read_i32_le};

const DD_HEADER_SIZE: usize = 64;
const SUPPORTED_VERSION: i32 = 2;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SectorHeader {
    pub version: i32,
    pub eval_struct_size: usize,
    pub field2_offset: u8,
    pub stone_diff: bool,
}

impl SectorHeader {
    fn parse(bytes: &[u8]) -> ParseResult<Self> {
        if bytes.len() < DD_HEADER_SIZE {
            return Err(ParseError::InvalidLength {
                expected: DD_HEADER_SIZE,
                actual: bytes.len(),
            });
        }

        let version = read_i32_le(bytes, 0)?;
        if version != SUPPORTED_VERSION {
            return Err(ParseError::InvalidHeader {
                message: format!("expected version {SUPPORTED_VERSION}, got {version}"),
            });
        }

        let eval_struct_size = read_i32_le(bytes, 4)?;
        if !(1..=4).contains(&eval_struct_size) {
            return Err(ParseError::InvalidHeader {
                message: format!("unsupported eval struct size {eval_struct_size}"),
            });
        }

        let field2_offset = read_i32_le(bytes, 8)?;
        let bit_width = eval_struct_size * 8;
        if !(1..bit_width).contains(&field2_offset) {
            return Err(ParseError::InvalidHeader {
                message: format!("field2 offset {field2_offset} is outside 1..{bit_width}"),
            });
        }

        let stone_diff = match bytes[12] {
            0 => false,
            1 => true,
            flag => {
                return Err(ParseError::InvalidHeader {
                    message: format!("unsupported stone_diff flag {flag}"),
                });
            }
        };

        Ok(Self {
            version,
            eval_struct_size: eval_struct_size as usize,
            field2_offset: field2_offset as u8,
            stone_diff,
        })
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RawEval {
    pub key1: i32,
    pub key2: i32,
}

impl RawEval {
    pub fn new(key1: i32, key2: i32) -> Self {
        Self { key1, key2 }
    }

    pub fn kind(self) -> RawEvalKind {
        if self.key1 != 0 {
            RawEvalKind::Value
        } else if self.key2 >= 0 {
            RawEvalKind::Count
        } else {
            let operation = -(self.key2 + 1);
            assert!(
                (0..16).contains(&operation),
                "symmetry operation must be in 0..16"
            );
            RawEvalKind::Symmetry {
                operation: operation as u8,
            }
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RawEvalKind {
    Value,
    Count,
    Symmetry { operation: u8 },
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SectorFile {
    header: SectorHeader,
    eval_count: usize,
    eval_bytes: Vec<u8>,
    em_set: BTreeMap<usize, i32>,
}

impl SectorFile {
    pub fn parse(bytes: &[u8], eval_count: usize) -> ParseResult<Self> {
        let header = SectorHeader::parse(bytes)?;
        let eval_size =
            eval_count
                .checked_mul(header.eval_struct_size)
                .ok_or(ParseError::InvalidLength {
                    expected: usize::MAX,
                    actual: bytes.len(),
                })?;
        let em_set_offset =
            DD_HEADER_SIZE
                .checked_add(eval_size)
                .ok_or(ParseError::InvalidLength {
                    expected: usize::MAX,
                    actual: bytes.len(),
                })?;
        let em_set_count_offset = em_set_offset;
        let em_set_count = read_i32_le(bytes, em_set_count_offset)?;
        if em_set_count < 0 {
            return Err(ParseError::InvalidHeader {
                message: format!("negative em_set length {em_set_count}"),
            });
        }

        let em_set_len = em_set_count as usize;
        let expected_len = em_set_count_offset
            .checked_add(4)
            .and_then(|base| base.checked_add(em_set_len.checked_mul(8)?))
            .ok_or(ParseError::InvalidLength {
                expected: usize::MAX,
                actual: bytes.len(),
            })?;
        if bytes.len() != expected_len {
            return Err(ParseError::InvalidLength {
                expected: expected_len,
                actual: bytes.len(),
            });
        }

        let eval_bytes = bytes[DD_HEADER_SIZE..em_set_offset].to_vec();
        let mut em_set = BTreeMap::new();
        let mut offset = em_set_count_offset + 4;
        for _ in 0..em_set_len {
            let index = read_i32_le(bytes, offset)?;
            let value = read_i32_le(bytes, offset + 4)?;
            if index < 0 {
                return Err(ParseError::InvalidHeader {
                    message: format!("negative em_set index {index}"),
                });
            }
            let index = index as usize;
            assert!(
                em_set.insert(index, value).is_none(),
                "duplicate em_set entry for eval index {index}"
            );
            offset += 8;
        }

        Ok(Self {
            header,
            eval_count,
            eval_bytes,
            em_set,
        })
    }

    pub fn header(&self) -> SectorHeader {
        self.header
    }

    pub fn eval_count(&self) -> usize {
        self.eval_count
    }

    pub fn em_set_len(&self) -> usize {
        self.em_set.len()
    }

    pub fn eval_at(&self, index: usize) -> ParseResult<RawEval> {
        if index >= self.eval_count {
            return Err(ParseError::OutOfBounds {
                index,
                len: self.eval_count,
            });
        }

        let offset = index * self.header.eval_struct_size;
        let mut raw = 0_u32;
        for byte_index in 0..self.header.eval_struct_size {
            raw |= u32::from(self.eval_bytes[offset + byte_index]) << (8 * byte_index);
        }

        let field1_bits = self.header.field2_offset;
        let field2_bits = (self.header.eval_struct_size as u8 * 8) - field1_bits;
        let field1_mask = (1_u32 << field1_bits) - 1;
        let key1 = sign_extend(raw & field1_mask, field1_bits);
        let mut key2 = sign_extend(raw >> field1_bits, field2_bits);

        let spec_field2 = -(1_i32 << (field2_bits - 1));
        if key2 == spec_field2 {
            key2 = self
                .em_set
                .get(&index)
                .copied()
                .ok_or(ParseError::MissingEmSetEntry { index })?;
        }

        Ok(RawEval::new(key1, key2))
    }
}

fn sign_extend(value: u32, bits: u8) -> i32 {
    assert!(
        (1..32).contains(&bits),
        "sign extension width must be 1..32"
    );
    let shift = 32 - bits;
    ((value << shift) as i32) >> shift
}
