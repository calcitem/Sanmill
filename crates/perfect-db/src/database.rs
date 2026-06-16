// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

//! Rust-native Perfect Database loader prototype.
//!
//! This layer combines the byte parser and perfect-index hasher without
//! depending on the optional C++ oracle. It is deliberately provider-based so
//! native files and future Web asset bytes can share the same parser and
//! indexing code.

use std::cmp::Ordering;
use std::collections::BTreeMap;
use std::fmt;
use std::io;
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

pub struct BoxDatabaseProvider {
    inner: Box<dyn DatabaseProvider + Send + Sync>,
}

impl BoxDatabaseProvider {
    pub fn new(provider: impl DatabaseProvider + Send + Sync + 'static) -> Self {
        Self {
            inner: Box::new(provider),
        }
    }
}

impl fmt::Debug for BoxDatabaseProvider {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("BoxDatabaseProvider")
            .finish_non_exhaustive()
    }
}

impl DatabaseProvider for BoxDatabaseProvider {
    fn read(&self, name: &str) -> Result<Vec<u8>, DatabaseError> {
        self.inner.read(name)
    }
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

#[derive(Clone, Debug, Default)]
pub struct MemoryDatabaseProvider {
    files: BTreeMap<String, Vec<u8>>,
}

impl MemoryDatabaseProvider {
    pub fn from_files<I, N, B>(files: I) -> Self
    where
        I: IntoIterator<Item = (N, B)>,
        N: Into<String>,
        B: Into<Vec<u8>>,
    {
        let mut provider = Self::default();
        for (name, bytes) in files {
            provider.insert(name, bytes);
        }
        provider
    }

    pub fn insert(&mut self, name: impl Into<String>, bytes: impl Into<Vec<u8>>) {
        let name = name.into();
        assert!(
            !self.files.contains_key(&name),
            "Perfect DB memory provider file names must be unique"
        );
        self.files.insert(name, bytes.into());
    }

    pub fn len(&self) -> usize {
        self.files.len()
    }

    pub fn is_empty(&self) -> bool {
        self.files.is_empty()
    }
}

impl DatabaseProvider for MemoryDatabaseProvider {
    fn read(&self, name: &str) -> Result<Vec<u8>, DatabaseError> {
        self.files
            .get(name)
            .cloned()
            .ok_or_else(|| DatabaseError::Read {
                name: name.to_owned(),
                source: io::Error::new(
                    io::ErrorKind::NotFound,
                    "perfect database memory asset is missing",
                ),
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

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct DatabaseVariant {
    pub name: &'static str,
    pub piece_count: u8,
}

impl DatabaseVariant {
    pub const STANDARD: Self = Self {
        name: "std",
        piece_count: 9,
    };
    pub const LASKER: Self = Self {
        name: "lask",
        piece_count: 10,
    };
    pub const MORABARABA: Self = Self {
        name: "mora",
        piece_count: 12,
    };
    pub const KNOWN: [Self; 3] = [Self::STANDARD, Self::LASKER, Self::MORABARABA];

    fn secval_file_name(self) -> String {
        format!("{}.secval", self.name)
    }

    fn sector_file_name(self, id: SectorId) -> String {
        format!(
            "{}_{}_{}_{}_{}.sec2",
            self.name, id.white_on_board, id.black_on_board, id.white_in_hand, id.black_in_hand
        )
    }

    fn assert_supports(self, query: PerfectQuery) {
        let white_on_board = query.white_bits.count_ones() as u8;
        let black_on_board = query.black_bits.count_ones() as u8;
        assert!(
            query.white_in_hand <= self.piece_count && query.black_in_hand <= self.piece_count,
            "Perfect DB query hand counts must not exceed the database variant piece count"
        );
        assert!(
            white_on_board + query.white_in_hand <= self.piece_count,
            "Perfect DB white on-board plus in-hand count must fit the database variant"
        );
        assert!(
            black_on_board + query.black_in_hand <= self.piece_count,
            "Perfect DB black on-board plus in-hand count must fit the database variant"
        );
    }
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

    /// Mirrors the legacy `pd_evaluate` wrapper, which parses
    /// `gui_eval_elem2::to_string()` into `Value` before converting to WDL.
    /// Best-move ranking should use `to_outcome()` instead.
    pub fn to_public_wdl_steps(self, sec_vals: &SecValTable) -> (i32, i32) {
        let absolute = self.absolute_key1();
        let wdl = if absolute == i32::from(sec_vals.virt_win_val()) {
            1
        } else if absolute == 0 {
            0
        } else {
            -1
        };
        (wdl, self.raw.key2)
    }
}

#[derive(Debug)]
pub struct Database<P> {
    provider: P,
    variant: DatabaseVariant,
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
        Self::open_variant(provider, DatabaseVariant::STANDARD)
    }

    pub fn open_variant(provider: P, variant: DatabaseVariant) -> Result<Self, DatabaseError> {
        assert!(
            DatabaseVariant::KNOWN.contains(&variant),
            "Perfect DB variant metadata must be one of the known legacy variants"
        );
        let name = variant.secval_file_name();
        let bytes = provider.read(&name)?;
        let text = String::from_utf8(bytes).map_err(|source| DatabaseError::InvalidUtf8 {
            name: name.clone(),
            source,
        })?;
        let sec_vals = SecValTable::parse(&text).map_err(|source| DatabaseError::Parse {
            name: name.clone(),
            source,
        })?;

        Ok(Self {
            provider,
            variant,
            sec_vals,
            sectors: BTreeMap::new(),
        })
    }

    pub fn evaluate_raw(
        &mut self,
        query: PerfectQuery,
    ) -> Result<Option<DatabaseEval>, DatabaseError> {
        self.variant.assert_supports(query);
        if query.only_stone_taking {
            return Ok(None);
        }

        let (id, board) = query.sector_and_board();
        let sector_name = self.variant.sector_file_name(id);
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
            .evaluate_raw(query)?
            .map(|eval| eval.to_public_wdl_steps(&self.sec_vals)))
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
            let name = self.variant.sector_file_name(id);
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

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use super::*;

    fn asset_root() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../src/ui/flutter_app/assets/databases")
    }

    fn memory_provider_for(names: &[&str]) -> MemoryDatabaseProvider {
        let files = names.iter().map(|name| {
            let bytes = std::fs::read(asset_root().join(name)).unwrap();
            ((*name).to_owned(), bytes)
        });
        MemoryDatabaseProvider::from_files(files)
    }

    #[test]
    fn memory_provider_reads_assets_without_filesystem_dependency() {
        let provider = memory_provider_for(&["std.secval", "std_0_0_9_9.sec2"]);
        assert_eq!(provider.len(), 2);

        let mut db = Database::open(provider).unwrap();
        let query = PerfectQuery::new(0, 0, 9, 9, 0, false);
        assert_eq!(db.evaluate(query).unwrap(), Some((0, 2)));
    }

    #[test]
    fn memory_provider_reports_missing_assets() {
        let provider = MemoryDatabaseProvider::from_files([("std.secval", b"0\n".to_vec())]);
        let err = provider.read("std_0_0_9_9.sec2").unwrap_err();
        match err {
            DatabaseError::Read { name, source } => {
                assert_eq!(name, "std_0_0_9_9.sec2");
                assert_eq!(source.kind(), io::ErrorKind::NotFound);
            }
            other => panic!("expected missing memory asset read error, got {other}"),
        }
    }

    #[test]
    #[should_panic(expected = "file names must be unique")]
    fn memory_provider_rejects_duplicate_names() {
        let _ = MemoryDatabaseProvider::from_files([
            ("std.secval", b"0\n".to_vec()),
            ("std.secval", b"1\n".to_vec()),
        ]);
    }

    #[test]
    fn database_variant_metadata_matches_legacy_counts() {
        assert_eq!(DatabaseVariant::STANDARD.name, "std");
        assert_eq!(DatabaseVariant::STANDARD.piece_count, 9);
        assert_eq!(DatabaseVariant::LASKER.name, "lask");
        assert_eq!(DatabaseVariant::LASKER.piece_count, 10);
        assert_eq!(DatabaseVariant::MORABARABA.name, "mora");
        assert_eq!(DatabaseVariant::MORABARABA.piece_count, 12);
    }

    #[test]
    fn missing_non_standard_variant_fails_explicitly() {
        let err = Database::open_variant(
            FileDatabaseProvider::new(asset_root()),
            DatabaseVariant::LASKER,
        )
        .unwrap_err();
        match err {
            DatabaseError::Read { name, .. } => {
                assert!(
                    name.ends_with("lask.secval"),
                    "unexpected missing file: {name}"
                );
            }
            other => panic!("expected missing variant file, got {other}"),
        }
    }

    #[test]
    #[should_panic(expected = "database variant piece count")]
    fn standard_database_rejects_ten_piece_queries() {
        let mut db = Database::open(FileDatabaseProvider::new(asset_root())).unwrap();
        let query = PerfectQuery::new(0, 0, 10, 10, 0, false);
        let _ = db.evaluate_raw(query);
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

    #[test]
    fn public_wdl_steps_match_cxx_string_parser_shape() {
        let sec_vals =
            SecValTable::parse("virt_loss_val: -299\nvirt_win_val: 299\n1\n0 0 9 9  21\n").unwrap();

        assert_eq!(
            DatabaseEval {
                raw: RawEval::new(-21, 2),
                sector_value: 21,
            }
            .to_public_wdl_steps(&sec_vals),
            (0, 2)
        );
        assert_eq!(
            DatabaseEval {
                raw: RawEval::new(-20, -5),
                sector_value: 10,
            }
            .to_public_wdl_steps(&sec_vals),
            (-1, -5)
        );
        assert_eq!(
            DatabaseEval {
                raw: RawEval::new(298, 4),
                sector_value: 1,
            }
            .to_public_wdl_steps(&sec_vals),
            (1, 4)
        );
    }
}
