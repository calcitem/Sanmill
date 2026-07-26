// SPDX-License-Identifier: AGPL-3.0-or-later

use std::collections::{BTreeMap, BTreeSet};

use sha2::{Digest, Sha256};
use tgf_cli::h2h_trace::{
    H2H_RAW_UCI_LIMIT_BYTES, H2hActor, H2hGameEndKind, H2hTraceManifestV2, sha256_bytes,
};
use tgf_core::{
    Action, ActionList, Game, GameRules, GameStateSnapshot, OutcomeKind, SearchActionList,
    Workbench,
};
use tgf_mill::{
    MillActionKind, MillGame, MillPlyCount, MillRules, MillUciCodec, MillVariantOptions,
    OPENING_BOOK_SYMMETRY_COUNT, logical_turn_completed, transform_opening_book_node,
};

use crate::mill_data_query::summarize_position;

use super::model::{
    EvidenceLevel, Finding, FindingClass, LoadedRun, LogicalTurnRecord, NormalizedGame,
    ReplayedGame, StateEvidence,
};

struct PendingTurn {
    actor: H2hActor,
    logical_ply_index: u32,
    action_start: usize,
    root: GameStateSnapshot,
    root_history: Vec<GameStateSnapshot>,
    before: StateEvidence,
    actions: Vec<Action>,
    tokens: Vec<String>,
    after_each_action: Vec<StateEvidence>,
}

pub(crate) fn replay_run(
    run: &LoadedRun,
    options: &MillVariantOptions,
    rules_sha256: &str,
) -> Vec<ReplayedGame> {
    let rules = MillRules::new(options.clone());
    let mut games = run
        .games
        .iter()
        .map(|game| {
            let mut replay = replay_game(game, options, &rules, rules_sha256);
            if let Some(manifest) = run.manifest.as_ref() {
                let contract = trace_manifest_contract_findings(
                    &replay.source,
                    &replay.states,
                    manifest,
                    rules_sha256,
                );
                replay.findings.extend(contract);
            }
            replay
        })
        .collect::<Vec<_>>();
    validate_instance_ordinals(&mut games, rules_sha256);
    games
}

fn trace_manifest_contract_findings(
    game: &NormalizedGame,
    states: &[StateEvidence],
    manifest: &H2hTraceManifestV2,
    rules_sha256: &str,
) -> Vec<Finding> {
    let mut findings = Vec::new();
    let white_instance = game.white_engine_instance_id.as_deref().unwrap_or("");
    let black_instance = game.black_engine_instance_id.as_deref().unwrap_or("");
    if white_instance.is_empty() || black_instance.is_empty() {
        findings.push(finding(
            game,
            None,
            None,
            None,
            EvidenceLevel::Hard,
            FindingClass::EngineAnomaly,
            "missing_engine_instance_id",
            "Trace v2 requires non-empty White and Black engine instance IDs",
            states.first(),
            rules_sha256,
            "trace_protocol",
        ));
    } else if white_instance == black_instance {
        findings.push(finding(
            game,
            None,
            None,
            None,
            EvidenceLevel::Hard,
            FindingClass::EngineAnomaly,
            "duplicate_side_engine_instance",
            "White and Black claim the same engine instance ID",
            states.first(),
            rules_sha256,
            "trace_protocol",
        ));
    }
    if manifest.reproducibility.fixed_search_seed
        && (game.white_seed.is_none() || game.black_seed.is_none())
    {
        findings.push(finding(
            game,
            None,
            None,
            None,
            EvidenceLevel::Hard,
            FindingClass::EngineAnomaly,
            "missing_fixed_search_seed",
            "manifest claims fixed search seeds but a game omits a board-side seed",
            states.first(),
            rules_sha256,
            "trace_reproducibility",
        ));
    }

    for decision in &game.decisions {
        let state = states.get(decision.action_index).or_else(|| states.last());
        let expected_instance = match decision.actor {
            H2hActor::White => white_instance,
            H2hActor::Black => black_instance,
        };
        if decision.engine_instance_id != expected_instance {
            findings.push(finding(
                game,
                Some(decision.action_index),
                Some(decision.logical_ply_index),
                Some(decision.actor),
                EvidenceLevel::Hard,
                FindingClass::EngineAnomaly,
                "decision_engine_instance_mismatch",
                "decision engine instance does not match the actor's board-side instance",
                state,
                rules_sha256,
                "trace_protocol",
            ));
        }
        let expected_role = match game.current_white {
            Some(candidate_is_white)
                if (decision.actor == H2hActor::White) == candidate_is_white =>
            {
                "candidate"
            }
            Some(_) => "reference",
            None => "candidate",
        };
        if decision.engine_role != expected_role {
            findings.push(finding(
                game,
                Some(decision.action_index),
                Some(decision.logical_ply_index),
                Some(decision.actor),
                EvidenceLevel::Hard,
                FindingClass::EngineAnomaly,
                "decision_engine_role_mismatch",
                "decision engine role contradicts the match mode and board colour",
                state,
                rules_sha256,
                "trace_protocol",
            ));
        }
        let identity = if expected_role == "reference" {
            manifest.reference.as_ref()
        } else {
            Some(&manifest.candidate)
        };
        if let Some(identity) = identity
            && decision.go_command != identity.go_command
        {
            findings.push(finding(
                game,
                Some(decision.action_index),
                Some(decision.logical_ply_index),
                Some(decision.actor),
                EvidenceLevel::Hard,
                FindingClass::EngineAnomaly,
                "decision_go_command_mismatch",
                "decision go command differs from the engine manifest",
                state,
                rules_sha256,
                "trace_reproducibility",
            ));
        }
        if decision.instance_search_ordinal == 0 {
            findings.push(finding(
                game,
                Some(decision.action_index),
                Some(decision.logical_ply_index),
                Some(decision.actor),
                EvidenceLevel::Hard,
                FindingClass::EngineAnomaly,
                "zero_engine_search_ordinal",
                "engine instance search ordinals are one-based and cannot be zero",
                state,
                rules_sha256,
                "trace_protocol",
            ));
        }
        if decision.bestmove.is_some() && decision.protocol_error.is_some() {
            findings.push(finding(
                game,
                Some(decision.action_index),
                Some(decision.logical_ply_index),
                Some(decision.actor),
                EvidenceLevel::Hard,
                FindingClass::EngineAnomaly,
                "decision_protocol_status_contradiction",
                "a decision contains both a usable bestmove and a protocol error",
                state,
                rules_sha256,
                "trace_protocol",
            ));
        }
    }
    findings
}

fn replay_game(
    game: &NormalizedGame,
    options: &MillVariantOptions,
    rules: &MillRules,
    rules_sha256: &str,
) -> ReplayedGame {
    let mut snapshot = rules.initial_state(&[]);
    let mut history = Vec::<GameStateSnapshot>::new();
    let mut applied_tokens = Vec::<String>::new();
    let mut counts = MillPlyCount::default();
    let mut states = Vec::with_capacity(game.moves.len() + 1);
    let mut logical_turns = Vec::new();
    let mut findings = Vec::new();
    let mut pending_turn: Option<PendingTurn> = None;

    let initial = state_evidence(
        rules,
        options,
        &snapshot,
        &history,
        &applied_tokens,
        counts,
        0,
    );
    findings.extend(contract_findings(
        game,
        options,
        rules,
        &snapshot,
        &history,
        &initial,
        rules_sha256,
    ));
    states.push(initial);

    let decisions_by_action = game
        .decisions
        .iter()
        .map(|decision| (decision.action_index, decision))
        .collect::<BTreeMap<_, _>>();
    if decisions_by_action.len() != game.decisions.len() {
        findings.push(finding(
            game,
            None,
            None,
            None,
            EvidenceLevel::Hard,
            FindingClass::EngineAnomaly,
            "duplicate_decision_action_index",
            "two engine decisions claim the same action index",
            None,
            rules_sha256,
            "trace_protocol",
        ));
    }

    for (action_index, token) in game.moves.iter().enumerate() {
        let before = snapshot;
        let before_evidence = states
            .last()
            .cloned()
            .expect("the initial replay state is always present");
        let actor = H2hActor::from_side(before.side_to_move);
        if pending_turn.is_none()
            && let Some(actor) = actor
        {
            pending_turn = Some(PendingTurn {
                actor,
                logical_ply_index: counts.logical_plies,
                action_start: action_index,
                root: before,
                root_history: history.clone(),
                before: before_evidence.clone(),
                actions: Vec::new(),
                tokens: Vec::new(),
                after_each_action: Vec::new(),
            });
        }

        if action_index >= game.opening_moves.len() {
            match decisions_by_action.get(&action_index) {
                Some(decision) => {
                    if Some(decision.actor) != actor {
                        findings.push(finding(
                            game,
                            Some(action_index),
                            Some(counts.logical_plies),
                            actor,
                            EvidenceLevel::Hard,
                            FindingClass::EngineAnomaly,
                            "decision_actor_mismatch",
                            "decision actor does not match the replayed side to move",
                            Some(&before_evidence),
                            rules_sha256,
                            "trace_protocol",
                        ));
                    }
                    if decision.logical_ply_index != counts.logical_plies {
                        findings.push(finding(
                            game,
                            Some(action_index),
                            Some(counts.logical_plies),
                            actor,
                            EvidenceLevel::Hard,
                            FindingClass::EngineAnomaly,
                            "decision_logical_ply_mismatch",
                            "decision logical-ply index disagrees with strict replay",
                            Some(&before_evidence),
                            rules_sha256,
                            "trace_protocol",
                        ));
                    }
                    if decision.bestmove.as_deref() != Some(token.as_str()) {
                        findings.push(finding(
                            game,
                            Some(action_index),
                            Some(counts.logical_plies),
                            actor,
                            EvidenceLevel::Hard,
                            FindingClass::EngineAnomaly,
                            "decision_bestmove_mismatch",
                            "logged bestmove differs from the atomic action applied by the referee",
                            Some(&before_evidence),
                            rules_sha256,
                            "trace_protocol",
                        ));
                    }
                }
                None if game.schema_version >= 2 => findings.push(finding(
                    game,
                    Some(action_index),
                    Some(counts.logical_plies),
                    actor,
                    EvidenceLevel::Hard,
                    FindingClass::EngineAnomaly,
                    "missing_decision_trace",
                    "a non-opening atomic action has no engine decision trace",
                    Some(&before_evidence),
                    rules_sha256,
                    "trace_protocol",
                )),
                None => {}
            }
        }

        let mut legal = ActionList::<256>::new();
        rules.legal_actions(&before, &mut legal);
        let decoded = MillUciCodec::decode_action(&before, token);
        let Some(action) = decoded else {
            findings.push(finding(
                game,
                Some(action_index),
                Some(counts.logical_plies),
                actor,
                EvidenceLevel::Hard,
                FindingClass::EngineAnomaly,
                "undecodable_action",
                &format!("atomic action `{token}` cannot be decoded"),
                Some(&before_evidence),
                rules_sha256,
                "rules_replay",
            ));
            break;
        };
        if !legal.as_slice().contains(&action) {
            findings.push(finding(
                game,
                Some(action_index),
                Some(counts.logical_plies),
                actor,
                EvidenceLevel::Hard,
                FindingClass::EngineAnomaly,
                "illegal_action",
                &format!("atomic action `{token}` is not legal at the replay root"),
                Some(&before_evidence),
                rules_sha256,
                "rules_replay",
            ));
            break;
        }
        let canonical = MillUciCodec::encode_action(action);
        if canonical != *token {
            findings.push(finding(
                game,
                Some(action_index),
                Some(counts.logical_plies),
                actor,
                EvidenceLevel::Hard,
                FindingClass::EngineAnomaly,
                "noncanonical_action_token",
                &format!("action `{token}` has canonical spelling `{canonical}`"),
                Some(&before_evidence),
                rules_sha256,
                "rules_replay",
            ));
        }

        let next = rules.apply_with_history(&before, action, &history);
        findings.extend(transition_contract_findings(
            game,
            options,
            &before,
            &next,
            &history,
            action,
            action_index,
            counts.logical_plies,
            &before_evidence,
            rules_sha256,
        ));
        if let Err(error) = counts.record(rules, &before, &next) {
            findings.push(finding(
                game,
                Some(action_index),
                Some(counts.logical_plies),
                actor,
                EvidenceLevel::Hard,
                FindingClass::EngineAnomaly,
                "logical_ply_counter_error",
                &error.to_string(),
                Some(&before_evidence),
                rules_sha256,
                "logical_turn",
            ));
        }
        history.push(before);
        applied_tokens.push(token.clone());
        snapshot = next;
        let after = state_evidence(
            rules,
            options,
            &snapshot,
            &history,
            &applied_tokens,
            counts,
            action_index + 1,
        );
        findings.extend(contract_findings(
            game,
            options,
            rules,
            &snapshot,
            &history,
            &after,
            rules_sha256,
        ));
        states.push(after.clone());

        if let Some(turn) = pending_turn.as_mut() {
            turn.actions.push(action);
            turn.tokens.push(token.clone());
            turn.after_each_action.push(after);
        }
        if logical_turn_completed(rules, &before, &snapshot)
            && let Some(turn) = pending_turn.take()
        {
            logical_turns.push(LogicalTurnRecord {
                logical_ply_index: turn.logical_ply_index,
                actor: turn.actor,
                action_start: turn.action_start,
                action_end: action_index + 1,
                tokens: turn.tokens,
                actions: turn.actions,
                root: turn.root,
                final_snapshot: snapshot,
                root_history: turn.root_history,
                before: turn.before,
                after_each_action: turn.after_each_action,
                database: None,
                deterministic_search: None,
                process_replay: None,
            });
        }
    }

    for decision in &game.decisions {
        let decision_state = states.get(decision.action_index).or_else(|| states.last());
        if decision.raw_uci_output.len() > H2H_RAW_UCI_LIMIT_BYTES {
            findings.push(finding(
                game,
                Some(decision.action_index),
                Some(decision.logical_ply_index),
                Some(decision.actor),
                EvidenceLevel::Hard,
                FindingClass::EngineAnomaly,
                "raw_uci_capture_exceeds_limit",
                "a decision stores more than the 64 KiB Trace v2 UCI capture limit",
                decision_state,
                rules_sha256,
                "trace_integrity",
            ));
        }
        let hash_is_hex = decision.raw_uci_sha256.len() == 64
            && decision
                .raw_uci_sha256
                .bytes()
                .all(|byte| byte.is_ascii_hexdigit());
        if !hash_is_hex
            || (!decision.raw_uci_truncated
                && plain_sha256(decision.raw_uci_output.as_bytes())
                    != decision.raw_uci_sha256.to_ascii_lowercase())
        {
            findings.push(finding(
                game,
                Some(decision.action_index),
                Some(decision.logical_ply_index),
                Some(decision.actor),
                EvidenceLevel::Hard,
                FindingClass::EngineAnomaly,
                "raw_uci_sha256_mismatch",
                "the retained UCI stream does not match its full-stream SHA-256",
                decision_state,
                rules_sha256,
                "trace_integrity",
            ));
        }
        if !decision.raw_uci_truncated
            && let Some(bestmove) = decision.bestmove.as_deref()
            && !decision
                .raw_uci_output
                .split_whitespace()
                .any(|token| token == bestmove)
        {
            findings.push(finding(
                game,
                Some(decision.action_index),
                Some(decision.logical_ply_index),
                Some(decision.actor),
                EvidenceLevel::Hard,
                FindingClass::EngineAnomaly,
                "bestmove_missing_from_raw_uci",
                "the parsed bestmove is absent from the complete retained UCI stream",
                decision_state,
                rules_sha256,
                "trace_integrity",
            ));
        }
        if decision.action_index < game.opening_moves.len() {
            findings.push(finding(
                game,
                Some(decision.action_index),
                Some(decision.logical_ply_index),
                Some(decision.actor),
                EvidenceLevel::Hard,
                FindingClass::EngineAnomaly,
                "decision_inside_opening_prefix",
                "an engine decision claims an action owned by the referee opening prefix",
                states.get(decision.action_index),
                rules_sha256,
                "trace_protocol",
            ));
            continue;
        }
        if decision.action_index < game.moves.len() {
            continue;
        }
        let state = states.last();
        if decision.action_index != game.moves.len() {
            findings.push(finding(
                game,
                Some(decision.action_index),
                Some(decision.logical_ply_index),
                Some(decision.actor),
                EvidenceLevel::Hard,
                FindingClass::EngineAnomaly,
                "decision_action_index_out_of_range",
                "an engine decision points beyond the final replay root",
                state,
                rules_sha256,
                "trace_protocol",
            ));
            continue;
        }
        if let Some(error) = decision.protocol_error.as_ref() {
            findings.push(finding(
                game,
                Some(decision.action_index),
                Some(decision.logical_ply_index),
                Some(decision.actor),
                EvidenceLevel::Hard,
                FindingClass::EngineAnomaly,
                "uci_search_protocol_error",
                &format!("the final engine search failed before a usable action: {error}"),
                state,
                rules_sha256,
                "trace_protocol",
            ));
        }
        match decision.bestmove.as_deref() {
            None => {}
            Some(token) => {
                let Some(root) = states.last() else {
                    continue;
                };
                let Some(action) = MillUciCodec::decode_action(&snapshot, token) else {
                    findings.push(finding(
                        game,
                        Some(decision.action_index),
                        Some(decision.logical_ply_index),
                        Some(decision.actor),
                        EvidenceLevel::Hard,
                        FindingClass::EngineAnomaly,
                        "undecodable_unapplied_bestmove",
                        &format!("unapplied bestmove `{token}` cannot be decoded"),
                        Some(root),
                        rules_sha256,
                        "trace_protocol",
                    ));
                    continue;
                };
                let mut legal = ActionList::<256>::new();
                rules.legal_actions(&snapshot, &mut legal);
                let (code, message) = if legal.as_slice().contains(&action) {
                    (
                        "legal_bestmove_not_applied",
                        format!("legal bestmove `{token}` was not applied by the referee"),
                    )
                } else {
                    (
                        "illegal_unapplied_bestmove",
                        format!("engine returned illegal bestmove `{token}`"),
                    )
                };
                findings.push(finding(
                    game,
                    Some(decision.action_index),
                    Some(decision.logical_ply_index),
                    Some(decision.actor),
                    EvidenceLevel::Hard,
                    FindingClass::EngineAnomaly,
                    code,
                    &message,
                    Some(root),
                    rules_sha256,
                    "trace_protocol",
                ));
            }
        }
    }

    if let Some(turn) = pending_turn {
        let pending = MillRules::decode_snapshot(snapshot).pending_removals();
        let ongoing = matches!(rules.outcome(&snapshot).kind, OutcomeKind::Ongoing);
        if ongoing || pending != [0, 0] {
            findings.push(finding(
                game,
                Some(turn.action_start),
                Some(turn.logical_ply_index),
                Some(turn.actor),
                EvidenceLevel::Hard,
                FindingClass::EngineAnomaly,
                "incomplete_logical_turn",
                "game trace ends while the actor still owes a mandatory continuation",
                Some(&turn.before),
                rules_sha256,
                "logical_turn",
            ));
        }
    }

    if game.plies != game.moves.len() {
        findings.push(finding(
            game,
            None,
            None,
            None,
            EvidenceLevel::Hard,
            FindingClass::EngineAnomaly,
            "ply_count_mismatch",
            &format!(
                "trace declares {} plies but contains {} atomic actions",
                game.plies,
                game.moves.len()
            ),
            states.last(),
            rules_sha256,
            "trace_protocol",
        ));
    }

    let final_outcome = rules.outcome(&snapshot);
    let replay_winner = match final_outcome.kind {
        OutcomeKind::Win(0) => Some(H2hActor::White),
        OutcomeKind::Win(1) => Some(H2hActor::Black),
        _ => None,
    };
    let replay_terminal = !matches!(final_outcome.kind, OutcomeKind::Ongoing);
    validate_final_outcome(
        game,
        replay_winner,
        &final_outcome.reason,
        replay_terminal,
        states.last(),
        rules_sha256,
        &mut findings,
    );

    ReplayedGame {
        source: game.clone(),
        states,
        logical_turns,
        findings,
    }
}

#[allow(clippy::too_many_arguments)]
fn transition_contract_findings(
    game: &NormalizedGame,
    options: &MillVariantOptions,
    before: &GameStateSnapshot,
    after: &GameStateSnapshot,
    history: &[GameStateSnapshot],
    action: Action,
    action_index: usize,
    logical_ply_index: u32,
    evidence: &StateEvidence,
    rules_sha256: &str,
) -> Vec<Finding> {
    let mut findings = Vec::new();
    let repetition_history = MillRules::repetition_history_from_snapshots(before, history);
    let root_resets = MillRules::root_position_resets_repetition_from_snapshots(before, history);
    let game_impl =
        MillGame::new_with_repetition_context(options.clone(), repetition_history, root_resets);
    let mut workbench = game_impl.build_workbench(before);
    workbench.do_move(action);
    let search_after = workbench.snapshot();
    if search_after != *after {
        findings.push(finding(
            game,
            Some(action_index),
            Some(logical_ply_index),
            H2hActor::from_side(before.side_to_move),
            EvidenceLevel::Hard,
            FindingClass::EngineAnomaly,
            "rules_search_transition_mismatch",
            "GameRules::apply_with_history and Mill Workbench::do_move disagree",
            Some(evidence),
            rules_sha256,
            "rules_search_contract",
        ));
    }

    if action.kind_tag == MillActionKind::Remove as i16 {
        let decoded = MillRules::decode_snapshot(*after);
        if decoded.ply_since_capture() != 0 {
            findings.push(finding(
                game,
                Some(action_index),
                Some(logical_ply_index),
                H2hActor::from_side(before.side_to_move),
                EvidenceLevel::Hard,
                FindingClass::EngineAnomaly,
                "remove_did_not_reset_inactivity",
                "a removal did not reset the no-capture counter",
                Some(evidence),
                rules_sha256,
                "draw_counter",
            ));
        }
        let mut after_history = history.to_vec();
        after_history.push(*before);
        if !MillRules::repetition_history_from_snapshots(after, &after_history).is_empty() {
            findings.push(finding(
                game,
                Some(action_index),
                Some(logical_ply_index),
                H2hActor::from_side(before.side_to_move),
                EvidenceLevel::Hard,
                FindingClass::EngineAnomaly,
                "remove_did_not_reset_repetition_window",
                "a removal did not clear the reversible repetition window",
                Some(evidence),
                rules_sha256,
                "repetition",
            ));
        }
    }
    findings
}

fn contract_findings(
    game: &NormalizedGame,
    options: &MillVariantOptions,
    rules: &MillRules,
    snapshot: &GameStateSnapshot,
    history: &[GameStateSnapshot],
    evidence: &StateEvidence,
    rules_sha256: &str,
) -> Vec<Finding> {
    let mut findings = Vec::new();
    let repetition_history = MillRules::repetition_history_from_snapshots(snapshot, history);
    let root_resets = MillRules::root_position_resets_repetition_from_snapshots(snapshot, history);
    let game_impl =
        MillGame::new_with_repetition_context(options.clone(), repetition_history, root_resets);
    let workbench = game_impl.build_workbench(snapshot);
    let decoded = MillRules::decode_snapshot(*snapshot);
    if workbench.side_to_move() != snapshot.side_to_move
        || workbench.pieces_on_board() != decoded.pieces_on_board()
        || workbench.pieces_in_hand() != decoded.pieces_in_hand()
    {
        findings.push(finding(
            game,
            Some(evidence.action_index),
            Some(evidence.logical_ply_index),
            H2hActor::from_side(snapshot.side_to_move),
            EvidenceLevel::Hard,
            FindingClass::EngineAnomaly,
            "rules_search_state_mismatch",
            "Mill Workbench decoded a different side or piece count than GameRules",
            Some(evidence),
            rules_sha256,
            "rules_search_contract",
        ));
    }

    let mut rules_legal = ActionList::<256>::new();
    rules.legal_actions(snapshot, &mut rules_legal);
    let mut search_legal = SearchActionList::new();
    MillGame::generate_legal(&workbench, &mut search_legal);
    let rules_tokens = action_set(rules_legal.as_slice());
    let search_tokens = action_set(search_legal.as_slice());
    if rules_tokens != search_tokens {
        findings.push(finding(
            game,
            Some(evidence.action_index),
            Some(evidence.logical_ply_index),
            H2hActor::from_side(snapshot.side_to_move),
            EvidenceLevel::Hard,
            FindingClass::EngineAnomaly,
            "rules_search_legal_actions_mismatch",
            "GameRules and MillGame search enumerate different legal actions",
            Some(evidence),
            rules_sha256,
            "rules_search_contract",
        ));
    }

    if pending_removal_inactivity_override(
        evidence.pending_removal,
        <MillGame as Game>::search_alpha_override(&workbench),
    ) {
        findings.push(finding(
            game,
            Some(evidence.action_index),
            Some(evidence.logical_ply_index),
            H2hActor::from_side(snapshot.side_to_move),
            EvidenceLevel::Hard,
            FindingClass::EngineAnomaly,
            "pending_removal_inactivity_override",
            "search returned an N-move draw floor while a mandatory removal was pending",
            Some(evidence),
            rules_sha256,
            "pending_removal_draw_boundary",
        ));
    }
    findings
}

pub(crate) fn pending_removal_inactivity_override(
    pending_removal: bool,
    search_alpha_override: Option<i32>,
) -> bool {
    pending_removal && search_alpha_override.is_some()
}

fn action_set(actions: &[Action]) -> BTreeSet<String> {
    actions
        .iter()
        .copied()
        .map(MillUciCodec::encode_action)
        .collect()
}

fn state_evidence(
    rules: &MillRules,
    options: &MillVariantOptions,
    snapshot: &GameStateSnapshot,
    history: &[GameStateSnapshot],
    action_tokens: &[String],
    counts: MillPlyCount,
    action_index: usize,
) -> StateEvidence {
    let summary = summarize_position(rules, snapshot, history, action_tokens, counts)
        .expect("strict replay state summary must succeed");
    let decoded = MillRules::decode_snapshot(*snapshot);
    let mut legal = ActionList::<256>::new();
    rules.legal_actions(snapshot, &mut legal);
    let repetition = MillRules::repetition_history_from_snapshots(snapshot, history);
    let repetition_current_count = repetition
        .last()
        .map(|current| repetition.iter().filter(|value| *value == current).count())
        .unwrap_or(0);
    let pieces_on_board = decoded.pieces_on_board();
    let pieces_in_hand = decoded.pieces_in_hand();
    let is_endgame = options.endgame_n_move_rule > 0
        && options.endgame_n_move_rule < options.n_move_rule
        && pieces_on_board.contains(&3);
    let inactivity_threshold = if is_endgame {
        options.endgame_n_move_rule
    } else {
        options.n_move_rule
    };
    let inactivity_threshold = (inactivity_threshold > 0).then_some(inactivity_threshold);
    let flying_sides = std::array::from_fn(|side| {
        options.may_fly
            && pieces_in_hand[side] == 0
            && pieces_on_board[side] >= options.pieces_at_least_count
            && pieces_on_board[side] <= options.fly_piece_count
    });
    StateEvidence {
        action_index,
        logical_ply_index: counts.logical_plies,
        fen: summary.current_fen,
        side_to_move: H2hActor::from_side(snapshot.side_to_move),
        phase: summary.phase,
        action_tag: decoded.action_tag(),
        pending_removal: summary.pending_removal,
        pending_removals: summary.pending_removals,
        pieces_on_board,
        pieces_in_hand,
        no_capture_count: summary.no_capture_plies,
        inactivity_threshold,
        inactivity_boundary_distance: inactivity_threshold
            .map(|threshold| threshold.saturating_sub(u32::from(summary.no_capture_plies))),
        flying_sides,
        repetition_current_count,
        repetition_history_length: summary.repetition_history_len,
        snapshot_history_length: summary.snapshot_history_len,
        history_sha256: summary.history_sha256,
        legal_actions: legal
            .as_slice()
            .iter()
            .copied()
            .map(MillUciCodec::encode_action)
            .collect(),
        terminal: summary.outcome.kind != "ongoing",
        winner: summary.outcome.winner.and_then(H2hActor::from_side),
        outcome_reason: summary.outcome.reason,
    }
}

fn validate_final_outcome(
    game: &NormalizedGame,
    replay_winner: Option<H2hActor>,
    replay_reason: &str,
    replay_terminal: bool,
    state: Option<&StateEvidence>,
    rules_sha256: &str,
    findings: &mut Vec<Finding>,
) {
    let final_action_index = state.map(|value| value.action_index);
    let final_logical_ply = state.map(|value| value.logical_ply_index);
    match game.end_kind {
        Some(H2hGameEndKind::Rule) => {
            if !replay_terminal
                || game.winner != replay_winner
                || game.outcome_reason.as_deref() != Some(replay_reason)
            {
                findings.push(finding(
                    game,
                    final_action_index,
                    final_logical_ply,
                    None,
                    EvidenceLevel::Hard,
                    FindingClass::EngineAnomaly,
                    "final_outcome_mismatch",
                    "strict replay disagrees with the referee's rule termination",
                    state,
                    rules_sha256,
                    "rules_replay",
                ));
            }
        }
        Some(H2hGameEndKind::PlyCap) => {
            if replay_terminal {
                findings.push(finding(
                    game,
                    final_action_index,
                    final_logical_ply,
                    None,
                    EvidenceLevel::Hard,
                    FindingClass::EngineAnomaly,
                    "ply_cap_masked_rule_terminal",
                    "trace labels a ply cap but strict replay had already reached a rule terminal",
                    state,
                    rules_sha256,
                    "rules_replay",
                ));
            }
        }
        Some(H2hGameEndKind::ProtocolError) => findings.push(finding(
            game,
            final_action_index,
            final_logical_ply,
            None,
            EvidenceLevel::Hard,
            FindingClass::EngineAnomaly,
            "protocol_termination",
            &format!(
                "the H2H referee terminated on a protocol error: {}",
                game.outcome_reason.as_deref().unwrap_or("unspecified")
            ),
            state,
            rules_sha256,
            "trace_protocol",
        )),
        None => {
            if let Some(expected) = game.winner
                && replay_winner != Some(expected)
            {
                findings.push(finding(
                    game,
                    final_action_index,
                    final_logical_ply,
                    None,
                    EvidenceLevel::Hard,
                    FindingClass::EngineAnomaly,
                    "legacy_final_winner_mismatch",
                    "v1 result winner disagrees with strict replay",
                    state,
                    rules_sha256,
                    "rules_replay",
                ));
            }
        }
    }
}

fn validate_instance_ordinals(games: &mut [ReplayedGame], rules_sha256: &str) {
    let mut entries = games
        .iter()
        .flat_map(|game| {
            game.source.decisions.iter().map(move |decision| {
                (
                    decision.engine_instance_id.clone(),
                    decision.instance_search_ordinal,
                    game.source.game_index,
                    decision.action_index,
                )
            })
        })
        .collect::<Vec<_>>();
    entries.sort_by(|left, right| (left.0.as_str(), left.1).cmp(&(right.0.as_str(), right.1)));
    let mut expected = BTreeMap::<String, u64>::new();
    for (instance, ordinal, game_index, action_index) in entries {
        let next = expected.entry(instance.clone()).or_insert(1);
        if ordinal != *next
            && let Some(game) = games
                .iter_mut()
                .find(|game| game.source.game_index == game_index)
        {
            game.findings.push(finding(
                &game.source,
                Some(action_index),
                None,
                None,
                EvidenceLevel::Hard,
                FindingClass::EngineAnomaly,
                "engine_search_ordinal_gap",
                &format!(
                    "engine instance `{instance}` search ordinal is {ordinal}, expected {}",
                    *next
                ),
                game.states.get(action_index),
                rules_sha256,
                "trace_protocol",
            ));
        }
        *next = ordinal.saturating_add(1);
    }
}

#[allow(clippy::too_many_arguments)]
pub(crate) fn finding(
    game: &NormalizedGame,
    action_index: Option<usize>,
    logical_ply_index: Option<u32>,
    actor: Option<H2hActor>,
    evidence: EvidenceLevel,
    classification: FindingClass,
    code: &str,
    message: &str,
    state: Option<&StateEvidence>,
    rules_sha256: &str,
    semantic_shape: &str,
) -> Finding {
    let history_sha = state.map(|value| value.history_sha256.clone());
    let exact_case_key = state.map(|value| {
        hash_key(
            b"sanmill.h2h.exact-case.v1\0",
            &format!(
                "{rules_sha256}\0{}\0{}",
                value.history_sha256,
                action_index.unwrap_or(value.action_index)
            ),
        )
    });
    let canonical_position_key = state.map(|value| {
        let canonical = canonical_forensic_fen(&value.fen).unwrap_or_else(|_| value.fen.clone());
        hash_key(b"sanmill.h2h.canonical-position.v1\0", &canonical)
    });
    let semantic_signature = Some(format!(
        "{code}|{semantic_shape}|pending={}|phase={}|n-boundary={}|flying={:?}",
        state.is_some_and(|value| value.pending_removal),
        state.map(|value| value.phase.as_str()).unwrap_or("unknown"),
        state
            .and_then(|value| value.inactivity_boundary_distance)
            .map(|value| value.to_string())
            .unwrap_or_else(|| "disabled".to_string()),
        state
            .map(|value| value.flying_sides)
            .unwrap_or([false, false])
    ));
    let identity = format!(
        "{}\0{}\0{}\0{}",
        game.game_index,
        action_index.unwrap_or(usize::MAX),
        code,
        history_sha.as_deref().unwrap_or("")
    );
    let (subsystems, symbols) = subsystem_hints(code);
    Finding {
        finding_id: format!(
            "finding-{}",
            &hash_key(b"sanmill.h2h.finding-id.v1\0", &identity)[..16]
        ),
        game_index: game.game_index,
        pair_index: game.pair_index,
        action_index,
        logical_ply_index,
        actor,
        evidence,
        classification,
        code: code.to_string(),
        message: message.to_string(),
        facts: vec![message.to_string()],
        inferences: Vec::new(),
        unknowns: Vec::new(),
        root_fen: state.map(|value| value.fen.clone()),
        history_sha256: history_sha,
        exact_case_key,
        canonical_position_key,
        semantic_signature,
        database: None,
        suspected_subsystems: subsystems,
        suspected_symbols: symbols,
        case_ids: Vec::new(),
    }
}

fn subsystem_hints(code: &str) -> (Vec<String>, Vec<String>) {
    match code {
        "pending_removal_inactivity_override" => (
            vec!["Mill draw-rule/search contract".to_string()],
            vec![
                "search_n_move_draw_alpha_override".to_string(),
                "MillGame::search_alpha_override".to_string(),
            ],
        ),
        "rules_search_transition_mismatch"
        | "rules_search_state_mismatch"
        | "rules_search_legal_actions_mismatch" => (
            vec!["TGF Mill rules/search parity".to_string()],
            vec![
                "MillRules".to_string(),
                "MillGame".to_string(),
                "MillWorkbench".to_string(),
            ],
        ),
        "remove_did_not_reset_inactivity" | "remove_did_not_reset_repetition_window" => (
            vec!["Mill removal and history".to_string()],
            vec!["MillRules::apply_with_history".to_string()],
        ),
        _ => (vec!["H2H trace/replay".to_string()], Vec::new()),
    }
}

fn hash_key(domain: &[u8], text: &str) -> String {
    sha256_bytes(domain, text.as_bytes())
}

fn plain_sha256(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

/// Canonicalize a complete node-id FEN without erasing forensic state.
///
/// Opening-book canonicalization deliberately clears formed-mill and
/// inactivity fields. That is correct for book lookup but would merge states
/// that have different draw-rule or anti-remill semantics. This transform
/// rotates every node-bearing field while retaining side, phase, pending
/// removals, counters, and all other rule state.
fn canonical_forensic_fen(fen: &str) -> Result<String, String> {
    let mut canonical = forensic_fen_transform(fen, 0)?;
    for transform in 1..OPENING_BOOK_SYMMETRY_COUNT {
        let candidate = forensic_fen_transform(fen, transform)?;
        if candidate < canonical {
            canonical = candidate;
        }
    }
    Ok(canonical)
}

fn forensic_fen_transform(fen: &str, transform: usize) -> Result<String, String> {
    let mut fields = fen
        .split_whitespace()
        .map(str::to_owned)
        .collect::<Vec<_>>();
    if fields.len() < 18 || !fields.iter().any(|field| field == "ids:nodes") {
        return Err("forensic canonicalization requires a complete node-id FEN".to_string());
    }

    let board = fields[0]
        .split('/')
        .flat_map(str::chars)
        .collect::<Vec<_>>();
    if board.len() != 24 {
        return Err(format!(
            "forensic FEN board must contain 24 nodes, got {}",
            board.len()
        ));
    }
    let mut transformed = ['*'; 24];
    for (node, piece) in board.into_iter().enumerate() {
        let target = transform_opening_book_node(node, transform)?;
        transformed[target] = piece;
    }
    fields[0] = format!(
        "{}/{}/{}",
        transformed[0..8].iter().collect::<String>(),
        transformed[8..16].iter().collect::<String>(),
        transformed[16..24].iter().collect::<String>()
    );

    for field in &mut fields[10..14] {
        let node = field
            .parse::<i16>()
            .map_err(|_| format!("invalid last-mill node `{field}`"))?;
        if node >= 0 {
            *field = transform_opening_book_node(node as usize, transform)?.to_string();
        }
    }

    let formed = fields[14]
        .parse::<u64>()
        .map_err(|_| format!("invalid formed-mills bitboard `{}`", fields[14]))?;
    let white = transform_node_bits(((formed >> 32) & 0x00ff_ffff) as u32, transform)?;
    let black = transform_node_bits((formed & 0x00ff_ffff) as u32, transform)?;
    fields[14] = ((u64::from(white) << 32) | u64::from(black)).to_string();

    for field in &mut fields[18..] {
        if let Some(value) = field.strip_prefix("p:") {
            let node = value
                .parse::<usize>()
                .map_err(|_| format!("invalid preferred-removal node `{field}`"))?;
            *field = format!("p:{}", transform_opening_book_node(node, transform)?);
        } else if matches!(field.get(..2), Some("c:") | Some("i:") | Some("l:")) {
            *field = transform_capture_extension(field, transform)?;
        }
    }
    Ok(fields.join(" "))
}

fn transform_node_bits(bits: u32, transform: usize) -> Result<u32, String> {
    if bits & !0x00ff_ffff != 0 {
        return Err(format!("node bitboard uses bits outside 0..23: {bits}"));
    }
    let mut transformed = 0_u32;
    for node in 0..24 {
        if bits & (1_u32 << node) != 0 {
            transformed |= 1_u32 << transform_opening_book_node(node, transform)?;
        }
    }
    Ok(transformed)
}

fn transform_capture_extension(field: &str, transform: usize) -> Result<String, String> {
    let (prefix, value) = field
        .split_once(':')
        .ok_or_else(|| format!("invalid capture extension `{field}`"))?;
    let mut transformed_segments = Vec::new();
    for segment in value.split('|') {
        let mut parts = segment.splitn(3, '-');
        let side = parts
            .next()
            .ok_or_else(|| format!("invalid capture extension `{field}`"))?;
        let count = parts
            .next()
            .ok_or_else(|| format!("invalid capture extension `{field}`"))?;
        let nodes = parts
            .next()
            .ok_or_else(|| format!("invalid capture extension `{field}`"))?;
        let mut transformed_nodes = nodes
            .split('.')
            .filter(|node| !node.is_empty())
            .map(|node| {
                node.parse::<usize>()
                    .map_err(|_| format!("invalid capture target `{node}`"))
                    .and_then(|node| transform_opening_book_node(node, transform))
            })
            .collect::<Result<Vec<_>, _>>()?;
        transformed_nodes.sort_unstable();
        let targets = transformed_nodes
            .iter()
            .map(usize::to_string)
            .collect::<Vec<_>>()
            .join(".");
        transformed_segments.push(format!("{side}-{count}-{targets}"));
    }
    Ok(format!("{prefix}:{}", transformed_segments.join("|")))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tgf_cli::h2h_trace::{H2hDecisionTraceV2, H2hGameEndKind};

    fn game_with_moves(moves: &[&str]) -> NormalizedGame {
        NormalizedGame {
            schema_version: 1,
            run_id: None,
            game_index: 0,
            pair_index: 0,
            worker_id: None,
            current_white: Some(true),
            result: "unfinished".to_string(),
            plies: moves.len(),
            opening_moves: Vec::new(),
            moves: moves.iter().map(|value| (*value).to_string()).collect(),
            white_seed: None,
            black_seed: None,
            white_engine_instance_id: None,
            black_engine_instance_id: None,
            winner: None,
            outcome_reason: None,
            end_kind: Some(H2hGameEndKind::PlyCap),
            decisions: Vec::new(),
        }
    }

    #[test]
    fn mill_and_forced_removal_are_one_logical_turn() {
        let game = game_with_moves(&["d7", "a1", "g7", "d1", "a7", "xa1"]);
        let options = MillVariantOptions::default();
        let rules = MillRules::new(options.clone());
        let replay = replay_game(&game, &options, &rules, "rules");
        assert_eq!(replay.logical_turns.len(), 5);
        assert_eq!(
            replay.logical_turns.last().unwrap().tokens,
            vec!["a7".to_string(), "xa1".to_string()]
        );
        assert!(
            !replay
                .findings
                .iter()
                .any(|finding| finding.code == "incomplete_logical_turn")
        );
    }

    #[test]
    fn incomplete_mill_turn_is_a_hard_anomaly() {
        let game = game_with_moves(&["d7", "a1", "g7", "d1", "a7"]);
        let options = MillVariantOptions::default();
        let rules = MillRules::new(options.clone());
        let replay = replay_game(&game, &options, &rules, "rules");
        assert!(replay.findings.iter().any(|finding| {
            finding.code == "incomplete_logical_turn" && finding.evidence == EvidenceLevel::Hard
        }));
    }

    #[test]
    fn pending_removal_override_predicate_catches_the_bug_shape() {
        assert!(pending_removal_inactivity_override(true, Some(0)));
        assert!(!pending_removal_inactivity_override(true, None));
        assert!(!pending_removal_inactivity_override(false, Some(0)));
    }

    #[test]
    fn reported_a4_d7_fixture_has_no_override_after_the_fix() {
        let options = MillVariantOptions {
            n_move_rule: 50,
            endgame_n_move_rule: 20,
            ..MillVariantOptions::default()
        };
        let rules = MillRules::new(options.clone());
        let state = rules
            .set_from_fen(
                "O*****@*/O*****@*/**@***O@ w m s 3 0 4 0 0 0 -1 -1 -1 -1 0 19 32 ids:nodes",
            )
            .unwrap();
        let root = rules.encode_state(state);
        let action = MillUciCodec::decode_action(&root, "a4-d7").unwrap();
        let pending = rules.apply(&root, action);
        let decoded = MillRules::decode_snapshot(pending);
        assert!(decoded.pending_removals()[0] > 0);
        assert_eq!(decoded.ply_since_capture(), 20);
        let workbench = MillGame::new(options).build_workbench(&pending);
        assert!(!pending_removal_inactivity_override(
            true,
            <MillGame as Game>::search_alpha_override(&workbench)
        ));
    }

    #[test]
    fn forensic_position_key_merges_symmetry_but_preserves_counters() {
        let fen = "O*******/**@*****/****O*** b p p 2 7 1 8 0 0 -1 -1 -1 -1 7 42 3 ids:nodes";
        let rotated = forensic_fen_transform(fen, 13).unwrap();
        assert_ne!(fen, rotated);
        assert_eq!(
            canonical_forensic_fen(fen).unwrap(),
            canonical_forensic_fen(&rotated).unwrap()
        );

        let mut changed = fen
            .split_whitespace()
            .map(str::to_owned)
            .collect::<Vec<_>>();
        changed[15] = "41".to_string();
        assert_ne!(
            canonical_forensic_fen(fen).unwrap(),
            canonical_forensic_fen(&changed.join(" ")).unwrap(),
            "different no-capture counters must not share a position cluster"
        );
    }

    #[test]
    fn exact_case_key_keeps_same_position_with_different_history_separate() {
        let options = MillVariantOptions::default();
        let rules = MillRules::new(options.clone());
        let state = rules
            .set_from_fen(
                "O*****@*/O*****@*/**@***O@ w m s 3 0 4 0 0 0 -1 -1 -1 -1 0 3 32 ids:nodes",
            )
            .unwrap();
        let snapshot = rules.encode_state(state);
        let first = state_evidence(
            &rules,
            &options,
            &snapshot,
            &[],
            &[],
            MillPlyCount::default(),
            0,
        );
        let mut second = first.clone();
        second.history_sha256 = "different-valid-history".to_string();
        assert_ne!(first.history_sha256, second.history_sha256);

        let game = game_with_moves(&[]);
        let left = finding(
            &game,
            Some(0),
            Some(0),
            Some(H2hActor::White),
            EvidenceLevel::Unresolved,
            FindingClass::Unresolved,
            "test",
            "test",
            Some(&first),
            "rules",
            "test",
        );
        let right = finding(
            &game,
            Some(0),
            Some(0),
            Some(H2hActor::White),
            EvidenceLevel::Unresolved,
            FindingClass::Unresolved,
            "test",
            "test",
            Some(&second),
            "rules",
            "test",
        );
        assert_eq!(left.canonical_position_key, right.canonical_position_key);
        assert_ne!(left.exact_case_key, right.exact_case_key);
    }

    #[test]
    fn protocol_termination_retains_an_illegal_unapplied_bestmove() {
        let mut game = game_with_moves(&[]);
        game.schema_version = 2;
        game.end_kind = Some(H2hGameEndKind::ProtocolError);
        game.outcome_reason = Some("protocol_illegal_bestmove:a4-d7".to_string());
        game.decisions.push(H2hDecisionTraceV2 {
            actor: H2hActor::White,
            engine_role: "candidate".to_string(),
            engine_instance_id: "worker-0-white".to_string(),
            instance_search_ordinal: 1,
            action_index: 0,
            logical_ply_index: 0,
            go_command: "go nodes 100000".to_string(),
            elapsed_ms: 1,
            bestmove: Some("a4-d7".to_string()),
            depth: Some(1),
            score_kind: Some("cp".to_string()),
            score_value: Some(0),
            nodes: Some(1),
            raw_uci_output: "bestmove a4-d7\n".to_string(),
            raw_uci_sha256: "hash".to_string(),
            raw_uci_truncated: false,
            protocol_error: None,
        });
        let options = MillVariantOptions::default();
        let rules = MillRules::new(options.clone());
        let replay = replay_game(&game, &options, &rules, "rules");
        assert!(replay.findings.iter().any(|finding| {
            finding.code == "illegal_unapplied_bestmove" && finding.evidence == EvidenceLevel::Hard
        }));
        assert!(
            replay
                .findings
                .iter()
                .any(|finding| finding.code == "protocol_termination")
        );
    }
}
