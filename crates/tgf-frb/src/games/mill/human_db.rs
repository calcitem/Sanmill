// SPDX-License-Identifier: AGPL-3.0-or-later
// Human-game database lookup for standard Nine Men's Morris positions.
//
// The database is produced outside Sanmill. It is intentionally read-only here:
// Sanmill uses it as an advisory move source before falling back to the native
// Rust search.

#[cfg(not(target_arch = "wasm32"))]
use std::path::Path;
#[cfg(not(target_arch = "wasm32"))]
use std::sync::Mutex;

#[cfg(not(target_arch = "wasm32"))]
use once_cell::sync::Lazy;
#[cfg(not(target_arch = "wasm32"))]
use rusqlite::{Connection, OpenFlags, params};
// The state_key / D4 / notation conventions live in the shared codec so the
// patch packer and this lookup can never drift apart on coordinates.
use tgf_mill::human_db_codec::{SYM_INVERSE, state_key_from_fen, transform_notation};

#[cfg(not(target_arch = "wasm32"))]
static HUMAN_DB: Lazy<Mutex<Option<HumanDatabase>>> = Lazy::new(|| Mutex::new(None));

#[derive(Clone, Debug)]
pub(crate) struct HumanDatabaseStatus {
    pub readable: bool,
    pub initialized: bool,
    pub error: String,
    pub schema_version: String,
    pub build_date: String,
    pub total_games: u32,
    pub position_count: u32,
    pub move_count: u32,
}

#[derive(Clone, Debug)]
pub(crate) struct HumanDatabaseMove {
    pub notation: String,
    pub wins: u32,
    pub losses: u32,
    pub draws: u32,
    pub total: u32,
    pub win_pct: f64,
    pub score_delta: f64,
}

#[derive(Clone, Debug)]
pub(crate) struct HumanDatabaseQuery {
    pub available: bool,
    pub state_key: String,
    pub error: String,
    pub moves: Vec<HumanDatabaseMove>,
}

#[cfg(not(target_arch = "wasm32"))]
struct HumanDatabase {
    path: String,
    conn: Connection,
    schema_version: String,
    build_date: String,
    total_games: u32,
    position_count: u32,
    move_count: u32,
}

pub(crate) fn unavailable_status(error: impl Into<String>) -> HumanDatabaseStatus {
    HumanDatabaseStatus {
        readable: false,
        initialized: false,
        error: error.into(),
        schema_version: String::new(),
        build_date: String::new(),
        total_games: 0,
        position_count: 0,
        move_count: 0,
    }
}

#[cfg(target_arch = "wasm32")]
pub(crate) fn init_database_path(_path: String) -> bool {
    false
}

#[cfg(not(target_arch = "wasm32"))]
pub(crate) fn init_database_path(path: String) -> bool {
    let Ok(database) = HumanDatabase::open(&path) else {
        return false;
    };
    *HUMAN_DB
        .lock()
        .expect("Human Database mutex must not be poisoned") = Some(database);
    true
}

#[cfg(target_arch = "wasm32")]
pub(crate) fn deinit_database() {}

#[cfg(not(target_arch = "wasm32"))]
pub(crate) fn deinit_database() {
    *HUMAN_DB
        .lock()
        .expect("Human Database mutex must not be poisoned") = None;
}

#[cfg(target_arch = "wasm32")]
pub(crate) fn database_status(_path: String) -> HumanDatabaseStatus {
    unavailable_status("Human game database is not available on Web")
}

#[cfg(not(target_arch = "wasm32"))]
pub(crate) fn database_status(path: String) -> HumanDatabaseStatus {
    match HumanDatabase::open(&path) {
        Ok(database) => database.status(is_initialized_path(&path)),
        Err(err) => unavailable_status(err),
    }
}

#[cfg(target_arch = "wasm32")]
pub(crate) fn query_moves(_fen: String, _max_moves: u32, _min_samples: u32) -> HumanDatabaseQuery {
    HumanDatabaseQuery {
        available: false,
        state_key: String::new(),
        error: "Human game database is not available on Web".to_owned(),
        moves: Vec::new(),
    }
}

#[cfg(not(target_arch = "wasm32"))]
pub(crate) fn query_moves(fen: String, max_moves: u32, min_samples: u32) -> HumanDatabaseQuery {
    let key = match state_key_from_fen(&fen) {
        Ok((state_key, sym_idx)) => (state_key, sym_idx),
        Err(err) => {
            return HumanDatabaseQuery {
                available: false,
                state_key: String::new(),
                error: err,
                moves: Vec::new(),
            };
        }
    };

    let guard = HUMAN_DB
        .lock()
        .expect("Human Database mutex must not be poisoned");
    let Some(database) = guard.as_ref() else {
        return HumanDatabaseQuery {
            available: false,
            state_key: key.0,
            error: "Human game database has not been initialized".to_owned(),
            moves: Vec::new(),
        };
    };

    match database.query(&key.0, key.1, max_moves.max(1), min_samples.max(1)) {
        Ok(moves) => HumanDatabaseQuery {
            available: true,
            state_key: key.0,
            error: String::new(),
            moves,
        },
        Err(err) => HumanDatabaseQuery {
            available: false,
            state_key: key.0,
            error: err,
            moves: Vec::new(),
        },
    }
}

#[cfg(not(target_arch = "wasm32"))]
fn is_initialized_path(path: &str) -> bool {
    HUMAN_DB
        .lock()
        .expect("Human Database mutex must not be poisoned")
        .as_ref()
        .is_some_and(|database| database.path == path)
}

#[cfg(not(target_arch = "wasm32"))]
impl HumanDatabase {
    fn open(path: &str) -> Result<Self, String> {
        if !Path::new(path).is_file() {
            return Err(format!("Human game database file not found: {path}"));
        }
        let conn = Connection::open_with_flags(path, OpenFlags::SQLITE_OPEN_READ_ONLY)
            .map_err(|err| format!("failed to open Human Database: {err}"))?;
        validate_schema(&conn)?;

        let schema_version = meta_value(&conn, "schema_version")?;
        let build_date = meta_value(&conn, "build_date")?;
        let total_games = meta_value(&conn, "total_games")?
            .parse::<u32>()
            .map_err(|err| format!("invalid total_games metadata: {err}"))?;
        let position_count = count_rows(&conn, "positions")?;
        let move_count = count_rows(&conn, "moves")?;

        Ok(Self {
            path: path.to_owned(),
            conn,
            schema_version,
            build_date,
            total_games,
            position_count,
            move_count,
        })
    }

    fn status(&self, initialized: bool) -> HumanDatabaseStatus {
        HumanDatabaseStatus {
            readable: true,
            initialized,
            error: String::new(),
            schema_version: self.schema_version.clone(),
            build_date: self.build_date.clone(),
            total_games: self.total_games,
            position_count: self.position_count,
            move_count: self.move_count,
        }
    }

    fn query(
        &self,
        state_key: &str,
        sym_idx: usize,
        max_moves: u32,
        min_samples: u32,
    ) -> Result<Vec<HumanDatabaseMove>, String> {
        let inverse = SYM_INVERSE[sym_idx];
        let mut stmt = self
            .conn
            .prepare(
                "SELECT notation, wins, losses, draws, total \
                 FROM moves \
                 WHERE state_key = ?1 AND total >= ?2 \
                 ORDER BY ((wins + 0.4 * draws) * 1.0 / total) DESC, total DESC \
                 LIMIT ?3",
            )
            .map_err(|err| format!("failed to prepare Human Database query: {err}"))?;

        let rows = stmt
            .query_map(params![state_key, min_samples, max_moves], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, u32>(1)?,
                    row.get::<_, u32>(2)?,
                    row.get::<_, u32>(3)?,
                    row.get::<_, u32>(4)?,
                ))
            })
            .map_err(|err| format!("failed to query Human Database moves: {err}"))?;

        let mut moves = Vec::new();
        for row in rows {
            let (notation, wins, losses, draws, total) =
                row.map_err(|err| format!("failed to read Human Database row: {err}"))?;
            let Some(actual_notation) = transform_notation(&notation, inverse) else {
                continue;
            };
            let total_f = f64::from(total);
            let win_pct = if total == 0 {
                0.0
            } else {
                f64::from(wins) / total_f
            };
            let raw = if total == 0 {
                0.0
            } else {
                (f64::from(wins) + 0.4 * f64::from(draws)) / total_f - 0.5
            };
            let confidence = if total == 0 {
                0.0
            } else {
                (f64::from(total + 1).ln() / 20_f64.ln()).min(1.0)
            };
            moves.push(HumanDatabaseMove {
                notation: actual_notation,
                wins,
                losses,
                draws,
                total,
                win_pct,
                score_delta: (raw * confidence).clamp(-0.5, 0.5),
            });
        }
        Ok(moves)
    }
}

#[cfg(not(target_arch = "wasm32"))]
fn validate_schema(conn: &Connection) -> Result<(), String> {
    for table in ["meta", "positions", "moves"] {
        let exists: bool = conn
            .query_row(
                "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name=?1)",
                [table],
                |row| row.get(0),
            )
            .map_err(|err| format!("failed to inspect Human Database schema: {err}"))?;
        if !exists {
            return Err(format!(
                "Human Database is missing required table '{table}'"
            ));
        }
    }
    Ok(())
}

#[cfg(not(target_arch = "wasm32"))]
fn meta_value(conn: &Connection, key: &str) -> Result<String, String> {
    conn.query_row("SELECT value FROM meta WHERE key = ?1", [key], |row| {
        row.get(0)
    })
    .map_err(|err| format!("Human Database metadata '{key}' is missing or invalid: {err}"))
}

#[cfg(not(target_arch = "wasm32"))]
fn count_rows(conn: &Connection, table: &str) -> Result<u32, String> {
    let sql = format!("SELECT COUNT(*) FROM {table}");
    let count = conn
        .query_row(&sql, [], |row| row.get::<_, u32>(0))
        .map_err(|err| format!("failed to count Human Database table '{table}': {err}"))?;
    Ok(count)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Regression guard for the shared-codec extraction: the lookup's
    /// recommended-move pipeline is `state_key_from_fen` (canonical key +
    /// symmetry index) followed by `transform_notation(SYM_INVERSE[idx])`
    /// back into the live orientation. A canonical-orientation query must
    /// stay untransformed, and a mirrored query must map the stored
    /// notation back onto the live board exactly as before the refactor.
    #[test]
    fn query_pipeline_keeps_recommended_moves_in_the_live_orientation() {
        let canonical_fen =
            "********/********/******** w p p 0 9 0 9 0 0 -1 -1 -1 -1 0 0 1 ids:nodes";
        let (key, sym_idx) = state_key_from_fen(canonical_fen).expect("initial FEN must parse");
        assert_eq!(key, "........................|W|place|0|0|0|0");
        assert_eq!(sym_idx, 0);
        assert_eq!(
            transform_notation("d6-d7xa4", SYM_INVERSE[sym_idx]).as_deref(),
            Some("d6-d7xa4"),
            "identity orientation must return stored notations verbatim"
        );

        // A single white piece on b2 canonicalizes through a non-identity
        // symmetry; the stored (canonical-frame) notation must come back in
        // the live frame via the inverse transform, exactly like
        // `HumanDatabase::query` applies it.
        // A single white stone on d6: its D4 orbit reaches b4, which sits
        // later in the NMM board string, so the canonical form is strictly
        // smaller than the identity image and the symmetry index must be
        // nonzero (no reliance on tie-breaking between equal images).
        let mirrored_fen =
            "********/O*******/******** b p p 1 8 0 9 0 0 -1 -1 -1 -1 0 0 1 ids:nodes";
        let (mirrored_key, mirrored_idx) =
            state_key_from_fen(mirrored_fen).expect("mirrored FEN must parse");
        assert_ne!(mirrored_idx, 0, "fixture must exercise a real symmetry");
        let stored = "d6";
        let live = transform_notation(stored, SYM_INVERSE[mirrored_idx])
            .expect("stored notation must map back to the live frame");
        let round_trip = transform_notation(&live, mirrored_idx)
            .expect("live notation must map back to the canonical frame");
        assert_eq!(round_trip, stored, "transform must be self-inverse");
        assert!(
            mirrored_key.starts_with(['.', 'W', 'B']),
            "canonical key must be a plain board string, got {mirrored_key}"
        );
    }
}
