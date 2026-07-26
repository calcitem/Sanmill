// SPDX-License-Identifier: AGPL-3.0-or-later

use std::path::PathBuf;

use perfect_db::database::PerfectOutcome;
use serde::{Deserialize, Serialize};
use tgf_cli::h2h_trace::{H2hActor, H2hDecisionTraceV2, H2hGameEndKind, H2hTraceManifestV2};
use tgf_core::{Action, GameStateSnapshot};

#[derive(Clone, Debug)]
pub(crate) struct AnalyzerError {
    pub exit_code: i32,
    pub code: String,
    pub message: String,
}

impl AnalyzerError {
    pub fn arguments(code: &str, message: impl Into<String>) -> Self {
        Self {
            exit_code: 2,
            code: code.to_string(),
            message: message.into(),
        }
    }

    pub fn incomplete(code: &str, message: impl Into<String>) -> Self {
        Self {
            exit_code: 3,
            code: code.to_string(),
            message: message.into(),
        }
    }
}

impl std::fmt::Display for AnalyzerError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(formatter, "{}: {}", self.code, self.message)
    }
}

impl std::error::Error for AnalyzerError {}

pub(crate) const ANALYSIS_SCHEMA_VERSION: u32 = 1;
pub(crate) const BASELINE_SCHEMA_VERSION: u32 = 1;
pub(crate) const Z_99_9: f64 = 3.290_526_731_491_925;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum TraceFormat {
    V1,
    V2,
}

#[derive(Clone, Debug)]
pub(crate) struct LoadedRun {
    pub format: TraceFormat,
    pub games: Vec<NormalizedGame>,
    pub manifest: Option<H2hTraceManifestV2>,
    pub source_log: PathBuf,
    pub source_manifest: Option<PathBuf>,
    pub truncated_tail: Option<String>,
}

#[derive(Clone, Debug)]
pub(crate) struct NormalizedGame {
    pub schema_version: u32,
    pub run_id: Option<String>,
    pub game_index: usize,
    pub pair_index: usize,
    pub worker_id: Option<usize>,
    pub current_white: Option<bool>,
    pub result: String,
    pub plies: usize,
    pub opening_moves: Vec<String>,
    pub moves: Vec<String>,
    pub white_seed: Option<String>,
    pub black_seed: Option<String>,
    pub white_engine_instance_id: Option<String>,
    pub black_engine_instance_id: Option<String>,
    pub winner: Option<H2hActor>,
    pub outcome_reason: Option<String>,
    pub end_kind: Option<H2hGameEndKind>,
    pub decisions: Vec<H2hDecisionTraceV2>,
}

impl NormalizedGame {
    pub fn is_loss_for_candidate(&self) -> bool {
        if self.result == "loss" {
            return true;
        }
        let Some(current_white) = self.current_white else {
            // In v2 self-play both board-side instances are the candidate.
            // Every decisive game therefore contains one candidate loss.
            return self.schema_version >= 2 && self.winner.is_some();
        };
        matches!(
            (self.winner, current_white),
            (Some(H2hActor::White), false) | (Some(H2hActor::Black), true)
        )
    }

    pub fn loser(&self) -> Option<H2hActor> {
        match self.winner {
            Some(H2hActor::White) => Some(H2hActor::Black),
            Some(H2hActor::Black) => Some(H2hActor::White),
            None => None,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum EvidenceLevel {
    Hard,
    Exact,
    Probable,
    Unresolved,
    Advisory,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum FindingClass {
    EngineAnomaly,
    MoveError,
    ConversionInefficiency,
    Unresolved,
    ReplayNote,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub(crate) struct Finding {
    pub finding_id: String,
    pub game_index: usize,
    pub pair_index: usize,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub action_index: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub logical_ply_index: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub actor: Option<H2hActor>,
    pub evidence: EvidenceLevel,
    pub classification: FindingClass,
    pub code: String,
    pub message: String,
    #[serde(default)]
    pub facts: Vec<String>,
    #[serde(default)]
    pub inferences: Vec<String>,
    #[serde(default)]
    pub unknowns: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub root_fen: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub history_sha256: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub exact_case_key: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub canonical_position_key: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub semantic_signature: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub database: Option<DatabaseEvidence>,
    #[serde(default)]
    pub suspected_subsystems: Vec<String>,
    #[serde(default)]
    pub suspected_symbols: Vec<String>,
    #[serde(default)]
    pub case_ids: Vec<String>,
}

impl Finding {
    pub fn is_hard(&self) -> bool {
        self.evidence == EvidenceLevel::Hard
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub(crate) struct DatabaseEvidence {
    pub status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub best_wdl: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub best_steps: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub played_wdl: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub played_steps: Option<i32>,
    #[serde(default)]
    pub best_turns: Vec<Vec<String>>,
    #[serde(default)]
    pub all_turns: Vec<DatabaseTurnEvidence>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub(crate) struct DatabaseTurnEvidence {
    pub actions: Vec<String>,
    pub wdl: i32,
    pub steps: i32,
}

impl DatabaseTurnEvidence {
    pub fn from_outcome(actions: Vec<String>, outcome: PerfectOutcome) -> Self {
        Self {
            actions,
            wdl: outcome.wdl(),
            steps: outcome.steps(),
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub(crate) struct StateEvidence {
    pub action_index: usize,
    pub logical_ply_index: u32,
    pub fen: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub side_to_move: Option<H2hActor>,
    pub phase: String,
    pub action_tag: i16,
    pub pending_removal: bool,
    pub pending_removals: [u8; 2],
    pub pieces_on_board: [u8; 2],
    pub pieces_in_hand: [u8; 2],
    pub no_capture_count: u16,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub inactivity_threshold: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub inactivity_boundary_distance: Option<u32>,
    pub flying_sides: [bool; 2],
    pub repetition_current_count: usize,
    pub repetition_history_length: usize,
    pub snapshot_history_length: usize,
    pub history_sha256: String,
    pub legal_actions: Vec<String>,
    pub terminal: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub winner: Option<H2hActor>,
    pub outcome_reason: String,
}

#[derive(Clone, Debug)]
pub(crate) struct LogicalTurnRecord {
    pub logical_ply_index: u32,
    pub actor: H2hActor,
    pub action_start: usize,
    pub action_end: usize,
    pub tokens: Vec<String>,
    pub actions: Vec<Action>,
    pub root: GameStateSnapshot,
    pub final_snapshot: GameStateSnapshot,
    pub root_history: Vec<GameStateSnapshot>,
    pub before: StateEvidence,
    pub after_each_action: Vec<StateEvidence>,
    pub database: Option<DatabaseEvidence>,
    pub deterministic_search: Option<DeterministicSearchMatrix>,
    pub process_replay: Option<ProcessReplayEvidence>,
}

#[derive(Clone, Debug)]
pub(crate) struct ReplayedGame {
    pub source: NormalizedGame,
    pub states: Vec<StateEvidence>,
    pub logical_turns: Vec<LogicalTurnRecord>,
    pub findings: Vec<Finding>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub(crate) struct SearchProbeEvidence {
    pub algorithm: String,
    pub node_budget: u64,
    pub status: String,
    #[serde(default)]
    pub selected_turn: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub selected_score: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub played_score: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub score_gap: Option<i32>,
    pub nodes: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub completed_depth: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub(crate) struct DeterministicSearchMatrix {
    #[serde(default)]
    pub probes: Vec<SearchProbeEvidence>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub agreed_alternative: Option<Vec<String>>,
    pub probable: bool,
    pub budget_limited: bool,
    #[serde(default)]
    pub unresolved_reasons: Vec<String>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub(crate) struct ProcessReplayEvidence {
    pub status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub live_bestmove: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub fresh_bestmove: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sequence_bestmove: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reference_bestmove: Option<String>,
    #[serde(default)]
    pub notes: Vec<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub(crate) struct ValueSwing {
    pub logical_ply_index: u32,
    pub action_index: usize,
    pub actor: H2hActor,
    pub before_white_wdl: i32,
    pub after_white_wdl: i32,
    pub escaped: bool,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub(crate) struct LossReport {
    pub game_index: usize,
    pub pair_index: usize,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub loser: Option<H2hActor>,
    pub db_fully_covered: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub decisive_loss_turn: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub earliest_observed_suspect: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub first_engine_anomaly: Option<String>,
    #[serde(default)]
    pub escaped_blunders: Vec<u32>,
    #[serde(default)]
    pub value_swings: Vec<ValueSwing>,
    pub unresolved: bool,
    #[serde(default)]
    pub case_ids: Vec<String>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub(crate) struct PairMetrics {
    pub pair_index: usize,
    pub games: u32,
    pub games_with_wdl_drop: u32,
    pub severity_2_events: u32,
    pub persistent_db_errors: u32,
    pub process_state_dependence: u32,
    pub unresolved_losses: u32,
    pub losses: u32,
    pub db_roots: u32,
    pub db_covered_roots: u32,
    pub search_cases: u32,
    pub search_completed_cases: u32,
}

impl PairMetrics {
    pub fn unresolved_loss_rate(&self) -> f64 {
        if self.losses == 0 {
            0.0
        } else {
            f64::from(self.unresolved_losses) / f64::from(self.losses)
        }
    }

    pub fn db_coverage_rate(&self) -> f64 {
        if self.db_roots == 0 {
            1.0
        } else {
            f64::from(self.db_covered_roots) / f64::from(self.db_roots)
        }
    }

    pub fn search_coverage_rate(&self) -> f64 {
        if self.search_cases == 0 {
            1.0
        } else {
            f64::from(self.search_completed_cases) / f64::from(self.search_cases)
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub(crate) struct ClusterReport {
    pub cluster_level: String,
    pub key: String,
    pub finding_count: usize,
    pub finding_ids: Vec<String>,
    pub representative_finding_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub representative_case_id: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub(crate) struct GateMetric {
    pub name: String,
    pub paired_count: usize,
    pub mean_delta: f64,
    pub lower_99_9: f64,
    pub upper_99_9: f64,
    pub regressed: bool,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub(crate) struct GateResult {
    pub mode: String,
    pub passed: bool,
    #[serde(default)]
    pub configuration_errors: Vec<String>,
    #[serde(default)]
    pub metrics: Vec<GateMetric>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub(crate) struct AnalysisSummary {
    pub analysis_schema_version: u32,
    pub trace_schema_version: u32,
    pub run_id: String,
    pub profile_fingerprint: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub database_identity: Option<String>,
    pub deterministic: bool,
    pub baselinable: bool,
    pub analysis_complete: bool,
    pub expected_games: usize,
    pub analyzed_games: usize,
    pub analyzed_pairs: usize,
    pub hard_anomaly_count: usize,
    pub exact_move_error_count: usize,
    pub probable_anomaly_count: usize,
    pub unresolved_count: usize,
    pub unresolved_loss_count: usize,
    pub db_roots: usize,
    pub db_covered_roots: usize,
    pub search_cases: usize,
    pub search_completed_cases: usize,
    pub case_bundle_count: usize,
    pub pair_metrics: Vec<PairMetrics>,
    pub gate: GateResult,
    #[serde(default)]
    pub incomplete_reasons: Vec<String>,
    #[serde(default)]
    pub artifact_sha256: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub(crate) struct H2hBaseline {
    pub baseline_schema_version: u32,
    pub analysis_schema_version: u32,
    pub trace_schema_version: u32,
    pub profile_fingerprint: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub database_identity: Option<String>,
    pub approved_report_sha256: String,
    pub accepted_unix_ms: u128,
    pub pair_metrics: Vec<PairMetrics>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub(crate) struct CaseBundle {
    pub case_schema_version: u32,
    pub case_id: String,
    pub game_index: usize,
    pub pair_index: usize,
    pub title: String,
    pub facts: Vec<String>,
    pub inferences: Vec<String>,
    pub unknowns: Vec<String>,
    pub full_game: Vec<String>,
    pub suspect_prefix: Vec<String>,
    pub exact_root_fen: String,
    pub action_states: Vec<StateEvidence>,
    pub trace_manifest: Option<H2hTraceManifestV2>,
    pub run_fingerprint: String,
    pub rules_fingerprint: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub database_identity: Option<String>,
    #[serde(default)]
    pub engine_fingerprints: Vec<String>,
    #[serde(default)]
    pub live_decisions: Vec<H2hDecisionTraceV2>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub database: Option<DatabaseEvidence>,
    pub deterministic_search: DeterministicSearchMatrix,
    pub process_replay: ProcessReplayEvidence,
    #[serde(default)]
    pub engine_instance_chronology: Vec<String>,
    #[serde(default)]
    pub anomaly_codes: Vec<String>,
    #[serde(default)]
    pub suspected_subsystems: Vec<String>,
    #[serde(default)]
    pub suspected_symbols: Vec<String>,
    pub replay_command: String,
    pub llm_prompt: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn game(schema_version: u32, current_white: Option<bool>) -> NormalizedGame {
        NormalizedGame {
            schema_version,
            run_id: None,
            game_index: 0,
            pair_index: 0,
            worker_id: None,
            current_white,
            result: "black_win".to_string(),
            plies: 0,
            opening_moves: Vec::new(),
            moves: Vec::new(),
            white_seed: None,
            black_seed: None,
            white_engine_instance_id: None,
            black_engine_instance_id: None,
            winner: Some(H2hActor::Black),
            outcome_reason: None,
            end_kind: None,
            decisions: Vec::new(),
        }
    }

    #[test]
    fn decisive_v2_self_play_contains_a_candidate_loss() {
        assert!(game(2, None).is_loss_for_candidate());
        assert!(!game(1, None).is_loss_for_candidate());
        assert!(game(2, Some(true)).is_loss_for_candidate());
        assert!(!game(2, Some(false)).is_loss_for_candidate());
    }
}
