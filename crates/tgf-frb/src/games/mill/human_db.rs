// SPDX-License-Identifier: GPL-3.0-or-later
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
use tgf_mill::{MillPhase, MillRules, MillVariantOptions};

#[cfg(not(target_arch = "wasm32"))]
static HUMAN_DB: Lazy<Mutex<Option<HumanDatabase>>> = Lazy::new(|| Mutex::new(None));

const NMM_POSITION_ORDER_NODES: [usize; 24] = [
    23, 16, 17, 18, 19, 20, 21, 22, // outer ring
    15, 8, 9, 10, 11, 12, 13, 14, // middle ring
    7, 0, 1, 2, 3, 4, 5, 6, // inner ring
];

const NMM_POSITIONS: [&str; 24] = [
    "a7", "d7", "g7", "g4", "g1", "d1", "a1", "a4", "b6", "d6", "f6", "f4", "f2", "d2", "b2", "b4",
    "c5", "d5", "e5", "e4", "e3", "d3", "c3", "c4",
];

const POSITION_COORDS: [(i8, i8); 24] = [
    (-3, 3),
    (0, 3),
    (3, 3),
    (3, 0),
    (3, -3),
    (0, -3),
    (-3, -3),
    (-3, 0),
    (-2, 2),
    (0, 2),
    (2, 2),
    (2, 0),
    (2, -2),
    (0, -2),
    (-2, -2),
    (-2, 0),
    (-1, 1),
    (0, 1),
    (1, 1),
    (1, 0),
    (1, -1),
    (0, -1),
    (-1, -1),
    (-1, 0),
];

const SYMMETRIES: [(i8, i8, i8, i8); 8] = [
    (1, 0, 0, 1),
    (0, -1, 1, 0),
    (-1, 0, 0, -1),
    (0, 1, -1, 0),
    (-1, 0, 0, 1),
    (1, 0, 0, -1),
    (0, 1, 1, 0),
    (0, -1, -1, 0),
];

const SYM_INVERSE: [usize; 8] = [0, 3, 2, 1, 4, 5, 6, 7];

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

fn state_key_from_fen(fen: &str) -> Result<(String, usize), String> {
    let fields = fen.split_whitespace().collect::<Vec<_>>();
    if fields.len() < 8 {
        return Err("Mill FEN must contain at least 8 fields".to_owned());
    }
    if fields[1] != "w" && fields[1] != "b" {
        return Err(format!("invalid side-to-move in Mill FEN: {}", fields[1]));
    }

    let rules = MillRules::new(MillVariantOptions::default());
    let state = rules.set_from_fen(fen)?;
    let pieces_in_hand = state.pieces_in_hand();
    let pieces_on_board = state.pieces_on_board();

    for (side, in_hand) in pieces_in_hand.iter().enumerate() {
        assert!(
            *in_hand <= 9,
            "Human Database supports standard Nine Men's Morris hand counts only"
        );
        assert!(
            pieces_on_board[side] + *in_hand <= 9,
            "Human Database supports standard Nine Men's Morris piece totals only"
        );
    }

    let board24 = nmm_board24(state.board());
    let (canonical, sym_idx) = canonical_board_str(&board24);
    let turn = if fields[1] == "w" { "W" } else { "B" };
    let side = if fields[1] == "w" { 0 } else { 1 };
    let phase = phase_for_side(state.phase(), pieces_in_hand[side], pieces_on_board[side]);
    let placed_w = 9_u8 - pieces_in_hand[0];
    let placed_b = 9_u8 - pieces_in_hand[1];

    Ok((
        format!(
            "{canonical}|{turn}|{phase}|{placed_w}|{placed_b}|{}|{}",
            pieces_on_board[0], pieces_on_board[1],
        ),
        sym_idx,
    ))
}

fn phase_for_side(phase: MillPhase, pieces_in_hand: u8, pieces_on_board: u8) -> &'static str {
    if phase == MillPhase::Placing || pieces_in_hand > 0 {
        "place"
    } else if pieces_on_board <= 3 {
        "fly"
    } else {
        "move"
    }
}

fn nmm_board24(board: &[i8; 24]) -> String {
    NMM_POSITION_ORDER_NODES
        .iter()
        .map(|&node| match board[node] {
            1 => 'W',
            2 => 'B',
            _ => '.',
        })
        .collect()
}

fn canonical_board_str(board24: &str) -> (String, usize) {
    assert!(
        board24.len() == 24,
        "Human Database canonicalization requires a 24-character board"
    );
    let mut best = board24.to_owned();
    let mut best_idx = 0;
    for sym_idx in 1..SYMMETRIES.len() {
        let transformed =
            apply_board_sym(board24, sym_idx).expect("Mill D4 transform must stay on board");
        if transformed < best {
            best = transformed;
            best_idx = sym_idx;
        }
    }
    (best, best_idx)
}

fn apply_board_sym(board24: &str, sym_idx: usize) -> Option<String> {
    let chars = board24.chars().collect::<Vec<_>>();
    let mut result = ['?'; 24];
    for (old_idx, ch) in chars.into_iter().enumerate() {
        let new_idx = transform_index(old_idx, sym_idx)?;
        result[new_idx] = ch;
    }
    Some(result.iter().collect())
}

fn transform_notation(notation: &str, sym_idx: usize) -> Option<String> {
    if sym_idx == 0 {
        return Some(notation.to_owned());
    }

    let (base, capture) = match notation.split_once('x') {
        Some((base, capture)) => (base, Some(capture)),
        None => (notation, None),
    };
    let capture_suffix = match capture {
        Some(pos) => format!("x{}", transform_pos(pos, sym_idx)?),
        None => String::new(),
    };

    if let Some((from, to)) = base.split_once('-') {
        return Some(format!(
            "{}-{}{}",
            transform_pos(from, sym_idx)?,
            transform_pos(to, sym_idx)?,
            capture_suffix,
        ));
    }
    Some(format!(
        "{}{}",
        transform_pos(base, sym_idx)?,
        capture_suffix
    ))
}

fn transform_pos(pos: &str, sym_idx: usize) -> Option<&'static str> {
    let idx = position_index(pos)?;
    let next = transform_index(idx, sym_idx)?;
    Some(NMM_POSITIONS[next])
}

fn transform_index(idx: usize, sym_idx: usize) -> Option<usize> {
    let (x, y) = POSITION_COORDS[idx];
    let (a, b, c, d) = SYMMETRIES[sym_idx];
    position_index_from_coords((a * x + b * y, c * x + d * y))
}

fn position_index(pos: &str) -> Option<usize> {
    NMM_POSITIONS.iter().position(|candidate| *candidate == pos)
}

fn position_index_from_coords(coords: (i8, i8)) -> Option<usize> {
    POSITION_COORDS
        .iter()
        .position(|candidate| *candidate == coords)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_board_key_matches_human_db_builder() {
        let fen = "********/********/******** w p p 0 9 0 9 0 0 -1 -1 -1 -1 0 0 1 ids:nodes";
        let (key, sym_idx) = state_key_from_fen(fen).expect("initial FEN must parse");

        assert_eq!(key, "........................|W|place|0|0|0|0");
        assert_eq!(sym_idx, 0);
    }

    #[test]
    fn node_order_exports_nmm_outer_middle_inner_board_string() {
        let fen = "********/@***O***/******** w p p 1 8 1 8 0 0 -1 -1 -1 -1 0 0 2 ids:nodes";
        let rules = MillRules::new(MillVariantOptions::default());
        let state = rules.set_from_fen(fen).expect("fixture FEN must parse");

        assert_eq!(nmm_board24(state.board()), ".........B...W..........");
    }

    #[test]
    fn notation_transform_handles_move_with_capture() {
        assert_eq!(
            transform_notation("d6-d7xa4", 2).as_deref(),
            Some("d2-d1xg4"),
        );
        assert_eq!(
            transform_notation("d2-d1xg4", SYM_INVERSE[2]).as_deref(),
            Some("d6-d7xa4"),
        );
    }
}
