// SPDX-License-Identifier: AGPL-3.0-or-later

use std::time::{SystemTime, UNIX_EPOCH};

use super::*;

struct TempFixture {
    root: PathBuf,
}

impl TempFixture {
    fn new() -> Self {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock must be after the Unix epoch")
            .as_nanos();
        let root = std::env::temp_dir().join(format!(
            "sanmill-human-replay-index-{}-{nonce}",
            std::process::id()
        ));
        fs::create_dir_all(&root).expect("temporary test directory must be creatable");
        Self { root }
    }
}

impl Drop for TempFixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.root);
    }
}

#[test]
fn movement_turn_matches_python_humandb_canonicalisation() {
    let turn = turn_row(
        "0".repeat(64).as_str(),
        19,
        RawMove {
            move_type: "move".to_owned(),
            notation: "a7-d7".to_owned(),
            board_fen_before: "W..B..W..B..W..B..W..B..|W|9|9".to_owned(),
        },
    )
    .expect("valid movement turn");

    assert_eq!(
        turn.state_key.as_deref(),
        Some("..W.W..B.B.B..W.W....B..|W|move|9|9|4|4")
    );
    assert_eq!(turn.canonical_notation.as_deref(), Some("g7-d7"));
}

#[test]
fn opening_turn_is_replayable_but_not_added_to_lookup_index() {
    let turn = turn_row(
        "0".repeat(64).as_str(),
        1,
        RawMove {
            move_type: "move".to_owned(),
            notation: "a7".to_owned(),
            board_fen_before: "........................|W|0|0".to_owned(),
        },
    )
    .expect("valid opening turn");

    assert_eq!(turn.notation, "a7");
    assert!(turn.state_key.is_none());
    assert!(turn.canonical_notation.is_none());
}

#[test]
fn builder_creates_anonymised_database_and_colocated_readme() {
    let fixture = TempFixture::new();
    let games_dir = fixture.root.join("games");
    fs::create_dir_all(&games_dir).expect("games directory");
    let source = concat!(
        r#"{"source_type":"human_vs_human","white_player":"private-player","#,
        r#""black_player":"another-private-player","moves":["#,
        r#"{"type":"move","notation":"a7","board_fen_before":"........................|W|0|0"},"#,
        r#"{"type":"move","notation":"a7-d7","board_fen_before":"W..B..W..B..W..B..W..B..|W|9|9"}]}"#
    );
    fs::write(games_dir.join("sample.jsonl"), format!("{source}\n")).expect("source fixture");
    let output = fixture.root.join("human_replay_index.sqlite");
    let config = Config {
        games_dir,
        out: output.clone(),
        workers: 2,
        files_per_batch: 1,
        progress_every: 1,
        cache_mib: 16,
        max_files: 0,
    };

    build_index(&config).expect("replay index must build");

    let connection =
        Connection::open_with_flags(&output, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY)
            .expect("built database must open read-only");
    let game_count: i64 = connection
        .query_row("SELECT COUNT(*) FROM games", [], |row| row.get(0))
        .expect("game count");
    let turn_count: i64 = connection
        .query_row("SELECT COUNT(*) FROM turns", [], |row| row.get(0))
        .expect("turn count");
    let indexed_count: i64 = connection
        .query_row(
            "SELECT COUNT(*) FROM turns WHERE state_key IS NOT NULL",
            [],
            |row| row.get(0),
        )
        .expect("indexed-root count");
    let stored_sha256: String = connection
        .query_row("SELECT source_sha256 FROM games", [], |row| row.get(0))
        .expect("source hash");
    assert_eq!(game_count, 1);
    assert_eq!(turn_count, 2);
    assert_eq!(indexed_count, 1);
    assert_eq!(stored_sha256, sha256_bytes(source.as_bytes()));
    drop(connection);

    let database_bytes = fs::read(&output).expect("database bytes");
    assert!(
        !database_bytes
            .windows(b"private-player".len())
            .any(|window| window == b"private-player"),
        "player names must never enter the replay index"
    );
    let readme_path = documentation_path(&output).expect("README path");
    let readme = fs::read_to_string(readme_path).expect("co-located README");
    assert!(readme.contains("Schema version: `1`"));
    assert!(readme.contains("Database SHA-256: `"));
    assert!(!readme.contains("private-player"));
}
