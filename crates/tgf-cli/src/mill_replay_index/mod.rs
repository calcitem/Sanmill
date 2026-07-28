// SPDX-License-Identifier: AGPL-3.0-or-later
//! Parallel builder for the anonymised HumanDB replay sidecar.
//!
//! HumanDB deliberately stores aggregate position and move statistics rather
//! than complete game histories.  This module indexes the raw JSONL corpus so
//! a promising aggregate row can be traced back to its exact legal prefix.
//! Parsing and HumanDB D4 canonicalisation run on several Rust worker threads;
//! one bounded receiver owns SQLite writes.

use std::fs::{self, File};
use std::io::{BufRead, BufReader, Read};
use std::path::{Path, PathBuf};
use std::sync::mpsc::{self, SyncSender};
use std::thread;
use std::time::Instant;

use rusqlite::{Connection, params};
use serde::Deserialize;
use sha2::{Digest, Sha256};
use tgf_mill::human_db_codec::{canonical_board_str, transform_notation};

use crate::cli_args::parse_flag;

const SCHEMA_VERSION: &str = "1";
const STATE_KEY_MODEL: &str = "sector-corrected-v1";

#[derive(Clone, Debug)]
struct Config {
    games_dir: PathBuf,
    out: PathBuf,
    workers: usize,
    files_per_batch: usize,
    progress_every: usize,
    cache_mib: usize,
    max_files: usize,
}

#[derive(Debug, Deserialize)]
struct RawGame {
    source_type: String,
    moves: Vec<RawMove>,
}

#[derive(Debug, Deserialize)]
struct RawMove {
    #[serde(rename = "type")]
    move_type: String,
    notation: String,
    board_fen_before: String,
}

#[derive(Debug)]
struct GameRow {
    source_sha256: String,
    source_file: String,
    source_line: i64,
    logical_turn_count: i64,
}

#[derive(Debug)]
struct TurnRow {
    source_sha256: String,
    logical_ply: i64,
    notation: String,
    canonical_notation: Option<String>,
    board_fen: String,
    state_key: Option<String>,
    move_type: String,
    side_to_move: i64,
    placed_white: i64,
    placed_black: i64,
    white_on_board: i64,
    black_on_board: i64,
}

#[derive(Debug, Default)]
struct ParsedBatch {
    files: usize,
    games: Vec<GameRow>,
    turns: Vec<TurnRow>,
    invalid_game_records: usize,
    skipped_non_human_records: usize,
}

#[derive(Debug)]
struct CompactPosition {
    board: String,
    side_to_move: i64,
    turn_label: &'static str,
    placed_white: i64,
    placed_black: i64,
    white_on_board: i64,
    black_on_board: i64,
}

#[derive(Debug)]
struct BuildStatistics<'a> {
    source_root: &'a Path,
    build_date: &'a str,
    source_file_count: usize,
    game_count: i64,
    turn_count: i64,
    indexed_root_count: i64,
    duplicate_game_records: usize,
    invalid_game_records: usize,
    skipped_non_human_records: usize,
}

pub(crate) fn run(args: &[String]) {
    if let Err(error) = run_inner(args) {
        eprintln!("[human-replay-index] ERROR: {error}");
        std::process::exit(1);
    }
}

fn run_inner(args: &[String]) -> Result<(), String> {
    let games_dir = parse_flag(args, "--games-dir", String::new());
    let out = parse_flag(args, "--out", String::new());
    if games_dir.is_empty() || out.is_empty() {
        return Err("--games-dir PATH and --out PATH are required; example: \
             tgf mill replay-index --games-dir I:/data/human_games \
             --out I:/data/human_replay_index.sqlite"
            .to_owned());
    }

    let available_workers = thread::available_parallelism()
        .map(usize::from)
        .unwrap_or(1)
        .clamp(1, 8);
    let config = Config {
        games_dir: PathBuf::from(games_dir),
        out: PathBuf::from(out),
        workers: parse_flag(args, "--workers", available_workers),
        files_per_batch: parse_flag(args, "--files-per-batch", 64_usize),
        progress_every: parse_flag(args, "--progress-every", 5_000_usize),
        cache_mib: parse_flag(args, "--cache-mib", 256_usize),
        max_files: parse_flag(args, "--max-files", 0_usize),
    };
    validate_config(&config)?;
    build_index(&config)
}

fn validate_config(config: &Config) -> Result<(), String> {
    if config.workers == 0 {
        return Err("--workers must be positive".to_owned());
    }
    if config.files_per_batch == 0 {
        return Err("--files-per-batch must be positive".to_owned());
    }
    if config.progress_every < config.files_per_batch {
        return Err("--progress-every must be at least --files-per-batch".to_owned());
    }
    if config.cache_mib < 16 {
        return Err("--cache-mib must be at least 16".to_owned());
    }
    if !config.games_dir.is_dir() {
        return Err(format!(
            "source directory does not exist: {}",
            config.games_dir.display()
        ));
    }
    Ok(())
}

fn build_index(config: &Config) -> Result<(), String> {
    let mut files = Vec::new();
    collect_jsonl_files(&config.games_dir, &mut files)?;
    files.sort();
    if config.max_files > 0 {
        files.truncate(config.max_files);
    }
    if files.is_empty() {
        return Err("no JSONL source files were found".to_owned());
    }
    let source_file_count = files.len();

    let output = absolute_path(&config.out)?;
    let source_root = absolute_path(&config.games_dir)?;
    let building = append_suffix(&output, ".building")?;
    let documentation = documentation_path(&output)?;
    let documentation_building = append_suffix(&documentation, ".building")?;
    refuse_existing(&[
        (&output, "output database"),
        (&building, "partial database"),
        (&documentation, "output documentation"),
        (&documentation_building, "partial documentation"),
    ])?;
    if let Some(parent) = output.parent() {
        fs::create_dir_all(parent)
            .map_err(|error| format!("cannot create {}: {error}", parent.display()))?;
    }

    eprintln!(
        "[human-replay-index] source={} files={} workers={} batch={} out={}",
        source_root.display(),
        source_file_count,
        config.workers.min(source_file_count),
        config.files_per_batch,
        output.display()
    );

    let started = Instant::now();
    let mut connection = Connection::open(&building)
        .map_err(|error| format!("cannot create {}: {error}", building.display()))?;
    configure_connection(&connection, config.cache_mib)?;
    create_schema(&connection)?;

    let worker_count = config.workers.min(source_file_count);
    let mut partitions = vec![Vec::new(); worker_count];
    for (index, path) in files.into_iter().enumerate() {
        partitions[index % worker_count].push(path);
    }
    let (sender, receiver) = mpsc::sync_channel(worker_count * 2);
    let handles = partitions
        .into_iter()
        .map(|paths| {
            let root = source_root.clone();
            let sender = sender.clone();
            let files_per_batch = config.files_per_batch;
            thread::spawn(move || worker(paths, root, files_per_batch, sender))
        })
        .collect::<Vec<_>>();
    drop(sender);

    let transaction = connection
        .transaction()
        .map_err(|error| format!("cannot start SQLite transaction: {error}"))?;
    let mut processed_files = 0_usize;
    let mut parsed_games = 0_usize;
    let mut parsed_turns = 0_usize;
    let mut invalid_game_records = 0_usize;
    let mut skipped_non_human_records = 0_usize;
    let mut next_progress = config.progress_every;
    {
        let mut insert_game = transaction
            .prepare(
                "INSERT OR IGNORE INTO games (\
                 source_sha256, source_file, source_line, logical_turn_count\
                 ) VALUES (?1, ?2, ?3, ?4)",
            )
            .map_err(|error| format!("cannot prepare games insertion: {error}"))?;
        let mut insert_turn = transaction
            .prepare(
                "INSERT OR IGNORE INTO turns (\
                 source_sha256, logical_ply, notation, canonical_notation, \
                 board_fen, state_key, move_type, side_to_move, placed_white, \
                 placed_black, white_on_board, black_on_board\
                 ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)",
            )
            .map_err(|error| format!("cannot prepare turns insertion: {error}"))?;

        for batch in receiver {
            for game in &batch.games {
                insert_game
                    .execute(params![
                        game.source_sha256,
                        game.source_file,
                        game.source_line,
                        game.logical_turn_count,
                    ])
                    .map_err(|error| format!("cannot insert game row: {error}"))?;
            }
            for turn in &batch.turns {
                insert_turn
                    .execute(params![
                        turn.source_sha256,
                        turn.logical_ply,
                        turn.notation,
                        turn.canonical_notation,
                        turn.board_fen,
                        turn.state_key,
                        turn.move_type,
                        turn.side_to_move,
                        turn.placed_white,
                        turn.placed_black,
                        turn.white_on_board,
                        turn.black_on_board,
                    ])
                    .map_err(|error| format!("cannot insert turn row: {error}"))?;
            }
            processed_files += batch.files;
            parsed_games += batch.games.len();
            parsed_turns += batch.turns.len();
            invalid_game_records += batch.invalid_game_records;
            skipped_non_human_records += batch.skipped_non_human_records;
            if processed_files >= next_progress || processed_files == source_file_count {
                let elapsed = started.elapsed().as_secs_f64().max(0.001);
                eprintln!(
                    "[human-replay-index] files={} parsed-games={} parsed-turns={} \
                     rate={:.0} files/s",
                    processed_files,
                    parsed_games,
                    parsed_turns,
                    processed_files as f64 / elapsed
                );
                while next_progress <= processed_files {
                    next_progress = next_progress.saturating_add(config.progress_every);
                }
            }
        }
    }
    transaction
        .commit()
        .map_err(|error| format!("cannot commit replay rows: {error}"))?;

    for handle in handles {
        match handle.join() {
            Ok(Ok(())) => {}
            Ok(Err(error)) => return Err(error),
            Err(_) => return Err("a replay-index worker panicked".to_owned()),
        }
    }

    let game_count: i64 = connection
        .query_row("SELECT COUNT(*) FROM games", [], |row| row.get(0))
        .map_err(|error| format!("cannot count indexed games: {error}"))?;
    let turn_count: i64 = connection
        .query_row("SELECT COUNT(*) FROM turns", [], |row| row.get(0))
        .map_err(|error| format!("cannot count indexed turns: {error}"))?;
    let indexed_root_count: i64 = connection
        .query_row(
            "SELECT COUNT(*) FROM turns WHERE state_key IS NOT NULL",
            [],
            |row| row.get(0),
        )
        .map_err(|error| format!("cannot count indexed roots: {error}"))?;
    let duplicate_game_records = parsed_games.saturating_sub(game_count as usize);
    let build_date = sqlite_utc_now(&connection)?;
    let statistics = BuildStatistics {
        source_root: &source_root,
        build_date: &build_date,
        source_file_count: processed_files,
        game_count,
        turn_count,
        indexed_root_count,
        duplicate_game_records,
        invalid_game_records,
        skipped_non_human_records,
    };
    insert_metadata(&mut connection, &statistics)?;

    eprintln!("[human-replay-index] creating lookup indexes");
    connection
        .execute_batch(
            "CREATE INDEX turns_by_state_and_move \
                 ON turns(state_key, canonical_notation) \
                 WHERE state_key IS NOT NULL;\
             CREATE INDEX turns_by_material_and_ply \
                 ON turns(logical_ply, white_on_board, black_on_board) \
                 WHERE state_key IS NOT NULL;\
             ANALYZE;",
        )
        .map_err(|error| format!("cannot create replay lookup indexes: {error}"))?;
    let integrity: String = connection
        .query_row("PRAGMA integrity_check", [], |row| row.get(0))
        .map_err(|error| format!("cannot run SQLite integrity_check: {error}"))?;
    if integrity != "ok" {
        return Err(format!("SQLite integrity_check returned {integrity:?}"));
    }
    connection
        .close()
        .map_err(|(_, error)| format!("cannot close replay index: {error}"))?;

    let database_sha256 = sha256_file(&building)?;
    let readme = render_readme(&output, &database_sha256, &statistics, config);
    fs::write(&documentation_building, readme)
        .map_err(|error| format!("cannot write {}: {error}", documentation_building.display()))?;
    fs::rename(&building, &output).map_err(|error| {
        format!(
            "cannot publish {} as {}: {error}",
            building.display(),
            output.display()
        )
    })?;
    fs::rename(&documentation_building, &documentation).map_err(|error| {
        format!(
            "cannot publish {} as {}: {error}",
            documentation_building.display(),
            documentation.display()
        )
    })?;

    eprintln!(
        "[human-replay-index] done files={} games={} turns={} indexed-roots={} \
         seconds={:.1} out={} docs={}",
        processed_files,
        game_count,
        turn_count,
        indexed_root_count,
        started.elapsed().as_secs_f64(),
        output.display(),
        documentation.display()
    );
    Ok(())
}

fn collect_jsonl_files(directory: &Path, output: &mut Vec<PathBuf>) -> Result<(), String> {
    let entries = fs::read_dir(directory)
        .map_err(|error| format!("cannot read {}: {error}", directory.display()))?;
    for entry in entries {
        let entry =
            entry.map_err(|error| format!("cannot read {} entry: {error}", directory.display()))?;
        let file_type = entry
            .file_type()
            .map_err(|error| format!("cannot inspect {}: {error}", entry.path().display()))?;
        if file_type.is_dir() {
            collect_jsonl_files(&entry.path(), output)?;
        } else if file_type.is_file()
            && entry
                .path()
                .extension()
                .is_some_and(|extension| extension.eq_ignore_ascii_case("jsonl"))
        {
            output.push(entry.path());
        }
    }
    Ok(())
}

fn worker(
    paths: Vec<PathBuf>,
    source_root: PathBuf,
    files_per_batch: usize,
    sender: SyncSender<ParsedBatch>,
) -> Result<(), String> {
    let mut batch = ParsedBatch::default();
    for path in paths {
        parse_file(&path, &source_root, &mut batch)?;
        batch.files += 1;
        if batch.files >= files_per_batch {
            sender
                .send(std::mem::take(&mut batch))
                .map_err(|_| "SQLite writer stopped before workers completed".to_owned())?;
        }
    }
    if batch.files > 0 {
        sender
            .send(batch)
            .map_err(|_| "SQLite writer stopped before workers completed".to_owned())?;
    }
    Ok(())
}

fn parse_file(path: &Path, source_root: &Path, batch: &mut ParsedBatch) -> Result<(), String> {
    let file =
        File::open(path).map_err(|error| format!("cannot open {}: {error}", path.display()))?;
    let relative = path
        .strip_prefix(source_root)
        .map_err(|error| format!("cannot relativise {}: {error}", path.display()))?
        .to_string_lossy()
        .replace('\\', "/");
    let mut reader = BufReader::new(file);
    let mut raw_line = Vec::new();
    let mut source_line = 0_i64;
    loop {
        raw_line.clear();
        let read = reader
            .read_until(b'\n', &mut raw_line)
            .map_err(|error| format!("cannot read {}: {error}", path.display()))?;
        if read == 0 {
            break;
        }
        source_line += 1;
        while raw_line
            .last()
            .is_some_and(|byte| matches!(byte, b'\r' | b'\n'))
        {
            raw_line.pop();
        }
        if raw_line.iter().all(u8::is_ascii_whitespace) {
            continue;
        }
        let game = match serde_json::from_slice::<RawGame>(&raw_line) {
            Ok(game) => game,
            Err(_) => {
                batch.invalid_game_records += 1;
                continue;
            }
        };
        if game.source_type != "human_vs_human" {
            batch.skipped_non_human_records += 1;
            continue;
        }
        let source_sha256 = sha256_bytes(&raw_line);
        let mut turns = Vec::with_capacity(game.moves.len());
        let mut valid = true;
        for (index, raw_turn) in game.moves.into_iter().enumerate() {
            match turn_row(&source_sha256, index + 1, raw_turn) {
                Ok(turn) => turns.push(turn),
                Err(_) => {
                    valid = false;
                    break;
                }
            }
        }
        if !valid {
            batch.invalid_game_records += 1;
            continue;
        }
        batch.games.push(GameRow {
            source_sha256: source_sha256.clone(),
            source_file: relative.clone(),
            source_line,
            logical_turn_count: turns.len() as i64,
        });
        batch.turns.extend(turns);
    }
    Ok(())
}

fn turn_row(source_sha256: &str, logical_ply: usize, raw_turn: RawMove) -> Result<TurnRow, String> {
    let position = parse_compact_position(&raw_turn.board_fen_before)?;
    let movement_root =
        raw_turn.move_type == "move" && position.placed_white == 9 && position.placed_black == 9;
    let (state_key, canonical_notation) = if movement_root {
        let (canonical, symmetry) = canonical_board_str(&position.board);
        let side_on_board = if position.side_to_move == 0 {
            position.white_on_board
        } else {
            position.black_on_board
        };
        let phase = if side_on_board <= 3 { "fly" } else { "move" };
        let state_key = format!(
            "{canonical}|{}|{phase}|{}|{}|{}|{}",
            position.turn_label,
            position.placed_white,
            position.placed_black,
            position.white_on_board,
            position.black_on_board
        );
        let notation = transform_notation(&raw_turn.notation, symmetry)
            .ok_or_else(|| format!("invalid HumanDB notation {}", raw_turn.notation))?;
        (Some(state_key), Some(notation))
    } else {
        (None, None)
    };
    Ok(TurnRow {
        source_sha256: source_sha256.to_owned(),
        logical_ply: logical_ply as i64,
        notation: raw_turn.notation,
        canonical_notation,
        board_fen: raw_turn.board_fen_before,
        state_key,
        move_type: raw_turn.move_type,
        side_to_move: position.side_to_move,
        placed_white: position.placed_white,
        placed_black: position.placed_black,
        white_on_board: position.white_on_board,
        black_on_board: position.black_on_board,
    })
}

fn parse_compact_position(value: &str) -> Result<CompactPosition, String> {
    let fields = value.split('|').collect::<Vec<_>>();
    if fields.len() != 4 {
        return Err("compact HumanDB FEN must contain four fields".to_owned());
    }
    let board = fields[0];
    if board.len() != 24
        || !board
            .bytes()
            .all(|piece| matches!(piece, b'.' | b'W' | b'B'))
    {
        return Err("compact HumanDB FEN has an invalid board".to_owned());
    }
    let (side_to_move, turn_label) = match fields[1] {
        "W" => (0, "W"),
        "B" => (1, "B"),
        other => return Err(format!("invalid compact HumanDB side {other:?}")),
    };
    let placed_white = fields[2]
        .parse::<i64>()
        .map_err(|_| "invalid compact HumanDB White placement count".to_owned())?;
    let placed_black = fields[3]
        .parse::<i64>()
        .map_err(|_| "invalid compact HumanDB Black placement count".to_owned())?;
    if !(0..=9).contains(&placed_white) || !(0..=9).contains(&placed_black) {
        return Err("compact HumanDB placement counts must be in 0..=9".to_owned());
    }
    Ok(CompactPosition {
        board: board.to_owned(),
        side_to_move,
        turn_label,
        placed_white,
        placed_black,
        white_on_board: board.bytes().filter(|piece| *piece == b'W').count() as i64,
        black_on_board: board.bytes().filter(|piece| *piece == b'B').count() as i64,
    })
}

fn configure_connection(connection: &Connection, cache_mib: usize) -> Result<(), String> {
    connection
        .execute_batch(&format!(
            "PRAGMA foreign_keys = ON;\
             PRAGMA journal_mode = OFF;\
             PRAGMA synchronous = OFF;\
             PRAGMA temp_store = MEMORY;\
             PRAGMA cache_size = -{};",
            cache_mib * 1024
        ))
        .map_err(|error| format!("cannot configure SQLite build connection: {error}"))
}

fn create_schema(connection: &Connection) -> Result<(), String> {
    connection
        .execute_batch(
            "CREATE TABLE meta (\
                 key TEXT PRIMARY KEY,\
                 value TEXT NOT NULL\
             ) WITHOUT ROWID;\
             CREATE TABLE games (\
                 source_sha256 TEXT PRIMARY KEY,\
                 source_file TEXT NOT NULL,\
                 source_line INTEGER NOT NULL,\
                 logical_turn_count INTEGER NOT NULL\
             ) WITHOUT ROWID;\
             CREATE TABLE turns (\
                 source_sha256 TEXT NOT NULL,\
                 logical_ply INTEGER NOT NULL,\
                 notation TEXT NOT NULL,\
                 canonical_notation TEXT,\
                 board_fen TEXT NOT NULL,\
                 state_key TEXT,\
                 move_type TEXT NOT NULL,\
                 side_to_move INTEGER NOT NULL CHECK (side_to_move IN (0, 1)),\
                 placed_white INTEGER NOT NULL,\
                 placed_black INTEGER NOT NULL,\
                 white_on_board INTEGER NOT NULL,\
                 black_on_board INTEGER NOT NULL,\
                 PRIMARY KEY (source_sha256, logical_ply),\
                 FOREIGN KEY (source_sha256) REFERENCES games(source_sha256)\
             ) WITHOUT ROWID;",
        )
        .map_err(|error| format!("cannot create replay-index schema: {error}"))
}

fn insert_metadata(
    connection: &mut Connection,
    statistics: &BuildStatistics<'_>,
) -> Result<(), String> {
    let transaction = connection
        .transaction()
        .map_err(|error| format!("cannot start metadata transaction: {error}"))?;
    {
        let mut statement = transaction
            .prepare("INSERT INTO meta (key, value) VALUES (?1, ?2)")
            .map_err(|error| format!("cannot prepare metadata insertion: {error}"))?;
        let entries = [
            ("schema_version", SCHEMA_VERSION.to_owned()),
            ("build_date", statistics.build_date.to_owned()),
            ("source_root", statistics.source_root.display().to_string()),
            (
                "source_file_count",
                statistics.source_file_count.to_string(),
            ),
            ("game_count", statistics.game_count.to_string()),
            ("turn_count", statistics.turn_count.to_string()),
            (
                "indexed_root_count",
                statistics.indexed_root_count.to_string(),
            ),
            (
                "duplicate_game_records",
                statistics.duplicate_game_records.to_string(),
            ),
            (
                "invalid_game_records",
                statistics.invalid_game_records.to_string(),
            ),
            (
                "skipped_non_human_records",
                statistics.skipped_non_human_records.to_string(),
            ),
            ("anonymised", "true".to_owned()),
            ("state_key_model", STATE_KEY_MODEL.to_owned()),
        ];
        for (key, value) in entries {
            statement
                .execute(params![key, value])
                .map_err(|error| format!("cannot insert metadata {key}: {error}"))?;
        }
    }
    transaction
        .commit()
        .map_err(|error| format!("cannot commit replay metadata: {error}"))
}

fn sqlite_utc_now(connection: &Connection) -> Result<String, String> {
    connection
        .query_row("SELECT strftime('%Y-%m-%dT%H:%M:%SZ', 'now')", [], |row| {
            row.get(0)
        })
        .map_err(|error| format!("cannot obtain SQLite UTC timestamp: {error}"))
}

fn render_readme(
    output: &Path,
    database_sha256: &str,
    statistics: &BuildStatistics<'_>,
    config: &Config,
) -> String {
    format!(
        r#"# Human Replay Index

## Purpose

`{database_name}` is an anonymised, reproducible replay sidecar for the
HumanDB source corpus. It maps aggregate HumanDB position/move rows back to
complete game prefixes without rescanning the JSONL corpus.

This is a **candidate index**, not a game-theoretic oracle. Rust/TGF must
replay every selected history and Perfect DB must independently certify its
W/D/L and distance result before publication.

## Provenance

- Built at (UTC): `{build_date}`
- Source root: `{source_root}`
- Source JSONL files: `{source_file_count}`
- Anonymised games: `{game_count}`
- Logical turns: `{turn_count}`
- Searchable movement roots: `{indexed_root_count}`
- Duplicate game records ignored: `{duplicate_game_records}`
- Invalid game records skipped: `{invalid_game_records}`
- Database SHA-256: `{database_sha256}`
- Schema version: `{SCHEMA_VERSION}`
- HumanDB state-key model: `{STATE_KEY_MODEL}`

Player names and account identifiers are never deserialised into the index.
A source game is represented by the SHA-256 of its exact JSONL row, its
relative source file and its line number.

## Database Roles

- **HumanDB** stores aggregate positions, move frequencies and Malom priors.
- **Human Replay Index** stores anonymised ordered histories for provenance.
- **Perfect DB** supplies the final mathematical proof used for publication.

## Schema

### `meta`

Key/value build metadata, including the schema, source, counts and privacy
model above.

### `games`

| Column | Type | Meaning |
| --- | --- | --- |
| `source_sha256` | `TEXT` | Exact source-row SHA-256; primary key |
| `source_file` | `TEXT` | Path relative to the source root |
| `source_line` | `INTEGER` | One-based JSONL line |
| `logical_turn_count` | `INTEGER` | Number of complete logical turns |

### `turns`

| Column | Type | Meaning |
| --- | --- | --- |
| `source_sha256` | `TEXT` | Parent game |
| `logical_ply` | `INTEGER` | One-based complete-turn number |
| `notation` | `TEXT` | Recorded Sanmill full-turn notation |
| `canonical_notation` | `TEXT` | HumanDB D4-frame notation; `NULL` before movement |
| `board_fen` | `TEXT` | Compact position immediately before the turn |
| `state_key` | `TEXT` | HumanDB-compatible key; `NULL` before movement |
| `move_type` | `TEXT` | Source move type |
| `side_to_move` | `INTEGER` | `0` White, `1` Black |
| `placed_white`, `placed_black` | `INTEGER` | Pieces placed so far |
| `white_on_board`, `black_on_board` | `INTEGER` | Current material |

The primary key is (`source_sha256`, `logical_ply`). Lookup indexes cover
(`state_key`, `canonical_notation`) and movement-root material/ply filters.

## Symmetry

HumanDB joins use its eight D4 symmetries. Sanmill's additional outer/inner
ring swap is applied only at puzzle export, yielding 16 presentation
transforms without duplicating replay rows. Puzzle deduplication remains
canonical under all 16 transforms.

## Example Query

```sql
SELECT r.source_sha256, r.logical_ply, r.notation, p.malom_dtw
FROM turns AS r
JOIN human.positions AS p ON p.state_key = r.state_key
JOIN human.moves AS m
  ON m.state_key = r.state_key
 AND m.notation = r.canonical_notation
WHERE p.malom_wdl = 'W'
  AND p.canonical_winning_move IS NOT NULL
  AND r.canonical_notation <> p.canonical_winning_move
  AND m.malom_wdl_after IN ('D', 'W');
```

The HumanDB result is only a mining prior; the production Rust puzzle
generator performs the final replay and Perfect DB check.

## Rebuild

```powershell
cargo run -p tgf-cli --release -- mill replay-index `
  --games-dir "{source_root}" `
  --out "{output}" `
  --workers {workers} `
  --files-per-batch {files_per_batch}
```

The builder uses bounded parallel workers and one SQLite writer, validates
row counts and `PRAGMA integrity_check`, and publishes the database and this
README only after both have been prepared. Existing outputs are never
overwritten automatically. The version-controlled specification is
`docs/HUMAN_REPLAY_INDEX.md`.
"#,
        database_name = output
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("human_replay_index.sqlite"),
        build_date = statistics.build_date,
        source_root = statistics.source_root.display(),
        source_file_count = statistics.source_file_count,
        game_count = statistics.game_count,
        turn_count = statistics.turn_count,
        indexed_root_count = statistics.indexed_root_count,
        duplicate_game_records = statistics.duplicate_game_records,
        invalid_game_records = statistics.invalid_game_records,
        database_sha256 = database_sha256,
        output = output.display(),
        workers = config.workers,
        files_per_batch = config.files_per_batch,
    )
}

fn refuse_existing(paths: &[(&Path, &str)]) -> Result<(), String> {
    for (path, description) in paths {
        if path.exists() {
            return Err(format!(
                "{description} already exists at {}; inspect or remove it explicitly",
                path.display()
            ));
        }
    }
    Ok(())
}

fn absolute_path(path: &Path) -> Result<PathBuf, String> {
    if path.is_absolute() {
        Ok(path.to_owned())
    } else {
        std::env::current_dir()
            .map(|directory| directory.join(path))
            .map_err(|error| format!("cannot resolve {}: {error}", path.display()))
    }
}

fn append_suffix(path: &Path, suffix: &str) -> Result<PathBuf, String> {
    let file_name = path
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or_else(|| format!("output path has no UTF-8 file name: {}", path.display()))?;
    Ok(path.with_file_name(format!("{file_name}{suffix}")))
}

fn documentation_path(output: &Path) -> Result<PathBuf, String> {
    let stem = output
        .file_stem()
        .and_then(|name| name.to_str())
        .ok_or_else(|| format!("output path has no UTF-8 stem: {}", output.display()))?;
    Ok(output.with_file_name(format!("{stem}.README.md")))
}

fn sha256_bytes(bytes: &[u8]) -> String {
    hex_lower(Sha256::digest(bytes))
}

fn sha256_file(path: &Path) -> Result<String, String> {
    let mut file =
        File::open(path).map_err(|error| format!("cannot hash {}: {error}", path.display()))?;
    let mut hash = Sha256::new();
    let mut buffer = vec![0_u8; 1024 * 1024];
    loop {
        let read = file
            .read(&mut buffer)
            .map_err(|error| format!("cannot hash {}: {error}", path.display()))?;
        if read == 0 {
            break;
        }
        hash.update(&buffer[..read]);
    }
    Ok(hex_lower(hash.finalize()))
}

fn hex_lower(bytes: impl AsRef<[u8]>) -> String {
    let bytes = bytes.as_ref();
    let mut result = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        use std::fmt::Write as _;
        write!(&mut result, "{byte:02x}").expect("writing into String cannot fail");
    }
    result
}

#[cfg(test)]
mod tests;
