// SPDX-License-Identifier: AGPL-3.0-or-later

use std::collections::BTreeMap;
use std::io::{self, BufRead, Read, Write};

use serde_json::json;

use self::position::ReplayedPosition;
use self::protocol::{
    ApiError, ApiRequest, ApiResponse, ApiStatus, IdentitySource, PROTOCOL_VERSION, PlyCountMode,
};

pub(crate) use self::position::summarize_position;

mod book;
mod hashing;
mod human_db;
mod perfect;
mod position;
mod protocol;

#[derive(Default)]
struct QueryContext {
    perfect_databases: BTreeMap<(String, Option<usize>), perfect::PerfectDbSource>,
    human_databases: BTreeMap<String, human_db::HumanDbSource>,
}

pub(crate) fn run(args: &[String]) {
    let jsonl = match args {
        [] => false,
        [flag] if flag == "--jsonl" => true,
        _ => {
            let response = ApiResponse::error(
                "unknown",
                None,
                ApiError::new(
                    "protocol_error",
                    "data-query accepts only the optional --jsonl flag",
                ),
            );
            println!("{}", serde_json::to_string(&response).unwrap());
            std::process::exit(2);
        }
    };

    let exit_code = if jsonl {
        run_jsonl(io::stdin().lock(), io::stdout().lock())
    } else {
        run_one(io::stdin().lock(), io::stdout().lock())
    };
    if exit_code != 0 {
        std::process::exit(exit_code);
    }
}

fn run_one(mut input: impl Read, mut output: impl Write) -> i32 {
    let mut context = QueryContext::default();
    let mut text = String::new();
    if let Err(error) = input.read_to_string(&mut text) {
        return if write_response(
            &mut output,
            &ApiResponse::error(
                "unknown",
                None,
                ApiError::new("protocol_error", format!("failed to read request: {error}")),
            ),
        ) {
            2
        } else {
            3
        };
    }
    let response = process_text(&mut context, &text);
    let is_error = response.status == ApiStatus::Error;
    if !write_response(&mut output, &response) {
        return 3;
    }
    if is_error { 2 } else { 0 }
}

fn run_jsonl(input: impl BufRead, mut output: impl Write) -> i32 {
    let mut context = QueryContext::default();
    for line in input.lines() {
        let line = match line {
            Ok(line) => line,
            Err(error) => {
                let response = ApiResponse::error(
                    "unknown",
                    None,
                    ApiError::new("protocol_error", format!("failed to read request: {error}")),
                );
                write_response(&mut output, &response);
                return 3;
            }
        };
        if line.trim().is_empty() {
            continue;
        }
        if !write_response(&mut output, &process_text(&mut context, &line)) {
            return 3;
        }
    }
    0
}

fn process_text(context: &mut QueryContext, text: &str) -> ApiResponse {
    let request = match serde_json::from_str::<ApiRequest>(text) {
        Ok(request) => request,
        Err(error) => {
            return ApiResponse::error(
                "unknown",
                None,
                ApiError::new("protocol_error", format!("invalid JSON request: {error}")),
            );
        }
    };
    let operation = request.operation_name();
    let request_id = request.request_id();
    if request.protocol_version() != PROTOCOL_VERSION {
        return ApiResponse::error(
            operation,
            request_id,
            ApiError::new(
                "unsupported_protocol_version",
                format!(
                    "expected protocol_version {PROTOCOL_VERSION}, got {}",
                    request.protocol_version()
                ),
            ),
        );
    }
    process_request(context, request)
}

fn process_request(context: &mut QueryContext, request: ApiRequest) -> ApiResponse {
    match request {
        ApiRequest::QueryBook {
            request_id,
            position,
            asset_path,
            ..
        } => {
            let replayed = match ReplayedPosition::replay(&position) {
                Ok(replayed) => replayed,
                Err(error) => return ApiResponse::error("query_book", request_id, error),
            };
            let state = replayed.state_summary();
            if replayed.is_terminal() {
                return terminal_response("query_book", request_id, state);
            }
            match book::query(&replayed, asset_path.as_deref()) {
                Ok(result) => ApiResponse {
                    protocol_version: PROTOCOL_VERSION,
                    request_id,
                    operation: "query_book".to_owned(),
                    status: if result.candidates.is_empty() {
                        ApiStatus::BookMiss
                    } else {
                        ApiStatus::Available
                    },
                    state: Some(state),
                    source: Some(result.source),
                    candidates: Some(result.candidates),
                    result: None,
                    error: None,
                },
                Err(error) => ApiResponse::error("query_book", request_id, error),
            }
        }
        ApiRequest::QueryPerfectDb {
            request_id,
            position,
            database_path,
            cache_sectors,
            ..
        } => {
            let replayed = match ReplayedPosition::replay(&position) {
                Ok(replayed) => replayed,
                Err(error) => {
                    return ApiResponse::error("query_perfect_db", request_id, error);
                }
            };
            let state = replayed.state_summary();
            if replayed.is_terminal() {
                return terminal_response("query_perfect_db", request_id, state);
            }
            let key = (database_path.clone(), cache_sectors);
            if !context.perfect_databases.contains_key(&key) {
                let source = match perfect::PerfectDbSource::open(&database_path, cache_sectors) {
                    Ok(source) => source,
                    Err(error) => {
                        return ApiResponse::error("query_perfect_db", request_id, error);
                    }
                };
                context.perfect_databases.insert(key.clone(), source);
            }
            let source = context
                .perfect_databases
                .get_mut(&key)
                .expect("inserted Perfect Database source must be present");
            match source.query(&replayed) {
                Ok(result) => ApiResponse {
                    protocol_version: PROTOCOL_VERSION,
                    request_id,
                    operation: "query_perfect_db".to_owned(),
                    status: if result.candidates.is_empty() {
                        ApiStatus::DbMiss
                    } else {
                        ApiStatus::Available
                    },
                    state: Some(state),
                    source: Some(result.source),
                    candidates: Some(result.candidates),
                    result: None,
                    error: None,
                },
                Err(error) => ApiResponse::error("query_perfect_db", request_id, error),
            }
        }
        ApiRequest::QueryHumanDb {
            request_id,
            position,
            database_path,
            candidate_limit,
            min_total,
            ..
        } => {
            let replayed = match ReplayedPosition::replay(&position) {
                Ok(replayed) => replayed,
                Err(error) => {
                    return ApiResponse::error("query_human_db", request_id, error);
                }
            };
            let state = replayed.state_summary();
            if replayed.is_terminal() {
                return terminal_response("query_human_db", request_id, state);
            }
            if !context.human_databases.contains_key(&database_path) {
                let source = match human_db::HumanDbSource::open(&database_path) {
                    Ok(source) => source,
                    Err(error) => {
                        return ApiResponse::error("query_human_db", request_id, error);
                    }
                };
                context
                    .human_databases
                    .insert(database_path.clone(), source);
            }
            let source = context
                .human_databases
                .get(&database_path)
                .expect("inserted Human Database source must be present");
            match source.query(&replayed, candidate_limit, min_total.unwrap_or(0)) {
                Ok(result) => ApiResponse {
                    protocol_version: PROTOCOL_VERSION,
                    request_id,
                    operation: "query_human_db".to_owned(),
                    status: if result.candidates.is_empty() {
                        ApiStatus::HumanDbMiss
                    } else {
                        ApiStatus::Available
                    },
                    state: Some(state),
                    source: Some(result.source),
                    candidates: Some(result.candidates),
                    result: None,
                    error: None,
                },
                Err(error) => ApiResponse::error("query_human_db", request_id, error),
            }
        }
        ApiRequest::HistorySummary {
            request_id,
            position,
            count_mode,
            ..
        } => {
            let replayed = match ReplayedPosition::replay(&position) {
                Ok(replayed) => replayed,
                Err(error) => {
                    return ApiResponse::error("history_summary", request_id, error);
                }
            };
            let state = replayed.state_summary();
            let selected_count = match count_mode {
                PlyCountMode::Logical => state.logical_ply_count,
                PlyCountMode::Actions => state.action_token_count,
            };
            let status = if replayed.is_terminal() {
                ApiStatus::Terminal
            } else {
                ApiStatus::Available
            };
            ApiResponse {
                protocol_version: PROTOCOL_VERSION,
                request_id,
                operation: "history_summary".to_owned(),
                status,
                state: Some(state),
                source: None,
                candidates: None,
                result: Some(json!({
                    "count_mode": match count_mode {
                        PlyCountMode::Logical => "logical",
                        PlyCountMode::Actions => "actions",
                    },
                    "selected_count": selected_count,
                })),
                error: None,
            }
        }
        ApiRequest::SourceIdentity {
            request_id,
            source:
                IdentitySource::Book {
                    variant,
                    asset_path,
                },
            ..
        } => match book::identity(variant, asset_path.as_deref()) {
            Ok(identity) => ApiResponse {
                protocol_version: PROTOCOL_VERSION,
                request_id,
                operation: "source_identity".to_owned(),
                status: ApiStatus::Available,
                state: None,
                source: Some(identity),
                candidates: None,
                result: None,
                error: None,
            },
            Err(error) => ApiResponse::error("source_identity", request_id, error),
        },
        ApiRequest::SourceIdentity {
            request_id,
            source: IdentitySource::HumanDb { database_path },
            ..
        } => match human_db::identity(&database_path) {
            Ok(identity) => ApiResponse {
                protocol_version: PROTOCOL_VERSION,
                request_id,
                operation: "source_identity".to_owned(),
                status: ApiStatus::Available,
                state: None,
                source: Some(identity),
                candidates: None,
                result: None,
                error: None,
            },
            Err(error) => ApiResponse::error("source_identity", request_id, error),
        },
        ApiRequest::SourceIdentity {
            request_id,
            source: IdentitySource::PerfectDb { database_path },
            mode,
            ..
        } => match perfect::identity(&database_path, mode) {
            Ok(identity) => ApiResponse {
                protocol_version: PROTOCOL_VERSION,
                request_id,
                operation: "source_identity".to_owned(),
                status: ApiStatus::Available,
                state: None,
                source: Some(identity),
                candidates: None,
                result: None,
                error: None,
            },
            Err(error) => ApiResponse::error("source_identity", request_id, error),
        },
    }
}

fn terminal_response(
    operation: &str,
    request_id: Option<String>,
    state: protocol::StateSummary,
) -> ApiResponse {
    ApiResponse {
        protocol_version: PROTOCOL_VERSION,
        request_id,
        operation: operation.to_owned(),
        status: ApiStatus::Terminal,
        state: Some(state),
        source: None,
        candidates: Some(Vec::new()),
        result: None,
        error: None,
    }
}

fn write_response(output: &mut impl Write, response: &ApiResponse) -> bool {
    match serde_json::to_writer(&mut *output, response)
        .and_then(|_| output.write_all(b"\n").map_err(serde_json::Error::io))
        .and_then(|_| output.flush().map_err(serde_json::Error::io))
    {
        Ok(()) => true,
        Err(error) => {
            eprintln!("failed to write data-query response: {error}");
            false
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn history_summary_rejects_illegal_actions_without_fallback() {
        let request = r#"{
            "operation":"history_summary",
            "protocol_version":1,
            "position":{
                "rule":"nmm",
                "initial":"startpos",
                "history_origin":"game_start",
                "actions":["not-a-move"]
            }
        }"#;
        let response = process_text(&mut QueryContext::default(), request);
        assert_eq!(response.status, ApiStatus::Error);
        assert_eq!(response.error.unwrap().code, "protocol_error");
    }

    #[test]
    fn history_summary_counts_completed_turns() {
        let request = r#"{
            "operation":"history_summary",
            "protocol_version":1,
            "position":{
                "rule":"nmm",
                "initial":"startpos",
                "history_origin":"game_start",
                "actions":["d7","a1","g7","d1","a7","xa1"]
            }
        }"#;
        let response = process_text(&mut QueryContext::default(), request);
        assert_eq!(response.status, ApiStatus::Available);
        let state = response.state.unwrap();
        assert_eq!(state.action_token_count, 6);
        assert_eq!(state.logical_ply_count, 5);
        assert_eq!(state.logical_plies_by_side, [3, 2]);
    }

    #[test]
    fn eight_logical_plies_are_four_turns_per_side() {
        let request = r#"{
            "operation":"history_summary",
            "protocol_version":1,
            "position":{
                "rule":"nmm",
                "initial":"startpos",
                "history_origin":"game_start",
                "actions":["d7","a1","g7","d1","a7","xa1","a4","b6","g1"]
            },
            "count_mode":"logical"
        }"#;
        let response = process_text(&mut QueryContext::default(), request);
        assert_eq!(response.status, ApiStatus::Available);
        let state = response.state.unwrap();
        assert_eq!(state.action_token_count, 9);
        assert_eq!(state.logical_ply_count, 8);
        assert_eq!(state.logical_plies_by_side, [4, 4]);
        assert_eq!(response.result.unwrap()["selected_count"], 8);
    }

    #[test]
    fn action_count_mode_remains_explicitly_available() {
        let request = r#"{
            "operation":"history_summary",
            "protocol_version":1,
            "position":{
                "rule":"nmm",
                "initial":"startpos",
                "history_origin":"game_start",
                "actions":["d7","a1","g7","d1","a7","xa1"]
            },
            "count_mode":"actions"
        }"#;
        let response = process_text(&mut QueryContext::default(), request);
        assert_eq!(response.status, ApiStatus::Available);
        let state = response.state.unwrap();
        assert_eq!(state.action_token_count, 6);
        assert_eq!(state.logical_ply_count, 5);
        assert_eq!(response.result.unwrap()["selected_count"], 6);
    }

    #[test]
    fn terminal_positions_return_terminal_without_candidates() {
        let request = r#"{
            "operation":"query_book",
            "protocol_version":1,
            "position":{
                "rule":"nmm",
                "initial":"O*O*O*O*/*@*@*@*@/O@O@O@O@ w o p 9 0 9 0 0 0 -1 -1 -1 -1 0 0 1 ids:nodes",
                "history_origin":"fresh_setup",
                "actions":[]
            }
        }"#;
        let response = process_text(&mut QueryContext::default(), request);
        assert_eq!(response.status, ApiStatus::Terminal);
        assert_eq!(response.state.unwrap().phase, "game_over");
        assert!(response.candidates.unwrap().is_empty());
        assert!(response.source.is_none());
    }

    #[test]
    fn pending_removal_without_its_primary_action_fails_closed() {
        let request = r#"{
            "operation":"query_book",
            "protocol_version":1,
            "position":{
                "rule":"nmm",
                "initial":"********/********/OO**@@*O w p r 3 6 2 7 1 0 -1 -1 -1 -1 0 0 3 ids:nodes",
                "history_origin":"fresh_setup",
                "actions":[]
            }
        }"#;
        let response = process_text(&mut QueryContext::default(), request);
        assert_eq!(response.status, ApiStatus::Error);
        assert_eq!(response.error.unwrap().code, "incomplete_history");
    }

    #[test]
    fn explicit_fen_cannot_claim_a_missing_game_start_history() {
        let request = r#"{
            "operation":"history_summary",
            "protocol_version":1,
            "position":{
                "rule":"nmm",
                "initial":"********/********/******** w p p 0 9 0 9 0 0 -1 -1 -1 -1 0 0 1 ids:nodes",
                "history_origin":"game_start",
                "actions":[]
            }
        }"#;
        let response = process_text(&mut QueryContext::default(), request);
        assert_eq!(response.status, ApiStatus::Error);
        assert_eq!(response.error.unwrap().code, "protocol_error");
    }

    #[test]
    fn replay_preserves_no_capture_and_repetition_history_evidence() {
        let initial = "******O@/O*******/*@@****O w m s 3 0 3 0 0 0 -1 -1 -1 -1 0 0 1 ids:nodes";
        let first_request = format!(
            r#"{{
                "operation":"history_summary",
                "protocol_version":1,
                "position":{{
                    "rule":"nmm",
                    "initial":{initial:?},
                    "history_origin":"fresh_setup",
                    "actions":["d6-d7","g4-g1","d7-d6","g1-g4"]
                }}
            }}"#
        );
        let second_request = format!(
            r#"{{
                "operation":"history_summary",
                "protocol_version":1,
                "position":{{
                    "rule":"nmm",
                    "initial":{initial:?},
                    "history_origin":"fresh_setup",
                    "actions":["d6-a4","g4-b4","a4-d6","b4-g4"]
                }}
            }}"#
        );

        let first = process_text(&mut QueryContext::default(), &first_request);
        let second = process_text(&mut QueryContext::default(), &second_request);
        assert_eq!(first.status, ApiStatus::Available);
        assert_eq!(second.status, ApiStatus::Available);
        let first_state = first.state.unwrap();
        let second_state = second.state.unwrap();
        assert_eq!(first_state.current_fen, second_state.current_fen);
        assert_eq!(first_state.snapshot_history_len, 4);
        assert_eq!(second_state.snapshot_history_len, 4);
        assert_eq!(first_state.no_capture_plies, 4);
        assert_eq!(second_state.no_capture_plies, 4);
        assert_eq!(first_state.repetition_history_len, 4);
        assert_eq!(second_state.repetition_history_len, 4);
        assert_ne!(
            first_state.history_sha256, second_state.history_sha256,
            "equal current FENs with different complete histories need distinct identities"
        );
    }
}
