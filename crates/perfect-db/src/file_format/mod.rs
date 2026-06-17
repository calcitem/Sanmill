// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

//! Byte-level parsers for the fixed Perfect Database files.
//!
//! This module intentionally does not depend on filesystem APIs. Native code
//! can feed it bytes read from disk, while a future Web implementation can feed
//! it bytes loaded from Flutter assets or fetched over HTTP.

mod sector;
mod secval;

pub use sector::{RawEval, RawEvalKind, SectorFile, SectorHeader};
pub use secval::{SecValTable, SectorId};

use std::fmt;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ParseError {
    EmptyInput,
    MissingLine { line: usize, expected: &'static str },
    InvalidLine { line: usize, message: String },
    InvalidHeader { message: String },
    InvalidLength { expected: usize, actual: usize },
    OutOfBounds { index: usize, len: usize },
    MissingEmSetEntry { index: usize },
}

impl fmt::Display for ParseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::EmptyInput => write!(f, "empty input"),
            Self::MissingLine { line, expected } => {
                write!(f, "line {line}: missing {expected}")
            }
            Self::InvalidLine { line, message } => write!(f, "line {line}: {message}"),
            Self::InvalidHeader { message } => write!(f, "invalid sector header: {message}"),
            Self::InvalidLength { expected, actual } => {
                write!(f, "invalid length: expected {expected} bytes, got {actual}")
            }
            Self::OutOfBounds { index, len } => {
                write!(f, "index {index} is out of bounds for length {len}")
            }
            Self::MissingEmSetEntry { index } => {
                write!(f, "missing em_set entry for eval index {index}")
            }
        }
    }
}

impl std::error::Error for ParseError {}

type ParseResult<T> = Result<T, ParseError>;

fn read_i32_le(bytes: &[u8], offset: usize) -> ParseResult<i32> {
    let end = offset.checked_add(4).ok_or(ParseError::InvalidLength {
        expected: usize::MAX,
        actual: bytes.len(),
    })?;
    let chunk = bytes.get(offset..end).ok_or(ParseError::InvalidLength {
        expected: end,
        actual: bytes.len(),
    })?;
    Ok(i32::from_le_bytes(
        chunk.try_into().expect("slice length is 4"),
    ))
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use super::*;

    fn asset_path(name: &str) -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../src/ui/flutter_app/assets/databases")
            .join(name)
    }

    #[test]
    fn parses_std_secval_asset() {
        let text = std::fs::read_to_string(asset_path("std.secval")).unwrap();
        let table = SecValTable::parse(&text).unwrap();

        assert_eq!(table.virt_loss_val(), -299);
        assert_eq!(table.virt_win_val(), 299);
        assert_eq!(table.len(), 498);
        assert_eq!(table.value(SectorId::new(0, 0, 9, 9)), Some(21));
        assert_eq!(table.value(SectorId::new(0, 1, 9, 8)), Some(-18));
        assert_eq!(table.value(SectorId::new(1, 1, 8, 8)), Some(13));
    }

    #[test]
    fn parses_mora_secval_asset() {
        let text = std::fs::read_to_string(asset_path("mora.secval")).unwrap();
        let table = SecValTable::parse(&text).unwrap();

        assert_eq!(table.virt_loss_val(), -704);
        assert_eq!(table.virt_win_val(), 704);
        assert_eq!(table.len(), 1216);
        assert_eq!(table.value(SectorId::new(0, 0, 12, 12)), Some(686));
        assert_eq!(table.value(SectorId::new(0, 1, 12, 11)), Some(-101));
        assert_eq!(table.value(SectorId::new(1, 1, 11, 11)), Some(210));
    }

    #[test]
    fn parses_lasker_secval_asset() {
        let text = std::fs::read_to_string(asset_path("lask.secval")).unwrap();
        let table = SecValTable::parse(&text).unwrap();

        assert_eq!(table.virt_loss_val(), -1715);
        assert_eq!(table.virt_win_val(), 1715);
        assert_eq!(table.len(), 3070);
        assert_eq!(table.value(SectorId::new(0, 0, 10, 10)), Some(47));
        assert_eq!(table.value(SectorId::new(0, 1, 10, 9)), Some(-67));
        assert_eq!(table.value(SectorId::new(1, 1, 9, 9)), Some(0));
        assert_eq!(table.value(SectorId::new(1, 2, 9, 8)), Some(-386));
    }

    #[test]
    fn parses_empty_board_sector_asset() {
        let bytes = std::fs::read(asset_path("std_0_0_9_9.sec2")).unwrap();
        let sector = SectorFile::parse(&bytes, 1).unwrap();

        assert_eq!(sector.header().version, 2);
        assert_eq!(sector.header().eval_struct_size, 3);
        assert_eq!(sector.header().field2_offset, 12);
        assert!(!sector.header().stone_diff);
        assert_eq!(sector.eval_count(), 1);
        assert_eq!(sector.em_set_len(), 0);
        assert_eq!(sector.eval_at(0).unwrap(), RawEval::new(-21, 2));
    }

    #[test]
    fn parses_mora_empty_board_sector_asset() {
        let bytes = std::fs::read(asset_path("mora_0_0_12_12.sec2")).unwrap();
        let sector = SectorFile::parse(&bytes, 1).unwrap();

        assert_eq!(sector.header().version, 2);
        assert_eq!(sector.header().eval_struct_size, 3);
        assert_eq!(sector.header().field2_offset, 14);
        assert!(!sector.header().stone_diff);
        assert_eq!(sector.eval_count(), 1);
        assert_eq!(sector.em_set_len(), 0);
    }

    #[test]
    fn parses_lasker_empty_board_sector_asset() {
        let bytes = std::fs::read(asset_path("lask_0_0_10_10.sec2")).unwrap();
        let sector = SectorFile::parse(&bytes, 1).unwrap();

        assert_eq!(sector.header().version, 2);
        assert_eq!(sector.header().eval_struct_size, 3);
        assert_eq!(sector.header().field2_offset, 14);
        assert!(!sector.header().stone_diff);
        assert_eq!(sector.eval_count(), 1);
        assert_eq!(sector.em_set_len(), 0);
    }

    #[test]
    fn parses_single_black_stone_sector_asset() {
        let bytes = std::fs::read(asset_path("std_0_1_9_8.sec2")).unwrap();
        let sector = SectorFile::parse(&bytes, 24).unwrap();

        assert_eq!(sector.eval_count(), 24);
        assert_eq!(sector.em_set_len(), 0);
        assert_eq!(sector.eval_at(0).unwrap(), RawEval::new(18, 1));
        let redirect = sector.eval_at(23).unwrap();
        assert_eq!(redirect, RawEval::new(0, -9));
        assert_eq!(redirect.kind(), RawEvalKind::Symmetry { operation: 8 });
    }

    #[test]
    fn resolves_synthetic_em_set_entries() {
        let mut bytes = Vec::new();
        bytes.extend_from_slice(&2_i32.to_le_bytes());
        bytes.extend_from_slice(&3_i32.to_le_bytes());
        bytes.extend_from_slice(&12_i32.to_le_bytes());
        bytes.push(0);
        bytes.resize(64, 0);

        let spec_field2 = 0x800_u32;
        let raw = spec_field2 << 12;
        bytes.extend_from_slice(&raw.to_le_bytes()[0..3]);
        bytes.extend_from_slice(&1_i32.to_le_bytes());
        bytes.extend_from_slice(&0_i32.to_le_bytes());
        bytes.extend_from_slice(&(-3_i32).to_le_bytes());

        let sector = SectorFile::parse(&bytes, 1).unwrap();
        let eval = sector.eval_at(0).unwrap();
        assert_eq!(eval, RawEval::new(0, -3));
        assert_eq!(eval.kind(), RawEvalKind::Symmetry { operation: 2 });
    }
}
