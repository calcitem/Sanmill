// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

use tgf_core::GameRules;

use super::*;
use crate::rules::{MillActionKind, MillVariantOptions};

fn rules() -> MillRules {
    MillRules::new(MillVariantOptions::default())
}

#[test]
fn empty_board_key_matches_human_db_builder() {
    let fen = "********/********/******** w p p 0 9 0 9 0 0 -1 -1 -1 -1 0 0 1 ids:nodes";
    let (key, sym_idx) = state_key_from_fen(fen).expect("initial FEN must parse");

    assert_eq!(key, "........................|W|place|0|0|0|0");
    assert_eq!(sym_idx, 0);
}

#[test]
fn node_order_exports_nmm_outer_middle_inner_board_string() {
    let fen = "********/@***O***/******** w p p 1 8 1 8 0 0 -1 -1 -1 -1 0 0 2 ids:nodes";
    let state = rules().set_from_fen(fen).expect("fixture FEN must parse");

    assert_eq!(nmm_board24(state.board()), ".........B...W..........");
}

#[test]
fn notation_transform_handles_move_with_capture() {
    assert_eq!(
        transform_notation("d6-d7xa4", 2).as_deref(),
        Some("d2-d1xg4"),
    );
    assert_eq!(
        transform_notation("d2-d1xg4", SYM_INVERSE[2]).as_deref(),
        Some("d6-d7xa4"),
    );
}

#[test]
fn state_key_round_trips_through_fen() {
    let fen = "********/@***O***/******** w p p 1 8 1 8 0 0 -1 -1 -1 -1 0 0 2 ids:nodes";
    let (key, _) = state_key_from_fen(fen).expect("fixture FEN must produce a key");
    let decoded_fen = fen_from_state_key(&key).expect("key must decode back to a FEN");
    let (key_again, _) = state_key_from_fen(&decoded_fen).expect("decoded FEN must produce a key");
    assert_eq!(key, key_again, "state_key must be a fixed point");
}

#[test]
fn parse_human_turn_notation_accepts_the_three_turn_shapes() {
    let rules = rules();
    let snap = rules.initial_state(&[]);

    // BaseOnly: a plain opening placement.
    let turn = parse_human_turn_notation(&rules, &snap, "d6").expect("d6 must parse");
    match turn {
        HumanTurn::BaseOnly(action) => {
            assert_eq!(action.kind_tag, MillActionKind::Place as i16);
        }
        other => panic!("expected BaseOnly, got {other:?}"),
    }

    // Build a position where a placement forms a mill so BaseThenCapture
    // and CaptureOnly both have a real reference frame. White places d6,
    // d5; Black places b4, b2; White's d7 then closes the d5-d6-d7 mill.
    let mut snap = snap;
    for token in ["d6", "b4", "d5", "b2"] {
        let turn = parse_human_turn_notation(&rules, &snap, token).expect("setup move");
        let HumanTurn::BaseOnly(action) = turn else {
            panic!("setup moves are plain placements");
        };
        snap = rules.apply(&snap, action);
    }

    let combined =
        parse_human_turn_notation(&rules, &snap, "d7xb4").expect("mill + capture must parse");
    let HumanTurn::BaseThenCapture { base, capture } = combined else {
        panic!("expected BaseThenCapture, got {combined:?}");
    };
    assert_eq!(base.kind_tag, MillActionKind::Place as i16);
    assert_eq!(capture.kind_tag, MillActionKind::Remove as i16);

    // CaptureOnly is validated against a pending-removal snapshot.
    let pending = rules.apply(&snap, base);
    let capture_only =
        parse_human_turn_notation(&rules, &pending, "xb4").expect("bare capture must parse");
    assert_eq!(capture_only, HumanTurn::CaptureOnly(capture));
}

#[test]
fn parse_human_turn_notation_rejects_each_failure_mode() {
    let rules = rules();
    let snap = rules.initial_state(&[]);

    // Base segment garbage.
    assert_eq!(
        parse_human_turn_notation(&rules, &snap, "z9"),
        Err(HumanTurnError::BaseInvalid)
    );
    // Capture attached to a non-mill-forming base.
    assert_eq!(
        parse_human_turn_notation(&rules, &snap, "d6xb4"),
        Err(HumanTurnError::UnexpectedCapture)
    );
    // Bare capture with no pending removal.
    assert_eq!(
        parse_human_turn_notation(&rules, &snap, "xd6"),
        Err(HumanTurnError::CaptureInvalid)
    );

    // Capture segment must be validated in the post-base frame: removing a
    // point that is empty there is invalid even though the base is fine.
    let mut snap = snap;
    for token in ["d6", "b4", "d5", "b2"] {
        let HumanTurn::BaseOnly(action) =
            parse_human_turn_notation(&rules, &snap, token).expect("setup move")
        else {
            panic!("setup moves are plain placements");
        };
        snap = rules.apply(&snap, action);
    }
    assert_eq!(
        parse_human_turn_notation(&rules, &snap, "d7xg1"),
        Err(HumanTurnError::CaptureInvalid),
        "capturing an empty point must fail in the post-base frame"
    );
}

#[test]
fn stable_hash_is_deterministic_and_sensitive_to_input() {
    let a = stable_hash("abc");
    let b = stable_hash("abc");
    let c = stable_hash("abd");
    assert_eq!(a, b);
    assert_ne!(a, c);
}
