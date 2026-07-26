// SPDX-License-Identifier: AGPL-3.0-or-later

use std::collections::BTreeSet;
use std::path::Path;

use serde_json::Value;
use tgf_cli::h2h_trace::{
    H2H_MANIFEST_SCHEMA_VERSION, H2H_TRACE_SCHEMA_VERSION, H2hActor, H2hGameTraceV1,
    H2hGameTraceV2, H2hTraceManifestV2, mill_rules_identity,
};

use super::model::{AnalyzerError, LoadedRun, NormalizedGame, TraceFormat};

pub(crate) fn load_run(
    log_path: &Path,
    manifest_path: Option<&Path>,
) -> Result<LoadedRun, AnalyzerError> {
    let text = std::fs::read_to_string(log_path).map_err(|error| {
        AnalyzerError::arguments(
            "log_read_error",
            format!("failed to read {}: {error}", log_path.display()),
        )
    })?;
    let nonempty = text
        .lines()
        .enumerate()
        .filter(|(_, line)| !line.trim().is_empty())
        .collect::<Vec<_>>();
    if nonempty.is_empty() {
        return Err(AnalyzerError::incomplete(
            "empty_trace",
            format!("{} contains no game rows", log_path.display()),
        ));
    }

    let mut parsed = Vec::new();
    let mut truncated_tail = None;
    for (position, (line_index, line)) in nonempty.iter().enumerate() {
        match serde_json::from_str::<Value>(line) {
            Ok(value) => parsed.push((*line_index + 1, value)),
            Err(error) if position + 1 == nonempty.len() => {
                truncated_tail = Some(format!(
                    "truncated JSONL tail at line {}: {error}",
                    line_index + 1
                ));
            }
            Err(error) => {
                return Err(AnalyzerError::arguments(
                    "malformed_trace_row",
                    format!(
                        "{} line {} is not valid JSON: {error}",
                        log_path.display(),
                        line_index + 1
                    ),
                ));
            }
        }
    }
    if parsed.is_empty() {
        return Err(AnalyzerError::incomplete(
            "truncated_trace",
            truncated_tail.unwrap_or_else(|| "trace has no complete rows".to_string()),
        ));
    }

    let versions = parsed
        .iter()
        .map(|(_, value)| {
            value
                .get("schema_version")
                .and_then(Value::as_u64)
                .unwrap_or(1) as u32
        })
        .collect::<BTreeSet<_>>();
    if versions.len() != 1 {
        return Err(AnalyzerError::arguments(
            "mixed_trace_schema",
            format!("one JSONL run mixes schema versions {versions:?}"),
        ));
    }
    let version = *versions.first().expect("non-empty version set");
    let format = match version {
        1 => TraceFormat::V1,
        H2H_TRACE_SCHEMA_VERSION => TraceFormat::V2,
        other => {
            return Err(AnalyzerError::arguments(
                "unsupported_trace_schema",
                format!("trace schema version {other} is not supported"),
            ));
        }
    };

    let mut games = Vec::with_capacity(parsed.len());
    for (line, value) in parsed {
        let game = match format {
            TraceFormat::V1 => normalize_v1(serde_json::from_value(value).map_err(|error| {
                AnalyzerError::arguments(
                    "invalid_v1_trace",
                    format!("line {line} does not match H2H v1: {error}"),
                )
            })?),
            TraceFormat::V2 => normalize_v2(serde_json::from_value(value).map_err(|error| {
                AnalyzerError::arguments(
                    "invalid_v2_trace",
                    format!("line {line} does not match H2H v2: {error}"),
                )
            })?)?,
        };
        games.push(game);
    }
    games.sort_by_key(|game| game.game_index);
    validate_indices(&games)?;

    let (manifest, source_manifest) = if let Some(path) = manifest_path {
        let bytes = std::fs::read(path).map_err(|error| {
            AnalyzerError::arguments(
                "manifest_read_error",
                format!("failed to read {}: {error}", path.display()),
            )
        })?;
        let manifest: H2hTraceManifestV2 = serde_json::from_slice(&bytes).map_err(|error| {
            AnalyzerError::arguments(
                "manifest_schema_error",
                format!("failed to parse {}: {error}", path.display()),
            )
        })?;
        (Some(manifest), Some(path.to_path_buf()))
    } else {
        (None, None)
    };

    if format == TraceFormat::V2 {
        validate_v2_manifest(&games, manifest.as_ref())?;
    }
    let mut incomplete = truncated_tail;
    if let Some(manifest) = manifest.as_ref() {
        if manifest.completed_games != games.len() {
            append_incomplete(
                &mut incomplete,
                format!(
                    "manifest says {} completed games but JSONL has {} complete rows",
                    manifest.completed_games,
                    games.len()
                ),
            );
        }
        if manifest.completed_games != manifest.expected_games {
            append_incomplete(
                &mut incomplete,
                format!(
                    "run stopped at {}/{} expected games",
                    manifest.completed_games, manifest.expected_games
                ),
            );
        }
    }

    Ok(LoadedRun {
        format,
        games,
        manifest,
        source_log: log_path.to_path_buf(),
        source_manifest,
        truncated_tail: incomplete,
    })
}

fn normalize_v1(game: H2hGameTraceV1) -> NormalizedGame {
    let winner = match (game.result.as_str(), game.current_white) {
        ("win", Some(true)) | ("loss", Some(false)) => Some(H2hActor::White),
        ("win", Some(false)) | ("loss", Some(true)) => Some(H2hActor::Black),
        _ => None,
    };
    NormalizedGame {
        schema_version: 1,
        run_id: None,
        game_index: game.game_index,
        pair_index: game.game_index / 2,
        worker_id: None,
        current_white: game.current_white,
        result: game.result,
        plies: game.plies,
        opening_moves: game.opening_moves,
        moves: game.moves,
        white_seed: game.white_seed,
        black_seed: game.black_seed,
        white_engine_instance_id: None,
        black_engine_instance_id: None,
        winner,
        outcome_reason: None,
        end_kind: None,
        decisions: Vec::new(),
    }
}

fn normalize_v2(game: H2hGameTraceV2) -> Result<NormalizedGame, AnalyzerError> {
    if game.schema_version != H2H_TRACE_SCHEMA_VERSION {
        return Err(AnalyzerError::arguments(
            "invalid_v2_trace",
            format!(
                "game {} declares schema version {}",
                game.game_index, game.schema_version
            ),
        ));
    }
    if game.pair_index != game.game_index / 2 {
        return Err(AnalyzerError::arguments(
            "pair_index_mismatch",
            format!(
                "game {} declares pair_index {}, expected {}",
                game.game_index,
                game.pair_index,
                game.game_index / 2
            ),
        ));
    }
    if game.atomic_actions != game.moves {
        return Err(AnalyzerError::arguments(
            "atomic_action_mismatch",
            format!(
                "game {} has different `moves` and `atomic_actions` arrays",
                game.game_index
            ),
        ));
    }
    Ok(NormalizedGame {
        schema_version: game.schema_version,
        run_id: Some(game.run_id),
        game_index: game.game_index,
        pair_index: game.pair_index,
        worker_id: Some(game.worker_id),
        current_white: game.current_white,
        result: game.result,
        plies: game.plies,
        opening_moves: game.opening_moves,
        moves: game.moves,
        white_seed: game.white_seed,
        black_seed: game.black_seed,
        white_engine_instance_id: Some(game.white_engine_instance_id),
        black_engine_instance_id: Some(game.black_engine_instance_id),
        winner: game.winner,
        outcome_reason: Some(game.outcome_reason),
        end_kind: Some(game.end_kind),
        decisions: game.decisions,
    })
}

fn validate_indices(games: &[NormalizedGame]) -> Result<(), AnalyzerError> {
    for pair in games.windows(2) {
        if pair[0].game_index == pair[1].game_index {
            return Err(AnalyzerError::arguments(
                "duplicate_game_index",
                format!("game_index {} appears more than once", pair[0].game_index),
            ));
        }
        if pair[1].game_index != pair[0].game_index + 1 {
            return Err(AnalyzerError::arguments(
                "missing_game_index",
                format!(
                    "game_index gap between {} and {}",
                    pair[0].game_index, pair[1].game_index
                ),
            ));
        }
    }
    if games.first().is_some_and(|game| game.game_index != 0) {
        return Err(AnalyzerError::arguments(
            "missing_game_index",
            format!("first game_index is {}, expected 0", games[0].game_index),
        ));
    }
    Ok(())
}

fn validate_v2_manifest(
    games: &[NormalizedGame],
    manifest: Option<&H2hTraceManifestV2>,
) -> Result<(), AnalyzerError> {
    let manifest = manifest.ok_or_else(|| {
        AnalyzerError::arguments(
            "manifest_required",
            "H2H trace v2 requires its sidecar manifest",
        )
    })?;
    if manifest.schema_version != H2H_MANIFEST_SCHEMA_VERSION {
        return Err(AnalyzerError::arguments(
            "manifest_schema_error",
            format!("manifest schema {} is unsupported", manifest.schema_version),
        ));
    }
    match manifest.mode.as_str() {
        "vs" if manifest.reference.is_none() => {
            return Err(AnalyzerError::arguments(
                "manifest_reference_missing",
                "a `vs` trace manifest requires a reference engine identity",
            ));
        }
        "vs" => {}
        "self-current" | "self-master" if manifest.reference.is_some() => {
            return Err(AnalyzerError::arguments(
                "manifest_reference_unexpected",
                "a self-play trace must not declare an unused reference engine",
            ));
        }
        "self-current" | "self-master" => {}
        other => {
            return Err(AnalyzerError::arguments(
                "unsupported_h2h_mode",
                format!("manifest H2H mode `{other}` is not supported"),
            ));
        }
    }
    if manifest.candidate.role != "candidate"
        || manifest
            .reference
            .as_ref()
            .is_some_and(|identity| identity.role != "reference")
    {
        return Err(AnalyzerError::arguments(
            "manifest_engine_role_mismatch",
            "manifest engine identities do not use candidate/reference roles",
        ));
    }
    if manifest.reproducibility.deterministic
        && !(manifest.reproducibility.fixed_nodes
            && manifest.reproducibility.single_thread
            && manifest.reproducibility.fixed_opening_seed
            && manifest.reproducibility.fixed_search_seed
            && manifest.reproducibility.non_timed_search
            && manifest.config.ai_is_lazy == Some(false))
    {
        return Err(AnalyzerError::arguments(
            "manifest_reproducibility_contradiction",
            "manifest claims deterministic search while a reproducibility prerequisite is false",
        ));
    }
    let recomputed = mill_rules_identity(&manifest.rules.options);
    if recomputed.sha256 != manifest.rules.sha256
        || recomputed.format_version != manifest.rules.format_version
        || recomputed.ruleset_id != manifest.rules.ruleset_id
    {
        return Err(AnalyzerError::arguments(
            "rules_identity_mismatch",
            "manifest rules SHA-256 does not match its serialized options",
        ));
    }
    for game in games {
        if game.run_id.as_deref() != Some(manifest.run_id.as_str()) {
            return Err(AnalyzerError::arguments(
                "run_id_mismatch",
                format!(
                    "game {} run_id {:?} differs from manifest {}",
                    game.game_index, game.run_id, manifest.run_id
                ),
            ));
        }
        let colour_shape_matches = match manifest.mode.as_str() {
            "vs" => game.current_white.is_some(),
            "self-current" | "self-master" => game.current_white.is_none(),
            _ => false,
        };
        if !colour_shape_matches {
            return Err(AnalyzerError::arguments(
                "trace_mode_game_mismatch",
                format!(
                    "game {} current_white metadata contradicts manifest mode {}",
                    game.game_index, manifest.mode
                ),
            ));
        }
    }
    Ok(())
}

fn append_incomplete(target: &mut Option<String>, message: String) {
    match target {
        Some(existing) => {
            existing.push_str("; ");
            existing.push_str(&message);
        }
        None => *target = Some(message),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn temp_path(name: &str) -> std::path::PathBuf {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir().join(format!("sanmill-h2h-{name}-{nonce}.jsonl"))
    }

    #[test]
    fn accepts_v1_and_rejects_mixed_schema() {
        let path = temp_path("v1");
        std::fs::write(
            &path,
            "{\"game_index\":0,\"current_white\":true,\"result\":\"draw\",\"plies\":0,\"moves\":[]}\n",
        )
        .unwrap();
        let run = load_run(&path, None).unwrap();
        assert_eq!(run.format, TraceFormat::V1);
        std::fs::remove_file(&path).ok();

        let path = temp_path("mixed");
        std::fs::write(
            &path,
            concat!(
                "{\"game_index\":0,\"result\":\"draw\",\"plies\":0,\"moves\":[]}\n",
                "{\"schema_version\":2,\"game_index\":1}\n"
            ),
        )
        .unwrap();
        assert_eq!(
            load_run(&path, None).unwrap_err().code,
            "mixed_trace_schema"
        );
        std::fs::remove_file(&path).ok();
    }

    #[test]
    fn rejects_duplicate_and_missing_indices() {
        let duplicate = temp_path("duplicate");
        std::fs::write(
            &duplicate,
            concat!(
                "{\"game_index\":0,\"result\":\"draw\",\"plies\":0,\"moves\":[]}\n",
                "{\"game_index\":0,\"result\":\"draw\",\"plies\":0,\"moves\":[]}\n"
            ),
        )
        .unwrap();
        assert_eq!(
            load_run(&duplicate, None).unwrap_err().code,
            "duplicate_game_index"
        );
        std::fs::remove_file(&duplicate).ok();

        let missing = temp_path("missing");
        std::fs::write(
            &missing,
            concat!(
                "{\"game_index\":0,\"result\":\"draw\",\"plies\":0,\"moves\":[]}\n",
                "{\"game_index\":2,\"result\":\"draw\",\"plies\":0,\"moves\":[]}\n"
            ),
        )
        .unwrap();
        assert_eq!(
            load_run(&missing, None).unwrap_err().code,
            "missing_game_index"
        );
        std::fs::remove_file(&missing).ok();
    }

    #[test]
    fn retains_a_truncated_final_row_as_incomplete_evidence() {
        let path = temp_path("truncated");
        std::fs::write(
            &path,
            concat!(
                "{\"game_index\":0,\"result\":\"draw\",\"plies\":0,\"moves\":[]}\n",
                "{\"game_index\":1"
            ),
        )
        .unwrap();
        let run = load_run(&path, None).unwrap();
        assert_eq!(run.games.len(), 1);
        assert!(
            run.truncated_tail
                .as_deref()
                .is_some_and(|message| message.contains("truncated JSONL tail"))
        );
        std::fs::remove_file(&path).ok();
    }
}
