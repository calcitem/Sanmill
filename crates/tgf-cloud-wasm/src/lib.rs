// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
use serde::{Deserialize, Serialize};
use tgf_core::{GameRules, GameStateSnapshot, NotationCodec, OPAQUE_PAYLOAD_LEN, OutcomeKind};
use tgf_mill::{MillFenFormat, MillRules, MillUciCodec, MillVariantOptions};

#[cfg(target_arch = "wasm32")]
use wasm_bindgen::prelude::*;

const SNAPSHOT_WIRE_VERSION: u8 = 1;
const SNAPSHOT_HEADER_BYTES: usize = 14;
const SNAPSHOT_BYTES: usize = SNAPSHOT_HEADER_BYTES + OPAQUE_PAYLOAD_LEN;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct RuleResponse {
    ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<&'static str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    snapshot: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    fen: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    side_to_move: Option<i8>,
    #[serde(skip_serializing_if = "Option::is_none")]
    outcome: Option<OutcomeResponse>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct OutcomeResponse {
    kind: &'static str,
    winner: Option<i8>,
    reason: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ApplyRequest {
    options: MillVariantOptions,
    snapshot: String,
    action: String,
}

/// Create a canonical Mill position using the exact options supplied by the
/// Flutter client. The JSON response is intentionally exception-free so the
/// Worker can map every malformed request to a stable protocol failure.
#[cfg_attr(target_arch = "wasm32", wasm_bindgen)]
pub fn cloud_mill_create(options_json: &str) -> String {
    let options: MillVariantOptions = match serde_json::from_str(options_json) {
        Ok(value) => value,
        Err(_) => return error_json("invalid_options"),
    };
    if !valid_options(&options) {
        return error_json("invalid_options");
    }
    let rules = MillRules::new(options);
    let snapshot = rules.initial_state(&[]);
    success_json(&rules, snapshot)
}

/// Validate and apply one UCI-style Mill action to an opaque TGF snapshot.
/// No AI/search code is linked into this crate.
#[cfg_attr(target_arch = "wasm32", wasm_bindgen)]
pub fn cloud_mill_apply(request_json: &str) -> String {
    let request: ApplyRequest = match serde_json::from_str(request_json) {
        Ok(value) => value,
        Err(_) => return error_json("invalid_request"),
    };
    if !valid_options(&request.options) {
        return error_json("invalid_options");
    }
    let snapshot = match decode_snapshot(&request.snapshot) {
        Ok(value) => value,
        Err(error) => return error_json(error),
    };
    let rules = MillRules::new(request.options);
    let action = match MillUciCodec.decode(&snapshot, request.action.trim()) {
        Some(value) if rules.is_legal(&snapshot, value) => value,
        _ => return error_json("illegal_action"),
    };
    success_json(&rules, rules.apply(&snapshot, action))
}

fn valid_options(options: &MillVariantOptions) -> bool {
    (9..=12).contains(&options.piece_count)
        && (3..=options.piece_count).contains(&options.pieces_at_least_count)
        && (!options.may_fly || options.fly_piece_count >= 3)
        && (options.n_move_rule == 0 || (10..=200).contains(&options.n_move_rule))
        && (options.endgame_n_move_rule == 0 || (5..=200).contains(&options.endgame_n_move_rule))
}

fn success_json(rules: &MillRules, snapshot: GameStateSnapshot) -> String {
    use tgf_core::PositionTextFormat as _;

    let outcome = rules.outcome(&snapshot);
    let (kind, winner) = match outcome.kind {
        OutcomeKind::Ongoing => ("ongoing", None),
        OutcomeKind::Win(seat) => ("win", Some(seat)),
        OutcomeKind::WinTeam(team) => ("winTeam", Some(team as i8)),
        OutcomeKind::Draw => ("draw", None),
        OutcomeKind::Abandoned => ("abandoned", None),
    };
    response_json(RuleResponse {
        ok: true,
        error: None,
        snapshot: Some(encode_snapshot(&snapshot)),
        fen: Some(MillFenFormat::new(rules.clone()).write(&snapshot)),
        side_to_move: Some(snapshot.side_to_move),
        outcome: Some(OutcomeResponse {
            kind,
            winner,
            reason: outcome.reason,
        }),
    })
}

fn error_json(error: &'static str) -> String {
    response_json(RuleResponse {
        ok: false,
        error: Some(error),
        snapshot: None,
        fen: None,
        side_to_move: None,
        outcome: None,
    })
}

fn response_json(response: RuleResponse) -> String {
    serde_json::to_string(&response).expect("serializing a fixed rule response must succeed")
}

fn encode_snapshot(snapshot: &GameStateSnapshot) -> String {
    let mut bytes = Vec::with_capacity(SNAPSHOT_BYTES);
    bytes.push(SNAPSHOT_WIRE_VERSION);
    bytes.push(snapshot.side_to_move as u8);
    bytes.extend_from_slice(&snapshot.phase_tag.to_le_bytes());
    bytes.extend_from_slice(&snapshot.move_number.to_le_bytes());
    bytes.extend_from_slice(&snapshot.zobrist_key.to_le_bytes());
    bytes.extend_from_slice(&snapshot.opaque_payload);
    debug_assert_eq!(bytes.len(), SNAPSHOT_BYTES);
    URL_SAFE_NO_PAD.encode(bytes)
}

fn decode_snapshot(encoded: &str) -> Result<GameStateSnapshot, &'static str> {
    let bytes = URL_SAFE_NO_PAD
        .decode(encoded)
        .map_err(|_| "invalid_snapshot")?;
    if bytes.len() != SNAPSHOT_BYTES || bytes[0] != SNAPSHOT_WIRE_VERSION {
        return Err("invalid_snapshot");
    }
    let mut payload = [0_u8; OPAQUE_PAYLOAD_LEN];
    payload.copy_from_slice(&bytes[SNAPSHOT_HEADER_BYTES..]);
    Ok(GameStateSnapshot {
        side_to_move: bytes[1] as i8,
        phase_tag: i16::from_le_bytes([bytes[2], bytes[3]]),
        move_number: i16::from_le_bytes([bytes[4], bytes[5]]),
        zobrist_key: u64::from_le_bytes(bytes[6..14].try_into().map_err(|_| "invalid_snapshot")?),
        opaque_payload: payload,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn default_options_json() -> String {
        serde_json::to_string(&MillVariantOptions::default()).unwrap()
    }

    #[test]
    fn creates_and_applies_a_legal_action() {
        let created: serde_json::Value =
            serde_json::from_str(&cloud_mill_create(&default_options_json())).unwrap();
        assert_eq!(created["ok"], true);
        assert_eq!(created["sideToMove"], 0);

        let applied: serde_json::Value = serde_json::from_str(&cloud_mill_apply(
            &serde_json::json!({
                "options": MillVariantOptions::default(),
                "snapshot": created["snapshot"],
                "action": "a7",
            })
            .to_string(),
        ))
        .unwrap();
        assert_eq!(applied["ok"], true);
        assert_eq!(applied["sideToMove"], 1);
        assert_ne!(applied["snapshot"], created["snapshot"]);
    }

    #[test]
    fn rejects_illegal_and_malformed_input_without_panicking() {
        assert_eq!(
            serde_json::from_str::<serde_json::Value>(&cloud_mill_create("{}")).unwrap()["error"],
            "invalid_options"
        );
        let created: serde_json::Value =
            serde_json::from_str(&cloud_mill_create(&default_options_json())).unwrap();
        let request = |action: &str| {
            serde_json::json!({
                "options": MillVariantOptions::default(),
                "snapshot": created["snapshot"],
                "action": action,
            })
            .to_string()
        };
        assert_eq!(
            serde_json::from_str::<serde_json::Value>(&cloud_mill_apply(&request("xa7"))).unwrap()
                ["error"],
            "illegal_action"
        );
        assert_eq!(
            serde_json::from_str::<serde_json::Value>(&cloud_mill_apply("{}")).unwrap()["error"],
            "invalid_request"
        );
    }

    #[test]
    fn snapshot_codec_round_trips_exactly() {
        let rules = MillRules::default();
        let snapshot = rules.initial_state(&[]);
        assert_eq!(decode_snapshot(&encode_snapshot(&snapshot)), Ok(snapshot));
    }

    #[test]
    fn every_native_preset_has_the_same_cloud_initial_position() {
        use tgf_core::PositionTextFormat as _;
        use tgf_mill::{N_PRESETS, preset_for};

        for preset_id in 0..N_PRESETS {
            let preset = preset_for(preset_id).unwrap();
            let native_rules = MillRules::new(preset.options.clone());
            let native = native_rules.initial_state(&[]);
            let cloud: serde_json::Value = serde_json::from_str(&cloud_mill_create(
                &serde_json::to_string(&preset.options).unwrap(),
            ))
            .unwrap();

            assert_eq!(cloud["ok"], true, "preset {preset_id}");
            assert_eq!(
                decode_snapshot(cloud["snapshot"].as_str().unwrap()),
                Ok(native),
                "preset {preset_id}"
            );
            assert_eq!(
                cloud["fen"],
                MillFenFormat::new(native_rules).write(&native),
                "preset {preset_id}"
            );
        }
    }

    #[test]
    fn native_and_cloud_action_sequences_remain_identical() {
        use tgf_core::PositionTextFormat as _;

        let options = MillVariantOptions::default();
        let rules = MillRules::new(options.clone());
        let mut native = rules.initial_state(&[]);
        let mut cloud: serde_json::Value = serde_json::from_str(&cloud_mill_create(
            &serde_json::to_string(&options).unwrap(),
        ))
        .unwrap();

        for notation in ["a7", "d7", "g7", "d6", "g4", "f6"] {
            let action = MillUciCodec.decode(&native, notation).unwrap();
            assert!(rules.is_legal(&native, action), "{notation} must be legal");
            native = rules.apply(&native, action);
            cloud = serde_json::from_str(&cloud_mill_apply(
                &serde_json::json!({
                    "options": options,
                    "snapshot": cloud["snapshot"],
                    "action": notation,
                })
                .to_string(),
            ))
            .unwrap();

            assert_eq!(cloud["ok"], true, "action {notation}");
            assert_eq!(
                decode_snapshot(cloud["snapshot"].as_str().unwrap()),
                Ok(native),
                "action {notation}"
            );
            assert_eq!(
                cloud["fen"],
                MillFenFormat::new(rules.clone()).write(&native),
                "action {notation}"
            );
        }
    }
}
