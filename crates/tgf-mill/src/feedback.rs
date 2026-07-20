// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

//! Rule-aware, cold-path evidence extraction for move feedback.
//!
//! This module deliberately sits outside move generation, evaluation, and
//! search. Callers first finish MultiPV search, then replay the played turn
//! and the small candidate set here. Consequently merely compiling move
//! feedback into the engine has no cost in normal play or search hot paths.

use tgf_core::{Action, ActionList, GameRules, GameStateSnapshot, OutcomeKind};

use crate::{
    CaptureRuleConfig, MillActionKind, MillBoardFullAction, MillFormationActionInPlacingPhase,
    MillPhase, MillRules, MillState, StalemateAction,
};

/// Strategy capabilities derived from concrete rules and topology.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RuleStrategyProfile {
    pub topology_name: String,
    pub standard_topology: bool,
    pub node_degrees: Vec<u8>,
    pub high_connection_nodes: Vec<u16>,
    pub channel_nodes: Vec<u16>,
    pub has_independent_placing_phase: bool,
    pub may_move_in_placing_phase: bool,
    pub may_fly: bool,
    pub fly_piece_count: u8,
    pub pieces_at_least_count: u8,
    pub removes_from_board_on_placing_mill: bool,
    pub removes_from_hand_on_placing_mill: bool,
    pub delays_placing_mill_reward: bool,
    pub reward_based_on_mill_count: bool,
    pub may_remove_multiple: bool,
    pub may_remove_from_mills_always: bool,
    pub reusable_mills: bool,
    pub restricted_repeated_mills: bool,
    pub one_time_mills: bool,
    pub has_custodian_capture: bool,
    pub has_intervention_capture: bool,
    pub has_leap_capture: bool,
    pub stalemate_is_loss: bool,
    pub stalemate_is_draw: bool,
    pub stalemate_changes_turn_or_removes: bool,
    pub has_n_move_draw: bool,
    pub has_endgame_n_move_draw: bool,
    pub has_threefold_draw: bool,
    pub standard_strategy_compatible: bool,
    pub perfect_database_compatible: bool,
    pub trap_patch_compatible: bool,
}

impl RuleStrategyProfile {
    pub fn derive(rules: &MillRules) -> Self {
        let options = rules.options();
        let topology = GameRules::topology(rules);
        let node_degrees: Vec<u8> = (0..topology.node_count())
            .map(|node| topology.neighbors(node).len() as u8)
            .collect();
        let maximum_degree = node_degrees.iter().copied().max().unwrap_or(0);
        let high_connection_nodes = node_degrees
            .iter()
            .enumerate()
            .filter_map(|(node, &degree)| {
                (degree == maximum_degree && maximum_degree > 0).then_some(node as u16)
            })
            .collect();
        let channel_nodes = node_degrees
            .iter()
            .enumerate()
            .filter_map(|(node, &degree)| {
                let line_count = topology
                    .line_groups()
                    .iter()
                    .filter(|line| line.contains(&(node as u16)))
                    .count();
                (degree >= 3 && line_count >= 2).then_some(node as u16)
            })
            .collect();
        let standard_topology = topology.name() == "mill.24.standard";
        let standard_reward = options.mill_formation_action_in_placing_phase
            == MillFormationActionInPlacingPhase::RemoveOpponentsPieceFromBoard;
        let no_special_capture = !capture_enabled(&options.custodian_capture)
            && !capture_enabled(&options.intervention_capture)
            && !capture_enabled(&options.leap_capture);
        let standard_strategy_compatible = standard_topology
            && options.piece_count == 9
            && options.fly_piece_count == 3
            && options.pieces_at_least_count == 3
            && options.may_fly
            && standard_reward
            && !options.may_move_in_placing_phase
            && !options.may_remove_multiple
            && !options.restrict_repeated_mills_formation
            && !options.one_time_use_mill
            && !options.stop_placing_when_two_empty_squares
            && options.board_full_action == MillBoardFullAction::FirstPlayerLose
            && options.stalemate_action == StalemateAction::EndWithStalemateLoss
            && no_special_capture;

        // The bundled tablebase and trap patch are both mined for the exact
        // standard rules fingerprint. Draw counters do not alter their
        // position sectors, but every move/capture/topology rule does.
        let perfect_database_common = options.fly_piece_count == 3
            && options.pieces_at_least_count == 3
            && options.may_fly
            && standard_reward
            && options.board_full_action == MillBoardFullAction::FirstPlayerLose
            && options.stalemate_action == StalemateAction::EndWithStalemateLoss
            && !options.may_remove_from_mills_always
            && !options.may_remove_multiple
            && !options.restrict_repeated_mills_formation
            && !options.one_time_use_mill
            && no_special_capture;
        let standard_board_database_shape = standard_topology
            && matches!(
                (options.piece_count, options.may_move_in_placing_phase),
                (9, false) | (10, true)
            );
        let perfect_database_shape = standard_board_database_shape
            || (options.piece_count == 12
                && options.has_diagonal_lines
                && !options.may_move_in_placing_phase);
        let perfect_database_compatible = perfect_database_common && perfect_database_shape;
        let trap_patch_compatible = perfect_database_common
            && options.piece_count == 9
            && standard_topology
            && !options.may_move_in_placing_phase;

        Self {
            topology_name: topology.name().to_owned(),
            standard_topology,
            node_degrees,
            high_connection_nodes,
            channel_nodes,
            has_independent_placing_phase: !options.may_move_in_placing_phase,
            may_move_in_placing_phase: options.may_move_in_placing_phase,
            may_fly: options.may_fly,
            fly_piece_count: options.fly_piece_count,
            pieces_at_least_count: options.pieces_at_least_count,
            removes_from_board_on_placing_mill: standard_reward,
            removes_from_hand_on_placing_mill: matches!(
                options.mill_formation_action_in_placing_phase,
                MillFormationActionInPlacingPhase::RemoveOpponentsPieceFromHandThenOpponentsTurn
                    | MillFormationActionInPlacingPhase::RemoveOpponentsPieceFromHandThenYourTurn
                    | MillFormationActionInPlacingPhase::OpponentRemovesOwnPiece
            ),
            delays_placing_mill_reward: options.mill_formation_action_in_placing_phase
                == MillFormationActionInPlacingPhase::MarkAndDelayRemovingPieces,
            reward_based_on_mill_count: options.mill_formation_action_in_placing_phase
                == MillFormationActionInPlacingPhase::RemovalBasedOnMillCounts,
            may_remove_multiple: options.may_remove_multiple,
            may_remove_from_mills_always: options.may_remove_from_mills_always,
            reusable_mills: !options.one_time_use_mill
                && !options.restrict_repeated_mills_formation,
            restricted_repeated_mills: options.restrict_repeated_mills_formation,
            one_time_mills: options.one_time_use_mill,
            has_custodian_capture: capture_enabled(&options.custodian_capture),
            has_intervention_capture: capture_enabled(&options.intervention_capture),
            has_leap_capture: capture_enabled(&options.leap_capture),
            stalemate_is_loss: options.stalemate_action == StalemateAction::EndWithStalemateLoss,
            stalemate_is_draw: options.stalemate_action == StalemateAction::EndWithStalemateDraw,
            stalemate_changes_turn_or_removes: !matches!(
                options.stalemate_action,
                StalemateAction::EndWithStalemateLoss | StalemateAction::EndWithStalemateDraw
            ),
            has_n_move_draw: options.n_move_rule > 0,
            has_endgame_n_move_draw: options.endgame_n_move_rule > 0,
            has_threefold_draw: options.threefold_repetition_rule,
            standard_strategy_compatible,
            perfect_database_compatible,
            trap_patch_compatible,
        }
    }
}

fn capture_enabled(config: &CaptureRuleConfig) -> bool {
    config.enabled
        && (config.on_square_edges || config.on_cross_lines || config.on_diagonal_lines)
        && (config.in_placing_phase || config.in_moving_phase)
}

/// A root candidate and the complete atomic action sequence used to replay it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MillFeedbackCandidate {
    pub actions: Vec<Action>,
    pub score: i32,
}

/// Rule facts extracted by replaying the played complete turn.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MillFeedbackEvidence {
    pub complete_turn_legal: bool,
    pub action_kinds: Vec<String>,
    pub phase_before: String,
    pub phase_after: String,
    pub side_before: i8,
    pub side_after: i8,
    pub pieces_on_board_before: [u8; 2],
    pub pieces_on_board_after: [u8; 2],
    pub pieces_in_hand_before: [u8; 2],
    pub pieces_in_hand_after: [u8; 2],
    pub pending_removals_before: [u8; 2],
    pub pending_removals_after: [u8; 2],
    pub delayed_marked_before: u32,
    pub delayed_marked_after: u32,
    pub legal_actions_before: u32,
    pub legal_replies_after: u32,
    pub mover_board_loss: u8,
    pub opponent_board_loss: u8,
    pub mover_hand_loss: u8,
    pub opponent_hand_loss: u8,
    pub removal_rights_created: u8,
    pub formed_mill_with_reward: bool,
    pub actual_special_capture: bool,
    pub selected_capture_target: bool,
    pub phase_transition: bool,
    pub entered_flying: bool,
    pub opponent_entered_flying: bool,
    pub outcome_before: String,
    pub outcome_after: String,
    pub outcome_reason_after: String,
    pub mobility_delta: i32,
    pub draw_counter_delta: i32,
}

/// Cross-candidate interpretation kept separate from symbol classification.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct MoveContextAssessment {
    pub forced: bool,
    pub equivalent: bool,
    pub routine_gain: bool,
    pub created_opportunity: bool,
    pub missed_opportunity: bool,
    pub deferred_opportunity: bool,
    pub replaced_opportunity: bool,
    pub compensated_concession: bool,
    pub initiative_swing: bool,
    pub mobility_swing: bool,
    pub phase_transition_impact: bool,
    pub draw_resource_impact: bool,
}

/// Complete rule evidence returned to UI/review classifiers.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MillFeedbackReport {
    pub profile: RuleStrategyProfile,
    pub evidence: MillFeedbackEvidence,
    pub context: MoveContextAssessment,
}

/// Replay a played complete turn and candidate turns outside the search path.
pub fn assess_move_feedback(
    rules: &MillRules,
    root: GameStateSnapshot,
    played_actions: &[Action],
    candidates: &[MillFeedbackCandidate],
) -> MillFeedbackReport {
    let profile = RuleStrategyProfile::derive(rules);
    let played = replay_turn(rules, root, played_actions);
    let candidate_replays: Vec<ReplayResult> = candidates
        .iter()
        .map(|candidate| replay_turn(rules, root, &candidate.actions))
        .collect();
    let root_legal = legal_action_count(rules, &root);
    let equivalent = candidate_replays.iter().any(|candidate| {
        candidate.legal
            && played.legal
            && candidate.signature == played.signature
            && candidate.actions != played_actions
    });
    let best_reward = candidate_replays
        .iter()
        .filter(|candidate| candidate.legal)
        .map(|candidate| immediate_reward(&candidate.evidence))
        .max()
        .unwrap_or(0);
    let played_reward = immediate_reward(&played.evidence);
    let best_score = candidates.iter().map(|candidate| candidate.score).max();
    let played_score = candidates
        .iter()
        .find(|candidate| candidate.actions == played_actions)
        .map(|candidate| candidate.score);
    let near_best =
        matches!((best_score, played_score), (Some(best), Some(played)) if best - played <= 3);
    let missed_opportunity = best_reward > played_reward;
    let context = MoveContextAssessment {
        forced: root_legal == 1,
        equivalent,
        routine_gain: played.evidence.formed_mill_with_reward
            || played.evidence.selected_capture_target,
        created_opportunity: played.evidence.removal_rights_created > 0
            || played.evidence.actual_special_capture,
        missed_opportunity,
        deferred_opportunity: missed_opportunity && near_best,
        replaced_opportunity: missed_opportunity
            && matches!((best_score, played_score), (Some(best), Some(played)) if played >= best),
        compensated_concession: (played.evidence.mover_board_loss > 0
            || played.evidence.mover_hand_loss > 0)
            && near_best,
        initiative_swing: played.evidence.legal_replies_after > 0
            && played.evidence.legal_replies_after <= 2
            && played.evidence.side_after != played.evidence.side_before,
        mobility_swing: played.evidence.mobility_delta.abs() >= 2,
        phase_transition_impact: played.evidence.phase_transition
            || played.evidence.entered_flying
            || played.evidence.opponent_entered_flying,
        draw_resource_impact: played.evidence.outcome_after == "draw"
            || played.evidence.draw_counter_delta != 1,
    };

    MillFeedbackReport {
        profile,
        evidence: played.evidence,
        context,
    }
}

fn immediate_reward(evidence: &MillFeedbackEvidence) -> u16 {
    u16::from(evidence.opponent_board_loss)
        + u16::from(evidence.opponent_hand_loss)
        + u16::from(evidence.removal_rights_created)
        + u16::from(evidence.actual_special_capture)
}

#[derive(Clone)]
struct ReplayResult {
    actions: Vec<Action>,
    legal: bool,
    evidence: MillFeedbackEvidence,
    signature: PositionSignature,
}

#[derive(Clone, PartialEq, Eq)]
struct PositionSignature {
    board: [i8; 24],
    side_to_move: i8,
    phase: MillPhase,
    action_tag: i16,
    pieces_in_hand: [u8; 2],
    pieces_on_board: [u8; 2],
    pending_removals: [u8; 2],
    outcome: String,
    outcome_reason: String,
}

fn replay_turn(rules: &MillRules, root: GameStateSnapshot, actions: &[Action]) -> ReplayResult {
    let before = MillRules::decode_snapshot(root);
    let mover = before.side_to_move();
    let before_outcome = GameRules::outcome(rules, &root);
    let legal_before = legal_action_count(rules, &root);
    let before_mobility = mover_mobility(rules, &before, mover);
    let mut current = root;
    let mut legal = !actions.is_empty();
    let mut formed_mill_with_reward = false;
    let mut actual_special_capture = false;
    let mut removal_rights_created = 0_u8;

    for action in actions {
        if !GameRules::is_legal(rules, &current, *action) {
            legal = false;
            break;
        }
        let action_before = MillRules::decode_snapshot(current);
        let next = GameRules::apply(rules, &current, *action);
        let action_after = MillRules::decode_snapshot(next);
        let mover_index = usize::try_from(mover).unwrap_or(0).min(1);
        let opponent_index = 1 - mover_index;
        let pending_gain = action_after.pending_removals()[mover_index]
            .saturating_sub(action_before.pending_removals()[mover_index]);
        removal_rights_created = removal_rights_created.saturating_add(pending_gain);
        if action.kind_tag != MillActionKind::Remove as i16 {
            let opponent_board_drop = action_before.pieces_on_board()[opponent_index]
                .saturating_sub(action_after.pieces_on_board()[opponent_index]);
            let opponent_hand_drop = action_before.pieces_in_hand()[opponent_index]
                .saturating_sub(action_after.pieces_in_hand()[opponent_index]);
            let delayed_gain = action_after
                .delayed_marked_pieces()
                .count_ones()
                .saturating_sub(action_before.delayed_marked_pieces().count_ones());
            let closes_mill = action_closes_mill(rules, &action_after, *action, mover);
            let has_rule_reward = pending_gain > 0 || opponent_hand_drop > 0 || delayed_gain > 0;
            formed_mill_with_reward |= closes_mill && has_rule_reward;
            actual_special_capture |= opponent_board_drop > 0 && !has_rule_reward;
        }
        current = next;
    }

    let after = MillRules::decode_snapshot(current);
    let after_outcome = GameRules::outcome(rules, &current);
    let mover_index = usize::try_from(mover).unwrap_or(0).min(1);
    let opponent_index = 1 - mover_index;
    let pieces_on_board_before = before.pieces_on_board();
    let pieces_on_board_after = after.pieces_on_board();
    let pieces_in_hand_before = before.pieces_in_hand();
    let pieces_in_hand_after = after.pieces_in_hand();
    let pending_removals_before = before.pending_removals();
    let pending_removals_after = after.pending_removals();
    let legal_after = legal_action_count(rules, &current);
    let after_mobility = mover_mobility(rules, &after, mover);
    let outcome_after = outcome_name(&after_outcome.kind, mover);
    let evidence = MillFeedbackEvidence {
        complete_turn_legal: legal,
        action_kinds: actions
            .iter()
            .map(|action| action_kind(action.kind_tag))
            .collect(),
        phase_before: phase_name(before.phase()).to_owned(),
        phase_after: phase_name(after.phase()).to_owned(),
        side_before: mover,
        side_after: after.side_to_move(),
        pieces_on_board_before,
        pieces_on_board_after,
        pieces_in_hand_before,
        pieces_in_hand_after,
        pending_removals_before,
        pending_removals_after,
        delayed_marked_before: before.delayed_marked_pieces(),
        delayed_marked_after: after.delayed_marked_pieces(),
        legal_actions_before: legal_before,
        legal_replies_after: legal_after,
        mover_board_loss: pieces_on_board_before[mover_index]
            .saturating_sub(pieces_on_board_after[mover_index]),
        opponent_board_loss: pieces_on_board_before[opponent_index]
            .saturating_sub(pieces_on_board_after[opponent_index]),
        mover_hand_loss: pieces_in_hand_before[mover_index]
            .saturating_sub(pieces_in_hand_after[mover_index]),
        opponent_hand_loss: pieces_in_hand_before[opponent_index]
            .saturating_sub(pieces_in_hand_after[opponent_index]),
        removal_rights_created,
        formed_mill_with_reward,
        actual_special_capture,
        selected_capture_target: actions
            .iter()
            .any(|action| action.kind_tag == MillActionKind::Remove as i16),
        phase_transition: before.phase() != after.phase(),
        entered_flying: entered_flying(rules, &before, &after, mover_index),
        opponent_entered_flying: entered_flying(rules, &before, &after, opponent_index),
        outcome_before: outcome_name(&before_outcome.kind, mover),
        outcome_after,
        outcome_reason_after: after_outcome.reason.clone(),
        mobility_delta: after_mobility - before_mobility,
        draw_counter_delta: i32::from(after.ply_since_capture())
            - i32::from(before.ply_since_capture()),
    };
    let signature = PositionSignature {
        board: *after.board(),
        side_to_move: after.side_to_move(),
        phase: after.phase(),
        action_tag: after.action_tag(),
        pieces_in_hand: after.pieces_in_hand(),
        pieces_on_board: after.pieces_on_board(),
        pending_removals: after.pending_removals(),
        outcome: evidence.outcome_after.clone(),
        outcome_reason: evidence.outcome_reason_after.clone(),
    };
    ReplayResult {
        actions: actions.to_vec(),
        legal,
        evidence,
        signature,
    }
}

fn legal_action_count(rules: &MillRules, snapshot: &GameStateSnapshot) -> u32 {
    let mut actions = ActionList::<256>::new();
    GameRules::legal_actions(rules, snapshot, &mut actions);
    actions.len() as u32
}

fn mover_mobility(rules: &MillRules, state: &MillState, mover: i8) -> i32 {
    let mobility = rules.eval_features(state).mobility_diff;
    if mover == 0 { mobility } else { -mobility }
}

fn action_closes_mill(rules: &MillRules, state: &MillState, action: Action, mover: i8) -> bool {
    if action.kind_tag == MillActionKind::Remove as i16 || action.to_node < 0 {
        return false;
    }
    let to = action.to_node as u16;
    let piece = mover + 1;
    GameRules::topology(rules)
        .line_groups()
        .iter()
        .filter(|line| line.contains(&to))
        .any(|line| {
            line.iter()
                .all(|&node| state.board()[node as usize] == piece)
        })
}

fn entered_flying(rules: &MillRules, before: &MillState, after: &MillState, side: usize) -> bool {
    let options = rules.options();
    options.may_fly
        && before.pieces_on_board()[side] > options.fly_piece_count
        && after.pieces_on_board()[side] <= options.fly_piece_count
        && after.pieces_in_hand()[side] == 0
}

fn action_kind(kind_tag: i16) -> String {
    match kind_tag {
        value if value == MillActionKind::Place as i16 => "place",
        value if value == MillActionKind::Move as i16 => "move",
        value if value == MillActionKind::Remove as i16 => "remove",
        _ => "unknown",
    }
    .to_owned()
}

fn phase_name(phase: MillPhase) -> &'static str {
    match phase {
        MillPhase::Ready => "ready",
        MillPhase::Placing => "placing",
        MillPhase::Moving => "moving",
        MillPhase::GameOver => "gameOver",
    }
}

fn outcome_name(kind: &OutcomeKind, mover: i8) -> String {
    match kind {
        OutcomeKind::Ongoing => "ongoing",
        OutcomeKind::Win(winner) if *winner == mover => "win",
        OutcomeKind::Win(_) | OutcomeKind::WinTeam(_) => "loss",
        OutcomeKind::Draw => "draw",
        OutcomeKind::Abandoned => "abandoned",
    }
    .to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn legal_to(rules: &MillRules, snapshot: &GameStateSnapshot, to: i16) -> Action {
        let mut actions = ActionList::<256>::new();
        rules.legal_actions(snapshot, &mut actions);
        actions
            .iter()
            .copied()
            .find(|action| action.to_node == to)
            .expect("expected legal action")
    }

    #[test]
    fn standard_profile_is_derived_from_rules_and_topology() {
        let profile = RuleStrategyProfile::derive(&MillRules::default());
        assert!(profile.standard_topology);
        assert!(profile.standard_strategy_compatible);
        assert!(profile.reusable_mills);
        assert_eq!(profile.node_degrees.len(), 24);
        assert!(!profile.high_connection_nodes.is_empty());
    }

    #[test]
    fn incompatible_variants_disable_standard_strategy_capabilities() {
        let options = crate::MillVariantOptions {
            has_diagonal_lines: true,
            one_time_use_mill: true,
            ..crate::MillVariantOptions::default()
        };
        let profile = RuleStrategyProfile::derive(&MillRules::new(options));
        assert!(!profile.standard_topology);
        assert!(!profile.standard_strategy_compatible);
        assert!(!profile.reusable_mills);
        assert!(!profile.perfect_database_compatible);
    }

    #[test]
    fn canonical_variants_expose_only_their_actual_rule_capabilities() {
        let dooz = RuleStrategyProfile::derive(&crate::rules_for_preset(2).unwrap());
        assert!(dooz.removes_from_hand_on_placing_mill);
        assert!(!dooz.removes_from_board_on_placing_mill);

        let morabaraba = RuleStrategyProfile::derive(&crate::rules_for_preset(3).unwrap());
        assert!(morabaraba.may_remove_multiple);
        assert!(!morabaraba.perfect_database_compatible);

        let one_time = RuleStrategyProfile::derive(&crate::rules_for_preset(4).unwrap());
        assert!(one_time.one_time_mills);
        assert!(!one_time.reusable_mills);

        let lasker = RuleStrategyProfile::derive(&crate::rules_for_preset(5).unwrap());
        assert!(lasker.may_move_in_placing_phase);
        assert!(!lasker.has_independent_placing_phase);
        assert!(lasker.perfect_database_compatible);

        let delayed = RuleStrategyProfile::derive(&crate::rules_for_preset(7).unwrap());
        assert!(delayed.delays_placing_mill_reward);
        assert!(!delayed.may_fly);

        let zhi_qi = RuleStrategyProfile::derive(&crate::rules_for_preset(8).unwrap());
        assert!(zhi_qi.stalemate_changes_turn_or_removes);

        let counted = RuleStrategyProfile::derive(&crate::rules_for_preset(9).unwrap());
        assert!(counted.reward_based_on_mill_count);
    }

    #[test]
    fn direct_mill_and_capture_are_reported_as_one_complete_turn() {
        let rules = MillRules::default();
        let mut root = rules.initial_state(&[]);
        // White c5, Black d6, White d5, Black f6, then White e5 closes
        // the inner top mill and removes Black d6.
        for to in [7, 8, 0, 9] {
            let action = legal_to(&rules, &root, to);
            root = rules.apply(&root, action);
        }
        let place = legal_to(&rules, &root, 1);
        let pending = rules.apply(&root, place);
        let remove = legal_to(&rules, &pending, 8);
        let report = assess_move_feedback(
            &rules,
            root,
            &[place, remove],
            &[MillFeedbackCandidate {
                actions: vec![place, remove],
                score: 5,
            }],
        );
        assert!(report.evidence.complete_turn_legal);
        assert!(report.evidence.formed_mill_with_reward);
        assert_eq!(report.evidence.opponent_board_loss, 1);
        assert!(report.context.routine_gain);
        assert_eq!(report.evidence.action_kinds, ["place", "remove"]);
    }
}
