// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

//! The compact, self-contained "error patch" file format and its runtime
//! lookup/correction API.
//!
//! A patch file is a fixed header (engine fingerprint + a verbatim copy of
//! the mining database variant's `.secval` file) followed by a single
//! zstd-compressed payload of two record groups (see [`PatchFile`]): the
//! sector-grouped, slot-sorted settled-position records that make up the
//! bulk of a patch, and a flat, key-sorted list of mid-removal-position
//! records (see [`MidRemovalRecord`]) -- positions with a mill just formed
//! and a piece still to remove have no `(sector, slot)` of their own (see
//! [`crate::wdl_plane::MID_REMOVAL_KEY_TAG`]), so they cannot live in the
//! sector groups and need their own key-indexed lookup. The embedded
//! `.secval` bytes are what make the file fully self-contained:
//! [`PatchLookup`] bootstraps a [`crate::wdl_plane::WdlPlaneCache`] purely
//! to compute canonical `(sector, symmetry-slot)` keys (a disk-free
//! operation -- see
//! [`crate::wdl_plane::WdlPlaneCache::canonical_key_for_query`]), so a
//! patch never needs the multi-gigabyte `.sec2` sector files it was mined
//! from to be usable at runtime.

use std::io::{self, Read, Write};

use tgf_core::{Action, GameRules, GameStateSnapshot};
use tgf_mill::{MillRules, MillUciCodec, MillVariantOptions};

use crate::database::{DatabaseProvider, DatabaseVariant, MemoryDatabaseProvider};
use crate::wdl_plane::WdlPlaneCache;

const MAGIC: [u8; 4] = *b"SMLP";
/// Version 4 added the per-record trap-steering data (`trap_score_mask` +
/// `optimal_trap_nibbles`) that lets "make traps" rank the proven
/// value-preserving replies without the full database or per-child patch
/// entries.
/// Version 3 added the per-record optimal-set proof (`child_count` +
/// `optimal_mask`) that gates corrections on the chosen move being
/// *provably* value-dropping; version 2 records lack it and would
/// otherwise decode as garbage, so older files are rejected outright.
/// Version 2 added the mid-removal record group (a flat, key-sorted list
/// appended after the sector groups); version 1 files have no such group
/// and are rejected outright rather than silently misparsed, since the
/// payload layout differs from the first byte after the sector groups.
const FORMAT_VERSION: u8 = 4;

/// At most this many of a record's proven-optimal children carry a stored
/// trap score (one 4-bit nibble each in [`PackedRecord::optimal_trap_nibbles`]).
pub const MAX_TRAP_SCORED_CHILDREN: u32 = 16;

/// Rank of `child_index` within the set bits of `trap_score_mask`, or
/// `None` when the child carries no stored trap score. This is the single
/// index-space definition shared by the packer, the runtime, and tests:
/// bit `k` of the mask refers to the `k`-th smallest distinct child
/// canonical key (see [`sorted_distinct_child_keys`]), and nibble `rank`
/// of [`PackedRecord::optimal_trap_nibbles`] belongs to the `rank`-th set
/// bit of the mask.
pub fn trap_rank(trap_score_mask: u64, child_index: usize) -> Option<u8> {
    assert!(child_index < 64, "child index must fit the 64-bit masks");
    if trap_score_mask & (1_u64 << child_index) == 0 {
        return None;
    }
    Some((trap_score_mask & ((1_u64 << child_index) - 1)).count_ones() as u8)
}

/// The 4-bit trap score stored at `rank` (0-based over the set bits of the
/// trap-score mask).
pub fn nibble_at(nibbles: u64, rank: u8) -> u8 {
    assert!(
        u32::from(rank) < MAX_TRAP_SCORED_CHILDREN,
        "trap nibble rank must be below {MAX_TRAP_SCORED_CHILDREN}"
    );
    ((nibbles >> (u32::from(rank) * 4)) & 0xF) as u8
}

/// Widen a 4-bit trap score to the u8 `trap_score` scale. The exact
/// inverse of [`u8_trap_score_to_nibble_for_fusion`] for the `17 * n`
/// image points; used to write severity-0 steering entries' `trap_score`.
pub fn nibble_to_u8(nibble: u8) -> u8 {
    assert!(nibble <= 15, "trap nibble must fit 4 bits, got {nibble}");
    (u16::from(nibble) * 17) as u8
}

/// Quantize a u8 `trap_score` down to the 4-bit fusion scale. `17 * n`
/// round-trips exactly back to `n`, and any *positive* legacy score maps
/// to at least 1 so weak-but-real signals are not erased (this is why a
/// plain `>> 4` bit shift is forbidden here: `16 >> 4 == 1` but a score of
/// 16 must survive as 1 via `max(1, 16 / 17)` too -- the two disagree on
/// other values such as `33`).
pub fn u8_trap_score_to_nibble_for_fusion(score: u8) -> u8 {
    if score == 0 { 0 } else { (score / 17).max(1) }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PackAlgorithm {
    Mtdf,
}

impl PackAlgorithm {
    fn to_byte(self) -> u8 {
        match self {
            Self::Mtdf => 0,
        }
    }

    fn from_byte(byte: u8) -> io::Result<Self> {
        match byte {
            0 => Ok(Self::Mtdf),
            other => Err(invalid_data(format!("unknown algorithm tag {other}"))),
        }
    }
}

/// The exact engine configuration + rule toggles the mining run used to
/// judge blunders. A runtime consumer should refuse (or at least warn
/// loudly) if its own configuration disagrees, since a patch mined against
/// one engine configuration is not guaranteed sound for a different one.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct EngineFingerprint {
    pub algorithm: PackAlgorithm,
    pub skill_level: u8,
    pub depth_override: i32,
    pub near_optimal_margin: i32,
    pub consider_mobility: bool,
    pub focus_on_blocking_paths: bool,
    pub draw_on_human_experience: bool,
    pub ai_is_lazy: bool,
    pub top_k: u8,
    pub epsilon: f32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PackedRecord {
    pub slot: u32,
    pub best_child: u64,
    pub severity: u8,
    pub trap_score: u8,
    /// Number of distinct child canonical keys the mined position has (the
    /// length of the sorted, deduped child-key list [`optimal_mask`] is
    /// indexed against). A runtime whose own child enumeration disagrees
    /// must treat the record as not applying -- see
    /// [`PatchLookup::correct_action`].
    ///
    /// [`optimal_mask`]: Self::optimal_mask
    pub child_count: u8,
    /// Bit `i` set means the `i`-th smallest distinct child canonical key
    /// leads to a position that preserves the parent's game-theoretic
    /// value. Corrections only fire for children whose bit is clear (a
    /// *proven* value drop), never merely because the engine picked a
    /// different-but-equally-good move than [`Self::best_child`].
    pub optimal_mask: u64,
    /// Subset of [`Self::optimal_mask`] marking the (at most
    /// [`MAX_TRAP_SCORED_CHILDREN`]) proven value-preserving children that
    /// carry a stored *positive* trap score. The packer selects the top
    /// scorers (score descending, child key ascending on ties) among the
    /// opposite-side optimal children; same-side (pending-removal)
    /// children never enter this mask.
    pub trap_score_mask: u64,
    /// 4-bit trap scores, one nibble per set bit of
    /// [`Self::trap_score_mask`] in [`trap_rank`] order. Values are always
    /// in `1..=15` for masked children (a zero score never enters the
    /// mask).
    pub optimal_trap_nibbles: u64,
}

pub const RECORD_SIZE: usize = 4 + 8 + 1 + 1 + 1 + 8 + 8 + 8;

/// A correction for a mid-removal position (see the module docs): `key` is
/// the full, tagged [`crate::mill::mid_removal_key`] output, not a
/// `(sector, slot)` pair, since these positions have no perfect-database
/// sector of their own.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct MidRemovalRecord {
    pub key: u64,
    pub best_child: u64,
    pub severity: u8,
    pub trap_score: u8,
    /// See [`PackedRecord::child_count`].
    pub child_count: u8,
    /// See [`PackedRecord::optimal_mask`].
    pub optimal_mask: u64,
    /// See [`PackedRecord::trap_score_mask`].
    pub trap_score_mask: u64,
    /// See [`PackedRecord::optimal_trap_nibbles`].
    pub optimal_trap_nibbles: u64,
}

pub const MID_REMOVAL_RECORD_SIZE: usize = 8 + 8 + 1 + 1 + 1 + 8 + 8 + 8;

/// The two record shapes' common fields, as seen by [`PatchLookup`]'s
/// runtime queries -- neither `PackedRecord::slot` nor `MidRemovalRecord::key`
/// (the two groups' respective lookup inputs, already consumed by the time
/// a record is found) nor `severity` (mining/audit-only) has a runtime
/// consumer.
struct Correction {
    best_child: u64,
    trap_score: u8,
    child_count: u8,
    optimal_mask: u64,
    trap_score_mask: u64,
    optimal_trap_nibbles: u64,
}

impl From<PackedRecord> for Correction {
    fn from(record: PackedRecord) -> Self {
        Self {
            best_child: record.best_child,
            trap_score: record.trap_score,
            child_count: record.child_count,
            optimal_mask: record.optimal_mask,
            trap_score_mask: record.trap_score_mask,
            optimal_trap_nibbles: record.optimal_trap_nibbles,
        }
    }
}

impl From<MidRemovalRecord> for Correction {
    fn from(record: MidRemovalRecord) -> Self {
        Self {
            best_child: record.best_child,
            trap_score: record.trap_score,
            child_count: record.child_count,
            optimal_mask: record.optimal_mask,
            trap_score_mask: record.trap_score_mask,
            optimal_trap_nibbles: record.optimal_trap_nibbles,
        }
    }
}

/// Shared read-side validation for the fields both record shapes carry.
/// These are *file format* constraints: violations mean the file was not
/// produced by a correct packer, so the reader must reject it loudly
/// rather than trust masks that index into undefined children.
fn validate_record_fields(
    context: &str,
    child_count: u8,
    optimal_mask: u64,
    trap_score_mask: u64,
    optimal_trap_nibbles: u64,
) -> io::Result<()> {
    if child_count > 64 {
        return Err(invalid_data(format!(
            "{context}: child_count {child_count} exceeds the 64-bit mask space"
        )));
    }
    let allowed = if child_count == 64 {
        u64::MAX
    } else {
        (1_u64 << child_count) - 1
    };
    if optimal_mask & !allowed != 0 {
        return Err(invalid_data(format!(
            "{context}: optimal_mask has bits beyond child_count {child_count}"
        )));
    }
    if trap_score_mask & !optimal_mask != 0 {
        return Err(invalid_data(format!(
            "{context}: trap_score_mask is not a subset of optimal_mask"
        )));
    }
    let scored = trap_score_mask.count_ones();
    if scored > MAX_TRAP_SCORED_CHILDREN {
        return Err(invalid_data(format!(
            "{context}: trap_score_mask marks {scored} children, max is {MAX_TRAP_SCORED_CHILDREN}"
        )));
    }
    if scored < 16 && (optimal_trap_nibbles >> (scored * 4)) != 0 {
        return Err(invalid_data(format!(
            "{context}: optimal_trap_nibbles has data beyond the {scored} masked children"
        )));
    }
    for rank in 0..scored {
        if (optimal_trap_nibbles >> (rank * 4)) & 0xF == 0 {
            return Err(invalid_data(format!(
                "{context}: masked child at rank {rank} has a zero trap nibble \
                 (zero scores never enter trap_score_mask)"
            )));
        }
    }
    Ok(())
}

#[derive(Clone, Debug)]
pub struct SectorGroup {
    pub white_on_board: u8,
    pub black_on_board: u8,
    pub white_in_hand: u8,
    pub black_in_hand: u8,
    /// Sorted by `slot` ascending.
    pub records: Vec<PackedRecord>,
}

pub struct PatchFile {
    pub variant_byte: u8,
    pub fingerprint: EngineFingerprint,
    pub secval_bytes: Vec<u8>,
    pub sectors: Vec<SectorGroup>,
    /// Sorted by `key` ascending, for [`PatchFile::lookup_mid_removal`]'s
    /// binary search.
    pub mid_removal_records: Vec<MidRemovalRecord>,
}

fn invalid_data(message: String) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, message)
}

fn write_u8(out: &mut Vec<u8>, value: u8) {
    out.push(value);
}
fn write_bool(out: &mut Vec<u8>, value: bool) {
    out.push(u8::from(value));
}
fn write_i32(out: &mut Vec<u8>, value: i32) {
    out.extend_from_slice(&value.to_le_bytes());
}
fn write_u32(out: &mut Vec<u8>, value: u32) {
    out.extend_from_slice(&value.to_le_bytes());
}
fn write_u64(out: &mut Vec<u8>, value: u64) {
    out.extend_from_slice(&value.to_le_bytes());
}

fn read_u8(bytes: &[u8], offset: &mut usize) -> io::Result<u8> {
    let value = *bytes
        .get(*offset)
        .ok_or_else(|| invalid_data("unexpected end of patch file".to_string()))?;
    *offset += 1;
    Ok(value)
}
fn read_bool(bytes: &[u8], offset: &mut usize) -> io::Result<bool> {
    Ok(read_u8(bytes, offset)? != 0)
}
fn read_i32(bytes: &[u8], offset: &mut usize) -> io::Result<i32> {
    let end = *offset + 4;
    let chunk = bytes
        .get(*offset..end)
        .ok_or_else(|| invalid_data("unexpected end of patch file".to_string()))?;
    *offset = end;
    Ok(i32::from_le_bytes(chunk.try_into().expect("4 bytes")))
}
fn read_u32(bytes: &[u8], offset: &mut usize) -> io::Result<u32> {
    let end = *offset + 4;
    let chunk = bytes
        .get(*offset..end)
        .ok_or_else(|| invalid_data("unexpected end of patch file".to_string()))?;
    *offset = end;
    Ok(u32::from_le_bytes(chunk.try_into().expect("4 bytes")))
}
fn read_u64(bytes: &[u8], offset: &mut usize) -> io::Result<u64> {
    let end = *offset + 8;
    let chunk = bytes
        .get(*offset..end)
        .ok_or_else(|| invalid_data("unexpected end of patch file".to_string()))?;
    *offset = end;
    Ok(u64::from_le_bytes(chunk.try_into().expect("8 bytes")))
}

impl PatchFile {
    /// Total records across both the sector groups and the mid-removal
    /// list.
    pub fn entry_count(&self) -> usize {
        self.sector_entry_count() + self.mid_removal_records.len()
    }

    /// Records in the sector groups alone (excludes mid-removal), matching
    /// the header's `entry_count` field, which is a structural checksum
    /// against the sector payload only -- see [`Self::read_from`].
    fn sector_entry_count(&self) -> usize {
        self.sectors.iter().map(|s| s.records.len()).sum()
    }

    fn build_payload(&self) -> Vec<u8> {
        let mut payload = Vec::new();
        write_u32(&mut payload, self.sectors.len() as u32);
        for sector in &self.sectors {
            write_u8(&mut payload, sector.white_on_board);
            write_u8(&mut payload, sector.black_on_board);
            write_u8(&mut payload, sector.white_in_hand);
            write_u8(&mut payload, sector.black_in_hand);
            write_u32(&mut payload, sector.records.len() as u32);
            for record in &sector.records {
                write_u32(&mut payload, record.slot);
                write_u64(&mut payload, record.best_child);
                write_u8(&mut payload, record.severity);
                write_u8(&mut payload, record.trap_score);
                write_u8(&mut payload, record.child_count);
                write_u64(&mut payload, record.optimal_mask);
                write_u64(&mut payload, record.trap_score_mask);
                write_u64(&mut payload, record.optimal_trap_nibbles);
            }
        }
        write_u32(&mut payload, self.mid_removal_records.len() as u32);
        for record in &self.mid_removal_records {
            write_u64(&mut payload, record.key);
            write_u64(&mut payload, record.best_child);
            write_u8(&mut payload, record.severity);
            write_u8(&mut payload, record.trap_score);
            write_u8(&mut payload, record.child_count);
            write_u64(&mut payload, record.optimal_mask);
            write_u64(&mut payload, record.trap_score_mask);
            write_u64(&mut payload, record.optimal_trap_nibbles);
        }
        payload
    }

    /// Serialize header + zstd-compressed payload to `writer`.
    pub fn write_to(&self, writer: &mut impl Write, zstd_level: i32) -> io::Result<()> {
        let payload = self.build_payload();
        let compressed = {
            let mut encoder = zstd::Encoder::new(Vec::new(), zstd_level)?;
            encoder.include_checksum(true)?;
            encoder.write_all(&payload)?;
            encoder.finish()?
        };

        let mut header = Vec::new();
        header.extend_from_slice(&MAGIC);
        write_u8(&mut header, FORMAT_VERSION);
        write_u8(&mut header, self.variant_byte);
        write_u8(&mut header, self.fingerprint.algorithm.to_byte());
        write_u8(&mut header, self.fingerprint.skill_level);
        write_i32(&mut header, self.fingerprint.depth_override);
        write_i32(&mut header, self.fingerprint.near_optimal_margin);
        write_bool(&mut header, self.fingerprint.consider_mobility);
        write_bool(&mut header, self.fingerprint.focus_on_blocking_paths);
        write_bool(&mut header, self.fingerprint.draw_on_human_experience);
        write_bool(&mut header, self.fingerprint.ai_is_lazy);
        write_u8(&mut header, self.fingerprint.top_k);
        write_u32(&mut header, self.fingerprint.epsilon.to_bits());
        write_u32(&mut header, self.secval_bytes.len() as u32);
        header.extend_from_slice(&self.secval_bytes);
        write_u32(&mut header, self.sectors.len() as u32);
        write_u32(&mut header, self.sector_entry_count() as u32);
        write_u32(&mut header, self.mid_removal_records.len() as u32);
        write_u64(&mut header, payload.len() as u64);
        write_u64(&mut header, compressed.len() as u64);

        writer.write_all(&header)?;
        writer.write_all(&compressed)?;
        Ok(())
    }

    pub fn read_from(reader: &mut impl Read) -> io::Result<Self> {
        let mut all = Vec::new();
        reader.read_to_end(&mut all)?;
        let bytes = all.as_slice();
        let mut offset = 0_usize;

        let magic = bytes
            .get(0..4)
            .ok_or_else(|| invalid_data("patch file too short".to_string()))?;
        if magic != MAGIC {
            return Err(invalid_data("not a Sanmill Mill patch file".to_string()));
        }
        offset += 4;
        let format_version = read_u8(bytes, &mut offset)?;
        if format_version != FORMAT_VERSION {
            return Err(invalid_data(format!(
                "unsupported patch format version {format_version}"
            )));
        }
        let variant_byte = read_u8(bytes, &mut offset)?;
        let algorithm = PackAlgorithm::from_byte(read_u8(bytes, &mut offset)?)?;
        let skill_level = read_u8(bytes, &mut offset)?;
        let depth_override = read_i32(bytes, &mut offset)?;
        let near_optimal_margin = read_i32(bytes, &mut offset)?;
        let consider_mobility = read_bool(bytes, &mut offset)?;
        let focus_on_blocking_paths = read_bool(bytes, &mut offset)?;
        let draw_on_human_experience = read_bool(bytes, &mut offset)?;
        let ai_is_lazy = read_bool(bytes, &mut offset)?;
        let top_k = read_u8(bytes, &mut offset)?;
        let epsilon = f32::from_bits(read_u32(bytes, &mut offset)?);
        let secval_len = read_u32(bytes, &mut offset)? as usize;
        let secval_end = offset + secval_len;
        let secval_bytes = bytes
            .get(offset..secval_end)
            .ok_or_else(|| invalid_data("truncated secval block".to_string()))?
            .to_vec();
        offset = secval_end;
        let sector_count = read_u32(bytes, &mut offset)?;
        let entry_count = read_u32(bytes, &mut offset)?;
        let mid_removal_count = read_u32(bytes, &mut offset)?;
        let uncompressed_len = read_u64(bytes, &mut offset)? as usize;
        let compressed_len = read_u64(bytes, &mut offset)? as usize;
        let compressed_end = offset + compressed_len;
        let compressed = bytes
            .get(offset..compressed_end)
            .ok_or_else(|| invalid_data("truncated compressed payload".to_string()))?;
        if compressed_end != bytes.len() {
            return Err(invalid_data(format!(
                "trailing bytes after the compressed payload: {} extra",
                bytes.len() - compressed_end
            )));
        }

        let mut payload = Vec::with_capacity(uncompressed_len);
        zstd::Decoder::new(compressed)?.read_to_end(&mut payload)?;
        if payload.len() != uncompressed_len {
            return Err(invalid_data(format!(
                "decompressed payload length mismatch: expected {uncompressed_len}, got {}",
                payload.len()
            )));
        }

        let mut payload_offset = 0_usize;
        let payload_sector_count = read_u32(&payload, &mut payload_offset)?;
        if payload_sector_count != sector_count {
            return Err(invalid_data(
                "header/payload sector count mismatch".to_string(),
            ));
        }
        let mut sectors = Vec::with_capacity(sector_count as usize);
        let mut total_records = 0_u32;
        let mut previous_sector: Option<(u8, u8, u8, u8)> = None;
        for _ in 0..sector_count {
            let white_on_board = read_u8(&payload, &mut payload_offset)?;
            let black_on_board = read_u8(&payload, &mut payload_offset)?;
            let white_in_hand = read_u8(&payload, &mut payload_offset)?;
            let black_in_hand = read_u8(&payload, &mut payload_offset)?;
            let sector_key = (white_on_board, black_on_board, white_in_hand, black_in_hand);
            if let Some(previous) = previous_sector
                && previous >= sector_key
            {
                return Err(invalid_data(format!(
                    "sector groups out of order: {previous:?} then {sector_key:?}"
                )));
            }
            previous_sector = Some(sector_key);
            let count = read_u32(&payload, &mut payload_offset)?;
            let mut records = Vec::with_capacity(count as usize);
            let mut previous_slot: Option<u32> = None;
            for _ in 0..count {
                let slot = read_u32(&payload, &mut payload_offset)?;
                if let Some(previous) = previous_slot
                    && previous >= slot
                {
                    return Err(invalid_data(format!(
                        "sector {sector_key:?} slots out of order: {previous} then {slot}"
                    )));
                }
                previous_slot = Some(slot);
                let best_child = read_u64(&payload, &mut payload_offset)?;
                let severity = read_u8(&payload, &mut payload_offset)?;
                let trap_score = read_u8(&payload, &mut payload_offset)?;
                let child_count = read_u8(&payload, &mut payload_offset)?;
                let optimal_mask = read_u64(&payload, &mut payload_offset)?;
                let trap_score_mask = read_u64(&payload, &mut payload_offset)?;
                let optimal_trap_nibbles = read_u64(&payload, &mut payload_offset)?;
                validate_record_fields(
                    &format!("sector {sector_key:?} slot {slot}"),
                    child_count,
                    optimal_mask,
                    trap_score_mask,
                    optimal_trap_nibbles,
                )?;
                records.push(PackedRecord {
                    slot,
                    best_child,
                    severity,
                    trap_score,
                    child_count,
                    optimal_mask,
                    trap_score_mask,
                    optimal_trap_nibbles,
                });
            }
            total_records += count;
            sectors.push(SectorGroup {
                white_on_board,
                black_on_board,
                white_in_hand,
                black_in_hand,
                records,
            });
        }
        if total_records != entry_count {
            return Err(invalid_data(
                "header/payload entry count mismatch".to_string(),
            ));
        }

        let payload_mid_removal_count = read_u32(&payload, &mut payload_offset)?;
        if payload_mid_removal_count != mid_removal_count {
            return Err(invalid_data(
                "header/payload mid-removal count mismatch".to_string(),
            ));
        }
        let mut mid_removal_records = Vec::with_capacity(mid_removal_count as usize);
        let mut previous_key: Option<u64> = None;
        for _ in 0..mid_removal_count {
            let key = read_u64(&payload, &mut payload_offset)?;
            if let Some(previous) = previous_key
                && previous >= key
            {
                return Err(invalid_data(format!(
                    "mid-removal keys out of order: {previous:#x} then {key:#x}"
                )));
            }
            previous_key = Some(key);
            let best_child = read_u64(&payload, &mut payload_offset)?;
            let severity = read_u8(&payload, &mut payload_offset)?;
            let trap_score = read_u8(&payload, &mut payload_offset)?;
            let child_count = read_u8(&payload, &mut payload_offset)?;
            let optimal_mask = read_u64(&payload, &mut payload_offset)?;
            let trap_score_mask = read_u64(&payload, &mut payload_offset)?;
            let optimal_trap_nibbles = read_u64(&payload, &mut payload_offset)?;
            validate_record_fields(
                &format!("mid-removal key {key:#x}"),
                child_count,
                optimal_mask,
                trap_score_mask,
                optimal_trap_nibbles,
            )?;
            mid_removal_records.push(MidRemovalRecord {
                key,
                best_child,
                severity,
                trap_score,
                child_count,
                optimal_mask,
                trap_score_mask,
                optimal_trap_nibbles,
            });
        }
        if payload_offset != payload.len() {
            return Err(invalid_data(format!(
                "payload not fully consumed: {} bytes left",
                payload.len() - payload_offset
            )));
        }

        Ok(Self {
            variant_byte,
            fingerprint: EngineFingerprint {
                algorithm,
                skill_level,
                depth_override,
                near_optimal_margin,
                consider_mobility,
                focus_on_blocking_paths,
                draw_on_human_experience,
                ai_is_lazy,
                top_k,
                epsilon,
            },
            secval_bytes,
            sectors,
            mid_removal_records,
        })
    }

    /// Binary search for `(sector, slot)`'s record, if present.
    pub fn lookup(
        &self,
        white_on_board: u8,
        black_on_board: u8,
        white_in_hand: u8,
        black_in_hand: u8,
        slot: u32,
    ) -> Option<PackedRecord> {
        let sector = self
            .sectors
            .binary_search_by(|s| {
                (
                    s.white_on_board,
                    s.black_on_board,
                    s.white_in_hand,
                    s.black_in_hand,
                )
                    .cmp(&(
                        white_on_board,
                        black_on_board,
                        white_in_hand,
                        black_in_hand,
                    ))
            })
            .ok()?;
        let sector = &self.sectors[sector];
        let record = sector
            .records
            .binary_search_by(|r| r.slot.cmp(&slot))
            .ok()?;
        Some(sector.records[record])
    }

    /// Binary search for a mid-removal position's record by its full
    /// tagged key, if present. `key` is expected to already carry
    /// [`crate::wdl_plane::MID_REMOVAL_KEY_TAG`]; callers that dispatch on
    /// the tag bit themselves (as [`PatchLookup`] does) never need to
    /// strip it first, since it is just part of the key's bit pattern.
    pub fn lookup_mid_removal(&self, key: u64) -> Option<MidRemovalRecord> {
        let record = self
            .mid_removal_records
            .binary_search_by(|r| r.key.cmp(&key))
            .ok()?;
        Some(self.mid_removal_records[record])
    }

    pub fn database_variant(&self) -> Option<DatabaseVariant> {
        DatabaseVariant::KNOWN
            .into_iter()
            .find(|variant| variant.piece_count == variant_piece_count(self.variant_byte))
    }
}

fn variant_piece_count(variant_byte: u8) -> u8 {
    match variant_byte {
        1 => 10,
        2 => 12,
        _ => 9,
    }
}

/// Sorted, deduplicated canonical keys of every legal child of `snap`.
///
/// This list is the index space [`PackedRecord::optimal_mask`] is defined
/// against: bit `i` of the mask refers to the `i`-th entry of this exact
/// list. The packer (with the live database's plane cache) and the runtime
/// (with the patch's embedded plane cache) must therefore both go through
/// this one function, and both must pass the *history-free* replica of the
/// position (fresh repetition history, `ply_since_capture == 0`): a child
/// that is terminal has no canonical key and silently drops out of the
/// list, and history-dependent termination (threefold repetition, the
/// `n_move_rule` counter) would otherwise make the two ends disagree about
/// which children exist.
pub fn sorted_distinct_child_keys<P: DatabaseProvider>(
    keys: &mut WdlPlaneCache<P>,
    rules: &MillRules,
    options: &MillVariantOptions,
    snap: &GameStateSnapshot,
) -> Vec<u64> {
    let mut actions = tgf_core::ActionList::<256>::new();
    rules.legal_actions(snap, &mut actions);
    let mut child_keys: Vec<u64> = actions
        .as_slice()
        .iter()
        .filter_map(|&action| {
            let child_snap = rules.apply(snap, action);
            let child_state = MillRules::decode_snapshot(child_snap);
            crate::mill::canonical_key(keys, &child_state, options)
        })
        .collect();
    child_keys.sort_unstable();
    child_keys.dedup();
    child_keys
}

#[allow(dead_code)]
const _: () = assert!(RECORD_SIZE == 39);
#[allow(dead_code)]
const _: () = assert!(MID_REMOVAL_RECORD_SIZE == 43);

/// Runtime-facing wrapper: a parsed [`PatchFile`] plus the (disk-free)
/// canonical-key machinery needed to check and correct a chosen action
/// against it, with no dependency on the multi-gigabyte database the patch
/// was mined from.
pub struct PatchLookup {
    file: PatchFile,
    keys: WdlPlaneCache<MemoryDatabaseProvider>,
}

impl PatchLookup {
    pub fn open(bytes: &[u8]) -> io::Result<Self> {
        let file = PatchFile::read_from(&mut &bytes[..])?;
        let variant = file.database_variant().ok_or_else(|| {
            invalid_data(
                "patch file variant byte does not map to a known Perfect DB variant".to_string(),
            )
        })?;
        let secval_name = format!("{}.secval", variant.name);
        let provider =
            MemoryDatabaseProvider::from_files([(secval_name, file.secval_bytes.clone())]);
        let keys = WdlPlaneCache::new(provider, variant)
            .map_err(|e| invalid_data(format!("failed to bootstrap patch key cache: {e}")))?;
        Ok(Self { file, keys })
    }

    pub fn fingerprint(&self) -> EngineFingerprint {
        self.file.fingerprint
    }

    pub fn entry_count(&self) -> usize {
        self.file.entry_count()
    }

    /// `None` when `options` (the live ruleset) is not the exact rule
    /// "shape" the loaded patch was mined under (see
    /// [`PatchFile::variant_byte`] / [`PatchFile::database_variant`]).
    ///
    /// A patch's canonical keys are plain `(sector, slot)` (or mid-removal
    /// hash) indices with no variant tag of their own: a Lasker or
    /// Morabaraba position can otherwise decode to a key that happens to
    /// collide with an unrelated entry mined under a different variant
    /// (say, std). This is the single choke point both [`Self::correct_action`]
    /// and [`Self::trap_score_for_state`] go through, so it is the one
    /// place that needs to guard against that -- callers do not each need
    /// their own variant check.
    fn canonical_key_for_state(
        &mut self,
        state: &tgf_mill::rules::MillState,
        options: &MillVariantOptions,
    ) -> Option<u64> {
        if DatabaseVariant::from_mill_options(options) != self.file.database_variant() {
            return None;
        }
        crate::mill::canonical_key(&mut self.keys, state, options)
    }

    /// Look up `key`'s correction, if any, dispatching on
    /// [`crate::wdl_plane::MID_REMOVAL_KEY_TAG`] between the sector groups
    /// (settled positions, `(sector, slot)`-addressed) and the mid-removal
    /// list (hash-addressed): the two groups' keys live in disjoint spaces,
    /// so the tag bit alone determines which lookup applies.
    fn lookup_by_key(&self, key: u64) -> Option<Correction> {
        if key & crate::wdl_plane::MID_REMOVAL_KEY_TAG != 0 {
            return self.file.lookup_mid_removal(key).map(Correction::from);
        }
        let (sector_id, slot) = crate::wdl_plane::unpack_canonical_key(key);
        self.file
            .lookup(
                sector_id.white_on_board,
                sector_id.black_on_board,
                sector_id.white_in_hand,
                sector_id.black_in_hand,
                slot as u32,
            )
            .map(Correction::from)
    }

    /// If `snap`'s position has a patch entry and `chosen_action` is
    /// *proven* by the entry's optimal-set mask to drop the position's
    /// game-theoretic value, return the legal action whose resulting child
    /// matches the recorded `best_child` instead. Returns `None` when there
    /// is no patch entry for this position, or -- crucially -- when the
    /// chosen move is itself value-preserving: the engine's own pick among
    /// equally-good moves always stands, even when it differs from
    /// `best_child`. (Earlier format versions hard-overrode any
    /// non-recorded move; measured head-to-head that overrides far more
    /// good moves than blunders and costs real playing strength.)
    ///
    /// Child keys are computed against a *history-free* replica of the
    /// position, not the live snapshot. Patch entries were mined from bare
    /// positions (fresh repetition history, `ply_since_capture == 0`), but
    /// a live game snapshot carries both: the recorded corrective move can
    /// therefore end the live game on the spot -- as a threefold-repetition
    /// draw, or by pushing a live counter that was already close to the
    /// limit over `n_move_rule` -- and a terminal child has no canonical
    /// key, so matching against the live children would silently skip
    /// exactly the recorded reply. (Both observed in `mill arena`: draw
    /// -valued positions whose only safe move happened to also trip one of
    /// these, where the un-sanitized lookup found no match, applied no
    /// correction, and the engine lost.) Termination that is *not*
    /// history-dependent -- material, stalemate -- still terminates the
    /// replica's children, so a genuinely game-ending reply still never
    /// matches.
    pub fn correct_action(
        &mut self,
        rules: &MillRules,
        options: &MillVariantOptions,
        snap: &GameStateSnapshot,
        chosen_action: Action,
    ) -> Option<Action> {
        let state = MillRules::decode_snapshot(*snap);
        let key = self.canonical_key_for_state(&state, options)?;
        let record = self.lookup_by_key(key)?;

        let sanitized_snap = history_free_snapshot(rules, &state);

        // The optimal-set proof is indexed against the packer's sorted
        // distinct child-key list; if the runtime enumeration no longer
        // produces the same list (rules or canonicalization drift since the
        // patch was packed), the proof does not apply to what we are seeing
        // -- fail safe by leaving the move alone.
        let child_keys =
            sorted_distinct_child_keys(&mut self.keys, rules, options, &sanitized_snap);
        if child_keys.len() != usize::from(record.child_count) || child_keys.len() > 64 {
            debug_assert_eq!(
                child_keys.len(),
                usize::from(record.child_count),
                "patch record child count must match the runtime child enumeration"
            );
            return None;
        }

        let chosen_key = {
            let child_snap = rules.apply(&sanitized_snap, chosen_action);
            let child_state = MillRules::decode_snapshot(child_snap);
            self.canonical_key_for_state(&child_state, options)
        }?;
        let chosen_index = child_keys.binary_search(&chosen_key).ok()?;
        if record.optimal_mask & (1_u64 << chosen_index) != 0 {
            // Proven value-preserving (this covers `best_child` itself and
            // every other optimal sibling): nothing to correct.
            return None;
        }

        let mut actions = tgf_core::ActionList::<256>::new();
        rules.legal_actions(snap, &mut actions);
        for &action in actions.as_slice() {
            let child_snap = rules.apply(&sanitized_snap, action);
            let child_state = MillRules::decode_snapshot(child_snap);
            if self.canonical_key_for_state(&child_state, options) == Some(record.best_child) {
                return Some(action);
            }
        }
        None
    }

    /// Trap score of `snap`'s position, if it has a patch entry (used by
    /// "make traps" mode to compare candidate replies' resulting positions).
    pub fn trap_score_for_state(
        &mut self,
        state: &tgf_mill::rules::MillState,
        options: &MillVariantOptions,
    ) -> Option<u8> {
        let key = self.canonical_key_for_state(state, options)?;
        self.lookup_by_key(key).map(|record| record.trap_score)
    }

    /// Database-free "make traps": if `snap`'s position has a patch entry
    /// and `chosen_action` is one of the entry's mask-proven
    /// value-preserving moves, return the sibling optimal action whose
    /// stored trap nibble is *strictly higher* than the chosen move's own
    /// (i.e. hands the opponent the best-known blunder opportunity).
    ///
    /// The baseline of the comparison is `chosen_action` itself: its score
    /// is its stored nibble, or 0 when it carries none. Returns `None` when
    /// the position has no entry, the proof does not apply (child-count
    /// drift, unkeyable chosen child -- **no fallback of any kind here**,
    /// unlike [`Self::trap_score_after_action`]), `chosen_action` is not
    /// proven value-preserving (that is [`Self::correct_action`]'s job, not
    /// a tie-break's), or no proven sibling strictly beats the chosen
    /// move's score -- so this only ever re-orders among moves the patch
    /// proves equally good, and never picks a worse move than the
    /// underlying decision.
    pub fn trap_aware_action(
        &mut self,
        rules: &MillRules,
        options: &MillVariantOptions,
        snap: &GameStateSnapshot,
        chosen_action: Action,
    ) -> Option<Action> {
        let state = MillRules::decode_snapshot(*snap);
        let key = self.canonical_key_for_state(&state, options)?;
        let record = self.lookup_by_key(key)?;
        if record.trap_score_mask == 0 {
            return None;
        }

        let sanitized_snap = history_free_snapshot(rules, &state);
        let child_keys =
            sorted_distinct_child_keys(&mut self.keys, rules, options, &sanitized_snap);
        if child_keys.len() != usize::from(record.child_count) || child_keys.len() > 64 {
            debug_assert_eq!(
                child_keys.len(),
                usize::from(record.child_count),
                "patch record child count must match the runtime child enumeration"
            );
            return None;
        }

        let chosen_key = {
            let child_snap = rules.apply(&sanitized_snap, chosen_action);
            let child_state = MillRules::decode_snapshot(child_snap);
            self.canonical_key_for_state(&child_state, options)
        }?;
        let chosen_index = child_keys.binary_search(&chosen_key).ok()?;
        if record.optimal_mask & (1_u64 << chosen_index) == 0 {
            return None;
        }
        let chosen_score = trap_rank(record.trap_score_mask, chosen_index)
            .map(|rank| nibble_at(record.optimal_trap_nibbles, rank))
            .unwrap_or(0);

        // Ascending child-key scan + strictly-greater comparison: ties keep
        // the earliest (smallest-key) candidate, deterministically.
        let mut best: Option<(u8, u64)> = None;
        for (index, &child_key) in child_keys.iter().enumerate() {
            if child_key == chosen_key {
                continue;
            }
            let Some(rank) = trap_rank(record.trap_score_mask, index) else {
                continue;
            };
            let score = nibble_at(record.optimal_trap_nibbles, rank);
            if score > chosen_score && best.is_none_or(|(best_score, _)| score > best_score) {
                best = Some((score, child_key));
            }
        }
        let (_, best_key) = best?;

        let mut actions = tgf_core::ActionList::<256>::new();
        rules.legal_actions(snap, &mut actions);
        for &action in actions.as_slice() {
            let child_snap = rules.apply(&sanitized_snap, action);
            let child_state = MillRules::decode_snapshot(child_snap);
            if self.canonical_key_for_state(&child_state, options) == Some(best_key) {
                return Some(action);
            }
        }
        None
    }

    /// Trap score (u8 scale) of the position reached by playing `action`
    /// from `snap` -- the single entry point the perfect-database tied-best
    /// tie-break ranks its candidates through.
    ///
    /// Mechanical rules, in order:
    /// 1. Same-side perspective filter: when the reached position's side to
    ///    move is still the mover's (a mill just formed, removal pending),
    ///    the score is 0 on **every** path -- a "trap" whose next decision
    ///    is our own is a self-trap signal, and even the child-entry
    ///    fallback below must not resurrect it.
    /// 2. Parent proof: when `snap` has an entry whose optimal-set proof
    ///    matches the runtime enumeration, the score is the child's stored
    ///    nibble widened to u8 (0 when unscored).
    /// 3. Fallback: when there is no parent entry or its proof does not
    ///    apply (child-count drift / unkeyable child), fall back to the
    ///    reached position's own entry `trap_score`; `None` when that is
    ///    absent too.
    pub fn trap_score_after_action(
        &mut self,
        rules: &MillRules,
        options: &MillVariantOptions,
        snap: &GameStateSnapshot,
        action: Action,
    ) -> Option<u8> {
        let state = MillRules::decode_snapshot(*snap);
        // Variant guard up front (canonical_key_for_state embeds it): a
        // mismatched ruleset must not read anything out of this patch.
        if DatabaseVariant::from_mill_options(options) != self.file.database_variant() {
            return None;
        }

        let sanitized_snap = history_free_snapshot(rules, &state);
        let child_snap = rules.apply(&sanitized_snap, action);
        let child_state = MillRules::decode_snapshot(child_snap);
        if child_state.side_to_move() == state.side_to_move() {
            return Some(0);
        }

        if let Some(parent_key) = self.canonical_key_for_state(&state, options)
            && let Some(record) = self.lookup_by_key(parent_key)
        {
            let child_keys =
                sorted_distinct_child_keys(&mut self.keys, rules, options, &sanitized_snap);
            if child_keys.len() == usize::from(record.child_count)
                && child_keys.len() <= 64
                && let Some(chosen_key) = self.canonical_key_for_state(&child_state, options)
                && let Ok(chosen_index) = child_keys.binary_search(&chosen_key)
            {
                let nibble = trap_rank(record.trap_score_mask, chosen_index)
                    .map(|rank| nibble_at(record.optimal_trap_nibbles, rank))
                    .unwrap_or(0);
                return Some(nibble_to_u8(nibble));
            }
            // Proof drift: fall through to the child-entry fallback below
            // rather than reporting a fabricated 0.
        }

        self.canonical_key_for_state(&child_state, options)
            .and_then(|child_key| self.lookup_by_key(child_key))
            .map(|correction| correction.trap_score)
    }

    #[allow(dead_code)]
    fn debug_encode(&self, action: Action) -> String {
        MillUciCodec::encode_action(action)
    }
}

/// Tie-break selector shared by every perfect-database "make traps" call
/// site (CLI UCI and FRB alike): starting from `baseline` -- which MUST be
/// the move the plain (non-trap-aware) picker would have returned, so the
/// feature degrades to exactly the normal behavior -- switch to a tied
/// sibling only when its trap score is *strictly higher* than the current
/// best. Ties keep the earlier candidate (the baseline first, then tied
/// order), so an all-zero or all-equal score set returns `baseline`
/// unchanged instead of drifting to an arbitrary list position.
pub fn pick_strictly_better_trap_action(
    tied: &[Action],
    baseline: Action,
    mut trap_score_of: impl FnMut(Action) -> Option<u8>,
) -> Action {
    let mut best = baseline;
    let mut best_score = trap_score_of(baseline).unwrap_or(0);
    for &candidate in tied {
        if candidate == best {
            continue;
        }
        let score = trap_score_of(candidate).unwrap_or(0);
        if score > best_score {
            best = candidate;
            best_score = score;
        }
    }
    best
}

/// History-free replica of `state` (fresh repetition history, zeroed
/// `ply_since_capture`) -- the reference frame patch entries are mined in
/// and every proof/score computation must run in. See
/// [`PatchLookup::correct_action`]'s doc comment for why live counters
/// must not leak into child enumeration.
fn history_free_snapshot(
    rules: &MillRules,
    state: &tgf_mill::rules::MillState,
) -> GameStateSnapshot {
    let fen = rules.export_fen(state);
    let mut replica = rules
        .set_from_fen(&fen)
        .expect("a FEN exported from a live state must re-parse");
    replica.reset_ply_since_capture();
    rules.encode_state(replica)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tgf_core::OutcomeKind;
    use tgf_mill::MillRules;

    fn sample_patch() -> PatchFile {
        PatchFile {
            variant_byte: 0,
            fingerprint: EngineFingerprint {
                algorithm: PackAlgorithm::Mtdf,
                skill_level: 30,
                depth_override: 0,
                near_optimal_margin: 0,
                consider_mobility: true,
                focus_on_blocking_paths: false,
                draw_on_human_experience: true,
                ai_is_lazy: false,
                top_k: 3,
                epsilon: 0.15,
            },
            secval_bytes: std::fs::read(
                std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                    .join("../../src/ui/flutter_app/assets/databases/std.secval"),
            )
            .unwrap(),
            sectors: vec![],
            mid_removal_records: vec![],
        }
    }

    /// Build the `(child_count, optimal_mask)` proof for `snap`, marking
    /// exactly `optimal_child_keys` as value-preserving. Mirrors what the
    /// packer derives from the live database.
    fn proof_for_children(
        keys: &mut WdlPlaneCache<MemoryDatabaseProvider>,
        rules: &MillRules,
        options: &MillVariantOptions,
        snap: &GameStateSnapshot,
        optimal_child_keys: &[u64],
    ) -> (u8, u64) {
        let list = sorted_distinct_child_keys(keys, rules, options, snap);
        let mut mask = 0_u64;
        for key in optimal_child_keys {
            let index = list
                .binary_search(key)
                .expect("optimal child key must be among the position's children");
            mask |= 1_u64 << index;
        }
        (
            u8::try_from(list.len()).expect("Mill positions have at most 64 distinct children"),
            mask,
        )
    }

    /// Build `(trap_score_mask, optimal_trap_nibbles)` for `snap`, storing
    /// the given `(child_key, nibble)` scores. Mirrors the packer's
    /// encoding: mask bits index the sorted distinct child-key list,
    /// nibbles are laid out in [`trap_rank`] order.
    fn trap_fields_for_children(
        keys: &mut WdlPlaneCache<MemoryDatabaseProvider>,
        rules: &MillRules,
        options: &MillVariantOptions,
        snap: &GameStateSnapshot,
        scored: &[(u64, u8)],
    ) -> (u64, u64) {
        let list = sorted_distinct_child_keys(keys, rules, options, snap);
        let mut mask = 0_u64;
        for (key, nibble) in scored {
            assert!((1..=15).contains(nibble), "test scores must be 1..=15");
            let index = list
                .binary_search(key)
                .expect("scored child key must be among the position's children");
            mask |= 1_u64 << index;
        }
        let mut nibbles = 0_u64;
        for (key, nibble) in scored {
            let index = list.binary_search(key).expect("checked above");
            let rank = trap_rank(mask, index).expect("bit set above");
            nibbles |= u64::from(*nibble) << (u32::from(rank) * 4);
        }
        (mask, nibbles)
    }

    #[test]
    fn round_trips_through_bytes() {
        let mut patch = sample_patch();
        patch.sectors = vec![SectorGroup {
            white_on_board: 3,
            black_on_board: 3,
            white_in_hand: 0,
            black_in_hand: 0,
            records: vec![PackedRecord {
                slot: 7,
                best_child: 42,
                severity: 2,
                trap_score: 9,
                child_count: 5,
                optimal_mask: 0b1_0110,
                trap_score_mask: 0b0_0110,
                optimal_trap_nibbles: 0x73,
            }],
        }];
        patch.mid_removal_records = vec![MidRemovalRecord {
            key: crate::wdl_plane::MID_REMOVAL_KEY_TAG | 3,
            best_child: 41,
            severity: 1,
            trap_score: 8,
            child_count: 3,
            optimal_mask: 0b011,
            trap_score_mask: 0b001,
            optimal_trap_nibbles: 0x5,
        }];
        let mut buf = Vec::new();
        patch.write_to(&mut buf, 3).unwrap();
        let restored = PatchFile::read_from(&mut buf.as_slice()).unwrap();
        assert_eq!(restored.fingerprint, patch.fingerprint);
        assert_eq!(restored.secval_bytes, patch.secval_bytes);
        assert_eq!(restored.sectors[0].records, patch.sectors[0].records);
        assert_eq!(restored.mid_removal_records, patch.mid_removal_records);
    }

    #[test]
    fn patch_lookup_opens_without_any_external_database_file() {
        // The whole point of embedding secval bytes: this must succeed even
        // though no `.secval` / `.sec2` file exists anywhere near `bytes`.
        let patch = sample_patch();
        let mut buf = Vec::new();
        patch.write_to(&mut buf, 3).unwrap();
        let lookup = PatchLookup::open(&buf).unwrap();
        assert_eq!(lookup.entry_count(), 0);
    }

    #[test]
    fn correct_action_only_fires_on_a_proven_value_drop() {
        let options = MillVariantOptions::default();
        let rules = MillRules::new(options.clone());
        let snap = rules.encode_state(MillRules::decode_snapshot(rules.initial_state(&[])));

        let provider = MemoryDatabaseProvider::from_files([(
            "std.secval".to_string(),
            std::fs::read(
                std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                    .join("../../src/ui/flutter_app/assets/databases/std.secval"),
            )
            .unwrap(),
        )]);
        let mut keys = WdlPlaneCache::new(provider, DatabaseVariant::STANDARD).unwrap();

        // Pick three legal actions with pairwise distinct child keys: the
        // recorded reply, a different-but-also-optimal sibling, and a
        // "proven bad" one.
        let mut actions = tgf_core::ActionList::<256>::new();
        rules.legal_actions(&snap, &mut actions);
        let child_key_of =
            |keys: &mut WdlPlaneCache<MemoryDatabaseProvider>, action: Action| -> u64 {
                let child_state = MillRules::decode_snapshot(rules.apply(&snap, action));
                crate::mill::canonical_key(keys, &child_state, &options)
                    .expect("startpos children must have canonical keys")
            };
        let good_action = actions.as_slice()[0];
        let good_key = child_key_of(&mut keys, good_action);
        let sibling_action = actions
            .as_slice()
            .iter()
            .copied()
            .find(|&a| child_key_of(&mut keys, a) != good_key)
            .expect("startpos must have at least two distinct child keys");
        let sibling_key = child_key_of(&mut keys, sibling_action);
        let bad_action = actions
            .as_slice()
            .iter()
            .copied()
            .find(|&a| {
                let k = child_key_of(&mut keys, a);
                k != good_key && k != sibling_key
            })
            .expect("startpos must have at least three distinct child keys");

        let root_state = MillRules::decode_snapshot(snap);
        let root_key = crate::mill::canonical_key(&mut keys, &root_state, &options).unwrap();
        let (root_sector, root_slot) = crate::wdl_plane::unpack_canonical_key(root_key);

        let (child_count, optimal_mask) =
            proof_for_children(&mut keys, &rules, &options, &snap, &[good_key, sibling_key]);

        let patch = PatchFile {
            variant_byte: 0,
            fingerprint: sample_patch().fingerprint,
            secval_bytes: sample_patch().secval_bytes,
            sectors: vec![SectorGroup {
                white_on_board: root_sector.white_on_board,
                black_on_board: root_sector.black_on_board,
                white_in_hand: root_sector.white_in_hand,
                black_in_hand: root_sector.black_in_hand,
                records: vec![PackedRecord {
                    slot: root_slot as u32,
                    best_child: good_key,
                    severity: 1,
                    trap_score: 100,
                    child_count,
                    optimal_mask,
                    trap_score_mask: 0,
                    optimal_trap_nibbles: 0,
                }],
            }],
            mid_removal_records: vec![],
        };
        let mut buf = Vec::new();
        patch.write_to(&mut buf, 3).unwrap();
        let mut lookup = PatchLookup::open(&buf).unwrap();

        assert_eq!(
            lookup.correct_action(&rules, &options, &snap, good_action),
            None,
            "the recorded reply itself must not be corrected"
        );
        assert_eq!(
            lookup.correct_action(&rules, &options, &snap, sibling_action),
            None,
            "a different-but-proven-optimal sibling must be left alone -- \
             corrections only fire on a proven value drop"
        );
        assert_eq!(
            lookup.correct_action(&rules, &options, &snap, bad_action),
            Some(good_action),
            "a proven value-dropping action must be corrected to the recorded reply"
        );
    }

    /// A record whose `child_count` no longer matches the runtime child
    /// enumeration (canonicalization / rules drift since packing) must be
    /// ignored rather than trusted, since its mask indexes a different
    /// child list than the one the runtime sees.
    #[test]
    fn correct_action_ignores_a_record_with_a_stale_child_count() {
        let options = MillVariantOptions::default();
        let rules = MillRules::new(options.clone());
        let snap = rules.encode_state(MillRules::decode_snapshot(rules.initial_state(&[])));

        let provider = MemoryDatabaseProvider::from_files([(
            "std.secval".to_string(),
            sample_patch().secval_bytes,
        )]);
        let mut keys = WdlPlaneCache::new(provider, DatabaseVariant::STANDARD).unwrap();

        let mut actions = tgf_core::ActionList::<256>::new();
        rules.legal_actions(&snap, &mut actions);
        let good_action = actions.as_slice()[0];
        let good_state = MillRules::decode_snapshot(rules.apply(&snap, good_action));
        let good_key = crate::mill::canonical_key(&mut keys, &good_state, &options).unwrap();
        let bad_action = actions
            .as_slice()
            .iter()
            .copied()
            .find(|&a| {
                let s = MillRules::decode_snapshot(rules.apply(&snap, a));
                crate::mill::canonical_key(&mut keys, &s, &options) != Some(good_key)
            })
            .expect("startpos must have at least two distinct child keys");

        let root_state = MillRules::decode_snapshot(snap);
        let root_key = crate::mill::canonical_key(&mut keys, &root_state, &options).unwrap();
        let (root_sector, root_slot) = crate::wdl_plane::unpack_canonical_key(root_key);
        let (true_count, _) = proof_for_children(&mut keys, &rules, &options, &snap, &[good_key]);

        let patch = PatchFile {
            variant_byte: 0,
            fingerprint: sample_patch().fingerprint,
            secval_bytes: sample_patch().secval_bytes,
            sectors: vec![SectorGroup {
                white_on_board: root_sector.white_on_board,
                black_on_board: root_sector.black_on_board,
                white_in_hand: root_sector.white_in_hand,
                black_in_hand: root_sector.black_in_hand,
                records: vec![PackedRecord {
                    slot: root_slot as u32,
                    best_child: good_key,
                    severity: 1,
                    trap_score: 100,
                    child_count: true_count + 1,
                    optimal_mask: 0,
                    trap_score_mask: 0,
                    optimal_trap_nibbles: 0,
                }],
            }],
            mid_removal_records: vec![],
        };
        let mut buf = Vec::new();
        patch.write_to(&mut buf, 3).unwrap();
        let mut lookup = PatchLookup::open(&buf).unwrap();

        // Would be "corrected" under a trusting reader; the count guard must
        // reject the stale proof instead. Debug builds assert on the drift,
        // so exercise the graceful path in release builds only.
        if cfg!(debug_assertions) {
            let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                lookup.correct_action(&rules, &options, &snap, bad_action)
            }));
            assert!(
                result.is_err(),
                "debug builds must surface child-count drift loudly"
            );
        } else {
            assert_eq!(
                lookup.correct_action(&rules, &options, &snap, bad_action),
                None
            );
        }
    }

    /// Database-free "make traps" (v4): the pick must move to the sibling
    /// whose *stored nibble* is strictly higher than the chosen move's,
    /// stay put when the chosen move already is that sibling, refuse to
    /// touch a move that is not proven value-preserving, and never consult
    /// child entries (the sibling's own entry carries a deliberately
    /// contradictory `trap_score` to prove the nibbles are the source).
    #[test]
    fn trap_aware_action_reorders_only_among_proven_optimal_children() {
        let options = MillVariantOptions::default();
        let rules = MillRules::new(options.clone());
        let snap = rules.encode_state(MillRules::decode_snapshot(rules.initial_state(&[])));

        let provider = MemoryDatabaseProvider::from_files([(
            "std.secval".to_string(),
            sample_patch().secval_bytes,
        )]);
        let mut keys = WdlPlaneCache::new(provider, DatabaseVariant::STANDARD).unwrap();

        let mut actions = tgf_core::ActionList::<256>::new();
        rules.legal_actions(&snap, &mut actions);
        let child_key_of =
            |keys: &mut WdlPlaneCache<MemoryDatabaseProvider>, action: Action| -> u64 {
                let child_state = MillRules::decode_snapshot(rules.apply(&snap, action));
                crate::mill::canonical_key(keys, &child_state, &options)
                    .expect("startpos children must have canonical keys")
            };
        let good_action = actions.as_slice()[0];
        let good_key = child_key_of(&mut keys, good_action);
        let sibling_action = actions
            .as_slice()
            .iter()
            .copied()
            .find(|&a| child_key_of(&mut keys, a) != good_key)
            .expect("startpos must have at least two distinct child keys");
        let sibling_key = child_key_of(&mut keys, sibling_action);
        let bad_action = actions
            .as_slice()
            .iter()
            .copied()
            .find(|&a| {
                let k = child_key_of(&mut keys, a);
                k != good_key && k != sibling_key
            })
            .expect("startpos must have at least three distinct child keys");

        let root_state = MillRules::decode_snapshot(snap);
        let root_key = crate::mill::canonical_key(&mut keys, &root_state, &options).unwrap();
        let (root_sector, root_slot) = crate::wdl_plane::unpack_canonical_key(root_key);
        let (child_count, optimal_mask) =
            proof_for_children(&mut keys, &rules, &options, &snap, &[good_key, sibling_key]);
        // Only the sibling carries a stored (positive) trap nibble; the
        // chosen `good` move stays unscored (score 0).
        let (trap_score_mask, optimal_trap_nibbles) =
            trap_fields_for_children(&mut keys, &rules, &options, &snap, &[(sibling_key, 13)]);

        // The sibling's own child entry advertises trap_score 0 -- if
        // trap_aware_action wrongly consulted child entries instead of the
        // parent nibbles, the reorder below would not happen.
        let sibling_snap = rules.apply(&snap, sibling_action);
        let (sibling_sector, sibling_slot) = crate::wdl_plane::unpack_canonical_key(sibling_key);
        let sibling_children =
            sorted_distinct_child_keys(&mut keys, &rules, &options, &sibling_snap);
        let (sibling_child_count, sibling_mask) = proof_for_children(
            &mut keys,
            &rules,
            &options,
            &sibling_snap,
            &[sibling_children[0]],
        );

        let mut sectors = vec![
            SectorGroup {
                white_on_board: root_sector.white_on_board,
                black_on_board: root_sector.black_on_board,
                white_in_hand: root_sector.white_in_hand,
                black_in_hand: root_sector.black_in_hand,
                records: vec![PackedRecord {
                    slot: root_slot as u32,
                    best_child: good_key,
                    severity: 1,
                    trap_score: 100,
                    child_count,
                    optimal_mask,
                    trap_score_mask,
                    optimal_trap_nibbles,
                }],
            },
            SectorGroup {
                white_on_board: sibling_sector.white_on_board,
                black_on_board: sibling_sector.black_on_board,
                white_in_hand: sibling_sector.white_in_hand,
                black_in_hand: sibling_sector.black_in_hand,
                records: vec![PackedRecord {
                    slot: sibling_slot as u32,
                    best_child: sibling_children[0],
                    severity: 1,
                    trap_score: 0,
                    child_count: sibling_child_count,
                    optimal_mask: sibling_mask,
                    trap_score_mask: 0,
                    optimal_trap_nibbles: 0,
                }],
            },
        ];
        sectors.sort_by_key(|s| {
            (
                s.white_on_board,
                s.black_on_board,
                s.white_in_hand,
                s.black_in_hand,
            )
        });
        let patch = PatchFile {
            variant_byte: 0,
            fingerprint: sample_patch().fingerprint,
            secval_bytes: sample_patch().secval_bytes,
            sectors,
            mid_removal_records: vec![],
        };
        let mut buf = Vec::new();
        patch.write_to(&mut buf, 3).unwrap();
        let mut lookup = PatchLookup::open(&buf).unwrap();

        let replacement = lookup
            .trap_aware_action(&rules, &options, &snap, good_action)
            .expect("a strictly-higher-nibble optimal sibling must be preferred");
        let replacement_key = child_key_of(&mut keys, replacement);
        assert_eq!(
            replacement_key, sibling_key,
            "the pick must land on the nibble-scored sibling"
        );
        assert_eq!(
            lookup.trap_aware_action(&rules, &options, &snap, sibling_action),
            None,
            "the trap-max move itself must stay put"
        );
        assert_eq!(
            lookup.trap_aware_action(&rules, &options, &snap, bad_action),
            None,
            "a move that is not proven value-preserving must not be touched here"
        );
    }

    /// `trap_score_after_action`'s branch table: parent nibbles win when
    /// the proof applies (masked child -> widened nibble, unmasked ->
    /// `Some(0)` -- including non-optimal children), same-side children are
    /// 0 on every path, proof drift falls back to the child entry, and
    /// `None` only means "no information anywhere".
    #[test]
    fn trap_score_after_action_follows_the_branch_table() {
        let options = MillVariantOptions::default();
        let rules = MillRules::new(options.clone());
        let snap = rules.encode_state(MillRules::decode_snapshot(rules.initial_state(&[])));

        let provider = MemoryDatabaseProvider::from_files([(
            "std.secval".to_string(),
            sample_patch().secval_bytes,
        )]);
        let mut keys = WdlPlaneCache::new(provider, DatabaseVariant::STANDARD).unwrap();

        let mut actions = tgf_core::ActionList::<256>::new();
        rules.legal_actions(&snap, &mut actions);
        let child_key_of =
            |keys: &mut WdlPlaneCache<MemoryDatabaseProvider>, action: Action| -> u64 {
                let child_state = MillRules::decode_snapshot(rules.apply(&snap, action));
                crate::mill::canonical_key(keys, &child_state, &options)
                    .expect("startpos children must have canonical keys")
            };
        let scored_action = actions.as_slice()[0];
        let scored_key = child_key_of(&mut keys, scored_action);
        let unscored_action = actions
            .as_slice()
            .iter()
            .copied()
            .find(|&a| child_key_of(&mut keys, a) != scored_key)
            .expect("startpos must have at least two distinct child keys");
        let unscored_key = child_key_of(&mut keys, unscored_action);

        let root_state = MillRules::decode_snapshot(snap);
        let root_key = crate::mill::canonical_key(&mut keys, &root_state, &options).unwrap();
        let (root_sector, root_slot) = crate::wdl_plane::unpack_canonical_key(root_key);
        let (child_count, optimal_mask) =
            proof_for_children(&mut keys, &rules, &options, &snap, &[scored_key]);
        let (trap_score_mask, optimal_trap_nibbles) =
            trap_fields_for_children(&mut keys, &rules, &options, &snap, &[(scored_key, 9)]);

        // The unscored child's own position carries an entry with a large
        // trap_score: with a VALID parent proof it must be ignored (the
        // parent says 0), and with a BROKEN parent proof it must be the
        // fallback answer.
        let unscored_snap = rules.apply(&snap, unscored_action);
        let (unscored_sector, unscored_slot) = crate::wdl_plane::unpack_canonical_key(unscored_key);
        let unscored_children =
            sorted_distinct_child_keys(&mut keys, &rules, &options, &unscored_snap);
        let (unscored_child_count, unscored_mask) = proof_for_children(
            &mut keys,
            &rules,
            &options,
            &unscored_snap,
            &[unscored_children[0]],
        );
        let child_entry = |sector: crate::file_format::SectorId, slot: u32| SectorGroup {
            white_on_board: sector.white_on_board,
            black_on_board: sector.black_on_board,
            white_in_hand: sector.white_in_hand,
            black_in_hand: sector.black_in_hand,
            records: vec![PackedRecord {
                slot,
                best_child: unscored_children[0],
                severity: 1,
                trap_score: 200,
                child_count: unscored_child_count,
                optimal_mask: unscored_mask,
                trap_score_mask: 0,
                optimal_trap_nibbles: 0,
            }],
        };

        let build = |parent_child_count: u8| -> PatchLookup {
            let mut sectors = vec![
                SectorGroup {
                    white_on_board: root_sector.white_on_board,
                    black_on_board: root_sector.black_on_board,
                    white_in_hand: root_sector.white_in_hand,
                    black_in_hand: root_sector.black_in_hand,
                    records: vec![PackedRecord {
                        slot: root_slot as u32,
                        best_child: scored_key,
                        severity: 1,
                        trap_score: 100,
                        child_count: parent_child_count,
                        optimal_mask,
                        trap_score_mask,
                        optimal_trap_nibbles,
                    }],
                },
                child_entry(unscored_sector, unscored_slot as u32),
            ];
            sectors.sort_by_key(|s| {
                (
                    s.white_on_board,
                    s.black_on_board,
                    s.white_in_hand,
                    s.black_in_hand,
                )
            });
            let patch = PatchFile {
                variant_byte: 0,
                fingerprint: sample_patch().fingerprint,
                secval_bytes: sample_patch().secval_bytes,
                sectors,
                mid_removal_records: vec![],
            };
            let mut buf = Vec::new();
            patch.write_to(&mut buf, 3).unwrap();
            PatchLookup::open(&buf).unwrap()
        };

        // Valid parent proof: masked child reads its widened nibble, the
        // unmasked (here even non-optimal) child reads Some(0) -- the
        // child's own 200-score entry must NOT leak through.
        let mut lookup = build(child_count);
        assert_eq!(
            lookup.trap_score_after_action(&rules, &options, &snap, scored_action),
            Some(nibble_to_u8(9)),
        );
        assert_eq!(
            lookup.trap_score_after_action(&rules, &options, &snap, unscored_action),
            Some(0),
        );

        // Broken parent proof (stale child_count): fall back to the child
        // entry's own trap_score.
        let mut lookup = build(child_count + 1);
        assert_eq!(
            lookup.trap_score_after_action(&rules, &options, &snap, unscored_action),
            Some(200),
            "proof drift must fall back to the child entry, not fabricate 0"
        );
        assert_eq!(
            lookup.trap_score_after_action(&rules, &options, &snap, scored_action),
            None,
            "no parent proof and no child entry means no information"
        );

        // No entries at all: None.
        let mut buf = Vec::new();
        sample_patch().write_to(&mut buf, 3).unwrap();
        let mut empty = PatchLookup::open(&buf).unwrap();
        assert_eq!(
            empty.trap_score_after_action(&rules, &options, &snap, scored_action),
            None,
        );
    }

    /// A mill-forming move leaves the mover on turn (pending removal): its
    /// trap score is 0 on every path, even when the reached position has
    /// its own mid-removal entry with a large stored score.
    #[test]
    fn trap_score_after_action_zeroes_same_side_children_on_every_path() {
        let options = MillVariantOptions::default();
        let rules = MillRules::new(options.clone());

        // Walk to a position where some legal action forms a mill.
        let mut snap = rules.initial_state(&[]);
        let mut mill_action = None;
        'outer: for _ in 0..40 {
            let mut actions = tgf_core::ActionList::<256>::new();
            rules.legal_actions(&snap, &mut actions);
            for &action in actions.as_slice() {
                let next = MillRules::decode_snapshot(rules.apply(&snap, action));
                let side = next.side_to_move();
                if side >= 0
                    && next.pending_removals()[side as usize] > 0
                    && side == MillRules::decode_snapshot(snap).side_to_move()
                {
                    mill_action = Some(action);
                    break 'outer;
                }
            }
            snap = rules.apply(&snap, actions.as_slice()[0]);
        }
        let mill_action = mill_action.expect("must find a mill-forming move within 40 plies");

        // Give the reached mid-removal position its own entry with a large
        // trap_score; the same-side filter must still report 0.
        let provider = MemoryDatabaseProvider::from_files([(
            "std.secval".to_string(),
            sample_patch().secval_bytes,
        )]);
        let mut keys = WdlPlaneCache::new(provider, DatabaseVariant::STANDARD).unwrap();
        let state = MillRules::decode_snapshot(snap);
        let sanitized = history_free_snapshot(&rules, &state);
        let child_state = MillRules::decode_snapshot(rules.apply(&sanitized, mill_action));
        let child_key = crate::mill::mid_removal_key(&child_state).unwrap();
        let removal_children = sorted_distinct_child_keys(
            &mut keys,
            &rules,
            &options,
            &rules.apply(&sanitized, mill_action),
        );
        let (removal_count, removal_mask) = {
            let mut mask = 0_u64;
            mask |= 1;
            (removal_children.len() as u8, mask)
        };

        let patch = PatchFile {
            variant_byte: 0,
            fingerprint: sample_patch().fingerprint,
            secval_bytes: sample_patch().secval_bytes,
            sectors: vec![],
            mid_removal_records: vec![MidRemovalRecord {
                key: child_key,
                best_child: removal_children[0],
                severity: 1,
                trap_score: 250,
                child_count: removal_count,
                optimal_mask: removal_mask,
                trap_score_mask: 0,
                optimal_trap_nibbles: 0,
            }],
        };
        let mut buf = Vec::new();
        patch.write_to(&mut buf, 3).unwrap();
        let mut lookup = PatchLookup::open(&buf).unwrap();

        assert_eq!(
            lookup.trap_score_after_action(&rules, &options, &snap, mill_action),
            Some(0),
            "a same-side (pending removal) child is a self-trap signal and must read 0"
        );
    }

    /// The shared tied-best selector: the baseline (the plain picker's
    /// move) survives all-`None`, all-zero, and all-tied score sets, and
    /// only a strictly higher score moves the pick -- never `max_by_key`'s
    /// drift to the last maximal candidate.
    #[test]
    fn pick_strictly_better_trap_action_keeps_the_baseline_unless_strictly_beaten() {
        let place = |node: i16| Action {
            kind_tag: 0,
            from_node: -1,
            to_node: node,
            aux: 0,
            payload_bits: 0,
        };
        let a = place(1);
        let b = place(2);
        let c = place(3);
        let tied = [a, b, c];

        // No patch data at all: baseline stays put.
        assert_eq!(
            pick_strictly_better_trap_action(&tied, b, |_| None),
            b,
            "all-None scores must keep the baseline"
        );
        // All zero: baseline stays put.
        assert_eq!(
            pick_strictly_better_trap_action(&tied, b, |_| Some(0)),
            b,
            "all-zero scores must keep the baseline"
        );
        // Everything tied at a positive score: baseline stays put (no
        // strictly-greater candidate exists).
        assert_eq!(
            pick_strictly_better_trap_action(&tied, a, |_| Some(7)),
            a,
            "an all-tied score set must keep the baseline"
        );
        // A single strictly higher candidate wins...
        let score = |action: Action| -> Option<u8> { if action == c { Some(9) } else { Some(3) } };
        assert_eq!(pick_strictly_better_trap_action(&tied, a, score), c);
        // ...and when two candidates share the higher score, the earlier
        // tied-list candidate is kept (deterministic, no drift to the
        // last).
        let score_pair =
            |action: Action| -> Option<u8> { if action == a { Some(1) } else { Some(9) } };
        assert_eq!(
            pick_strictly_better_trap_action(&tied, a, score_pair),
            b,
            "equal improvements must resolve to the earliest tied candidate"
        );
    }

    #[test]
    fn trap_helpers_round_trip_and_reject_out_of_range() {
        assert_eq!(trap_rank(0b0110, 1), Some(0));
        assert_eq!(trap_rank(0b0110, 2), Some(1));
        assert_eq!(trap_rank(0b0110, 0), None);
        assert_eq!(trap_rank(0b0110, 63), None);
        assert_eq!(trap_rank(1_u64 << 63, 63), Some(0));

        let nibbles = 0x73_u64;
        assert_eq!(nibble_at(nibbles, 0), 3);
        assert_eq!(nibble_at(nibbles, 1), 7);
        assert_eq!(nibble_at(nibbles, 15), 0);

        for nibble in 0..=15_u8 {
            assert_eq!(
                u8_trap_score_to_nibble_for_fusion(nibble_to_u8(nibble)),
                nibble,
                "17n must round-trip"
            );
        }
        // Weak legacy signals survive as 1; `>> 4` would disagree (33 >> 4
        // == 2 while 33 / 17 == 1).
        assert_eq!(u8_trap_score_to_nibble_for_fusion(1), 1);
        assert_eq!(u8_trap_score_to_nibble_for_fusion(16), 1);
        assert_eq!(u8_trap_score_to_nibble_for_fusion(33), 1);
        assert_eq!(u8_trap_score_to_nibble_for_fusion(255), 15);
        assert_eq!(u8_trap_score_to_nibble_for_fusion(0), 0);
    }

    #[test]
    #[should_panic(expected = "trap nibble must fit 4 bits")]
    fn nibble_to_u8_asserts_on_out_of_range_input() {
        let _ = nibble_to_u8(16);
    }

    /// Read-side hard validation: every malformed shape must be rejected
    /// with `InvalidData` instead of being trusted. `write_to` serializes
    /// records exactly as given (no sorting, no repair), which is what
    /// makes these constructions reach the reader at all.
    #[test]
    fn read_from_rejects_malformed_records_and_layouts() {
        let write = |patch: &PatchFile| -> Vec<u8> {
            let mut buf = Vec::new();
            patch.write_to(&mut buf, 3).unwrap();
            buf
        };
        let assert_rejected = |patch: &PatchFile, needle: &str| {
            let err = match PatchFile::read_from(&mut write(patch).as_slice()) {
                Ok(_) => panic!("malformed patch must be rejected ({needle})"),
                Err(err) => err,
            };
            assert_eq!(err.kind(), std::io::ErrorKind::InvalidData);
            assert!(
                err.to_string().contains(needle),
                "error `{err}` must mention `{needle}`"
            );
        };
        let record = |child_count: u8,
                      optimal_mask: u64,
                      trap_score_mask: u64,
                      optimal_trap_nibbles: u64| PackedRecord {
            slot: 1,
            best_child: 42,
            severity: 1,
            trap_score: 10,
            child_count,
            optimal_mask,
            trap_score_mask,
            optimal_trap_nibbles,
        };
        let with_record = |r: PackedRecord| -> PatchFile {
            let mut patch = sample_patch();
            patch.sectors = vec![SectorGroup {
                white_on_board: 1,
                black_on_board: 1,
                white_in_hand: 8,
                black_in_hand: 8,
                records: vec![r],
            }];
            patch
        };

        assert_rejected(&with_record(record(65, 0, 0, 0)), "child_count 65");
        assert_rejected(
            &with_record(record(3, 0b1000, 0, 0)),
            "bits beyond child_count",
        );
        assert_rejected(
            &with_record(record(3, 0b001, 0b010, 0x1 << 4)),
            "not a subset",
        );
        {
            // 17 scored children out of 20.
            let optimal = (1_u64 << 20) - 1;
            let trap = (1_u64 << 17) - 1;
            let mut nibbles = 0_u64;
            for rank in 0..16 {
                nibbles |= 1_u64 << (rank * 4);
            }
            assert_rejected(
                &with_record(record(20, optimal, trap, nibbles)),
                "max is 16",
            );
        }
        assert_rejected(&with_record(record(3, 0b011, 0b010, 0)), "zero trap nibble");
        assert_rejected(
            &with_record(record(3, 0b011, 0b010, 0x5 | (0x3 << 4))),
            "beyond the 1 masked children",
        );

        // Sector groups out of order.
        {
            let mut patch = sample_patch();
            let sector = |w: u8| SectorGroup {
                white_on_board: w,
                black_on_board: 1,
                white_in_hand: 8,
                black_in_hand: 8,
                records: vec![record(0, 0, 0, 0)],
            };
            patch.sectors = vec![sector(2), sector(1)];
            assert_rejected(&patch, "sector groups out of order");
        }
        // Slots out of order within a sector.
        {
            let mut patch = sample_patch();
            let mut first = record(0, 0, 0, 0);
            first.slot = 5;
            let mut second = record(0, 0, 0, 0);
            second.slot = 5;
            patch.sectors = vec![SectorGroup {
                white_on_board: 1,
                black_on_board: 1,
                white_in_hand: 8,
                black_in_hand: 8,
                records: vec![first, second],
            }];
            assert_rejected(&patch, "slots out of order");
        }
        // Mid-removal keys out of order.
        {
            let mut patch = sample_patch();
            let mid = |key: u64| MidRemovalRecord {
                key,
                best_child: 42,
                severity: 1,
                trap_score: 10,
                child_count: 0,
                optimal_mask: 0,
                trap_score_mask: 0,
                optimal_trap_nibbles: 0,
            };
            patch.mid_removal_records = vec![
                mid(crate::wdl_plane::MID_REMOVAL_KEY_TAG | 9),
                mid(crate::wdl_plane::MID_REMOVAL_KEY_TAG | 3),
            ];
            assert_rejected(&patch, "mid-removal keys out of order");
        }
        // Trailing bytes after the compressed block.
        {
            let mut buf = write(&sample_patch());
            buf.push(0xAB);
            let err = match PatchFile::read_from(&mut buf.as_slice()) {
                Ok(_) => panic!("trailing bytes must be rejected"),
                Err(err) => err,
            };
            assert_eq!(err.kind(), std::io::ErrorKind::InvalidData);
            assert!(err.to_string().contains("trailing bytes"));
        }
    }

    /// A patch's canonical keys carry no variant tag of their own (they are
    /// plain `(sector, slot)` indices), so nothing stops a Lasker or
    /// Morabaraba position from decoding to a key that happens to match an
    /// entry mined under a different variant. `sample_patch()` is
    /// `variant_byte: 0` (std, 9 pieces); a live Lasker (10-piece,
    /// move-in-placing) game must never be corrected or trap-scored against
    /// it, regardless of what its canonical key happens to be.
    #[test]
    fn correct_action_and_trap_score_return_none_when_options_do_not_match_the_patch_variant() {
        let lasker_options = MillVariantOptions {
            piece_count: 10,
            may_move_in_placing_phase: true,
            ..MillVariantOptions::default()
        };
        assert_eq!(
            DatabaseVariant::from_mill_options(&lasker_options),
            Some(DatabaseVariant::LASKER),
            "test setup must actually exercise a non-std variant"
        );

        let rules = MillRules::new(lasker_options.clone());
        let snap = rules.encode_state(MillRules::decode_snapshot(rules.initial_state(&[])));
        let mut actions = tgf_core::ActionList::<256>::new();
        rules.legal_actions(&snap, &mut actions);
        let action = actions.as_slice()[0];

        let mut buf = Vec::new();
        sample_patch().write_to(&mut buf, 3).unwrap();
        let mut lookup = PatchLookup::open(&buf).unwrap();

        assert_eq!(
            lookup.correct_action(&rules, &lasker_options, &snap, action),
            None,
            "a std-only patch must never attempt to correct a Lasker position"
        );
        let child_state = MillRules::decode_snapshot(rules.apply(&snap, action));
        assert_eq!(
            lookup.trap_score_for_state(&child_state, &lasker_options),
            None,
            "a std-only patch must never trap-score a Lasker position"
        );
    }

    /// Regression for a real missed correction observed in `mill arena`:
    /// when the recorded corrective move would end the *live* game as a
    /// threefold-repetition draw, the live child is terminal, has no
    /// canonical key, and a naive child-key match therefore skips exactly
    /// the recorded reply (and, fail-safe, corrects nothing -- the engine
    /// then played a losing move in a draw-valued position). Child keys
    /// must be computed against a history-free replica of the position so
    /// the repetition move stays matchable; the arena applying it to the
    /// real game then correctly banks the draw.
    #[test]
    fn correct_action_still_matches_a_reply_that_draws_by_live_repetition() {
        let options = MillVariantOptions::default();
        let rules = MillRules::new(options.clone());

        // A quiet 3v4 moving-phase position (black to move) taken from the
        // arena investigation. Build a live snapshot that has already
        // shuttled twice through the same positions, so that re-playing
        // `target_action` creates the third occurrence and ends the live
        // game as a repetition draw.
        let fen = "OOO***@*/@**@****/******@* b m s 3 0 4 0 0 0 -1 -1 -1 -1 0 0 31 ids:nodes";
        let start = rules.encode_state(rules.set_from_fen(fen).unwrap());

        // Deterministic shuttle: black plays A, white plays B, black plays
        // A', white plays B', where A' reverses A and B' reverses B. Find
        // (A, B) such that all four reverses stay legal.
        let find_action = |snap: &tgf_core::GameStateSnapshot, token: &str| -> Option<Action> {
            let mut actions = tgf_core::ActionList::<256>::new();
            rules.legal_actions(snap, &mut actions);
            actions
                .as_slice()
                .iter()
                .copied()
                .find(|&a| MillUciCodec::encode_action(a) == token)
        };
        let reverse_token = |token: &str| -> Option<String> {
            token.split_once('-').map(|(f, t)| format!("{t}-{f}"))
        };

        let mut shuttle: Option<(Action, tgf_core::GameStateSnapshot)> = None;
        let mut black_moves = tgf_core::ActionList::<256>::new();
        rules.legal_actions(&start, &mut black_moves);
        'outer: for &a in black_moves.as_slice() {
            let a_token = MillUciCodec::encode_action(a);
            let Some(a_rev) = reverse_token(&a_token) else {
                continue;
            };
            let after_a = rules.apply(&start, a);
            let mut white_moves = tgf_core::ActionList::<256>::new();
            rules.legal_actions(&after_a, &mut white_moves);
            for &b in white_moves.as_slice() {
                let b_token = MillUciCodec::encode_action(b);
                let Some(b_rev) = reverse_token(&b_token) else {
                    continue;
                };
                let after_b = rules.apply(&after_a, b);
                let Some(a_back) = find_action(&after_b, &a_rev) else {
                    continue;
                };
                let after_a_back = rules.apply(&after_b, a_back);
                let Some(b_back) = find_action(&after_a_back, &b_rev) else {
                    continue;
                };
                let back_to_start = rules.apply(&after_a_back, b_back);
                if rules.outcome(&back_to_start).kind != OutcomeKind::Ongoing {
                    continue;
                }
                // One full shuttle cycle keeps the game ongoing; run a
                // second cycle to stack up repetition counts.
                let mut snap2 = back_to_start;
                let mut ok = true;
                for token in [&a_token, &b_token, &a_rev, &b_rev] {
                    let Some(action) = find_action(&snap2, token) else {
                        ok = false;
                        break;
                    };
                    snap2 = rules.apply(&snap2, action);
                    if rules.outcome(&snap2).kind != OutcomeKind::Ongoing {
                        ok = false;
                        break;
                    }
                }
                if !ok {
                    continue;
                }
                // Now black playing `a` once more creates the third
                // occurrence of the after-a position: live-terminal.
                let Some(a_again) = find_action(&snap2, &a_token) else {
                    continue;
                };
                let third = rules.apply(&snap2, a_again);
                if rules.outcome(&third).kind == OutcomeKind::Ongoing {
                    continue;
                }
                shuttle = Some((a_again, snap2));
                break 'outer;
            }
        }
        let (target_action, live_snap) =
            shuttle.expect("a repetition shuttle must exist in this quiet 3v4 position");

        // Patch entry: the live parent position, with best_child = the
        // (history-free) child of the repetition-triggering move.
        let provider = MemoryDatabaseProvider::from_files([(
            "std.secval".to_string(),
            sample_patch().secval_bytes,
        )]);
        let mut keys = WdlPlaneCache::new(provider, DatabaseVariant::STANDARD).unwrap();
        let parent_state = MillRules::decode_snapshot(live_snap);
        let parent_key = crate::mill::canonical_key(&mut keys, &parent_state, &options).unwrap();
        let (sector, slot) = crate::wdl_plane::unpack_canonical_key(parent_key);

        let sanitized_parent = rules.encode_state(
            rules
                .set_from_fen(&rules.export_fen(&parent_state))
                .unwrap(),
        );
        let best_child_state =
            MillRules::decode_snapshot(rules.apply(&sanitized_parent, target_action));
        let best_child_key =
            crate::mill::canonical_key(&mut keys, &best_child_state, &options).unwrap();
        // The proof frame is the history-free replica: from the live
        // snapshot the repetition child is terminal and has no canonical
        // key, which is the very asymmetry this regression test guards.
        let (child_count, optimal_mask) = proof_for_children(
            &mut keys,
            &rules,
            &options,
            &sanitized_parent,
            &[best_child_key],
        );

        let patch = PatchFile {
            variant_byte: 0,
            fingerprint: sample_patch().fingerprint,
            secval_bytes: sample_patch().secval_bytes,
            sectors: vec![SectorGroup {
                white_on_board: sector.white_on_board,
                black_on_board: sector.black_on_board,
                white_in_hand: sector.white_in_hand,
                black_in_hand: sector.black_in_hand,
                records: vec![PackedRecord {
                    slot: slot as u32,
                    best_child: best_child_key,
                    severity: 1,
                    trap_score: 100,
                    child_count,
                    optimal_mask,
                    trap_score_mask: 0,
                    optimal_trap_nibbles: 0,
                }],
            }],
            mid_removal_records: vec![],
        };
        let mut buf = Vec::new();
        patch.write_to(&mut buf, 3).unwrap();
        let mut lookup = PatchLookup::open(&buf).unwrap();

        // Choose some other legal move as the engine's (bad) pick; the
        // correction must find the repetition move even though applying it
        // to the live snapshot ends the game.
        let mut live_actions = tgf_core::ActionList::<256>::new();
        rules.legal_actions(&live_snap, &mut live_actions);
        let other = live_actions
            .as_slice()
            .iter()
            .copied()
            .find(|&a| a != target_action)
            .expect("position must have an alternative move");
        assert_eq!(
            lookup.correct_action(&rules, &options, &live_snap, other),
            Some(target_action),
            "the corrective reply must stay matchable despite live repetition history"
        );
    }

    /// Sibling regression to the repetition case above, for the other
    /// history-dependent way a quiet reply can end a live game: the
    /// `n_move_rule` inactivity counter. A patch entry is always mined
    /// with a fresh (zero) counter, but the exact same board reached via a
    /// long real game can have a live counter one ply from the limit --
    /// making the recorded corrective reply end the game on the spot in
    /// the live snapshot even though it is a perfectly ordinary, non
    /// -terminal reply from the mined position's point of view.
    #[test]
    fn correct_action_still_matches_a_reply_that_draws_by_live_n_move_rule() {
        let options = MillVariantOptions {
            n_move_rule: 10,
            ..MillVariantOptions::default()
        };
        let rules = MillRules::new(options.clone());

        let fresh_fen = "OOO***@*/@**@****/******@* b m s 3 0 4 0 0 0 -1 -1 -1 -1 0 0 31 ids:nodes";
        let fresh_state = rules.set_from_fen(fresh_fen).unwrap();
        let fresh_snap = rules.encode_state(fresh_state.clone());

        let mut actions = tgf_core::ActionList::<256>::new();
        rules.legal_actions(&fresh_snap, &mut actions);
        assert!(actions.as_slice().len() >= 2);
        let target_action = actions.as_slice()[0];
        let other_action = actions.as_slice()[1];

        // Splice a live counter one ply below `n_move_rule` into the same
        // position's FEN (field 15, 0-indexed -- see `export_fen`'s
        // `ply_since_capture` slot) to build a "long real game" snapshot
        // without needing `tgf_mill::rules`-internal access to the field.
        let mut fields: Vec<&str> = fresh_fen.split(' ').collect();
        assert_eq!(
            fields[15], "0",
            "test fixture's own counter must start at zero"
        );
        fields[15] = "9";
        let live_fen = fields.join(" ");
        let live_state = rules.set_from_fen(&live_fen).unwrap();
        let live_snap = rules.encode_state(live_state.clone());

        let provider = MemoryDatabaseProvider::from_files([(
            "std.secval".to_string(),
            sample_patch().secval_bytes,
        )]);
        let mut keys = WdlPlaneCache::new(provider, DatabaseVariant::STANDARD).unwrap();

        // The spliced position must still decode to the exact same
        // abstract game (so `target_action`/`other_action` stay legal and
        // the patch's parent key still matches), differing only in how
        // close it is to a rule-forced draw.
        assert_eq!(
            crate::mill::canonical_key(&mut keys, &fresh_state, &options),
            crate::mill::canonical_key(&mut keys, &live_state, &options)
        );
        let mut live_actions = tgf_core::ActionList::<256>::new();
        rules.legal_actions(&live_snap, &mut live_actions);
        assert!(live_actions.as_slice().contains(&target_action));

        // Confirm the live game genuinely ends when `target_action` is
        // played now (this is the failure mode under test, not an
        // incidental side effect): one more quiet ply crosses
        // `n_move_rule`.
        let live_after_target = rules.apply(&live_snap, target_action);
        assert_ne!(
            rules.outcome(&live_after_target).kind,
            OutcomeKind::Ongoing,
            "the live counter must be primed to end the game on this exact reply"
        );

        let parent_key = crate::mill::canonical_key(&mut keys, &fresh_state, &options).unwrap();
        let (sector, slot) = crate::wdl_plane::unpack_canonical_key(parent_key);
        let target_child_state =
            MillRules::decode_snapshot(rules.apply(&fresh_snap, target_action));
        let target_child_key =
            crate::mill::canonical_key(&mut keys, &target_child_state, &options).unwrap();
        let (child_count, optimal_mask) = proof_for_children(
            &mut keys,
            &rules,
            &options,
            &fresh_snap,
            &[target_child_key],
        );

        let patch = PatchFile {
            variant_byte: 0,
            fingerprint: sample_patch().fingerprint,
            secval_bytes: sample_patch().secval_bytes,
            sectors: vec![SectorGroup {
                white_on_board: sector.white_on_board,
                black_on_board: sector.black_on_board,
                white_in_hand: sector.white_in_hand,
                black_in_hand: sector.black_in_hand,
                records: vec![PackedRecord {
                    slot: slot as u32,
                    best_child: target_child_key,
                    severity: 1,
                    trap_score: 100,
                    child_count,
                    optimal_mask,
                    trap_score_mask: 0,
                    optimal_trap_nibbles: 0,
                }],
            }],
            mid_removal_records: vec![],
        };
        let mut buf = Vec::new();
        patch.write_to(&mut buf, 3).unwrap();
        let mut lookup = PatchLookup::open(&buf).unwrap();

        assert_eq!(
            lookup.correct_action(&rules, &options, &live_snap, other_action),
            Some(target_action),
            "the corrective reply must stay matchable despite the live n_move_rule counter"
        );
    }

    /// Regression test for a real crash: `correct_action` /
    /// `trap_score_for_state` must not blindly feed a mid-removal-tagged key
    /// (see `wdl_plane::MID_REMOVAL_KEY_TAG`) into `unpack_canonical_key`,
    /// whose "sector" fields are garbage for such a key and used to panic
    /// via `SectorId::new`'s range assert. Against an *empty* patch (no
    /// entry for this or any other position), both methods must return
    /// `None` for a mid-removal position instead of panicking; see
    /// `mid_removal_lookup_finds_a_correction_for_a_pending_removal`
    /// immediately below for the case where a mid-removal entry exists.
    #[test]
    fn correct_action_and_trap_score_do_not_panic_on_mid_removal_positions() {
        let options = MillVariantOptions::default();
        let rules = MillRules::new(options.clone());

        // Play forward until a mill closes and a removal is pending, mirroring
        // `perfect_db::mill::tests::find_mid_removal_state`.
        let mut snap = rules.initial_state(&[]);
        let mut mid_removal_snap = None;
        for _ in 0..40 {
            let state = MillRules::decode_snapshot(snap);
            let side = state.side_to_move();
            if side >= 0 && state.pending_removals()[side as usize] > 0 {
                mid_removal_snap = Some(snap);
                break;
            }
            let mut actions = tgf_core::ActionList::<256>::new();
            rules.legal_actions(&snap, &mut actions);
            let chosen = actions
                .as_slice()
                .iter()
                .copied()
                .find(|&a| {
                    let next = MillRules::decode_snapshot(rules.apply(&snap, a));
                    let s = next.side_to_move();
                    s >= 0 && next.pending_removals()[s as usize] > 0
                })
                .unwrap_or(actions.as_slice()[0]);
            snap = rules.apply(&snap, chosen);
        }
        let mid_removal_snap =
            mid_removal_snap.expect("must reach a mid-removal state within 40 plies");
        let mid_removal_state = MillRules::decode_snapshot(mid_removal_snap);

        let patch = sample_patch();
        let mut buf = Vec::new();
        patch.write_to(&mut buf, 3).unwrap();
        let mut lookup = PatchLookup::open(&buf).unwrap();

        let mut actions = tgf_core::ActionList::<256>::new();
        rules.legal_actions(&mid_removal_snap, &mut actions);
        let any_action = actions.as_slice()[0];
        assert_eq!(
            lookup.correct_action(&rules, &options, &mid_removal_snap, any_action),
            None
        );
        assert_eq!(
            lookup.trap_score_for_state(&mid_removal_state, &options),
            None
        );
    }

    /// A mid-removal parent position with a real entry in
    /// `mid_removal_records`: `correct_action` must find it (dispatching
    /// past the sector groups entirely, since the key is tagged) and
    /// redirect an unsafe removal choice to the recorded one, exactly like
    /// a settled position's sector-group entry does.
    #[test]
    fn mid_removal_lookup_finds_a_correction_for_a_pending_removal() {
        let options = MillVariantOptions::default();
        let rules = MillRules::new(options.clone());

        let mut snap = rules.initial_state(&[]);
        let mut mid_removal_snap = None;
        for _ in 0..40 {
            let state = MillRules::decode_snapshot(snap);
            let side = state.side_to_move();
            if side >= 0 && state.pending_removals()[side as usize] > 0 {
                mid_removal_snap = Some(snap);
                break;
            }
            let mut actions = tgf_core::ActionList::<256>::new();
            rules.legal_actions(&snap, &mut actions);
            let chosen = actions
                .as_slice()
                .iter()
                .copied()
                .find(|&a| {
                    let next = MillRules::decode_snapshot(rules.apply(&snap, a));
                    let s = next.side_to_move();
                    s >= 0 && next.pending_removals()[s as usize] > 0
                })
                .unwrap_or(actions.as_slice()[0]);
            snap = rules.apply(&snap, chosen);
        }
        let mid_removal_snap =
            mid_removal_snap.expect("must reach a mid-removal state within 40 plies");
        let mid_removal_state = MillRules::decode_snapshot(mid_removal_snap);

        let mut actions = tgf_core::ActionList::<256>::new();
        rules.legal_actions(&mid_removal_snap, &mut actions);
        assert!(
            actions.as_slice().len() >= 2,
            "need at least two removal choices to distinguish safe from unsafe"
        );
        let safe_removal = actions.as_slice()[0];
        let unsafe_removal = actions.as_slice()[1];

        let provider = MemoryDatabaseProvider::from_files([(
            "std.secval".to_string(),
            sample_patch().secval_bytes,
        )]);
        let mut keys = WdlPlaneCache::new(provider, DatabaseVariant::STANDARD).unwrap();
        let parent_key = crate::mill::mid_removal_key(&mid_removal_state).unwrap();
        let safe_child_state =
            MillRules::decode_snapshot(rules.apply(&mid_removal_snap, safe_removal));
        let safe_child_key =
            crate::mill::canonical_key(&mut keys, &safe_child_state, &options).unwrap();
        let (child_count, optimal_mask) = proof_for_children(
            &mut keys,
            &rules,
            &options,
            &mid_removal_snap,
            &[safe_child_key],
        );

        let patch = PatchFile {
            variant_byte: 0,
            fingerprint: sample_patch().fingerprint,
            secval_bytes: sample_patch().secval_bytes,
            sectors: vec![],
            mid_removal_records: vec![MidRemovalRecord {
                key: parent_key,
                best_child: safe_child_key,
                severity: 1,
                trap_score: 100,
                child_count,
                optimal_mask,
                trap_score_mask: 0,
                optimal_trap_nibbles: 0,
            }],
        };
        let mut buf = Vec::new();
        patch.write_to(&mut buf, 3).unwrap();
        let mut lookup = PatchLookup::open(&buf).unwrap();

        assert_eq!(
            lookup.correct_action(&rules, &options, &mid_removal_snap, safe_removal),
            None,
            "already-safe removal must not be corrected"
        );
        assert_eq!(
            lookup.correct_action(&rules, &options, &mid_removal_snap, unsafe_removal),
            Some(safe_removal),
            "unsafe removal must be corrected to the recorded mid-removal reply"
        );
        assert_eq!(
            lookup.trap_score_for_state(&mid_removal_state, &options),
            Some(100)
        );
    }
}
