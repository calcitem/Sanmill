// SPDX-License-Identifier: AGPL-3.0-or-later

use std::collections::{BTreeMap, HashSet};
use std::ffi::OsString;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::SystemTime;

use rusqlite::{Connection, OpenFlags, OptionalExtension};
use serde::Serialize;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use tgf_mill::human_db_codec::{
    HumanTurn, SYM_INVERSE, parse_human_turn_notation_with_history, state_key_from_fen,
    transform_notation,
};
use tgf_mill::{MillRules, MillUciCodec, legal_logical_turns};

use super::hashing::{hex_lower, sha256_file, update_length_prefixed};
use super::position::ReplayedPosition;
use super::protocol::{ApiError, Candidate, HumanCandidateData, RulePreset};

const TRUSTED_MALOM_LABEL_VERSION: &str = "sector-corrected-v1";

#[derive(Clone, Debug)]
pub(super) struct HumanQueryResult {
    pub source: Value,
    pub candidates: Vec<Candidate>,
}

#[derive(Clone, Debug, Serialize)]
pub(super) struct HumanIdentity {
    kind: &'static str,
    database_format: &'static str,
    path: String,
    sha256: String,
    file_size: u64,
    schema_version: String,
    schema_sha256: String,
    build_date: String,
    total_games: u64,
    position_count: u64,
    move_count: u64,
    read_only: bool,
    immutable: bool,
    sidecars_absent: bool,
    malom_label_version: Option<String>,
    malom_trusted: bool,
    malom_trust_reason: String,
    meta: Vec<MetaEntry>,
}

#[derive(Clone, Debug, Serialize)]
struct MetaEntry {
    key: String,
    value: String,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct FileStamp {
    len: u64,
    modified: SystemTime,
}

pub(super) struct HumanDbSource {
    path: PathBuf,
    conn: Connection,
    stamp: FileStamp,
    identity: HumanIdentity,
}

#[derive(Clone, Debug)]
struct HumanMoveRow {
    raw_notation: String,
    mapped_notation: String,
    full_actions: Vec<String>,
    wins: u64,
    losses: u64,
    draws: u64,
    total: u64,
    moves_to_end_sum: f64,
    malom_wdl_after: Option<String>,
    malom_dtw_after: Option<i64>,
}

#[derive(Clone, Debug, Serialize)]
struct HumanPositionData {
    total_games: u64,
    wins: u64,
    losses: u64,
    draws: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    malom_wdl: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    malom_dtw: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    canonical_winning_move: Option<String>,
}

impl HumanDbSource {
    pub(super) fn open(path: &str) -> Result<Self, ApiError> {
        let path = validated_database_path(path)?;
        ensure_no_live_sidecars(&path)?;
        let stamp = file_stamp(&path)?;
        let sha256 =
            sha256_file(&path).map_err(|message| ApiError::new("database_open_error", message))?;
        if file_stamp(&path)? != stamp {
            return Err(ApiError::new(
                "database_changed",
                "Human Database changed while its SHA-256 was being calculated",
            ));
        }
        let uri = immutable_sqlite_uri(&path)?;
        let flags = OpenFlags::SQLITE_OPEN_READ_ONLY
            | OpenFlags::SQLITE_OPEN_URI
            | OpenFlags::SQLITE_OPEN_NO_MUTEX;
        let conn = Connection::open_with_flags(uri, flags)
            .map_err(|error| sqlite_error("database_open_error", "open Human Database", error))?;
        conn.execute_batch("PRAGMA query_only=ON;")
            .map_err(|error| {
                sqlite_error("database_open_error", "enable query-only mode", error)
            })?;
        validate_quick_check(&conn)?;
        let schema_sha256 = validate_schema(&conn)?;
        let meta = read_meta(&conn)?;
        let schema_version = required_meta(&meta, "schema_version")?.to_owned();
        if schema_version != "2" {
            return Err(ApiError::new(
                "database_schema_incompatible",
                format!("Human Database schema version {schema_version:?} is unsupported"),
            ));
        }
        let build_date = required_meta(&meta, "build_date")?.to_owned();
        let total_games = parse_meta_u64(&meta, "total_games")?;
        let position_count = count_rows(&conn, "positions")?;
        let move_count = count_rows(&conn, "moves")?;
        let malom_label_version = meta.get("malom_label_version").cloned();
        let malom_trusted = malom_label_version.as_deref() == Some(TRUSTED_MALOM_LABEL_VERSION);
        let malom_trust_reason = if malom_trusted {
            format!("meta.malom_label_version={TRUSTED_MALOM_LABEL_VERSION}")
        } else {
            match &malom_label_version {
                Some(version) => format!(
                    "unsupported meta.malom_label_version={version}; expected \
                     {TRUSTED_MALOM_LABEL_VERSION}"
                ),
                None => "meta.malom_label_version is absent".to_owned(),
            }
        };
        ensure_no_live_sidecars(&path)?;
        if file_stamp(&path)? != stamp {
            return Err(ApiError::new(
                "database_changed",
                "Human Database changed while it was being opened and validated",
            ));
        }
        let identity = HumanIdentity {
            kind: "human_database",
            database_format: "nmm-llm-human-db",
            path: path.display().to_string(),
            sha256,
            file_size: stamp.len,
            schema_version,
            schema_sha256,
            build_date,
            total_games,
            position_count,
            move_count,
            read_only: true,
            immutable: true,
            sidecars_absent: true,
            malom_label_version,
            malom_trusted,
            malom_trust_reason,
            meta: meta
                .into_iter()
                .map(|(key, value)| MetaEntry { key, value })
                .collect(),
        };
        Ok(Self {
            path,
            conn,
            stamp,
            identity,
        })
    }

    pub(super) fn identity_json(&self) -> Value {
        serde_json::to_value(&self.identity).expect("Human DB identity must serialize")
    }

    pub(super) fn query(
        &self,
        replayed: &ReplayedPosition,
        candidate_limit: Option<usize>,
        min_total: u64,
    ) -> Result<HumanQueryResult, ApiError> {
        if replayed.rule != RulePreset::Nmm {
            return Err(ApiError::new(
                "unsupported_rule",
                "Human Database data-query supports standard NMM only",
            ));
        }
        if candidate_limit == Some(0) {
            return Err(ApiError::new(
                "protocol_error",
                "candidate_limit must be positive when provided",
            ));
        }
        self.verify_unchanged()?;
        let source_position = replayed.source_position();
        if replayed.current_side_has_pending_removal() && !source_position.prefix_complete {
            return Err(ApiError::new(
                "incomplete_history",
                "Human Database queries in pending-removal states require the initiating history",
            ));
        }
        let source_fen = replayed
            .rules
            .export_fen(&MillRules::decode_snapshot(*source_position.snapshot));
        let (state_key, symmetry_index) = state_key_from_fen(&source_fen).map_err(|message| {
            ApiError::new(
                "coordinate_mapping_error",
                format!("failed to build Human Database state_key: {message}"),
            )
        })?;
        let position_data = self.query_position(&state_key)?;
        let mut rows = self.query_moves(
            replayed,
            source_position.snapshot,
            source_position.history,
            &state_key,
            symmetry_index,
        )?;

        if !source_position.prefix_actions.is_empty() {
            rows.retain(|row| {
                row.full_actions
                    .iter()
                    .zip(source_position.prefix_tokens.iter())
                    .all(|(actual, prefix)| actual == prefix)
                    && row.full_actions.len() >= source_position.prefix_tokens.len()
            });
        }
        let frequency_denominator = rows
            .iter()
            .try_fold(0_u64, |total, row| total.checked_add(row.total))
            .ok_or_else(|| {
                ApiError::new(
                    "database_corrupt",
                    "Human Database candidate totals overflow u64",
                )
            })?;
        let total_matching_candidates = rows.len();
        rows.retain(|row| row.total >= min_total);
        rows.sort_by(|left, right| {
            right
                .total
                .cmp(&left.total)
                .then_with(|| left.raw_notation.cmp(&right.raw_notation))
                .then_with(|| left.mapped_notation.cmp(&right.mapped_notation))
        });
        let eligible_candidate_count = rows.len();
        if let Some(limit) = candidate_limit {
            rows.truncate(limit);
        }

        let mut candidates = Vec::with_capacity(rows.len());
        for (stable_index, row) in rows.into_iter().enumerate() {
            let remaining_actions =
                row.full_actions[source_position.prefix_tokens.len()..].to_vec();
            let removal_action = row
                .full_actions
                .iter()
                .find(|token| token.starts_with('x'))
                .cloned();
            let total_f = row.total as f64;
            let relative_frequency = if frequency_denominator == 0 {
                0.0
            } else {
                row.total as f64 / frequency_denominator as f64
            };
            let (win_rate, draw_rate, loss_rate, legacy_score) = if row.total == 0 {
                (0.0, 0.0, 0.0, 0.0)
            } else {
                let raw = (row.wins as f64 + 0.4 * row.draws as f64) / total_f - 0.5;
                let confidence = ((row.total + 1) as f64).ln() / 20_f64.ln();
                (
                    row.wins as f64 / total_f,
                    row.draws as f64 / total_f,
                    row.losses as f64 / total_f,
                    (raw * confidence.min(1.0)).clamp(-0.5, 0.5),
                )
            };
            candidates.push(Candidate {
                logical_move_id: logical_move_id(
                    &self.identity.sha256,
                    &state_key,
                    &row.full_actions,
                ),
                source_group_id: None,
                stable_index,
                source_rank: None,
                raw_notation: Some(row.raw_notation),
                mapped_notation: row.mapped_notation,
                full_turn_actions: row.full_actions,
                remaining_actions,
                contains_removal: removal_action.is_some(),
                removal_action,
                logical_ply_delta: 1,
                turn_prefix_complete: source_position.prefix_complete,
                perfect: None,
                human: Some(HumanCandidateData {
                    wins: row.wins,
                    losses: row.losses,
                    draws: row.draws,
                    total: row.total,
                    frequency_numerator: row.total,
                    frequency_denominator,
                    relative_frequency,
                    empirical_win_rate: win_rate,
                    empirical_draw_rate: draw_rate,
                    empirical_loss_rate: loss_rate,
                    legacy_experience_score: legacy_score,
                    moves_to_end_sum: row.moves_to_end_sum,
                    average_moves_to_end: (row.total > 0).then_some(row.moves_to_end_sum / total_f),
                    malom_wdl_after: row.malom_wdl_after,
                    malom_dtw_after: row.malom_dtw_after,
                }),
            });
        }
        self.verify_unchanged()?;
        Ok(HumanQueryResult {
            source: json!({
                "identity": self.identity,
                "state_key": state_key,
                "symmetry_index": symmetry_index,
                "candidate_order":
                    "total_desc_then_canonical_notation_then_mapped_notation",
                "frequency_denominator_scope": if source_position.prefix_tokens.is_empty() {
                    "all_state_candidates"
                } else {
                    "all_candidates_matching_pending_turn_prefix"
                },
                "total_matching_candidates": total_matching_candidates,
                "eligible_candidate_count": eligible_candidate_count,
                "returned_candidate_count": candidates.len(),
                "candidate_limit": candidate_limit,
                "min_total": min_total,
                "position": position_data,
                "fallback": "none"
            }),
            candidates,
        })
    }

    fn query_position(&self, state_key: &str) -> Result<Option<HumanPositionData>, ApiError> {
        let row = self
            .conn
            .query_row(
                "SELECT total_games, wins, losses, draws, malom_wdl, malom_dtw, \
                 canonical_winning_move FROM positions WHERE state_key=?1",
                [state_key],
                |row| {
                    Ok((
                        row.get::<_, i64>(0)?,
                        row.get::<_, i64>(1)?,
                        row.get::<_, i64>(2)?,
                        row.get::<_, i64>(3)?,
                        row.get::<_, Option<String>>(4)?,
                        row.get::<_, Option<i64>>(5)?,
                        row.get::<_, Option<String>>(6)?,
                    ))
                },
            )
            .optional()
            .map_err(|error| sqlite_error("database_query_error", "query positions", error))?;
        let Some((total, wins, losses, draws, malom_wdl, malom_dtw, winning_move)) = row else {
            return Ok(None);
        };
        let [total, wins, losses, draws] =
            validate_nonnegative_stats([total, wins, losses, draws], "positions")?;
        if wins
            .checked_add(losses)
            .and_then(|value| value.checked_add(draws))
            != Some(total)
        {
            return Err(ApiError::new(
                "database_corrupt",
                format!("Human Database position statistics do not sum to total for {state_key}"),
            ));
        }
        validate_malom_wdl(malom_wdl.as_deref(), "positions.malom_wdl")?;
        Ok(Some(HumanPositionData {
            total_games: total,
            wins,
            losses,
            draws,
            malom_wdl: self.identity.malom_trusted.then_some(malom_wdl).flatten(),
            malom_dtw: self.identity.malom_trusted.then_some(malom_dtw).flatten(),
            canonical_winning_move: self
                .identity
                .malom_trusted
                .then_some(winning_move)
                .flatten(),
        }))
    }

    fn query_moves(
        &self,
        replayed: &ReplayedPosition,
        snapshot: &tgf_core::GameStateSnapshot,
        history: &[tgf_core::GameStateSnapshot],
        state_key: &str,
        symmetry_index: usize,
    ) -> Result<Vec<HumanMoveRow>, ApiError> {
        let inverse = *SYM_INVERSE.get(symmetry_index).ok_or_else(|| {
            ApiError::new(
                "coordinate_mapping_error",
                format!("Human Database symmetry index {symmetry_index} is invalid"),
            )
        })?;
        let legal_turns = legal_logical_turns(&replayed.rules, snapshot, history)
            .map_err(|error| ApiError::new("invalid_state", error.to_string()))?;
        let legal_turn_tokens = legal_turns
            .into_iter()
            .map(|turn| {
                turn.actions
                    .into_iter()
                    .map(MillUciCodec::encode_action)
                    .collect::<Vec<_>>()
            })
            .collect::<HashSet<_>>();
        let mut stmt = self
            .conn
            .prepare(
                "SELECT notation, wins, losses, draws, total, moves_to_end_sum, \
                 malom_wdl_after, malom_dtw_after FROM moves \
                 WHERE state_key=?1 ORDER BY total DESC, notation ASC",
            )
            .map_err(|error| sqlite_error("database_query_error", "prepare moves query", error))?;
        let query = stmt
            .query_map([state_key], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, i64>(1)?,
                    row.get::<_, i64>(2)?,
                    row.get::<_, i64>(3)?,
                    row.get::<_, i64>(4)?,
                    row.get::<_, f64>(5)?,
                    row.get::<_, Option<String>>(6)?,
                    row.get::<_, Option<i64>>(7)?,
                ))
            })
            .map_err(|error| sqlite_error("database_query_error", "query moves", error))?;
        let mut seen = HashSet::new();
        let mut moves = Vec::new();
        for row in query {
            let (raw, wins, losses, draws, total, moves_to_end_sum, malom_wdl, malom_dtw) = row
                .map_err(|error| {
                    sqlite_error("database_corrupt", "read Human Database move row", error)
                })?;
            if !seen.insert(raw.clone()) {
                return Err(ApiError::new(
                    "database_corrupt",
                    format!("duplicate Human Database notation {raw:?} for {state_key}"),
                ));
            }
            let [wins, losses, draws, total] =
                validate_nonnegative_stats([wins, losses, draws, total], "moves")?;
            if wins
                .checked_add(losses)
                .and_then(|value| value.checked_add(draws))
                != Some(total)
            {
                return Err(ApiError::new(
                    "database_corrupt",
                    format!("Human Database move statistics do not sum to total for {raw:?}"),
                ));
            }
            if !moves_to_end_sum.is_finite() || moves_to_end_sum < 0.0 {
                return Err(ApiError::new(
                    "database_corrupt",
                    format!("invalid moves_to_end_sum for Human Database move {raw:?}"),
                ));
            }
            validate_malom_wdl(malom_wdl.as_deref(), "moves.malom_wdl_after")?;
            let mapped = transform_notation(&raw, inverse).ok_or_else(|| {
                ApiError::new(
                    "coordinate_mapping_error",
                    format!("cannot map Human Database notation {raw:?} to the live board"),
                )
            })?;
            let parsed = parse_human_turn_notation_with_history(
                &replayed.rules,
                snapshot,
                history,
                &mapped,
            )
            .map_err(|error| {
                ApiError::new(
                    "illegal_source_move",
                    format!(
                        "Human Database notation {raw:?} maps to illegal turn {mapped:?}: {error:?}"
                    ),
                )
            })?;
            let actions = match parsed {
                HumanTurn::BaseOnly(action) | HumanTurn::CaptureOnly(action) => vec![action],
                HumanTurn::BaseThenCapture { base, capture } => vec![base, capture],
            };
            let full_actions = actions
                .into_iter()
                .map(MillUciCodec::encode_action)
                .collect::<Vec<_>>();
            if !legal_turn_tokens.contains(&full_actions) {
                return Err(ApiError::new(
                    "illegal_source_move",
                    format!(
                        "Human Database notation {raw:?} does not form one complete legal turn"
                    ),
                ));
            }
            moves.push(HumanMoveRow {
                raw_notation: raw,
                mapped_notation: mapped,
                full_actions,
                wins,
                losses,
                draws,
                total,
                moves_to_end_sum,
                malom_wdl_after: self.identity.malom_trusted.then_some(malom_wdl).flatten(),
                malom_dtw_after: self.identity.malom_trusted.then_some(malom_dtw).flatten(),
            });
        }
        Ok(moves)
    }

    fn verify_unchanged(&self) -> Result<(), ApiError> {
        ensure_no_live_sidecars(&self.path)?;
        if file_stamp(&self.path)? != self.stamp {
            return Err(ApiError::new(
                "database_changed",
                "Human Database file identity changed after it was opened",
            ));
        }
        Ok(())
    }
}

pub(super) fn identity(path: &str) -> Result<Value, ApiError> {
    Ok(HumanDbSource::open(path)?.identity_json())
}

fn validated_database_path(path: &str) -> Result<PathBuf, ApiError> {
    let path = PathBuf::from(path);
    let metadata = fs::metadata(&path).map_err(|error| {
        let code = if error.kind() == std::io::ErrorKind::NotFound {
            "database_missing"
        } else {
            "database_open_error"
        };
        ApiError::new(
            code,
            format!(
                "failed to inspect Human Database {}: {error}",
                path.display()
            ),
        )
    })?;
    if !metadata.is_file() {
        return Err(ApiError::new(
            "database_open_error",
            format!("Human Database path is not a file: {}", path.display()),
        ));
    }
    fs::canonicalize(&path).map_err(|error| {
        ApiError::new(
            "database_open_error",
            format!(
                "failed to canonicalize Human Database path {}: {error}",
                path.display()
            ),
        )
    })
}

fn file_stamp(path: &Path) -> Result<FileStamp, ApiError> {
    let metadata = fs::metadata(path).map_err(|error| {
        ApiError::new(
            "database_open_error",
            format!(
                "failed to inspect Human Database {}: {error}",
                path.display()
            ),
        )
    })?;
    let modified = metadata.modified().map_err(|error| {
        ApiError::new(
            "database_open_error",
            format!(
                "failed to read Human Database modification time {}: {error}",
                path.display()
            ),
        )
    })?;
    Ok(FileStamp {
        len: metadata.len(),
        modified,
    })
}

fn ensure_no_live_sidecars(path: &Path) -> Result<(), ApiError> {
    for suffix in ["-wal", "-shm"] {
        let mut sidecar: OsString = path.as_os_str().to_owned();
        sidecar.push(suffix);
        let sidecar = PathBuf::from(sidecar);
        match fs::metadata(&sidecar) {
            Ok(metadata) if metadata.len() > 0 => {
                return Err(ApiError::new(
                    "database_not_immutable",
                    format!(
                        "Human Database has a non-empty SQLite sidecar: {}",
                        sidecar.display()
                    ),
                ));
            }
            Ok(_) => {}
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(error) => {
                return Err(ApiError::new(
                    "database_open_error",
                    format!(
                        "failed to inspect SQLite sidecar {}: {error}",
                        sidecar.display()
                    ),
                ));
            }
        }
    }
    Ok(())
}

fn immutable_sqlite_uri(path: &Path) -> Result<String, ApiError> {
    let text = path.to_str().ok_or_else(|| {
        ApiError::new(
            "database_open_error",
            "Human Database path is not valid UTF-8",
        )
    })?;
    let normalized = if let Some(rest) = text.strip_prefix(r"\\?\UNC\") {
        format!("//{}", rest.replace('\\', "/"))
    } else {
        text.strip_prefix(r"\\?\")
            .unwrap_or(text)
            .replace('\\', "/")
    };
    let mut encoded = String::with_capacity(normalized.len());
    for byte in normalized.as_bytes() {
        match *byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'/' | b':' | b'.' | b'-' | b'_' => {
                encoded.push(*byte as char)
            }
            value => encoded.push_str(&format!("%{value:02X}")),
        }
    }
    Ok(format!("file:{encoded}?mode=ro&immutable=1"))
}

fn validate_quick_check(conn: &Connection) -> Result<(), ApiError> {
    let result = conn
        .query_row("PRAGMA quick_check(1)", [], |row| row.get::<_, String>(0))
        .map_err(|error| sqlite_error("database_corrupt", "run SQLite quick_check", error))?;
    if result == "ok" {
        Ok(())
    } else {
        Err(ApiError::new(
            "database_corrupt",
            format!("SQLite quick_check failed: {result}"),
        ))
    }
}

fn validate_schema(conn: &Connection) -> Result<String, ApiError> {
    let required = [
        ("meta", &[("key", 1_i64), ("value", 0_i64)][..]),
        (
            "positions",
            &[
                ("state_key", 1),
                ("total_games", 0),
                ("wins", 0),
                ("losses", 0),
                ("draws", 0),
                ("malom_wdl", 0),
                ("malom_dtw", 0),
                ("canonical_winning_move", 0),
            ][..],
        ),
        (
            "moves",
            &[
                ("state_key", 1),
                ("notation", 2),
                ("wins", 0),
                ("losses", 0),
                ("draws", 0),
                ("total", 0),
                ("moves_to_end_sum", 0),
                ("malom_wdl_after", 0),
                ("malom_dtw_after", 0),
            ][..],
        ),
    ];
    for (table, columns) in required {
        let actual = table_columns(conn, table)?;
        for &(column, pk_position) in columns {
            let Some(actual_pk) = actual.get(column) else {
                return Err(ApiError::new(
                    "database_schema_incompatible",
                    format!("Human Database table {table} is missing column {column}"),
                ));
            };
            if *actual_pk != pk_position {
                return Err(ApiError::new(
                    "database_schema_incompatible",
                    format!(
                        "Human Database column {table}.{column} has primary-key position \
                         {actual_pk}, expected {pk_position}"
                    ),
                ));
            }
        }
    }

    let mut stmt = conn
        .prepare(
            "SELECT type, name, COALESCE(sql, '') FROM sqlite_master \
             WHERE type IN ('table','index') AND name NOT LIKE 'sqlite_%' \
             ORDER BY type, name",
        )
        .map_err(|error| sqlite_error("database_schema_incompatible", "inspect schema", error))?;
    let rows = stmt
        .query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
            ))
        })
        .map_err(|error| sqlite_error("database_schema_incompatible", "query schema", error))?;
    let mut hash = Sha256::new();
    hash.update(b"sanmill.human-db.schema.v1\0");
    for row in rows {
        let (kind, name, sql) = row
            .map_err(|error| sqlite_error("database_schema_incompatible", "read schema", error))?;
        update_length_prefixed(&mut hash, kind.as_bytes());
        update_length_prefixed(&mut hash, name.as_bytes());
        update_length_prefixed(&mut hash, sql.as_bytes());
    }
    Ok(hex_lower(&hash.finalize()))
}

fn table_columns(conn: &Connection, table: &str) -> Result<BTreeMap<String, i64>, ApiError> {
    let sql = format!("PRAGMA table_info({table})");
    let mut stmt = conn
        .prepare(&sql)
        .map_err(|error| sqlite_error("database_schema_incompatible", "inspect columns", error))?;
    let rows = stmt
        .query_map([], |row| {
            Ok((row.get::<_, String>(1)?, row.get::<_, i64>(5)?))
        })
        .map_err(|error| sqlite_error("database_schema_incompatible", "query columns", error))?;
    let mut columns = BTreeMap::new();
    for row in rows {
        let (name, primary_key_position) = row.map_err(|error| {
            sqlite_error(
                "database_schema_incompatible",
                "read column metadata",
                error,
            )
        })?;
        columns.insert(name, primary_key_position);
    }
    Ok(columns)
}

fn read_meta(conn: &Connection) -> Result<BTreeMap<String, String>, ApiError> {
    let mut stmt = conn
        .prepare("SELECT key, value FROM meta ORDER BY key")
        .map_err(|error| {
            sqlite_error("database_schema_incompatible", "prepare meta query", error)
        })?;
    let rows = stmt
        .query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })
        .map_err(|error| sqlite_error("database_schema_incompatible", "query meta", error))?;
    let mut meta = BTreeMap::new();
    for row in rows {
        let (key, value) =
            row.map_err(|error| sqlite_error("database_corrupt", "read meta row", error))?;
        if meta.insert(key.clone(), value).is_some() {
            return Err(ApiError::new(
                "database_corrupt",
                format!("duplicate Human Database meta key {key:?}"),
            ));
        }
    }
    Ok(meta)
}

fn required_meta<'a>(meta: &'a BTreeMap<String, String>, key: &str) -> Result<&'a str, ApiError> {
    meta.get(key).map(String::as_str).ok_or_else(|| {
        ApiError::new(
            "database_schema_incompatible",
            format!("Human Database is missing required meta key {key:?}"),
        )
    })
}

fn parse_meta_u64(meta: &BTreeMap<String, String>, key: &str) -> Result<u64, ApiError> {
    required_meta(meta, key)?.parse::<u64>().map_err(|error| {
        ApiError::new(
            "database_corrupt",
            format!("Human Database meta key {key:?} is not a u64: {error}"),
        )
    })
}

fn count_rows(conn: &Connection, table: &str) -> Result<u64, ApiError> {
    let sql = format!("SELECT COUNT(*) FROM {table}");
    let count = conn
        .query_row(&sql, [], |row| row.get::<_, i64>(0))
        .map_err(|error| sqlite_error("database_query_error", "count database rows", error))?;
    u64::try_from(count).map_err(|_| {
        ApiError::new(
            "database_corrupt",
            format!("Human Database table {table} has a negative row count"),
        )
    })
}

fn validate_nonnegative_stats<const N: usize>(
    values: [i64; N],
    context: &str,
) -> Result<[u64; N], ApiError> {
    let mut converted = [0_u64; N];
    for (index, value) in values.into_iter().enumerate() {
        converted[index] = u64::try_from(value).map_err(|_| {
            ApiError::new(
                "database_corrupt",
                format!("Human Database {context} statistic at index {index} is negative"),
            )
        })?;
    }
    Ok(converted)
}

fn validate_malom_wdl(value: Option<&str>, field: &str) -> Result<(), ApiError> {
    if value.is_none_or(|value| matches!(value, "W" | "D" | "L")) {
        Ok(())
    } else {
        Err(ApiError::new(
            "database_corrupt",
            format!("Human Database {field} contains an invalid WDL label {value:?}"),
        ))
    }
}

fn sqlite_error(code: &str, context: &str, error: rusqlite::Error) -> ApiError {
    let mapped = match &error {
        rusqlite::Error::SqliteFailure(details, _)
            if matches!(
                details.code,
                rusqlite::ErrorCode::DatabaseCorrupt | rusqlite::ErrorCode::NotADatabase
            ) =>
        {
            "database_corrupt"
        }
        rusqlite::Error::SqliteFailure(details, _)
            if details.code == rusqlite::ErrorCode::CannotOpen =>
        {
            "database_open_error"
        }
        _ => code,
    };
    ApiError::new(mapped, format!("failed to {context}: {error}"))
}

fn logical_move_id(identity: &str, state_key: &str, tokens: &[String]) -> String {
    let mut hash = Sha256::new();
    update_length_prefixed(&mut hash, b"human");
    update_length_prefixed(&mut hash, identity.as_bytes());
    update_length_prefixed(&mut hash, state_key.as_bytes());
    for token in tokens {
        update_length_prefixed(&mut hash, token.as_bytes());
    }
    format!("human:{}", hex_lower(&hash.finalize()))
}

#[cfg(test)]
#[path = "human_db_tests.rs"]
mod tests;
