// SPDX-License-Identifier: AGPL-3.0-or-later

use std::collections::BTreeMap;
use std::env;
use std::io::{BufRead, BufReader, Write};
use std::path::Path;
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::mpsc::{self, Receiver};
use std::thread;
use std::time::{Duration, Instant};

use tgf_cli::h2h_trace::{
    H2hActor, H2hDecisionTraceV2, H2hEngineIdentity, H2hTraceManifestV2, sha256_file,
};

use super::model::{EvidenceLevel, FindingClass, ProcessReplayEvidence, ReplayedGame};
use super::replay::finding;

const UCI_HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(30);
const SEARCH_TIMEOUT: Duration = Duration::from_secs(300);

struct UciProcess {
    child: Child,
    stdin: ChildStdin,
    output: Receiver<String>,
}

#[derive(Clone, Debug)]
struct ReplaySearchResult {
    bestmove: Option<String>,
}

impl UciProcess {
    fn spawn(identity: &H2hEngineIdentity) -> Result<Self, String> {
        let engine_path = Path::new(&identity.path);
        if !engine_path.is_file() {
            return Err(format!(
                "engine executable does not exist: {}",
                identity.path
            ));
        }
        if let Some(expected) = identity.binary_sha256.as_deref() {
            let actual = sha256_file(engine_path).map_err(|error| {
                format!(
                    "failed to fingerprint replay engine {}: {error}",
                    identity.path
                )
            })?;
            if !actual.eq_ignore_ascii_case(expected) {
                return Err(format!(
                    "replay engine SHA-256 differs from manifest: expected {expected}, got {actual}"
                ));
            }
        }
        let mut command = Command::new(&identity.path);
        command
            .args(&identity.arguments)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null());
        for (name, _) in env::vars().filter(|(name, _)| name.starts_with("TGF_")) {
            command.env_remove(name);
        }
        for value in &identity.environment {
            if let Some(replay_value) = value.replay_value.as_ref() {
                command.env(&value.name, replay_value);
            }
        }
        let mut child = command
            .spawn()
            .map_err(|error| format!("failed to spawn {}: {error}", identity.path))?;
        let stdin = child
            .stdin
            .take()
            .ok_or_else(|| "engine stdin is unavailable".to_string())?;
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| "engine stdout is unavailable".to_string())?;
        let (tx, output) = mpsc::channel();
        thread::spawn(move || {
            let reader = BufReader::new(stdout);
            for line in reader.lines() {
                let Ok(line) = line else {
                    break;
                };
                if tx.send(line).is_err() {
                    break;
                }
            }
        });
        let mut process = Self {
            child,
            stdin,
            output,
        };
        process.cmd("uci")?;
        process.wait_for("uciok", UCI_HANDSHAKE_TIMEOUT)?;
        for option in &identity.setoptions {
            process.cmd(&format!(
                "setoption name {} value {}",
                option.name, option.value
            ))?;
        }
        process.cmd("isready")?;
        process.wait_for("readyok", UCI_HANDSHAKE_TIMEOUT)?;
        Ok(process)
    }

    fn cmd(&mut self, command: &str) -> Result<(), String> {
        writeln!(self.stdin, "{command}")
            .and_then(|_| self.stdin.flush())
            .map_err(|error| format!("failed to write `{command}` to engine: {error}"))
    }

    fn wait_for(&self, token: &str, timeout: Duration) -> Result<Vec<String>, String> {
        let started = Instant::now();
        let mut lines = Vec::new();
        loop {
            let remaining = timeout
                .checked_sub(started.elapsed())
                .ok_or_else(|| format!("timed out waiting for `{token}`"))?;
            match self.output.recv_timeout(remaining) {
                Ok(line) => {
                    let matched = line.contains(token);
                    lines.push(line);
                    if matched {
                        return Ok(lines);
                    }
                }
                Err(mpsc::RecvTimeoutError::Timeout) => {
                    return Err(format!("timed out waiting for `{token}`"));
                }
                Err(mpsc::RecvTimeoutError::Disconnected) => {
                    return Err(format!("engine exited before `{token}`"));
                }
            }
        }
    }

    fn new_game(&mut self, seed: Option<&str>) -> Result<(), String> {
        self.cmd("ucinewgame")?;
        if let Some(seed) = seed {
            self.cmd(&format!("setoption name SearchShuffleSeed value {seed}"))?;
        }
        Ok(())
    }

    fn search(&mut self, moves: &[String], go: &str) -> Result<ReplaySearchResult, String> {
        if moves.is_empty() {
            self.cmd("position startpos")?;
        } else {
            self.cmd(&format!("position startpos moves {}", moves.join(" ")))?;
        }
        self.cmd(go)?;
        let lines = self.wait_for("bestmove", SEARCH_TIMEOUT)?;
        let bestmove = lines.iter().rev().find_map(|line| parse_bestmove(line));
        if bestmove.is_none() {
            return Err("engine ended the search without a usable bestmove".to_string());
        }
        Ok(ReplaySearchResult { bestmove })
    }
}

impl Drop for UciProcess {
    fn drop(&mut self) {
        let _ = writeln!(self.stdin, "quit");
        let _ = self.stdin.flush();
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

pub(crate) fn run_process_replays(
    games: &mut [ReplayedGame],
    manifest: &H2hTraceManifestV2,
    reference_engine: Option<&Path>,
    rules_sha256: &str,
) {
    let targets = games
        .iter()
        .enumerate()
        .flat_map(|(game_slot, game)| {
            game.logical_turns
                .iter()
                .enumerate()
                .filter(|(_, turn)| turn.deterministic_search.is_some())
                .map(move |(turn_slot, _)| (game_slot, turn_slot))
        })
        .collect::<Vec<_>>();
    let sequence_results = replay_selected_sequences(games, manifest, &targets);

    for (game_slot, turn_slot) in targets {
        let action_index = games[game_slot].logical_turns[turn_slot].action_start;
        let action_end = games[game_slot].logical_turns[turn_slot].action_end;
        let logical_ply = games[game_slot].logical_turns[turn_slot].logical_ply_index;
        let actor = games[game_slot].logical_turns[turn_slot].actor;
        let Some(live) = games[game_slot]
            .source
            .decisions
            .iter()
            .find(|decision| decision.action_index == action_index)
            .cloned()
        else {
            games[game_slot].logical_turns[turn_slot].process_replay =
                Some(ProcessReplayEvidence {
                    status: "unresolved_missing_live_decision".to_string(),
                    ..Default::default()
                });
            continue;
        };
        let identity = if live.engine_role == "reference" {
            manifest.reference.as_ref().unwrap_or(&manifest.candidate)
        } else {
            &manifest.candidate
        };
        let live_turn = logical_turn_bestmove(
            &games[game_slot],
            &live.engine_instance_id,
            action_index,
            action_end,
        );
        let fresh = replay_fresh(&games[game_slot], &live, action_end, identity);
        let sequence = sequence_results
            .get(&(
                live.engine_instance_id.clone(),
                live.instance_search_ordinal,
            ))
            .cloned()
            .unwrap_or_else(|| {
                Err("target search ordinal was not present in grouped sequence replay".to_string())
            });
        let reference = reference_engine.map(|path| {
            let mut identity = manifest.candidate.clone();
            identity.role = "known_good_reference".to_string();
            identity.path = path.display().to_string();
            identity.binary_sha256 = sha256_file(path).ok();
            identity.git_revision = None;
            if path
                .file_stem()
                .and_then(|value| value.to_str())
                .is_some_and(|name| name.eq_ignore_ascii_case("tgf"))
            {
                identity.arguments = vec!["uci".to_string()];
            }
            replay_fresh(&games[game_slot], &live, action_end, &identity)
        });
        let reference_bestmove = reference
            .as_ref()
            .and_then(|result| result.as_ref().ok())
            .and_then(|result| result.bestmove.clone());
        let reference_failed = reference.as_ref().is_some_and(Result::is_err);
        let mut evidence = if fresh.is_err() || sequence.is_err() || reference_failed {
            ProcessReplayEvidence {
                status: "replay_incomplete".to_string(),
                live_bestmove: live_turn.clone(),
                fresh_bestmove: fresh
                    .as_ref()
                    .ok()
                    .and_then(|result| result.bestmove.clone()),
                sequence_bestmove: sequence
                    .as_ref()
                    .ok()
                    .and_then(|result| result.bestmove.clone()),
                reference_bestmove,
                notes: Vec::new(),
            }
        } else {
            classify_process_replay(
                live_turn,
                fresh
                    .as_ref()
                    .ok()
                    .and_then(|result| result.bestmove.clone()),
                sequence
                    .as_ref()
                    .ok()
                    .and_then(|result| result.bestmove.clone()),
                reference_bestmove,
            )
        };
        if let Err(error) = fresh {
            evidence.notes.push(format!("fresh replay failed: {error}"));
        }
        if let Err(error) = sequence {
            evidence
                .notes
                .push(format!("sequence replay failed: {error}"));
        }
        if let Some(Err(error)) = reference {
            evidence
                .notes
                .push(format!("known-good reference replay failed: {error}"));
        }
        if identity
            .environment
            .iter()
            .any(|value| value.replay_value.is_none())
        {
            evidence.notes.push(
                "one or more engine environment values were hash-only and could not be replayed"
                    .to_string(),
            );
        }

        let finding_spec = match evidence.status.as_str() {
            "process_state_dependence" => Some((
                EvidenceLevel::Probable,
                FindingClass::EngineAnomaly,
                "process_state_dependence",
                "sequence replay reproduces the live move while fresh replay does not",
            )),
            "nondeterminism_or_config_mismatch" => Some((
                EvidenceLevel::Unresolved,
                FindingClass::Unresolved,
                "nondeterminism_or_config_mismatch",
                "neither fresh nor sequence replay reproduces the live move",
            )),
            "replay_disagreement" => Some((
                EvidenceLevel::Unresolved,
                FindingClass::Unresolved,
                "sequence_replay_disagreement",
                "fresh and sequence replay disagree without proving process-state dependence",
            )),
            "replay_incomplete" => Some((
                EvidenceLevel::Unresolved,
                FindingClass::Unresolved,
                "process_replay_incomplete",
                "fresh or sequence replay failed, so deterministic reproduction is unresolved",
            )),
            "unresolved_missing_live_bestmove" => Some((
                EvidenceLevel::Unresolved,
                FindingClass::Unresolved,
                "process_replay_missing_live_bestmove",
                "the live search did not retain a usable bestmove for comparison",
            )),
            _ => None,
        };
        if let Some((level, class, code, message)) = finding_spec {
            let turn = &games[game_slot].logical_turns[turn_slot];
            let mut item = finding(
                &games[game_slot].source,
                Some(action_index),
                Some(logical_ply),
                Some(actor),
                level,
                class,
                code,
                message,
                Some(&turn.before),
                rules_sha256,
                if turn.tokens.len() > 1 {
                    "process_replay_mill_with_removal"
                } else {
                    "process_replay_single_action"
                },
            );
            item.facts.extend(evidence.notes.clone());
            games[game_slot].findings.push(item);
        }
        games[game_slot].logical_turns[turn_slot].process_replay = Some(evidence);
    }
}

fn replay_fresh(
    game: &ReplayedGame,
    target: &H2hDecisionTraceV2,
    action_end: usize,
    identity: &H2hEngineIdentity,
) -> Result<ReplaySearchResult, String> {
    let mut process = UciProcess::spawn(identity)?;
    process.new_game(seed_for(game, target.actor))?;
    replay_logical_turn(
        &mut process,
        game,
        &target.engine_instance_id,
        target.action_index,
        action_end,
    )
}

fn replay_logical_turn(
    process: &mut UciProcess,
    game: &ReplayedGame,
    instance_id: &str,
    action_start: usize,
    action_end: usize,
) -> Result<ReplaySearchResult, String> {
    let mut tokens = Vec::new();
    let mut decisions = game
        .source
        .decisions
        .iter()
        .filter(|decision| {
            decision.engine_instance_id == instance_id
                && action_start <= decision.action_index
                && decision.action_index < action_end
        })
        .collect::<Vec<_>>();
    decisions.sort_by_key(|decision| decision.action_index);
    for decision in decisions {
        let result = process.search(
            &game.source.moves[..decision.action_index],
            &decision.go_command,
        )?;
        let Some(token) = result.bestmove else {
            return Ok(ReplaySearchResult { bestmove: None });
        };
        tokens.push(token);
    }
    if tokens.is_empty() {
        return Err("logical turn has no engine decisions to replay".to_string());
    }
    Ok(ReplaySearchResult {
        bestmove: Some(tokens.join(" ")),
    })
}

fn logical_turn_bestmove(
    game: &ReplayedGame,
    instance_id: &str,
    action_start: usize,
    action_end: usize,
) -> Option<String> {
    let mut decisions = game
        .source
        .decisions
        .iter()
        .filter(|decision| {
            decision.engine_instance_id == instance_id
                && action_start <= decision.action_index
                && decision.action_index < action_end
        })
        .collect::<Vec<_>>();
    decisions.sort_by_key(|decision| decision.action_index);
    if decisions.is_empty() || decisions.iter().any(|decision| decision.bestmove.is_none()) {
        return None;
    }
    Some(
        decisions
            .iter()
            .filter_map(|decision| decision.bestmove.as_deref())
            .collect::<Vec<_>>()
            .join(" "),
    )
}

fn replay_selected_sequences(
    games: &[ReplayedGame],
    manifest: &H2hTraceManifestV2,
    targets: &[(usize, usize)],
) -> BTreeMap<(String, u64), Result<ReplaySearchResult, String>> {
    #[derive(Clone)]
    struct TurnTarget {
        key_ordinal: u64,
        ordinals: Vec<u64>,
    }

    #[derive(Clone)]
    struct Plan {
        identity: H2hEngineIdentity,
        targets: Vec<TurnTarget>,
    }

    let mut plans = BTreeMap::<String, Plan>::new();
    for &(game_slot, turn_slot) in targets {
        let turn = &games[game_slot].logical_turns[turn_slot];
        let action_index = turn.action_start;
        let Some(live) = games[game_slot]
            .source
            .decisions
            .iter()
            .find(|decision| decision.action_index == action_index)
        else {
            continue;
        };
        let identity = if live.engine_role == "reference" {
            manifest.reference.as_ref().unwrap_or(&manifest.candidate)
        } else {
            &manifest.candidate
        };
        let mut ordinals = games[game_slot]
            .source
            .decisions
            .iter()
            .filter(|decision| {
                decision.engine_instance_id == live.engine_instance_id
                    && turn.action_start <= decision.action_index
                    && decision.action_index < turn.action_end
            })
            .map(|decision| decision.instance_search_ordinal)
            .collect::<Vec<_>>();
        ordinals.sort_unstable();
        if ordinals.is_empty() {
            continue;
        }
        let target = TurnTarget {
            key_ordinal: live.instance_search_ordinal,
            ordinals,
        };
        plans
            .entry(live.engine_instance_id.clone())
            .and_modify(|plan| {
                if !plan
                    .targets
                    .iter()
                    .any(|existing| existing.key_ordinal == target.key_ordinal)
                {
                    plan.targets.push(target.clone());
                }
            })
            .or_insert_with(|| Plan {
                identity: identity.clone(),
                targets: vec![target],
            });
    }

    let mut results = BTreeMap::new();
    for (instance_id, plan) in plans {
        let fail_all = |results: &mut BTreeMap<_, _>, message: String| {
            for target in &plan.targets {
                results.insert(
                    (instance_id.clone(), target.key_ordinal),
                    Err(message.clone()),
                );
            }
        };
        let mut process = match UciProcess::spawn(&plan.identity) {
            Ok(process) => process,
            Err(error) => {
                fail_all(&mut results, error);
                continue;
            }
        };
        let max_ordinal = plan
            .targets
            .iter()
            .flat_map(|target| target.ordinals.iter().copied())
            .max()
            .unwrap_or(0);
        let mut chronology = games
            .iter()
            .flat_map(|game| {
                game.source
                    .decisions
                    .iter()
                    .filter(|decision| {
                        decision.engine_instance_id == instance_id
                            && decision.instance_search_ordinal <= max_ordinal
                    })
                    .map(move |decision| (game, decision))
            })
            .collect::<Vec<_>>();
        chronology.sort_by_key(|(_, decision)| decision.instance_search_ordinal);
        let mut active_game = None;
        let mut failure = None;
        let mut atomic_results = BTreeMap::<u64, Option<String>>::new();
        for (game, decision) in chronology {
            if active_game != Some(game.source.game_index) {
                if let Err(error) = process.new_game(seed_for(game, decision.actor)) {
                    failure = Some(error);
                    break;
                }
                active_game = Some(game.source.game_index);
            }
            match process.search(
                &game.source.moves[..decision.action_index],
                &decision.go_command,
            ) {
                Ok(result) => {
                    atomic_results.insert(decision.instance_search_ordinal, result.bestmove);
                }
                Err(error) => {
                    failure = Some(error);
                    break;
                }
            }
        }
        for target in &plan.targets {
            let mut tokens = Vec::new();
            let mut missing_bestmove = false;
            let mut missing_ordinal = false;
            for ordinal in &target.ordinals {
                match atomic_results.get(ordinal) {
                    Some(Some(token)) => tokens.push(token.clone()),
                    Some(None) => {
                        missing_bestmove = true;
                        break;
                    }
                    None => {
                        missing_ordinal = true;
                        break;
                    }
                }
            }
            let result = if missing_ordinal {
                Err(failure.clone().unwrap_or_else(|| {
                    "target logical-turn ordinal was absent from instance chronology".to_string()
                }))
            } else if missing_bestmove {
                Ok(ReplaySearchResult { bestmove: None })
            } else {
                Ok(ReplaySearchResult {
                    bestmove: Some(tokens.join(" ")),
                })
            };
            results.insert((instance_id.clone(), target.key_ordinal), result);
        }
    }
    results
}

fn seed_for(game: &ReplayedGame, actor: H2hActor) -> Option<&str> {
    match actor {
        H2hActor::White => game.source.white_seed.as_deref(),
        H2hActor::Black => game.source.black_seed.as_deref(),
    }
}

fn classify_process_replay(
    live: Option<String>,
    fresh: Option<String>,
    sequence: Option<String>,
    reference: Option<String>,
) -> ProcessReplayEvidence {
    let status = if live.is_none() {
        "unresolved_missing_live_bestmove"
    } else if sequence == live && fresh != live {
        "process_state_dependence"
    } else if sequence == live && fresh == live {
        "reproduced"
    } else if sequence != live && fresh != live {
        "nondeterminism_or_config_mismatch"
    } else {
        "replay_disagreement"
    };
    ProcessReplayEvidence {
        status: status.to_string(),
        live_bestmove: live,
        fresh_bestmove: fresh,
        sequence_bestmove: sequence,
        reference_bestmove: reference,
        notes: Vec::new(),
    }
}

fn parse_bestmove(line: &str) -> Option<String> {
    let tokens = line.split_whitespace().collect::<Vec<_>>();
    let index = tokens.iter().position(|token| *token == "bestmove")?;
    let value = tokens.get(index + 1)?.to_string();
    (!matches!(value.as_str(), "none" | "(none)" | "0000")).then_some(value)
}

pub(crate) fn instance_chronology(
    games: &[ReplayedGame],
    instance_id: &str,
    through_ordinal: u64,
) -> Vec<String> {
    let mut values = games
        .iter()
        .flat_map(|game| {
            game.source
                .decisions
                .iter()
                .filter(|decision| {
                    decision.engine_instance_id == instance_id
                        && decision.instance_search_ordinal <= through_ordinal
                })
                .map(move |decision| {
                    (
                        decision.instance_search_ordinal,
                        format!(
                            "game={} action={} logical={} ordinal={} actor={:?} bestmove={}",
                            game.source.game_index,
                            decision.action_index,
                            decision.logical_ply_index,
                            decision.instance_search_ordinal,
                            decision.actor,
                            decision.bestmove.as_deref().unwrap_or("<none>")
                        ),
                    )
                })
        })
        .collect::<Vec<_>>();
    values.sort_by_key(|(ordinal, _)| *ordinal);
    values.into_iter().map(|(_, value)| value).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fresh_sequence_difference_identifies_process_state_dependence() {
        let evidence = classify_process_replay(
            Some("a1".to_string()),
            Some("d1".to_string()),
            Some("a1".to_string()),
            None,
        );
        assert_eq!(evidence.status, "process_state_dependence");
    }

    #[test]
    fn failure_to_reproduce_stays_unresolved() {
        let evidence = classify_process_replay(
            Some("a1".to_string()),
            Some("d1".to_string()),
            Some("g1".to_string()),
            None,
        );
        assert_eq!(evidence.status, "nondeterminism_or_config_mismatch");
    }

    #[test]
    fn process_replay_compares_the_mandatory_removal_too() {
        let evidence = classify_process_replay(
            Some("a4-d7 xd1".to_string()),
            Some("a4-d7 xg1".to_string()),
            Some("a4-d7 xd1".to_string()),
            None,
        );
        assert_eq!(evidence.status, "process_state_dependence");
        assert_ne!(evidence.live_bestmove, evidence.fresh_bestmove);
    }
}
