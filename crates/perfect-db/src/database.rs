// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

//! Rust-native Perfect Database loader prototype.
//!
//! This layer combines the byte parser and perfect-index hasher without
//! replacing the current C++ bridge. It is deliberately provider-based so
//! native files and future Web asset bytes can share the same parser and
//! indexing code.

use std::cmp::Ordering;
use std::collections::BTreeMap;
use std::fmt;
use std::path::{Path, PathBuf};

use crate::file_format::{ParseError, RawEval, RawEvalKind, SecValTable, SectorFile, SectorId};
use crate::index::PerfectHasher;
use crate::index::symmetry::transform48;

#[derive(Debug)]
pub enum DatabaseError {
    Read {
        name: String,
        source: std::io::Error,
    },
    InvalidUtf8 {
        name: String,
        source: std::string::FromUtf8Error,
    },
    Parse {
        name: String,
        source: ParseError,
    },
    MissingSectorValue {
        id: SectorId,
    },
}

impl fmt::Display for DatabaseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Read { name, source } => write!(f, "failed to read {name}: {source}"),
            Self::InvalidUtf8 { name, source } => {
                write!(f, "database text file {name} is not UTF-8: {source}")
            }
            Self::Parse { name, source } => write!(f, "failed to parse {name}: {source}"),
            Self::MissingSectorValue { id } => {
                write!(f, "missing sector base value for {id:?}")
            }
        }
    }
}

impl std::error::Error for DatabaseError {}

pub trait DatabaseProvider {
    fn read(&self, name: &str) -> Result<Vec<u8>, DatabaseError>;
}

#[derive(Clone, Debug)]
pub struct FileDatabaseProvider {
    root: PathBuf,
}

impl FileDatabaseProvider {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }

    pub fn root(&self) -> &Path {
        &self.root
    }
}

impl DatabaseProvider for FileDatabaseProvider {
    fn read(&self, name: &str) -> Result<Vec<u8>, DatabaseError> {
        let path = self.root.join(name);
        std::fs::read(&path).map_err(|source| DatabaseError::Read {
            name: path.display().to_string(),
            source,
        })
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PerfectQuery {
    pub white_bits: u32,
    pub black_bits: u32,
    pub white_in_hand: u8,
    pub black_in_hand: u8,
    pub side_to_move: u8,
    pub only_stone_taking: bool,
}

impl PerfectQuery {
    pub fn new(
        white_bits: u32,
        black_bits: u32,
        white_in_hand: u8,
        black_in_hand: u8,
        side_to_move: u8,
        only_stone_taking: bool,
    ) -> Self {
        assert!(
            white_bits & !0x00ff_ffff == 0 && black_bits & !0x00ff_ffff == 0,
            "Perfect DB bitboards must fit in 24 bits"
        );
        assert_eq!(
            white_bits & black_bits,
            0,
            "Perfect DB bitboards must not overlap"
        );
        assert!(side_to_move <= 1, "Perfect DB side_to_move must be 0 or 1");
        assert!(
            white_in_hand <= 12 && black_in_hand <= 12,
            "Perfect DB hand counts must stay within supported Mill variants"
        );
        Self {
            white_bits,
            black_bits,
            white_in_hand,
            black_in_hand,
            side_to_move,
            only_stone_taking,
        }
    }

    fn sector_and_board(self) -> (SectorId, u64) {
        let white_on_board = self.white_bits.count_ones() as u8;
        let black_on_board = self.black_bits.count_ones() as u8;
        if self.side_to_move == 0 {
            (
                SectorId::new(
                    white_on_board,
                    black_on_board,
                    self.white_in_hand,
                    self.black_in_hand,
                ),
                u64::from(self.white_bits) | (u64::from(self.black_bits) << 24),
            )
        } else {
            (
                SectorId::new(
                    black_on_board,
                    white_on_board,
                    self.black_in_hand,
                    self.white_in_hand,
                ),
                u64::from(self.black_bits) | (u64::from(self.white_bits) << 24),
            )
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct DatabaseEval {
    pub raw: RawEval,
    pub sector_value: i16,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PerfectOutcome {
    Win { steps: i32 },
    Draw { steps: i32 },
    Loss { steps: i32 },
}

impl PerfectOutcome {
    pub fn wdl(self) -> i32 {
        match self {
            Self::Win { .. } => 1,
            Self::Draw { .. } => 0,
            Self::Loss { .. } => -1,
        }
    }

    pub fn steps(self) -> i32 {
        match self {
            Self::Win { steps } | Self::Draw { steps } | Self::Loss { steps } => steps,
        }
    }

    pub fn to_wdl_steps(self) -> (i32, i32) {
        (self.wdl(), self.steps())
    }

    pub fn default_rank(self) -> i32 {
        self.wdl()
    }

    pub fn strict_cmp(self, other: Self) -> Ordering {
        match self.wdl().cmp(&other.wdl()) {
            Ordering::Equal => match (self, other) {
                (Self::Win { steps }, Self::Win { steps: other_steps }) => other_steps.cmp(&steps),
                (Self::Loss { steps }, Self::Loss { steps: other_steps }) => {
                    steps.cmp(&other_steps)
                }
                _ => Ordering::Equal,
            },
            ordering => ordering,
        }
    }

    pub fn negate(self) -> Self {
        match self {
            Self::Win { steps } => Self::Loss { steps },
            Self::Draw { steps } => Self::Draw { steps },
            Self::Loss { steps } => Self::Win { steps },
        }
    }
}

impl DatabaseEval {
    pub fn absolute_key1(self) -> i32 {
        self.raw.key1 + i32::from(self.sector_value)
    }

    pub fn to_outcome(self, sec_vals: &SecValTable) -> PerfectOutcome {
        let absolute = self.absolute_key1();
        if absolute == i32::from(sec_vals.virt_win_val()) {
            PerfectOutcome::Win {
                steps: self.raw.key2,
            }
        } else if absolute == i32::from(sec_vals.virt_loss_val()) {
            PerfectOutcome::Loss {
                steps: self.raw.key2,
            }
        } else {
            PerfectOutcome::Draw {
                steps: self.raw.key2,
            }
        }
    }

    pub fn to_wdl_steps(self, sec_vals: &SecValTable) -> (i32, i32) {
        self.to_outcome(sec_vals).to_wdl_steps()
    }
}

#[derive(Debug)]
pub struct Database<P> {
    provider: P,
    variant_name: &'static str,
    sec_vals: SecValTable,
    sectors: BTreeMap<SectorId, LoadedSector>,
}

#[derive(Clone, Debug)]
struct LoadedSector {
    value: i16,
    hasher: PerfectHasher,
    file: SectorFile,
}

impl<P: DatabaseProvider> Database<P> {
    pub fn open(provider: P) -> Result<Self, DatabaseError> {
        let name = "std.secval";
        let bytes = provider.read(name)?;
        let text = String::from_utf8(bytes).map_err(|source| DatabaseError::InvalidUtf8 {
            name: name.to_owned(),
            source,
        })?;
        let sec_vals = SecValTable::parse(&text).map_err(|source| DatabaseError::Parse {
            name: name.to_owned(),
            source,
        })?;

        Ok(Self {
            provider,
            variant_name: "std",
            sec_vals,
            sectors: BTreeMap::new(),
        })
    }

    pub fn evaluate_raw(
        &mut self,
        query: PerfectQuery,
    ) -> Result<Option<DatabaseEval>, DatabaseError> {
        if query.only_stone_taking {
            return Ok(None);
        }

        let (id, board) = query.sector_and_board();
        let sector_name = sector_file_name(self.variant_name, id);
        let sector = self.load_sector(id)?;
        let probe = sector.hasher.hash_probe(board);
        let mut raw = sector
            .file
            .eval_at(probe.index)
            .map_err(|source| DatabaseError::Parse {
                name: sector_name.clone(),
                source,
            })?;

        if let RawEvalKind::Symmetry { operation } = raw.kind() {
            let redirected_board = transform48(operation, probe.canonical_board);
            let redirected_index = sector.hasher.direct_hash_index(redirected_board);
            raw = sector
                .file
                .eval_at(redirected_index)
                .map_err(|source| DatabaseError::Parse {
                    name: sector_name.clone(),
                    source,
                })?;
            assert!(
                !matches!(raw.kind(), RawEvalKind::Symmetry { .. }),
                "Perfect DB symmetry redirects must resolve to a concrete eval"
            );
        }

        Ok(Some(DatabaseEval {
            raw,
            sector_value: sector.value,
        }))
    }

    pub fn evaluate(&mut self, query: PerfectQuery) -> Result<Option<(i32, i32)>, DatabaseError> {
        Ok(self
            .evaluate_outcome(query)?
            .map(PerfectOutcome::to_wdl_steps))
    }

    pub fn evaluate_outcome(
        &mut self,
        query: PerfectQuery,
    ) -> Result<Option<PerfectOutcome>, DatabaseError> {
        Ok(self
            .evaluate_raw(query)?
            .map(|eval| eval.to_outcome(&self.sec_vals)))
    }

    fn load_sector(&mut self, id: SectorId) -> Result<&LoadedSector, DatabaseError> {
        if !self.sectors.contains_key(&id) {
            let value = self
                .sec_vals
                .value(id)
                .ok_or(DatabaseError::MissingSectorValue { id })?;
            let hasher = PerfectHasher::new(id.white_on_board, id.black_on_board);
            let name = sector_file_name(self.variant_name, id);
            let bytes = self.provider.read(&name)?;
            let file = SectorFile::parse(&bytes, hasher.hash_count()).map_err(|source| {
                DatabaseError::Parse {
                    name: name.clone(),
                    source,
                }
            })?;
            self.sectors.insert(
                id,
                LoadedSector {
                    value,
                    hasher,
                    file,
                },
            );
        }

        Ok(self
            .sectors
            .get(&id)
            .expect("sector must be loaded after insertion"))
    }
}

fn sector_file_name(variant_name: &str, id: SectorId) -> String {
    format!(
        "{variant_name}_{}_{}_{}_{}.sec2",
        id.white_on_board, id.black_on_board, id.white_in_hand, id.black_in_hand
    )
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use super::*;

    fn asset_root() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../src/ui/flutter_app/assets/databases")
    }

    #[test]
    fn evaluates_empty_board_from_assets() {
        let mut db = Database::open(FileDatabaseProvider::new(asset_root())).unwrap();
        let query = PerfectQuery::new(0, 0, 9, 9, 0, false);
        let eval = db.evaluate_raw(query).unwrap().unwrap();

        assert_eq!(eval.raw, RawEval::new(-21, 2));
        assert_eq!(eval.sector_value, 21);
        assert_eq!(eval.absolute_key1(), 0);
        assert_eq!(db.evaluate(query).unwrap(), Some((0, 2)));
    }

    #[test]
    fn evaluates_black_to_move_after_a4_from_assets() {
        let mut db = Database::open(FileDatabaseProvider::new(asset_root())).unwrap();
        let query = PerfectQuery::new(1, 0, 8, 9, 1, false);
        let eval = db.evaluate_raw(query).unwrap().unwrap();

        assert_eq!(eval.raw, RawEval::new(18, 1));
        assert_eq!(eval.sector_value, -18);
        assert_eq!(eval.absolute_key1(), 0);
        assert_eq!(db.evaluate(query).unwrap(), Some((0, 1)));
    }

    #[test]
    fn resolves_symmetry_redirect_from_assets() {
        let mut db = Database::open(FileDatabaseProvider::new(asset_root())).unwrap();
        let query = PerfectQuery::new(0, 1 << 23, 9, 8, 0, false);
        let eval = db.evaluate_raw(query).unwrap().unwrap();

        assert_eq!(eval.raw.kind(), RawEvalKind::Value);
        assert_eq!(eval.raw, RawEval::new(18, 1));
        assert_eq!(eval.sector_value, -18);
        assert_eq!(eval.absolute_key1(), 0);
        assert_eq!(db.evaluate(query).unwrap(), Some((0, 1)));
    }

    #[test]
    fn skips_stone_taking_subpositions() {
        let mut db = Database::open(FileDatabaseProvider::new(asset_root())).unwrap();
        let query = PerfectQuery::new(1, 0, 8, 9, 1, true);
        assert_eq!(db.evaluate_raw(query).unwrap(), None);
    }

    #[test]
    fn perfect_outcome_comparison_matches_cxx_direction() {
        assert_eq!(
            PerfectOutcome::Win { steps: 1 }.strict_cmp(PerfectOutcome::Win { steps: 3 }),
            std::cmp::Ordering::Greater
        );
        assert_eq!(
            PerfectOutcome::Loss { steps: 5 }.strict_cmp(PerfectOutcome::Loss { steps: 2 }),
            std::cmp::Ordering::Greater
        );
        assert_eq!(
            PerfectOutcome::Draw { steps: 1 }.strict_cmp(PerfectOutcome::Draw { steps: 9 }),
            std::cmp::Ordering::Equal
        );
        assert_eq!(
            PerfectOutcome::Win { steps: 8 }.strict_cmp(PerfectOutcome::Draw { steps: 0 }),
            std::cmp::Ordering::Greater
        );
    }
}
