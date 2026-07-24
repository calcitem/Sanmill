// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

//! Cold-path helpers for grouping Mill action tokens into logical turns.
//!
//! A mill-forming placement or move and its mandatory removal are separate
//! TGF actions, but they belong to one player's turn. Machine-facing data
//! queries use these helpers so action-token counts never leak into opening
//! prefix accounting.

use std::fmt;

use tgf_core::{Action, ActionList, GameRules, GameStateSnapshot, OutcomeKind};

use crate::MillRules;

const MAX_ACTIONS_PER_LOGICAL_TURN: usize = 24;

/// One complete legal Mill turn, possibly represented by multiple TGF actions.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MillLogicalTurn {
    pub actions: Vec<Action>,
    pub final_snapshot: GameStateSnapshot,
}

/// Deterministic action-token and logical-ply counts for a replay.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct MillPlyCount {
    pub action_tokens: u32,
    pub logical_plies: u32,
    pub logical_plies_by_side: [u32; 2],
}

/// Failure while enumerating a complete logical turn.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum LogicalTurnError {
    InvalidSideToMove(i8),
    NoLegalContinuation,
    ContinuationLimitExceeded,
}

impl fmt::Display for LogicalTurnError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidSideToMove(side) => {
                write!(f, "logical turn has invalid side to move {side}")
            }
            Self::NoLegalContinuation => {
                write!(f, "logical turn requires a continuation but none is legal")
            }
            Self::ContinuationLimitExceeded => write!(
                f,
                "logical turn exceeded the {MAX_ACTIONS_PER_LOGICAL_TURN}-action safety limit"
            ),
        }
    }
}

impl std::error::Error for LogicalTurnError {}

impl MillPlyCount {
    /// Record one successfully applied action.
    pub fn record(
        &mut self,
        rules: &MillRules,
        before: &GameStateSnapshot,
        after: &GameStateSnapshot,
    ) -> Result<(), LogicalTurnError> {
        let side = before.side_to_move;
        if side != 0 && side != 1 {
            return Err(LogicalTurnError::InvalidSideToMove(side));
        }
        self.action_tokens = self.action_tokens.saturating_add(1);
        if logical_turn_completed(rules, before, after) {
            self.logical_plies = self.logical_plies.saturating_add(1);
            self.logical_plies_by_side[side as usize] =
                self.logical_plies_by_side[side as usize].saturating_add(1);
        }
        Ok(())
    }
}

/// Return whether an applied action completed the active player's logical turn.
pub fn logical_turn_completed(
    rules: &MillRules,
    before: &GameStateSnapshot,
    after: &GameStateSnapshot,
) -> bool {
    after.side_to_move != before.side_to_move
        || !matches!(rules.outcome(after).kind, OutcomeKind::Ongoing)
}

/// Enumerate every complete legal turn from `snapshot` in stable rule order.
///
/// `history` is chronological and excludes `snapshot`, matching
/// [`GameRules::apply_with_history`]. The function is intended for data
/// queries and other cold paths; search continues to use atomic TGF actions.
pub fn legal_logical_turns(
    rules: &MillRules,
    snapshot: &GameStateSnapshot,
    history: &[GameStateSnapshot],
) -> Result<Vec<MillLogicalTurn>, LogicalTurnError> {
    let root_side = snapshot.side_to_move;
    if root_side != 0 && root_side != 1 {
        return Err(LogicalTurnError::InvalidSideToMove(root_side));
    }
    if !matches!(rules.outcome(snapshot).kind, OutcomeKind::Ongoing) {
        return Ok(Vec::new());
    }

    let mut legal = ActionList::<256>::new();
    rules.legal_actions(snapshot, &mut legal);
    if legal.as_slice().is_empty() {
        return Err(LogicalTurnError::NoLegalContinuation);
    }

    let mut turns = Vec::new();
    for &action in legal.as_slice() {
        let mut branch_history = history.to_vec();
        let next = rules.apply_with_history(snapshot, action, &branch_history);
        branch_history.push(*snapshot);
        enumerate_continuation(
            rules,
            root_side,
            next,
            branch_history,
            vec![action],
            &mut turns,
        )?;
    }
    Ok(turns)
}

fn enumerate_continuation(
    rules: &MillRules,
    root_side: i8,
    snapshot: GameStateSnapshot,
    history: Vec<GameStateSnapshot>,
    actions: Vec<Action>,
    turns: &mut Vec<MillLogicalTurn>,
) -> Result<(), LogicalTurnError> {
    if actions.len() > MAX_ACTIONS_PER_LOGICAL_TURN {
        return Err(LogicalTurnError::ContinuationLimitExceeded);
    }

    if snapshot.side_to_move != root_side
        || !matches!(rules.outcome(&snapshot).kind, OutcomeKind::Ongoing)
    {
        turns.push(MillLogicalTurn {
            actions,
            final_snapshot: snapshot,
        });
        return Ok(());
    }

    let mut legal = ActionList::<256>::new();
    rules.legal_actions(&snapshot, &mut legal);
    if legal.as_slice().is_empty() {
        return Err(LogicalTurnError::NoLegalContinuation);
    }

    for &action in legal.as_slice() {
        let mut next_history = history.clone();
        let next = rules.apply_with_history(&snapshot, action, &next_history);
        next_history.push(snapshot);
        let mut next_actions = actions.clone();
        next_actions.push(action);
        enumerate_continuation(rules, root_side, next, next_history, next_actions, turns)?;
    }
    Ok(())
}

#[cfg(test)]
#[path = "logical_turn_tests.rs"]
mod tests;
