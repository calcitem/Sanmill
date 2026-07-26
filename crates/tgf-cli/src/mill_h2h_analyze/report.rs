// SPDX-License-Identifier: AGPL-3.0-or-later

use std::collections::{BTreeMap, BTreeSet};
use std::io::Write;
use std::path::{Path, PathBuf};

use tgf_cli::h2h_trace::{H2hTraceManifestV2, sha256_bytes, sha256_file};

use super::model::{
    AnalysisSummary, AnalyzerError, CaseBundle, ClusterReport, DeterministicSearchMatrix,
    EvidenceLevel, Finding, FindingClass, LoadedRun, LossReport, ProcessReplayEvidence,
    ReplayedGame,
};
use super::process_replay::instance_chronology;

pub(crate) struct PreparedArtifacts {
    pub findings: Vec<Finding>,
    pub losses: Vec<LossReport>,
    pub clusters: Vec<ClusterReport>,
    pub cases: Vec<CaseBundle>,
}

pub(crate) struct ArtifactContext<'a> {
    pub profile_fingerprint: &'a str,
    pub database_identity: Option<&'a str>,
    pub database_path: Option<&'a Path>,
    pub reference_engine: Option<&'a Path>,
    pub triage_nodes: u64,
    pub confirm_nodes: u64,
    pub max_search_cases: usize,
}

pub(crate) fn prepare_artifacts(
    run: &LoadedRun,
    games: &[ReplayedGame],
    mut losses: Vec<LossReport>,
    context: &ArtifactContext<'_>,
) -> PreparedArtifacts {
    let mut findings = games
        .iter()
        .flat_map(|game| game.findings.iter().cloned())
        .collect::<Vec<_>>();
    findings.sort_by(|left, right| {
        (
            left.game_index,
            left.action_index.unwrap_or(usize::MAX),
            left.finding_id.as_str(),
        )
            .cmp(&(
                right.game_index,
                right.action_index.unwrap_or(usize::MAX),
                right.finding_id.as_str(),
            ))
    });
    let mut clusters = cluster_findings(&findings);
    let mut requested = BTreeMap::<String, CaseRequest>::new();

    for cluster in &clusters {
        let Some(finding) = findings
            .iter()
            .find(|finding| finding.finding_id == cluster.representative_finding_id)
        else {
            continue;
        };
        // Routine DB misses and finite-budget move errors remain visible in
        // findings/clusters, but generating one Markdown file for every exact
        // root would explode a long partial-DB run. Evidence bundles are
        // mandatory for every unresolved loss and for actual engineering
        // anomaly clusters.
        if finding.classification != FindingClass::EngineAnomaly {
            continue;
        }
        let key = case_key(
            finding.game_index,
            finding.action_index,
            std::slice::from_ref(&finding.code),
        );
        requested.entry(key.clone()).or_insert_with(|| CaseRequest {
            case_id: key,
            game_index: finding.game_index,
            action_index: finding.action_index,
            finding_ids: vec![finding.finding_id.clone()],
            loss_game: false,
        });
    }
    for loss in &losses {
        if !loss.unresolved {
            continue;
        }
        let game = games
            .iter()
            .find(|game| game.source.game_index == loss.game_index);
        let action_index = loss
            .earliest_observed_suspect
            .and_then(|logical| {
                game.and_then(|game| {
                    game.logical_turns
                        .iter()
                        .find(|turn| turn.logical_ply_index == logical)
                        .map(|turn| turn.action_start)
                })
            })
            .or_else(|| {
                game.and_then(|game| {
                    game.logical_turns
                        .iter()
                        .rev()
                        .find(|turn| Some(turn.actor) == loss.loser)
                        .or_else(|| game.logical_turns.last())
                        .map(|turn| turn.action_start)
                })
            });
        let codes = findings
            .iter()
            .filter(|finding| finding.game_index == loss.game_index)
            .map(|finding| finding.code.clone())
            .collect::<Vec<_>>();
        let key = case_key(loss.game_index, action_index, &codes);
        requested
            .entry(key.clone())
            .and_modify(|request| request.loss_game = true)
            .or_insert_with(|| CaseRequest {
                case_id: key,
                game_index: loss.game_index,
                action_index,
                finding_ids: findings
                    .iter()
                    .filter(|finding| finding.game_index == loss.game_index)
                    .map(|finding| finding.finding_id.clone())
                    .collect(),
                loss_game: true,
            });
    }

    let mut cases = requested
        .values()
        .filter_map(|request| build_case(request, run, games, &findings, context))
        .collect::<Vec<_>>();
    cases.sort_by(|left, right| left.case_id.cmp(&right.case_id));
    let case_by_finding = requested
        .values()
        .flat_map(|request| {
            request
                .finding_ids
                .iter()
                .map(move |finding| (finding.clone(), request.case_id.clone()))
        })
        .collect::<BTreeMap<_, _>>();
    for finding in &mut findings {
        if let Some(case_id) = case_by_finding.get(&finding.finding_id) {
            finding.case_ids.push(case_id.clone());
        }
    }
    for cluster in &mut clusters {
        cluster.representative_case_id = case_by_finding
            .get(&cluster.representative_finding_id)
            .cloned();
    }
    let case_by_game = requested
        .iter()
        .filter(|(_, request)| request.loss_game)
        .map(|(_, request)| (request.game_index, request.case_id.clone()))
        .collect::<BTreeMap<_, _>>();
    for loss in &mut losses {
        if let Some(case_id) = case_by_game.get(&loss.game_index) {
            loss.case_ids.push(case_id.clone());
        }
    }

    PreparedArtifacts {
        findings,
        losses,
        clusters,
        cases,
    }
}

#[derive(Clone, Debug)]
struct CaseRequest {
    case_id: String,
    game_index: usize,
    action_index: Option<usize>,
    finding_ids: Vec<String>,
    loss_game: bool,
}

fn cluster_findings(findings: &[Finding]) -> Vec<ClusterReport> {
    let mut groups = BTreeMap::<(String, String), Vec<&Finding>>::new();
    for finding in findings.iter().filter(|finding| {
        finding.evidence != EvidenceLevel::Advisory
            && finding.classification != FindingClass::ReplayNote
    }) {
        for (level, key) in [
            ("exact_case", finding.exact_case_key.as_ref()),
            (
                "canonical_position",
                finding.canonical_position_key.as_ref(),
            ),
            ("semantic_signature", finding.semantic_signature.as_ref()),
        ] {
            if let Some(key) = key {
                groups
                    .entry((level.to_string(), key.clone()))
                    .or_default()
                    .push(finding);
            }
        }
    }
    groups
        .into_iter()
        .map(|((level, key), mut members)| {
            members.sort_by_key(|finding| {
                (
                    finding.game_index,
                    finding.action_index.unwrap_or(usize::MAX),
                )
            });
            ClusterReport {
                cluster_level: level,
                key,
                finding_count: members.len(),
                finding_ids: members
                    .iter()
                    .map(|finding| finding.finding_id.clone())
                    .collect(),
                representative_finding_id: members[0].finding_id.clone(),
                representative_case_id: None,
            }
        })
        .collect()
}

fn build_case(
    request: &CaseRequest,
    run: &LoadedRun,
    games: &[ReplayedGame],
    findings: &[Finding],
    context: &ArtifactContext<'_>,
) -> Option<CaseBundle> {
    let game = games
        .iter()
        .find(|game| game.source.game_index == request.game_index)?;
    let turn = request
        .action_index
        .and_then(|index| {
            game.logical_turns
                .iter()
                .find(|turn| turn.action_start <= index && index < turn.action_end)
        })
        .or_else(|| {
            request
                .action_index
                .is_none()
                .then(|| game.logical_turns.last())
                .flatten()
        });
    let related = findings
        .iter()
        .filter(|finding| request.finding_ids.contains(&finding.finding_id))
        .collect::<Vec<_>>();
    let mut facts = distinct(
        related
            .iter()
            .flat_map(|finding| finding.facts.iter().cloned())
            .chain(
                request
                    .loss_game
                    .then_some("this game is an unresolved loss".to_string()),
            ),
    );
    if let Some(worker) = game.source.worker_id {
        facts.push(format!("H2H worker ID: {worker}"));
    }
    if let Some(instance) = game.source.white_engine_instance_id.as_ref() {
        facts.push(format!("White engine instance: {instance}"));
    }
    if let Some(instance) = game.source.black_engine_instance_id.as_ref() {
        facts.push(format!("Black engine instance: {instance}"));
    }
    let inferences = distinct(
        related
            .iter()
            .flat_map(|finding| finding.inferences.iter().cloned()),
    );
    let mut unknowns = distinct(
        related
            .iter()
            .flat_map(|finding| finding.unknowns.iter().cloned()),
    );
    if unknowns.is_empty() && request.loss_game {
        unknowns.push(
            "the available evidence does not prove one exact engineering root cause".to_string(),
        );
    }
    if turn.is_none_or(|turn| turn.deterministic_search.is_none()) {
        unknowns.push(
            "this root was not selected within the configured deterministic deep-search case budget"
                .to_string(),
        );
    }
    unknowns.sort();
    unknowns.dedup();
    let action_states = turn
        .map(|turn| {
            std::iter::once(turn.before.clone())
                .chain(turn.after_each_action.iter().cloned())
                .collect()
        })
        .unwrap_or_else(|| {
            request
                .action_index
                .and_then(|index| game.states.get(index).cloned())
                .map(|state| vec![state])
                .unwrap_or_else(|| game.states.clone())
        });
    let exact_root_fen = turn
        .map(|turn| turn.before.fen.clone())
        .or_else(|| {
            request
                .action_index
                .and_then(|index| game.states.get(index).map(|state| state.fen.clone()))
        })
        .or_else(|| game.states.first().map(|state| state.fen.clone()))
        .unwrap_or_default();
    let action_index = turn
        .map(|turn| turn.action_start)
        .or(request.action_index)
        .unwrap_or(0);
    let live_decisions: Vec<tgf_cli::h2h_trace::H2hDecisionTraceV2> = turn
        .map(|turn| {
            game.source
                .decisions
                .iter()
                .filter(|decision| {
                    turn.action_start <= decision.action_index
                        && decision.action_index < turn.action_end
                })
                .cloned()
                .collect()
        })
        .unwrap_or_else(|| {
            game.source
                .decisions
                .iter()
                .filter(|decision| decision.action_index == action_index)
                .cloned()
                .collect()
        });
    let chronology = live_decisions
        .first()
        .map(|decision| {
            instance_chronology(
                games,
                &decision.engine_instance_id,
                decision.instance_search_ordinal,
            )
        })
        .unwrap_or_default();
    let mut engine_fingerprints = run
        .manifest
        .as_ref()
        .map(engine_fingerprints)
        .unwrap_or_default();
    if let Some(path) = context.reference_engine {
        engine_fingerprints.push(format!(
            "known-good-reference:path={} sha256={}",
            path.display(),
            sha256_file(path).unwrap_or_else(|_| "<unavailable>".to_string())
        ));
    }
    let replay_command = replay_command(
        run,
        context.database_path,
        context.reference_engine,
        context.triage_nodes,
        context.confirm_nodes,
        context.max_search_cases,
    );
    let anomaly_codes = distinct(related.iter().map(|finding| finding.code.clone()));
    let suspected_subsystems = distinct(
        related
            .iter()
            .flat_map(|finding| finding.suspected_subsystems.iter().cloned()),
    );
    let suspected_symbols = distinct(
        related
            .iter()
            .flat_map(|finding| finding.suspected_symbols.iter().cloned()),
    );
    Some(CaseBundle {
        case_schema_version: 1,
        case_id: request.case_id.clone(),
        game_index: request.game_index,
        pair_index: game.source.pair_index,
        title: if request.loss_game {
            format!("Unresolved H2H loss in game {}", request.game_index)
        } else {
            format!("H2H anomaly in game {}", request.game_index)
        },
        facts,
        inferences,
        unknowns,
        full_game: game.source.moves.clone(),
        suspect_prefix: game.source.moves[..action_index.min(game.source.moves.len())].to_vec(),
        exact_root_fen,
        action_states,
        trace_manifest: run.manifest.clone(),
        run_fingerprint: context.profile_fingerprint.to_string(),
        rules_fingerprint: run
            .manifest
            .as_ref()
            .map(|manifest| manifest.rules.sha256.clone())
            .unwrap_or_else(|| "legacy-v1-unknown".to_string()),
        database_identity: context.database_identity.map(str::to_string),
        engine_fingerprints,
        live_decisions,
        database: turn.and_then(|turn| turn.database.clone()),
        deterministic_search: turn
            .and_then(|turn| turn.deterministic_search.clone())
            .unwrap_or_else(|| DeterministicSearchMatrix {
                unresolved_reasons: vec![
                    "deterministic PVS/MTD(f) matrix was not attempted for this root"
                        .to_string(),
                ],
                ..Default::default()
            }),
        process_replay: turn
            .and_then(|turn| turn.process_replay.clone())
            .unwrap_or_else(|| ProcessReplayEvidence {
                status: "not_attempted".to_string(),
                ..Default::default()
            }),
        engine_instance_chronology: chronology,
        anomaly_codes,
        suspected_subsystems,
        suspected_symbols,
        replay_command,
        llm_prompt: "Analyze this evidence bundle. Separate proven facts from hypotheses, do not treat missing DB/search coverage as safety, identify the smallest plausible subsystem fault, and propose a minimal deterministic regression test before suggesting a fix.".to_string(),
    })
}

fn engine_fingerprints(manifest: &H2hTraceManifestV2) -> Vec<String> {
    let mut values = vec![format!(
        "candidate:path={} sha256={} git={}",
        manifest.candidate.path,
        manifest
            .candidate
            .binary_sha256
            .as_deref()
            .unwrap_or("<unknown>"),
        manifest
            .candidate
            .git_revision
            .as_deref()
            .unwrap_or("<unknown>")
    )];
    if let Some(reference) = manifest.reference.as_ref() {
        values.push(format!(
            "reference:path={} sha256={} git={}",
            reference.path,
            reference.binary_sha256.as_deref().unwrap_or("<unknown>"),
            reference.git_revision.as_deref().unwrap_or("<unknown>")
        ));
    }
    values
}

fn replay_command(
    run: &LoadedRun,
    database_path: Option<&Path>,
    reference_engine: Option<&Path>,
    triage_nodes: u64,
    confirm_nodes: u64,
    max_search_cases: usize,
) -> String {
    let manifest = run
        .source_manifest
        .as_ref()
        .map(|path| format!(" --manifest \"{}\"", shell_quote_content(path)))
        .unwrap_or_default();
    let database = database_path
        .map(|path| format!(" --db \"{}\"", shell_quote_content(path)))
        .unwrap_or_default();
    let reference = reference_engine
        .map(|path| format!(" --reference-engine \"{}\"", shell_quote_content(path)))
        .unwrap_or_default();
    format!(
        "tgf mill h2h-analyze --log \"{}\"{} --out-dir \"h2h-replay\"{}{} --triage-nodes {} --confirm-nodes {} --max-search-cases {} --fail-on none",
        shell_quote_content(&run.source_log),
        manifest,
        database,
        reference,
        triage_nodes,
        confirm_nodes,
        max_search_cases
    )
}

fn shell_quote_content(path: &Path) -> String {
    path.display().to_string().replace('"', "\\\"")
}

fn case_key(game_index: usize, action_index: Option<usize>, codes: &[String]) -> String {
    let identity = format!(
        "{game_index}\0{}\0{}",
        action_index.unwrap_or(usize::MAX),
        codes.join("\0")
    );
    let hash = sha256_bytes(b"sanmill.h2h.case-id.v1\0", identity.as_bytes());
    format!("case-{}", &hash[..16])
}

fn distinct(values: impl IntoIterator<Item = String>) -> Vec<String> {
    values
        .into_iter()
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect()
}

pub(crate) fn write_report(
    out_dir: &Path,
    summary: &AnalysisSummary,
    artifacts: &PreparedArtifacts,
) -> Result<(), AnalyzerError> {
    let cases_dir = out_dir.join("cases");
    if cases_dir.exists() {
        std::fs::remove_dir_all(&cases_dir).map_err(|error| {
            AnalyzerError::incomplete(
                "report_write_error",
                format!("failed to replace {}: {error}", cases_dir.display()),
            )
        })?;
    }
    std::fs::create_dir_all(&cases_dir).map_err(|error| {
        AnalyzerError::incomplete(
            "report_write_error",
            format!("failed to create {}: {error}", out_dir.display()),
        )
    })?;
    write_json(out_dir.join("summary.json"), summary)?;
    write_jsonl(out_dir.join("findings.jsonl"), &artifacts.findings)?;
    write_jsonl(out_dir.join("losses.jsonl"), &artifacts.losses)?;
    write_json(out_dir.join("clusters.json"), &artifacts.clusters)?;
    write_text(
        out_dir.join("report.md"),
        &render_report(summary, artifacts),
    )?;
    for case in &artifacts.cases {
        write_json(
            out_dir.join("cases").join(format!("{}.json", case.case_id)),
            case,
        )?;
        write_text(
            out_dir.join("cases").join(format!("{}.md", case.case_id)),
            &render_case(case),
        )?;
    }
    write_checksums(out_dir)
}

fn write_json(path: PathBuf, value: &impl serde::Serialize) -> Result<(), AnalyzerError> {
    let file = std::fs::File::create(&path).map_err(|error| {
        AnalyzerError::incomplete(
            "report_write_error",
            format!("failed to create {}: {error}", path.display()),
        )
    })?;
    serde_json::to_writer_pretty(file, value).map_err(|error| {
        AnalyzerError::incomplete(
            "report_write_error",
            format!("failed to write {}: {error}", path.display()),
        )
    })
}

fn write_jsonl<T: serde::Serialize>(path: PathBuf, values: &[T]) -> Result<(), AnalyzerError> {
    let file = std::fs::File::create(&path).map_err(|error| {
        AnalyzerError::incomplete(
            "report_write_error",
            format!("failed to create {}: {error}", path.display()),
        )
    })?;
    let mut writer = std::io::BufWriter::new(file);
    for value in values {
        serde_json::to_writer(&mut writer, value).map_err(|error| {
            AnalyzerError::incomplete(
                "report_write_error",
                format!("failed to serialize {}: {error}", path.display()),
            )
        })?;
        writeln!(writer).map_err(|error| {
            AnalyzerError::incomplete(
                "report_write_error",
                format!("failed to write {}: {error}", path.display()),
            )
        })?;
    }
    Ok(())
}

fn write_text(path: PathBuf, text: &str) -> Result<(), AnalyzerError> {
    std::fs::write(&path, text).map_err(|error| {
        AnalyzerError::incomplete(
            "report_write_error",
            format!("failed to write {}: {error}", path.display()),
        )
    })
}

fn render_report(summary: &AnalysisSummary, artifacts: &PreparedArtifacts) -> String {
    format!(
        "# Sanmill H2H Forensic Analysis\n\n\
         Run: `{}`\n\n\
         - Games: {}\n\
         - Pairs: {}\n\
         - Hard engine anomalies: {}\n\
         - Exact DB move errors: {}\n\
         - Probable engine anomalies: {}\n\
         - Unresolved findings: {}\n\
         - Unresolved losses: {}\n\
         - DB coverage: {}/{} logical roots\n\
         - Deterministic search coverage: {}/{} cases\n\
         - Gate: {} ({})\n\
         - LLM evidence bundles: {}\n\n\
         ## Evidence policy\n\n\
         `move_error` is an exact WDL drop and is not automatically an engineering defect. \
         `engine_anomaly` requires a rules/search contract failure, reproducible process-state \
         dependence, or stable high-budget disagreement. Missing evidence remains `unresolved`.\n\n\
         ## Findings\n\n{}\n",
        summary.run_id,
        summary.analyzed_games,
        summary.analyzed_pairs,
        summary.hard_anomaly_count,
        summary.exact_move_error_count,
        summary.probable_anomaly_count,
        summary.unresolved_count,
        summary.unresolved_loss_count,
        summary.db_covered_roots,
        summary.db_roots,
        summary.search_completed_cases,
        summary.search_cases,
        if summary.gate.passed { "pass" } else { "fail" },
        summary.gate.mode,
        artifacts.cases.len(),
        artifacts
            .findings
            .iter()
            .map(|finding| format!(
                "- `{}` [{} / {:?}] game {} action {:?}: {}",
                finding.code,
                serde_json::to_string(&finding.evidence)
                    .unwrap_or_else(|_| "\"unknown\"".to_string())
                    .trim_matches('"'),
                finding.classification,
                finding.game_index,
                finding.action_index,
                finding.message
            ))
            .collect::<Vec<_>>()
            .join("\n")
    )
}

fn render_case(case: &CaseBundle) -> String {
    let pretty = serde_json::to_string_pretty(case)
        .expect("serializing an already-built case bundle must succeed");
    format!(
        "# {}\n\n\
         Case ID: `{}`  \n\
         Game / pair: `{}` / `{}`\n\n\
         ## Proven facts\n\n{}\n\n\
         ## Inferences\n\n{}\n\n\
         ## Unknowns\n\n{}\n\n\
         ## Exact root\n\n\
         ```text\n{}\n```\n\n\
         Full atomic game:\n\n\
         ```text\n{}\n```\n\n\
         ## One-command reproduction\n\n\
         ```text\n{}\n```\n\n\
         ## Complete machine-readable evidence\n\n\
         ```json\n{}\n```\n\n\
         ## Prompt for an LLM\n\n{}\n",
        case.title,
        case.case_id,
        case.game_index,
        case.pair_index,
        markdown_list(&case.facts),
        markdown_list(&case.inferences),
        markdown_list(&case.unknowns),
        case.exact_root_fen,
        case.full_game.join(" "),
        case.replay_command,
        pretty,
        case.llm_prompt
    )
}

fn markdown_list(values: &[String]) -> String {
    if values.is_empty() {
        "- None recorded.".to_string()
    } else {
        values
            .iter()
            .map(|value| format!("- {value}"))
            .collect::<Vec<_>>()
            .join("\n")
    }
}

fn write_checksums(out_dir: &Path) -> Result<(), AnalyzerError> {
    let mut files = [
        "summary.json",
        "findings.jsonl",
        "losses.jsonl",
        "clusters.json",
        "report.md",
    ]
    .into_iter()
    .map(PathBuf::from)
    .collect::<Vec<_>>();
    collect_files(out_dir, &out_dir.join("cases"), &mut files)?;
    files.sort();
    let mut lines = Vec::with_capacity(files.len());
    for relative in files {
        let hash = sha256_file(&out_dir.join(&relative)).map_err(|error| {
            AnalyzerError::incomplete(
                "checksum_error",
                format!("failed to hash {}: {error}", relative.display()),
            )
        })?;
        lines.push(format!(
            "{hash}  {}",
            relative.to_string_lossy().replace('\\', "/")
        ));
    }
    write_text(out_dir.join("SHA256SUMS"), &(lines.join("\n") + "\n"))
}

fn collect_files(
    root: &Path,
    directory: &Path,
    out: &mut Vec<PathBuf>,
) -> Result<(), AnalyzerError> {
    for entry in std::fs::read_dir(directory).map_err(|error| {
        AnalyzerError::incomplete(
            "checksum_error",
            format!("failed to scan {}: {error}", directory.display()),
        )
    })? {
        let entry = entry.map_err(|error| {
            AnalyzerError::incomplete("checksum_error", format!("directory entry error: {error}"))
        })?;
        let path = entry.path();
        if path.is_dir() {
            collect_files(root, &path, out)?;
        } else if path.is_file() {
            out.push(path.strip_prefix(root).unwrap_or(&path).to_path_buf());
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn case_json_contains_llm_critical_fields() {
        let case = CaseBundle {
            case_schema_version: 1,
            case_id: "case-test".to_string(),
            game_index: 1,
            pair_index: 0,
            title: "test".to_string(),
            facts: vec!["fact".to_string()],
            inferences: vec!["inference".to_string()],
            unknowns: vec!["unknown".to_string()],
            full_game: vec!["a1".to_string()],
            suspect_prefix: Vec::new(),
            exact_root_fen: "fen".to_string(),
            action_states: Vec::new(),
            trace_manifest: None,
            run_fingerprint: "run".to_string(),
            rules_fingerprint: "rules".to_string(),
            database_identity: None,
            engine_fingerprints: vec!["engine".to_string()],
            live_decisions: Vec::new(),
            database: None,
            deterministic_search:
                crate::mill_h2h_analyze::model::DeterministicSearchMatrix::default(),
            process_replay: ProcessReplayEvidence {
                status: "not_attempted".to_string(),
                ..Default::default()
            },
            engine_instance_chronology: Vec::new(),
            anomaly_codes: vec!["unresolved".to_string()],
            suspected_subsystems: Vec::new(),
            suspected_symbols: Vec::new(),
            replay_command: "tgf mill h2h-analyze --log trace.jsonl".to_string(),
            llm_prompt: "separate facts from guesses".to_string(),
        };
        let value = serde_json::to_value(&case).unwrap();
        for field in [
            "facts",
            "inferences",
            "unknowns",
            "full_game",
            "exact_root_fen",
            "trace_manifest",
            "live_decisions",
            "deterministic_search",
            "process_replay",
            "replay_command",
            "llm_prompt",
        ] {
            assert!(value.get(field).is_some(), "missing {field}");
        }
        assert!(
            value["replay_command"]
                .as_str()
                .unwrap()
                .starts_with("tgf mill h2h-analyze")
        );
    }

    #[test]
    fn case_id_keeps_histories_separate_by_game_and_action() {
        let first = case_key(1, Some(4), &["x".to_string()]);
        let different_history = case_key(2, Some(4), &["x".to_string()]);
        let different_action = case_key(1, Some(5), &["x".to_string()]);
        assert_ne!(first, different_history);
        assert_ne!(first, different_action);
    }
}
