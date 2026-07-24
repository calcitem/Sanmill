// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

use super::*;
use crate::mill_data_query::position::ReplayedPosition;
use crate::mill_data_query::protocol::{HistoryOrigin, PositionRequest};
use rusqlite::params;
use std::sync::atomic::{AtomicUsize, Ordering};

static FIXTURE_COUNTER: AtomicUsize = AtomicUsize::new(0);

type MoveRow<'a> = (
    &'a str,
    i64,
    i64,
    i64,
    i64,
    f64,
    Option<&'a str>,
    Option<i64>,
);

struct FixtureDb {
    path: PathBuf,
    directory: PathBuf,
}

impl FixtureDb {
    fn path_text(&self) -> &str {
        self.path.to_str().expect("fixture path must be UTF-8")
    }
}

impl Drop for FixtureDb {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.path);
        let _ = fs::remove_dir(&self.directory);
    }
}

fn fixture_path(label: &str) -> FixtureDb {
    let directory = std::env::temp_dir().join(format!(
        "sanmill_data_query_human_{label}_{}_{}",
        std::process::id(),
        FIXTURE_COUNTER.fetch_add(1, Ordering::Relaxed)
    ));
    fs::create_dir_all(&directory).expect("fixture directory must be created");
    FixtureDb {
        path: directory.join("human_db.sqlite"),
        directory,
    }
}

fn fixture_database(state_key: &str, marker: Option<&str>, rows: &[MoveRow<'_>]) -> FixtureDb {
    let fixture = fixture_path("valid");
    let conn = Connection::open(&fixture.path).expect("fixture database must open");
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
    .expect("fixture schema must be created");
    for (key, value) in [
        ("schema_version", "2"),
        ("build_date", "2026-07-25T00:00:00Z"),
        ("total_games", "40"),
    ] {
        conn.execute(
            "INSERT INTO meta(key, value) VALUES (?1, ?2)",
            params![key, value],
        )
        .expect("fixture metadata must be inserted");
    }
    if let Some(marker) = marker {
        conn.execute(
            "INSERT INTO meta(key, value) VALUES ('malom_label_version', ?1)",
            [marker],
        )
        .expect("fixture marker must be inserted");
    }
    conn.execute(
        "INSERT INTO positions(
             state_key, total_games, wins, losses, draws,
             malom_wdl, malom_dtw, canonical_winning_move
         ) VALUES (?1, 40, 20, 10, 10, 'D', 12, 'd2')",
        [state_key],
    )
    .expect("fixture position must be inserted");
    for &(notation, wins, losses, draws, total, move_sum, malom_wdl, malom_dtw) in rows {
        conn.execute(
            "INSERT INTO moves(
                 state_key, notation, wins, losses, draws, total,
                 moves_to_end_sum, malom_wdl_after, malom_dtw_after
             ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
            params![
                state_key, notation, wins, losses, draws, total, move_sum, malom_wdl, malom_dtw
            ],
        )
        .expect("fixture move must be inserted");
    }
    drop(conn);
    fixture
}

fn replay(actions: &[&str]) -> ReplayedPosition {
    ReplayedPosition::replay(&PositionRequest {
        rule: RulePreset::Nmm,
        initial: "startpos".to_owned(),
        history_origin: HistoryOrigin::GameStart,
        actions: actions.iter().map(|action| (*action).to_owned()).collect(),
        expected_current_fen: None,
    })
    .expect("fixture history must replay")
}

fn canonical_state(replayed: &ReplayedPosition) -> (String, usize) {
    let fen = replayed
        .rules
        .export_fen(&MillRules::decode_snapshot(replayed.snapshot));
    state_key_from_fen(&fen).expect("fixture state must canonicalize")
}

fn open_error(path: &str) -> ApiError {
    match HumanDbSource::open(path) {
        Ok(_) => panic!("Human Database fixture unexpectedly opened"),
        Err(error) => error,
    }
}

#[test]
fn sqlite_uri_is_read_only_and_immutable() {
    let uri = immutable_sqlite_uri(Path::new(r"I:\Mill Training\human_db.sqlite")).unwrap();
    assert_eq!(
        uri,
        "file:I:/Mill%20Training/human_db.sqlite?mode=ro&immutable=1"
    );
    let unc = immutable_sqlite_uri(Path::new(r"\\?\UNC\server\share\human_db.sqlite")).unwrap();
    assert_eq!(
        unc,
        "file://server/share/human_db.sqlite?mode=ro&immutable=1"
    );
}

#[test]
fn malom_wdl_validation_rejects_unknown_labels() {
    assert!(validate_malom_wdl(Some("W"), "field").is_ok());
    assert!(validate_malom_wdl(None, "field").is_ok());
    assert!(validate_malom_wdl(Some("win"), "field").is_err());
}

#[test]
fn total_controls_frequency_and_order_independently_of_experience_score() {
    let replayed = replay(&[]);
    let (state_key, _) = canonical_state(&replayed);
    let fixture = fixture_database(
        &state_key,
        Some(TRUSTED_MALOM_LABEL_VERSION),
        &[
            ("d2", 18, 2, 10, 30, 90.0, Some("W"), Some(5)),
            ("a1", 1, 8, 1, 10, 50.0, Some("L"), Some(9)),
        ],
    );
    let source = HumanDbSource::open(fixture.path_text()).unwrap();
    let result = source.query(&replayed, None, 0).unwrap();

    assert_eq!(result.candidates.len(), 2);
    assert_eq!(result.candidates[0].mapped_notation, "d2");
    assert_eq!(result.candidates[1].mapped_notation, "a1");
    let first = result.candidates[0].human.as_ref().unwrap();
    let second = result.candidates[1].human.as_ref().unwrap();
    assert_eq!(
        (first.frequency_numerator, first.frequency_denominator),
        (30, 40)
    );
    assert_eq!(
        (second.frequency_numerator, second.frequency_denominator),
        (10, 40)
    );
    assert_eq!(first.relative_frequency, 0.75);
    assert_eq!(second.relative_frequency, 0.25);
    assert_ne!(
        first.relative_frequency, first.empirical_win_rate,
        "human choice frequency must not be replaced by experience win rate"
    );
    assert_eq!(result.source["identity"]["malom_trusted"], true);
    assert_eq!(result.source["position"]["malom_wdl"], "D");
    assert_eq!(first.malom_wdl_after.as_deref(), Some("W"));
}

#[test]
fn missing_or_unknown_marker_masks_only_malom_fields() {
    let replayed = replay(&[]);
    let (state_key, _) = canonical_state(&replayed);
    for marker in [None, Some("legacy-untrusted")] {
        let fixture = fixture_database(
            &state_key,
            marker,
            &[("d2", 18, 2, 10, 30, 90.0, Some("W"), Some(5))],
        );
        let source = HumanDbSource::open(fixture.path_text()).unwrap();
        let result = source.query(&replayed, None, 0).unwrap();
        let human = result.candidates[0].human.as_ref().unwrap();

        assert_eq!(human.total, 30);
        assert_eq!(human.wins, 18);
        assert!(human.malom_wdl_after.is_none());
        assert!(human.malom_dtw_after.is_none());
        assert_eq!(result.source["identity"]["malom_trusted"], false);
        assert!(result.source["position"].get("malom_wdl").is_none());
        assert!(result.source["position"].get("malom_dtw").is_none());
        assert!(
            result.source["position"]
                .get("canonical_winning_move")
                .is_none()
        );
    }
}

#[test]
fn d4_notation_is_mapped_back_to_the_live_orientation() {
    let replayed = replay(&["d2", "a1"]);
    let (state_key, symmetry) = canonical_state(&replayed);
    assert_ne!(
        symmetry, 0,
        "fixture must exercise a non-identity D4 presentation"
    );
    let raw = transform_notation("d6", symmetry).unwrap();
    let fixture = fixture_database(
        &state_key,
        Some(TRUSTED_MALOM_LABEL_VERSION),
        &[(&raw, 4, 2, 4, 10, 20.0, Some("D"), Some(3))],
    );
    let source = HumanDbSource::open(fixture.path_text()).unwrap();
    let result = source.query(&replayed, None, 0).unwrap();

    assert_eq!(result.candidates.len(), 1);
    assert_eq!(
        result.candidates[0].raw_notation.as_deref(),
        Some(raw.as_str())
    );
    assert_eq!(result.candidates[0].mapped_notation, "d6");
    assert_eq!(result.candidates[0].full_turn_actions, ["d6"]);
}

#[test]
fn compound_human_turn_remains_one_logical_ply_in_pending_removal() {
    let parent = replay(&["d7", "a1", "g7", "d1"]);
    let (state_key, symmetry) = canonical_state(&parent);
    let raw = transform_notation("a7xa1", symmetry).unwrap();
    let fixture = fixture_database(
        &state_key,
        Some(TRUSTED_MALOM_LABEL_VERSION),
        &[(&raw, 5, 2, 3, 10, 30.0, Some("W"), Some(2))],
    );
    let source = HumanDbSource::open(fixture.path_text()).unwrap();

    let complete = source.query(&parent, None, 0).unwrap();
    assert_eq!(complete.candidates[0].full_turn_actions, ["a7", "xa1"]);
    assert_eq!(complete.candidates[0].remaining_actions, ["a7", "xa1"]);
    assert_eq!(complete.candidates[0].logical_ply_delta, 1);

    let pending = replay(&["d7", "a1", "g7", "d1", "a7"]);
    assert!(pending.current_side_has_pending_removal());
    let continuation = source.query(&pending, None, 0).unwrap();
    assert_eq!(continuation.candidates[0].full_turn_actions, ["a7", "xa1"]);
    assert_eq!(continuation.candidates[0].remaining_actions, ["xa1"]);
    assert_eq!(continuation.candidates[0].logical_ply_delta, 1);
    assert!(continuation.candidates[0].turn_prefix_complete);
}

#[test]
fn illegal_rows_fail_closed_even_below_the_requested_limit() {
    let replayed = replay(&[]);
    let (state_key, _) = canonical_state(&replayed);
    let fixture = fixture_database(
        &state_key,
        Some(TRUSTED_MALOM_LABEL_VERSION),
        &[
            ("d2", 8, 1, 1, 10, 20.0, Some("W"), Some(2)),
            ("a1-a4", 1, 0, 0, 1, 2.0, Some("W"), Some(1)),
        ],
    );
    let source = HumanDbSource::open(fixture.path_text()).unwrap();
    let error = source.query(&replayed, Some(1), 0).unwrap_err();
    assert_eq!(error.code, "illegal_source_move");
}

#[test]
fn miss_missing_corrupt_and_incompatible_are_distinct() {
    let replayed = replay(&[]);
    let (state_key, _) = canonical_state(&replayed);
    let fixture = fixture_database(&state_key, Some(TRUSTED_MALOM_LABEL_VERSION), &[]);
    let source = HumanDbSource::open(fixture.path_text()).unwrap();
    assert!(
        source
            .query(&replayed, None, 0)
            .unwrap()
            .candidates
            .is_empty()
    );
    drop(source);

    let missing = fixture.directory.join("missing.sqlite");
    let error = open_error(missing.to_str().unwrap());
    assert_eq!(error.code, "database_missing");

    let corrupt = fixture_path("corrupt");
    fs::write(&corrupt.path, b"not a SQLite database").unwrap();
    let error = open_error(corrupt.path_text());
    assert_eq!(error.code, "database_corrupt");

    let incompatible = fixture_path("incompatible");
    let connection = Connection::open(&incompatible.path).unwrap();
    connection
        .execute_batch("CREATE TABLE unrelated(value TEXT);")
        .unwrap();
    drop(connection);
    let error = open_error(incompatible.path_text());
    assert_eq!(error.code, "database_schema_incompatible");
}
