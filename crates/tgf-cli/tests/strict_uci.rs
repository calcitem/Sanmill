// SPDX-License-Identifier: AGPL-3.0-or-later

use std::io::Write;
use std::process::{Command, Stdio};

fn run_uci(script: &str) -> String {
    let mut child = Command::new(env!("CARGO_BIN_EXE_tgf"))
        .args(["mill", "uci"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("tgf UCI process must start");
    child
        .stdin
        .take()
        .expect("UCI stdin must be piped")
        .write_all(script.as_bytes())
        .expect("UCI script must be written");
    let output = child
        .wait_with_output()
        .expect("tgf UCI process must finish");
    assert!(
        output.status.success(),
        "UCI process failed:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );
    String::from_utf8(output.stdout).expect("UCI output must be UTF-8")
}

fn fixed_node_script() -> &'static str {
    "setoption name StrictFailurePolicy value true\n\
     setoption name MoveTimeMs value 0\n\
     setoption name IDSEnabled value true\n\
     setoption name Shuffling value false\n\
     setoption name SearchShuffleSeed value 7\n\
     position startpos\n\
     go depth 12 nodes 256\n\
     quit\n"
}

#[test]
fn strict_policy_is_advertised_as_default_off() {
    let output = run_uci("uci\nquit\n");

    assert!(
        output.contains("option name StrictFailurePolicy type check default false"),
        "strict failure handling must remain opt-in:\n{output}"
    );
}

#[test]
fn strict_fixed_node_search_is_reproducible_and_legal() {
    let first = run_uci(fixed_node_script());
    let second = run_uci(fixed_node_script());
    assert_eq!(
        first, second,
        "fixed-node strict searches must be identical across fresh processes"
    );
    assert!(!first.contains("sanmill_error"), "{first}");

    let bestmove = first
        .split_whitespace()
        .collect::<Vec<_>>()
        .windows(2)
        .find(|pair| pair[0] == "bestmove")
        .map(|pair| pair[1])
        .expect("fixed-node search must emit bestmove");
    const INITIAL_PLACEMENTS: &[&str] = &[
        "a7", "d7", "g7", "g4", "g1", "d1", "a1", "a4", "b6", "d6", "f6", "f4", "f2", "d2", "b2",
        "b4", "c5", "d5", "e5", "e4", "e3", "d3", "c3", "c4",
    ];
    assert!(
        INITIAL_PLACEMENTS.contains(&bestmove),
        "startpos bestmove must be a legal placement, got {bestmove}"
    );
}

#[test]
fn strict_position_history_errors_block_search_without_bestmove() {
    let illegal = run_uci(
        "setoption name StrictFailurePolicy value true\n\
         position startpos moves a7 a7\n\
         go depth 1 nodes 32\n\
         quit\n",
    );
    assert!(
        illegal.contains(r#""code":"position_history_illegal_action""#),
        "{illegal}"
    );
    assert!(
        illegal.contains(r#""code":"position_unavailable""#),
        "{illegal}"
    );
    assert!(!illegal.contains("bestmove"), "{illegal}");

    let truncated = run_uci(
        "setoption name StrictFailurePolicy value true\n\
         position startpos moves a7 a4-\n\
         go depth 1 nodes 32\n\
         quit\n",
    );
    assert!(
        truncated.contains(r#""code":"position_history_truncated""#),
        "{truncated}"
    );
    assert!(
        truncated.contains(r#""code":"position_unavailable""#),
        "{truncated}"
    );
    assert!(!truncated.contains("bestmove"), "{truncated}");
}
