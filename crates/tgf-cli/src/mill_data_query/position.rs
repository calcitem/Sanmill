// SPDX-License-Identifier: AGPL-3.0-or-later

use sha2::{Digest, Sha256};
use tgf_core::{Action, ActionList, GameRules, GameStateSnapshot, OutcomeKind};
use tgf_mill::{
    MillPhase, MillPlyCount, MillRules, MillUciCodec, MillVariantOptions, rules_for_preset,
};

use super::hashing::{hex_lower, update_length_prefixed};
use super::protocol::{
    ApiError, HistoryOrigin, OutcomeSummary, PositionRequest, RulePreset, StateSummary,
};

#[derive(Clone, Debug)]
pub(super) struct AppliedAction {
    pub action: Action,
    pub token: String,
    pub before: GameStateSnapshot,
}

#[derive(Clone, Debug)]
pub(super) struct ReplayedPosition {
    pub rule: RulePreset,
    pub rules: MillRules,
    pub options: MillVariantOptions,
    pub snapshot: GameStateSnapshot,
    pub history: Vec<GameStateSnapshot>,
    pub applied: Vec<AppliedAction>,
    pub counts: MillPlyCount,
}

pub(super) struct SourcePosition<'a> {
    pub snapshot: &'a GameStateSnapshot,
    pub history: &'a [GameStateSnapshot],
    pub prefix_actions: Vec<Action>,
    pub prefix_tokens: Vec<String>,
    pub prefix_complete: bool,
}

impl ReplayedPosition {
    pub(super) fn replay(request: &PositionRequest) -> Result<Self, ApiError> {
        match (request.initial.as_str(), request.history_origin) {
            ("startpos", HistoryOrigin::GameStart) => {}
            ("startpos", HistoryOrigin::FreshSetup) => {
                return Err(ApiError::new(
                    "protocol_error",
                    "startpos requires history_origin=game_start",
                ));
            }
            (_, HistoryOrigin::GameStart) => {
                return Err(ApiError::new(
                    "protocol_error",
                    "an explicit initial FEN requires history_origin=fresh_setup",
                ));
            }
            (_, HistoryOrigin::FreshSetup) => {}
        }
        let rules = rules_for_preset(request.rule.preset_id()).ok_or_else(|| {
            ApiError::new(
                "unsupported_rule",
                format!("unsupported Mill rule preset {:?}", request.rule),
            )
        })?;
        let options = rules.options().clone();
        let mut snapshot = if request.initial == "startpos" {
            rules.initial_state(&[])
        } else {
            let state = rules.set_from_fen(&request.initial).map_err(|message| {
                ApiError::new(
                    "invalid_fen",
                    format!("invalid initial Mill FEN: {message}"),
                )
            })?;
            rules.encode_state(state)
        };
        let mut history = Vec::with_capacity(request.actions.len());
        let mut applied = Vec::with_capacity(request.actions.len());
        let mut counts = MillPlyCount::default();

        for (action_index, token) in request.actions.iter().enumerate() {
            let action = MillUciCodec::decode_action(&snapshot, token).ok_or_else(|| {
                ApiError::at_action(
                    "protocol_error",
                    format!("invalid Mill action token {token:?}"),
                    action_index,
                )
            })?;
            let mut legal = ActionList::<256>::new();
            rules.legal_actions(&snapshot, &mut legal);
            if !legal.as_slice().contains(&action) {
                return Err(ApiError::at_action(
                    "illegal_action",
                    format!("Mill action {token:?} is illegal in the replayed position"),
                    action_index,
                ));
            }
            let before = snapshot;
            let after = rules.apply_with_history(&before, action, &history);
            counts.record(&rules, &before, &after).map_err(|error| {
                ApiError::at_action("invalid_state", error.to_string(), action_index)
            })?;
            history.push(before);
            let canonical_token = MillUciCodec::encode_action(action);
            applied.push(AppliedAction {
                action,
                token: canonical_token,
                before,
            });
            snapshot = after;
        }

        if let Some(expected) = &request.expected_current_fen {
            let expected_state = rules.set_from_fen(expected).map_err(|message| {
                ApiError::new(
                    "invalid_expected_fen",
                    format!("invalid expected current FEN: {message}"),
                )
            })?;
            let expected_fen = rules.export_fen(&expected_state);
            let actual_fen = rules.export_fen(&MillRules::decode_snapshot(snapshot));
            if actual_fen != expected_fen {
                return Err(ApiError::new(
                    "state_mismatch",
                    format!(
                        "replayed current FEN does not match expected_current_fen: \
                         expected {expected_fen:?}, got {actual_fen:?}"
                    ),
                ));
            }
        }

        Ok(Self {
            rule: request.rule,
            rules,
            options,
            snapshot,
            history,
            applied,
            counts,
        })
    }

    pub(super) fn is_terminal(&self) -> bool {
        !matches!(
            self.rules.outcome(&self.snapshot).kind,
            OutcomeKind::Ongoing
        )
    }

    pub(super) fn state_summary(&self) -> StateSummary {
        let tokens = self
            .applied
            .iter()
            .map(|record| record.token.clone())
            .collect::<Vec<_>>();
        summarize_position(
            &self.rules,
            &self.snapshot,
            &self.history,
            &tokens,
            self.counts,
        )
        .expect("a replayed data-query position has aligned history and action tokens")
    }

    pub(super) fn source_position(&self) -> SourcePosition<'_> {
        if !self.current_side_has_pending_removal() {
            return SourcePosition {
                snapshot: &self.snapshot,
                history: &self.history,
                prefix_actions: Vec::new(),
                prefix_tokens: Vec::new(),
                prefix_complete: true,
            };
        }

        let side = self.snapshot.side_to_move;
        let mut start = self.applied.len();
        while start > 0 && self.applied[start - 1].before.side_to_move == side {
            start -= 1;
        }
        if start == self.applied.len() {
            return SourcePosition {
                snapshot: &self.snapshot,
                history: &self.history,
                prefix_actions: Vec::new(),
                prefix_tokens: Vec::new(),
                prefix_complete: false,
            };
        }
        let source_snapshot = &self.applied[start].before;
        let prefix_complete = !snapshot_has_pending_removal(source_snapshot);
        SourcePosition {
            snapshot: source_snapshot,
            history: &self.history[..start],
            prefix_actions: self.applied[start..]
                .iter()
                .map(|record| record.action)
                .collect(),
            prefix_tokens: self.applied[start..]
                .iter()
                .map(|record| record.token.clone())
                .collect(),
            prefix_complete,
        }
    }

    pub(super) fn current_side_has_pending_removal(&self) -> bool {
        snapshot_has_pending_removal(&self.snapshot)
    }
}

/// Build the version-1 data-query state summary from an already replayed
/// position.
///
/// The UCI `statejson` extension calls this same cold-path function so its
/// logical-ply counts, repetition-window length, and history digest cannot
/// drift from `mill data-query`. `history` is chronological and excludes
/// `snapshot`; `action_tokens[index]` must be the canonical action that
/// transformed `history[index]` toward the next state.
pub(crate) fn summarize_position(
    rules: &MillRules,
    snapshot: &GameStateSnapshot,
    history: &[GameStateSnapshot],
    action_tokens: &[String],
    counts: MillPlyCount,
) -> Result<StateSummary, String> {
    if history.len() != action_tokens.len() {
        return Err(format!(
            "snapshot history length {} does not match action-token length {}",
            history.len(),
            action_tokens.len()
        ));
    }

    let state = MillRules::decode_snapshot(*snapshot);
    let outcome = rules.outcome(snapshot);
    let (kind, winner) = match outcome.kind {
        OutcomeKind::Ongoing => ("ongoing", None),
        OutcomeKind::Win(side) => ("win", Some(side)),
        OutcomeKind::Draw => ("draw", None),
        OutcomeKind::Abandoned => ("abandoned", None),
        OutcomeKind::WinTeam(_) => ("win_team", None),
    };
    let repetition_history = MillRules::repetition_history_from_snapshots(snapshot, history);
    Ok(StateSummary {
        current_fen: rules.export_fen(&state),
        side_to_move: match snapshot.side_to_move {
            0 => Some("white".to_owned()),
            1 => Some("black".to_owned()),
            _ => None,
        },
        phase: match state.phase() {
            MillPhase::Ready => "ready",
            MillPhase::Placing => "placing",
            MillPhase::Moving => "moving",
            MillPhase::GameOver => "game_over",
        }
        .to_owned(),
        pending_removal: snapshot_has_pending_removal(snapshot),
        pending_removals: state.pending_removals(),
        no_capture_plies: state.ply_since_capture(),
        action_token_count: counts.action_tokens,
        logical_ply_count: counts.logical_plies,
        logical_plies_by_side: counts.logical_plies_by_side,
        snapshot_history_len: history.len(),
        repetition_history_len: repetition_history.len(),
        history_sha256: history_sha256(rules, snapshot, history, action_tokens),
        outcome: OutcomeSummary {
            kind: kind.to_owned(),
            winner,
            reason: outcome.reason,
        },
    })
}

fn history_sha256(
    rules: &MillRules,
    snapshot: &GameStateSnapshot,
    history: &[GameStateSnapshot],
    action_tokens: &[String],
) -> String {
    let mut hash = Sha256::new();
    hash.update(b"sanmill.data-query.history.v1\0");
    for (index, (before, token)) in history.iter().zip(action_tokens).enumerate() {
        let fen = rules.export_fen(&MillRules::decode_snapshot(*before));
        update_length_prefixed(&mut hash, fen.as_bytes());
        update_length_prefixed(&mut hash, token.as_bytes());
        hash.update((index as u64).to_le_bytes());
    }
    let current = rules.export_fen(&MillRules::decode_snapshot(*snapshot));
    update_length_prefixed(&mut hash, current.as_bytes());
    hex_lower(&hash.finalize())
}

fn snapshot_has_pending_removal(snapshot: &GameStateSnapshot) -> bool {
    let side = snapshot.side_to_move;
    (side == 0 || side == 1)
        && MillRules::decode_snapshot(*snapshot).pending_removals()[side as usize] > 0
}
