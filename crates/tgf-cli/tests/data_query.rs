// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

use std::io::Write;
use std::process::{Command, Stdio};

const INITIAL_BOOK_REQUEST: &str = r#"{"operation":"query_book","protocol_version":1,"request_id":"cross-process","position":{"rule":"nmm","initial":"startpos","history_origin":"game_start","actions":[]}}"#;

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

#[test]
fn book_enumeration_is_byte_stable_across_fresh_processes() {
    let first = run_data_query(INITIAL_BOOK_REQUEST);
    let second = run_data_query(INITIAL_BOOK_REQUEST);
    assert_eq!(first, second);

    let response: serde_json::Value =
        serde_json::from_slice(&first).expect("response must be valid JSON");
    assert_eq!(response["status"], "available");
    assert_eq!(response["source"]["candidate_order"], "source_array");
    assert_eq!(response["source"]["identity"]["oracle_positions"], 109);
    assert_eq!(response["source"]["identity"]["oracle_records"], 437);
}
