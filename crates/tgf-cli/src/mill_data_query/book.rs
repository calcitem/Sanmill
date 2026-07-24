// SPDX-License-Identifier: AGPL-3.0-or-later

use std::collections::{BTreeMap, HashSet};
use std::fs;
use std::path::PathBuf;

use serde::de::{MapAccess, Visitor};
use serde::{Deserialize, Deserializer, Serialize};
use serde_json::{Value, json};
use tgf_core::{ActionList, GameRules};
use tgf_mill::{
    MillRules, MillUciCodec, canonical_opening_book_fen, inverse_opening_book_transform,
    legal_logical_turns, normalize_opening_book_fen, rules_for_preset,
    transform_opening_book_notation,
};

use super::hashing::{sha256_bytes, update_length_prefixed};
use super::position::ReplayedPosition;
use super::protocol::{ApiError, Candidate, RulePreset};

const NMM_BOOK: &[u8] = include_bytes!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../src/ui/flutter_app/assets/opening_books/nmm/opening_book.json"
));
const EL_FILJA_BOOK: &[u8] = include_bytes!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../src/ui/flutter_app/assets/opening_books/el_filja/opening_book.json"
));

#[derive(Clone, Debug)]
pub(super) struct BookQueryResult {
    pub source: Value,
    pub candidates: Vec<Candidate>,
}

#[derive(Clone, Debug)]
pub(super) struct BookAsset {
    identity: BookIdentity,
    oracle: BTreeMap<String, Vec<String>>,
}

#[derive(Clone, Debug, Serialize)]
struct BookIdentity {
    kind: &'static str,
    schema_version: u32,
    variant: String,
    symmetry: String,
    sha256: String,
    byte_length: u64,
    oracle_positions: usize,
    oracle_records: usize,
    source: String,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct BookDocument {
    #[serde(rename = "schemaVersion")]
    schema_version: u32,
    variant: String,
    symmetry: String,
    oracle: StrictOracle,
    openings: Value,
}

struct StrictOracle(BTreeMap<String, Vec<String>>);

impl<'de> Deserialize<'de> for StrictOracle {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        struct OracleVisitor;

        impl<'de> Visitor<'de> for OracleVisitor {
            type Value = StrictOracle;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("an opening-book oracle object")
            }

            fn visit_map<A>(self, mut map: A) -> Result<Self::Value, A::Error>
            where
                A: MapAccess<'de>,
            {
                let mut oracle = BTreeMap::new();
                while let Some((fen, moves)) = map.next_entry::<String, Vec<String>>()? {
                    if oracle.insert(fen.clone(), moves).is_some() {
                        return Err(serde::de::Error::custom(format!(
                            "duplicate opening-book FEN key {fen:?}"
                        )));
                    }
                }
                Ok(StrictOracle(oracle))
            }
        }

        deserializer.deserialize_map(OracleVisitor)
    }
}

impl BookAsset {
    pub(super) fn load(variant: RulePreset, asset_path: Option<&str>) -> Result<Self, ApiError> {
        let (bytes, source) = match asset_path {
            Some(path) => {
                let path = PathBuf::from(path);
                let bytes = fs::read(&path).map_err(|error| {
                    let code = if error.kind() == std::io::ErrorKind::NotFound {
                        "asset_missing"
                    } else {
                        "asset_open_error"
                    };
                    ApiError::new(
                        code,
                        format!(
                            "failed to read opening-book asset {}: {error}",
                            path.display()
                        ),
                    )
                })?;
                (bytes, path.display().to_string())
            }
            None => (
                match variant {
                    RulePreset::Nmm => NMM_BOOK.to_vec(),
                    RulePreset::ElFilja => EL_FILJA_BOOK.to_vec(),
                },
                "bundled".to_owned(),
            ),
        };
        Self::parse(variant, &bytes, source)
    }

    fn parse(variant: RulePreset, bytes: &[u8], source: String) -> Result<Self, ApiError> {
        let document = serde_json::from_slice::<BookDocument>(bytes).map_err(|error| {
            ApiError::new(
                "asset_parse_error",
                format!("failed to parse opening-book asset: {error}"),
            )
        })?;
        if document.schema_version != 1 {
            return Err(ApiError::new(
                "asset_schema_incompatible",
                format!(
                    "opening-book schema version {} is unsupported",
                    document.schema_version
                ),
            ));
        }
        if document.variant != variant.book_variant() {
            return Err(ApiError::new(
                "asset_identity_mismatch",
                format!(
                    "opening-book variant {:?} does not match requested {:?}",
                    document.variant,
                    variant.book_variant()
                ),
            ));
        }
        if document.symmetry != "ring16" {
            return Err(ApiError::new(
                "asset_schema_incompatible",
                format!(
                    "opening-book symmetry {:?} is unsupported",
                    document.symmetry
                ),
            ));
        }
        if !document.openings.is_array() {
            return Err(ApiError::new(
                "asset_parse_error",
                "opening-book openings field must be an array",
            ));
        }
        if document.oracle.0.is_empty() {
            return Err(ApiError::new(
                "asset_integrity_error",
                "opening-book oracle must not be empty",
            ));
        }

        let rules = rules_for_preset(variant.preset_id())
            .expect("query protocol only exposes known opening-book presets");
        validate_oracle(&rules, &document.oracle.0)?;
        let oracle_records = document.oracle.0.values().map(Vec::len).sum();
        Ok(Self {
            identity: BookIdentity {
                kind: "opening_book",
                schema_version: document.schema_version,
                variant: document.variant,
                symmetry: document.symmetry,
                sha256: sha256_bytes(bytes),
                byte_length: bytes.len() as u64,
                oracle_positions: document.oracle.0.len(),
                oracle_records,
                source,
            },
            oracle: document.oracle.0,
        })
    }

    pub(super) fn identity_json(&self) -> Value {
        serde_json::to_value(&self.identity).expect("book identity must serialize")
    }
}

pub(super) fn query(
    replayed: &ReplayedPosition,
    asset_path: Option<&str>,
) -> Result<BookQueryResult, ApiError> {
    let asset = BookAsset::load(replayed.rule, asset_path)?;
    let source_position = replayed.source_position();
    if replayed.current_side_has_pending_removal() && !source_position.prefix_complete {
        return Err(ApiError::new(
            "incomplete_history",
            "book queries in pending-removal states require the initiating action history",
        ));
    }
    let source_fen = replayed
        .rules
        .export_fen(&MillRules::decode_snapshot(*source_position.snapshot));
    let (canonical_fen, to_canonical) =
        canonical_opening_book_fen(&source_fen).map_err(|message| {
            ApiError::new(
                "invalid_state",
                format!("failed to canonicalize opening-book FEN: {message}"),
            )
        })?;
    let Some(raw_moves) = asset.oracle.get(&canonical_fen) else {
        return Ok(BookQueryResult {
            source: book_source_json(&asset, &canonical_fen, to_canonical),
            candidates: Vec::new(),
        });
    };
    let inverse = inverse_opening_book_transform(to_canonical).map_err(|message| {
        ApiError::new(
            "coordinate_mapping_error",
            format!("failed to invert opening-book transform: {message}"),
        )
    })?;
    let turns = legal_logical_turns(
        &replayed.rules,
        source_position.snapshot,
        source_position.history,
    )
    .map_err(|error| ApiError::new("invalid_state", error.to_string()))?;
    let mut candidates = Vec::new();
    for (rank_index, raw_move) in raw_moves.iter().enumerate() {
        let mapped = transform_opening_book_notation(raw_move, inverse).map_err(|message| {
            ApiError::new(
                "coordinate_mapping_error",
                format!("failed to map opening-book move {raw_move:?}: {message}"),
            )
        })?;
        let mapped_action = decode_legal(&replayed.rules, source_position.snapshot, &mapped)
            .ok_or_else(|| {
                ApiError::new(
                    "illegal_source_move",
                    format!(
                        "opening-book move {raw_move:?} maps to illegal move {mapped:?} \
                     for {source_fen}"
                    ),
                )
            })?;
        let mut produced = 0_usize;
        for turn in turns.iter().filter(|turn| {
            turn.actions.first() == Some(&mapped_action)
                && turn.actions.starts_with(&source_position.prefix_actions)
        }) {
            let turn_tokens = turn
                .actions
                .iter()
                .copied()
                .map(MillUciCodec::encode_action)
                .collect::<Vec<_>>();
            let remaining = turn_tokens[source_position.prefix_tokens.len()..].to_vec();
            let removal_action = turn_tokens
                .iter()
                .find(|token| token.starts_with('x'))
                .cloned();
            candidates.push(Candidate {
                logical_move_id: logical_move_id(
                    "book",
                    &asset.identity.sha256,
                    &canonical_fen,
                    &turn_tokens,
                ),
                source_group_id: Some(format!("book-rank-{}", rank_index + 1)),
                stable_index: 0,
                source_rank: Some(rank_index + 1),
                raw_notation: Some(raw_move.clone()),
                mapped_notation: mapped.clone(),
                full_turn_actions: turn_tokens,
                remaining_actions: remaining,
                contains_removal: removal_action.is_some(),
                removal_action,
                logical_ply_delta: 1,
                turn_prefix_complete: source_position.prefix_complete,
                perfect: None,
                human: None,
            });
            produced += 1;
        }
        if produced == 0 && source_position.prefix_actions.is_empty() {
            return Err(ApiError::new(
                "illegal_source_move",
                format!(
                    "opening-book move {raw_move:?} has no complete legal logical turn \
                     for {source_fen}"
                ),
            ));
        }
    }
    candidates.sort_by(|left, right| {
        left.source_rank
            .cmp(&right.source_rank)
            .then_with(|| left.full_turn_actions.cmp(&right.full_turn_actions))
    });
    for (index, candidate) in candidates.iter_mut().enumerate() {
        candidate.stable_index = index;
    }
    Ok(BookQueryResult {
        source: book_source_json(&asset, &canonical_fen, to_canonical),
        candidates,
    })
}

fn validate_oracle(
    rules: &MillRules,
    oracle: &BTreeMap<String, Vec<String>>,
) -> Result<(), ApiError> {
    for (fen, moves) in oracle {
        let normalized = normalize_opening_book_fen(fen).map_err(|message| {
            ApiError::new(
                "asset_integrity_error",
                format!("invalid opening-book FEN {fen:?}: {message}"),
            )
        })?;
        let (canonical, _) = canonical_opening_book_fen(&normalized).map_err(|message| {
            ApiError::new(
                "asset_integrity_error",
                format!("cannot canonicalize opening-book FEN {fen:?}: {message}"),
            )
        })?;
        if normalized != *fen || canonical != *fen {
            return Err(ApiError::new(
                "asset_integrity_error",
                format!("opening-book FEN is not normalized and canonical: {fen}"),
            ));
        }
        let state = rules.set_from_fen(fen).map_err(|message| {
            ApiError::new(
                "asset_integrity_error",
                format!("opening-book FEN does not parse ({message}): {fen}"),
            )
        })?;
        let snapshot = rules.encode_state(state);
        let mut legal = ActionList::<256>::new();
        rules.legal_actions(&snapshot, &mut legal);
        if moves.is_empty() {
            return Err(ApiError::new(
                "asset_integrity_error",
                format!("opening-book candidate list is empty for {fen}"),
            ));
        }
        let mut seen = HashSet::new();
        for candidate in moves {
            if !seen.insert(candidate) {
                return Err(ApiError::new(
                    "asset_integrity_error",
                    format!("opening-book move {candidate:?} is duplicated for {fen}"),
                ));
            }
            let action = MillUciCodec::decode_action(&snapshot, candidate).ok_or_else(|| {
                ApiError::new(
                    "asset_integrity_error",
                    format!("opening-book move {candidate:?} is malformed for {fen}"),
                )
            })?;
            if !legal.as_slice().contains(&action) {
                return Err(ApiError::new(
                    "illegal_source_move",
                    format!("opening-book move {candidate:?} is illegal for {fen}"),
                ));
            }
        }
    }
    Ok(())
}

fn decode_legal(
    rules: &MillRules,
    snapshot: &tgf_core::GameStateSnapshot,
    token: &str,
) -> Option<tgf_core::Action> {
    let action = MillUciCodec::decode_action(snapshot, token)?;
    let mut legal = ActionList::<256>::new();
    rules.legal_actions(snapshot, &mut legal);
    legal
        .as_slice()
        .iter()
        .copied()
        .find(|item| *item == action)
}

fn book_source_json(asset: &BookAsset, canonical_fen: &str, transform: usize) -> Value {
    json!({
        "identity": asset.identity_json(),
        "canonical_fen": canonical_fen,
        "transform_to_canonical": transform,
        "candidate_order": "source_array",
        "selection_weight": {
            "kind": "geometric_rank",
            "ratio": 0.6,
            "formula": "ratio^(rank-1)"
        }
    })
}

fn logical_move_id(kind: &str, identity: &str, state_key: &str, tokens: &[String]) -> String {
    let mut hash = sha2::Sha256::new();
    use sha2::Digest;
    update_length_prefixed(&mut hash, kind.as_bytes());
    update_length_prefixed(&mut hash, identity.as_bytes());
    update_length_prefixed(&mut hash, state_key.as_bytes());
    for token in tokens {
        update_length_prefixed(&mut hash, token.as_bytes());
    }
    format!("book:{}", super::hashing::hex_lower(&hash.finalize()))
}

pub(super) fn identity(variant: RulePreset, asset_path: Option<&str>) -> Result<Value, ApiError> {
    Ok(BookAsset::load(variant, asset_path)?.identity_json())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::mill_data_query::protocol::{HistoryOrigin, PositionRequest};
    use tgf_mill::{OPENING_BOOK_SYMMETRY_COUNT, transform_opening_book_fen};

    #[test]
    fn bundled_nmm_book_has_expected_identity() {
        let asset = BookAsset::load(RulePreset::Nmm, None).unwrap();
        assert_eq!(asset.identity.oracle_positions, 109);
        assert_eq!(asset.identity.oracle_records, 437);
        assert_eq!(
            asset.identity.sha256,
            "cdc4768bc461c22177634985a4cc1d92452774e2992515b937fed8812eb076f5"
        );
    }

    #[test]
    fn initial_book_query_returns_source_order() {
        let replayed = ReplayedPosition::replay(&PositionRequest {
            rule: RulePreset::Nmm,
            initial: "startpos".to_owned(),
            history_origin: HistoryOrigin::GameStart,
            actions: Vec::new(),
            expected_current_fen: None,
        })
        .unwrap();
        let result = query(&replayed, None).unwrap();
        assert_eq!(result.candidates[0].mapped_notation, "d2");
        assert_eq!(result.candidates[0].source_rank, Some(1));
        assert!(result.candidates.iter().all(|candidate| {
            !candidate.full_turn_actions.is_empty() && candidate.logical_ply_delta == 1
        }));
    }

    #[test]
    fn every_ring16_presentation_maps_candidates_back_to_the_live_board() {
        let asset = BookAsset::load(RulePreset::Nmm, None).unwrap();
        let canonical_fen =
            "********/*******O/******** b p p 1 8 0 9 0 0 -1 -1 -1 -1 0 0 1 ids:nodes";
        let expected_raw = asset.oracle[canonical_fen].clone();

        for transform in 0..OPENING_BOOK_SYMMETRY_COUNT {
            let live_fen = transform_opening_book_fen(canonical_fen, transform).unwrap();
            let replayed = ReplayedPosition::replay(&PositionRequest {
                rule: RulePreset::Nmm,
                initial: live_fen,
                history_origin: HistoryOrigin::FreshSetup,
                actions: Vec::new(),
                expected_current_fen: None,
            })
            .unwrap();
            let result = query(&replayed, None).unwrap();
            let actual_raw = result
                .candidates
                .iter()
                .map(|candidate| candidate.raw_notation.clone().unwrap())
                .collect::<Vec<_>>();
            assert_eq!(
                actual_raw, expected_raw,
                "transform {transform} must preserve source candidate order"
            );
            assert!(result.candidates.iter().all(|candidate| {
                decode_legal(
                    &replayed.rules,
                    &replayed.snapshot,
                    &candidate.mapped_notation,
                )
                .is_some()
            }));
        }
    }

    #[test]
    fn mill_closing_book_move_keeps_one_rank_across_removal_branches() {
        let asset = BookAsset::load(RulePreset::Nmm, None).unwrap();
        let rules = rules_for_preset(RulePreset::Nmm.preset_id()).unwrap();

        for (fen, raw_moves) in &asset.oracle {
            let snapshot = rules.encode_state(rules.set_from_fen(fen).unwrap());
            let turns = legal_logical_turns(&rules, &snapshot, &[]).unwrap();
            for (rank_index, raw_move) in raw_moves.iter().enumerate() {
                let primary = decode_legal(&rules, &snapshot, raw_move).unwrap();
                let expected = turns
                    .iter()
                    .filter(|turn| turn.actions.first() == Some(&primary) && turn.actions.len() > 1)
                    .count();
                if expected < 2 {
                    continue;
                }

                let replayed = ReplayedPosition::replay(&PositionRequest {
                    rule: RulePreset::Nmm,
                    initial: fen.clone(),
                    history_origin: HistoryOrigin::FreshSetup,
                    actions: Vec::new(),
                    expected_current_fen: None,
                })
                .unwrap();
                let result = query(&replayed, None).unwrap();
                let branches = result
                    .candidates
                    .iter()
                    .filter(|candidate| candidate.source_rank == Some(rank_index + 1))
                    .collect::<Vec<_>>();
                assert_eq!(branches.len(), expected);
                assert!(branches.iter().all(|candidate| {
                    candidate.source_group_id == Some(format!("book-rank-{}", rank_index + 1))
                        && candidate.contains_removal
                        && candidate.removal_action.is_some()
                        && candidate.full_turn_actions.len() > 1
                        && candidate.logical_ply_delta == 1
                }));
                return;
            }
        }
        panic!("bundled NMM book must contain a mill-closing move with removal choices");
    }

    #[test]
    fn book_miss_is_distinct_from_asset_integrity_errors() {
        let replayed = ReplayedPosition::replay(&PositionRequest {
            rule: RulePreset::Nmm,
            initial: "startpos".to_owned(),
            history_origin: HistoryOrigin::GameStart,
            actions: vec!["a1".to_owned()],
            expected_current_fen: None,
        })
        .unwrap();
        assert!(query(&replayed, None).unwrap().candidates.is_empty());

        let duplicate = br#"{
            "schemaVersion":1,
            "variant":"nmm",
            "symmetry":"ring16",
            "oracle":{
                "********/********/******** w p p 0 9 0 9 0 0 -1 -1 -1 -1 0 0 1 ids:nodes":
                    ["d2","d2"]
            },
            "openings":[]
        }"#;
        let error = BookAsset::parse(RulePreset::Nmm, duplicate, "fixture".to_owned()).unwrap_err();
        assert_eq!(error.code, "asset_integrity_error");
    }

    #[test]
    fn missing_malformed_and_illegal_assets_have_distinct_errors() {
        let missing = std::env::temp_dir().join(format!(
            "sanmill_missing_opening_book_{}.json",
            std::process::id()
        ));
        let error = BookAsset::load(RulePreset::Nmm, Some(missing.to_str().unwrap())).unwrap_err();
        assert_eq!(error.code, "asset_missing");

        let error =
            BookAsset::parse(RulePreset::Nmm, b"not JSON", "fixture".to_owned()).unwrap_err();
        assert_eq!(error.code, "asset_parse_error");

        let illegal = br#"{
            "schemaVersion":1,
            "variant":"nmm",
            "symmetry":"ring16",
            "oracle":{
                "********/********/******** w p p 0 9 0 9 0 0 -1 -1 -1 -1 0 0 1 ids:nodes":
                    ["d2-d6"]
            },
            "openings":[]
        }"#;
        let error = BookAsset::parse(RulePreset::Nmm, illegal, "fixture".to_owned()).unwrap_err();
        assert_eq!(error.code, "illegal_source_move");
    }
}
