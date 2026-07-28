// SPDX-License-Identifier: AGPL-3.0-or-later
// Plain JSON boundary between external constraint solvers and Rust/Perfect DB.

use std::collections::HashSet;

use perfect_db::database::PerfectQuery;
use perfect_db::query_from_state;
use serde::Deserialize;
use tgf_core::{Action, GameRules, OutcomeKind};
use tgf_mill::human_db_codec::{HumanTurn, parse_human_turn_notation_with_history};
use tgf_mill::{MillRules, MillVariantOptions};

use super::motifs::PuzzleMotif;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ConstraintCandidatePackage {
    format_version: String,
    #[serde(default)]
    solver: Option<SolverIdentity>,
    #[serde(default)]
    source: Option<HumanSourceIdentity>,
    #[serde(default)]
    motif: Option<String>,
    #[serde(default)]
    rule_variant_id: Option<String>,
    candidates: Vec<ConstraintCandidate>,
}

#[derive(Debug, Deserialize)]
struct SolverIdentity {
    name: String,
    version: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct HumanSourceIdentity {
    kind: String,
    corpus: String,
    database_sha256: String,
    transform_model: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ConstraintCandidate {
    white_bits: u32,
    black_bits: u32,
    white_in_hand: u8,
    black_in_hand: u8,
    side_to_move: u8,
    #[serde(default)]
    replay: Option<HumanReplayJson>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct HumanReplayJson {
    history: Vec<String>,
    recorded_turn: String,
    source_game_sha256: String,
    source_logical_ply: usize,
    presentation_transform: u8,
    position_games: u64,
    recorded_turn_games: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) enum CandidateDiscovery {
    SmtZ3 {
        solver_version: String,
    },
    HumanGameReplay {
        corpus: String,
        database_sha256: String,
        transform_model: String,
    },
    EngineBlunderCorpus {
        manifest_sha256: String,
        source_file_count: usize,
        inspected_rows: usize,
        eligible_rows: usize,
    },
}

#[derive(Clone, Debug)]
pub(super) struct HumanReplayEvidence {
    pub corpus: String,
    pub database_sha256: String,
    pub transform_model: String,
    pub history: Vec<String>,
    pub recorded_turn: String,
    pub recorded_actions: Vec<Action>,
    pub source_game_sha256: String,
    pub source_logical_ply: usize,
    pub presentation_transform: u8,
    pub position_games: u64,
    pub recorded_turn_games: u64,
}

#[derive(Clone, Debug)]
pub(super) struct EngineBlunderEvidence {
    pub severity: i8,
    pub trap_score: u8,
    pub mass: f64,
    pub depth_used: i32,
}

pub(super) struct LoadedCandidate {
    pub query: PerfectQuery,
    pub replay: Option<HumanReplayEvidence>,
    pub engine_blunder: Option<EngineBlunderEvidence>,
}

pub(super) struct LoadedCandidateSet {
    pub motif: PuzzleMotif,
    pub discovery: CandidateDiscovery,
    pub candidates: Vec<LoadedCandidate>,
}

pub(super) fn load_constraint_candidates(path: &str) -> LoadedCandidateSet {
    let text = std::fs::read_to_string(path)
        .unwrap_or_else(|err| panic!("[puzzle-gen] cannot read candidate file {path}: {err}"));
    parse_constraint_candidates(&text)
        .unwrap_or_else(|err| panic!("[puzzle-gen] invalid candidate file {path}: {err}"))
}

fn parse_constraint_candidates(text: &str) -> Result<LoadedCandidateSet, String> {
    let package: ConstraintCandidatePackage =
        serde_json::from_str(text).map_err(|err| format!("invalid JSON: {err}"))?;
    if package.format_version != "1.0" {
        return Err(format!(
            "unsupported formatVersion {}; expected 1.0",
            package.format_version
        ));
    }
    if package.candidates.is_empty() {
        return Err("candidate array must not be empty".to_string());
    }

    let (motif, discovery) = match (package.solver, package.source) {
        (Some(solver), None) => {
            if !solver.name.eq_ignore_ascii_case("z3") {
                return Err(format!(
                    "solver must be Z3 for discovery:smt-z3 provenance, got {}",
                    solver.name
                ));
            }
            if solver.version.trim().is_empty() {
                return Err("solver version must not be empty".to_string());
            }
            let motif_name = package.motif.as_deref().unwrap_or_default();
            let motif = PuzzleMotif::parse(motif_name);
            if motif == PuzzleMotif::Any {
                return Err(format!("unsupported or missing motif `{motif_name}`"));
            }
            (
                motif,
                CandidateDiscovery::SmtZ3 {
                    solver_version: solver.version,
                },
            )
        }
        (None, Some(source)) if source.kind == "human-game-replay" => {
            if package.rule_variant_id.as_deref() != Some("standard_9mm") {
                return Err(
                    "human replay packages must declare ruleVariantId standard_9mm".to_string(),
                );
            }
            validate_sha256("databaseSha256", &source.database_sha256)?;
            if source.corpus.trim().is_empty() {
                return Err("human replay corpus must not be empty".to_string());
            }
            if source.transform_model != "sanmill-ring16-v1" {
                return Err(format!(
                    "unsupported human replay transform model {}",
                    source.transform_model
                ));
            }
            (
                PuzzleMotif::Any,
                CandidateDiscovery::HumanGameReplay {
                    corpus: source.corpus,
                    database_sha256: source.database_sha256,
                    transform_model: source.transform_model,
                },
            )
        }
        (Some(_), Some(_)) => {
            return Err(
                "candidate package must declare either solver or source, not both".to_string(),
            );
        }
        _ => return Err("candidate package must declare a solver or source".to_string()),
    };

    let mut seen = HashSet::new();
    let mut candidates = Vec::with_capacity(package.candidates.len());
    for (index, candidate) in package.candidates.into_iter().enumerate() {
        if candidate.white_bits & !0x00ff_ffff != 0 || candidate.black_bits & !0x00ff_ffff != 0 {
            return Err(format!(
                "candidate {index} uses bits outside the 24-node board"
            ));
        }
        if candidate.white_bits & candidate.black_bits != 0 {
            return Err(format!("candidate {index} overlaps white and black pieces"));
        }
        if candidate.side_to_move > 1 {
            return Err(format!(
                "candidate {index} has invalid sideToMove {}",
                candidate.side_to_move
            ));
        }
        if candidate.white_in_hand > 12 || candidate.black_in_hand > 12 {
            return Err(format!("candidate {index} has an impossible hand count"));
        }
        if candidate.white_bits.count_ones() + u32::from(candidate.white_in_hand) > 12
            || candidate.black_bits.count_ones() + u32::from(candidate.black_in_hand) > 12
        {
            return Err(format!(
                "candidate {index} exceeds the maximum supported piece budget"
            ));
        }
        let raw_key = u64::from(candidate.white_bits)
            | (u64::from(candidate.black_bits) << 24)
            | (u64::from(candidate.white_in_hand) << 48)
            | (u64::from(candidate.black_in_hand) << 52)
            | (u64::from(candidate.side_to_move) << 56);
        if !seen.insert(raw_key) {
            return Err(format!(
                "candidate {index} duplicates an earlier exact root"
            ));
        }
        let query = PerfectQuery::new(
            candidate.white_bits,
            candidate.black_bits,
            candidate.white_in_hand,
            candidate.black_in_hand,
            candidate.side_to_move,
            false,
        );
        let replay = match &discovery {
            CandidateDiscovery::SmtZ3 { .. } => {
                if candidate.replay.is_some() {
                    return Err(format!(
                        "Z3 candidate {index} must not claim human replay evidence"
                    ));
                }
                None
            }
            CandidateDiscovery::HumanGameReplay {
                corpus,
                database_sha256,
                transform_model,
            } => Some(validate_human_replay(
                index,
                query,
                candidate
                    .replay
                    .ok_or_else(|| format!("human candidate {index} is missing replay evidence"))?,
                corpus,
                database_sha256,
                transform_model,
            )?),
            CandidateDiscovery::EngineBlunderCorpus { .. } => {
                unreachable!("constraint packages cannot declare a mine-entry source")
            }
        };
        candidates.push(LoadedCandidate {
            query,
            replay,
            engine_blunder: None,
        });
    }

    Ok(LoadedCandidateSet {
        motif,
        discovery,
        candidates,
    })
}

fn validate_sha256(label: &str, value: &str) -> Result<(), String> {
    if value.len() != 64 || !value.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return Err(format!("{label} must be a 64-character hexadecimal digest"));
    }
    Ok(())
}

fn human_turn_actions(turn: HumanTurn) -> Vec<Action> {
    match turn {
        HumanTurn::BaseOnly(action) | HumanTurn::CaptureOnly(action) => vec![action],
        HumanTurn::BaseThenCapture { base, capture } => vec![base, capture],
    }
}

fn validate_human_replay(
    index: usize,
    expected_query: PerfectQuery,
    replay: HumanReplayJson,
    corpus: &str,
    database_sha256: &str,
    transform_model: &str,
) -> Result<HumanReplayEvidence, String> {
    validate_sha256("sourceGameSha256", &replay.source_game_sha256)?;
    if replay.presentation_transform >= 16 {
        return Err(format!(
            "human candidate {index} has presentationTransform outside 0..15"
        ));
    }
    if replay.source_logical_ply != replay.history.len() + 1 {
        return Err(format!(
            "human candidate {index} sourceLogicalPly does not follow its replay history"
        ));
    }
    if replay.recorded_turn.trim().is_empty() {
        return Err(format!("human candidate {index} has an empty recordedTurn"));
    }
    if replay.position_games == 0 || replay.recorded_turn_games == 0 {
        return Err(format!(
            "human candidate {index} must retain positive HumanDB sample counts"
        ));
    }

    let options = MillVariantOptions::default();
    let rules = MillRules::new(options.clone());
    let mut snapshot = rules.initial_state(&[]);
    let mut history = Vec::new();
    for (logical_ply, notation) in replay.history.iter().enumerate() {
        let turn = parse_human_turn_notation_with_history(&rules, &snapshot, &history, notation)
            .map_err(|error| {
                format!(
                    "human candidate {index} replay logical ply {} is illegal: {error:?}",
                    logical_ply + 1
                )
            })?;
        for action in human_turn_actions(turn) {
            let next = rules.apply_with_history(&snapshot, action, &history);
            history.push(snapshot);
            snapshot = next;
        }
    }
    if rules.outcome(&snapshot).kind != OutcomeKind::Ongoing {
        return Err(format!(
            "human candidate {index} replay reaches a terminal root"
        ));
    }
    let state = MillRules::decode_snapshot(snapshot);
    let replayed_query = query_from_state(&state, &options, snapshot.side_to_move)
        .ok_or_else(|| format!("human candidate {index} replay is outside Perfect DB rules"))?;
    if replayed_query != expected_query {
        return Err(format!(
            "human candidate {index} bitboards do not match its replayed root"
        ));
    }
    let recorded_turn =
        parse_human_turn_notation_with_history(&rules, &snapshot, &history, &replay.recorded_turn)
            .map_err(|error| {
                format!("human candidate {index} recordedTurn is illegal at its root: {error:?}")
            })?;

    Ok(HumanReplayEvidence {
        corpus: corpus.to_string(),
        database_sha256: database_sha256.to_string(),
        transform_model: transform_model.to_string(),
        history: replay.history,
        recorded_turn: replay.recorded_turn,
        recorded_actions: human_turn_actions(recorded_turn),
        source_game_sha256: replay.source_game_sha256.to_ascii_lowercase(),
        source_logical_ply: replay.source_logical_ply,
        presentation_transform: replay.presentation_transform,
        position_games: replay.position_games,
        recorded_turn_games: replay.recorded_turn_games,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_a_z3_candidate_package() {
        let loaded = parse_constraint_candidates(
            r#"{
              "formatVersion": "1.0",
              "solver": {"name": "Z3", "version": "5.0.0"},
              "motif": "dual-threat",
              "candidates": [{
                "whiteBits": 7,
                "blackBits": 56,
                "whiteInHand": 0,
                "blackInHand": 0,
                "sideToMove": 0,
                "witness": {"from": "a4", "to": "a7"}
              }]
            }"#,
        )
        .expect("valid package must parse");
        assert_eq!(loaded.motif, PuzzleMotif::DualThreat);
        assert_eq!(
            loaded.discovery,
            CandidateDiscovery::SmtZ3 {
                solver_version: "5.0.0".to_string()
            }
        );
        assert_eq!(loaded.candidates.len(), 1);
        assert_eq!(loaded.candidates[0].query.white_bits, 7);
    }

    #[test]
    fn rejects_false_z3_provenance() {
        let err = parse_constraint_candidates(
            r#"{
              "formatVersion": "1.0",
              "solver": {"name": "random sampler", "version": "1"},
              "motif": "dual-threat",
              "candidates": [{
                "whiteBits": 1,
                "blackBits": 2,
                "whiteInHand": 0,
                "blackInHand": 0,
                "sideToMove": 0
              }]
            }"#,
        )
        .err()
        .expect("non-Z3 source must be rejected");
        assert!(err.contains("solver must be Z3"));
    }

    #[test]
    fn accepts_only_a_human_root_reached_by_its_replay() {
        let loaded = parse_constraint_candidates(
            r#"{
              "formatVersion": "1.0",
              "ruleVariantId": "standard_9mm",
              "source": {
                "kind": "human-game-replay",
                "corpus": "HumanDB raw human games",
                "databaseSha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                "transformModel": "sanmill-ring16-v1"
              },
              "candidates": [{
                "whiteBits": 2,
                "blackBits": 4,
                "whiteInHand": 8,
                "blackInHand": 8,
                "sideToMove": 0,
                "replay": {
                  "history": ["a7", "d7"],
                  "recordedTurn": "g7",
                  "sourceGameSha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                  "sourceLogicalPly": 3,
                  "presentationTransform": 0,
                  "positionGames": 4,
                  "recordedTurnGames": 1
                }
              }]
            }"#,
        )
        .expect("a legal replay-backed candidate must parse");

        assert_eq!(loaded.motif, PuzzleMotif::Any);
        assert_eq!(loaded.candidates.len(), 1);
        let replay = loaded.candidates[0]
            .replay
            .as_ref()
            .expect("human candidate must retain replay evidence");
        assert_eq!(replay.history, ["a7", "d7"]);
        assert_eq!(replay.recorded_turn, "g7");
        assert_eq!(replay.recorded_actions.len(), 1);
    }
}
