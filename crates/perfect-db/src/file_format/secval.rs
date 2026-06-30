// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

use std::collections::BTreeMap;

use super::{ParseError, ParseResult};

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct SectorId {
    pub white_on_board: u8,
    pub black_on_board: u8,
    pub white_in_hand: u8,
    pub black_in_hand: u8,
}

impl SectorId {
    pub fn new(
        white_on_board: u8,
        black_on_board: u8,
        white_in_hand: u8,
        black_in_hand: u8,
    ) -> Self {
        assert!(
            white_on_board <= 12
                && black_on_board <= 12
                && white_in_hand <= 12
                && black_in_hand <= 12,
            "Perfect DB sector ids must stay within supported Mill piece counts"
        );
        Self {
            white_on_board,
            black_on_board,
            white_in_hand,
            black_in_hand,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SecValTable {
    virt_loss_val: i16,
    virt_win_val: i16,
    values: BTreeMap<SectorId, i16>,
}

impl SecValTable {
    pub fn parse(text: &str) -> ParseResult<Self> {
        if text.trim().is_empty() {
            return Err(ParseError::EmptyInput);
        }

        let mut lines = text.lines().enumerate();
        let (loss_line, loss_text) = next_line(&mut lines, 1, "virt_loss_val")?;
        let virt_loss_val = parse_prefixed_i16(loss_line, loss_text, "virt_loss_val:")?;

        let (win_line, win_text) = next_line(&mut lines, 2, "virt_win_val")?;
        let virt_win_val = parse_prefixed_i16(win_line, win_text, "virt_win_val:")?;
        assert_eq!(
            virt_win_val, -virt_loss_val,
            "Perfect DB virtual win/loss values must be symmetric"
        );

        let (count_line, count_text) = next_line(&mut lines, 3, "sector count")?;
        let expected_count = parse_usize(count_line, count_text)?;

        let mut values = BTreeMap::new();
        for _ in 0..expected_count {
            let (line_number, line) = next_line(&mut lines, count_line + 1, "sector value")?;
            let (id, value) = parse_sector_value(line_number, line)?;
            assert!(
                values.insert(id, value).is_none(),
                "duplicate Perfect DB sector id: {id:?}"
            );
        }

        for (line_index, line) in lines {
            if !line.trim().is_empty() {
                return Err(ParseError::InvalidLine {
                    line: line_index + 1,
                    message: "unexpected trailing content".to_owned(),
                });
            }
        }

        assert_eq!(
            values.len(),
            expected_count,
            "parsed sector count must match std.secval header"
        );

        Ok(Self {
            virt_loss_val,
            virt_win_val,
            values,
        })
    }

    /// Validate the virtual sentinel values against the packed `key1` width.
    ///
    /// The legacy reader derives `secValMinValue` from `field1Size` and asserts
    /// `2 * virt_loss_val - 5 > secValMinValue` after loading `.secval`.
    pub fn validate_value_range(&self, field1_size: u8) -> ParseResult<()> {
        assert!(
            (1..=15).contains(&field1_size),
            "Perfect DB field1 size must fit a signed i16 value"
        );
        let sec_val_min_value = -(1_i32 << (field1_size - 1));
        let guarded_loss = 2 * i32::from(self.virt_loss_val) - 5;
        if guarded_loss <= sec_val_min_value {
            return Err(ParseError::InvalidHeader {
                message: format!(
                    "virt_loss_val {} is outside field1_size {field1_size}",
                    self.virt_loss_val
                ),
            });
        }
        Ok(())
    }

    pub fn virt_loss_val(&self) -> i16 {
        self.virt_loss_val
    }

    pub fn virt_win_val(&self) -> i16 {
        self.virt_win_val
    }

    pub fn len(&self) -> usize {
        self.values.len()
    }

    pub fn is_empty(&self) -> bool {
        self.values.is_empty()
    }

    pub fn value(&self, id: SectorId) -> Option<i16> {
        self.values.get(&id).copied()
    }

    pub fn sector_ids(&self) -> impl Iterator<Item = SectorId> + '_ {
        self.values.keys().copied()
    }
}

fn next_line<'a>(
    lines: &mut impl Iterator<Item = (usize, &'a str)>,
    fallback_line: usize,
    expected: &'static str,
) -> ParseResult<(usize, &'a str)> {
    lines
        .next()
        .map(|(index, line)| (index + 1, line))
        .ok_or(ParseError::MissingLine {
            line: fallback_line,
            expected,
        })
}

fn parse_prefixed_i16(line_number: usize, line: &str, prefix: &str) -> ParseResult<i16> {
    let value = line
        .trim()
        .strip_prefix(prefix)
        .ok_or_else(|| ParseError::InvalidLine {
            line: line_number,
            message: format!("expected prefix {prefix:?}"),
        })?
        .trim();
    parse_i16(line_number, value)
}

fn parse_sector_value(line_number: usize, line: &str) -> ParseResult<(SectorId, i16)> {
    let parts = line.split_whitespace().collect::<Vec<_>>();
    if parts.len() != 5 {
        return Err(ParseError::InvalidLine {
            line: line_number,
            message: format!("expected 5 fields, got {}", parts.len()),
        });
    }
    let white_on_board = parse_u8(line_number, parts[0])?;
    let black_on_board = parse_u8(line_number, parts[1])?;
    let white_in_hand = parse_u8(line_number, parts[2])?;
    let black_in_hand = parse_u8(line_number, parts[3])?;
    let value = parse_i16(line_number, parts[4])?;
    Ok((
        SectorId::new(white_on_board, black_on_board, white_in_hand, black_in_hand),
        value,
    ))
}

fn parse_usize(line_number: usize, text: &str) -> ParseResult<usize> {
    text.trim()
        .parse::<usize>()
        .map_err(|e| ParseError::InvalidLine {
            line: line_number,
            message: e.to_string(),
        })
}

fn parse_u8(line_number: usize, text: &str) -> ParseResult<u8> {
    text.parse::<u8>().map_err(|e| ParseError::InvalidLine {
        line: line_number,
        message: e.to_string(),
    })
}

fn parse_i16(line_number: usize, text: &str) -> ParseResult<i16> {
    text.parse::<i16>().map_err(|e| ParseError::InvalidLine {
        line: line_number,
        message: e.to_string(),
    })
}
