// SPDX-License-Identifier: AGPL-3.0-or-later

//! Versioned H2H forensic trace types and stable artifact fingerprints.
//!
//! The match driver lives in an integration test while the offline analyzer
//! lives in the `tgf` binary.  Keeping the wire schema in this library target
//! prevents the two consumers from silently drifting apart.

use std::fs::{self, File};
use std::io::{self, Read};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use perfect_db::database::{Database, DatabaseVariant, FileDatabaseProvider};
use perfect_db::file_format::{SECTOR_HEADER_SIZE, SectorHeader};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use tgf_mill::{MillVariantOptions, rules_for_preset};

pub const H2H_TRACE_SCHEMA_VERSION: u32 = 2;
pub const H2H_MANIFEST_SCHEMA_VERSION: u32 = 2;
pub const H2H_RAW_UCI_LIMIT_BYTES: usize = 64 * 1024;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct H2hTraceManifestV2 {
    pub schema_version: u32,
    pub run_id: String,
    pub created_unix_ms: u128,
    pub expected_games: usize,
    pub completed_games: usize,
    pub mode: String,
    pub rules: H2hRulesIdentity,
    pub candidate: H2hEngineIdentity,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reference: Option<H2hEngineIdentity>,
    pub config: H2hMatchConfig,
    pub reproducibility: H2hReproducibility,
    #[serde(default)]
    pub artifacts: Vec<H2hArtifactIdentity>,
}

impl H2hTraceManifestV2 {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        run_id: String,
        expected_games: usize,
        mode: String,
        rules: H2hRulesIdentity,
        candidate: H2hEngineIdentity,
        reference: Option<H2hEngineIdentity>,
        config: H2hMatchConfig,
        reproducibility: H2hReproducibility,
        artifacts: Vec<H2hArtifactIdentity>,
    ) -> Self {
        Self {
            schema_version: H2H_MANIFEST_SCHEMA_VERSION,
            run_id,
            created_unix_ms: unix_time_ms(),
            expected_games,
            completed_games: 0,
            mode,
            rules,
            candidate,
            reference,
            config,
            reproducibility,
            artifacts,
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct H2hRulesIdentity {
    pub ruleset_id: String,
    pub format_version: u32,
    pub sha256: String,
    pub options: MillVariantOptions,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct H2hSetOption {
    pub name: String,
    pub value: String,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct H2hEnvironmentFingerprint {
    pub name: String,
    pub value_sha256: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub replay_value: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct H2hEngineIdentity {
    pub role: String,
    pub path: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub binary_sha256: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub git_revision: Option<String>,
    #[serde(default)]
    pub arguments: Vec<String>,
    #[serde(default)]
    pub uci_id: Vec<String>,
    #[serde(default)]
    pub setoptions: Vec<H2hSetOption>,
    pub go_command: String,
    #[serde(default)]
    pub environment: Vec<H2hEnvironmentFingerprint>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct H2hMatchConfig {
    pub jobs: usize,
    pub engine_threads: u32,
    pub skill_level: u32,
    pub max_plies: usize,
    pub opening_plies: usize,
    pub opening_seed: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub search_seed: Option<String>,
    /// When true, both colour-swapped games in an opening pair reuse the
    /// same board-side shuffle seeds, run on one worker, and start from an
    /// empty transposition table.
    #[serde(default)]
    pub strict_pairing: bool,
    pub shuffling: bool,
    pub algorithm: String,
    pub draw_on_human_experience: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ai_is_lazy: Option<bool>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct H2hReproducibility {
    pub fixed_nodes: bool,
    pub single_thread: bool,
    pub fixed_opening_seed: bool,
    pub fixed_search_seed: bool,
    pub non_timed_search: bool,
    pub deterministic: bool,
    #[serde(default)]
    pub nondeterministic_reasons: Vec<String>,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct H2hArtifactIdentity {
    pub role: String,
    pub kind: String,
    pub path: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sha256: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub fast_manifest_sha256: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub byte_len: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub file_count: Option<usize>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub declared_sector_count: Option<usize>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub available_sector_count: Option<usize>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub fully_available: Option<bool>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum H2hActor {
    White,
    Black,
}

impl H2hActor {
    pub fn from_side(side: i8) -> Option<Self> {
        match side {
            0 => Some(Self::White),
            1 => Some(Self::Black),
            _ => None,
        }
    }

    pub fn side(self) -> i8 {
        match self {
            Self::White => 0,
            Self::Black => 1,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum H2hGameEndKind {
    Rule,
    PlyCap,
    ProtocolError,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct H2hDecisionTraceV2 {
    pub actor: H2hActor,
    pub engine_role: String,
    pub engine_instance_id: String,
    pub instance_search_ordinal: u64,
    pub action_index: usize,
    pub logical_ply_index: u32,
    pub go_command: String,
    pub elapsed_ms: u128,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub bestmove: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub depth: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub score_kind: Option<String>,
    /// Parsed UCI score normalized to White's perspective.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub score_value: Option<i32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub nodes: Option<u64>,
    pub raw_uci_output: String,
    pub raw_uci_sha256: String,
    pub raw_uci_truncated: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub protocol_error: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct H2hGameTraceV2 {
    pub schema_version: u32,
    pub run_id: String,
    pub game_index: usize,
    pub pair_index: usize,
    pub worker_id: usize,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub current_white: Option<bool>,
    /// Legacy result spelling (`win`, `loss`, `draw`, `unfinished`).
    pub result: String,
    pub plies: usize,
    #[serde(default)]
    pub opening_moves: Vec<String>,
    /// Legacy field retained byte-for-field in meaning.
    #[serde(default)]
    pub moves: Vec<String>,
    #[serde(default)]
    pub atomic_actions: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub white_seed: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub black_seed: Option<String>,
    pub white_engine_instance_id: String,
    pub black_engine_instance_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub winner: Option<H2hActor>,
    pub outcome_reason: String,
    pub end_kind: H2hGameEndKind,
    #[serde(default)]
    pub decisions: Vec<H2hDecisionTraceV2>,
}

/// Minimal legacy row accepted by the offline analyzer.
#[derive(Clone, Debug, Deserialize)]
pub struct H2hGameTraceV1 {
    pub game_index: usize,
    #[serde(default)]
    pub current_white: Option<bool>,
    pub result: String,
    pub plies: usize,
    #[serde(default)]
    pub opening_moves: Vec<String>,
    #[serde(default)]
    pub moves: Vec<String>,
    #[serde(default)]
    pub white_seed: Option<String>,
    #[serde(default)]
    pub black_seed: Option<String>,
}

pub fn unix_time_ms() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
}

pub fn new_run_id() -> String {
    let process = std::process::id();
    let nonce = unix_time_ms();
    let mut hash = Sha256::new();
    hash.update(b"sanmill.h2h.run-id.v1\0");
    hash.update(nonce.to_le_bytes());
    hash.update(process.to_le_bytes());
    format!("h2h-{}-{}", nonce, &hex_lower(hash.finalize())[..12])
}

pub fn manifest_path_for_log(log_path: &Path) -> PathBuf {
    let stem = log_path
        .file_stem()
        .and_then(|value| value.to_str())
        .unwrap_or("h2h");
    log_path.with_file_name(format!("{stem}.manifest.json"))
}

pub fn sha256_bytes(domain: &[u8], bytes: &[u8]) -> String {
    let mut hash = Sha256::new();
    hash.update(domain);
    hash.update((bytes.len() as u64).to_le_bytes());
    hash.update(bytes);
    hex_lower(hash.finalize())
}

pub fn sha256_file(path: &Path) -> io::Result<String> {
    let mut file = File::open(path)?;
    let mut hash = Sha256::new();
    let mut buffer = [0_u8; 1024 * 1024];
    loop {
        let read = file.read(&mut buffer)?;
        if read == 0 {
            break;
        }
        hash.update(&buffer[..read]);
    }
    Ok(hex_lower(hash.finalize()))
}

pub fn fingerprint_environment(
    values: &[(String, String)],
    replay_allowlist: &[&str],
) -> Vec<H2hEnvironmentFingerprint> {
    let mut fingerprints = values
        .iter()
        .map(|(name, value)| H2hEnvironmentFingerprint {
            name: name.clone(),
            value_sha256: sha256_bytes(b"sanmill.h2h.env-value.v1\0", value.as_bytes()),
            replay_value: replay_allowlist
                .iter()
                .any(|safe| name.eq_ignore_ascii_case(safe))
                .then(|| value.clone()),
        })
        .collect::<Vec<_>>();
    fingerprints.sort_by(|left, right| left.name.cmp(&right.name));
    fingerprints
}

pub fn mill_rules_identity(options: &MillVariantOptions) -> H2hRulesIdentity {
    let bytes = serde_json::to_vec(options).expect("serializing Mill rule options must not fail");
    let mut hash = Sha256::new();
    hash.update(b"sanmill.uci.rules.v1\0");
    hash.update((bytes.len() as u64).to_le_bytes());
    hash.update(bytes);
    H2hRulesIdentity {
        ruleset_id: mill_ruleset_id(options).to_string(),
        format_version: 1,
        sha256: hex_lower(hash.finalize()),
        options: options.clone(),
    }
}

pub fn mill_ruleset_id(options: &MillVariantOptions) -> &'static str {
    let current =
        serde_json::to_value(options).expect("serializing Mill rule options must not fail");
    let standard = serde_json::to_value(MillVariantOptions::default())
        .expect("serializing default Mill rule options must not fail");
    if current == standard {
        return "nmm";
    }
    if let Some(el_filja) = rules_for_preset(9)
        && current
            == serde_json::to_value(el_filja.options())
                .expect("serializing El Filja rule options must not fail")
    {
        return "el_filja";
    }
    "custom"
}

pub fn fingerprint_file(role: &str, kind: &str, path: &Path) -> H2hArtifactIdentity {
    let metadata = fs::metadata(path).ok();
    H2hArtifactIdentity {
        role: role.to_string(),
        kind: kind.to_string(),
        path: path.display().to_string(),
        sha256: metadata
            .as_ref()
            .filter(|value| value.is_file())
            .and_then(|_| sha256_file(path).ok()),
        fast_manifest_sha256: None,
        byte_len: metadata.as_ref().map(fs::Metadata::len),
        file_count: metadata.as_ref().filter(|value| value.is_file()).map(|_| 1),
        declared_sector_count: None,
        available_sector_count: None,
        fully_available: None,
    }
}

/// Build a stable, cold-path identity for a complete or partial standard DB.
///
/// The manifest hashes `std.secval` in full and each available sector's name,
/// size, and validated fixed-size header.  It therefore avoids reading an
/// 83-GB database while still detecting format/content-set drift.
pub fn fingerprint_perfect_database(
    role: &str,
    path: &Path,
) -> Result<H2hArtifactIdentity, String> {
    let root = fs::canonicalize(path).map_err(|error| {
        format!(
            "failed to canonicalize Perfect DB path {}: {error}",
            path.display()
        )
    })?;
    let provider = FileDatabaseProvider::new(root.clone());
    let variants = Database::<FileDatabaseProvider>::supported_variants(&provider)
        .map_err(|error| format!("failed to inspect Perfect DB {}: {error}", root.display()))?;
    let standard = variants
        .find(DatabaseVariant::STANDARD)
        .ok_or_else(|| format!("{} does not contain std.secval", root.display()))?;
    let secval_path = root.join(DatabaseVariant::STANDARD.secval_file_name());
    let secval_sha = sha256_file(&secval_path)
        .map_err(|error| format!("failed to hash {}: {error}", secval_path.display()))?;

    let mut manifest = Sha256::new();
    manifest.update(b"sanmill.perfect-db.fast-manifest.v2\0");
    update_length_prefixed(&mut manifest, secval_sha.as_bytes());
    manifest.update((standard.sector_count() as u64).to_le_bytes());
    manifest.update((standard.available_sector_count() as u64).to_le_bytes());
    let mut total_bytes = fs::metadata(&secval_path)
        .map_err(|error| format!("failed to inspect {}: {error}", secval_path.display()))?
        .len();
    let mut file_count = 1_usize;
    for id in &standard.available_sector_ids {
        let name = DatabaseVariant::STANDARD.sector_file_name(*id);
        let sector_path = root.join(&name);
        let metadata = fs::metadata(&sector_path)
            .map_err(|error| format!("failed to inspect {}: {error}", sector_path.display()))?;
        if !metadata.is_file() {
            return Err(format!(
                "Perfect DB sector is not a regular file: {}",
                sector_path.display()
            ));
        }
        let mut file = File::open(&sector_path)
            .map_err(|error| format!("failed to open {}: {error}", sector_path.display()))?;
        let mut header = [0_u8; SECTOR_HEADER_SIZE];
        file.read_exact(&mut header)
            .map_err(|error| format!("failed to read {}: {error}", sector_path.display()))?;
        SectorHeader::parse(&header)
            .map_err(|error| format!("invalid sector header {}: {error}", sector_path.display()))?;
        update_length_prefixed(&mut manifest, name.as_bytes());
        manifest.update(metadata.len().to_le_bytes());
        manifest.update(header);
        total_bytes = total_bytes.saturating_add(metadata.len());
        file_count += 1;
    }

    Ok(H2hArtifactIdentity {
        role: role.to_string(),
        kind: "perfect_database".to_string(),
        path: root.display().to_string(),
        sha256: Some(secval_sha),
        fast_manifest_sha256: Some(hex_lower(manifest.finalize())),
        byte_len: Some(total_bytes),
        file_count: Some(file_count),
        declared_sector_count: Some(standard.sector_count()),
        available_sector_count: Some(standard.available_sector_count()),
        fully_available: Some(standard.is_fully_available()),
    })
}

fn update_length_prefixed(hash: &mut Sha256, bytes: &[u8]) {
    hash.update((bytes.len() as u64).to_le_bytes());
    hash.update(bytes);
}

fn hex_lower(bytes: impl AsRef<[u8]>) -> String {
    bytes
        .as_ref()
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rules_identity_matches_statejson_domain() {
        let identity = mill_rules_identity(&MillVariantOptions::default());
        assert_eq!(identity.format_version, 1);
        assert_eq!(identity.ruleset_id, "nmm");
        assert_eq!(identity.sha256.len(), 64);
    }

    #[test]
    fn manifest_path_replaces_jsonl_suffix() {
        assert_eq!(
            manifest_path_for_log(Path::new("out/match.jsonl")),
            PathBuf::from("out/match.manifest.json")
        );
    }

    #[test]
    fn environment_values_are_hashed_unless_explicitly_safe() {
        let values = vec![
            ("SECRET".to_string(), "do-not-print".to_string()),
            ("TGF_SAFE_SWITCH".to_string(), "true".to_string()),
        ];
        let fingerprints = fingerprint_environment(&values, &["TGF_SAFE_SWITCH"]);
        assert_eq!(fingerprints[0].name, "SECRET");
        assert_eq!(fingerprints[0].value_sha256.len(), 64);
        assert_eq!(fingerprints[0].replay_value, None);
        assert_eq!(fingerprints[1].replay_value.as_deref(), Some("true"));
        let json = serde_json::to_string(&fingerprints).unwrap();
        assert!(!json.contains("do-not-print"));
    }

    #[test]
    fn v1_and_v2_rows_have_distinct_schema_shapes() {
        let legacy = r#"{"game_index":0,"current_white":true,"result":"draw","plies":0,"opening_moves":[],"moves":[]}"#;
        let row: H2hGameTraceV1 = serde_json::from_str(legacy).unwrap();
        assert_eq!(row.game_index, 0);

        let v2 = H2hGameTraceV2 {
            schema_version: H2H_TRACE_SCHEMA_VERSION,
            run_id: "test".to_string(),
            game_index: 0,
            pair_index: 0,
            worker_id: 0,
            current_white: Some(true),
            result: "draw".to_string(),
            plies: 0,
            opening_moves: Vec::new(),
            moves: Vec::new(),
            atomic_actions: Vec::new(),
            white_seed: None,
            black_seed: None,
            white_engine_instance_id: "w".to_string(),
            black_engine_instance_id: "b".to_string(),
            winner: None,
            outcome_reason: "ply_cap".to_string(),
            end_kind: H2hGameEndKind::PlyCap,
            decisions: Vec::new(),
        };
        let value = serde_json::to_value(v2).unwrap();
        assert_eq!(value["schema_version"], H2H_TRACE_SCHEMA_VERSION);
        assert_eq!(value["pair_index"], 0);
    }
}
