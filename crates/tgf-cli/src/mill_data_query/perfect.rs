// SPDX-License-Identifier: AGPL-3.0-or-later

use std::fs::{self, File};
use std::io::Read;
use std::path::{Path, PathBuf};
use std::time::SystemTime;

use super::hashing::{hex_lower, sha256_file, update_length_prefixed};
use super::position::ReplayedPosition;
use super::protocol::{ApiError, Candidate, IdentityMode, PerfectCandidateData, RulePreset};
use perfect_db::database::{
    Database, DatabaseError, DatabaseOptions, DatabaseVariant, FileDatabaseProvider,
    PerfectOutcome, SupportedPerfectVariant,
};
use perfect_db::file_format::{SECTOR_FORMAT_VERSION, SECTOR_HEADER_SIZE, SectorHeader, SectorId};
use perfect_db::{PerfectMoveOrdering, best_logical_turn_choices_with_ordering};
use serde::Serialize;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};

#[derive(Clone, Debug)]
pub(super) struct PerfectQueryResult {
    pub source: Value,
    pub candidates: Vec<Candidate>,
}

#[derive(Clone, Debug, Serialize)]
pub(super) struct PerfectIdentity {
    kind: &'static str,
    database_format: &'static str,
    sector_format_version: i32,
    variant: &'static str,
    root: String,
    secval_sha256: String,
    fast_manifest_sha256: String,
    manifest_algorithm: &'static str,
    declared_sector_count: usize,
    available_sector_count: usize,
    placement_sector_count: usize,
    settled_sector_count: usize,
    flying_related_sector_count: usize,
    fully_available: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    full_content_sha256: Option<String>,
}

pub(super) struct PerfectDbSource {
    database: Database<FileDatabaseProvider>,
    identity: PerfectIdentity,
    file_stamps: Vec<PerfectFileStamp>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct PerfectFileStamp {
    path: PathBuf,
    len: u64,
    modified: SystemTime,
}

impl PerfectDbSource {
    pub(super) fn open(path: &str, cache_sectors: Option<usize>) -> Result<Self, ApiError> {
        let root = validated_root(path)?;
        if cache_sectors == Some(0) {
            return Err(ApiError::new(
                "protocol_error",
                "cache_sectors must be positive when provided",
            ));
        }
        let secval_path = root.join(DatabaseVariant::STANDARD.secval_file_name());
        let secval_before = file_stamp(&secval_path)?;
        let provider = FileDatabaseProvider::new(root.clone());
        let variants = Database::<FileDatabaseProvider>::supported_variants(&provider)
            .map_err(|error| map_database_error(error, "database_open_error"))?;
        ensure_same_file_stamps(&[secval_before], &[file_stamp(&secval_path)?])?;
        let standard = variants.find(DatabaseVariant::STANDARD).ok_or_else(|| {
            ApiError::new(
                "database_format_incompatible",
                format!("{} does not contain std.secval", root.display()),
            )
        })?;
        ensure_complete(standard)?;
        let (identity, file_stamps) = build_stable_identity(&root, standard, IdentityMode::Fast)?;
        let options = cache_sectors
            .map(DatabaseOptions::with_sector_cache_capacity)
            .unwrap_or_default();
        let database = Database::open_variant_with_options(
            FileDatabaseProvider::new(root.clone()),
            DatabaseVariant::STANDARD,
            options,
        )
        .map_err(|error| map_database_error(error, "database_open_error"))?;
        let after_open = capture_file_stamps(&root, standard)?;
        ensure_same_file_stamps(&file_stamps, &after_open)?;
        Ok(Self {
            database,
            identity,
            file_stamps: after_open,
        })
    }

    pub(super) fn query(
        &mut self,
        replayed: &ReplayedPosition,
    ) -> Result<PerfectQueryResult, ApiError> {
        if replayed.rule != RulePreset::Nmm {
            return Err(ApiError::new(
                "unsupported_rule",
                "Perfect Database data-query currently supports standard NMM only",
            ));
        }
        let source_position = replayed.source_position();
        if replayed.current_side_has_pending_removal() && !source_position.prefix_complete {
            return Err(ApiError::new(
                "incomplete_history",
                "Perfect Database queries in pending-removal states require the initiating history",
            ));
        }
        self.verify_unchanged()?;
        let choices = best_logical_turn_choices_with_ordering(
            &mut self.database,
            &replayed.rules,
            &replayed.snapshot,
            &replayed.history,
            &replayed.options,
            PerfectMoveOrdering::StrictSteps,
        )
        .map_err(|error| map_database_error(error, "database_query_error"))?;
        let Some(choices) = choices else {
            return Ok(PerfectQueryResult {
                source: perfect_source_json(&self.identity),
                candidates: Vec::new(),
            });
        };

        let prefix =
            if replayed.current_side_has_pending_removal() && source_position.prefix_complete {
                source_position.prefix_tokens
            } else {
                Vec::new()
            };
        let current_fen = replayed.state_summary().current_fen;
        let mut candidates = Vec::with_capacity(choices.len());
        for choice in choices {
            let remaining_actions = choice.tokens;
            let mut full_turn_actions = prefix.clone();
            full_turn_actions.extend(remaining_actions.iter().cloned());
            let removal_action = full_turn_actions
                .iter()
                .find(|token| token.starts_with('x'))
                .cloned();
            let category = outcome_category(choice.outcome);
            candidates.push(Candidate {
                logical_move_id: logical_move_id(
                    &self.identity.fast_manifest_sha256,
                    &current_fen,
                    &full_turn_actions,
                ),
                source_group_id: None,
                stable_index: 0,
                source_rank: None,
                raw_notation: None,
                mapped_notation: full_turn_actions.join(" "),
                full_turn_actions,
                remaining_actions,
                contains_removal: removal_action.is_some(),
                removal_action,
                logical_ply_delta: 1,
                turn_prefix_complete: !replayed.current_side_has_pending_removal()
                    || source_position.prefix_complete,
                perfect: Some(PerfectCandidateData {
                    category: category.to_owned(),
                    wdl: choice.outcome.wdl(),
                    steps: choice.outcome.steps(),
                    mode: "strict_steps".to_owned(),
                }),
                human: None,
            });
        }
        candidates.sort_by(|left, right| left.full_turn_actions.cmp(&right.full_turn_actions));
        for (index, candidate) in candidates.iter_mut().enumerate() {
            candidate.stable_index = index;
        }
        Ok(PerfectQueryResult {
            source: perfect_source_json(&self.identity),
            candidates,
        })
    }

    fn verify_unchanged(&self) -> Result<(), ApiError> {
        for expected in &self.file_stamps {
            let actual = file_stamp(&expected.path).map_err(|error| {
                ApiError::new(
                    "database_changed",
                    format!(
                        "Perfect Database file changed after open ({}): {}",
                        expected.path.display(),
                        error.message
                    ),
                )
            })?;
            if actual != *expected {
                return Err(ApiError::new(
                    "database_changed",
                    format!(
                        "Perfect Database file identity changed after open: {}",
                        expected.path.display()
                    ),
                ));
            }
        }
        Ok(())
    }
}

pub(super) fn identity(path: &str, mode: IdentityMode) -> Result<Value, ApiError> {
    let root = validated_root(path)?;
    let secval_path = root.join(DatabaseVariant::STANDARD.secval_file_name());
    let secval_before = file_stamp(&secval_path)?;
    let provider = FileDatabaseProvider::new(root.clone());
    let variants = Database::<FileDatabaseProvider>::supported_variants(&provider)
        .map_err(|error| map_database_error(error, "database_open_error"))?;
    ensure_same_file_stamps(&[secval_before], &[file_stamp(&secval_path)?])?;
    let standard = variants.find(DatabaseVariant::STANDARD).ok_or_else(|| {
        ApiError::new(
            "database_format_incompatible",
            format!("{} does not contain std.secval", root.display()),
        )
    })?;
    ensure_complete(standard)?;
    let (identity, _) = build_stable_identity(&root, standard, mode)?;
    serde_json::to_value(identity)
        .map_err(|error| ApiError::new("internal_error", error.to_string()))
}

fn validated_root(path: &str) -> Result<PathBuf, ApiError> {
    let root = PathBuf::from(path);
    let metadata = fs::metadata(&root).map_err(|error| {
        let code = if error.kind() == std::io::ErrorKind::NotFound {
            "database_missing"
        } else {
            "database_open_error"
        };
        ApiError::new(
            code,
            format!(
                "failed to inspect Perfect Database path {}: {error}",
                root.display()
            ),
        )
    })?;
    if !metadata.is_dir() {
        return Err(ApiError::new(
            "database_open_error",
            format!(
                "Perfect Database path is not a directory: {}",
                root.display()
            ),
        ));
    }
    fs::canonicalize(&root).map_err(|error| {
        ApiError::new(
            "database_open_error",
            format!(
                "failed to canonicalize Perfect Database path {}: {error}",
                root.display()
            ),
        )
    })
}

fn ensure_complete(standard: &SupportedPerfectVariant) -> Result<(), ApiError> {
    if standard.is_fully_available() {
        return Ok(());
    }
    let missing = standard
        .sector_ids
        .iter()
        .filter(|id| standard.available_sector_ids.binary_search(id).is_err())
        .take(8)
        .map(|id| DatabaseVariant::STANDARD.sector_file_name(*id))
        .collect::<Vec<_>>();
    Err(ApiError::new(
        "database_incomplete",
        format!(
            "Perfect Database has {}/{} declared sectors; missing examples: {}",
            standard.available_sector_count(),
            standard.sector_count(),
            missing.join(", ")
        ),
    ))
}

fn build_identity(
    root: &Path,
    standard: &SupportedPerfectVariant,
    mode: IdentityMode,
) -> Result<PerfectIdentity, ApiError> {
    let secval_path = root.join(DatabaseVariant::STANDARD.secval_file_name());
    let secval_sha256 = sha256_file(&secval_path)
        .map_err(|message| ApiError::new("database_open_error", message))?;
    let mut manifest = Sha256::new();
    manifest.update(b"sanmill.perfect-db.fast-manifest.v1\0");
    update_length_prefixed(&mut manifest, secval_sha256.as_bytes());
    let mut placement = 0_usize;
    let mut settled = 0_usize;
    let mut flying = 0_usize;
    for id in &standard.sector_ids {
        classify_sector(*id, &mut placement, &mut settled, &mut flying);
        let name = DatabaseVariant::STANDARD.sector_file_name(*id);
        let path = root.join(&name);
        let metadata = fs::metadata(&path).map_err(|error| {
            ApiError::new(
                "database_incomplete",
                format!(
                    "failed to inspect Perfect DB sector {}: {error}",
                    path.display()
                ),
            )
        })?;
        if !metadata.is_file() {
            return Err(ApiError::new(
                "database_incomplete",
                format!(
                    "Perfect DB sector is not a regular file: {}",
                    path.display()
                ),
            ));
        }
        let mut file = File::open(&path).map_err(|error| {
            ApiError::new(
                "database_open_error",
                format!(
                    "failed to open Perfect DB sector {}: {error}",
                    path.display()
                ),
            )
        })?;
        let mut header = [0_u8; SECTOR_HEADER_SIZE];
        file.read_exact(&mut header).map_err(|error| {
            ApiError::new(
                "database_corrupt",
                format!(
                    "failed to read Perfect DB sector header {}: {error}",
                    path.display()
                ),
            )
        })?;
        SectorHeader::parse(&header).map_err(|error| {
            ApiError::new(
                "database_format_incompatible",
                format!(
                    "invalid Perfect DB sector header {}: {error}",
                    path.display()
                ),
            )
        })?;
        update_length_prefixed(&mut manifest, name.as_bytes());
        manifest.update(metadata.len().to_le_bytes());
        manifest.update(header);
    }
    let full_content_sha256 = if mode == IdentityMode::Full {
        Some(full_content_identity(root, standard)?)
    } else {
        None
    };
    Ok(PerfectIdentity {
        kind: "perfect_database",
        database_format: "malom-sector",
        sector_format_version: SECTOR_FORMAT_VERSION,
        variant: "std",
        root: root.display().to_string(),
        secval_sha256,
        fast_manifest_sha256: hex_lower(&manifest.finalize()),
        manifest_algorithm: "sha256(names,sizes,headers)-v1",
        declared_sector_count: standard.sector_count(),
        available_sector_count: standard.available_sector_count(),
        placement_sector_count: placement,
        settled_sector_count: settled,
        flying_related_sector_count: flying,
        fully_available: standard.is_fully_available(),
        full_content_sha256,
    })
}

fn build_stable_identity(
    root: &Path,
    standard: &SupportedPerfectVariant,
    mode: IdentityMode,
) -> Result<(PerfectIdentity, Vec<PerfectFileStamp>), ApiError> {
    let before = capture_file_stamps(root, standard)?;
    let identity = build_identity(root, standard, mode)?;
    let after = capture_file_stamps(root, standard)?;
    ensure_same_file_stamps(&before, &after)?;
    Ok((identity, after))
}

fn capture_file_stamps(
    root: &Path,
    standard: &SupportedPerfectVariant,
) -> Result<Vec<PerfectFileStamp>, ApiError> {
    let mut names = vec![DatabaseVariant::STANDARD.secval_file_name()];
    names.extend(
        standard
            .sector_ids
            .iter()
            .map(|id| DatabaseVariant::STANDARD.sector_file_name(*id)),
    );
    names
        .into_iter()
        .map(|name| file_stamp(&root.join(name)))
        .collect()
}

fn file_stamp(path: &Path) -> Result<PerfectFileStamp, ApiError> {
    let metadata = fs::metadata(path).map_err(|error| {
        let code = if error.kind() == std::io::ErrorKind::NotFound {
            "database_incomplete"
        } else {
            "database_open_error"
        };
        ApiError::new(
            code,
            format!(
                "failed to inspect Perfect Database file {}: {error}",
                path.display()
            ),
        )
    })?;
    if !metadata.is_file() {
        return Err(ApiError::new(
            "database_open_error",
            format!(
                "Perfect Database asset is not a regular file: {}",
                path.display()
            ),
        ));
    }
    let modified = metadata.modified().map_err(|error| {
        ApiError::new(
            "database_open_error",
            format!(
                "failed to read Perfect Database modification time {}: {error}",
                path.display()
            ),
        )
    })?;
    Ok(PerfectFileStamp {
        path: path.to_path_buf(),
        len: metadata.len(),
        modified,
    })
}

fn ensure_same_file_stamps(
    before: &[PerfectFileStamp],
    after: &[PerfectFileStamp],
) -> Result<(), ApiError> {
    if before == after {
        Ok(())
    } else {
        Err(ApiError::new(
            "database_changed",
            "Perfect Database file identity changed while it was being opened or hashed",
        ))
    }
}

fn full_content_identity(
    root: &Path,
    standard: &SupportedPerfectVariant,
) -> Result<String, ApiError> {
    let mut hash = Sha256::new();
    hash.update(b"sanmill.perfect-db.full-content.v1\0");
    let mut names = vec![DatabaseVariant::STANDARD.secval_file_name()];
    names.extend(
        standard
            .sector_ids
            .iter()
            .map(|id| DatabaseVariant::STANDARD.sector_file_name(*id)),
    );
    for name in names {
        let path = root.join(&name);
        let metadata = fs::metadata(&path).map_err(|error| {
            ApiError::new(
                "database_open_error",
                format!("failed to inspect {}: {error}", path.display()),
            )
        })?;
        update_length_prefixed(&mut hash, name.as_bytes());
        hash.update(metadata.len().to_le_bytes());
        let mut file = File::open(&path).map_err(|error| {
            ApiError::new(
                "database_open_error",
                format!("failed to open {}: {error}", path.display()),
            )
        })?;
        let mut buffer = vec![0_u8; 1024 * 1024];
        loop {
            let read = file.read(&mut buffer).map_err(|error| {
                ApiError::new(
                    "database_open_error",
                    format!("failed to read {}: {error}", path.display()),
                )
            })?;
            if read == 0 {
                break;
            }
            hash.update(&buffer[..read]);
        }
    }
    Ok(hex_lower(&hash.finalize()))
}

fn classify_sector(id: SectorId, placement: &mut usize, settled: &mut usize, flying: &mut usize) {
    if id.white_in_hand > 0 || id.black_in_hand > 0 {
        *placement += 1;
    } else {
        *settled += 1;
        if id.white_on_board <= 3 || id.black_on_board <= 3 {
            *flying += 1;
        }
    }
}

fn map_database_error(error: DatabaseError, default_code: &str) -> ApiError {
    match &error {
        DatabaseError::Read { source, .. } if source.kind() == std::io::ErrorKind::NotFound => {
            ApiError::new("database_incomplete", error.to_string())
        }
        DatabaseError::Parse { .. } | DatabaseError::InvalidUtf8 { .. } => {
            ApiError::new("database_corrupt", error.to_string())
        }
        DatabaseError::MissingSectorValue { .. } => {
            ApiError::new("database_format_incompatible", error.to_string())
        }
        DatabaseError::InvalidState { .. } => ApiError::new("invalid_state", error.to_string()),
        DatabaseError::Read { .. } => ApiError::new(default_code, error.to_string()),
    }
}

fn outcome_category(outcome: PerfectOutcome) -> &'static str {
    match outcome {
        PerfectOutcome::Win { .. } => "win",
        PerfectOutcome::Draw { .. } => "draw",
        PerfectOutcome::Loss { .. } => "loss",
    }
}

fn perfect_source_json(identity: &PerfectIdentity) -> Value {
    json!({
        "identity": identity,
        "query_mode": "strict_steps",
        "candidate_order": "full_turn_uci_lexicographic",
        "fallback": "none",
        "coverage": {
            "placing": true,
            "moving": true,
            "flying": true,
            "pending_removal": "resolved_by_legal_continuation"
        }
    })
}

fn logical_move_id(identity: &str, fen: &str, tokens: &[String]) -> String {
    let mut hash = Sha256::new();
    update_length_prefixed(&mut hash, b"perfect");
    update_length_prefixed(&mut hash, identity.as_bytes());
    update_length_prefixed(&mut hash, fen.as_bytes());
    for token in tokens {
        update_length_prefixed(&mut hash, token.as_bytes());
    }
    format!("perfect:{}", hex_lower(&hash.finalize()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::mill_data_query::position::ReplayedPosition;
    use crate::mill_data_query::protocol::{HistoryOrigin, PositionRequest};
    use std::sync::atomic::{AtomicUsize, Ordering};

    static FIXTURE_COUNTER: AtomicUsize = AtomicUsize::new(0);

    struct PerfectFixture {
        root: PathBuf,
    }

    impl Drop for PerfectFixture {
        fn drop(&mut self) {
            let _ = fs::remove_file(self.root.join("std.secval"));
            let _ = fs::remove_file(self.root.join("std_0_1_9_8.sec2"));
            let _ = fs::remove_dir(&self.root);
        }
    }

    fn initial_sector_fixture() -> PerfectFixture {
        let root = std::env::temp_dir().join(format!(
            "sanmill_data_query_perfect_{}_{}",
            std::process::id(),
            FIXTURE_COUNTER.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(&root).expect("fixture directory must be created");
        fs::write(
            root.join("std.secval"),
            b"virt_loss_val: -299\nvirt_win_val: 299\n1\n0 1 9 8 -18\n",
        )
        .expect("fixture secval must be written");
        let asset = Path::new(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../src/ui/flutter_app/assets/databases/std_0_1_9_8.sec2"
        ));
        fs::copy(asset, root.join("std_0_1_9_8.sec2")).expect("fixture sector must be copied");
        PerfectFixture { root }
    }

    fn initial_position() -> ReplayedPosition {
        ReplayedPosition::replay(&PositionRequest {
            rule: RulePreset::Nmm,
            initial: "startpos".to_owned(),
            history_origin: HistoryOrigin::GameStart,
            actions: Vec::new(),
            expected_current_fen: None,
        })
        .expect("initial position must replay")
    }

    fn open_error(path: &str) -> ApiError {
        match PerfectDbSource::open(path, Some(2)) {
            Ok(_) => panic!("Perfect Database fixture unexpectedly opened"),
            Err(error) => error,
        }
    }

    #[test]
    fn coverage_classification_distinguishes_phases() {
        let mut placement = 0;
        let mut settled = 0;
        let mut flying = 0;
        classify_sector(
            SectorId::new(2, 3, 7, 6),
            &mut placement,
            &mut settled,
            &mut flying,
        );
        classify_sector(
            SectorId::new(4, 5, 0, 0),
            &mut placement,
            &mut settled,
            &mut flying,
        );
        classify_sector(
            SectorId::new(3, 4, 0, 0),
            &mut placement,
            &mut settled,
            &mut flying,
        );
        assert_eq!((placement, settled, flying), (1, 2, 1));
    }

    #[test]
    fn strict_steps_returns_every_tied_initial_move_in_stable_order() {
        let fixture = initial_sector_fixture();
        let mut source = PerfectDbSource::open(fixture.root.to_str().unwrap(), Some(2)).unwrap();
        let result = source.query(&initial_position()).unwrap();

        assert_eq!(result.candidates.len(), 24);
        let actions = result
            .candidates
            .iter()
            .map(|candidate| candidate.full_turn_actions.join(" "))
            .collect::<Vec<_>>();
        let mut sorted = actions.clone();
        sorted.sort();
        assert_eq!(actions, sorted);
        assert!(result.candidates.iter().all(|candidate| {
            candidate.logical_ply_delta == 1
                && candidate
                    .perfect
                    .as_ref()
                    .is_some_and(|data| data.category == "draw" && data.steps == 1)
        }));
    }

    #[test]
    fn missing_incomplete_and_corrupt_databases_fail_closed() {
        let fixture = initial_sector_fixture();
        let missing = fixture.root.join("missing");
        let error = open_error(missing.to_str().unwrap());
        assert_eq!(error.code, "database_missing");

        fs::remove_file(fixture.root.join("std_0_1_9_8.sec2")).unwrap();
        let error = open_error(fixture.root.to_str().unwrap());
        assert_eq!(error.code, "database_incomplete");

        fs::write(
            fixture.root.join("std_0_1_9_8.sec2"),
            [0_u8; SECTOR_HEADER_SIZE],
        )
        .unwrap();
        let error = open_error(fixture.root.to_str().unwrap());
        assert!(
            matches!(
                error.code.as_str(),
                "database_format_incompatible" | "database_corrupt"
            ),
            "unexpected error code: {}",
            error.code
        );
    }

    #[test]
    fn an_open_database_detects_later_file_changes() {
        let fixture = initial_sector_fixture();
        let mut source = PerfectDbSource::open(fixture.root.to_str().unwrap(), Some(2)).unwrap();
        fs::write(
            fixture.root.join("std_0_1_9_8.sec2"),
            [0_u8; SECTOR_HEADER_SIZE + 1],
        )
        .unwrap();

        let error = source.query(&initial_position()).unwrap_err();
        assert_eq!(error.code, "database_changed");
    }
}
