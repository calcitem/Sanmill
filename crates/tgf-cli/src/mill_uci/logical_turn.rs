// SPDX-License-Identifier: AGPL-3.0-or-later

//! One-budget search for a complete Mill logical turn.
//!
//! A normal UCI move and its mandatory removal are separate protocol actions.
//! This explicit CLI extension keeps them under one aggregate node budget and
//! returns them together. The normal UCI and Flutter/FRB paths do not call
//! this module.

use serde::Serialize;
use serde_json::json;
use tgf_core::{Action, ActionList, Game, GameRules, GameStateSnapshot, OutcomeKind};
use tgf_mill::{MillGame, MillPlyCount, MillRules, MillUciCodec, MillVariantOptions};
use tgf_search::{SearchOptions, SearchResult, Searcher, SharedTt};

use super::board::{GoOptions, ParsedPosition};
use super::{
    EngineConfig, UciMachineError, effective_search_depth, eval_weights_from_env,
    mtdf_initial_guess, run_algorithm_at_depth, search_options_for_go,
};

const LOGICAL_TURN_PROTOCOL_VERSION: u32 = 1;
const LOGICAL_TURN_PREFIX: &str = "info string sanmill_logical_turn ";
const MAX_LOGICAL_TURN_ACTIONS: usize = 24;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct LogicalGoOptions {
    node_budget: u64,
    requested_depth: Option<i32>,
}

#[derive(Clone, Debug)]
struct TurnPrefix {
    actions: Vec<Action>,
    state: GameStateSnapshot,
    history: Vec<GameStateSnapshot>,
}

#[derive(Clone, Debug)]
struct CompletedRootSearch {
    result: SearchResult,
    depth: i32,
    turn: TurnPrefix,
}

#[derive(Clone, Copy, Debug, Default)]
struct NodeUsage {
    primary: u64,
    removal: u64,
    search_calls: u32,
}

impl NodeUsage {
    fn total(self) -> u64 {
        self.primary.saturating_add(self.removal)
    }

    fn remaining(self, budget: u64) -> u64 {
        budget.saturating_sub(self.total())
    }

    fn record_primary(&mut self, used: u64, budget: u64) -> Result<(), UciMachineError> {
        self.primary = self.primary.saturating_add(used);
        self.search_calls = self.search_calls.saturating_add(1);
        self.check_budget(budget)
    }

    fn record_removal(&mut self, used: u64, budget: u64) -> Result<(), UciMachineError> {
        self.removal = self.removal.saturating_add(used);
        self.search_calls = self.search_calls.saturating_add(1);
        self.check_budget(budget)
    }

    fn check_budget(self, budget: u64) -> Result<(), UciMachineError> {
        if self.total() <= budget {
            Ok(())
        } else {
            Err(logical_error(
                "logical_node_budget_exceeded",
                format!(
                    "search consumed {} nodes under a requested budget of {budget}",
                    self.total()
                ),
            ))
        }
    }
}

#[derive(Serialize)]
struct ModelAction {
    from: Option<String>,
    to: String,
    capture: Option<String>,
}

#[derive(Serialize)]
struct LogicalTurnResponse {
    protocol_version: u32,
    status: &'static str,
    full_turn_actions: Vec<String>,
    logical_move_id: String,
    model_action: ModelAction,
    logical_ply_delta: u8,
    resulting_fen: String,
    resulting_side_to_move: Option<&'static str>,
    terminal: bool,
    winner: Option<&'static str>,
    winner_code: Option<i8>,
    outcome_reason: String,
    effective_depth: i32,
    completed_depth: i32,
    score_kind: &'static str,
    score: i32,
    score_perspective: &'static str,
    node_budget: u64,
    primary_nodes: u64,
    removal_nodes: u64,
    total_nodes: u64,
    search_calls: u32,
}

pub(super) fn run_logical_go(
    line: &str,
    options: &MillVariantOptions,
    position: &ParsedPosition,
    cfg: &EngineConfig,
    qsearch_max_depth: i32,
    shared_tt: SharedTt,
) -> Result<String, UciMachineError> {
    if !cfg.strict_failure_policy {
        return Err(logical_error(
            "strict_policy_required",
            "`go logical` requires `StrictFailurePolicy=true`",
        ));
    }
    let go = parse_logical_go(line)?;
    if !matches!(cfg.algorithm, 0..=2) {
        return Err(logical_error(
            "logical_search_algorithm_unsupported",
            format!(
                "`go logical` supports alpha-beta and MTD(f), not Algorithm={}",
                cfg.algorithm
            ),
        ));
    }

    let rules = MillRules::new(options.clone());
    let outcome = rules.outcome(&position.state);
    if !matches!(outcome.kind, OutcomeKind::Ongoing) {
        return Ok(terminal_info_line(go.node_budget, &outcome));
    }
    let decoded = MillRules::decode_snapshot(position.state);
    if decoded.pending_removals() != [0, 0] || decoded.action_tag() == 2 {
        return Err(logical_error(
            "logical_turn_unstable_position",
            "`go logical` requires a stable root with no pending removal",
        ));
    }

    let effective_depth = effective_search_depth(
        options,
        &position.state,
        go.requested_depth.unwrap_or(0),
        cfg,
    )
    .max(1);
    let root_repetition_history =
        MillRules::repetition_history_from_snapshots(&position.state, &position.history);
    let root_position_resets_repetition = MillRules::root_position_resets_repetition_from_snapshots(
        &position.state,
        &position.history,
    );
    let mut game = MillGame::new_with_repetition_context(
        options.clone(),
        root_repetition_history,
        root_position_resets_repetition,
    );
    if let Some(weights) = eval_weights_from_env() {
        game.set_eval_weights(weights);
    }
    let mut workbench = game.build_workbench(&position.state);
    let mut searcher = super::mill_searcher_with_shared_tt(shared_tt);
    searcher.clear_tt();
    searcher.set_qsearch_max_depth(qsearch_max_depth);

    let mut usage = NodeUsage::default();
    let mut first_guess = mtdf_initial_guess(cfg, position.state.side_to_move);
    let mut latest_completed = None;
    for depth in primary_depths(effective_depth, cfg.ids_enabled) {
        let remaining = usage.remaining(go.node_budget);
        if remaining == 0 {
            break;
        }
        searcher.set_options(logical_search_options(cfg, depth, remaining));
        let result = run_algorithm_at_depth(&mut searcher, &mut workbench, cfg, depth, first_guess);
        let used = result.nodes;
        usage.record_primary(used, go.node_budget)?;
        let aborted = searcher.was_aborted();
        if !aborted {
            first_guess = result.score;
            let turn = reconstruct_turn_prefix(
                &searcher,
                &rules,
                position.state,
                &position.history,
                &result,
            )?;
            latest_completed = Some(CompletedRootSearch {
                result,
                depth,
                turn,
            });
        }
        if aborted {
            break;
        }
    }

    let Some(mut completed) = latest_completed else {
        return Err(logical_error(
            "logical_turn_budget_exhausted",
            "the node budget ended before any search depth produced a complete primary result",
        ));
    };

    complete_pending_turn(
        &mut completed.turn,
        position.state.side_to_move,
        &rules,
        options,
        cfg,
        qsearch_max_depth,
        effective_depth,
        go.node_budget,
        &mut usage,
        &mut searcher,
    )?;
    validate_complete_turn(&rules, position.state, &position.history, &completed.turn)?;

    let action_tokens = completed
        .turn
        .actions
        .iter()
        .copied()
        .map(MillUciCodec::encode_action)
        .collect::<Vec<_>>();
    let model_action = model_action(&action_tokens)?;
    let final_outcome = rules.outcome(&completed.turn.state);
    let (winner, winner_code) = winner_fields(&final_outcome.kind);
    let output_score = if position.state.side_to_move == 1 {
        -completed.result.score
    } else {
        completed.result.score
    };
    let (score_kind, score) = score_fields(output_score);
    let response = LogicalTurnResponse {
        protocol_version: LOGICAL_TURN_PROTOCOL_VERSION,
        status: "ok",
        logical_move_id: action_tokens.join(""),
        full_turn_actions: action_tokens,
        model_action,
        logical_ply_delta: 1,
        resulting_fen: rules.export_fen(&MillRules::decode_snapshot(completed.turn.state)),
        resulting_side_to_move: side_name(completed.turn.state.side_to_move),
        terminal: !matches!(final_outcome.kind, OutcomeKind::Ongoing),
        winner,
        winner_code,
        outcome_reason: final_outcome.reason,
        effective_depth,
        completed_depth: completed.depth,
        score_kind,
        score,
        score_perspective: "white",
        node_budget: go.node_budget,
        primary_nodes: usage.primary,
        removal_nodes: usage.removal,
        total_nodes: usage.total(),
        search_calls: usage.search_calls,
    };
    let payload = serde_json::to_string(&response)
        .expect("serializing a logical-turn response must not fail");
    Ok(format!("{LOGICAL_TURN_PREFIX}{payload}"))
}

fn parse_logical_go(line: &str) -> Result<LogicalGoOptions, UciMachineError> {
    let tokens = line.split_whitespace().collect::<Vec<_>>();
    if tokens.get(..2) != Some(&["go", "logical"]) {
        return Err(logical_error(
            "logical_go_protocol_error",
            "command must start with `go logical`",
        ));
    }
    let mut node_budget = None;
    let mut requested_depth = None;
    let mut index = 2;
    while index < tokens.len() {
        let key = tokens[index];
        let Some(value) = tokens.get(index + 1) else {
            return Err(logical_error(
                "logical_go_protocol_error",
                format!("missing value after `{key}`"),
            ));
        };
        match key {
            "nodes" if node_budget.is_none() => {
                node_budget = Some(value.parse::<u64>().map_err(|_| {
                    logical_error(
                        "logical_go_protocol_error",
                        format!("invalid node budget `{value}`"),
                    )
                })?);
            }
            "depth" if requested_depth.is_none() => {
                let depth = value.parse::<i32>().map_err(|_| {
                    logical_error(
                        "logical_go_protocol_error",
                        format!("invalid depth `{value}`"),
                    )
                })?;
                if depth <= 0 {
                    return Err(logical_error(
                        "logical_go_protocol_error",
                        "logical search depth must be positive",
                    ));
                }
                requested_depth = Some(depth);
            }
            "nodes" | "depth" => {
                return Err(logical_error(
                    "logical_go_protocol_error",
                    format!("duplicate `{key}` parameter"),
                ));
            }
            _ => {
                return Err(logical_error(
                    "logical_go_protocol_error",
                    format!("unsupported `go logical` parameter `{key}`"),
                ));
            }
        }
        index += 2;
    }
    let node_budget = node_budget.ok_or_else(|| {
        logical_error(
            "logical_go_protocol_error",
            "`go logical` requires an explicit `nodes N` budget",
        )
    })?;
    if node_budget == 0 {
        return Err(logical_error(
            "logical_go_protocol_error",
            "logical node budget must be positive",
        ));
    }
    Ok(LogicalGoOptions {
        node_budget,
        requested_depth,
    })
}

fn primary_depths(effective_depth: i32, ids_enabled: bool) -> Vec<i32> {
    if ids_enabled {
        (1..=effective_depth).collect()
    } else {
        vec![effective_depth]
    }
}

fn logical_search_options(cfg: &EngineConfig, depth: i32, node_limit: u64) -> SearchOptions {
    search_options_for_go(
        cfg,
        &GoOptions {
            depth,
            depth_is_explicit: true,
            movetime_ms: None,
            node_limit: Some(node_limit),
            topn: None,
        },
    )
}

fn reconstruct_turn_prefix(
    searcher: &Searcher<MillGame>,
    rules: &MillRules,
    root: GameStateSnapshot,
    root_history: &[GameStateSnapshot],
    result: &SearchResult,
) -> Result<TurnPrefix, UciMachineError> {
    let mut legal = ActionList::<256>::new();
    rules.legal_actions(&root, &mut legal);
    if result.best_action.is_none()
        || result.draw_reason.is_some()
        || !legal.as_slice().contains(&result.best_action)
    {
        return Err(logical_error(
            "logical_search_missing_primary",
            "a completed primary search did not return a legal action",
        ));
    }

    let root_side = root.side_to_move;
    let mut prefix = TurnPrefix {
        actions: Vec::new(),
        state: root,
        history: root_history.to_vec(),
    };
    apply_turn_action(rules, &mut prefix, result.best_action)?;
    if logical_turn_complete(rules, root_side, &prefix.state) {
        return Ok(prefix);
    }

    let repetition_history =
        MillRules::repetition_history_from_snapshots(&prefix.state, &prefix.history);
    let root_resets =
        MillRules::root_position_resets_repetition_from_snapshots(&prefix.state, &prefix.history);
    let game = MillGame::new_with_repetition_context(
        rules.options().clone(),
        repetition_history,
        root_resets,
    );
    let mut workbench = game.build_workbench(&prefix.state);
    for action in searcher.principal_variation(
        &mut workbench,
        MAX_LOGICAL_TURN_ACTIONS.saturating_sub(prefix.actions.len()),
    ) {
        apply_turn_action(rules, &mut prefix, action)?;
        if logical_turn_complete(rules, root_side, &prefix.state) {
            break;
        }
    }
    apply_forced_continuations(rules, root_side, &mut prefix)?;
    Ok(prefix)
}

#[allow(clippy::too_many_arguments)]
fn complete_pending_turn(
    turn: &mut TurnPrefix,
    root_side: i8,
    rules: &MillRules,
    options: &MillVariantOptions,
    cfg: &EngineConfig,
    qsearch_max_depth: i32,
    effective_depth: i32,
    node_budget: u64,
    usage: &mut NodeUsage,
    searcher: &mut Searcher<MillGame>,
) -> Result<(), UciMachineError> {
    while !logical_turn_complete(rules, root_side, &turn.state) {
        if turn.actions.len() >= MAX_LOGICAL_TURN_ACTIONS {
            return Err(logical_error(
                "logical_turn_continuation_limit",
                "logical turn exceeded the continuation safety limit",
            ));
        }
        let mut legal = ActionList::<256>::new();
        rules.legal_actions(&turn.state, &mut legal);
        if legal.as_slice().is_empty() {
            return Err(logical_error(
                "logical_turn_missing_continuation",
                "the position requires another same-side action but none is legal",
            ));
        }
        if legal.len() == 1 {
            apply_turn_action(rules, turn, legal.as_slice()[0])?;
            continue;
        }

        let remaining = usage.remaining(node_budget);
        if remaining == 0 {
            return Err(logical_error(
                "logical_turn_budget_exhausted",
                "the total node budget ended before a mandatory removal was selected",
            ));
        }
        let repetition_history =
            MillRules::repetition_history_from_snapshots(&turn.state, &turn.history);
        let root_resets =
            MillRules::root_position_resets_repetition_from_snapshots(&turn.state, &turn.history);
        let mut game =
            MillGame::new_with_repetition_context(options.clone(), repetition_history, root_resets);
        if let Some(weights) = eval_weights_from_env() {
            game.set_eval_weights(weights);
        }
        let mut workbench = game.build_workbench(&turn.state);
        let mut selected = None;
        let mut first_guess = 0;
        for depth in primary_depths(effective_depth, cfg.ids_enabled) {
            let remaining = usage.remaining(node_budget);
            if remaining == 0 {
                break;
            }
            searcher.set_options(logical_search_options(cfg, depth, remaining));
            searcher.set_qsearch_max_depth(qsearch_max_depth);
            let result = run_algorithm_at_depth(searcher, &mut workbench, cfg, depth, first_guess);
            usage.record_removal(result.nodes, node_budget)?;
            let aborted = searcher.was_aborted();
            if !aborted
                && !result.best_action.is_none()
                && result.draw_reason.is_none()
                && legal.as_slice().contains(&result.best_action)
            {
                first_guess = result.score;
                selected = Some(result.best_action);
            }
            if aborted {
                break;
            }
        }
        let action = selected.ok_or_else(|| {
            logical_error(
                "logical_turn_budget_exhausted",
                "the remaining node budget did not produce a legal mandatory removal",
            )
        })?;
        apply_turn_action(rules, turn, action)?;
        apply_forced_continuations(rules, root_side, turn)?;
    }
    Ok(())
}

fn apply_forced_continuations(
    rules: &MillRules,
    root_side: i8,
    turn: &mut TurnPrefix,
) -> Result<(), UciMachineError> {
    while !logical_turn_complete(rules, root_side, &turn.state) {
        let mut legal = ActionList::<256>::new();
        rules.legal_actions(&turn.state, &mut legal);
        if legal.len() != 1 {
            break;
        }
        apply_turn_action(rules, turn, legal.as_slice()[0])?;
        if turn.actions.len() >= MAX_LOGICAL_TURN_ACTIONS {
            return Err(logical_error(
                "logical_turn_continuation_limit",
                "logical turn exceeded the continuation safety limit",
            ));
        }
    }
    Ok(())
}

fn apply_turn_action(
    rules: &MillRules,
    turn: &mut TurnPrefix,
    action: Action,
) -> Result<(), UciMachineError> {
    let mut legal = ActionList::<256>::new();
    rules.legal_actions(&turn.state, &mut legal);
    if !legal.as_slice().contains(&action) {
        return Err(logical_error(
            "logical_turn_illegal_action",
            format!(
                "search continuation `{}` is not legal",
                MillUciCodec::encode_action(action)
            ),
        ));
    }
    let before = turn.state;
    let after = rules.apply_with_history(&before, action, &turn.history);
    turn.history.push(before);
    turn.actions.push(action);
    turn.state = after;
    Ok(())
}

fn validate_complete_turn(
    rules: &MillRules,
    root: GameStateSnapshot,
    root_history: &[GameStateSnapshot],
    turn: &TurnPrefix,
) -> Result<(), UciMachineError> {
    let terminal = !matches!(rules.outcome(&turn.state).kind, OutcomeKind::Ongoing);
    if turn.state.side_to_move == root.side_to_move && !terminal {
        return Err(logical_error(
            "logical_turn_incomplete",
            "the returned actions did not switch side to move or end the game",
        ));
    }
    if MillRules::decode_snapshot(turn.state).pending_removals() != [0, 0] {
        return Err(logical_error(
            "logical_turn_incomplete",
            "the returned actions leave a pending removal",
        ));
    }

    let mut counts = MillPlyCount::default();
    let mut state = root;
    let mut history = root_history.to_vec();
    for action in turn.actions.iter().copied() {
        let before = state;
        let after = rules.apply_with_history(&before, action, &history);
        counts.record(rules, &before, &after).map_err(|error| {
            logical_error(
                "logical_turn_invalid_state",
                format!("failed to count the returned logical turn: {error}"),
            )
        })?;
        history.push(before);
        state = after;
    }
    if state != turn.state || counts.logical_plies != 1 {
        return Err(logical_error(
            "logical_turn_invalid_delta",
            format!(
                "returned action sequence has logical-ply delta {}",
                counts.logical_plies
            ),
        ));
    }
    Ok(())
}

fn logical_turn_complete(rules: &MillRules, root_side: i8, state: &GameStateSnapshot) -> bool {
    state.side_to_move != root_side || !matches!(rules.outcome(state).kind, OutcomeKind::Ongoing)
}

fn model_action(tokens: &[String]) -> Result<ModelAction, UciMachineError> {
    let Some(primary) = tokens.first() else {
        return Err(logical_error(
            "logical_turn_empty",
            "a successful logical turn must contain a primary action",
        ));
    };
    let (from, to) = if let Some((from, to)) = primary.split_once('-') {
        (Some(from.to_owned()), to.to_owned())
    } else if primary.starts_with('x') {
        return Err(logical_error(
            "logical_turn_missing_primary",
            "a stable logical turn cannot begin with a removal",
        ));
    } else {
        (None, primary.clone())
    };
    let captures = tokens
        .iter()
        .skip(1)
        .filter_map(|token| token.strip_prefix('x'))
        .collect::<Vec<_>>();
    if captures.len() > 1 {
        return Err(logical_error(
            "logical_turn_model_mapping_unsupported",
            "the NMM_LLM {from,to,capture} mapping cannot encode multiple removals",
        ));
    }
    Ok(ModelAction {
        from,
        to,
        capture: captures.first().map(|capture| (*capture).to_owned()),
    })
}

fn score_fields(output_score: i32) -> (&'static str, i32) {
    const VALUE_MATE: i32 = 80;
    const VALUE_MATE_IN_MAX_PLY: i32 = 48;
    if output_score.abs() > VALUE_MATE_IN_MAX_PLY {
        let mate_in = if output_score > 0 {
            (VALUE_MATE - output_score + 1) / 2
        } else {
            -(VALUE_MATE + output_score + 1) / 2
        };
        ("mate", mate_in)
    } else {
        ("cp", output_score)
    }
}

fn winner_fields(kind: &OutcomeKind) -> (Option<&'static str>, Option<i8>) {
    match kind {
        OutcomeKind::Win(0) => (Some("white"), Some(0)),
        OutcomeKind::Win(1) => (Some("black"), Some(1)),
        OutcomeKind::Win(side) => (None, Some(*side)),
        _ => (None, None),
    }
}

fn side_name(side: i8) -> Option<&'static str> {
    match side {
        0 => Some("white"),
        1 => Some("black"),
        _ => None,
    }
}

fn terminal_info_line(node_budget: u64, outcome: &tgf_core::Outcome) -> String {
    let (winner, winner_code) = winner_fields(&outcome.kind);
    let payload = json!({
        "protocol_version": LOGICAL_TURN_PROTOCOL_VERSION,
        "status": "terminal",
        "full_turn_actions": [],
        "logical_ply_delta": 0,
        "terminal": true,
        "winner": winner,
        "winner_code": winner_code,
        "outcome_reason": &outcome.reason,
        "node_budget": node_budget,
        "primary_nodes": 0,
        "removal_nodes": 0,
        "total_nodes": 0,
        "search_calls": 0,
    });
    format!("{LOGICAL_TURN_PREFIX}{payload}")
}

fn logical_error(code: &'static str, message: impl Into<String>) -> UciMachineError {
    UciMachineError::new(code, "go logical", message)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::mill_uci::board::parse_position_command_strict;

    #[test]
    fn parser_requires_one_positive_node_budget() {
        assert_eq!(
            parse_logical_go("go logical nodes 500 depth 12").unwrap(),
            LogicalGoOptions {
                node_budget: 500,
                requested_depth: Some(12),
            }
        );
        for invalid in [
            "go logical",
            "go logical nodes 0",
            "go logical nodes nope",
            "go logical nodes 10 nodes 20",
            "go logical movetime 10",
        ] {
            assert!(parse_logical_go(invalid).is_err(), "{invalid}");
        }
    }

    #[test]
    fn placement_and_removal_map_to_one_model_action() {
        let mapped = model_action(&["a7".to_owned(), "xa1".to_owned()]).unwrap();
        assert_eq!(mapped.from, None);
        assert_eq!(mapped.to, "a7");
        assert_eq!(mapped.capture.as_deref(), Some("a1"));

        let mapped = model_action(&["d6-d5".to_owned(), "xd1".to_owned()]).unwrap();
        assert_eq!(mapped.from.as_deref(), Some("d6"));
        assert_eq!(mapped.to, "d5");
        assert_eq!(mapped.capture.as_deref(), Some("d1"));
    }

    #[test]
    fn complete_turn_validation_counts_mill_and_removal_once() {
        let rules = MillRules::default();
        let root =
            parse_position_command_strict(&rules, "position startpos moves d7 a1 g7 d1").unwrap();
        let mut turn = TurnPrefix {
            actions: Vec::new(),
            state: root.state,
            history: root.history.clone(),
        };
        let primary = MillUciCodec::decode_action(&turn.state, "a7").unwrap();
        apply_turn_action(&rules, &mut turn, primary).unwrap();
        let removal = MillUciCodec::decode_action(&turn.state, "xa1").unwrap();
        apply_turn_action(&rules, &mut turn, removal).unwrap();

        validate_complete_turn(&rules, root.state, &root.history, &turn).unwrap();
    }

    #[test]
    fn complete_turn_can_remove_when_every_enemy_piece_is_in_a_mill() {
        let rules = MillRules::default();
        let root = parse_position_command_strict(
            &rules,
            "position fen ********/**OO****/***@@@** w p p 2 7 3 6 0 0 -1 -1 -1 -1 0 0 1 ids:nodes",
        )
        .unwrap();
        let mut turn = TurnPrefix {
            actions: Vec::new(),
            state: root.state,
            history: root.history.clone(),
        };
        let primary = MillUciCodec::decode_action(&turn.state, "f6").unwrap();
        apply_turn_action(&rules, &mut turn, primary).unwrap();

        let mut legal_removals = ActionList::<256>::new();
        rules.legal_actions(&turn.state, &mut legal_removals);
        let labels = legal_removals
            .as_slice()
            .iter()
            .copied()
            .map(MillUciCodec::encode_action)
            .collect::<Vec<_>>();
        assert_eq!(labels, ["xa1", "xd1", "xg1"]);

        apply_turn_action(&rules, &mut turn, legal_removals.as_slice()[0]).unwrap();
        validate_complete_turn(&rules, root.state, &root.history, &turn).unwrap();
    }
}
