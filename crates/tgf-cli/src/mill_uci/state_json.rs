// SPDX-License-Identifier: AGPL-3.0-or-later

//! Versioned, machine-readable snapshots of the live Mill UCI position.
//!
//! This is a CLI-only cold path. It deliberately reuses the data-query state
//! summarizer and never invokes search, a database, patch data, or randomness.

use serde::Serialize;
use serde_json::json;
use sha2::{Digest, Sha256};
use tgf_cli::h2h_trace::{mill_rules_identity, mill_ruleset_id};
use tgf_core::{ActionList, GameRules, OutcomeKind};
use tgf_mill::{MillRules, MillUciCodec, MillVariantOptions};

use super::board::{ParsedPosition, PositionHistoryOrigin};
use super::{StrictRefereeProfile, UciMachineError};

const STATE_PROTOCOL_VERSION: u32 = 1;
const STATE_PREFIX: &str = "info string sanmill_state ";

#[derive(Serialize)]
struct RulesIdentity {
    format_version: u32,
    sha256: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct RefereeRulesIdentity {
    format: &'static str,
    profile: &'static str,
    repetition_observation: &'static str,
    origin_counted: bool,
    semantic_digest: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct RefereeSemanticMaterial<'a> {
    format: &'static str,
    rules_options: &'a MillVariantOptions,
    profile: &'static str,
    repetition_observation: &'static str,
    origin_counted: bool,
    repetition_reset_events: [&'static str; 2],
    logical_turn: &'static str,
}

#[derive(Serialize)]
struct StateResponse<'a> {
    protocol_version: u32,
    status: &'static str,
    ruleset_id: &'static str,
    rules_identity: RulesIdentity,
    strict_referee_identity: RefereeRulesIdentity,
    rules_options: &'a MillVariantOptions,
    history_origin: &'static str,
    fen: String,
    side_to_move: Option<String>,
    phase: String,
    action: &'static str,
    pending_removal: bool,
    pending_removal_count: u8,
    pending_removals: [u8; 2],
    legal_actions: Vec<String>,
    action_token_count: u32,
    logical_ply_count: u32,
    logical_plies_by_side: [u32; 2],
    no_capture_count: u16,
    repetition_current_count: usize,
    repetition_history_length: usize,
    snapshot_history_length: usize,
    history_sha256: String,
    terminal: bool,
    winner: Option<&'static str>,
    winner_code: Option<i8>,
    outcome_reason: String,
    outcome_reason_code: &'static str,
}

#[cfg(test)]
pub(super) fn state_info_line(
    options: &MillVariantOptions,
    rules: &MillRules,
    position: &ParsedPosition,
    rejected_position: Option<&UciMachineError>,
) -> String {
    state_info_line_with_profile(
        options,
        rules,
        position,
        rejected_position,
        StrictRefereeProfile::SanmillLiveV1,
    )
}

pub(super) fn state_info_line_with_profile(
    options: &MillVariantOptions,
    rules: &MillRules,
    position: &ParsedPosition,
    rejected_position: Option<&UciMachineError>,
    profile: StrictRefereeProfile,
) -> String {
    let strict_referee_identity = referee_rules_identity(options, profile);
    if let Some(error) = rejected_position {
        return prefixed_json(&json!({
            "protocol_version": STATE_PROTOCOL_VERSION,
            "status": "position_unavailable",
            "code": "position_unavailable",
            "message": "the most recent position command was rejected",
            "position_error_code": error.code,
            "strict_referee_identity": strict_referee_identity,
        }));
    }

    let summary = match crate::mill_data_query::summarize_position(
        rules,
        &position.state,
        &position.history,
        &position.action_tokens,
        position.counts,
    ) {
        Ok(summary) => summary,
        Err(message) => {
            return prefixed_json(&json!({
                "protocol_version": STATE_PROTOCOL_VERSION,
                "status": "error",
                "code": "state_summary_error",
                "message": message,
            }));
        }
    };

    let decoded = MillRules::decode_snapshot(position.state);
    let outcome = rules.outcome(&position.state);
    let terminal = !matches!(outcome.kind, OutcomeKind::Ongoing);
    let (winner, winner_code) = match outcome.kind {
        OutcomeKind::Win(0) => (Some("white"), Some(0)),
        OutcomeKind::Win(1) => (Some("black"), Some(1)),
        OutcomeKind::Win(side) => (None, Some(side)),
        _ => (None, None),
    };
    let mut legal = ActionList::<256>::new();
    rules.legal_actions(&position.state, &mut legal);
    let legal_actions = legal
        .as_slice()
        .iter()
        .copied()
        .map(MillUciCodec::encode_action)
        .collect::<Vec<_>>();
    let current_side = position.state.side_to_move;
    let pending_removal_count = if current_side == 0 || current_side == 1 {
        decoded.pending_removals()[current_side as usize]
    } else {
        0
    };

    let repetition_history =
        MillRules::repetition_history_from_snapshots(&position.state, &position.history);
    // The rolling repetition history stores the rule's repetition signature,
    // not the terminal state's full Zobrist key. Counting its final signature
    // therefore still reports 3 after the third occurrence changes phase to
    // GameOver.
    let repetition_current_count = if outcome.reason == "drawThreefoldRepetition" {
        // The transition that adjudicates the third occurrence also changes
        // phase/winner and therefore the final snapshot's full Zobrist key.
        // The rule outcome is authoritative evidence that the configured
        // three-occurrence threshold was reached.
        3
    } else {
        repetition_history
            .last()
            .map(|current_key| {
                repetition_history
                    .iter()
                    .filter(|candidate| *candidate == current_key)
                    .count()
            })
            .unwrap_or(0)
    };

    let response = StateResponse {
        protocol_version: STATE_PROTOCOL_VERSION,
        status: if terminal { "terminal" } else { "ok" },
        ruleset_id: ruleset_id(options),
        rules_identity: rules_identity(options),
        strict_referee_identity,
        rules_options: options,
        history_origin: match position.history_origin {
            PositionHistoryOrigin::GameStart => "game_start",
            PositionHistoryOrigin::FreshSetup => "fresh_setup",
        },
        fen: summary.current_fen,
        side_to_move: summary.side_to_move,
        phase: summary.phase,
        action: action_name(decoded.action_tag()),
        pending_removal: summary.pending_removal,
        pending_removal_count,
        pending_removals: summary.pending_removals,
        legal_actions,
        action_token_count: summary.action_token_count,
        logical_ply_count: summary.logical_ply_count,
        logical_plies_by_side: summary.logical_plies_by_side,
        no_capture_count: summary.no_capture_plies,
        repetition_current_count,
        repetition_history_length: summary.repetition_history_len,
        snapshot_history_length: summary.snapshot_history_len,
        history_sha256: summary.history_sha256,
        terminal,
        winner,
        winner_code,
        outcome_reason_code: outcome_reason_code(&summary.outcome.reason),
        outcome_reason: summary.outcome.reason,
    };
    prefixed_json(&response)
}

fn referee_rules_identity(
    options: &MillVariantOptions,
    profile: StrictRefereeProfile,
) -> RefereeRulesIdentity {
    let material = RefereeSemanticMaterial {
        format: "SANMILL-STRICT-REFEREE-RULES/1",
        rules_options: options,
        profile: profile.id(),
        repetition_observation: profile.repetition_observation(),
        origin_counted: profile.origin_counted(),
        repetition_reset_events: ["board-remove", "place"],
        logical_turn: "primary-with-required-removal-v1",
    };
    let canonical = serde_json_canonicalizer::to_vec(&material)
        .expect("strict referee identity must be valid RFC 8785 JSON");
    let digest = Sha256::digest(canonical);
    let semantic_digest = digest
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect::<String>();
    RefereeRulesIdentity {
        format: material.format,
        profile: profile.id(),
        repetition_observation: profile.repetition_observation(),
        origin_counted: profile.origin_counted(),
        semantic_digest: format!("sha256:{semantic_digest}"),
    }
}

fn ruleset_id(options: &MillVariantOptions) -> &'static str {
    mill_ruleset_id(options)
}

fn rules_identity(options: &MillVariantOptions) -> RulesIdentity {
    let identity = mill_rules_identity(options);
    RulesIdentity {
        format_version: identity.format_version,
        sha256: identity.sha256,
    }
}

fn action_name(action_tag: i16) -> &'static str {
    match action_tag {
        0 => "place",
        1 => "select",
        2 => "remove",
        3 => "game_over",
        _ => "unknown",
    }
}

fn outcome_reason_code(reason: &str) -> &'static str {
    match reason {
        "ongoing" => "ongoing",
        "loseFullBoard" => "lose_full_board",
        "loseFewerThanThree" => "lose_fewer_than_three",
        "loseNoLegalMoves" => "lose_no_legal_moves",
        "drawFullBoard" => "draw_full_board",
        "drawFiftyMove" => "draw_fifty_move",
        "drawEndgameFiftyMove" => "draw_endgame_fifty_move",
        "drawThreefoldRepetition" => "draw_threefold_repetition",
        "drawStalemateCondition" => "draw_stalemate_condition",
        "draw" => "draw",
        _ => "unknown",
    }
}

fn prefixed_json(value: &impl Serialize) -> String {
    let payload =
        serde_json::to_string(value).expect("serializing a UCI state payload must not fail");
    format!("{STATE_PREFIX}{payload}")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::mill_uci::board::parse_position_command_strict;

    fn payload(line: &str) -> serde_json::Value {
        serde_json::from_str(
            line.strip_prefix(STATE_PREFIX)
                .expect("state line must use the machine prefix"),
        )
        .expect("state payload must be JSON")
    }

    #[test]
    fn startpos_snapshot_uses_data_query_counts_and_identity() {
        let options = MillVariantOptions::default();
        let rules = MillRules::new(options.clone());
        let position = parse_position_command_strict(&rules, "position startpos").unwrap();
        let value = payload(&state_info_line(&options, &rules, &position, None));

        assert_eq!(value["protocol_version"], 1);
        assert_eq!(value["status"], "ok");
        assert_eq!(value["ruleset_id"], "nmm");
        assert_eq!(value["history_origin"], "game_start");
        assert_eq!(value["phase"], "placing");
        assert_eq!(value["action"], "place");
        assert_eq!(value["action_token_count"], 0);
        assert_eq!(value["logical_ply_count"], 0);
        assert_eq!(value["legal_actions"].as_array().unwrap().len(), 24);
        assert_eq!(
            value["rules_identity"]["sha256"].as_str().unwrap().len(),
            64
        );
        assert_eq!(
            value["strict_referee_identity"]["profile"],
            "sanmill-live-v1"
        );
        assert_eq!(value["strict_referee_identity"]["originCounted"], false);
        assert!(
            value["strict_referee_identity"]["semanticDigest"]
                .as_str()
                .is_some_and(|digest| digest.starts_with("sha256:") && digest.len() == 71)
        );
    }

    #[test]
    fn mill_primary_and_removal_have_distinct_action_and_logical_counts() {
        let options = MillVariantOptions::default();
        let rules = MillRules::new(options.clone());
        let pending =
            parse_position_command_strict(&rules, "position startpos moves d7 a1 g7 d1 a7")
                .unwrap();
        let pending_value = payload(&state_info_line(&options, &rules, &pending, None));
        assert_eq!(pending_value["pending_removal"], true);
        assert_eq!(pending_value["pending_removal_count"], 1);
        assert_eq!(pending_value["action"], "remove");
        assert_eq!(pending_value["action_token_count"], 5);
        assert_eq!(pending_value["logical_ply_count"], 4);

        let complete =
            parse_position_command_strict(&rules, "position startpos moves d7 a1 g7 d1 a7 xa1")
                .unwrap();
        let complete_value = payload(&state_info_line(&options, &rules, &complete, None));
        assert_eq!(complete_value["pending_removal"], false);
        assert_eq!(complete_value["action_token_count"], 6);
        assert_eq!(complete_value["logical_ply_count"], 5);
        assert_eq!(complete_value["logical_plies_by_side"], json!([3, 2]));
        assert_eq!(complete_value["no_capture_count"], 0);
        assert_eq!(complete_value["repetition_history_length"], 0);
    }

    #[test]
    fn imported_terminal_positions_report_authoritative_reasons() {
        let options = MillVariantOptions::default();
        let rules = MillRules::new(options.clone());
        let fewer_than_three = parse_position_command_strict(
            &rules,
            "position fen **O**O**/**@**@**/******** w m s 2 0 2 0 0 0 -1 -1 -1 -1 0 0 1 ids:nodes",
        )
        .unwrap();
        let lost = payload(&state_info_line(&options, &rules, &fewer_than_three, None));
        assert_eq!(lost["status"], "terminal");
        assert_eq!(lost["terminal"], true);
        assert_eq!(lost["winner"], "black");
        assert_eq!(lost["winner_code"], 1);
        assert_eq!(lost["outcome_reason"], "loseFewerThanThree");
        assert_eq!(lost["outcome_reason_code"], "lose_fewer_than_three");

        let no_capture = parse_position_command_strict(
            &rules,
            "position fen ***OOO**/***@@@**/******** w m s 3 0 3 0 0 0 -1 -1 -1 -1 0 100 1 ids:nodes",
        )
        .unwrap();
        let drawn = payload(&state_info_line(&options, &rules, &no_capture, None));
        assert_eq!(drawn["status"], "terminal");
        assert_eq!(drawn["no_capture_count"], 100);
        assert_eq!(drawn["outcome_reason"], "drawFiftyMove");
        assert_eq!(drawn["outcome_reason_code"], "draw_fifty_move");
    }

    #[test]
    fn rejected_position_never_exposes_the_previous_snapshot() {
        let options = MillVariantOptions::default();
        let rules = MillRules::new(options.clone());
        let position = parse_position_command_strict(&rules, "position startpos").unwrap();
        let error =
            parse_position_command_strict(&rules, "position startpos moves a7 a7").unwrap_err();
        let value = payload(&state_info_line(&options, &rules, &position, Some(&error)));

        assert_eq!(value["status"], "position_unavailable");
        assert_eq!(
            value["position_error_code"],
            "position_history_illegal_action"
        );
        assert!(value.get("fen").is_none());
    }
}
