// SPDX-License-Identifier: AGPL-3.0-or-later

use std::collections::{BTreeMap, BTreeSet};

use tgf_core::{
    Action, ActionList, Evaluator, Game, GameRules, GameStateSnapshot, MoveOrderAlgorithm,
    MoveOrderContext, OutcomeKind,
};
use tgf_mill::{
    MillActionKind, MillGame, MillRules, MillUciCodec, MillVariantOptions, logical_turn_completed,
};
use tgf_search::{SearchOptions, SearchPolicy, Searcher};

use super::model::{
    DeterministicSearchMatrix, EvidenceLevel, FindingClass, ReplayedGame, SearchProbeEvidence,
};
use super::replay::finding;

const TRIAGE_CAP: u64 = 1_000_000;
const CONFIRM_CAP: u64 = 4_000_000;
const SEARCH_SEED: u64 = 0x4842_485f_464f_5245;
const MAX_SEARCH_DEPTH: i32 = 32;
const MATE_THRESHOLD: i32 = 48;

#[derive(Clone, Copy, Debug)]
pub(crate) struct SearchTriageConfig {
    pub triage_floor: u64,
    pub confirm_floor: u64,
    pub max_cases: usize,
}

#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct SearchTriageStats {
    pub eligible_cases: usize,
    pub selected_cases: usize,
    pub completed_cases: usize,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum ProbeAlgorithm {
    Pvs,
    Mtdf,
}

impl ProbeAlgorithm {
    fn name(self) -> &'static str {
        match self {
            Self::Pvs => "pvs",
            Self::Mtdf => "mtdf",
        }
    }

    fn move_order(self) -> MoveOrderAlgorithm {
        match self {
            Self::Pvs => MoveOrderAlgorithm::Pvs,
            Self::Mtdf => MoveOrderAlgorithm::Mtdf,
        }
    }
}

#[derive(Clone, Debug)]
struct Candidate {
    game_slot: usize,
    turn_slot: usize,
    priority: u32,
    reasons: BTreeSet<String>,
}

#[derive(Clone, Debug)]
struct SearchRun {
    selected_turn: Vec<String>,
    score: i32,
    nodes: u64,
    completed_depth: i32,
}

pub(crate) fn analyze_search_cases(
    games: &mut [ReplayedGame],
    options: &MillVariantOptions,
    rules_sha256: &str,
    config: SearchTriageConfig,
) -> SearchTriageStats {
    let candidates = select_candidates(games);
    let eligible_cases = candidates.len();
    let selected = candidates
        .into_iter()
        .take(config.max_cases)
        .collect::<Vec<_>>();
    let selected_cases = selected.len();
    let mut completed_cases = 0;

    for candidate in selected {
        let game_slot = candidate.game_slot;
        let turn_slot = candidate.turn_slot;
        let live_nodes = games[game_slot]
            .source
            .decisions
            .iter()
            .find(|decision| {
                decision.action_index == games[game_slot].logical_turns[turn_slot].action_start
            })
            .and_then(|decision| decision.nodes)
            .unwrap_or(0);
        let triage = config
            .triage_floor
            .max(live_nodes.saturating_mul(4))
            .min(TRIAGE_CAP);
        let confirm = config
            .confirm_floor
            .max(live_nodes.saturating_mul(16))
            .min(CONFIRM_CAP);
        let matrix = {
            let turn = &games[game_slot].logical_turns[turn_slot];
            build_matrix(turn, options, triage, confirm)
        };
        if matrix.probes.iter().all(|probe| probe.status == "complete") {
            completed_cases += 1;
        }

        let turn = &games[game_slot].logical_turns[turn_slot];
        let (level, class, code, message) = if matrix.probable {
            (
                EvidenceLevel::Probable,
                FindingClass::EngineAnomaly,
                "probable_engine_anomaly",
                format!(
                    "PVS and MTD(f) at both node budgets agree on `{}` instead of the played `{}`",
                    matrix
                        .agreed_alternative
                        .as_ref()
                        .map(|actions| actions.join(" "))
                        .unwrap_or_default(),
                    turn.tokens.join(" ")
                ),
            )
        } else if matrix.budget_limited {
            (
                EvidenceLevel::Advisory,
                FindingClass::ReplayNote,
                "budget_limited_move_error",
                "the low-budget search disagreement disappears or changes at confirmation budget"
                    .to_string(),
            )
        } else {
            (
                EvidenceLevel::Unresolved,
                FindingClass::Unresolved,
                "unresolved_deterministic_search",
                "deterministic PVS/MTD(f) probes did not converge on one material alternative"
                    .to_string(),
            )
        };
        let mut item = finding(
            &games[game_slot].source,
            Some(turn.action_start),
            Some(turn.logical_ply_index),
            Some(turn.actor),
            level,
            class,
            code,
            &message,
            Some(&turn.before),
            rules_sha256,
            if turn.tokens.len() > 1 {
                "deterministic_search_mill_with_removal"
            } else {
                "deterministic_search_single_action"
            },
        );
        item.facts.push(format!(
            "triage reasons: {}",
            candidate.reasons.into_iter().collect::<Vec<_>>().join(", ")
        ));
        if !matrix.unresolved_reasons.is_empty() {
            item.unknowns.extend(matrix.unresolved_reasons.clone());
        }
        games[game_slot].findings.push(item);
        games[game_slot].logical_turns[turn_slot].deterministic_search = Some(matrix);
    }

    SearchTriageStats {
        eligible_cases,
        selected_cases,
        completed_cases,
    }
}

fn select_candidates(games: &[ReplayedGame]) -> Vec<Candidate> {
    let mut candidates = BTreeMap::<(usize, usize), Candidate>::new();
    for (game_slot, game) in games.iter().enumerate() {
        for (turn_slot, turn) in game.logical_turns.iter().enumerate() {
            if turn.action_start < game.source.opening_moves.len() {
                continue;
            }
            let is_candidate_turn = if game.source.schema_version >= 2 {
                game.source
                    .decisions
                    .iter()
                    .find(|decision| decision.action_index == turn.action_start)
                    .is_some_and(|decision| decision.engine_role == "candidate")
            } else {
                game.source.current_white.is_none_or(|white| {
                    turn.actor
                        == if white {
                            tgf_cli::h2h_trace::H2hActor::White
                        } else {
                            tgf_cli::h2h_trace::H2hActor::Black
                        }
                })
            };
            if !is_candidate_turn {
                continue;
            }
            let key = (game_slot, turn_slot);
            if turn
                .database
                .as_ref()
                .is_none_or(|evidence| evidence.status != "covered")
            {
                add_candidate(
                    &mut candidates,
                    key,
                    80,
                    "Perfect DB miss/error".to_string(),
                );
            }
            if game.findings.iter().any(|finding| {
                finding.action_index == Some(turn.action_start)
                    && matches!(finding.evidence, EvidenceLevel::Hard | EvidenceLevel::Exact)
            }) {
                add_candidate(
                    &mut candidates,
                    key,
                    100,
                    "hard or exact finding".to_string(),
                );
            }
            let after = turn.after_each_action.last();
            if turn.tokens.len() > 1 {
                add_candidate(
                    &mut candidates,
                    key,
                    70,
                    "mill/removal boundary".to_string(),
                );
            }
            if turn.before.phase != after.map(|state| state.phase.as_str()).unwrap_or("") {
                add_candidate(&mut candidates, key, 65, "phase boundary".to_string());
            }
            if after.is_some_and(|state| state.flying_sides != turn.before.flying_sides) {
                add_candidate(&mut candidates, key, 75, "flying boundary".to_string());
            }
            if turn.before.repetition_current_count >= 2
                || after.is_some_and(|state| state.repetition_current_count >= 2)
            {
                add_candidate(
                    &mut candidates,
                    key,
                    90,
                    "threefold-repetition boundary".to_string(),
                );
            }
            let distance = turn.before.inactivity_boundary_distance.unwrap_or(u32::MAX);
            if distance <= 1 {
                add_candidate(&mut candidates, key, 90, "N-move boundary".to_string());
            }
            if game.source.decisions.iter().any(|decision| {
                turn.action_start <= decision.action_index
                    && decision.action_index < turn.action_end
                    && (decision.depth.is_none_or(|depth| depth == 0)
                        || decision.nodes.is_none_or(|nodes| nodes == 0)
                        || decision.protocol_error.is_some())
            }) {
                add_candidate(
                    &mut candidates,
                    key,
                    95,
                    "search telemetry anomaly".to_string(),
                );
            }
        }

        let mut previous_by_instance = BTreeMap::new();
        for decision in &game.source.decisions {
            let previous =
                previous_by_instance.insert(decision.engine_instance_id.as_str(), decision);
            let Some(previous) = previous else {
                continue;
            };
            let (Some(left), Some(right)) = (previous.score_value, decision.score_value) else {
                continue;
            };
            let score_cliff = (right - left).abs() >= 10;
            let mate_flip = (previous.score_kind.as_deref() == Some("mate")
                || decision.score_kind.as_deref() == Some("mate"))
                && left.signum() != right.signum();
            if score_cliff || mate_flip {
                if decision.engine_role != "candidate" {
                    continue;
                }
                if let Some(turn_slot) = game
                    .logical_turns
                    .iter()
                    .position(|turn| turn.action_start == decision.action_index)
                {
                    add_candidate(
                        &mut candidates,
                        (game_slot, turn_slot),
                        if mate_flip { 90 } else { 60 },
                        if mate_flip {
                            "live mate-sign flip".to_string()
                        } else {
                            "live score cliff".to_string()
                        },
                    );
                }
            }
        }

        let candidate_loser = match game.source.current_white {
            Some(white) => game.source.is_loss_for_candidate().then_some(if white {
                tgf_cli::h2h_trace::H2hActor::White
            } else {
                tgf_cli::h2h_trace::H2hActor::Black
            }),
            None => game.source.loser(),
        };
        if let Some(loser) = candidate_loser
            && let Some((turn_slot, _)) =
                game.logical_turns
                    .iter()
                    .enumerate()
                    .rev()
                    .find(|(_, turn)| {
                        turn.actor == loser && turn.action_start >= game.source.opening_moves.len()
                    })
        {
            add_candidate(
                &mut candidates,
                (game_slot, turn_slot),
                85,
                "at least one suspect per loss".to_string(),
            );
        }
    }
    let mut values = candidates.into_values().collect::<Vec<_>>();
    values.sort_by(|left, right| {
        right
            .priority
            .cmp(&left.priority)
            .then_with(|| left.game_slot.cmp(&right.game_slot))
            .then_with(|| left.turn_slot.cmp(&right.turn_slot))
    });
    values
}

fn add_candidate(
    candidates: &mut BTreeMap<(usize, usize), Candidate>,
    key: (usize, usize),
    priority: u32,
    reason: String,
) {
    let candidate = candidates.entry(key).or_insert_with(|| Candidate {
        game_slot: key.0,
        turn_slot: key.1,
        priority,
        reasons: BTreeSet::new(),
    });
    candidate.priority = candidate.priority.max(priority);
    candidate.reasons.insert(reason);
}

fn build_matrix(
    turn: &super::model::LogicalTurnRecord,
    options: &MillVariantOptions,
    triage: u64,
    confirm: u64,
) -> DeterministicSearchMatrix {
    let rules = MillRules::new(options.clone());
    let mut probes = Vec::with_capacity(4);
    for budget in [triage, confirm] {
        for algorithm in [ProbeAlgorithm::Pvs, ProbeAlgorithm::Mtdf] {
            probes.push(probe(turn, options, &rules, budget, algorithm));
        }
    }
    classify_matrix(probes, &turn.tokens, triage, confirm)
}

fn probe(
    turn: &super::model::LogicalTurnRecord,
    options: &MillVariantOptions,
    rules: &MillRules,
    node_budget: u64,
    algorithm: ProbeAlgorithm,
) -> SearchProbeEvidence {
    let best = search_complete_turn(
        rules,
        options,
        turn.root,
        &turn.root_history,
        node_budget,
        algorithm,
    );
    let best = match best {
        Ok(best) => best,
        Err(error) => return failed_probe(algorithm, node_budget, error),
    };
    let played = evaluate_played_turn(
        rules,
        options,
        turn,
        node_budget,
        best.completed_depth.saturating_sub(1),
        algorithm,
    );
    match played {
        Ok((played_score, played_nodes)) => SearchProbeEvidence {
            algorithm: algorithm.name().to_string(),
            node_budget,
            status: "complete".to_string(),
            selected_turn: best.selected_turn,
            selected_score: Some(best.score),
            played_score: Some(played_score),
            score_gap: Some(best.score.saturating_sub(played_score)),
            nodes: best.nodes.saturating_add(played_nodes),
            completed_depth: Some(best.completed_depth),
            error: None,
        },
        Err(error) => failed_probe(algorithm, node_budget, error),
    }
}

fn failed_probe(algorithm: ProbeAlgorithm, node_budget: u64, error: String) -> SearchProbeEvidence {
    SearchProbeEvidence {
        algorithm: algorithm.name().to_string(),
        node_budget,
        status: "unresolved".to_string(),
        selected_turn: Vec::new(),
        selected_score: None,
        played_score: None,
        score_gap: None,
        nodes: 0,
        completed_depth: None,
        error: Some(error),
    }
}

fn search_complete_turn(
    rules: &MillRules,
    options: &MillVariantOptions,
    root: GameStateSnapshot,
    root_history: &[GameStateSnapshot],
    node_budget: u64,
    algorithm: ProbeAlgorithm,
) -> Result<SearchRun, String> {
    let root_side = root.side_to_move;
    if root_side != 0 && root_side != 1 {
        return Err("invalid root side".to_string());
    }
    if MillRules::decode_snapshot(root).pending_removals() != [0, 0] {
        return Err("logical search root has pending removal".to_string());
    }
    // Reserve part of the advertised logical-turn budget for a mandatory
    // removal search. Without this reserve an iterative primary search will
    // normally consume the entire budget, leaving every mill-forming result
    // unresolved even though the logical turn itself is the comparison unit.
    let primary_budget = node_budget.saturating_sub(node_budget / 5).max(1);
    let primary = iterative_action_search(options, root, root_history, primary_budget, algorithm)?;
    let mut actions = vec![primary.0];
    let mut tokens = vec![MillUciCodec::encode_action(primary.0)];
    let mut state = rules.apply_with_history(&root, primary.0, root_history);
    let mut history = root_history.to_vec();
    history.push(root);
    let mut nodes = primary.2;
    while !logical_turn_completed(rules, &root, &state) {
        if actions.len() >= 24 {
            return Err("logical continuation exceeded safety limit".to_string());
        }
        let mut legal = ActionList::<256>::new();
        rules.legal_actions(&state, &mut legal);
        if legal.as_slice().is_empty() {
            return Err("logical continuation has no legal action".to_string());
        }
        let action = if legal.len() == 1 {
            legal.as_slice()[0]
        } else {
            let remaining = node_budget.saturating_sub(nodes);
            if remaining == 0 {
                return Err("node budget ended before removal selection".to_string());
            }
            let selected = iterative_action_search(options, state, &history, remaining, algorithm)?;
            nodes = nodes.saturating_add(selected.2);
            selected.0
        };
        let before = state;
        state = rules.apply_with_history(&before, action, &history);
        history.push(before);
        actions.push(action);
        tokens.push(MillUciCodec::encode_action(action));
    }
    Ok(SearchRun {
        selected_turn: tokens,
        score: primary.1,
        nodes,
        completed_depth: primary.3,
    })
}

fn iterative_action_search(
    options: &MillVariantOptions,
    root: GameStateSnapshot,
    history: &[GameStateSnapshot],
    node_budget: u64,
    algorithm: ProbeAlgorithm,
) -> Result<(Action, i32, u64, i32), String> {
    let repetition_history = MillRules::repetition_history_from_snapshots(&root, history);
    let root_resets = MillRules::root_position_resets_repetition_from_snapshots(&root, history);
    let game =
        MillGame::new_with_repetition_context(options.clone(), repetition_history, root_resets);
    let mut workbench = game.build_workbench(&root);
    let mut searcher = Searcher::<MillGame>::new();
    searcher.set_policy(SearchPolicy {
        quiescence_kind_tag: Some(MillActionKind::Remove as i16),
        ..Default::default()
    });
    searcher.clear_tt();
    searcher.set_random_seed(SEARCH_SEED);
    let mut used = 0_u64;
    let mut latest = None;
    let mut guess = 0;
    for depth in 1..=MAX_SEARCH_DEPTH {
        let remaining = node_budget.saturating_sub(used);
        if remaining == 0 {
            break;
        }
        searcher.set_options(SearchOptions {
            depth_extension: true,
            node_limit: Some(remaining),
            time_limit_ms: None,
            allow_null_move: false,
            shuffle_root: false,
            enable_prefetch: false,
            prefetch_all: false,
            enable_aspiration_window: false,
            move_order_context: MoveOrderContext {
                algorithm: algorithm.move_order(),
                skill_level: 30,
                shuffling: false,
                hash_move: None,
                shuffle_seed: SEARCH_SEED,
            },
        });
        let result = match algorithm {
            ProbeAlgorithm::Pvs => searcher.search_pvs(&mut workbench, depth),
            ProbeAlgorithm::Mtdf => searcher.search_mtdf_with_guess(&mut workbench, depth, guess),
        };
        used = used.saturating_add(result.nodes);
        if searcher.was_aborted() {
            break;
        }
        if result.best_action.is_none() || result.draw_reason.is_some() {
            return Err(format!(
                "{} returned no legal best action at depth {depth}",
                algorithm.name()
            ));
        }
        guess = result.score;
        latest = Some((result.best_action, result.score, depth));
        if result.score.abs() > MATE_THRESHOLD {
            break;
        }
    }
    latest
        .map(|(action, score, depth)| (action, score, used, depth))
        .ok_or_else(|| {
            format!(
                "{} exhausted {node_budget} nodes before completing depth 1",
                algorithm.name()
            )
        })
}

fn evaluate_played_turn(
    rules: &MillRules,
    options: &MillVariantOptions,
    turn: &super::model::LogicalTurnRecord,
    node_budget: u64,
    child_depth: i32,
    algorithm: ProbeAlgorithm,
) -> Result<(i32, u64), String> {
    let outcome = rules.outcome(&turn.final_snapshot);
    match outcome.kind {
        OutcomeKind::Win(side) => {
            return Ok((if side == turn.actor.side() { 80 } else { -80 }, 0));
        }
        OutcomeKind::Draw => return Ok((0, 0)),
        OutcomeKind::Ongoing => {}
        _ => return Err("played logical turn has unsupported outcome".to_string()),
    }
    let mut history = turn.root_history.clone();
    let mut state = turn.root;
    for action in &turn.actions {
        let before = state;
        state = rules.apply_with_history(&before, *action, &history);
        history.push(before);
    }
    let repetition_history = MillRules::repetition_history_from_snapshots(&state, &history);
    let root_resets = MillRules::root_position_resets_repetition_from_snapshots(&state, &history);
    let game =
        MillGame::new_with_repetition_context(options.clone(), repetition_history, root_resets);
    let mut workbench = game.build_workbench(&state);
    let mut searcher = Searcher::<MillGame>::new();
    searcher.set_policy(SearchPolicy {
        quiescence_kind_tag: Some(MillActionKind::Remove as i16),
        ..Default::default()
    });
    searcher.clear_tt();
    searcher.set_random_seed(SEARCH_SEED);
    searcher.set_options(SearchOptions {
        depth_extension: true,
        node_limit: Some(node_budget),
        time_limit_ms: None,
        allow_null_move: false,
        shuffle_root: false,
        enable_prefetch: false,
        prefetch_all: false,
        enable_aspiration_window: false,
        move_order_context: MoveOrderContext {
            algorithm: algorithm.move_order(),
            skill_level: 30,
            shuffling: false,
            hash_move: None,
            shuffle_seed: SEARCH_SEED,
        },
    });
    let child_score = if child_depth <= 0 {
        <MillGame as Game>::Evaluator::score(&workbench)
    } else {
        searcher
            .debug_root_probe(&mut workbench, child_depth, i32::MIN + 1, i32::MAX - 1)
            .0
    };
    if searcher.was_aborted() {
        return Err(format!(
            "{} exhausted {node_budget} nodes while scoring the played turn at depth {child_depth}",
            algorithm.name()
        ));
    }
    let root_score = if state.side_to_move == turn.actor.side() {
        child_score
    } else {
        -child_score
    };
    Ok((root_score, searcher.nodes()))
}

fn classify_matrix(
    probes: Vec<SearchProbeEvidence>,
    played: &[String],
    triage: u64,
    confirm: u64,
) -> DeterministicSearchMatrix {
    let complete = probes
        .iter()
        .filter(|probe| probe.status == "complete")
        .collect::<Vec<_>>();
    let all_complete = complete.len() == 4;
    let agreed = all_complete
        .then(|| complete[0].selected_turn.clone())
        .filter(|candidate| {
            complete
                .iter()
                .all(|probe| probe.selected_turn == *candidate)
        });
    let probable = agreed.as_ref().is_some_and(|candidate| {
        candidate != played
            && complete.iter().all(|probe| {
                let selected = probe.selected_score.unwrap_or(i32::MIN);
                let played_score = probe.played_score.unwrap_or(i32::MAX);
                selected > played_score
                    && (probe.score_gap.is_some_and(|gap| gap >= 5)
                        || (selected.abs() > MATE_THRESHOLD
                            && played_score.abs() <= MATE_THRESHOLD))
            })
    });

    let triage_choices = complete
        .iter()
        .filter(|probe| probe.node_budget == triage)
        .map(|probe| probe.selected_turn.clone())
        .collect::<BTreeSet<_>>();
    let confirm_choices = complete
        .iter()
        .filter(|probe| probe.node_budget == confirm)
        .map(|probe| probe.selected_turn.clone())
        .collect::<BTreeSet<_>>();
    let budget_limited = !probable
        && triage_choices.len() == 1
        && triage_choices
            .first()
            .is_some_and(|choice| choice != played)
        && (confirm_choices.len() != 1 || confirm_choices != triage_choices);
    let mut reasons = Vec::new();
    if !all_complete {
        reasons.push("one or more searches did not complete a depth".to_string());
    }
    if all_complete && agreed.is_none() {
        reasons.push("algorithms or budgets selected different turns".to_string());
    }
    if agreed.as_deref() == Some(played) {
        reasons.push("high-budget deterministic search selected the played turn".to_string());
    }
    if agreed.is_some() && !probable && !budget_limited {
        reasons.push("the stable alternative did not clear the 5-point/mate threshold".to_string());
    }
    DeterministicSearchMatrix {
        probes,
        agreed_alternative: agreed,
        probable,
        budget_limited,
        unresolved_reasons: reasons,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn probe(
        algorithm: &str,
        budget: u64,
        selected: &[&str],
        selected_score: i32,
        played_score: i32,
    ) -> SearchProbeEvidence {
        SearchProbeEvidence {
            algorithm: algorithm.to_string(),
            node_budget: budget,
            status: "complete".to_string(),
            selected_turn: selected.iter().map(|value| (*value).to_string()).collect(),
            selected_score: Some(selected_score),
            played_score: Some(played_score),
            score_gap: Some(selected_score - played_score),
            nodes: budget,
            completed_depth: Some(4),
            error: None,
        }
    }

    #[test]
    fn four_agreeing_material_probes_are_probable() {
        let probes = vec![
            probe("pvs", 10, &["a1"], 10, 0),
            probe("mtdf", 10, &["a1"], 10, 0),
            probe("pvs", 20, &["a1"], 12, 0),
            probe("mtdf", 20, &["a1"], 12, 0),
        ];
        let matrix = classify_matrix(probes, &["d1".to_string()], 10, 20);
        assert!(matrix.probable);
        assert!(!matrix.budget_limited);
    }

    #[test]
    fn low_budget_error_corrected_at_confirmation_is_budget_limited() {
        let probes = vec![
            probe("pvs", 10, &["a1"], 10, 0),
            probe("mtdf", 10, &["a1"], 10, 0),
            probe("pvs", 20, &["d1"], 0, 0),
            probe("mtdf", 20, &["d1"], 0, 0),
        ];
        let matrix = classify_matrix(probes, &["d1".to_string()], 10, 20);
        assert!(!matrix.probable);
        assert!(matrix.budget_limited);
    }

    #[test]
    fn disagreement_stays_unresolved() {
        let probes = vec![
            probe("pvs", 10, &["a1"], 10, 0),
            probe("mtdf", 10, &["d1"], 10, 0),
            probe("pvs", 20, &["a1"], 10, 0),
            probe("mtdf", 20, &["d1"], 10, 0),
        ];
        let matrix = classify_matrix(probes, &["g1".to_string()], 10, 20);
        assert!(!matrix.probable);
        assert!(!matrix.budget_limited);
        assert!(!matrix.unresolved_reasons.is_empty());
    }
}
