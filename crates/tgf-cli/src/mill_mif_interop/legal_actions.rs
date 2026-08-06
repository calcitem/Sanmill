// SPDX-License-Identifier: AGPL-3.0-or-later

use serde_json::{Value, json};

use super::model::{
    ADJACENCY, COORDS, Diagnostic, Manifest, Result, State, parse_obligation_branches,
    projection_state,
};

pub(super) fn project(payload: &Value) -> Result<Value> {
    let manifest = Manifest::new(payload.get("manifest").cloned().ok_or_else(|| {
        Diagnostic::new(
            "integrity",
            "manifest-missing",
            "legal action projection requires manifest",
        )
    })?)?;
    let current = payload
        .get("current")
        .and_then(Value::as_str)
        .ok_or_else(|| {
            Diagnostic::new(
                "syntax",
                "current-missing",
                "legal action projection requires current MFEN",
            )
        })?;
    let state = projection_state(&manifest, current)?;
    let actions = legal_actions(&manifest, &state)?;
    Ok(json!({
        "document": {
            "profile": "legal-actions-v1",
            "stateProfile": "mill24-state-v1",
            "semanticDigest": manifest.semantic_digest,
            "current": current,
            "actions": actions,
        }
    }))
}

fn legal_actions(manifest: &Manifest, state: &State) -> Result<Vec<Value>> {
    if state.outcome != "-" {
        return Ok(Vec::new());
    }
    if state.obligations != "-" {
        return removal_actions(state);
    }

    let mut actions = Vec::new();
    if state.phase == 'p' && state.hands[player_index(state.side)] > 0 {
        for (index, point) in COORDS.iter().enumerate() {
            if state.board[index] == '.' {
                actions.push(json!({
                    "actor": state.side.to_string(),
                    "type": "place",
                    "at": point,
                }));
            }
        }
    }
    if state.phase == 'm' || (state.phase == 'p' && manifest.movement_allowed()) {
        append_move_actions(&mut actions, manifest, state);
    }
    Ok(actions)
}

fn append_move_actions(actions: &mut Vec<Value>, manifest: &Manifest, state: &State) {
    let actor = state.side;
    let piece = actor.to_ascii_uppercase();
    let flying = state.phase == 'm'
        && manifest
            .value
            .pointer("/flying/enabled")
            .and_then(Value::as_bool)
            == Some(true)
        && live_count(state, actor)
            <= manifest
                .value
                .pointer("/flying/maximumLive")
                .and_then(Value::as_u64)
                .unwrap_or(0);
    for (source, source_point) in COORDS.iter().enumerate() {
        if state.board[source] != piece {
            continue;
        }
        for (target, target_point) in COORDS.iter().enumerate() {
            if state.board[target] == '.' && (flying || ADJACENCY[source].contains(&target)) {
                actions.push(json!({
                    "actor": actor.to_string(),
                    "type": "move",
                    "from": source_point,
                    "to": target_point,
                }));
            }
        }
    }
}

fn removal_actions(state: &State) -> Result<Vec<Value>> {
    let branches = parse_obligation_branches(&state.obligations)?;
    let mut board_targets = [false; 24];
    let mut hand_targets = [false; 2];
    for head in branches.iter().filter_map(|branch| branch.first()) {
        if head.actor != state.side {
            return Err(Diagnostic::new(
                "inconsistent",
                "side-obligation-actor-mismatch",
                "obligation actor differs from the active side",
            ));
        }
        if head.targets_deferred {
            return Err(Diagnostic::new(
                "inconsistent",
                "obligation-target-mismatch",
                "active obligation targets must be materialized",
            ));
        }
        match head.zone {
            'b' => {
                if head.targets & !0x00ff_ffff != 0 {
                    return Err(Diagnostic::new(
                        "syntax",
                        "obligation-invalid",
                        "board obligation target mask exceeds the topology",
                    ));
                }
                for (index, selected) in board_targets.iter_mut().enumerate() {
                    if head.targets & (1 << index) == 0 {
                        continue;
                    }
                    if state.board[index] != head.owner.to_ascii_uppercase() {
                        return Err(Diagnostic::new(
                            "inconsistent",
                            "obligation-target-mismatch",
                            "board obligation target owner does not match state",
                        ));
                    }
                    *selected = true;
                }
            }
            'h' if matches!(head.owner, 'w' | 'b') => {
                let owner = player_index(head.owner);
                if state.hands[owner] == 0 {
                    return Err(Diagnostic::new(
                        "inconsistent",
                        "obligation-target-mismatch",
                        "hand obligation target has no remaining material",
                    ));
                }
                hand_targets[owner] = true;
            }
            _ => {
                return Err(Diagnostic::new(
                    "syntax",
                    "obligation-invalid",
                    "obligation target zone or owner is invalid",
                ));
            }
        }
    }

    let mut actions = Vec::new();
    for (index, selected) in board_targets.into_iter().enumerate() {
        if selected {
            actions.push(json!({
                "actor": state.side.to_string(),
                "type": "remove",
                "target": { "zone": "board", "at": COORDS[index] },
            }));
        }
    }
    for (index, selected) in hand_targets.into_iter().enumerate() {
        if selected {
            actions.push(json!({
                "actor": state.side.to_string(),
                "type": "remove",
                "target": {
                    "zone": "hand",
                    "player": if index == 0 { "w" } else { "b" },
                },
            }));
        }
    }
    Ok(actions)
}

fn live_count(state: &State, player: char) -> u64 {
    let piece = player.to_ascii_uppercase();
    state.board.iter().filter(|value| **value == piece).count() as u64
}

fn player_index(player: char) -> usize {
    usize::from(player == 'b')
}
