// SPDX-License-Identifier: AGPL-3.0-or-later

use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};

use serde_json::{Value, json};
use tgf_cli::h2h_trace::{
    H2hEngineIdentity, H2hSetOption, H2hTraceManifestV2, sha256_bytes, sha256_file, unix_time_ms,
};

use super::model::{
    ANALYSIS_SCHEMA_VERSION, AnalysisSummary, AnalyzerError, BASELINE_SCHEMA_VERSION, GateMetric,
    GateResult, H2hBaseline, LossReport, PairMetrics, ReplayedGame, Z_99_9,
};

pub(crate) fn profile_fingerprint(
    manifest: Option<&H2hTraceManifestV2>,
    triage_nodes: u64,
    confirm_nodes: u64,
    max_search_cases: usize,
    reference_engine: Option<&Path>,
) -> String {
    let reference_engine_sha256 = reference_engine.and_then(|path| sha256_file(path).ok());
    let value = match manifest {
        Some(manifest) => json!({
            "analysis": {
                "schema": ANALYSIS_SCHEMA_VERSION,
                "triage_nodes": triage_nodes,
                "confirm_nodes": confirm_nodes,
                "max_search_cases": max_search_cases,
                "known_good_reference_sha256": reference_engine_sha256,
            },
            "trace_schema": manifest.schema_version,
            "mode": manifest.mode,
            "rules_sha256": manifest.rules.sha256,
            "rules_options": manifest.rules.options,
            "config": manifest.config,
            "reproducibility": manifest.reproducibility,
            // Candidate binary/revision intentionally stay out: the baseline
            // exists to compare commits under one stable profile.
            "candidate": profile_engine(&manifest.candidate, false),
            // A changed opponent is a changed experiment.
            "reference": manifest.reference.as_ref().map(|reference| {
                profile_engine(reference, true)
            }),
            // Paths are machine-local; content identities are not.
            "artifacts": manifest.artifacts.iter().map(|artifact| json!({
                "role": artifact.role,
                "kind": artifact.kind,
                "sha256": artifact.sha256,
                "fast_manifest_sha256": artifact.fast_manifest_sha256,
                "byte_len": artifact.byte_len,
                "file_count": artifact.file_count,
                "declared_sector_count": artifact.declared_sector_count,
                "available_sector_count": artifact.available_sector_count,
                "fully_available": artifact.fully_available,
            })).collect::<Vec<_>>(),
        }),
        None => json!({
            "analysis": {
                "schema": ANALYSIS_SCHEMA_VERSION,
                "triage_nodes": triage_nodes,
                "confirm_nodes": confirm_nodes,
                "max_search_cases": max_search_cases,
                "known_good_reference_sha256": reference_engine_sha256,
            },
            "trace_schema": 1,
            "legacy": true,
        }),
    };
    let bytes = serde_json::to_vec(&value).expect("profile JSON serialization must succeed");
    sha256_bytes(b"sanmill.h2h.analysis-profile.v1\0", &bytes)
}

fn profile_engine(identity: &H2hEngineIdentity, include_binary: bool) -> Value {
    json!({
        "arguments": identity.arguments,
        "setoptions": identity.setoptions.iter().map(profile_setoption).collect::<Vec<_>>(),
        "go_command": identity.go_command,
        "environment": identity.environment.iter().map(|value| json!({
            "name": value.name,
            "value_sha256": value.value_sha256,
        })).collect::<Vec<_>>(),
        "binary_sha256": include_binary.then_some(identity.binary_sha256.as_ref()).flatten(),
        "git_revision": include_binary.then_some(identity.git_revision.as_ref()).flatten(),
        "uci_id": include_binary.then_some(&identity.uci_id),
    })
}

fn profile_setoption(option: &H2hSetOption) -> Value {
    let value = if option.name.to_ascii_lowercase().contains("path") {
        "<artifact-path>"
    } else {
        option.value.as_str()
    };
    json!({"name": option.name, "value": value})
}

pub(crate) fn collect_pair_metrics(
    games: &[ReplayedGame],
    losses: &[LossReport],
) -> Vec<PairMetrics> {
    let mut pairs = BTreeMap::<usize, PairMetrics>::new();
    for game in games {
        let metrics = pairs
            .entry(game.source.pair_index)
            .or_insert_with(|| PairMetrics {
                pair_index: game.source.pair_index,
                ..Default::default()
            });
        metrics.games += 1;
        if game.source.is_loss_for_candidate() {
            metrics.losses += 1;
        }
        let candidate_actions = game
            .source
            .decisions
            .iter()
            .filter(|decision| decision.engine_role == "candidate")
            .map(|decision| decision.action_index)
            .collect::<BTreeSet<_>>();
        let exact = game.findings.iter().filter(|finding| {
            finding.classification == super::model::FindingClass::MoveError
                && finding.evidence == super::model::EvidenceLevel::Exact
                && finding
                    .action_index
                    .is_some_and(|index| candidate_actions.contains(&index))
        });
        let exact = exact.collect::<Vec<_>>();
        if !exact.is_empty() {
            metrics.games_with_wdl_drop += 1;
        }
        metrics.severity_2_events += exact
            .iter()
            .filter(|finding| {
                finding.database.as_ref().is_some_and(|database| {
                    database
                        .best_wdl
                        .zip(database.played_wdl)
                        .is_some_and(|(best, played)| best - played == 2)
                })
            })
            .count() as u32;
        metrics.process_state_dependence += game
            .findings
            .iter()
            .filter(|finding| {
                finding.code == "process_state_dependence"
                    && finding
                        .action_index
                        .is_some_and(|index| candidate_actions.contains(&index))
            })
            .count() as u32;
        for turn in &game.logical_turns {
            metrics.db_roots += 1;
            if turn
                .database
                .as_ref()
                .is_some_and(|database| database.status == "covered")
            {
                metrics.db_covered_roots += 1;
            }
            if let Some(matrix) = turn.deterministic_search.as_ref() {
                metrics.search_cases += 1;
                if matrix.probes.iter().all(|probe| probe.status == "complete") {
                    metrics.search_completed_cases += 1;
                }
                let exact_here = exact
                    .iter()
                    .any(|finding| finding.action_index == Some(turn.action_start));
                if exact_here && matrix.probable {
                    metrics.persistent_db_errors += 1;
                }
            }
        }
    }
    for loss in losses {
        let candidate_lost = games
            .iter()
            .find(|game| game.source.game_index == loss.game_index)
            .is_some_and(|game| game.source.is_loss_for_candidate());
        if loss.unresolved
            && candidate_lost
            && let Some(metrics) = pairs.get_mut(&loss.pair_index)
        {
            metrics.unresolved_losses += 1;
        }
    }
    pairs.into_values().collect()
}

pub(crate) fn no_baseline_gate() -> GateResult {
    GateResult {
        mode: "none".to_string(),
        passed: true,
        configuration_errors: Vec::new(),
        metrics: Vec::new(),
    }
}

pub(crate) fn compare_baseline(
    current: &[PairMetrics],
    baseline: &H2hBaseline,
    profile_fingerprint: &str,
    database_identity: Option<&str>,
) -> GateResult {
    let mut errors = Vec::new();
    if baseline.baseline_schema_version != BASELINE_SCHEMA_VERSION
        || baseline.analysis_schema_version != ANALYSIS_SCHEMA_VERSION
    {
        errors.push("baseline or analysis schema version mismatch".to_string());
    }
    if baseline.profile_fingerprint != profile_fingerprint {
        errors.push("analysis profile fingerprint differs from the baseline".to_string());
    }
    if baseline.database_identity.as_deref() != database_identity {
        errors.push("Perfect DB identity differs from the baseline".to_string());
    }
    if current.len() != baseline.pair_metrics.len()
        || current
            .iter()
            .zip(&baseline.pair_metrics)
            .any(|(left, right)| left.pair_index != right.pair_index)
    {
        errors.push("paired opening units differ from the baseline".to_string());
    }
    if errors.is_empty() {
        let baseline_db_coverage = aggregate_coverage(
            &baseline.pair_metrics,
            |value| value.db_covered_roots,
            |value| value.db_roots,
        );
        let current_db_coverage = aggregate_coverage(
            current,
            |value| value.db_covered_roots,
            |value| value.db_roots,
        );
        if current_db_coverage + f64::EPSILON < baseline_db_coverage {
            errors.push(format!(
                "Perfect DB coverage declined from {baseline_db_coverage:.6} to {current_db_coverage:.6}"
            ));
        }
        let baseline_search_coverage = aggregate_coverage(
            &baseline.pair_metrics,
            |value| value.search_completed_cases,
            |value| value.search_cases,
        );
        let current_search_coverage = aggregate_coverage(
            current,
            |value| value.search_completed_cases,
            |value| value.search_cases,
        );
        if current_search_coverage + f64::EPSILON < baseline_search_coverage {
            errors.push(format!(
                "deterministic search coverage declined from {baseline_search_coverage:.6} to {current_search_coverage:.6}"
            ));
        }
    }
    if !errors.is_empty() {
        return GateResult {
            mode: "baseline".to_string(),
            passed: false,
            configuration_errors: errors,
            metrics: Vec::new(),
        };
    }

    let metric = |name: &str, values: Vec<f64>| paired_metric(name, &values);
    let mut metrics = vec![
        metric(
            "games_with_wdl_drop",
            paired(current, &baseline.pair_metrics, |value| {
                f64::from(value.games_with_wdl_drop)
            }),
        ),
        metric(
            "severity_2_events",
            paired(current, &baseline.pair_metrics, |value| {
                f64::from(value.severity_2_events)
            }),
        ),
        metric(
            "persistent_db_errors",
            paired(current, &baseline.pair_metrics, |value| {
                f64::from(value.persistent_db_errors)
            }),
        ),
        metric(
            "process_state_dependence",
            paired(current, &baseline.pair_metrics, |value| {
                f64::from(value.process_state_dependence)
            }),
        ),
        metric(
            "unresolved_loss_rate",
            paired(
                current,
                &baseline.pair_metrics,
                PairMetrics::unresolved_loss_rate,
            ),
        ),
    ];
    // Coverage is a good metric, so invert the delta: positive means the
    // current run is worse, matching every other gate metric.
    metrics.push(paired_metric(
        "db_coverage_regression",
        &baseline
            .pair_metrics
            .iter()
            .zip(current)
            .map(|(base, now)| base.db_coverage_rate() - now.db_coverage_rate())
            .collect::<Vec<_>>(),
    ));
    metrics.push(paired_metric(
        "search_coverage_regression",
        &baseline
            .pair_metrics
            .iter()
            .zip(current)
            .map(|(base, now)| base.search_coverage_rate() - now.search_coverage_rate())
            .collect::<Vec<_>>(),
    ));
    let passed = metrics.iter().all(|metric| !metric.regressed);
    GateResult {
        mode: "baseline".to_string(),
        passed,
        configuration_errors: Vec::new(),
        metrics,
    }
}

fn aggregate_coverage(
    values: &[PairMetrics],
    covered: impl Fn(&PairMetrics) -> u32,
    total: impl Fn(&PairMetrics) -> u32,
) -> f64 {
    let covered = values.iter().map(&covered).map(u64::from).sum::<u64>();
    let total = values.iter().map(&total).map(u64::from).sum::<u64>();
    if total == 0 {
        1.0
    } else {
        covered as f64 / total as f64
    }
}

fn paired(
    current: &[PairMetrics],
    baseline: &[PairMetrics],
    value: impl Fn(&PairMetrics) -> f64,
) -> Vec<f64> {
    current
        .iter()
        .zip(baseline)
        .map(|(now, base)| value(now) - value(base))
        .collect()
}

fn paired_metric(name: &str, values: &[f64]) -> GateMetric {
    let count = values.len();
    let mean = if count == 0 {
        0.0
    } else {
        values.iter().sum::<f64>() / count as f64
    };
    let variance = if count > 1 {
        values
            .iter()
            .map(|value| (value - mean).powi(2))
            .sum::<f64>()
            / (count - 1) as f64
    } else {
        0.0
    };
    let margin = if count == 0 {
        0.0
    } else {
        Z_99_9 * variance.sqrt() / (count as f64).sqrt()
    };
    let lower = mean - margin;
    let upper = mean + margin;
    GateMetric {
        name: name.to_string(),
        paired_count: count,
        mean_delta: mean,
        lower_99_9: lower,
        upper_99_9: upper,
        regressed: lower > 0.0,
    }
}

pub(crate) fn load_baseline(path: &Path) -> Result<H2hBaseline, AnalyzerError> {
    let bytes = std::fs::read(path).map_err(|error| {
        AnalyzerError::arguments(
            "baseline_read_error",
            format!("failed to read {}: {error}", path.display()),
        )
    })?;
    serde_json::from_slice(&bytes).map_err(|error| {
        AnalyzerError::arguments(
            "baseline_schema_error",
            format!("failed to parse {}: {error}", path.display()),
        )
    })
}

pub(crate) fn accept_baseline(report: &Path, out: &Path) -> Result<(), AnalyzerError> {
    let summary_path = resolve_summary_path(report);
    let bytes = std::fs::read(&summary_path).map_err(|error| {
        AnalyzerError::arguments(
            "report_read_error",
            format!("failed to read {}: {error}", summary_path.display()),
        )
    })?;
    let summary: AnalysisSummary = serde_json::from_slice(&bytes).map_err(|error| {
        AnalyzerError::arguments(
            "report_schema_error",
            format!("failed to parse {}: {error}", summary_path.display()),
        )
    })?;
    let baseline = baseline_from_summary(&summary, &summary_path)?;
    if let Some(parent) = out.parent().filter(|path| !path.as_os_str().is_empty()) {
        std::fs::create_dir_all(parent).map_err(|error| {
            AnalyzerError::incomplete(
                "baseline_write_error",
                format!("failed to create {}: {error}", parent.display()),
            )
        })?;
    }
    let file = std::fs::File::create(out).map_err(|error| {
        AnalyzerError::incomplete(
            "baseline_write_error",
            format!("failed to create {}: {error}", out.display()),
        )
    })?;
    serde_json::to_writer_pretty(file, &baseline).map_err(|error| {
        AnalyzerError::incomplete(
            "baseline_write_error",
            format!("failed to write {}: {error}", out.display()),
        )
    })
}

fn baseline_from_summary(
    summary: &AnalysisSummary,
    summary_path: &Path,
) -> Result<H2hBaseline, AnalyzerError> {
    if summary.analysis_schema_version != ANALYSIS_SCHEMA_VERSION {
        return Err(AnalyzerError::arguments(
            "analysis_schema_mismatch",
            "report analysis schema is not supported",
        ));
    }
    if summary.hard_anomaly_count > 0 {
        return Err(AnalyzerError::arguments(
            "baseline_contains_hard_anomaly",
            "reports with hard rules/protocol anomalies cannot become baselines",
        ));
    }
    if !summary.deterministic {
        return Err(AnalyzerError::arguments(
            "baseline_nondeterministic",
            "a baseline requires fixed nodes, one thread, fixed seeds, and no timing",
        ));
    }
    if !summary.analysis_complete {
        return Err(AnalyzerError::arguments(
            "baseline_analysis_incomplete",
            "an incomplete or budget-failed analysis cannot become a baseline",
        ));
    }
    if !summary.baselinable {
        return Err(AnalyzerError::arguments(
            "baseline_report_ineligible",
            "legacy or profile-incomplete reports cannot become baselines",
        ));
    }
    if !summary.gate.configuration_errors.is_empty() {
        return Err(AnalyzerError::arguments(
            "baseline_gate_configuration_error",
            "the report contains gate/profile configuration errors",
        ));
    }
    let report_hash = sha256_file(summary_path).map_err(|error| {
        AnalyzerError::arguments(
            "report_hash_error",
            format!("failed to hash {}: {error}", summary_path.display()),
        )
    })?;
    Ok(H2hBaseline {
        baseline_schema_version: BASELINE_SCHEMA_VERSION,
        analysis_schema_version: summary.analysis_schema_version,
        trace_schema_version: summary.trace_schema_version,
        profile_fingerprint: summary.profile_fingerprint.clone(),
        database_identity: summary.database_identity.clone(),
        approved_report_sha256: report_hash,
        accepted_unix_ms: unix_time_ms(),
        pair_metrics: summary.pair_metrics.clone(),
    })
}

fn resolve_summary_path(report: &Path) -> PathBuf {
    if report.is_dir() {
        report.join("summary.json")
    } else {
        report.to_path_buf()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn metrics(pair: usize, errors: u32) -> PairMetrics {
        PairMetrics {
            pair_index: pair,
            games: 2,
            games_with_wdl_drop: errors,
            db_roots: 2,
            db_covered_roots: 2,
            ..Default::default()
        }
    }

    fn valid_summary() -> AnalysisSummary {
        AnalysisSummary {
            analysis_schema_version: ANALYSIS_SCHEMA_VERSION,
            trace_schema_version: 2,
            run_id: "run".to_string(),
            profile_fingerprint: "profile".to_string(),
            database_identity: Some("db".to_string()),
            deterministic: true,
            baselinable: true,
            analysis_complete: true,
            expected_games: 2,
            analyzed_games: 2,
            analyzed_pairs: 1,
            hard_anomaly_count: 0,
            exact_move_error_count: 0,
            probable_anomaly_count: 0,
            unresolved_count: 0,
            unresolved_loss_count: 0,
            db_roots: 2,
            db_covered_roots: 2,
            search_cases: 0,
            search_completed_cases: 0,
            case_bundle_count: 0,
            pair_metrics: vec![metrics(0, 0)],
            gate: no_baseline_gate(),
            incomplete_reasons: Vec::new(),
            artifact_sha256: None,
        }
    }

    #[test]
    fn paired_gate_uses_99_9_percent_lower_bound() {
        let baseline = H2hBaseline {
            baseline_schema_version: BASELINE_SCHEMA_VERSION,
            analysis_schema_version: ANALYSIS_SCHEMA_VERSION,
            trace_schema_version: 2,
            profile_fingerprint: "profile".to_string(),
            database_identity: Some("db".to_string()),
            approved_report_sha256: "hash".to_string(),
            accepted_unix_ms: 0,
            pair_metrics: (0..32).map(|pair| metrics(pair, 0)).collect(),
        };
        let current = (0..32).map(|pair| metrics(pair, 1)).collect::<Vec<_>>();
        let gate = compare_baseline(&current, &baseline, "profile", Some("db"));
        assert!(!gate.passed);
        assert!(
            gate.metrics
                .iter()
                .find(|metric| metric.name == "games_with_wdl_drop")
                .unwrap()
                .lower_99_9
                > 0.0
        );
    }

    #[test]
    fn profile_or_database_mismatch_is_configuration_failure() {
        let baseline = H2hBaseline {
            baseline_schema_version: BASELINE_SCHEMA_VERSION,
            analysis_schema_version: ANALYSIS_SCHEMA_VERSION,
            trace_schema_version: 2,
            profile_fingerprint: "old".to_string(),
            database_identity: Some("old-db".to_string()),
            approved_report_sha256: "hash".to_string(),
            accepted_unix_ms: 0,
            pair_metrics: vec![metrics(0, 0)],
        };
        let gate = compare_baseline(&[metrics(0, 0)], &baseline, "new", Some("new-db"));
        assert!(!gate.passed);
        assert_eq!(gate.configuration_errors.len(), 2);
    }

    #[test]
    fn coverage_decline_is_a_configuration_failure() {
        let baseline = H2hBaseline {
            baseline_schema_version: BASELINE_SCHEMA_VERSION,
            analysis_schema_version: ANALYSIS_SCHEMA_VERSION,
            trace_schema_version: 2,
            profile_fingerprint: "profile".to_string(),
            database_identity: Some("db".to_string()),
            approved_report_sha256: "hash".to_string(),
            accepted_unix_ms: 0,
            pair_metrics: vec![metrics(0, 0)],
        };
        let mut current = metrics(0, 0);
        current.db_covered_roots = 1;
        let gate = compare_baseline(&[current], &baseline, "profile", Some("db"));
        assert!(!gate.passed);
        assert!(
            gate.configuration_errors
                .iter()
                .any(|error| error.contains("coverage declined"))
        );
    }

    #[test]
    fn analyzer_budgets_are_part_of_the_profile() {
        let first = profile_fingerprint(None, 250_000, 1_000_000, 8, None);
        let second = profile_fingerprint(None, 250_000, 2_000_000, 8, None);
        assert_ne!(first, second);
    }

    #[test]
    fn baseline_acceptance_rejects_hard_and_nondeterministic_reports() {
        let mut hard = valid_summary();
        hard.hard_anomaly_count = 1;
        assert_eq!(
            baseline_from_summary(&hard, Path::new("unused"))
                .unwrap_err()
                .code,
            "baseline_contains_hard_anomaly"
        );

        let mut nondeterministic = valid_summary();
        nondeterministic.deterministic = false;
        assert_eq!(
            baseline_from_summary(&nondeterministic, Path::new("unused"))
                .unwrap_err()
                .code,
            "baseline_nondeterministic"
        );
    }
}
