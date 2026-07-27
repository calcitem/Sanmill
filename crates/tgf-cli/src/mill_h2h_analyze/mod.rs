// SPDX-License-Identifier: AGPL-3.0-or-later

use std::path::PathBuf;

use perfect_db::database::DatabaseVariant;
use tgf_cli::h2h_trace::{fingerprint_perfect_database, mill_rules_identity};
use tgf_mill::{MillRules, MillVariantOptions};

mod baseline;
mod model;
mod oracle;
mod process_replay;
mod replay;
mod report;
mod search;
mod trace;

use baseline::{
    accept_baseline, collect_pair_metrics, compare_baseline, load_baseline, no_baseline_gate,
    profile_fingerprint,
};
use model::{
    ANALYSIS_SCHEMA_VERSION, AnalysisSummary, AnalyzerError, EvidenceLevel, FindingClass,
    TraceFormat,
};
use oracle::{PerfectOracle, loss_reports, mark_all_database_unavailable};
use process_replay::run_process_replays;
use replay::replay_run;
use report::{ArtifactContext, prepare_artifacts, write_report};
use search::{SearchTriageConfig, analyze_search_cases};
use trace::load_run;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum FailOn {
    Baseline,
    None,
}

#[derive(Debug)]
struct AnalyzeArgs {
    log: PathBuf,
    manifest: Option<PathBuf>,
    out_dir: PathBuf,
    database: Option<PathBuf>,
    baseline: Option<PathBuf>,
    reference_engine: Option<PathBuf>,
    triage_nodes: u64,
    confirm_nodes: u64,
    max_search_cases: usize,
    fail_on: FailOn,
}

pub(crate) fn run_h2h_analyze(args: &[String]) {
    if matches!(args.first().map(String::as_str), Some("-h" | "--help")) {
        println!(
            "Usage: tgf mill h2h-analyze --log PATH --manifest PATH --out-dir PATH \
             [--db PATH] [--baseline PATH] [--reference-engine PATH] \
             [--triage-nodes N] [--confirm-nodes N] [--max-search-cases N] \
             [--fail-on baseline|none]"
        );
        return;
    }
    let exit_code = match parse_analyze_args(args).and_then(analyze) {
        Ok(code) => code,
        Err(error) => {
            eprintln!("[h2h-analyze] ERROR [{}]: {}", error.code, error.message);
            error.exit_code
        }
    };
    if exit_code != 0 {
        std::process::exit(exit_code);
    }
}

pub(crate) fn run_h2h_baseline(args: &[String]) {
    if matches!(args.first().map(String::as_str), Some("-h" | "--help")) {
        println!("Usage: tgf mill h2h-baseline accept --report PATH --out PATH");
        return;
    }
    let result = (|| {
        if args.first().map(String::as_str) != Some("accept") {
            return Err(AnalyzerError::arguments(
                "baseline_subcommand_required",
                "usage: tgf mill h2h-baseline accept --report PATH --out PATH",
            ));
        }
        let values = parse_named_args(&args[1..], &["--report", "--out"])?;
        let report = required_path(&values, "--report")?;
        let out = required_path(&values, "--out")?;
        accept_baseline(&report, &out)?;
        eprintln!(
            "[h2h-baseline] accepted {} -> {}",
            report.display(),
            out.display()
        );
        Ok(())
    })();
    if let Err(error) = result {
        eprintln!("[h2h-baseline] ERROR [{}]: {}", error.code, error.message);
        std::process::exit(error.exit_code);
    }
}

fn analyze(args: AnalyzeArgs) -> Result<i32, AnalyzerError> {
    if let Some(path) = args.reference_engine.as_ref()
        && !path.is_file()
    {
        return Err(AnalyzerError::arguments(
            "reference_engine_not_found",
            format!(
                "known-good reference engine does not exist: {}",
                path.display()
            ),
        ));
    }
    let run = load_run(&args.log, args.manifest.as_deref())?;
    let options = run
        .manifest
        .as_ref()
        .map(|manifest| manifest.rules.options.clone())
        .unwrap_or_else(MillVariantOptions::default);
    ensure_standard_nmm(&options)?;
    let rules_identity = mill_rules_identity(&options);
    let rules = MillRules::new(options.clone());
    let mut games = replay_run(&run, &options, &rules_identity.sha256);

    let database_artifact = args
        .database
        .as_ref()
        .map(|path| {
            fingerprint_perfect_database("analysis_database", path)
                .map_err(|message| AnalyzerError::arguments("database_identity_error", message))
        })
        .transpose()?;
    let database_identity = database_artifact.as_ref().and_then(|artifact| {
        artifact.fast_manifest_sha256.as_ref().map(|hash| {
            format!(
                "{}:{}/{}",
                hash,
                artifact.available_sector_count.unwrap_or(0),
                artifact.declared_sector_count.unwrap_or(0)
            )
        })
    });
    if let Some(path) = args.database.as_ref() {
        let mut oracle = PerfectOracle::open(path, &options)
            .map_err(|message| AnalyzerError::arguments("database_open_error", message))?;
        oracle.annotate(&mut games, &rules, &options, &rules_identity.sha256);
    } else {
        mark_all_database_unavailable(&mut games, &rules_identity.sha256);
    }

    let search_stats = analyze_search_cases(
        &mut games,
        &options,
        &rules_identity.sha256,
        SearchTriageConfig {
            triage_floor: args.triage_nodes,
            confirm_floor: args.confirm_nodes,
            max_cases: args.max_search_cases,
        },
    );
    if let Some(manifest) = run.manifest.as_ref()
        && search_stats.selected_cases > 0
    {
        run_process_replays(
            &mut games,
            manifest,
            args.reference_engine.as_deref(),
            &rules_identity.sha256,
        );
    }

    let losses = loss_reports(&games);
    let pair_metrics = collect_pair_metrics(&games, &losses);
    let profile = profile_fingerprint(
        run.manifest.as_ref(),
        args.triage_nodes,
        args.confirm_nodes,
        args.max_search_cases,
        args.reference_engine.as_deref(),
    );
    let gate = if let Some(path) = args.baseline.as_ref() {
        let baseline = load_baseline(path)?;
        compare_baseline(
            &pair_metrics,
            &baseline,
            &profile,
            database_identity.as_deref(),
        )
    } else {
        no_baseline_gate()
    };

    let mut incomplete_reasons = Vec::new();
    if let Some(reason) = run.truncated_tail.as_ref() {
        incomplete_reasons.push(reason.clone());
    }
    if let Some(manifest) = run.manifest.as_ref() {
        incomplete_reasons.extend(manifest_evidence_gaps(manifest));
    }
    for game in &games {
        for turn in &game.logical_turns {
            if turn
                .database
                .as_ref()
                .is_some_and(|evidence| evidence.status == "error")
            {
                incomplete_reasons.push(format!(
                    "game {} logical ply {} encountered a Perfect DB read error",
                    game.source.game_index, turn.logical_ply_index
                ));
            }
            if let Some(matrix) = turn.deterministic_search.as_ref()
                && matrix.probes.iter().any(|probe| probe.status != "complete")
            {
                incomplete_reasons.push(format!(
                    "game {} logical ply {} exhausted a deterministic search budget",
                    game.source.game_index, turn.logical_ply_index
                ));
            }
            if turn
                .process_replay
                .as_ref()
                .is_some_and(|evidence| evidence.status == "replay_incomplete")
            {
                incomplete_reasons.push(format!(
                    "game {} logical ply {} could not complete process replay",
                    game.source.game_index, turn.logical_ply_index
                ));
            }
        }
    }
    incomplete_reasons.sort();
    incomplete_reasons.dedup();
    let analysis_complete = incomplete_reasons.is_empty();
    let deterministic = run
        .manifest
        .as_ref()
        .is_some_and(|manifest| manifest.reproducibility.deterministic);
    let baselinable = run.format == TraceFormat::V2
        && deterministic
        && analysis_complete
        && database_identity.is_some();
    let expected_games = run
        .manifest
        .as_ref()
        .map(|manifest| manifest.expected_games)
        .unwrap_or(run.games.len());
    let trace_schema_version = match run.format {
        TraceFormat::V1 => 1,
        TraceFormat::V2 => 2,
    };
    let run_id = run
        .manifest
        .as_ref()
        .map(|manifest| manifest.run_id.clone())
        .unwrap_or_else(|| "legacy-v1".to_string());

    let prepared = prepare_artifacts(
        &run,
        &games,
        losses,
        &ArtifactContext {
            profile_fingerprint: &profile,
            database_identity: database_identity.as_deref(),
            database_path: args.database.as_deref(),
            reference_engine: args.reference_engine.as_deref(),
            triage_nodes: args.triage_nodes,
            confirm_nodes: args.confirm_nodes,
            max_search_cases: args.max_search_cases,
        },
    );
    let hard_anomaly_count = prepared
        .findings
        .iter()
        .filter(|finding| finding.is_hard())
        .count();
    let exact_move_error_count = prepared
        .findings
        .iter()
        .filter(|finding| {
            finding.evidence == EvidenceLevel::Exact
                && finding.classification == FindingClass::MoveError
        })
        .count();
    let probable_anomaly_count = prepared
        .findings
        .iter()
        .filter(|finding| {
            finding.evidence == EvidenceLevel::Probable
                && finding.classification == FindingClass::EngineAnomaly
        })
        .count();
    let unresolved_count = prepared
        .findings
        .iter()
        .filter(|finding| finding.evidence == EvidenceLevel::Unresolved)
        .count();
    let unresolved_loss_count = prepared
        .losses
        .iter()
        .filter(|loss| loss.unresolved)
        .count();
    let db_roots = games.iter().map(|game| game.logical_turns.len()).sum();
    let db_covered_roots = games
        .iter()
        .flat_map(|game| &game.logical_turns)
        .filter(|turn| {
            turn.database
                .as_ref()
                .is_some_and(|database| database.status == "covered")
        })
        .count();
    let summary = AnalysisSummary {
        analysis_schema_version: ANALYSIS_SCHEMA_VERSION,
        trace_schema_version,
        run_id,
        profile_fingerprint: profile,
        database_identity,
        deterministic,
        baselinable,
        analysis_complete,
        expected_games,
        analyzed_games: games.len(),
        analyzed_pairs: pair_metrics.len(),
        hard_anomaly_count,
        exact_move_error_count,
        probable_anomaly_count,
        unresolved_count,
        unresolved_loss_count,
        db_roots,
        db_covered_roots,
        search_cases: search_stats.selected_cases,
        search_completed_cases: search_stats.completed_cases,
        case_bundle_count: prepared.cases.len(),
        pair_metrics,
        gate,
        incomplete_reasons,
        artifact_sha256: None,
    };
    write_report(&args.out_dir, &summary, &prepared)?;
    eprintln!(
        "[h2h-analyze] games={} hard={} exact_move_errors={} probable={} unresolved={} search_selected={}/{} cases={} gate={} out={}",
        summary.analyzed_games,
        summary.hard_anomaly_count,
        summary.exact_move_error_count,
        summary.probable_anomaly_count,
        summary.unresolved_count,
        search_stats.selected_cases,
        search_stats.eligible_cases,
        summary.case_bundle_count,
        if summary.gate.passed { "pass" } else { "fail" },
        args.out_dir.display()
    );

    if !summary.gate.configuration_errors.is_empty() {
        return Ok(2);
    }
    if summary.hard_anomaly_count > 0 {
        return Ok(1);
    }
    if !summary.analysis_complete {
        return Ok(3);
    }
    if args.fail_on == FailOn::Baseline && !summary.gate.passed {
        return Ok(1);
    }
    Ok(0)
}

fn ensure_standard_nmm(options: &MillVariantOptions) -> Result<(), AnalyzerError> {
    if !matches!(
        DatabaseVariant::match_mill_options(options),
        Ok(DatabaseVariant::STANDARD)
    ) {
        return Err(AnalyzerError::arguments(
            "unsupported_variant",
            "h2h-analyze v1 supports standard Nine Men's Morris only",
        ));
    }
    Ok(())
}

fn manifest_evidence_gaps(manifest: &tgf_cli::h2h_trace::H2hTraceManifestV2) -> Vec<String> {
    let mut gaps = Vec::new();
    for engine in std::iter::once(&manifest.candidate).chain(manifest.reference.as_ref()) {
        if engine.binary_sha256.is_none() {
            gaps.push(format!("{} engine binary SHA-256 is missing", engine.role));
        }
        if engine.git_revision.is_none() {
            gaps.push(format!("{} engine Git revision is missing", engine.role));
        }
        if engine.uci_id.is_empty() {
            gaps.push(format!("{} engine UCI identity is missing", engine.role));
        }
        for environment in &engine.environment {
            if environment.replay_value.is_none() {
                gaps.push(format!(
                    "{} engine environment variable {} is hash-only and cannot be replayed faithfully",
                    engine.role, environment.name
                ));
            }
        }
    }
    for artifact in &manifest.artifacts {
        if artifact.sha256.is_none() && artifact.fast_manifest_sha256.is_none() {
            gaps.push(format!(
                "{} {} artifact has no stable content identity",
                artifact.role, artifact.kind
            ));
        }
    }
    if manifest.config.opening_plies > 0
        && !manifest
            .artifacts
            .iter()
            .any(|artifact| artifact.role == "opening_database")
    {
        gaps.push("paired Perfect DB opening artifact identity is missing".to_string());
    }
    if manifest.config.ai_is_lazy.is_none() {
        gaps.push("AiIsLazy was not explicitly pinned for replay".to_string());
    }
    gaps
}

fn parse_analyze_args(args: &[String]) -> Result<AnalyzeArgs, AnalyzerError> {
    let names = [
        "--log",
        "--manifest",
        "--out-dir",
        "--db",
        "--baseline",
        "--reference-engine",
        "--triage-nodes",
        "--confirm-nodes",
        "--max-search-cases",
        "--fail-on",
    ];
    let values = parse_named_args(args, &names)?;
    let log = required_path(&values, "--log")?;
    let out_dir = required_path(&values, "--out-dir")?;
    let manifest = optional_path(&values, "--manifest");
    let database = optional_path(&values, "--db");
    let baseline = optional_path(&values, "--baseline");
    let reference_engine = optional_path(&values, "--reference-engine");
    let triage_nodes = parse_number(&values, "--triage-nodes", 250_000_u64)?;
    let confirm_nodes = parse_number(&values, "--confirm-nodes", 1_000_000_u64)?;
    let max_search_cases = parse_number(&values, "--max-search-cases", 8_usize)?;
    if triage_nodes == 0 || confirm_nodes == 0 {
        return Err(AnalyzerError::arguments(
            "invalid_search_budget",
            "triage and confirm node budgets must be positive",
        ));
    }
    if confirm_nodes <= triage_nodes {
        return Err(AnalyzerError::arguments(
            "invalid_search_budget",
            "--confirm-nodes must be greater than --triage-nodes",
        ));
    }
    let fail_on = match values.get("--fail-on").map(String::as_str) {
        None => {
            if baseline.is_some() {
                FailOn::Baseline
            } else {
                FailOn::None
            }
        }
        Some("baseline") => FailOn::Baseline,
        Some("none") => FailOn::None,
        Some(value) => {
            return Err(AnalyzerError::arguments(
                "invalid_fail_on",
                format!("--fail-on must be `baseline` or `none`, got `{value}`"),
            ));
        }
    };
    if fail_on == FailOn::Baseline && baseline.is_none() {
        return Err(AnalyzerError::arguments(
            "baseline_required",
            "--fail-on baseline requires --baseline PATH",
        ));
    }
    Ok(AnalyzeArgs {
        log,
        manifest,
        out_dir,
        database,
        baseline,
        reference_engine,
        triage_nodes,
        confirm_nodes,
        max_search_cases,
        fail_on,
    })
}

fn parse_named_args(
    args: &[String],
    known: &[&str],
) -> Result<std::collections::BTreeMap<String, String>, AnalyzerError> {
    let mut values = std::collections::BTreeMap::new();
    let mut index = 0;
    while index < args.len() {
        let token = &args[index];
        if let Some((name, value)) = token.split_once('=') {
            if !known.contains(&name) || value.is_empty() {
                return Err(AnalyzerError::arguments(
                    "invalid_argument",
                    format!("unknown or empty argument `{token}`"),
                ));
            }
            if values.insert(name.to_string(), value.to_string()).is_some() {
                return Err(AnalyzerError::arguments(
                    "duplicate_argument",
                    format!("argument `{name}` was provided more than once"),
                ));
            }
            index += 1;
            continue;
        }
        if !known.contains(&token.as_str()) {
            return Err(AnalyzerError::arguments(
                "unknown_argument",
                format!("unknown argument `{token}`"),
            ));
        }
        let value = args.get(index + 1).ok_or_else(|| {
            AnalyzerError::arguments(
                "missing_argument_value",
                format!("{token} requires a value"),
            )
        })?;
        if value.starts_with("--") {
            return Err(AnalyzerError::arguments(
                "missing_argument_value",
                format!("{token} requires a value"),
            ));
        }
        if values.insert(token.clone(), value.clone()).is_some() {
            return Err(AnalyzerError::arguments(
                "duplicate_argument",
                format!("argument `{token}` was provided more than once"),
            ));
        }
        index += 2;
    }
    Ok(values)
}

fn required_path(
    values: &std::collections::BTreeMap<String, String>,
    name: &str,
) -> Result<PathBuf, AnalyzerError> {
    values.get(name).map(PathBuf::from).ok_or_else(|| {
        AnalyzerError::arguments(
            "missing_required_argument",
            format!("{name} PATH is required"),
        )
    })
}

fn optional_path(
    values: &std::collections::BTreeMap<String, String>,
    name: &str,
) -> Option<PathBuf> {
    values.get(name).map(PathBuf::from)
}

fn parse_number<T: std::str::FromStr>(
    values: &std::collections::BTreeMap<String, String>,
    name: &str,
    default: T,
) -> Result<T, AnalyzerError> {
    match values.get(name) {
        Some(value) => value.parse().map_err(|_| {
            AnalyzerError::arguments(
                "invalid_numeric_argument",
                format!("{name} got invalid value `{value}`"),
            )
        }),
        None => Ok(default),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use sha2::{Digest, Sha256};
    use tgf_cli::h2h_trace::{
        H2hActor, H2hArtifactIdentity, H2hDecisionTraceV2, H2hEngineIdentity, H2hGameEndKind,
        H2hGameTraceV2, H2hMatchConfig, H2hReproducibility, H2hTraceManifestV2,
    };

    #[test]
    fn argument_parser_is_strict_and_supports_equals() {
        let args = vec![
            "--log=a.jsonl".to_string(),
            "--out-dir".to_string(),
            "out".to_string(),
            "--fail-on".to_string(),
            "none".to_string(),
        ];
        let parsed = parse_analyze_args(&args).unwrap();
        assert_eq!(parsed.log, PathBuf::from("a.jsonl"));
        assert_eq!(parsed.max_search_cases, 8);

        let mut bad = args.clone();
        bad.push("--unknown".to_string());
        assert_eq!(parse_analyze_args(&bad).unwrap_err().exit_code, 2);
    }

    #[test]
    fn nonstandard_variants_are_explicitly_unsupported() {
        let options = MillVariantOptions {
            piece_count: 12,
            has_diagonal_lines: true,
            ..MillVariantOptions::default()
        };
        assert_eq!(
            ensure_standard_nmm(&options).unwrap_err().code,
            "unsupported_variant"
        );
    }

    #[test]
    fn two_pair_trace_to_report_and_llm_case_smoke() {
        let nonce = tgf_cli::h2h_trace::unix_time_ms();
        let root = std::env::temp_dir().join(format!(
            "sanmill-h2h-analyze-smoke-{}-{nonce}",
            std::process::id()
        ));
        std::fs::create_dir_all(&root).unwrap();
        let log = root.join("games.jsonl");
        let manifest_path = root.join("games.manifest.json");
        let out = root.join("report");

        let options = MillVariantOptions {
            n_move_rule: 50,
            endgame_n_move_rule: 20,
            ..MillVariantOptions::default()
        };
        let engine = H2hEngineIdentity {
            role: "candidate".to_string(),
            path: "target/release/tgf".to_string(),
            binary_sha256: Some("a".repeat(64)),
            git_revision: Some("test-revision".to_string()),
            arguments: vec!["uci".to_string()],
            uci_id: vec!["id name Sanmill smoke".to_string()],
            setoptions: Vec::new(),
            go_command: "go nodes 100000".to_string(),
            environment: Vec::new(),
        };
        let mut manifest = H2hTraceManifestV2::new(
            "smoke-run".to_string(),
            4,
            "self-current".to_string(),
            mill_rules_identity(&options),
            engine,
            None,
            H2hMatchConfig {
                jobs: 2,
                engine_threads: 1,
                skill_level: 30,
                max_plies: 120,
                opening_plies: 4,
                opening_seed: "0x1".to_string(),
                search_seed: Some("0x2".to_string()),
                strict_pairing: false,
                shuffling: true,
                algorithm: "mtdf".to_string(),
                draw_on_human_experience: true,
                ai_is_lazy: Some(false),
            },
            H2hReproducibility {
                fixed_nodes: true,
                single_thread: true,
                fixed_opening_seed: true,
                fixed_search_seed: true,
                non_timed_search: true,
                deterministic: true,
                nondeterministic_reasons: Vec::new(),
            },
            vec![H2hArtifactIdentity {
                role: "opening_database".to_string(),
                kind: "perfect_database".to_string(),
                path: "<smoke>".to_string(),
                sha256: Some("b".repeat(64)),
                fast_manifest_sha256: Some("c".repeat(64)),
                byte_len: Some(1),
                file_count: Some(1),
                declared_sector_count: Some(1),
                available_sector_count: Some(1),
                fully_available: Some(true),
            }],
        );
        manifest.completed_games = 4;
        std::fs::write(
            &manifest_path,
            serde_json::to_vec_pretty(&manifest).unwrap(),
        )
        .unwrap();

        let empty_sha = Sha256::digest([])
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect::<String>();
        let mut rows = Vec::new();
        for game_index in 0..4 {
            let moves = if game_index / 2 == 0 {
                ["d7", "a1", "g7", "d1"]
            } else {
                ["a4", "d7", "a7", "g7"]
            }
            .into_iter()
            .map(str::to_string)
            .collect::<Vec<_>>();
            let white_instance = format!("game-{game_index}-white");
            let row = H2hGameTraceV2 {
                schema_version: tgf_cli::h2h_trace::H2H_TRACE_SCHEMA_VERSION,
                run_id: manifest.run_id.clone(),
                game_index,
                pair_index: game_index / 2,
                worker_id: game_index % 2,
                current_white: None,
                result: "unfinished".to_string(),
                plies: moves.len(),
                opening_moves: moves.clone(),
                moves: moves.clone(),
                atomic_actions: moves,
                white_seed: Some(format!("0x{:x}", game_index * 2 + 1)),
                black_seed: Some(format!("0x{:x}", game_index * 2 + 2)),
                white_engine_instance_id: white_instance.clone(),
                black_engine_instance_id: format!("game-{game_index}-black"),
                winner: None,
                outcome_reason: "protocol_missing_bestmove".to_string(),
                end_kind: H2hGameEndKind::ProtocolError,
                decisions: vec![H2hDecisionTraceV2 {
                    actor: H2hActor::White,
                    engine_role: "candidate".to_string(),
                    engine_instance_id: white_instance,
                    instance_search_ordinal: 1,
                    action_index: 4,
                    logical_ply_index: 4,
                    go_command: "go nodes 100000".to_string(),
                    elapsed_ms: 1,
                    bestmove: None,
                    depth: None,
                    score_kind: None,
                    score_value: None,
                    nodes: None,
                    raw_uci_output: String::new(),
                    raw_uci_sha256: empty_sha.clone(),
                    raw_uci_truncated: false,
                    protocol_error: Some("engine_stdout_eof_before_bestmove".to_string()),
                }],
            };
            rows.push(serde_json::to_string(&row).unwrap());
        }
        std::fs::write(&log, rows.join("\n") + "\n").unwrap();

        let exit = analyze(AnalyzeArgs {
            log: log.clone(),
            manifest: Some(manifest_path),
            out_dir: out.clone(),
            database: None,
            baseline: None,
            reference_engine: None,
            triage_nodes: 250_000,
            confirm_nodes: 1_000_000,
            max_search_cases: 0,
            fail_on: FailOn::None,
        })
        .unwrap();
        assert_eq!(
            exit, 1,
            "protocol anomalies must fail after writing evidence"
        );
        for path in [
            "summary.json",
            "findings.jsonl",
            "losses.jsonl",
            "clusters.json",
            "report.md",
            "SHA256SUMS",
        ] {
            assert!(out.join(path).is_file(), "missing {path}");
        }
        let summary: AnalysisSummary =
            serde_json::from_slice(&std::fs::read(out.join("summary.json")).unwrap()).unwrap();
        assert_eq!(summary.analyzed_games, 4);
        assert_eq!(summary.analyzed_pairs, 2);
        assert!(summary.case_bundle_count > 0);
        let case_markdown = std::fs::read_dir(out.join("cases"))
            .unwrap()
            .filter_map(Result::ok)
            .find(|entry| entry.path().extension().is_some_and(|ext| ext == "md"))
            .expect("at least one LLM Markdown case")
            .path();
        let markdown = std::fs::read_to_string(case_markdown).unwrap();
        assert!(markdown.contains("## Proven facts"));
        assert!(markdown.contains("## Prompt for an LLM"));
        assert!(markdown.contains("tgf mill h2h-analyze"));
        std::fs::remove_dir_all(root).ok();
    }
}
