// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};

use rusqlite::{Connection, params};
use serde_json::{Value, json};

const INITIAL_BOOK_REQUEST: &str = r#"{"operation":"query_book","protocol_version":1,"request_id":"cross-process","position":{"rule":"nmm","initial":"startpos","history_origin":"game_start","actions":[]}}"#;
static FIXTURE_COUNTER: AtomicUsize = AtomicUsize::new(0);

struct FixtureDirectory {
    root: PathBuf,
}

impl FixtureDirectory {
    fn path(&self, name: &str) -> PathBuf {
        self.root.join(name)
    }
}

impl Drop for FixtureDirectory {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.root);
    }
}

fn fixture_directory(label: &str) -> FixtureDirectory {
    let root = std::env::temp_dir().join(format!(
        "sanmill_data_query_process_{label}_{}_{}",
        std::process::id(),
        FIXTURE_COUNTER.fetch_add(1, Ordering::Relaxed)
    ));
    fs::create_dir_all(&root).expect("fixture directory must be created");
    FixtureDirectory { root }
}

fn human_fixture() -> FixtureDirectory {
    let fixture = fixture_directory("human");
    let path = fixture.path("human_db.sqlite");
    let conn = Connection::open(&path).expect("HumanDB fixture must open");
    conn.execute_batch(
        "CREATE TABLE meta (
             key TEXT PRIMARY KEY,
             value TEXT NOT NULL
         );
         CREATE TABLE positions (
             state_key TEXT PRIMARY KEY,
             total_games INTEGER NOT NULL,
             wins INTEGER NOT NULL,
             losses INTEGER NOT NULL,
             draws INTEGER NOT NULL,
             malom_wdl TEXT,
             malom_dtw INTEGER,
             canonical_winning_move TEXT
         );
         CREATE TABLE moves (
             state_key TEXT NOT NULL,
             notation TEXT NOT NULL,
             wins INTEGER NOT NULL,
             losses INTEGER NOT NULL,
             draws INTEGER NOT NULL,
             total INTEGER NOT NULL,
             moves_to_end_sum REAL NOT NULL,
             malom_wdl_after TEXT,
             malom_dtw_after INTEGER,
             PRIMARY KEY (state_key, notation)
         );",
    )
    .expect("HumanDB fixture schema must be created");
    for (key, value) in [
        ("schema_version", "2"),
        ("build_date", "2026-07-25T00:00:00Z"),
        ("total_games", "40"),
        ("malom_label_version", "sector-corrected-v1"),
    ] {
        conn.execute(
            "INSERT INTO meta(key, value) VALUES (?1, ?2)",
            params![key, value],
        )
        .expect("HumanDB fixture metadata must be inserted");
    }
    let state_key = "........................|W|place|0|0|0|0";
    conn.execute(
        "INSERT INTO positions(
             state_key, total_games, wins, losses, draws,
             malom_wdl, malom_dtw, canonical_winning_move
         ) VALUES (?1, 40, 20, 10, 10, 'D', 2, 'd2')",
        [state_key],
    )
    .expect("HumanDB fixture position must be inserted");
    for (notation, wins, losses, draws, total) in [("d2", 12, 8, 10, 30), ("d6", 4, 3, 3, 10)] {
        conn.execute(
            "INSERT INTO moves(
                 state_key, notation, wins, losses, draws, total,
                 moves_to_end_sum, malom_wdl_after, malom_dtw_after
             ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, 'D', 1)",
            params![
                state_key,
                notation,
                wins,
                losses,
                draws,
                total,
                f64::from(total * 2)
            ],
        )
        .expect("HumanDB fixture move must be inserted");
    }
    drop(conn);
    fixture
}

fn perfect_fixture() -> FixtureDirectory {
    let fixture = fixture_directory("perfect");
    fs::write(
        fixture.path("std.secval"),
        b"virt_loss_val: -299\nvirt_win_val: 299\n1\n0 1 9 8 -18\n",
    )
    .expect("Perfect DB fixture secval must be written");
    let sector = Path::new(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../src/ui/flutter_app/assets/databases/std_0_1_9_8.sec2"
    ));
    fs::copy(sector, fixture.path("std_0_1_9_8.sec2"))
        .expect("Perfect DB fixture sector must be copied");
    fixture
}

fn run_data_query(request: &str) -> Vec<u8> {
    let mut child = Command::new(env!("CARGO_BIN_EXE_tgf"))
        .args(["mill", "data-query"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("data-query process must start");
    child
        .stdin
        .take()
        .expect("child stdin must be piped")
        .write_all(request.as_bytes())
        .expect("request must be written");
    let output = child.wait_with_output().expect("data-query must finish");
    assert!(
        output.status.success(),
        "data-query failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    output.stdout
}

fn assert_byte_stable(request: &str) -> Value {
    let first = run_data_query(request);
    let second = run_data_query(request);
    assert_eq!(first, second);
    serde_json::from_slice(&first).expect("response must be valid JSON")
}

#[test]
fn book_enumeration_is_byte_stable_across_fresh_processes() {
    let response = assert_byte_stable(INITIAL_BOOK_REQUEST);
    assert_eq!(response["status"], "available");
    assert_eq!(response["source"]["candidate_order"], "source_array");
    assert_eq!(response["source"]["identity"]["oracle_positions"], 109);
    assert_eq!(response["source"]["identity"]["oracle_records"], 437);
}

#[test]
fn perfect_enumeration_is_byte_stable_across_fresh_processes() {
    let fixture = perfect_fixture();
    let request = json!({
        "operation": "query_perfect_db",
        "protocol_version": 1,
        "request_id": "perfect-cross-process",
        "position": {
            "rule": "nmm",
            "initial": "startpos",
            "history_origin": "game_start",
            "actions": []
        },
        "database_path": fixture.root.to_str().unwrap(),
        "cache_sectors": 2
    })
    .to_string();
    let response = assert_byte_stable(&request);

    assert_eq!(response["status"], "available");
    assert_eq!(
        response["source"]["candidate_order"],
        "full_turn_uci_lexicographic"
    );
    assert_eq!(
        response["candidates"]
            .as_array()
            .expect("candidates must be an array")
            .len(),
        24
    );
}

#[test]
fn human_enumeration_is_byte_stable_across_fresh_processes() {
    let fixture = human_fixture();
    let request = json!({
        "operation": "query_human_db",
        "protocol_version": 1,
        "request_id": "human-cross-process",
        "position": {
            "rule": "nmm",
            "initial": "startpos",
            "history_origin": "game_start",
            "actions": []
        },
        "database_path": fixture.path("human_db.sqlite")
    })
    .to_string();
    let response = assert_byte_stable(&request);

    assert_eq!(response["status"], "available");
    assert_eq!(
        response["source"]["candidate_order"],
        "total_desc_then_canonical_notation_then_mapped_notation"
    );
    let candidates = response["candidates"]
        .as_array()
        .expect("candidates must be an array");
    assert_eq!(candidates.len(), 2);
    assert_eq!(candidates[0]["mapped_notation"], "d2");
    assert_eq!(candidates[1]["mapped_notation"], "d6");
}

#[test]
fn database_misses_are_not_converted_to_fallback_moves() {
    let perfect = perfect_fixture();
    let perfect_request = json!({
        "operation": "query_perfect_db",
        "protocol_version": 1,
        "position": {
            "rule": "nmm",
            "initial": "startpos",
            "history_origin": "game_start",
            "actions": ["d2"]
        },
        "database_path": perfect.root.to_str().unwrap()
    })
    .to_string();
    let perfect_response: Value =
        serde_json::from_slice(&run_data_query(&perfect_request)).unwrap();
    assert_eq!(perfect_response["status"], "db_miss");
    assert_eq!(
        perfect_response["candidates"]
            .as_array()
            .expect("db_miss candidates must be an array")
            .len(),
        0
    );

    let human = human_fixture();
    let human_request = json!({
        "operation": "query_human_db",
        "protocol_version": 1,
        "position": {
            "rule": "nmm",
            "initial": "startpos",
            "history_origin": "game_start",
            "actions": ["a1"]
        },
        "database_path": human.path("human_db.sqlite")
    })
    .to_string();
    let human_response: Value = serde_json::from_slice(&run_data_query(&human_request)).unwrap();
    assert_eq!(human_response["status"], "human_db_miss");
    assert_eq!(
        human_response["candidates"]
            .as_array()
            .expect("human_db_miss candidates must be an array")
            .len(),
        0
    );
}

#[test]
fn strict_data_query_sources_do_not_depend_on_search_or_each_other() {
    const DISPATCH: &str = include_str!("../src/mill_data_query/mod.rs");
    const BOOK: &str = include_str!("../src/mill_data_query/book.rs");
    const PERFECT: &str = include_str!("../src/mill_data_query/perfect.rs");
    const HUMAN: &str = include_str!("../src/mill_data_query/human_db.rs");
    const PRODUCTION_SOURCES: [&str; 4] = [DISPATCH, BOOK, PERFECT, HUMAN];
    const FORBIDDEN_SEARCH_REFERENCES: [&str; 5] =
        ["tgf_search", "Searcher", "RandomSearch", "Mtdf", "Pvs"];

    for source in PRODUCTION_SOURCES {
        for forbidden in FORBIDDEN_SEARCH_REFERENCES {
            assert!(
                !source.contains(forbidden),
                "strict data-query production code must not reference {forbidden}"
            );
        }
    }
    assert!(!BOOK.contains("perfect::"));
    assert!(!BOOK.contains("human_db::"));
    assert!(!PERFECT.contains("book::"));
    assert!(!PERFECT.contains("human_db::"));
    assert!(!HUMAN.contains("book::"));
    assert!(!HUMAN.contains("perfect::"));
}
