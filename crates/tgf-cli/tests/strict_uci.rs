// SPDX-License-Identifier: AGPL-3.0-or-later

use std::io::Write;
use std::process::{Command, Stdio};

use serde_json::Value;

const STATE_PREFIX: &str = "info string sanmill_state ";
const LOGICAL_TURN_PREFIX: &str = "info string sanmill_logical_turn ";
const MOVING_CYCLE_FEN: &str =
    "O*@*****/O*@*****/*@*****O w m s 3 0 3 0 0 0 -1 -1 -1 -1 0 0 1 ids:nodes";
const FOUR_PLY_CYCLE: &str = "d5-e5 e4-e3 e5-d5 e3-e4";

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

fn prefixed_json_lines(output: &str, prefix: &str) -> Vec<Value> {
    output
        .lines()
        .filter_map(|line| line.strip_prefix(prefix))
        .map(|payload| serde_json::from_str(payload).expect("machine response must be valid JSON"))
        .collect()
}

#[test]
fn strict_policy_is_advertised_as_default_off() {
    let output = run_uci("uci\nquit\n");

    assert!(
        output.contains("option name StrictFailurePolicy type check default false"),
        "strict failure handling must remain opt-in:\n{output}"
    );
    assert!(
        output.contains(
            "option name StrictRefereeProfile type combo default sanmill-live-v1 var sanmill-live-v1 var mif-stable-moving-v1"
        ),
        "the portable referee profile must be explicit and default off:\n{output}"
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

#[test]
fn statejson_tracks_atomic_actions_and_complete_logical_turns() {
    let output = run_uci(
        "setoption name StrictFailurePolicy value true\n\
         setoption name StrictRefereeProfile value mif-stable-moving-v1\n\
         position startpos\n\
         statejson\n\
         position startpos moves d7 a1 g7 d1 a7\n\
         statejson\n\
         position startpos moves d7 a1 g7 d1 a7 xa1\n\
         statejson\n\
         quit\n",
    );
    let states = prefixed_json_lines(&output, STATE_PREFIX);
    assert_eq!(states.len(), 3, "{output}");

    assert_eq!(states[0]["status"], "ok");
    assert_eq!(states[0]["ruleset_id"], "nmm");
    assert_eq!(states[0]["action_token_count"], 0);
    assert_eq!(states[0]["logical_ply_count"], 0);
    assert_eq!(states[0]["legal_actions"].as_array().unwrap().len(), 24);
    assert_eq!(
        states[0]["strict_referee_identity"]["profile"],
        "mif-stable-moving-v1"
    );
    assert_eq!(states[0]["strict_referee_identity"]["originCounted"], true);

    assert_eq!(states[1]["action"], "remove");
    assert_eq!(states[1]["pending_removal"], true);
    assert_eq!(states[1]["pending_removal_count"], 1);
    assert_eq!(states[1]["action_token_count"], 5);
    assert_eq!(states[1]["logical_ply_count"], 4);

    assert_eq!(states[2]["action"], "place");
    assert_eq!(states[2]["pending_removal"], false);
    assert_eq!(states[2]["action_token_count"], 6);
    assert_eq!(states[2]["logical_ply_count"], 5);
    assert_eq!(
        states[2]["logical_plies_by_side"],
        serde_json::json!([3, 2])
    );
    assert_eq!(states[2]["no_capture_count"], 0);
    assert_eq!(states[2]["repetition_history_length"], 0);
    assert_eq!(
        states[2]["history_sha256"].as_str().unwrap().len(),
        64,
        "{output}"
    );
}

#[test]
fn statejson_reports_terminal_reasons_and_rule_counters() {
    let output = run_uci(
        "setoption name StrictFailurePolicy value true\n\
         position fen **O**O**/**@**@**/******** w m s 2 0 2 0 0 0 -1 -1 -1 -1 0 0 1 ids:nodes\n\
         statejson\n\
         position fen O@O@O@O@/@*@*@*@*/******** w m s 4 0 8 0 0 0 -1 -1 -1 -1 0 0 1 ids:nodes\n\
         statejson\n\
         position fen O*@*****/O*@*****/*@*****O w m s 3 0 3 0 0 0 -1 -1 -1 -1 0 0 1 ids:nodes moves d5-e5 e4-e3 e5-d5 e3-e4 d5-e5 e4-e3 e5-d5 e3-e4 d5-e5\n\
         statejson\n\
         quit\n",
    );
    let states = prefixed_json_lines(&output, STATE_PREFIX);
    assert_eq!(states.len(), 3, "{output}");

    assert_eq!(states[0]["status"], "terminal");
    assert_eq!(states[0]["winner"], "black");
    assert_eq!(states[0]["outcome_reason_code"], "lose_fewer_than_three");

    assert_eq!(states[1]["status"], "terminal");
    assert_eq!(states[1]["winner"], "black");
    assert_eq!(states[1]["outcome_reason_code"], "lose_no_legal_moves");
    assert!(states[1]["legal_actions"].as_array().unwrap().is_empty());

    assert_eq!(states[2]["status"], "terminal");
    assert_eq!(
        states[2]["outcome_reason_code"],
        "draw_threefold_repetition"
    );
    assert_eq!(states[2]["repetition_current_count"], 3);
    assert_eq!(states[2]["action_token_count"], 9);
    assert_eq!(states[2]["logical_ply_count"], 9);
}

#[test]
fn legacy_live_profile_keeps_post_move_repetition_origin_semantics() {
    let moves4 = FOUR_PLY_CYCLE;
    let moves8 = [FOUR_PLY_CYCLE, FOUR_PLY_CYCLE].join(" ");
    let moves9 = format!("{moves8} d5-e5");
    let script = format!(
        "setoption name StrictFailurePolicy value true\n\
         position fen {MOVING_CYCLE_FEN}\n\
         statejson\n\
         position fen {MOVING_CYCLE_FEN} moves {moves4}\n\
         statejson\n\
         position fen {MOVING_CYCLE_FEN} moves {moves8}\n\
         statejson\n\
         position fen {MOVING_CYCLE_FEN} moves {moves9}\n\
         statejson\n\
         quit\n"
    );
    let output = run_uci(&script);
    let states = prefixed_json_lines(&output, STATE_PREFIX);
    assert_eq!(states.len(), 4, "{output}");

    for (index, expected) in [0, 1, 2, 3].into_iter().enumerate() {
        assert_eq!(states[index]["repetition_current_count"], expected);
    }
    for state in &states[..3] {
        assert_eq!(state["status"], "ok");
        assert_eq!(state["terminal"], false);
        assert_eq!(state["outcome_reason_code"], "ongoing");
    }
    assert_eq!(states[3]["status"], "terminal");
    assert_eq!(states[3]["terminal"], true);
    assert_eq!(
        states[3]["outcome_reason_code"],
        "draw_threefold_repetition"
    );
    assert_eq!(states[3]["logical_ply_count"], 9);
}

#[test]
fn mif_stable_moving_profile_counts_origin_and_draws_at_ply_eight() {
    let moves4 = FOUR_PLY_CYCLE;
    let moves8 = [FOUR_PLY_CYCLE, FOUR_PLY_CYCLE].join(" ");
    let moves9 = format!("{moves8} d5-e5");
    let script = format!(
        "setoption name StrictFailurePolicy value true\n\
         setoption name StrictRefereeProfile value mif-stable-moving-v1\n\
         position fen {MOVING_CYCLE_FEN}\n\
         statejson\n\
         position fen {MOVING_CYCLE_FEN} moves {moves4}\n\
         statejson\n\
         position fen {MOVING_CYCLE_FEN} moves {moves8}\n\
         statejson\n\
         position fen {MOVING_CYCLE_FEN} moves {moves9}\n\
         statejson\n\
         quit\n"
    );
    let output = run_uci(&script);
    let states = prefixed_json_lines(&output, STATE_PREFIX);
    assert_eq!(states.len(), 4, "{output}");

    assert_eq!(states[0]["repetition_current_count"], 1);
    assert_eq!(states[0]["repetition_history_length"], 1);
    assert_eq!(states[0]["status"], "ok");
    assert_eq!(states[0]["terminal"], false);
    assert_eq!(states[0]["outcome_reason_code"], "ongoing");

    assert_eq!(states[1]["repetition_current_count"], 2);
    assert_eq!(states[1]["repetition_history_length"], 5);
    assert_eq!(states[1]["status"], "ok");
    assert_eq!(states[1]["terminal"], false);
    assert_eq!(states[1]["outcome_reason_code"], "ongoing");

    assert_eq!(states[2]["repetition_current_count"], 3);
    assert_eq!(states[2]["repetition_history_length"], 9);
    assert_eq!(states[2]["status"], "terminal");
    assert_eq!(states[2]["terminal"], true);
    assert_eq!(
        states[2]["outcome_reason_code"],
        "draw_threefold_repetition"
    );
    assert_eq!(states[2]["logical_ply_count"], 8);
    assert_eq!(
        states[2]["strict_referee_identity"]["profile"],
        "mif-stable-moving-v1"
    );
    assert_eq!(
        states[2]["strict_referee_identity"]["repetitionObservation"],
        "stable-moving-v1"
    );
    assert!(
        states[2]["strict_referee_identity"]["semanticDigest"]
            .as_str()
            .is_some_and(|value| value.starts_with("sha256:") && value.len() == 71)
    );

    assert_eq!(states[3]["status"], "position_unavailable");
    assert_eq!(
        states[3]["position_error_code"],
        "position_history_illegal_action"
    );
    assert!(states[3].get("terminal").is_none());
}

#[test]
fn mif_profile_resets_then_observes_after_required_removal() {
    let output = run_uci(
        "setoption name StrictFailurePolicy value true\n\
         setoption name StrictRefereeProfile value mif-stable-moving-v1\n\
         position startpos moves d6 f4 d2 b4 g4 d7 a4 d1 e4 d5 c4 d3 f6 b6 b2 f2 g7 g1\n\
         statejson\n\
         position startpos moves d6 f4 d2 b4 g4 d7 a4 d1 d5 d3 e4 f6 f2 b2 b6 g7 a7 c3 d5-c5 c3-c4 e4-e5 c4-c3 d6-d5 xd3\n\
         statejson\n\
         quit\n",
    );
    let states = prefixed_json_lines(&output, STATE_PREFIX);
    assert_eq!(states.len(), 2, "{output}");
    let after_final_placement = &states[0];
    assert_eq!(after_final_placement["status"], "ok");
    assert_eq!(after_final_placement["phase"], "moving");
    assert_eq!(after_final_placement["repetition_current_count"], 1);
    assert_eq!(after_final_placement["repetition_history_length"], 1);
    assert_eq!(after_final_placement["no_capture_count"], 0);

    let state = &states[1];
    assert_eq!(state["status"], "ok", "{output}");
    assert_eq!(state["phase"], "moving");
    assert_eq!(state["action"], "select");
    assert_eq!(state["pending_removal"], false);
    assert_eq!(state["repetition_current_count"], 1);
    assert_eq!(state["repetition_history_length"], 1);
    assert_eq!(state["no_capture_count"], 0);
    assert_eq!(
        state["action_token_count"].as_u64().unwrap(),
        state["logical_ply_count"].as_u64().unwrap() + 1,
        "the required removal is atomic but remains in the same logical turn"
    );
}

#[test]
fn statejson_counts_exactly_one_hundred_no_capture_logical_plies() {
    let cycle = ["d5-e5", "e4-e3", "e5-d5", "e3-e4"].repeat(25).join(" ");
    let script = format!(
        "setoption name StrictFailurePolicy value true\n\
         setoption name StrictRefereeProfile value mif-stable-moving-v1\n\
         setoption name ThreefoldRepetitionRule value false\n\
         position fen O*@*****/O*@*****/*@*****O w m s 3 0 3 0 0 0 -1 -1 -1 -1 0 0 1 ids:nodes moves {cycle}\n\
         statejson\n\
         quit\n"
    );
    let output = run_uci(&script);
    let states = prefixed_json_lines(&output, STATE_PREFIX);
    assert_eq!(states.len(), 1, "{output}");
    let state = &states[0];

    assert_eq!(state["status"], "terminal");
    assert_eq!(state["outcome_reason_code"], "draw_fifty_move");
    assert_eq!(state["action_token_count"], 100);
    assert_eq!(state["logical_ply_count"], 100);
    assert_eq!(state["logical_plies_by_side"], serde_json::json!([50, 50]));
    assert_eq!(state["no_capture_count"], 100);
}

#[test]
fn rejected_position_makes_statejson_unavailable() {
    let output = run_uci(
        "setoption name StrictFailurePolicy value true\n\
         position startpos moves a7\n\
         statejson\n\
         position startpos moves a7 a7\n\
         statejson\n\
         position startpos moves a7 a4-\n\
         statejson\n\
         quit\n",
    );
    let states = prefixed_json_lines(&output, STATE_PREFIX);
    assert_eq!(states.len(), 3, "{output}");
    assert_eq!(states[0]["status"], "ok");
    assert!(states[0].get("fen").is_some());
    assert_eq!(states[1]["status"], "position_unavailable");
    assert_eq!(
        states[1]["position_error_code"],
        "position_history_illegal_action"
    );
    assert!(states[1].get("fen").is_none());
    assert_eq!(states[2]["status"], "position_unavailable");
    assert_eq!(
        states[2]["position_error_code"],
        "position_history_truncated"
    );
    assert!(states[2].get("fen").is_none());
}

#[test]
fn statejson_and_history_digest_are_reproducible_across_processes() {
    let moves8 = [FOUR_PLY_CYCLE, FOUR_PLY_CYCLE].join(" ");
    let script = format!(
        "setoption name StrictFailurePolicy value true\n\
         setoption name StrictRefereeProfile value mif-stable-moving-v1\n\
         position fen {MOVING_CYCLE_FEN} moves {moves8}\n\
         statejson\n\
         quit\n"
    );
    let first = run_uci(&script);
    let second = run_uci(&script);
    assert_eq!(first, second);
    let state = prefixed_json_lines(&first, STATE_PREFIX)
        .pop()
        .expect("statejson response");
    assert_eq!(state["action_token_count"], 8);
    assert_eq!(state["logical_ply_count"], 8);
    assert_eq!(state["status"], "terminal");
    assert_eq!(state["repetition_current_count"], 3);
    assert_eq!(state["history_sha256"].as_str().unwrap().len(), 64);
}

#[test]
fn logical_go_covers_place_move_fly_and_mill_removal_turns() {
    let output = run_uci(
        "setoption name StrictFailurePolicy value true\n\
         setoption name Algorithm value 2\n\
         setoption name MoveTimeMs value 0\n\
         setoption name IDSEnabled value true\n\
         setoption name Shuffling value false\n\
         setoption name SearchShuffleSeed value 7\n\
         setoption name SkillLevel value 30\n\
         position startpos\n\
         go logical nodes 4096 depth 4\n\
         position fen ***O****/OO@*@*@@/@OOO@*O* w m s 7 0 6 0 0 0 -1 -1 -1 -1 0 3 15 ids:nodes\n\
         go logical nodes 20000 depth 4\n\
         position fen O**O*@**/**O*@***/*@****** w m s 3 0 3 0 0 0 -1 -1 -1 -1 0 0 1 ids:nodes\n\
         go logical nodes 20000 depth 4\n\
         position startpos moves d2 d6 f4 b4 f2 g4\n\
         go logical nodes 100000 depth 5\n\
         position startpos moves d6 f4 d2 b4 g4 d7 a4 d1 d5 d3 e4 f6 f2 b2 b6 g7 a7 c3 d5-c5 c3-c4 e4-e5 c4-c3\n\
         go logical nodes 500000 depth 8\n\
         position fen **O**O**/**@**@**/******** w m s 2 0 2 0 0 0 -1 -1 -1 -1 0 0 1 ids:nodes\n\
         go logical nodes 100 depth 2\n\
         quit\n",
    );
    let turns = prefixed_json_lines(&output, LOGICAL_TURN_PREFIX);
    assert_eq!(turns.len(), 6, "{output}");

    assert_eq!(turns[0]["full_turn_actions"].as_array().unwrap().len(), 1);
    assert!(turns[0]["model_action"]["from"].is_null());

    assert_eq!(turns[1]["full_turn_actions"].as_array().unwrap().len(), 1);
    assert!(turns[1]["model_action"]["from"].is_string());
    assert!(turns[1]["model_action"]["capture"].is_null());

    assert_eq!(turns[2]["full_turn_actions"].as_array().unwrap().len(), 1);
    assert!(turns[2]["model_action"]["from"].is_string());
    assert!(turns[2]["model_action"]["capture"].is_null());

    for turn in [&turns[3], &turns[4]] {
        assert_eq!(turn["full_turn_actions"].as_array().unwrap().len(), 2);
        assert!(turn["model_action"]["capture"].is_string());
        assert_eq!(turn["logical_ply_delta"], 1);
        assert_eq!(turn["resulting_side_to_move"], "black");
        assert_eq!(turn["terminal"], false);
        assert!(turn["logical_move_id"].as_str().unwrap().contains('x'));
    }
    assert_eq!(turns[3]["model_action"]["from"], Value::Null);
    assert!(turns[4]["model_action"]["from"].is_string());
    let placement_removal = turns[3]["full_turn_actions"][1].as_str().unwrap();
    assert!(
        ["xg4", "xb4", "xd6"].contains(&placement_removal),
        "{placement_removal} must be one of the legal capture targets"
    );

    assert_eq!(turns[5]["status"], "terminal");
    assert!(turns[5]["full_turn_actions"].as_array().unwrap().is_empty());
    assert_eq!(turns[5]["logical_ply_delta"], 0);
    assert_eq!(turns[5]["total_nodes"], 0);
    assert_eq!(turns[5]["outcome_reason"], "loseFewerThanThree");

    for turn in turns {
        let budget = turn["node_budget"].as_u64().unwrap();
        let primary = turn["primary_nodes"].as_u64().unwrap();
        let removal = turn["removal_nodes"].as_u64().unwrap();
        let total = turn["total_nodes"].as_u64().unwrap();
        assert_eq!(primary + removal, total);
        assert!(total <= budget, "{turn}");
    }
}

#[test]
fn logical_go_is_cross_process_reproducible_under_fixed_contract() {
    let script = "setoption name StrictFailurePolicy value true\n\
                  setoption name Algorithm value 2\n\
                  setoption name MoveTimeMs value 0\n\
                  setoption name IDSEnabled value true\n\
                  setoption name Shuffling value false\n\
                  setoption name SearchShuffleSeed value 7\n\
                  setoption name SkillLevel value 30\n\
                  position startpos moves d2 d6 f4 b4 f2 g4\n\
                  go logical nodes 100000 depth 5\n\
                  quit\n";
    let first = run_uci(script);
    let second = run_uci(script);
    assert_eq!(
        first, second,
        "logical action, node accounting, and resulting state must match"
    );
    assert_eq!(prefixed_json_lines(&first, LOGICAL_TURN_PREFIX).len(), 1);
}

#[test]
fn logical_go_errors_are_fail_closed_without_legacy_fallbacks() {
    let output = run_uci(
        "position startpos\n\
         go logical nodes 100 depth 2\n\
         setoption name StrictFailurePolicy value true\n\
         position startpos moves d7 a1 g7 d1 a7\n\
         go logical nodes 100 depth 2\n\
         position startpos\n\
         go logical nodes 1 depth 12\n\
         position startpos moves a7 a7\n\
         go logical nodes 100 depth 2\n\
         quit\n",
    );
    for code in [
        "strict_policy_required",
        "logical_turn_unstable_position",
        "logical_turn_budget_exhausted",
        "position_unavailable",
    ] {
        assert!(
            output.contains(&format!(r#""code":"{code}""#)),
            "missing {code}:\n{output}"
        );
    }
    assert!(!output.contains("bestmove"), "{output}");
    assert!(!output.contains(LOGICAL_TURN_PREFIX), "{output}");
    assert!(!output.contains("aimovetype"), "{output}");
}
