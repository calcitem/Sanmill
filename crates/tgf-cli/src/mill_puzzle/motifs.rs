// SPDX-License-Identifier: AGPL-3.0-or-later
// Exact structural predicates for constraint-directed and corpus-mined Mill
// puzzle themes.
//
// Candidate sources only propose promising roots. These predicates inspect
// the Perfect DB-certified shortest logical turns and reject a candidate
// unless every accepted first turn itself exhibits the requested theme.

use std::collections::HashSet;

use perfect_db::PerfectLogicalTurnChoice;
use tgf_core::{Action, ActionList, BoardTopology, GameRules, OutcomeKind};
use tgf_mill::{MillActionKind, MillPhase, MillRules, MillState, MillTopology};

use super::analysis::{RootTurnBreakdown, closes_mill};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum PuzzleMotif {
    Any,
    DualThreat,
    MillBlock,
    MillAbandonment,
    CaptureChoice,
    Zugzwang,
    AllowMill,
    MobilitySqueeze,
    JunctionRelease,
    MillRecovery,
    RightAngleThreat,
    RingTransfer,
}

impl PuzzleMotif {
    pub(super) fn parse(value: &str) -> Self {
        match value {
            "dual-threat" | "dual-mill" | "dual-mills" => Self::DualThreat,
            "mill-block" | "block-mill" => Self::MillBlock,
            "mill-abandonment" | "abandon-mill" => Self::MillAbandonment,
            "capture-choice" | "removal-choice" => Self::CaptureChoice,
            "zugzwang" | "forced-move" => Self::Zugzwang,
            "allow-mill" | "allow-opponent-mill" => Self::AllowMill,
            "mobility-squeeze" | "herding" => Self::MobilitySqueeze,
            "junction-release" | "cardinal-release" => Self::JunctionRelease,
            "mill-recovery" | "feeder" | "feeder-piece" => Self::MillRecovery,
            "right-angle-threat" | "right-angle-fork" => Self::RightAngleThreat,
            "ring-transfer" | "cross-ring" => Self::RingTransfer,
            _ => Self::Any,
        }
    }

    pub(super) fn tag(self) -> Option<&'static str> {
        match self {
            Self::Any => None,
            Self::DualThreat => Some("dual-threat"),
            Self::MillBlock => Some("mill-block"),
            Self::MillAbandonment => Some("mill-abandonment"),
            Self::CaptureChoice => Some("capture-choice"),
            Self::Zugzwang => Some("zugzwang"),
            Self::AllowMill => Some("allow-mill"),
            Self::MobilitySqueeze => Some("mobility-squeeze"),
            Self::JunctionRelease => Some("junction-release"),
            Self::MillRecovery => Some("mill-recovery"),
            Self::RightAngleThreat => Some("right-angle-threat"),
            Self::RingTransfer => Some("ring-transfer"),
        }
    }
}

pub(super) fn matches_required_motif(
    motif: PuzzleMotif,
    rules: &MillRules,
    root: &tgf_core::GameStateSnapshot,
    root_side: i8,
    all_turns: &[PerfectLogicalTurnChoice],
    breakdown: &RootTurnBreakdown,
) -> bool {
    if motif == PuzzleMotif::Any {
        return true;
    }

    assert!(
        !breakdown.shortest_winning.is_empty(),
        "motif classification requires a shortest winning turn"
    );
    breakdown.shortest_winning.iter().all(|choice| {
        shortest_turn_has_motif(motif, rules, root, root_side, choice, all_turns, breakdown)
    })
}

fn shortest_turn_has_motif(
    motif: PuzzleMotif,
    rules: &MillRules,
    root: &tgf_core::GameStateSnapshot,
    root_side: i8,
    choice: &PerfectLogicalTurnChoice,
    all_turns: &[PerfectLogicalTurnChoice],
    breakdown: &RootTurnBreakdown,
) -> bool {
    let primary = choice.actions[0];
    match motif {
        PuzzleMotif::Any => true,
        PuzzleMotif::DualThreat => {
            !closes_mill(rules, root, primary, root_side)
                && open_mill_targets(
                    &state_after_turn(rules, root, choice),
                    root_side,
                    &topology_for(rules),
                )
                .len()
                    >= 2
        }
        PuzzleMotif::MillBlock => {
            !closes_mill(rules, root, primary, root_side)
                && primary.to_node >= 0
                && blocks_accessible_open_mill(
                    &MillRules::decode_snapshot(*root),
                    1 - root_side,
                    primary.to_node as u16,
                    &topology_for(rules),
                )
        }
        PuzzleMotif::MillAbandonment => {
            primary.kind_tag == MillActionKind::Move as i16
                && primary.from_node >= 0
                && !closes_mill(rules, root, primary, root_side)
                && formed_mill_through(
                    &MillRules::decode_snapshot(*root),
                    root_side,
                    primary.from_node as u16,
                    &topology_for(rules),
                )
        }
        PuzzleMotif::CaptureChoice => {
            closes_mill(rules, root, primary, root_side)
                && removal_choice_changes_result(primary, all_turns, breakdown)
        }
        PuzzleMotif::Zugzwang => {
            !closes_mill(rules, root, primary, root_side)
                && leaves_one_forced_move(rules, root, choice, 1 - root_side)
        }
        PuzzleMotif::AllowMill => {
            !closes_mill(rules, root, primary, root_side)
                && leaves_an_accessible_mill(rules, root, choice, 1 - root_side)
        }
        PuzzleMotif::MobilitySqueeze => {
            !closes_mill(rules, root, primary, root_side)
                && squeezes_mobility(rules, root, choice, 1 - root_side)
        }
        PuzzleMotif::JunctionRelease => {
            primary.kind_tag == MillActionKind::Move as i16
                && primary.from_node >= 0
                && primary.to_node >= 0
                && !closes_mill(rules, root, primary, root_side)
                && releases_junction(rules, root, choice, root_side)
        }
        PuzzleMotif::MillRecovery => {
            primary.kind_tag == MillActionKind::Move as i16
                && primary.from_node >= 0
                && primary.to_node >= 0
                && !closes_mill(rules, root, primary, root_side)
                && prepares_mill_recovery(rules, root, choice, root_side)
        }
        PuzzleMotif::RightAngleThreat => {
            primary.to_node >= 0
                && !closes_mill(rules, root, primary, root_side)
                && creates_right_angle_threat(rules, root, choice, root_side)
        }
        PuzzleMotif::RingTransfer => {
            primary.kind_tag == MillActionKind::Move as i16
                && primary.from_node >= 0
                && primary.to_node >= 0
                && !closes_mill(rules, root, primary, root_side)
                && transfers_ring_to_new_threat(rules, root, choice, root_side)
        }
    }
}

fn topology_for(rules: &MillRules) -> MillTopology {
    MillTopology::new(rules.options().has_diagonal_lines)
}

fn state_after_turn(
    rules: &MillRules,
    root: &tgf_core::GameStateSnapshot,
    choice: &PerfectLogicalTurnChoice,
) -> MillState {
    let mut snap = *root;
    for &action in &choice.actions {
        snap = rules.apply(&snap, action);
    }
    MillRules::decode_snapshot(snap)
}

fn snapshot_after_turn(
    rules: &MillRules,
    root: &tgf_core::GameStateSnapshot,
    choice: &PerfectLogicalTurnChoice,
) -> tgf_core::GameStateSnapshot {
    let mut snap = *root;
    for &action in &choice.actions {
        snap = rules.apply(&snap, action);
    }
    snap
}

fn owned(state: &MillState, node: u16, side: i8) -> bool {
    state.board()[node as usize] == side + 1
}

fn empty(state: &MillState, node: u16) -> bool {
    state.board()[node as usize] == 0
}

fn formed_mill_through(state: &MillState, side: i8, node: u16, topology: &MillTopology) -> bool {
    topology
        .line_groups()
        .iter()
        .filter(|line| line.contains(&node))
        .any(|line| line.iter().all(|&candidate| owned(state, candidate, side)))
}

fn open_mill_targets(state: &MillState, side: i8, topology: &MillTopology) -> HashSet<u16> {
    let mut targets = HashSet::new();
    for line in topology.line_groups() {
        let owned_count = line
            .iter()
            .filter(|&&node| owned(state, node, side))
            .count();
        if owned_count != 2 {
            continue;
        }
        if let Some(&target) = line.iter().find(|&&node| empty(state, node)) {
            targets.insert(target);
        }
    }
    targets
}

fn blocks_accessible_open_mill(
    state: &MillState,
    opponent: i8,
    target: u16,
    topology: &MillTopology,
) -> bool {
    if !empty(state, target) {
        return false;
    }
    let target_completes_mill = topology
        .line_groups()
        .iter()
        .filter(|line| line.contains(&target))
        .any(|line| {
            line.iter()
                .filter(|&&node| owned(state, node, opponent))
                .count()
                == 2
        });
    if !target_completes_mill {
        return false;
    }

    can_reach_empty_node(state, opponent, target, topology)
}

fn can_reach_empty_node(state: &MillState, side: i8, target: u16, topology: &MillTopology) -> bool {
    if !empty(state, target) {
        return false;
    }
    let side = side as usize;
    if state.phase() == MillPhase::Placing && state.pieces_in_hand()[side] > 0 {
        return true;
    }
    if state.phase() == MillPhase::Moving
        && state.pieces_in_hand()[side] == 0
        && state.pieces_on_board()[side] <= 3
    {
        return true;
    }
    topology
        .neighbors(target)
        .iter()
        .any(|&from| owned(state, from, side as i8))
}

fn removal_choice_changes_result(
    primary: Action,
    all_turns: &[PerfectLogicalTurnChoice],
    breakdown: &RootTurnBreakdown,
) -> bool {
    let same_primary: Vec<&PerfectLogicalTurnChoice> = all_turns
        .iter()
        .filter(|turn| turn.actions.first() == Some(&primary))
        .collect();
    if same_primary.len() < 2 {
        return false;
    }
    let shortest_count = same_primary
        .iter()
        .filter(|turn| breakdown.shortest_winning.contains(turn))
        .count();
    shortest_count > 0 && shortest_count < same_primary.len()
}

fn leaves_one_forced_move(
    rules: &MillRules,
    root: &tgf_core::GameStateSnapshot,
    choice: &PerfectLogicalTurnChoice,
    defender: i8,
) -> bool {
    let mut snap = *root;
    for &action in &choice.actions {
        snap = rules.apply(&snap, action);
    }
    if snap.side_to_move != defender || rules.outcome(&snap).kind != OutcomeKind::Ongoing {
        return false;
    }
    let state = MillRules::decode_snapshot(snap);
    if state.pieces_on_board()[defender as usize] <= 3 {
        return false;
    }
    let mut legal = ActionList::<256>::new();
    rules.legal_actions(&snap, &mut legal);
    legal.len() == 1
}

fn leaves_an_accessible_mill(
    rules: &MillRules,
    root: &tgf_core::GameStateSnapshot,
    choice: &PerfectLogicalTurnChoice,
    defender: i8,
) -> bool {
    let topology = topology_for(rules);
    let root_state = MillRules::decode_snapshot(*root);
    let targets = open_mill_targets(&root_state, defender, &topology)
        .into_iter()
        .filter(|&target| can_reach_empty_node(&root_state, defender, target, &topology))
        .collect::<HashSet<_>>();
    if targets.is_empty() {
        return false;
    }
    let primary = choice.actions[0];
    if primary.to_node >= 0 && targets.contains(&(primary.to_node as u16)) {
        return false;
    }

    let child = snapshot_after_turn(rules, root, choice);
    if child.side_to_move != defender || rules.outcome(&child).kind != OutcomeKind::Ongoing {
        return false;
    }
    let mut legal = ActionList::<256>::new();
    rules.legal_actions(&child, &mut legal);
    legal
        .as_slice()
        .iter()
        .copied()
        .any(|action| closes_mill(rules, &child, action, defender))
}

fn movement_mobility(state: &MillState, side: i8, topology: &MillTopology) -> Option<usize> {
    let side_index = side as usize;
    if state.phase() != MillPhase::Moving || state.pieces_in_hand()[side_index] != 0 {
        return None;
    }
    let on_board = state.pieces_on_board()[side_index] as usize;
    if on_board <= 3 {
        let empty_count = state.board().iter().filter(|&&piece| piece == 0).count();
        return Some(on_board * empty_count);
    }
    Some(
        (0..state.board().len())
            .filter(|&node| state.board()[node] == side + 1)
            .map(|node| {
                topology
                    .neighbors(node as u16)
                    .iter()
                    .filter(|&&target| empty(state, target))
                    .count()
            })
            .sum(),
    )
}

fn mobility_before_and_after(
    rules: &MillRules,
    root: &tgf_core::GameStateSnapshot,
    choice: &PerfectLogicalTurnChoice,
    side: i8,
) -> Option<(usize, usize)> {
    let topology = topology_for(rules);
    let before = MillRules::decode_snapshot(*root);
    let after = state_after_turn(rules, root, choice);
    Some((
        movement_mobility(&before, side, &topology)?,
        movement_mobility(&after, side, &topology)?,
    ))
}

fn squeezes_mobility(
    rules: &MillRules,
    root: &tgf_core::GameStateSnapshot,
    choice: &PerfectLogicalTurnChoice,
    defender: i8,
) -> bool {
    let Some((before, after)) = mobility_before_and_after(rules, root, choice, defender) else {
        return false;
    };
    after > 0
        && before >= 4
        && before.saturating_sub(after) >= 2
        && after.saturating_mul(4) <= before.saturating_mul(3)
}

fn releases_junction(
    rules: &MillRules,
    root: &tgf_core::GameStateSnapshot,
    choice: &PerfectLogicalTurnChoice,
    root_side: i8,
) -> bool {
    let primary = choice.actions[0];
    let from = primary.from_node as u16;
    let to = primary.to_node as u16;
    let topology = topology_for(rules);
    if topology.neighbors(from).len() != 4
        || topology.neighbors(to).len() >= topology.neighbors(from).len()
    {
        return false;
    }
    let root_state = MillRules::decode_snapshot(*root);
    if formed_mill_through(&root_state, root_side, from, &topology) {
        return false;
    }
    let Some((before, after)) = mobility_before_and_after(rules, root, choice, 1 - root_side)
    else {
        return false;
    };
    after > 0 && after < before
}

fn mill_recovery_links(
    state: &MillState,
    side: i8,
    topology: &MillTopology,
) -> HashSet<(u16, u16)> {
    let mut links = HashSet::new();
    for line in topology.line_groups() {
        if !line.iter().all(|&node| owned(state, node, side)) {
            continue;
        }
        for &mill_node in line {
            for &feeder in topology.neighbors(mill_node) {
                if !line.contains(&feeder) && owned(state, feeder, side) {
                    links.insert((mill_node, feeder));
                }
            }
        }
    }
    links
}

fn prepares_mill_recovery(
    rules: &MillRules,
    root: &tgf_core::GameStateSnapshot,
    choice: &PerfectLogicalTurnChoice,
    root_side: i8,
) -> bool {
    let primary = choice.actions[0];
    let topology = topology_for(rules);
    let before = MillRules::decode_snapshot(*root);
    if before.phase() != MillPhase::Moving
        || formed_mill_through(&before, root_side, primary.from_node as u16, &topology)
    {
        return false;
    }
    let before_links = mill_recovery_links(&before, root_side, &topology);
    let after = state_after_turn(rules, root, choice);
    mill_recovery_links(&after, root_side, &topology)
        .difference(&before_links)
        .any(|&(_, feeder)| feeder == primary.to_node as u16)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
enum LineAxis {
    Horizontal,
    Vertical,
}

fn line_axis(line: &[u16], topology: &MillTopology) -> Option<LineAxis> {
    let first = topology.coordinate_of(line[0]);
    if line
        .iter()
        .all(|&node| topology.coordinate_of(node).y == first.y)
    {
        return Some(LineAxis::Horizontal);
    }
    if line
        .iter()
        .all(|&node| topology.coordinate_of(node).x == first.x)
    {
        return Some(LineAxis::Vertical);
    }
    None
}

fn creates_right_angle_threat(
    rules: &MillRules,
    root: &tgf_core::GameStateSnapshot,
    choice: &PerfectLogicalTurnChoice,
    root_side: i8,
) -> bool {
    let destination = choice.actions[0].to_node as u16;
    let topology = topology_for(rules);
    let after = state_after_turn(rules, root, choice);
    if !owned(&after, destination, root_side) {
        return false;
    }

    let mut axes = HashSet::new();
    let mut targets = HashSet::new();
    for line in topology
        .line_groups()
        .iter()
        .filter(|line| line.contains(&destination))
    {
        if line
            .iter()
            .filter(|&&node| owned(&after, node, root_side))
            .count()
            != 2
        {
            continue;
        }
        let Some(&target) = line.iter().find(|&&node| empty(&after, node)) else {
            continue;
        };
        let Some(axis) = line_axis(line, &topology) else {
            continue;
        };
        axes.insert(axis);
        targets.insert(target);
    }
    axes.len() == 2 && targets.len() >= 2
}

fn open_mill_targets_through(
    state: &MillState,
    side: i8,
    node: u16,
    topology: &MillTopology,
) -> HashSet<u16> {
    topology
        .line_groups()
        .iter()
        .filter(|line| line.contains(&node))
        .filter(|line| {
            line.iter()
                .filter(|&&candidate| owned(state, candidate, side))
                .count()
                == 2
        })
        .filter_map(|line| {
            line.iter()
                .find(|&&candidate| empty(state, candidate))
                .copied()
        })
        .collect()
}

fn transfers_ring_to_new_threat(
    rules: &MillRules,
    root: &tgf_core::GameStateSnapshot,
    choice: &PerfectLogicalTurnChoice,
    root_side: i8,
) -> bool {
    let primary = choice.actions[0];
    let from = primary.from_node as u16;
    let to = primary.to_node as u16;
    // MillTopology assigns contiguous blocks of eight nodes to the inner,
    // middle and outer rings.
    let from_ring = from / 8;
    let to_ring = to / 8;
    if from_ring.abs_diff(to_ring) != 1 {
        return false;
    }

    let topology = topology_for(rules);
    let before = MillRules::decode_snapshot(*root);
    let before_targets = open_mill_targets(&before, root_side, &topology);
    let after = state_after_turn(rules, root, choice);
    open_mill_targets_through(&after, root_side, to, &topology)
        .difference(&before_targets)
        .next()
        .is_some()
}
