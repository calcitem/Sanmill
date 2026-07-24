// SPDX-License-Identifier: AGPL-3.0-or-later

use serde::{Deserialize, Serialize};
use serde_json::Value;

pub(super) const PROTOCOL_VERSION: u32 = 1;

#[derive(Clone, Debug, Deserialize)]
#[serde(tag = "operation", rename_all = "snake_case", deny_unknown_fields)]
pub(super) enum ApiRequest {
    QueryBook {
        protocol_version: u32,
        #[serde(default)]
        request_id: Option<String>,
        position: PositionRequest,
        #[serde(default)]
        asset_path: Option<String>,
    },
    QueryPerfectDb {
        protocol_version: u32,
        #[serde(default)]
        request_id: Option<String>,
        position: PositionRequest,
        database_path: String,
        #[serde(default)]
        cache_sectors: Option<usize>,
    },
    QueryHumanDb {
        protocol_version: u32,
        #[serde(default)]
        request_id: Option<String>,
        position: PositionRequest,
        database_path: String,
        #[serde(default)]
        candidate_limit: Option<usize>,
        #[serde(default)]
        min_total: Option<u64>,
    },
    HistorySummary {
        protocol_version: u32,
        #[serde(default)]
        request_id: Option<String>,
        position: PositionRequest,
        #[serde(default)]
        count_mode: PlyCountMode,
    },
    SourceIdentity {
        protocol_version: u32,
        #[serde(default)]
        request_id: Option<String>,
        source: IdentitySource,
        #[serde(default)]
        mode: IdentityMode,
    },
}

impl ApiRequest {
    pub(super) fn protocol_version(&self) -> u32 {
        match self {
            Self::QueryBook {
                protocol_version, ..
            }
            | Self::QueryPerfectDb {
                protocol_version, ..
            }
            | Self::QueryHumanDb {
                protocol_version, ..
            }
            | Self::HistorySummary {
                protocol_version, ..
            }
            | Self::SourceIdentity {
                protocol_version, ..
            } => *protocol_version,
        }
    }

    pub(super) fn request_id(&self) -> Option<String> {
        match self {
            Self::QueryBook { request_id, .. }
            | Self::QueryPerfectDb { request_id, .. }
            | Self::QueryHumanDb { request_id, .. }
            | Self::HistorySummary { request_id, .. }
            | Self::SourceIdentity { request_id, .. } => request_id.clone(),
        }
    }

    pub(super) fn operation_name(&self) -> &'static str {
        match self {
            Self::QueryBook { .. } => "query_book",
            Self::QueryPerfectDb { .. } => "query_perfect_db",
            Self::QueryHumanDb { .. } => "query_human_db",
            Self::HistorySummary { .. } => "history_summary",
            Self::SourceIdentity { .. } => "source_identity",
        }
    }
}

#[derive(Clone, Copy, Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub(super) enum RulePreset {
    Nmm,
    ElFilja,
}

impl RulePreset {
    pub(super) fn preset_id(self) -> i32 {
        match self {
            Self::Nmm => 0,
            Self::ElFilja => 9,
        }
    }

    pub(super) fn book_variant(self) -> &'static str {
        match self {
            Self::Nmm => "nmm",
            Self::ElFilja => "el_filja",
        }
    }
}

#[derive(Clone, Copy, Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub(super) enum HistoryOrigin {
    GameStart,
    FreshSetup,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct PositionRequest {
    pub rule: RulePreset,
    pub initial: String,
    pub history_origin: HistoryOrigin,
    pub actions: Vec<String>,
    #[serde(default)]
    pub expected_current_fen: Option<String>,
}

#[derive(Clone, Copy, Debug, Default, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub(super) enum PlyCountMode {
    #[default]
    Logical,
    Actions,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub(super) enum IdentitySource {
    Book {
        variant: RulePreset,
        #[serde(default)]
        asset_path: Option<String>,
    },
    PerfectDb {
        database_path: String,
    },
    HumanDb {
        database_path: String,
    },
}

#[derive(Clone, Copy, Debug, Default, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub(super) enum IdentityMode {
    #[default]
    Fast,
    Full,
}

#[derive(Clone, Copy, Debug, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub(super) enum ApiStatus {
    Available,
    BookMiss,
    DbMiss,
    HumanDbMiss,
    Terminal,
    Error,
}

#[derive(Clone, Debug, Serialize)]
pub(super) struct ApiResponse {
    pub protocol_version: u32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub request_id: Option<String>,
    pub operation: String,
    pub status: ApiStatus,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub state: Option<StateSummary>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub candidates: Option<Vec<Candidate>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<ApiError>,
}

impl ApiResponse {
    pub(super) fn error(
        operation: impl Into<String>,
        request_id: Option<String>,
        error: ApiError,
    ) -> Self {
        Self {
            protocol_version: PROTOCOL_VERSION,
            request_id,
            operation: operation.into(),
            status: ApiStatus::Error,
            state: None,
            source: None,
            candidates: None,
            result: None,
            error: Some(error),
        }
    }
}

#[derive(Clone, Debug, Serialize)]
pub(super) struct ApiError {
    pub code: String,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub action_index: Option<usize>,
}

impl ApiError {
    pub(super) fn new(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            code: code.into(),
            message: message.into(),
            action_index: None,
        }
    }

    pub(super) fn at_action(
        code: impl Into<String>,
        message: impl Into<String>,
        action_index: usize,
    ) -> Self {
        Self {
            code: code.into(),
            message: message.into(),
            action_index: Some(action_index),
        }
    }
}

#[derive(Clone, Debug, Serialize)]
pub(super) struct StateSummary {
    pub current_fen: String,
    pub side_to_move: Option<String>,
    pub phase: String,
    pub pending_removal: bool,
    pub pending_removals: [u8; 2],
    pub no_capture_plies: u16,
    pub action_token_count: u32,
    pub logical_ply_count: u32,
    pub logical_plies_by_side: [u32; 2],
    pub snapshot_history_len: usize,
    pub repetition_history_len: usize,
    pub history_sha256: String,
    pub outcome: OutcomeSummary,
}

#[derive(Clone, Debug, Serialize)]
pub(super) struct OutcomeSummary {
    pub kind: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub winner: Option<i8>,
    pub reason: String,
}

#[derive(Clone, Debug, Serialize)]
pub(super) struct Candidate {
    pub logical_move_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source_group_id: Option<String>,
    pub stable_index: usize,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source_rank: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub raw_notation: Option<String>,
    pub mapped_notation: String,
    pub full_turn_actions: Vec<String>,
    pub remaining_actions: Vec<String>,
    pub contains_removal: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub removal_action: Option<String>,
    pub logical_ply_delta: u8,
    pub turn_prefix_complete: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub perfect: Option<PerfectCandidateData>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub human: Option<HumanCandidateData>,
}

#[derive(Clone, Debug, Serialize)]
pub(super) struct PerfectCandidateData {
    pub category: String,
    pub wdl: i32,
    pub steps: i32,
    pub mode: String,
}

#[derive(Clone, Debug, Serialize)]
pub(super) struct HumanCandidateData {
    pub wins: u64,
    pub losses: u64,
    pub draws: u64,
    pub total: u64,
    pub frequency_numerator: u64,
    pub frequency_denominator: u64,
    pub relative_frequency: f64,
    pub empirical_win_rate: f64,
    pub empirical_draw_rate: f64,
    pub empirical_loss_rate: f64,
    pub legacy_experience_score: f64,
    pub moves_to_end_sum: f64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub average_moves_to_end: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub malom_wdl_after: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub malom_dtw_after: Option<i64>,
}
