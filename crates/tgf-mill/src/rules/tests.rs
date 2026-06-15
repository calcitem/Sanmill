// SPDX-License-Identifier: GPL-3.0-or-later
// Unit tests for `crates/tgf-mill/src/rules/mod.rs`.  Hosted in a
// dedicated file so the main rules module stays under the 1k-line bar.

use super::*;
use tgf_core::{Evaluator, Game, GameRules, GameStateSnapshot, Workbench};

#[test]
fn initial_state_has_24_placing_actions() {
    let rules = MillRules::default();
    let snap = rules.initial_state(&[]);
    let mut actions = ActionList::<256>::new();
    rules.legal_actions(&snap, &mut actions);
    assert_eq!(actions.len(), 24);
    assert!(
        actions
            .iter()
            .all(|a| a.kind_tag == MillActionKind::Place as i16)
    );
}

/// Regression (bench MCTS self-play crash): a terminal state can carry a
/// stale `action == Remove` together with the GameOver side-to-move
/// sentinel `-1` -- the fewer-than-three Remove branch sets
/// `side_to_move = -1` without re-syncing the cached `action` byte.  MCTS
/// node expansion generates moves for such a terminal child, so legal-action
/// generation must return an empty list instead of indexing
/// `pending_removals[(-1) as usize]` out of bounds.
#[test]
fn legal_actions_on_terminal_remove_state_is_empty() {
    let rules = MillRules::default();
    let terminal = MillState {
        phase: MillPhase::GameOver,
        side_to_move: -1,
        action: MillActionState::Remove,
        winner: 0,
        outcome_reason: MillOutcomeReason::LoseFewerThanThree,
        ..Default::default()
    };
    let snap = rules.encode_state(terminal);

    // MCTS expansion path: `Game::generate_legal_ctx` on the terminal
    // workbench (this is what panicked in `legal_actions_ctx`).
    let game = MillGame::default();
    let wb = game.build_workbench(&snap);
    let mut ctx_actions = ActionList::<256>::new();
    MillGame::generate_legal_ctx(
        &wb,
        &mut ctx_actions,
        &tgf_core::MoveOrderContext::default(),
    );
    assert!(ctx_actions.is_empty());

    // Trait path: `GameRules::legal_actions`.
    let mut actions = ActionList::<256>::new();
    rules.legal_actions(&snap, &mut actions);
    assert!(actions.is_empty());
}

/// Regression for the `apply_unchecked` memory-safety guard:
/// caller-supplied actions whose `from_node` / `to_node` falls
/// outside the 0..24 board range must not panic; instead the rules
/// engine returns the input snapshot unchanged so the FFI boundary
/// can recover.  The "unchecked" path skips the slow legality
/// lookup; it must not skip basic memory-safety bounds.
#[test]
fn apply_with_out_of_range_action_is_a_noop() {
    let rules = MillRules::default();
    let snap = rules.initial_state(&[]);
    for bogus_to in [-2_i16, 24, 99, i16::MAX] {
        let action = Action {
            kind_tag: MillActionKind::Place as i16,
            from_node: -1,
            to_node: bogus_to,
            aux: -1,
            payload_bits: 0,
        };
        let result = rules.apply(&snap, action);
        assert_eq!(
            result, snap,
            "out-of-range to_node={bogus_to} must yield an unmodified snapshot",
        );
    }
    for bogus_from in [-2_i16, 24, 99, i16::MAX] {
        let action = Action {
            kind_tag: MillActionKind::Move as i16,
            from_node: bogus_from,
            to_node: 0,
            aux: -1,
            payload_bits: 0,
        };
        let result = rules.apply(&snap, action);
        assert_eq!(
            result, snap,
            "out-of-range from_node={bogus_from} must yield an unmodified snapshot",
        );
    }
}

#[test]
fn place_action_reduces_hand_and_switches_side() {
    let rules = MillRules::default();
    let snap = rules.initial_state(&[]);
    let next = rules.apply(
        &snap,
        Action {
            kind_tag: MillActionKind::Place as i16,
            from_node: -1,
            to_node: 0,
            aux: -1,
            payload_bits: 0,
        },
    );
    let state = MillRules::decode(&next);
    assert_eq!(state.board[0], 1);
    assert_eq!(state.side_to_move, 1);
    assert_eq!(state.pieces_in_hand[0], 8);
    assert_eq!(state.pieces_on_board[0], 1);
}

#[test]
fn place_action_resets_ply_since_capture_counter() {
    let rules = MillRules::default();
    let mut state = MillRules::decode(&rules.initial_state(&[]));
    state.ply_since_capture = 42;

    let after = rules.apply(
        &rules.encode(state),
        Action {
            kind_tag: MillActionKind::Place as i16,
            from_node: -1,
            to_node: 0,
            aux: -1,
            payload_bits: 0,
        },
    );

    let state = MillRules::decode(&after);
    assert_eq!(state.ply_since_capture, 0);
}

#[test]
fn move_order_bias_star_square_matches_movepick_rating() {
    use tgf_core::Game;

    let rules = MillRules::default();
    let game = MillGame::default();
    let mut snap = rules.initial_state(&[]);
    for n in [0_i16, 1, 2] {
        snap = rules.apply(
            &snap,
            Action {
                kind_tag: MillActionKind::Place as i16,
                from_node: -1,
                to_node: n,
                aux: -1,
                payload_bits: 0,
            },
        );
    }
    let wb = game.build_workbench(&snap);
    assert_eq!(wb.state.side_to_move, 1);
    let star_place = Action {
        kind_tag: MillActionKind::Place as i16,
        from_node: -1,
        // Legacy SQ_16 ("d6") is a C++ star-priority square.
        // In Rust's dense node numbering it is node 9.
        to_node: 9,
        aux: -1,
        payload_bits: 0,
    };
    assert_eq!(
        <MillGame as Game>::move_order_bias_ctx(
            &wb,
            star_place,
            &tgf_core::MoveOrderContext {
                algorithm: tgf_core::MoveOrderAlgorithm::Mcts,
                ..Default::default()
            }
        ),
        11
    );
    let non_star = Action {
        kind_tag: MillActionKind::Place as i16,
        from_node: -1,
        to_node: 3,
        aux: -1,
        payload_bits: 0,
    };
    assert_eq!(<MillGame as Game>::move_order_bias(&wb, non_star), 0);
}

#[test]
fn move_order_bias_mcts_enables_star_square_without_diagonals() {
    use tgf_core::{Game, MoveOrderAlgorithm, MoveOrderContext};

    let rules = MillRules::default();
    let game = MillGame::default();
    let mut snap = rules.initial_state(&[]);
    for n in [0_i16, 2] {
        snap = rules.apply(
            &snap,
            Action {
                kind_tag: MillActionKind::Place as i16,
                from_node: -1,
                to_node: n,
                aux: -1,
                payload_bits: 0,
            },
        );
    }
    snap = rules.apply(
        &snap,
        Action {
            kind_tag: MillActionKind::Place as i16,
            from_node: -1,
            to_node: 4,
            aux: -1,
            payload_bits: 0,
        },
    );
    let wb = game.build_workbench(&snap);
    let star_place = Action {
        kind_tag: MillActionKind::Place as i16,
        from_node: -1,
        to_node: 9,
        aux: -1,
        payload_bits: 0,
    };

    assert_eq!(<MillGame as Game>::move_order_bias(&wb, star_place), 0);
    assert_eq!(
        <MillGame as Game>::move_order_bias_ctx(
            &wb,
            star_place,
            &MoveOrderContext {
                algorithm: MoveOrderAlgorithm::Mcts,
                ..Default::default()
            },
        ),
        RATING_STAR_SQUARE
    );
}

#[test]
fn star_square_mapping_matches_legacy_move_priority() {
    // Matches C++ `Mills::move_priority_list_shuffle`:
    //   standard: SQ_16, SQ_18, SQ_20, SQ_22
    //   diagonal: SQ_17, SQ_19, SQ_21, SQ_23
    // converted through `MillTopology::square_to_node`.
    let standard = MillVariantOptions::default();
    assert!(is_star_square(&standard, 9)); // SQ_16 / d6
    assert!(is_star_square(&standard, 11)); // SQ_18 / f4
    assert!(is_star_square(&standard, 13)); // SQ_20 / d2
    assert!(is_star_square(&standard, 15)); // SQ_22 / b4
    assert!(!is_star_square(&standard, 16)); // SQ_15 / c5

    let diagonal = MillVariantOptions {
        has_diagonal_lines: true,
        ..Default::default()
    };
    assert!(is_star_square(&diagonal, 10)); // SQ_17 / f6
    assert!(is_star_square(&diagonal, 12)); // SQ_19 / f2
    assert!(is_star_square(&diagonal, 14)); // SQ_21 / b2
    assert!(is_star_square(&diagonal, 8)); // SQ_23 / b6
    assert!(!is_star_square(&diagonal, 17)); // SQ_8 / d5
}

#[test]
fn move_order_bias_prefers_completing_own_mill_and_blocking_opponent() {
    use tgf_core::Game;

    let rules = MillRules::default();
    let game = MillGame::default();
    // White already owns 0 and 2: placing on 1 closes the a7-b7-c7 mill,
    // matching the `RATING_ONE_MILL` weight (=11) in `movepick.cpp`.
    // Black already owns 4 and 6: placing on 5 instead would only block
    // black's mill, which scores `RATING_BLOCK_ONE_MILL` (=10).
    let mut board = [0_i8; 24];
    board[0] = 1;
    board[2] = 1;
    board[4] = 2;
    board[6] = 2;
    let state = MillState {
        board,
        side_to_move: 0,
        phase: MillPhase::Placing,
        pieces_in_hand: [9, 9],
        ..MillState::default()
    };
    let snap = rules.encode(state);
    let wb = game.build_workbench(&snap);

    let close_own_mill = Action {
        kind_tag: MillActionKind::Place as i16,
        from_node: -1,
        to_node: 1,
        aux: -1,
        payload_bits: 0,
    };
    let block_opponent_mill = Action {
        kind_tag: MillActionKind::Place as i16,
        from_node: -1,
        to_node: 5,
        aux: -1,
        payload_bits: 0,
    };

    assert_eq!(<MillGame as Game>::move_order_bias(&wb, close_own_mill), 0);
    assert_eq!(
        <MillGame as Game>::move_order_bias_ctx(&wb, close_own_mill, &Default::default()),
        RATING_ONE_MILL
    );
    assert_eq!(
        <MillGame as Game>::move_order_bias_ctx(&wb, block_opponent_mill, &Default::default()),
        RATING_BLOCK_ONE_MILL
    );
}

#[test]
fn move_order_bias_remove_prefers_high_mobility_targets() {
    use tgf_core::Game;

    let rules = MillRules::default();
    let game = MillGame::default();
    // Black piece at d7 (1) has both adjacent ring nodes empty, so
    // empty_count (mobility) = 3 making it a high-value remove target.
    // Black piece at c5 (16) sits between two filled black neighbours
    // (17 and 23 are also black) so empty_count = 0 and the
    // RATING_BLOCK_ONE_MILL-block heuristic does not fire.
    let mut board = [0_i8; 24];
    board[1] = 2;
    board[16] = 2;
    board[17] = 2;
    board[23] = 2;
    let state = MillState {
        board,
        side_to_move: 0,
        phase: MillPhase::Moving,
        pending_removals: [1, 0],
        mill_available_at_removal: true,
        pieces_on_board: [3, 4],
        ..MillState::default()
    };
    let snap = rules.encode(state);
    let wb = game.build_workbench(&snap);

    let mobile_target = Action {
        kind_tag: MillActionKind::Remove as i16,
        from_node: -1,
        to_node: 1,
        aux: -1,
        payload_bits: 0,
    };
    let surrounded_target = Action {
        kind_tag: MillActionKind::Remove as i16,
        from_node: -1,
        to_node: 16,
        aux: -1,
        payload_bits: 0,
    };

    assert_eq!(<MillGame as Game>::move_order_bias(&wb, mobile_target), 0);
    let mobile_score =
        <MillGame as Game>::move_order_bias_ctx(&wb, mobile_target, &Default::default());
    let surrounded_score =
        <MillGame as Game>::move_order_bias_ctx(&wb, surrounded_target, &Default::default());
    assert!(
        mobile_score > surrounded_score,
        "high-mobility remove target should out-score a surrounded one (mobile={}, surrounded={})",
        mobile_score,
        surrounded_score,
    );
}

#[test]
fn mill_formation_generates_remove_actions_and_keeps_turn() {
    let rules = MillRules::default();
    let mut snap = rules.initial_state(&[]);

    // Equivalent to the C++ golden scenario:
    // W: d7(1), B: a1(6), W: g7(2), B: d1(5), W: a7(0)
    // White completes a7-d7-g7 and must remove one black piece.
    for node in [1, 6, 2, 5, 0] {
        snap = rules.apply(
            &snap,
            Action {
                kind_tag: MillActionKind::Place as i16,
                from_node: -1,
                to_node: node,
                aux: -1,
                payload_bits: 0,
            },
        );
    }

    let state = MillRules::decode(&snap);
    assert_eq!(state.side_to_move, 0, "White keeps turn until removal");
    assert_eq!(state.pending_removals[0], 1);

    let mut actions = ActionList::<256>::new();
    rules.legal_actions(&snap, &mut actions);
    assert_eq!(actions.len(), 2);
    assert!(
        actions
            .iter()
            .all(|a| a.kind_tag == MillActionKind::Remove as i16)
    );
    assert!(actions.iter().any(|a| a.to_node == 6)); // a1
    assert!(actions.iter().any(|a| a.to_node == 5)); // d1

    let after_remove = rules.apply(
        &snap,
        Action {
            kind_tag: MillActionKind::Remove as i16,
            from_node: -1,
            to_node: 6,
            aux: -1,
            payload_bits: 0,
        },
    );
    let state = MillRules::decode(&after_remove);
    assert_eq!(state.board[6], 0);
    assert_eq!(state.side_to_move, 1, "Turn passes to black after removal");
    assert_eq!(state.pending_removals[0], 0);
    assert_eq!(state.pieces_on_board[1], 1);
}

#[test]
fn placing_mill_f2_f4_f6_generates_remove_actions_for_black() {
    // Replicates the exact sequence reported in the bug:
    //   1. d2 d6   (W node 13, B node 9)
    //   2. f4 b4   (W node 11, B node 15)
    //   3. f2 g4   (W node 12, B node 3)
    //   4. f6      (W node 10) → forms mill [10,11,12] (f6-f4-f2)
    //
    // After White places f6, pending_removals[0] must be 1 and
    // legal_actions must include remove actions for every Black piece.
    let rules = MillRules::default();
    let mut snap = rules.initial_state(&[]);
    for node in [13_i16, 9, 11, 15, 12, 3, 10] {
        snap = rules.apply(
            &snap,
            Action {
                kind_tag: MillActionKind::Place as i16,
                from_node: -1,
                to_node: node,
                aux: -1,
                payload_bits: 0,
            },
        );
    }

    let state = MillRules::decode(&snap);
    assert_eq!(
        state.side_to_move, 0,
        "White keeps turn after forming the mill"
    );
    assert_eq!(
        state.pending_removals[0], 1,
        "White must remove one Black piece"
    );

    let mut actions = ActionList::<256>::new();
    rules.legal_actions(&snap, &mut actions);
    assert_eq!(
        actions.len(),
        3,
        "Exactly three remove actions (one per Black piece)"
    );
    assert!(
        actions
            .iter()
            .all(|a| a.kind_tag == MillActionKind::Remove as i16),
        "All actions must be Remove"
    );
    assert!(
        actions.iter().any(|a| a.to_node == 9),
        "xd6 (node 9) must be a legal remove target"
    );
    assert!(
        actions.iter().any(|a| a.to_node == 15),
        "xb4 (node 15) must be a legal remove target"
    );
    assert!(
        actions.iter().any(|a| a.to_node == 3),
        "xg4 (node 3) must be a legal remove target"
    );
}

fn placing_mill_fixture_for_action(
    action: MillFormationActionInPlacingPhase,
) -> (MillRules, GameStateSnapshot) {
    let rules = MillRules::new(MillVariantOptions {
        mill_formation_action_in_placing_phase: action,
        ..MillVariantOptions::default()
    });
    let mut snap = rules.initial_state(&[]);
    for node in [1, 6, 2, 5, 0] {
        snap = rules.apply(
            &snap,
            Action {
                kind_tag: MillActionKind::Place as i16,
                from_node: -1,
                to_node: node,
                aux: -1,
                payload_bits: 0,
            },
        );
    }
    (rules, snap)
}

#[test]
fn mill_action_remove_from_hand_then_opponent_turn() {
    let (_rules, snap) = placing_mill_fixture_for_action(
        MillFormationActionInPlacingPhase::RemoveOpponentsPieceFromHandThenOpponentsTurn,
    );
    let state = MillRules::decode(&snap);
    assert_eq!(state.pieces_in_hand[1], 6, "black lost one piece from hand");
    assert_eq!(state.pending_removals[0], 0);
    assert_eq!(state.side_to_move, 1, "turn passes to opponent");
}

/// Dooz regression (oracle rule_idx 2): when the in-hand removal
/// empties the opponent's hand mid-placing, C++ `set_side_to_move`
/// derives the phase from the active side's hand count, so the
/// opponent answers with board moves while the mill former still
/// holds pieces in hand — and the phase flips back to placing once
/// the turn returns.
#[test]
fn from_hand_removal_emptying_opponent_hand_starts_their_moving_turn() {
    let rules = MillRules::new(MillVariantOptions {
        mill_formation_action_in_placing_phase:
            MillFormationActionInPlacingPhase::RemoveOpponentsPieceFromHandThenOpponentsTurn,
        ..MillVariantOptions::default()
    });
    let mut state = MillState {
        side_to_move: 0,
        phase: MillPhase::Placing,
        move_number: 8,
        pieces_in_hand: [2, 1],
        pieces_on_board: [2, 3],
        pending_removals: [0, 0],
        winner: -1,
        ..MillState::default()
    };
    // White completes the [0, 1, 2] line by placing at 2; black owns
    // 16..=18 on the outer ring.
    state.board[0] = 1;
    state.board[1] = 1;
    for node in 16_usize..=18 {
        state.board[node] = 2;
    }

    let snap = rules.apply(
        &rules.encode(state),
        Action {
            kind_tag: MillActionKind::Place as i16,
            from_node: -1,
            to_node: 2,
            aux: -1,
            payload_bits: 0,
        },
    );
    let state = MillRules::decode(&snap);
    assert_eq!(
        state.pieces_in_hand,
        [1, 0],
        "the removal must come from black's hand"
    );
    assert_eq!(state.side_to_move, 1, "turn passes to the opponent");
    assert_eq!(
        state.phase,
        MillPhase::Moving,
        "black has no hand pieces left, so black moves on the board"
    );

    let mut actions = ActionList::<256>::new();
    rules.legal_actions(&snap, &mut actions);
    assert!(
        !actions.is_empty(),
        "black must receive board moves, not an empty legal set"
    );
    assert!(
        actions
            .iter()
            .all(|a| a.kind_tag == MillActionKind::Move as i16)
    );

    // Black answers 16 -> 23 (no mill); the turn returns to White who
    // still holds one piece in hand, so the phase flips back to placing.
    let snap = rules.apply(
        &snap,
        Action {
            kind_tag: MillActionKind::Move as i16,
            from_node: 16,
            to_node: 23,
            aux: -1,
            payload_bits: 0,
        },
    );
    let state = MillRules::decode(&snap);
    assert_eq!(state.side_to_move, 0);
    assert_eq!(state.phase, MillPhase::Placing);
    let mut actions = ActionList::<256>::new();
    rules.legal_actions(&snap, &mut actions);
    assert!(
        actions
            .iter()
            .all(|a| a.kind_tag == MillActionKind::Place as i16),
        "white is still placing and Dooz has no move-in-placing option"
    );
}

#[test]
fn mill_action_remove_from_hand_then_your_turn() {
    let (_rules, snap) = placing_mill_fixture_for_action(
        MillFormationActionInPlacingPhase::RemoveOpponentsPieceFromHandThenYourTurn,
    );
    let state = MillRules::decode(&snap);
    assert_eq!(state.pieces_in_hand[1], 6, "black lost one piece from hand");
    assert_eq!(state.pending_removals[0], 0);
    assert_eq!(state.side_to_move, 0, "active player keeps the turn");
}

#[test]
fn mill_action_opponent_removes_own_piece() {
    let (rules, snap) =
        placing_mill_fixture_for_action(MillFormationActionInPlacingPhase::OpponentRemovesOwnPiece);
    let state = MillRules::decode(&snap);
    assert_eq!(state.side_to_move, 1);
    assert_eq!(state.pending_removals[1], 1);
    let mut actions = ActionList::<256>::new();
    rules.legal_actions(&snap, &mut actions);
    // Opponent removes one of White's pieces; at least the just formed
    // mill pieces are legal targets.
    assert!(
        actions
            .iter()
            .all(|a| a.kind_tag == MillActionKind::Remove as i16)
    );
    assert!(actions.iter().any(|a| a.to_node == 0));
    assert!(actions.iter().any(|a| a.to_node == 1));
    assert!(actions.iter().any(|a| a.to_node == 2));
}

#[test]
fn mill_action_removal_based_on_mill_counts_waits_until_placing_end() {
    let (_rules, snap) = placing_mill_fixture_for_action(
        MillFormationActionInPlacingPhase::RemovalBasedOnMillCounts,
    );
    let state = MillRules::decode(&snap);
    assert_eq!(state.pending_removals, [0, 0]);
    assert_eq!(
        state.side_to_move, 1,
        "no removal until all pieces are placed"
    );
}

#[test]
fn mill_action_removal_based_on_mill_counts_assigns_at_placing_end() {
    let rules = MillRules::new(MillVariantOptions {
        mill_formation_action_in_placing_phase:
            MillFormationActionInPlacingPhase::RemovalBasedOnMillCounts,
        ..MillVariantOptions::default()
    });
    let mut state = MillState {
        board: {
            let mut board = [0_i8; 24];
            // White has one mill a7-d7-g7; black has no mills.
            board[0] = 1;
            board[1] = 1;
            board[2] = 1;
            board[6] = 2;
            board[11] = 2;
            board[14] = 2;
            board
        },
        side_to_move: 0,
        phase: MillPhase::Placing,
        move_number: 17,
        pieces_in_hand: [1, 0],
        pieces_on_board: [3, 3],
        pending_removals: [0, 0],
        winner: -1,
        ..MillState::default()
    };
    // Add a harmless final white piece that does not create another mill.
    state.board[8] = 0;
    let after = rules.apply(
        &rules.encode(state),
        Action {
            kind_tag: MillActionKind::Place as i16,
            from_node: -1,
            to_node: 8,
            aux: -1,
            payload_bits: 0,
        },
    );
    let state = MillRules::decode(&after);
    assert_eq!(state.phase, MillPhase::Moving);
    assert_eq!(
        state.pending_removals,
        [2, 1],
        "white has mills while black has none, matching C++ removalBasedOnMillCounts"
    );
}

/// `MarkAndDelayRemovingPieces` mirrors C++ position.cpp: mill formation
/// arms a regular remove obligation, and the chosen target is *marked*
/// (kept on the board with its colour) instead of physically removed.
/// Marked pieces stay until the placing-to-moving boundary, where
/// `enter_moving_phase` calls the equivalent of `remove_marked_pieces`
/// to sweep them.
#[test]
fn mill_action_mark_and_delay_arms_remove_then_marks_target() {
    let (rules, snap) = placing_mill_fixture_for_action(
        MillFormationActionInPlacingPhase::MarkAndDelayRemovingPieces,
    );
    let state = MillRules::decode(&snap);
    // Active side now owes a removal obligation against the opponent.
    assert_eq!(state.pending_removals[0], 1);
    assert_eq!(state.side_to_move, 0);
    assert!(state.mill_available_at_removal);

    // Pick any opponent piece to "mark".
    let mut actions = ActionList::<256>::new();
    rules.legal_actions(&snap, &mut actions);
    let target = actions
        .iter()
        .copied()
        .find(|a| a.kind_tag == MillActionKind::Remove as i16)
        .expect("at least one remove target");
    let after = rules.apply(&snap, target);
    let state = MillRules::decode(&after);
    // Target square keeps its colour but is now flagged as marked.
    assert_eq!(state.board[target.to_node as usize], 2, "still owns colour");
    assert!(
        (state.delayed_marked_pieces & (1u32 << target.to_node)) != 0,
        "square must be flagged as marked"
    );
    // Live mill / mobility helpers must treat the marked cell as empty.
    assert_eq!(live_piece(&state, target.to_node as usize), 0);
}

/// On the placing-to-moving boundary every marked piece must clear,
/// matching `Position::remove_marked_pieces`.
#[test]
fn mark_and_delay_marked_pieces_sweep_on_phase_transition() {
    let options = MillVariantOptions {
        mill_formation_action_in_placing_phase:
            MillFormationActionInPlacingPhase::MarkAndDelayRemovingPieces,
        ..MillVariantOptions::default()
    };
    // Build a placing-end snapshot with a single marked piece.
    let mut state = MillState {
        side_to_move: 0,
        phase: MillPhase::Placing,
        move_number: 17,
        pieces_in_hand: [0, 0],
        pieces_on_board: [9, 8],
        pending_removals: [0, 0],
        ..MillState::default()
    };
    state.board[0] = 2;
    state.delayed_marked_pieces = 1u32 << 0;
    enter_moving_phase(&mut state, &options);
    assert_eq!(state.phase, MillPhase::Moving);
    assert_eq!(
        state.board[0], 0,
        "marked square must be cleared on entering moving phase"
    );
    assert_eq!(state.delayed_marked_pieces, 0);
}

/// `RemovalBasedOnMillCounts` reaches the placing-to-moving boundary
/// with neither side having formed a mill.  Master `position.cpp`
/// signals "remove your own piece" by setting
/// `pieceToRemoveCount[c] = -1` for both sides; the Rust port models
/// this with `remove_own_piece[c]=true` plus `pending_removals[c]=1`.
/// The legal-action set after the final placement must enumerate own
/// pieces, not opponent pieces.
#[test]
fn mill_action_removal_based_on_mill_counts_double_zero_removes_own_piece() {
    let rules = MillRules::new(MillVariantOptions {
        mill_formation_action_in_placing_phase:
            MillFormationActionInPlacingPhase::RemovalBasedOnMillCounts,
        ..MillVariantOptions::default()
    });
    // Build a placing-end position where neither side has a mill.  Each
    // side has placed 8 pieces; white is about to place its last.
    let mut state = MillState {
        side_to_move: 0,
        phase: MillPhase::Placing,
        move_number: 17,
        pieces_in_hand: [1, 0],
        pieces_on_board: [8, 9],
        pending_removals: [0, 0],
        winner: -1,
        ..MillState::default()
    };
    // White on nodes 0,3,6,9,12,15,18,21 (no mill thanks to gaps).
    for &n in &[0_usize, 3, 6, 9, 12, 15, 18, 21] {
        state.board[n] = 1;
    }
    // Black on nodes 2,5,8,11,14,17,20,23 + one extra on 4 (no mill).
    for &n in &[2_usize, 5, 8, 11, 14, 17, 20, 23, 4] {
        state.board[n] = 2;
    }
    // White places at node 1 — still no mills for either side.
    let after = rules.apply(
        &rules.encode(state),
        Action {
            kind_tag: MillActionKind::Place as i16,
            from_node: -1,
            to_node: 1,
            aux: -1,
            payload_bits: 0,
        },
    );
    let state = MillRules::decode(&after);
    assert_eq!(state.phase, MillPhase::Moving);
    assert_eq!(
        state.pending_removals,
        [1, 1],
        "double-zero mills schedules one removal per side"
    );
    assert_eq!(
        state.remove_own_piece,
        [true, true],
        "negative pieceToRemoveCount semantics: each side removes own"
    );

    let mut actions = ActionList::<256>::new();
    rules.legal_actions(&after, &mut actions);
    assert!(!actions.is_empty(), "must offer at least one legal removal");
    let active = state.side_to_move;
    let own_color = active + 1;
    for action in actions.iter() {
        assert_eq!(action.kind_tag, MillActionKind::Remove as i16);
        assert_eq!(
            state.board[action.to_node as usize], own_color,
            "removal must target the active side's own piece, not opponent"
        );
    }

    // Apply one of the own-piece removals and confirm the flag clears.
    let pick = actions.iter().next().copied().unwrap();
    let after = rules.apply(&after, pick);
    let state = MillRules::decode(&after);
    assert!(
        !state.remove_own_piece[active as usize],
        "remove_own_piece flag must clear once quota reaches zero"
    );
}

#[test]
fn remove_own_piece_respects_mill_protection() {
    let rules = MillRules::default();
    let state = MillState {
        board: {
            let mut board = [0_i8; 24];
            for node in [0_usize, 1, 2, 6] {
                board[node] = 1;
            }
            for node in [8_usize, 11, 14] {
                board[node] = 2;
            }
            board
        },
        side_to_move: 0,
        phase: MillPhase::Moving,
        move_number: 30,
        pieces_in_hand: [0, 0],
        pieces_on_board: [4, 3],
        pending_removals: [1, 0],
        remove_own_piece: [true, false],
        winner: -1,
        ..MillState::default()
    };

    let mut actions = ActionList::<256>::new();
    rules.legal_actions(&rules.encode(state), &mut actions);

    assert_eq!(actions.len(), 1);
    assert_eq!(
        actions.iter().next().unwrap().to_node,
        6,
        "own pieces in a mill stay protected while a non-mill target exists"
    );
}

fn stalemate_fixture() -> MillState {
    let mut state = MillState {
        side_to_move: 0,
        phase: MillPhase::Moving,
        move_number: 30,
        pieces_in_hand: [0, 0],
        pieces_on_board: [4, 4],
        pending_removals: [0, 0],
        winner: -1,
        ..MillState::default()
    };
    // White corners are fully blocked by black side-middle pieces.
    for node in [0_usize, 2, 4, 6] {
        state.board[node] = 1;
    }
    for node in [1_usize, 3, 5, 7] {
        state.board[node] = 2;
    }
    state
}

#[test]
fn stalemate_default_action_loses_for_side_to_move() {
    let rules = MillRules::default();
    let mut state = stalemate_fixture();
    rules.maybe_handle_stalemate(&mut state);
    assert_eq!(state.phase, MillPhase::GameOver);
    assert_eq!(state.winner, 1);
    let outcome = rules.outcome(&rules.encode(state));
    assert_eq!(outcome.kind, OutcomeKind::Win(1));
    assert_eq!(outcome.reason, "loseNoLegalMoves");
}

#[test]
fn stalemate_draw_action_draws() {
    let rules = MillRules::new(MillVariantOptions {
        stalemate_action: StalemateAction::EndWithStalemateDraw,
        ..MillVariantOptions::default()
    });
    let mut state = stalemate_fixture();
    rules.maybe_handle_stalemate(&mut state);
    assert_eq!(state.phase, MillPhase::GameOver);
    assert_eq!(state.winner, 2);
    assert_eq!(
        rules.outcome(&rules.encode(state)).reason,
        "drawStalemateCondition"
    );
}

#[test]
fn stalemate_change_side_to_move_only_switches_turn() {
    let rules = MillRules::new(MillVariantOptions {
        stalemate_action: StalemateAction::ChangeSideToMove,
        ..MillVariantOptions::default()
    });
    let mut state = stalemate_fixture();
    rules.maybe_handle_stalemate(&mut state);
    assert_eq!(state.phase, MillPhase::Moving);
    assert_eq!(state.side_to_move, 1);
    assert_eq!(state.pending_removals, [0, 0]);
}

#[test]
fn stalemate_remove_and_make_next_move_keeps_turn_after_remove() {
    let rules = MillRules::new(MillVariantOptions {
        stalemate_action: StalemateAction::RemoveOpponentsPieceAndMakeNextMove,
        ..MillVariantOptions::default()
    });
    let mut state = stalemate_fixture();
    rules.maybe_handle_stalemate(&mut state);
    assert_eq!(state.pending_removals, [1, 0]);
    assert!(state.stalemate_removing);
    let after = rules.apply(
        &rules.encode(state),
        Action {
            kind_tag: MillActionKind::Remove as i16,
            from_node: -1,
            to_node: 1,
            aux: -1,
            payload_bits: 0,
        },
    );
    let state = MillRules::decode(&after);
    assert_eq!(state.side_to_move, 0);
    assert_eq!(state.pending_removals, [0, 0]);
    assert!(!state.stalemate_removing);
}

/// Zhi Qi regression (oracle rule_idx 8): arming a stalemate removal
/// must resync the action state (mirror of `check_if_game_is_over`'s
/// tail in legacy position.cpp) so the legal-action generator emits
/// the removal targets instead of an empty move list, and the
/// stalemate path skips mill protection (mirror of `generate<REMOVE>`),
/// so opponent pieces inside a mill stay removable.
#[test]
fn stalemate_removal_offers_adjacent_targets_without_mill_protection() {
    let rules = MillRules::new(MillVariantOptions {
        stalemate_action: StalemateAction::RemoveOpponentsPieceAndMakeNextMove,
        ..MillVariantOptions::default()
    });
    let mut state = stalemate_fixture();
    // Extend the fixture with a black mill on the [1, 9, 17] spoke.
    state.board[9] = 2;
    state.board[17] = 2;
    state.pieces_on_board[1] += 2;

    let mut state_after = state.clone();
    rules.maybe_handle_stalemate(&mut state_after);
    assert_eq!(state_after.pending_removals, [1, 0]);
    assert!(state_after.stalemate_removing);

    let mut actions = ActionList::<256>::new();
    rules.legal_actions(&rules.encode(state_after), &mut actions);
    assert!(
        !actions.is_empty(),
        "the stalemated side must see removal targets, not an empty set"
    );
    assert!(
        actions
            .iter()
            .all(|a| a.kind_tag == MillActionKind::Remove as i16)
    );
    let targets: std::collections::BTreeSet<i16> = actions.iter().map(|a| a.to_node).collect();
    assert_eq!(
        targets,
        [1_i16, 3, 5, 7].into_iter().collect(),
        "exactly the black pieces adjacent to white are removable"
    );
    assert!(
        targets.contains(&1),
        "node 1 sits in the black mill [1, 9, 17] and must stay removable \
         because the stalemate path bypasses mill protection"
    );
}

#[test]
fn stalemate_remove_and_change_side_switches_turn_after_remove() {
    let rules = MillRules::new(MillVariantOptions {
        stalemate_action: StalemateAction::RemoveOpponentsPieceAndChangeSideToMove,
        ..MillVariantOptions::default()
    });
    let mut state = stalemate_fixture();
    rules.maybe_handle_stalemate(&mut state);
    assert_eq!(state.pending_removals, [1, 0]);
    let after = rules.apply(
        &rules.encode(state),
        Action {
            kind_tag: MillActionKind::Remove as i16,
            from_node: -1,
            to_node: 1,
            aux: -1,
            payload_bits: 0,
        },
    );
    let state = MillRules::decode(&after);
    assert_eq!(state.side_to_move, 1);
    assert_eq!(state.pending_removals, [0, 0]);
}

#[test]
fn stalemate_both_players_remove_in_order() {
    let rules = MillRules::new(MillVariantOptions {
        stalemate_action: StalemateAction::BothPlayersRemoveOpponentsPiece,
        ..MillVariantOptions::default()
    });
    let mut state = stalemate_fixture();
    rules.maybe_handle_stalemate(&mut state);
    assert_eq!(state.pending_removals, [1, 1]);
    assert!(state.both_stalemate_removing);
    let after_first = rules.apply(
        &rules.encode(state),
        Action {
            kind_tag: MillActionKind::Remove as i16,
            from_node: -1,
            to_node: 1,
            aux: -1,
            payload_bits: 0,
        },
    );
    let state = MillRules::decode(&after_first);
    assert_eq!(state.side_to_move, 1);
    assert_eq!(state.pending_removals, [0, 1]);
    let after_second = rules.apply(
        &after_first,
        Action {
            kind_tag: MillActionKind::Remove as i16,
            from_node: -1,
            to_node: 0,
            aux: -1,
            payload_bits: 0,
        },
    );
    let state = MillRules::decode(&after_second);
    assert_eq!(state.side_to_move, 0);
    assert_eq!(state.pending_removals, [0, 0]);
    assert!(!state.both_stalemate_removing);
}

#[test]
fn moving_phase_mill_generates_remove_obligation() {
    let rules = MillRules::default();
    let state = MillState {
        // White can move node 1 -> node 0 to complete outer-top mill
        // [0, 1, 2].  Black has enough material that removal is not
        // terminal.
        board: {
            let mut board = [0_i8; 24];
            board[1] = 1; // W d7
            board[2] = 1; // W g7
            board[3] = 1; // W g4 (moving piece)
            board[6] = 2; // B a1
            board[5] = 2; // B d1
            board[10] = 2; // B f6
            board
        },
        side_to_move: 0,
        phase: MillPhase::Moving,
        move_number: 18,
        pieces_in_hand: [0, 0],
        pieces_on_board: [3, 3],
        pending_removals: [0, 0],
        winner: -1,
        ..MillState::default()
    };
    let snap = rules.encode(state);
    let after_move = rules.apply(
        &snap,
        Action {
            kind_tag: MillActionKind::Move as i16,
            from_node: 3,
            to_node: 0,
            aux: -1,
            payload_bits: 0,
        },
    );

    let state = MillRules::decode(&after_move);
    assert_eq!(state.side_to_move, 0, "White keeps turn after forming mill");
    assert_eq!(state.pending_removals[0], 1);

    let mut actions = ActionList::<256>::new();
    rules.legal_actions(&after_move, &mut actions);
    assert!(
        actions
            .iter()
            .all(|a| a.kind_tag == MillActionKind::Remove as i16)
    );
    assert_eq!(actions.len(), 3);
}

#[test]
fn moving_phase_removal_below_three_ends_game() {
    let rules = MillRules::default();
    let state = MillState {
        board: {
            let mut board = [0_i8; 24];
            board[0] = 1;
            board[1] = 1;
            board[2] = 1;
            board[6] = 2;
            board[5] = 2;
            board
        },
        side_to_move: 0,
        phase: MillPhase::Moving,
        move_number: 20,
        pieces_in_hand: [0, 0],
        pieces_on_board: [3, 2],
        pending_removals: [1, 0],
        winner: -1,
        ..MillState::default()
    };
    let snap = rules.encode(state);
    let after_remove = rules.apply(
        &snap,
        Action {
            kind_tag: MillActionKind::Remove as i16,
            from_node: -1,
            to_node: 6,
            aux: -1,
            payload_bits: 0,
        },
    );

    let state = MillRules::decode(&after_remove);
    assert_eq!(state.phase, MillPhase::GameOver);
    assert_eq!(state.winner, 0);
    assert_eq!(state.side_to_move, -1);
    let outcome = rules.outcome(&after_remove);
    assert_eq!(outcome.kind, OutcomeKind::Win(0));
    assert_eq!(outcome.reason, "loseFewerThanThree");
}

/// Mirror of master remove_piece L1834-1838: the fewer-than-three loss
/// fires as soon as `pieceOnBoardCount + pieceInHandCount` drops below
/// `pieces_at_least_count`, even during the placing phase while the
/// victim still holds pieces in hand.  Regression test for the removed
/// `pieces_in_hand == [0, 0]` gate which deferred the loss and let a
/// doomed position keep playing.
#[test]
fn placing_phase_removal_below_three_ends_game_despite_pieces_in_hand() {
    let rules = MillRules::default();
    let state = MillState {
        board: {
            let mut board = [0_i8; 24];
            board[0] = 1;
            board[1] = 1;
            board[2] = 1;
            board[6] = 2;
            board
        },
        side_to_move: 0,
        phase: MillPhase::Placing,
        move_number: 13,
        // Both sides still hold pieces; Black's board + hand total will
        // drop to 2 (< 3) after the capture below.
        pieces_in_hand: [4, 2],
        pieces_on_board: [3, 1],
        pending_removals: [1, 0],
        winner: -1,
        ..MillState::default()
    };
    let snap = rules.encode(state);
    let after_remove = rules.apply(
        &snap,
        Action {
            kind_tag: MillActionKind::Remove as i16,
            from_node: -1,
            to_node: 6,
            aux: -1,
            payload_bits: 0,
        },
    );

    let state = MillRules::decode(&after_remove);
    assert_eq!(state.phase, MillPhase::GameOver);
    assert_eq!(state.winner, 0);
    assert_eq!(state.side_to_move, -1);
    let outcome = rules.outcome(&after_remove);
    assert_eq!(outcome.kind, OutcomeKind::Win(0));
    assert_eq!(outcome.reason, "loseFewerThanThree");
}

#[test]
fn mill_game_workbench_do_and_undo_move() {
    let rules = MillRules::default();
    let game = MillGame::default();
    let snap = rules.initial_state(&[]);
    let mut wb = game.build_workbench(&snap);

    let mut actions = ActionList::<256>::new();
    MillGame::generate_legal(&wb, &mut actions);
    assert_eq!(actions.len(), 24);

    wb.do_move(actions[0]);
    assert_eq!(wb.side_to_move(), 1);
    assert_eq!(wb.state.pieces_in_hand[0], 8);
    assert_eq!(wb.state.pieces_on_board[0], 1);

    wb.undo_move();
    assert_eq!(wb.side_to_move(), 0);
    assert_eq!(wb.state.pieces_in_hand[0], 9);
    assert_eq!(wb.state.pieces_on_board[0], 0);
}

#[test]
fn no_mill_moving_phase_fixture_reaches_moving_phase() {
    let rules = MillRules::default();
    let snap = rules.no_mill_moving_phase_snapshot();
    let state = MillRules::decode(&snap);
    assert_eq!(state.phase, MillPhase::Moving);
    assert_eq!(state.pieces_in_hand, [0, 0]);
    assert_eq!(state.pieces_on_board, [9, 9]);
    assert_eq!(state.pending_removals, [0, 0]);
}

#[test]
fn position_key_changes_after_move_and_restores_after_undo() {
    let rules = MillRules::default();
    let game = MillGame::default();
    let snap = rules.initial_state(&[]);
    let mut wb = game.build_workbench(&snap);
    let initial_key = wb.key();

    let mut actions = ActionList::<256>::new();
    MillGame::generate_legal(&wb, &mut actions);
    wb.do_move(actions[0]);
    assert_ne!(wb.key(), initial_key);

    wb.undo_move();
    assert_eq!(wb.key(), initial_key);
}

#[test]
fn position_key_distinguishes_capture_slots_per_side() {
    // Note: master's Zobrist key (mirrored by the Rust port post
    // Phase 15+) intentionally COLLAPSES `remove_own_piece` -- the
    // misc bits only store `pending_removals[stm]` (clamped to 4),
    // matching master `update_key_misc` (src/position.cpp).  Two
    // states differing only in remove_own_piece therefore hash to
    // the same key, which is master's documented behaviour.
    let mut normal = MillState {
        side_to_move: 0,
        phase: MillPhase::Moving,
        action: MillActionState::Remove,
        pending_removals: [1, 0],
        ..MillState::default()
    };
    normal.board[0] = 1;
    normal.board[6] = 2;
    normal.pieces_on_board = [1, 1];

    // What still must differ: per-side capture target bitmaps go
    // through dedicated Zobrist::custodianTarget[color][s] entries.
    let mut white_capture = normal.clone();
    white_capture.custodian_targets[0] = node_bit(6);
    white_capture.custodian_count[0] = 1;
    let mut black_capture = normal.clone();
    black_capture.custodian_targets[1] = node_bit(6);
    black_capture.custodian_count[1] = 1;
    assert_ne!(position_key(&white_capture), position_key(&black_capture));
}

#[test]
fn may_remove_from_mills_always_relaxes_target_filter() {
    let options = MillVariantOptions {
        may_remove_from_mills_always: true,
        ..MillVariantOptions::default()
    };
    let rules = MillRules::new(options);

    // Build a state where Black already has a mill (a1-d1-g1) and
    // White has just formed a mill on top.  Without the option White
    // cannot remove a1/d1/g1 (all in mill, but no non-mill targets);
    // with the option White may target any of them freely.
    let mut state = MillState {
        board: [0; 24],
        side_to_move: 0,
        phase: MillPhase::Placing,
        move_number: 6,
        pieces_in_hand: [6, 6],
        pieces_on_board: [3, 3],
        pending_removals: [1, 0],
        winner: -1,
        ..MillState::default()
    };
    state.board[0] = 1; // W a7
    state.board[1] = 1; // W d7
    state.board[2] = 1; // W g7 — completes outer top mill
    state.board[6] = 2; // B a1
    state.board[5] = 2; // B d1
    state.board[4] = 2; // B g1 — black mill a1-d1-g1
    let snap = rules.encode(state);

    let mut actions = ActionList::<256>::new();
    rules.legal_actions(&snap, &mut actions);
    // Expect 3 remove targets even though every black piece is in a
    // mill, because the option is on.
    assert_eq!(actions.len(), 3);
    assert!(
        actions
            .iter()
            .all(|a| a.kind_tag == MillActionKind::Remove as i16)
    );
}

#[test]
fn may_remove_multiple_pending_removals_match_simultaneous_mills() {
    let options = MillVariantOptions {
        may_remove_multiple: true,
        ..MillVariantOptions::default()
    };
    let rules = MillRules::new(options);

    // Place W to form two mills at once: outer top a7-d7-g7 *and*
    // spoke top d7-d6-d5 share the d7 hub.  Place d7 last to trigger
    // simultaneous mill formation.
    let mut state = MillState {
        board: [0; 24],
        side_to_move: 0,
        phase: MillPhase::Placing,
        move_number: 8,
        pieces_in_hand: [5, 5],
        pieces_on_board: [4, 4],
        pending_removals: [0, 0],
        winner: -1,
        ..MillState::default()
    };
    state.board[0] = 1; // a7
    state.board[2] = 1; // g7
    state.board[9] = 1; // d6
    state.board[17] = 1; // d5
    state.board[6] = 2;
    state.board[5] = 2;
    state.board[4] = 2;
    state.board[15] = 2;
    let snap = rules.encode(state);
    let after = rules.apply(
        &snap,
        Action {
            kind_tag: MillActionKind::Place as i16,
            from_node: -1,
            to_node: 1, // d7 hub
            aux: -1,
            payload_bits: 0,
        },
    );
    // pending_removals[0] should be 2 because two mills formed at
    // once with may_remove_multiple = true.
    assert_eq!(after.opaque_payload[28], 2);
}

#[test]
fn n_move_rule_draws_after_threshold_without_capture() {
    // Use minimum valid n_move_rule (10) and pre-load ply_since_capture
    // to one less than the threshold so a single non-capture move fires.
    let options = MillVariantOptions {
        n_move_rule: 10,
        ..MillVariantOptions::default()
    };
    let rules = MillRules::new(options);
    let mut snap = rules.no_mill_moving_phase_snapshot();
    let mut state = MillRules::decode(&snap);
    state.ply_since_capture = 9; // one below threshold
    snap = rules.encode(state);

    let after = rules.apply(
        &snap,
        Action {
            kind_tag: MillActionKind::Move as i16,
            from_node: 18, // e5
            to_node: 19,   // e4, known non-mill move in the fixture
            aux: -1,
            payload_bits: 0,
        },
    );
    let state = MillRules::decode(&after);
    assert_eq!(state.phase, MillPhase::GameOver);
    assert_eq!(state.winner, 2);
    assert_eq!(rules.outcome(&after).kind, OutcomeKind::Draw);
}

#[test]
fn endgame_n_move_rule_uses_lower_threshold() {
    // Use minimum valid endgame_n_move_rule (5) and pre-load
    // ply_since_capture to one less than the endgame threshold.
    let options = MillVariantOptions {
        n_move_rule: 100,
        endgame_n_move_rule: 5,
        ..MillVariantOptions::default()
    };
    let rules = MillRules::new(options);
    let state = MillState {
        board: {
            let mut board = [0_i8; 24];
            board[1] = 1;
            board[17] = 1;
            board[3] = 1;
            board[6] = 2;
            board[5] = 2;
            board[10] = 2;
            board
        },
        side_to_move: 0,
        phase: MillPhase::Moving,
        move_number: 30,
        pieces_in_hand: [0, 0],
        // Exactly fly_piece_count (3) pieces per side → is_endgame = true
        pieces_on_board: [3, 3],
        pending_removals: [0, 0],
        winner: -1,
        // Pre-load so one more Move triggers the endgame threshold
        ply_since_capture: 4,
        ..MillState::default()
    };
    let after = rules.apply(
        &rules.encode(state),
        Action {
            kind_tag: MillActionKind::Move as i16,
            from_node: 3,
            to_node: 4,
            aux: -1,
            payload_bits: 0,
        },
    );
    assert_eq!(rules.outcome(&after).kind, OutcomeKind::Draw);
}

#[test]
fn endgame_n_move_rule_ignores_fly_piece_count_four() {
    let options = MillVariantOptions {
        fly_piece_count: 4,
        n_move_rule: 100,
        endgame_n_move_rule: 5,
        ..MillVariantOptions::default()
    };
    let rules = MillRules::new(options);
    let state = MillState {
        board: {
            let mut board = [0_i8; 24];
            for node in [0_usize, 3, 6, 9] {
                board[node] = 1;
            }
            for node in [2_usize, 5, 8, 11] {
                board[node] = 2;
            }
            board
        },
        side_to_move: 0,
        phase: MillPhase::Moving,
        move_number: 30,
        pieces_in_hand: [0, 0],
        pieces_on_board: [4, 4],
        pending_removals: [0, 0],
        winner: -1,
        ply_since_capture: 4,
        ..MillState::default()
    };

    let after = rules.apply(
        &rules.encode(state),
        Action {
            kind_tag: MillActionKind::Move as i16,
            from_node: 3,
            to_node: 4,
            aux: -1,
            payload_bits: 0,
        },
    );

    assert_eq!(rules.outcome(&after).kind, OutcomeKind::Ongoing);
    assert_eq!(MillRules::decode(&after).ply_since_capture, 5);
}

#[test]
fn may_move_in_placing_phase_adds_move_actions() {
    let options = MillVariantOptions {
        may_move_in_placing_phase: true,
        ..MillVariantOptions::default()
    };
    let rules = MillRules::new(options);
    let state = MillState {
        board: {
            let mut board = [0_i8; 24];
            board[0] = 1;
            board
        },
        side_to_move: 0,
        phase: MillPhase::Placing,
        move_number: 1,
        pieces_in_hand: [8, 9],
        pieces_on_board: [1, 0],
        pending_removals: [0, 0],
        winner: -1,
        ..MillState::default()
    };
    let mut actions = ActionList::<256>::new();
    rules.legal_actions(&rules.encode(state), &mut actions);
    assert_eq!(
        actions
            .iter()
            .filter(|a| a.kind_tag == MillActionKind::Move as i16)
            .count(),
        2
    );
}

#[test]
fn placing_phase_leap_requires_empty_hand() {
    let options = MillVariantOptions {
        may_move_in_placing_phase: true,
        leap_capture: CaptureRuleConfig {
            enabled: true,
            in_placing_phase: true,
            ..CaptureRuleConfig::default()
        },
        ..MillVariantOptions::default()
    };
    let rules = MillRules::new(options);
    let state = MillState {
        board: {
            let mut board = [0_i8; 24];
            board[0] = 1;
            board[1] = 2;
            board
        },
        side_to_move: 0,
        phase: MillPhase::Placing,
        move_number: 2,
        pieces_in_hand: [7, 8],
        pieces_on_board: [1, 1],
        pending_removals: [0, 0],
        winner: -1,
        ..MillState::default()
    };

    let mut actions = ActionList::<256>::new();
    rules.legal_actions(&rules.encode(state), &mut actions);

    assert!(
        actions
            .iter()
            .any(|a| a.kind_tag == MillActionKind::Place as i16),
        "placing actions must remain available while pieces are in hand"
    );
    assert!(
        !actions.iter().any(|a| {
            a.kind_tag == MillActionKind::Move as i16 && a.from_node == 0 && a.to_node == 2
        }),
        "leap move over node 1 must wait until the hand is empty"
    );
}

#[test]
fn moving_phase_fly_requires_empty_hand() {
    let options = MillVariantOptions {
        may_fly: true,
        fly_piece_count: 3,
        ..MillVariantOptions::default()
    };
    let rules = MillRules::new(options);
    let state = MillState {
        board: {
            let mut board = [0_i8; 24];
            board[0] = 1;
            board[1] = 1;
            board[2] = 1;
            board[8] = 2;
            board[9] = 2;
            board[10] = 2;
            board
        },
        side_to_move: 0,
        phase: MillPhase::Moving,
        move_number: 18,
        pieces_in_hand: [1, 0],
        pieces_on_board: [3, 3],
        pending_removals: [0, 0],
        winner: -1,
        ..MillState::default()
    };

    let mut actions = ActionList::<256>::new();
    rules.legal_actions(&rules.encode(state), &mut actions);

    assert!(
        actions
            .iter()
            .any(|a| a.kind_tag == MillActionKind::Move as i16),
        "adjacent moves still exist in this setup"
    );
    assert!(
        !actions.iter().any(|a| {
            a.kind_tag == MillActionKind::Move as i16 && a.from_node == 0 && a.to_node == 23
        }),
        "non-adjacent fly moves must not be generated with a piece in hand"
    );
}

/// `restrict_repeated_mills_formation` must track the last formed mill
/// **per side**, mirroring `lastMillFromSquare[c]` /
/// `lastMillToSquare[c]` in legacy `position.cpp`.  Without per-side
/// tracking, a mill formed by White would silently forbid Black from
/// re-forming a mill it just broke (and vice versa), even though only
/// the same player should be barred.
#[test]
fn restrict_repeated_mills_is_per_side() {
    let options = MillVariantOptions {
        restrict_repeated_mills_formation: true,
        ..MillVariantOptions::default()
    };
    let rules = MillRules::new(options);
    // White last formed a mill via 9 -> 8.  In a state where it is now
    // Black's turn, that record must NOT block Black from any move.
    let state = MillState {
        board: {
            let mut board = [0_i8; 24];
            board[0] = 2; // black piece at node 0
            board
        },
        side_to_move: 1,
        phase: MillPhase::Moving,
        pieces_in_hand: [0, 0],
        pieces_on_board: [0, 1],
        last_mill_from: [9, -1],
        last_mill_to: [8, -1],
        ..MillState::default()
    };
    let mut actions = ActionList::<256>::new();
    rules.legal_actions(&rules.encode(state), &mut actions);
    // Black should be allowed to move freely; the white record above
    // must be ignored when computing Black's legal actions.
    assert!(!actions.is_empty(), "Black must still have legal moves");
}

#[test]
fn restrict_repeated_mills_filters_reverse_reform_move() {
    let options = MillVariantOptions {
        restrict_repeated_mills_formation: true,
        ..MillVariantOptions::default()
    };
    let rules = MillRules::new(options);
    let state = MillState {
        board: {
            let mut board = [0_i8; 24];
            board[8] = 1;
            board[1] = 1;
            board[17] = 1;
            board[14] = 1;
            board[15] = 1;
            board[6] = 2;
            board[5] = 2;
            board[10] = 2;
            board
        },
        side_to_move: 0,
        phase: MillPhase::Moving,
        move_number: 20,
        pieces_in_hand: [0, 0],
        pieces_on_board: [5, 3],
        pending_removals: [0, 0],
        winner: -1,
        last_mill_from: [9, -1],
        last_mill_to: [8, -1],
        ..MillState::default()
    };
    let mut actions = ActionList::<256>::new();
    rules.legal_actions(&rules.encode(state), &mut actions);
    assert!(!actions.iter().any(|a| a.from_node == 8 && a.to_node == 9));
}

#[test]
fn one_time_use_mill_allows_used_reverse_reform_move() {
    let used_line = node_bit(1) | node_bit(9) | node_bit(17);
    let options = MillVariantOptions {
        restrict_repeated_mills_formation: true,
        one_time_use_mill: true,
        ..MillVariantOptions::default()
    };
    let rules = MillRules::new(options);
    let state = MillState {
        board: {
            let mut board = [0_i8; 24];
            board[8] = 1;
            board[1] = 1;
            board[17] = 1;
            board[14] = 1;
            board[15] = 1;
            board[6] = 2;
            board[5] = 2;
            board[10] = 2;
            board
        },
        side_to_move: 0,
        phase: MillPhase::Moving,
        move_number: 20,
        pieces_in_hand: [0, 0],
        pieces_on_board: [5, 3],
        pending_removals: [0, 0],
        winner: -1,
        last_mill_from: [9, -1],
        last_mill_to: [8, -1],
        formed_mills_bb: [used_line, 0],
        ..MillState::default()
    };
    let mut actions = ActionList::<256>::new();
    rules.legal_actions(&rules.encode(state), &mut actions);
    assert!(
        actions.iter().any(|a| a.from_node == 8 && a.to_node == 9),
        "oneTimeUseMill-used lines are ignored by repeated-mill restriction"
    );
}

#[test]
fn one_time_use_mill_suppresses_second_capture() {
    let options = MillVariantOptions {
        one_time_use_mill: true,
        ..MillVariantOptions::default()
    };
    let rules = MillRules::new(options);
    // Pre-populate formed_mills_bb[white] with the outer-top line
    // [0, 1, 2] (mirrors a previous mill White already consumed).
    // usable_mill_bits now consults formed_mills_bb per side rather
    // than the global used_mill_lines, so the test setup populates
    // the right state.
    let formed_top_line = node_bit(0) | node_bit(1) | node_bit(2);
    let state = MillState {
        board: {
            let mut board = [0_i8; 24];
            board[1] = 1;
            board[2] = 1;
            board[6] = 2;
            board[5] = 2;
            board
        },
        side_to_move: 0,
        phase: MillPhase::Placing,
        move_number: 4,
        pieces_in_hand: [7, 7],
        pieces_on_board: [2, 2],
        pending_removals: [0, 0],
        winner: -1,
        used_mill_lines: 1,
        formed_mills_bb: [formed_top_line, 0],
        ..MillState::default()
    };
    let after = rules.apply(
        &rules.encode(state),
        Action {
            kind_tag: MillActionKind::Place as i16,
            from_node: -1,
            to_node: 0,
            aux: -1,
            payload_bits: 0,
        },
    );
    let state = MillRules::decode(&after);
    assert_eq!(state.pending_removals[0], 0);
    assert_eq!(state.side_to_move, 1);
}

#[test]
fn stop_placing_when_two_empty_squares_enters_moving_phase() {
    let options = MillVariantOptions {
        piece_count: 12,
        stop_placing_when_two_empty_squares: true,
        ..MillVariantOptions::default()
    };
    let rules = MillRules::new(options);
    let mut board = [2_i8; 24];
    board[21] = 0;
    board[22] = 0;
    board[23] = 0;
    board[20] = 2;
    board[13] = 2;
    board[5] = 2;
    let state = MillState {
        board,
        side_to_move: 0,
        phase: MillPhase::Placing,
        move_number: 21,
        pieces_in_hand: [3, 0],
        pieces_on_board: [0, 21],
        pending_removals: [0, 0],
        winner: -1,
        ..MillState::default()
    };
    let after = rules.apply(
        &rules.encode(state),
        Action {
            kind_tag: MillActionKind::Place as i16,
            from_node: -1,
            to_node: 21,
            aux: -1,
            payload_bits: 0,
        },
    );
    let state = MillRules::decode(&after);
    assert_eq!(state.pieces_in_hand, [0, 0]);
    assert_eq!(state.phase, MillPhase::Moving);
}

#[test]
fn stop_placing_two_empty_does_not_preempt_mill_removal() {
    let options = MillVariantOptions {
        piece_count: 12,
        stop_placing_when_two_empty_squares: true,
        mill_formation_action_in_placing_phase:
            MillFormationActionInPlacingPhase::RemoveOpponentsPieceFromBoard,
        ..MillVariantOptions::default()
    };
    let rules = MillRules::new(options);
    let mut board = [2_i8; 24];
    // White forms a mill on [20, 21, 22] by placing at 22 while the
    // board has exactly three empty squares before the move.
    board[20] = 1;
    board[21] = 1;
    board[22] = 0;
    board[23] = 0;
    board[0] = 0;
    let state = MillState {
        board,
        side_to_move: 0,
        phase: MillPhase::Placing,
        move_number: 21,
        pieces_in_hand: [1, 0],
        pieces_on_board: [2, 19],
        pending_removals: [0, 0],
        winner: -1,
        ..MillState::default()
    };

    let after = rules.apply(
        &rules.encode(state),
        Action {
            kind_tag: MillActionKind::Place as i16,
            from_node: -1,
            to_node: 22,
            aux: -1,
            payload_bits: 0,
        },
    );
    let state = MillRules::decode(&after);

    assert_eq!(
        state.pending_removals[0], 1,
        "mill removal must be preserved when the two-empty rule is also true"
    );
    assert_eq!(
        state.side_to_move, 0,
        "mill removal keeps the forming side to move"
    );
    assert_eq!(
        state.pieces_in_hand,
        [0, 0],
        "the played piece itself leaves White with no hand pieces"
    );
    assert_eq!(state.phase, MillPhase::Placing);
}

#[test]
fn stop_placing_when_two_empty_squares_is_twelve_men_only() {
    let options = MillVariantOptions {
        piece_count: 9,
        stop_placing_when_two_empty_squares: true,
        ..MillVariantOptions::default()
    };
    let rules = MillRules::new(options);
    let mut board = [2_i8; 24];
    board[21] = 0;
    board[22] = 0;
    board[23] = 0;
    board[20] = 2;
    board[13] = 2;
    board[5] = 2;
    // Keep both hands non-empty so the per-side phase sync (mirror of
    // C++ set_side_to_move) stays in Placing for the next mover; the
    // discriminating observable for the 12-piece-only shortcut is that
    // the hands are NOT force-zeroed.
    let state = MillState {
        board,
        side_to_move: 0,
        phase: MillPhase::Placing,
        move_number: 21,
        pieces_in_hand: [3, 2],
        pieces_on_board: [0, 21],
        pending_removals: [0, 0],
        winner: -1,
        ..MillState::default()
    };

    let after = rules.apply(
        &rules.encode(state),
        Action {
            kind_tag: MillActionKind::Place as i16,
            from_node: -1,
            to_node: 21,
            aux: -1,
            payload_bits: 0,
        },
    );
    let state = MillRules::decode(&after);
    assert_eq!(
        state.pieces_in_hand,
        [2, 2],
        "9-piece games must not zero the hands via the two-empty shortcut"
    );
    assert_eq!(
        state.phase,
        MillPhase::Placing,
        "C++ only applies this shortcut for 12-piece games"
    );
}

#[test]
fn agree_to_draw_on_full_board_returns_draw_outcome() {
    let options = MillVariantOptions {
        piece_count: 12,
        board_full_action: MillBoardFullAction::AgreeToDraw,
        ..MillVariantOptions::default()
    };
    let rules = MillRules::new(options);
    let mut board = [2_i8; 24];
    board[21] = 0;
    board[20] = 2;
    board[22] = 2;
    board[13] = 2;
    board[5] = 2;
    let state = MillState {
        board,
        side_to_move: 0,
        phase: MillPhase::Placing,
        move_number: 23,
        pieces_in_hand: [1, 0],
        pieces_on_board: [0, 23],
        pending_removals: [0, 0],
        winner: -1,
        ..MillState::default()
    };
    let after = rules.apply(
        &rules.encode(state),
        Action {
            kind_tag: MillActionKind::Place as i16,
            from_node: -1,
            to_node: 21,
            aux: -1,
            payload_bits: 0,
        },
    );
    assert_eq!(rules.outcome(&after).kind, OutcomeKind::Draw);
}

fn board_full_one_empty_state() -> MillState {
    let mut board = [2_i8; 24];
    for node in [1_usize, 3, 5, 7, 9, 11, 14, 15, 17, 19, 20] {
        board[node] = 1;
    }
    board[21] = 0;
    MillState {
        board,
        side_to_move: 0,
        phase: MillPhase::Placing,
        move_number: 23,
        pieces_in_hand: [1, 0],
        pieces_on_board: [11, 12],
        pending_removals: [0, 0],
        winner: -1,
        ..MillState::default()
    }
}

fn fill_last_square(rules: &MillRules, state: MillState) -> GameStateSnapshot {
    rules.apply(
        &rules.encode(state),
        Action {
            kind_tag: MillActionKind::Place as i16,
            from_node: -1,
            to_node: 21,
            aux: -1,
            payload_bits: 0,
        },
    )
}

/// Mirror master src/position.cpp:3475 is_board_full_removal_at_placing_phase_end:
/// after Rust transitions the full board to Moving, board-full removals
/// remain regular mill-aware removals rather than stalemate removals.
#[test]
fn board_full_removal_does_not_use_stalemate_adjacency_filter() {
    let rules = MillRules::new(MillVariantOptions {
        piece_count: 12,
        board_full_action: MillBoardFullAction::FirstAndSecondPlayerRemovePiece,
        ..MillVariantOptions::default()
    });
    let after_fill = fill_last_square(&rules, board_full_one_empty_state());
    let state = MillRules::decode(&after_fill);
    assert_eq!(state.phase, MillPhase::Moving);
    assert_eq!(state.side_to_move, 0);

    let mut actions = ActionList::<256>::new();
    rules.legal_actions(&after_fill, &mut actions);
    assert!(
        !actions.is_empty(),
        "white must have at least one legal target"
    );

    let non_mill_opponent_targets = state
        .board
        .iter()
        .enumerate()
        .filter(|(node, piece)| **piece == 2 && !is_piece_in_mill(&state, &rules.options, *node))
        .count();
    assert_eq!(
        actions
            .iter()
            .filter(|a| a.kind_tag == MillActionKind::Remove as i16)
            .count(),
        non_mill_opponent_targets,
        "board-full removals must keep regular mill protection but not adjacency filtering"
    );
}

#[test]
fn board_full_first_and_second_remove_in_order() {
    let rules = MillRules::new(MillVariantOptions {
        piece_count: 12,
        board_full_action: MillBoardFullAction::FirstAndSecondPlayerRemovePiece,
        ..MillVariantOptions::default()
    });
    let after_fill = fill_last_square(&rules, board_full_one_empty_state());
    let state = MillRules::decode(&after_fill);
    assert_eq!(state.phase, MillPhase::Moving);
    assert_eq!(state.side_to_move, 0, "first player removes first");
    assert_eq!(state.pending_removals, [1, 1]);

    let after_white_remove = rules.apply(
        &after_fill,
        Action {
            kind_tag: MillActionKind::Remove as i16,
            from_node: -1,
            to_node: 0,
            aux: -1,
            payload_bits: 0,
        },
    );
    let state = MillRules::decode(&after_white_remove);
    assert_eq!(state.pending_removals, [0, 1]);
    assert_eq!(state.side_to_move, 1, "second player removes next");
}

#[test]
fn board_full_second_and_first_remove_in_order() {
    let rules = MillRules::new(MillVariantOptions {
        piece_count: 12,
        board_full_action: MillBoardFullAction::SecondAndFirstPlayerRemovePiece,
        ..MillVariantOptions::default()
    });
    let after_fill = fill_last_square(&rules, board_full_one_empty_state());
    let state = MillRules::decode(&after_fill);
    assert_eq!(state.phase, MillPhase::Moving);
    assert_eq!(state.side_to_move, 1, "second player removes first");
    assert_eq!(state.pending_removals, [1, 1]);

    let after_black_remove = rules.apply(
        &after_fill,
        Action {
            kind_tag: MillActionKind::Remove as i16,
            from_node: -1,
            to_node: 21,
            aux: -1,
            payload_bits: 0,
        },
    );
    let state = MillRules::decode(&after_black_remove);
    assert_eq!(state.pending_removals, [1, 0]);
    assert_eq!(state.side_to_move, 0, "first player removes next");
}

#[test]
fn board_full_side_to_move_remove_respects_defender_setting() {
    let rules = MillRules::new(MillVariantOptions {
        piece_count: 12,
        is_defender_move_first: true,
        board_full_action: MillBoardFullAction::SideToMoveRemovePiece,
        ..MillVariantOptions::default()
    });
    let after_fill = fill_last_square(&rules, board_full_one_empty_state());
    let state = MillRules::decode(&after_fill);
    assert_eq!(state.phase, MillPhase::Moving);
    assert_eq!(state.side_to_move, 1);
    assert_eq!(state.pending_removals, [0, 1]);
}

/// Helper: build a small moving-phase state where W just moved
/// d6→d7 (`9→1`) and the new state has a known repetition signature.
/// We pre-populate the rolling history so the next call to `apply`
/// will be the 3rd instance of that signature, triggering the rule.
fn moving_phase_swap_state(side_to_move: i8) -> MillState {
    let mut state = MillState {
        side_to_move,
        phase: MillPhase::Moving,
        move_number: 30,
        pieces_in_hand: [0, 0],
        pieces_on_board: [3, 3],
        pending_removals: [0, 0],
        winner: -1,
        ..MillState::default()
    };
    // Three white pieces (a7, d6, c4) and three black pieces
    // (g7, g4, c5) — pure non-mill geometry so any move is reversible.
    state.board[0] = 1; // a7
    state.board[9] = 1; // d6
    state.board[23] = 1; // c4
    state.board[2] = 2; // g7
    state.board[3] = 2; // g4
    state.board[16] = 2; // c5
    state
}

#[test]
fn threefold_triggers_after_three_repetitions() {
    let rules = MillRules::default();
    let mut state = moving_phase_swap_state(0);
    // Pre-populate history with the *post-move* signature twice.
    let mut after_move = state.clone();
    after_move.board[9] = 0;
    after_move.board[1] = 1;
    after_move.side_to_move = 1;
    let target_key = repetition_signature(&after_move);
    state.key_history = vec![target_key, target_key];
    state.key_history_len = state.key_history.len();

    let after = rules.apply(
        &rules.encode(state),
        Action {
            kind_tag: MillActionKind::Move as i16,
            from_node: 9,
            to_node: 1,
            aux: -1,
            payload_bits: 0,
        },
    );
    let final_state = MillRules::decode(&after);
    assert_eq!(final_state.phase, MillPhase::GameOver);
    assert_eq!(final_state.winner, 2, "draw winner sentinel");
    assert_eq!(rules.outcome(&after).kind, OutcomeKind::Draw);
    assert_eq!(rules.outcome(&after).reason, "drawThreefoldRepetition");
}

#[test]
fn threefold_does_not_trigger_after_two_repetitions() {
    let rules = MillRules::default();
    let mut state = moving_phase_swap_state(0);
    let mut after_move = state.clone();
    after_move.board[9] = 0;
    after_move.board[1] = 1;
    after_move.side_to_move = 1;
    let target_key = repetition_signature(&after_move);
    // Only one prior occurrence: the new push will make count == 2.
    state.key_history = vec![target_key];
    state.key_history_len = state.key_history.len();

    let after = rules.apply(
        &rules.encode(state),
        Action {
            kind_tag: MillActionKind::Move as i16,
            from_node: 9,
            to_node: 1,
            aux: -1,
            payload_bits: 0,
        },
    );
    let final_state = MillRules::decode(&after);
    assert_eq!(final_state.phase, MillPhase::Moving);
    assert_eq!(final_state.key_history_len, 2);
    assert_eq!(rules.outcome(&after).kind, OutcomeKind::Ongoing);
}

fn history_marker_snapshot(key: u64) -> GameStateSnapshot {
    let mut snap = GameStateSnapshot {
        phase_tag: MillPhase::Moving as i16,
        zobrist_key: key,
        ..GameStateSnapshot::default()
    };
    snap.opaque_payload[236] = 1;
    snap
}

#[test]
fn apply_with_history_detects_threefold_beyond_payload_window() {
    let rules = MillRules::default();
    let mut state = moving_phase_swap_state(0);
    let mut after_move = state.clone();
    after_move.board[9] = 0;
    after_move.board[1] = 1;
    after_move.side_to_move = 1;
    let target_key = repetition_signature(&after_move);

    state.key_history = (0..MILL_REPETITION_SNAPSHOT_WINDOW)
        .map(|i| 0xCAFE_0000_u64 + i as u64)
        .collect();
    state.key_history_len = state.key_history.len();
    let snap = rules.encode(state);

    let mut history = vec![GameStateSnapshot::default()];
    for i in 0..30_u64 {
        let key = if i == 3 || i == 9 {
            target_key
        } else {
            0xBEEF_0000_u64 + i
        };
        history.push(history_marker_snapshot(key));
    }

    let after = rules.apply_with_history(
        &snap,
        Action {
            kind_tag: MillActionKind::Move as i16,
            from_node: 9,
            to_node: 1,
            aux: -1,
            payload_bits: 0,
        },
        &history,
    );

    assert_eq!(rules.outcome(&after).kind, OutcomeKind::Draw);
    assert_eq!(rules.outcome(&after).reason, "drawThreefoldRepetition");
}

#[test]
fn mill_game_root_repetition_history_feeds_workbench() {
    let rules = MillRules::default();
    let state = moving_phase_swap_state(0);
    let snap = rules.encode(state);
    let key = snap.zobrist_key;
    let game = MillGame::new_with_repetition_history(
        MillVariantOptions::default(),
        vec![key, 0x1234_5678, key],
    );
    let wb = game.build_workbench(&snap);

    assert_eq!(wb.current_repetition_count(), 2);
}

#[test]
fn capture_clears_threefold_history() {
    let rules = MillRules::default();
    // Build a state where W has just formed a mill and must remove a
    // black piece; pre-load history with two prior occurrences of
    // the post-capture signature.  The Remove must clear history so
    // the post-state's signature count drops to 1, NOT 3.
    let mut state = MillState {
        side_to_move: 0,
        phase: MillPhase::Moving,
        move_number: 30,
        pieces_in_hand: [0, 0],
        pieces_on_board: [3, 4],
        pending_removals: [1, 0],
        winner: -1,
        ..MillState::default()
    };
    state.board[0] = 1;
    state.board[1] = 1;
    state.board[2] = 1; // W mill outer top
    state.board[6] = 2; // a1
    state.board[5] = 2; // d1
    state.board[10] = 2; // f6 (non-mill, capturable)
    state.board[15] = 2; // b4 (extra, avoid lose-by-<3 after removal)

    let mut bogus_state = state.clone();
    bogus_state.pending_removals = [0, 0];
    bogus_state.board[10] = 0;
    bogus_state.pieces_on_board = [3, 3];
    bogus_state.side_to_move = 1;
    let target_key = repetition_signature(&bogus_state);
    state.key_history = vec![target_key, target_key];
    state.key_history_len = state.key_history.len();

    let after = rules.apply(
        &rules.encode(state),
        Action {
            kind_tag: MillActionKind::Remove as i16,
            from_node: -1,
            to_node: 10,
            aux: -1,
            payload_bits: 0,
        },
    );
    let final_state = MillRules::decode(&after);
    assert_eq!(final_state.phase, MillPhase::Moving);
    assert_eq!(
        final_state.key_history_len, 0,
        "Remove must wipe rolling history"
    );
    assert_eq!(rules.outcome(&after).kind, OutcomeKind::Ongoing);
}

#[test]
fn disabling_threefold_keeps_game_ongoing() {
    let options = MillVariantOptions {
        threefold_repetition_rule: false,
        ..MillVariantOptions::default()
    };
    let rules = MillRules::new(options);
    let mut state = moving_phase_swap_state(0);
    // Same setup that would trigger when the rule is on: 2 prior
    // occurrences in history, the move would make it 3.
    let mut after_move = state.clone();
    after_move.board[9] = 0;
    after_move.board[1] = 1;
    after_move.side_to_move = 1;
    let target_key = repetition_signature(&after_move);
    state.key_history = vec![target_key, target_key];
    state.key_history_len = state.key_history.len();

    let after = rules.apply(
        &rules.encode(state),
        Action {
            kind_tag: MillActionKind::Move as i16,
            from_node: 9,
            to_node: 1,
            aux: -1,
            payload_bits: 0,
        },
    );
    let final_state = MillRules::decode(&after);
    assert_eq!(final_state.phase, MillPhase::Moving);
    // History still has the 2 pre-loaded entries only (threefold is
    // disabled, so push is skipped entirely).
    assert_eq!(final_state.key_history_len, 2);
    assert_eq!(rules.outcome(&after).kind, OutcomeKind::Ongoing);
}

#[test]
fn long_runtime_history_serializes_recent_payload_window() {
    let rules = MillRules::default();
    let mut long_state = moving_phase_swap_state(0);
    long_state.key_history = (0..40).map(|i| 0x1234_0000_u64 + i).collect();
    long_state.key_history_len = long_state.key_history.len();

    let decoded = MillRules::decode(&rules.encode(long_state));
    assert_eq!(
        decoded.key_history_len, 24,
        "snapshot payload stores the most recent 24 history entries"
    );
    assert_eq!(
        decoded.key_history.first().copied(),
        Some(0x1234_0000_u64 + 16)
    );
    assert_eq!(
        decoded.key_history.last().copied(),
        Some(0x1234_0000_u64 + 39)
    );
}

#[test]
fn custodian_capture_places_single_remove_obligation() {
    let options = MillVariantOptions {
        custodian_capture: CaptureRuleConfig {
            enabled: true,
            ..CaptureRuleConfig::default()
        },
        ..MillVariantOptions::default()
    };
    let rules = MillRules::new(options);
    let state = MillState {
        board: {
            let mut board = [0_i8; 24];
            board[1] = 2; // B d7 trapped between W a7 and W g7
            board[2] = 1; // W g7
            board
        },
        side_to_move: 0,
        phase: MillPhase::Placing,
        move_number: 2,
        pieces_in_hand: [8, 8],
        pieces_on_board: [1, 1],
        ..MillState::default()
    };
    let after = rules.apply(
        &rules.encode(state),
        Action {
            kind_tag: MillActionKind::Place as i16,
            from_node: -1,
            to_node: 0, // W a7
            aux: -1,
            payload_bits: 0,
        },
    );
    let state = MillRules::decode(&after);
    assert_eq!(state.pending_removals[0], 1);
    assert_eq!(state.custodian_targets[0], node_bit(1));
    assert!(!state.mill_available_at_removal);
    let mut actions = ActionList::<256>::new();
    rules.legal_actions(&after, &mut actions);
    assert_eq!(
        actions.iter().map(|a| a.to_node).collect::<Vec<_>>(),
        vec![1]
    );
}

#[test]
fn placing_end_custodian_capture_resolves_before_phase_transition() {
    let options = MillVariantOptions {
        mill_formation_action_in_placing_phase:
            MillFormationActionInPlacingPhase::RemovalBasedOnMillCounts,
        custodian_capture: CaptureRuleConfig {
            enabled: true,
            ..CaptureRuleConfig::default()
        },
        ..MillVariantOptions::default()
    };
    let rules = MillRules::new(options);
    let state = MillState {
        board: {
            let mut board = [0_i8; 24];
            board[1] = 2; // B d7 will be trapped between W a7 and W g7.
            board[2] = 1; // W g7
            board[3] = 1;
            board[4] = 2;
            board[5] = 2;
            board[6] = 1;
            board[8] = 1;
            board[9] = 1;
            board[10] = 2;
            board[11] = 1;
            board[12] = 1;
            board[13] = 2;
            board[14] = 2;
            board[15] = 2;
            board[16] = 2;
            board[17] = 2;
            board[19] = 2;
            board
        },
        side_to_move: 0,
        phase: MillPhase::Placing,
        move_number: 17,
        pieces_in_hand: [1, 0],
        pieces_on_board: [8, 9],
        ..MillState::default()
    };

    let after_place = rules.apply(
        &rules.encode(state),
        Action {
            kind_tag: MillActionKind::Place as i16,
            from_node: -1,
            to_node: 0, // Final W a7 placement triggers custodian capture.
            aux: -1,
            payload_bits: 0,
        },
    );
    let state = MillRules::decode(&after_place);

    assert_eq!(state.phase, MillPhase::Placing);
    assert_eq!(state.side_to_move, 0, "capturing side must remove first");
    assert_eq!(state.pieces_in_hand, [0, 0]);
    assert_eq!(state.pending_removals[0], 1);
    assert_eq!(state.custodian_targets[0], node_bit(1));
    assert!(!state.mill_available_at_removal);

    let mut actions = ActionList::<256>::new();
    rules.legal_actions(&after_place, &mut actions);
    assert_eq!(actions.len(), 1);
    let remove = actions.iter().next().copied().unwrap();
    assert_eq!(remove.kind_tag, MillActionKind::Remove as i16);
    assert_eq!(remove.to_node, 1);

    let after_remove = rules.apply(&after_place, remove);
    let state = MillRules::decode(&after_remove);
    assert_eq!(state.phase, MillPhase::Moving);
    assert_eq!(state.board[1], 0, "custodian target must be removed first");
    assert_eq!(
        state.pending_removals,
        [1, 1],
        "mill-count removals are scheduled only after capture removal"
    );
    assert_eq!(state.side_to_move, 0);
    assert_eq!(state.remove_own_piece, [true, true]);
}

#[test]
fn intervention_capture_uses_one_line_of_two_targets() {
    let options = MillVariantOptions {
        intervention_capture: CaptureRuleConfig {
            enabled: true,
            ..CaptureRuleConfig::default()
        },
        ..MillVariantOptions::default()
    };
    let rules = MillRules::new(options);
    let state = MillState {
        board: {
            let mut board = [0_i8; 24];
            board[0] = 2; // B a7
            board[2] = 2; // B g7
            board
        },
        side_to_move: 0,
        phase: MillPhase::Placing,
        move_number: 2,
        pieces_in_hand: [9, 7],
        pieces_on_board: [0, 2],
        ..MillState::default()
    };
    let after = rules.apply(
        &rules.encode(state),
        Action {
            kind_tag: MillActionKind::Place as i16,
            from_node: -1,
            to_node: 1, // W intervenes at d7
            aux: -1,
            payload_bits: 0,
        },
    );
    let state = MillRules::decode(&after);
    assert_eq!(state.pending_removals[0], 2);
    assert_eq!(state.intervention_targets[0], node_bit(0) | node_bit(2));
    let mut actions = ActionList::<256>::new();
    rules.legal_actions(&after, &mut actions);
    assert_eq!(actions.len(), 2);
    assert!(actions.iter().any(|a| a.to_node == 0));
    assert!(actions.iter().any(|a| a.to_node == 2));
}

#[test]
fn intervention_capture_does_not_fallback_after_filtering_selected_line() {
    let options = MillVariantOptions {
        intervention_capture: CaptureRuleConfig {
            enabled: true,
            ..CaptureRuleConfig::default()
        },
        ..MillVariantOptions::default()
    };
    let rules = MillRules::new(options);
    let state = MillState {
        board: {
            let mut board = [0_i8; 24];
            // Both targets in the preferred line [0,1,2] sit in mills,
            // so filtering that selected line empties it. The alternate
            // raw line [1,9,17] has removable targets, but master does
            // not fall back to it.
            for node in [0_usize, 2, 3, 4, 6, 7, 8, 9, 10, 17] {
                board[node] = 2;
            }
            board[5] = 1;
            board
        },
        side_to_move: 0,
        phase: MillPhase::Placing,
        move_number: 8,
        pieces_in_hand: [8, 0],
        pieces_on_board: [1, 10],
        preferred_remove_target: 0,
        ..MillState::default()
    };

    let after = rules.apply(
        &rules.encode(state),
        Action {
            kind_tag: MillActionKind::Place as i16,
            from_node: -1,
            to_node: 1,
            aux: -1,
            payload_bits: 0,
        },
    );
    let state = MillRules::decode(&after);

    assert!(is_piece_in_mill(&state, &rules.options, 0));
    assert!(is_piece_in_mill(&state, &rules.options, 2));
    assert!(!is_all_in_mills(&state, &rules.options, 2));
    assert_eq!(state.intervention_targets[0], 0);
    assert_eq!(state.intervention_count[0], 0);
    assert_eq!(
        state.pending_removals[0], 0,
        "filtered selected intervention line must cancel the capture"
    );
}

#[test]
fn leap_capture_takes_precedence_over_mill() {
    let options = MillVariantOptions {
        leap_capture: CaptureRuleConfig {
            enabled: true,
            ..CaptureRuleConfig::default()
        },
        ..MillVariantOptions::default()
    };
    let rules = MillRules::new(options);
    let state = MillState {
        board: {
            let mut board = [0_i8; 24];
            board[0] = 1; // W a7 jumps to g7
            board[1] = 2; // B d7 jumped
            board[3] = 1; // W g4
            board[4] = 1; // W g1, so landing at g7 also forms a mill
            board[6] = 2;
            board[5] = 2;
            board
        },
        side_to_move: 0,
        phase: MillPhase::Moving,
        move_number: 20,
        pieces_in_hand: [0, 0],
        pieces_on_board: [3, 3],
        ..MillState::default()
    };
    let after = rules.apply(
        &rules.encode(state),
        Action {
            kind_tag: MillActionKind::Move as i16,
            from_node: 0,
            to_node: 2,
            aux: -1,
            payload_bits: 0,
        },
    );
    let state = MillRules::decode(&after);
    assert_eq!(state.pending_removals[0], 1);
    assert_eq!(state.leap_targets[0], node_bit(1));
    assert!(!state.mill_available_at_removal);
}

#[test]
fn mill_plus_custodian_accumulates_only_when_may_remove_multiple() {
    let options = MillVariantOptions {
        may_remove_multiple: true,
        custodian_capture: CaptureRuleConfig {
            enabled: true,
            ..CaptureRuleConfig::default()
        },
        ..MillVariantOptions::default()
    };
    let rules = MillRules::new(options);
    let state = MillState {
        board: {
            let mut board = [0_i8; 24];
            board[7] = 1; // W a4
            board[6] = 1; // W a1 -> placing at a7 forms left mill
            board[1] = 2; // B d7 trapped by W a7 / W g7
            board[2] = 1; // W g7
            board[5] = 2;
            board
        },
        side_to_move: 0,
        phase: MillPhase::Placing,
        move_number: 5,
        pieces_in_hand: [6, 7],
        pieces_on_board: [3, 2],
        ..MillState::default()
    };
    let after = rules.apply(
        &rules.encode(state),
        Action {
            kind_tag: MillActionKind::Place as i16,
            from_node: -1,
            to_node: 0,
            aux: -1,
            payload_bits: 0,
        },
    );
    let state = MillRules::decode(&after);
    assert_eq!(state.pending_removals[0], 2);
    assert!(state.mill_available_at_removal);
    assert_eq!(state.custodian_targets[0], node_bit(1));
}

#[test]
fn mill_plus_custodian_does_not_accumulate_without_may_remove_multiple() {
    let options = MillVariantOptions {
        custodian_capture: CaptureRuleConfig {
            enabled: true,
            ..CaptureRuleConfig::default()
        },
        ..MillVariantOptions::default()
    };
    let rules = MillRules::new(options);
    let state = MillState {
        board: {
            let mut board = [0_i8; 24];
            board[7] = 1;
            board[6] = 1;
            board[1] = 2;
            board[2] = 1;
            board[5] = 2;
            board
        },
        side_to_move: 0,
        phase: MillPhase::Placing,
        move_number: 5,
        pieces_in_hand: [6, 7],
        pieces_on_board: [3, 2],
        ..MillState::default()
    };
    let after = rules.apply(
        &rules.encode(state),
        Action {
            kind_tag: MillActionKind::Place as i16,
            from_node: -1,
            to_node: 0,
            aux: -1,
            payload_bits: 0,
        },
    );
    let state = MillRules::decode(&after);
    assert_eq!(state.pending_removals[0], 1);
    assert!(state.mill_available_at_removal);
    assert_eq!(state.custodian_targets[0], node_bit(1));
}

#[test]
fn diagonal_lines_form_extra_mills_when_enabled() {
    let options = MillVariantOptions {
        has_diagonal_lines: true,
        ..MillVariantOptions::default()
    };
    let rules = MillRules::new(options);
    let mut state = MillState {
        side_to_move: 0,
        phase: MillPhase::Placing,
        move_number: 4,
        pieces_in_hand: [7, 7],
        pieces_on_board: [2, 2],
        ..MillState::default()
    };
    state.board[0] = 1; // a7
    state.board[8] = 1; // b6
    state.board[6] = 2;
    state.board[5] = 2;
    let after = rules.apply(
        &rules.encode(state),
        Action {
            kind_tag: MillActionKind::Place as i16,
            from_node: -1,
            to_node: 16, // c5 completes a7-b6-c5 diagonal
            aux: -1,
            payload_bits: 0,
        },
    );
    let state = MillRules::decode(&after);
    assert_eq!(state.pending_removals[0], 1);
    assert_eq!(state.side_to_move, 0, "turn stays while removing");
}

#[test]
fn diagonal_lines_do_not_form_when_disabled() {
    let rules = MillRules::default();
    let mut state = MillState {
        side_to_move: 0,
        phase: MillPhase::Placing,
        move_number: 4,
        pieces_in_hand: [7, 7],
        pieces_on_board: [2, 2],
        ..MillState::default()
    };
    state.board[0] = 1;
    state.board[8] = 1;
    state.board[6] = 2;
    state.board[5] = 2;
    let after = rules.apply(
        &rules.encode(state),
        Action {
            kind_tag: MillActionKind::Place as i16,
            from_node: -1,
            to_node: 16,
            aux: -1,
            payload_bits: 0,
        },
    );
    let state = MillRules::decode(&after);
    assert_eq!(state.pending_removals[0], 0);
    assert_eq!(state.side_to_move, 1);
}

#[test]
fn diagonal_custodian_sandwiches_opponent_on_diagonal_line() {
    let options = MillVariantOptions {
        has_diagonal_lines: true,
        piece_count: 12,
        custodian_capture: CaptureRuleConfig {
            enabled: true,
            on_diagonal_lines: true,
            ..CaptureRuleConfig::default()
        },
        ..MillVariantOptions::default()
    };
    let rules = MillRules::new(options);
    // Line [0, 8, 16]: own at 16, opponent at 8, place at 0 -> capture 8.
    let mut state = MillState {
        side_to_move: 0,
        phase: MillPhase::Placing,
        move_number: 5,
        pieces_in_hand: [7, 7],
        pieces_on_board: [2, 2],
        ..MillState::default()
    };
    state.board[16] = 1;
    state.board[8] = 2;
    let after = rules.apply(
        &rules.encode(state),
        Action {
            kind_tag: MillActionKind::Place as i16,
            from_node: -1,
            to_node: 0,
            aux: -1,
            payload_bits: 0,
        },
    );
    let st = MillRules::decode(&after);
    assert_eq!(st.custodian_targets[0], node_bit(8));
    assert_eq!(st.pending_removals[0], 1);
    assert!(!st.mill_available_at_removal);
}

#[test]
fn defender_moves_first_when_placing_phase_ends() {
    let options = MillVariantOptions {
        is_defender_move_first: true,
        ..MillVariantOptions::default()
    };
    let rules = MillRules::new(options);
    let mut snap = rules.initial_state(&[]);
    // Same no-mill 18-placement fixture used by C++ golden tests.
    for node in [
        1, 2, 3, 0, 7, 4, 10, 9, 8, 13, 12, 6, 18, 16, 23, 17, 20, 22,
    ] {
        snap = rules.apply(
            &snap,
            Action {
                kind_tag: MillActionKind::Place as i16,
                from_node: -1,
                to_node: node,
                aux: -1,
                payload_bits: 0,
            },
        );
    }
    let state = MillRules::decode(&snap);
    assert_eq!(state.phase, MillPhase::Moving);
    assert_eq!(
        state.side_to_move, 1,
        "defender (black) starts moving phase"
    );
}

/// After the opening Place on a corner, total material is even (each
/// side has 9 pieces between hand and board) but mobility is asymmetric
/// because White's lone piece on node 0 only contributes neighbours to
/// itself.  Match the legacy `evaluate.cpp` formula:
///   value = mobility_diff + 5*(in_hand_diff + on_board_diff)
/// then negate for Black-to-move.
#[test]
fn mill_evaluator_after_opening_place_matches_legacy_formula() {
    let rules = MillRules::default();
    let game = MillGame::default();
    let mut snap = rules.initial_state(&[]);
    snap = rules.apply(
        &snap,
        Action {
            kind_tag: MillActionKind::Place as i16,
            from_node: -1,
            to_node: 0,
            aux: -1,
            payload_bits: 0,
        },
    );
    let wb = game.build_workbench(&snap);
    let state = MillRules::decode(&snap);
    let opts = MillVariantOptions::default();
    let mobility = mobility_diff(&state, &opts);
    let in_hand_diff = i32::from(state.pieces_in_hand[0]) - i32::from(state.pieces_in_hand[1]);
    let on_board_diff = i32::from(state.pieces_on_board[0]) - i32::from(state.pieces_on_board[1]);
    let expected = -(mobility + 5 * (in_hand_diff + on_board_diff));
    assert_eq!(MillEvaluator::score(&wb), expected);
}

/// `focus_on_blocking_paths` should drop the material term entirely
/// in the placing phase and leave only the mobility delta.
#[test]
fn mill_evaluator_focus_on_blocking_paths_drops_material_term() {
    let opts = MillVariantOptions {
        focus_on_blocking_paths: true,
        consider_mobility: false,
        ..MillVariantOptions::default()
    };
    let rules = MillRules::new(opts.clone());
    let game = MillGame::new(opts.clone());
    let mut snap = rules.initial_state(&[]);
    snap = rules.apply(
        &snap,
        Action {
            kind_tag: MillActionKind::Place as i16,
            from_node: -1,
            to_node: 0,
            aux: -1,
            payload_bits: 0,
        },
    );
    let wb = game.build_workbench(&snap);
    let state = MillRules::decode(&snap);
    let mobility = mobility_diff(&state, &opts);
    // Black to move; flip sign.  No material term (focus on blocking),
    // no mobility (consider_mobility=false but focus path still adds it
    // because should_consider_mobility is OR with focus).
    assert_eq!(MillEvaluator::score(&wb), -mobility);
}

/// Game-over with one side below `pieces_at_least_count` resolves to
/// the master VALUE_MATE constant (=80) before perspective flip.
#[test]
fn mill_evaluator_gameover_loss_under_three_pieces() {
    let rules = MillRules::default();
    let game = MillGame::default();
    let state = MillState {
        phase: MillPhase::GameOver,
        pieces_on_board: [9, 2], // black under three pieces
        side_to_move: 1,
        winner: 0,
        ..MillState::default()
    };
    let snap = rules.encode(state);
    let wb = game.build_workbench(&snap);
    // C++ produces +VALUE_MATE for "BLACK has fewer than the minimum"
    // (favourable to white).  side_to_move=BLACK then flips perspective,
    // yielding -VALUE_MATE from Black's POV.
    assert_eq!(MillEvaluator::score(&wb), -80);
}

// ---------------------------------------------------------------------------
// Phase 6.A.1: setup-position editing tests
// ---------------------------------------------------------------------------

#[test]
fn setup_clear_then_set_piece_round_trips() {
    let rules = MillRules::default();
    let options = MillVariantOptions::default();

    // Start from initial state, clear to empty board.
    let mut state = rules.setup_empty();
    assert!(
        state.board.iter().all(|&p| p == 0),
        "empty board must have no pieces"
    );
    assert_eq!(
        state.pieces_in_hand[0], 9,
        "pieces_in_hand initialised from piece_count"
    );

    // Place White on node 0, Black on node 6.
    state.set_piece(0, 1);
    state.set_piece(6, 2);
    state.recompute_aux(&options);

    assert_eq!(state.board[0], 1);
    assert_eq!(state.board[6], 2);
    assert_eq!(state.pieces_on_board[0], 1);
    assert_eq!(state.pieces_on_board[1], 1);
    assert_eq!(state.pieces_in_hand[0], 8, "9 - 1 on board");
    assert_eq!(state.pieces_in_hand[1], 8);

    // Encoding and decoding must round-trip.
    let snap = rules.encode_state(state);
    let decoded = MillRules::decode_snapshot(snap);
    assert_eq!(decoded.board[0], 1);
    assert_eq!(decoded.board[6], 2);
}

#[test]
fn setup_recompute_zobrist_differs_from_initial() {
    let rules = MillRules::default();
    let options = MillVariantOptions::default();

    let initial_snap = rules.initial_state(&[]);

    let mut state = rules.setup_empty();
    state.set_piece(0, 1); // add White on node 0
    state.recompute_aux(&options);
    let edited_snap = rules.encode_state(state);

    // With a piece on the board the zobrist key must differ from initial.
    assert_ne!(
        initial_snap.zobrist_key, edited_snap.zobrist_key,
        "placing a piece should change the Zobrist key"
    );
}

/// Two setup sequences that produce identical board states must hash to the
/// same Zobrist key after `recompute_aux`.  Different boards must differ.
#[test]
fn setup_recompute_zobrist_matches_apply() {
    let rules = MillRules::default();
    let options = MillVariantOptions::default();

    // Build board A: White on 0, Black on 6, in either set_piece order.
    let mut state_a = rules.setup_empty();
    state_a.set_piece(0, 1);
    state_a.set_piece(6, 2);
    state_a.recompute_aux(&options);
    let snap_a = rules.encode_state(state_a);

    // Build the same layout again in reverse set_piece order.
    let mut state_b = rules.setup_empty();
    state_b.set_piece(6, 2);
    state_b.set_piece(0, 1);
    state_b.recompute_aux(&options);
    let snap_b = rules.encode_state(state_b);

    assert_eq!(
        snap_a.zobrist_key, snap_b.zobrist_key,
        "identical board set up in different call order must hash equally"
    );

    // A board with one fewer piece must produce a different key.
    let mut state_c = rules.setup_empty();
    state_c.set_piece(0, 1); // only White, Black removed
    state_c.recompute_aux(&options);
    let snap_c = rules.encode_state(state_c);

    assert_ne!(
        snap_a.zobrist_key, snap_c.zobrist_key,
        "different board layouts must produce distinct Zobrist keys"
    );
}

#[test]
fn set_from_fen_then_export_round_trip() {
    let rules = MillRules::default();

    // A minimal placing-phase FEN with one white and one black piece.
    let fen = "O@******/********/******** w p p 1 8 1 8 0 0 0 0 0 0 0 0 1";
    let state = rules.set_from_fen(fen).expect("valid FEN must parse");

    // White on FEN pos 0 (sq 8) → node 17; Black on FEN pos 1 (sq 9) → node 18.
    assert_eq!(state.board[17], 1, "node 17 should be White");
    assert_eq!(state.board[18], 2, "node 18 should be Black");
    assert_eq!(state.side_to_move, 0, "White to move");
    assert_eq!(state.phase, MillPhase::Placing);
    assert_eq!(state.pieces_in_hand[0], 8);
    assert_eq!(state.pieces_in_hand[1], 8);

    // Export and re-import; key board fields must survive the round-trip.
    let exported = rules.export_fen(&state);
    let state2 = rules
        .set_from_fen(&exported)
        .expect("exported FEN must re-parse");
    assert_eq!(state2.board, state.board, "board round-trips");
    assert_eq!(state2.side_to_move, state.side_to_move, "side round-trips");
    assert_eq!(state2.phase, state.phase, "phase round-trips");
    assert_eq!(
        state2.pieces_in_hand, state.pieces_in_hand,
        "hand counts round-trip"
    );
}

#[test]
fn set_from_fen_moving_phase_counts_in_hand_for_fewer_than_three() {
    let rules = MillRules::default();
    // Regression for master Dart validateFen (eb69c427a): the moving phase may
    // begin while a side still holds pieces, so on-board count alone can sit
    // below `pieces_at_least_count` when board + hand total is still legal.
    let legal_fen = "********/@@@*O*@@/******** b m s 1 3 5 4 0 0 0 0 0 0 0 0 0 1";
    let state = rules
        .set_from_fen(legal_fen)
        .expect("legal moving-phase FEN with pieces in hand must parse");
    assert_eq!(state.phase, MillPhase::Moving);
    assert_eq!(state.winner, -1);

    // Board + hand total below threshold => immediate loss on import.
    let illegal_fen = "********/@@@*O*@@/******** b m s 1 1 5 4 0 0 0 0 0 0 0 0 0 1";
    let lose_state = rules
        .set_from_fen(illegal_fen)
        .expect("below-threshold FEN must still parse");
    assert_eq!(lose_state.phase, MillPhase::GameOver);
    assert_eq!(
        lose_state.outcome_reason,
        MillOutcomeReason::LoseFewerThanThree
    );
}

#[test]
fn set_from_fen_runs_immediate_terminal_checks() {
    let rules = MillRules::default();

    let lose_fen = "**O**O**/**@**@**/******** w m s 2 0 2 0 0 0 0 0 0 0 0 0 1";
    let lose_state = rules
        .set_from_fen(lose_fen)
        .expect("terminal fewer-than-three FEN must parse");
    assert_eq!(lose_state.phase, MillPhase::GameOver);
    assert_eq!(lose_state.winner, 1);
    assert_eq!(
        lose_state.outcome_reason,
        MillOutcomeReason::LoseFewerThanThree
    );

    let draw_fen = "***OOO**/***@@@**/******** w m s 3 0 3 0 0 0 0 0 0 0 0 100 1";
    let draw_state = rules
        .set_from_fen(draw_fen)
        .expect("terminal n-move FEN must parse");
    assert_eq!(draw_state.phase, MillPhase::GameOver);
    assert_eq!(draw_state.winner, 2);
    assert_eq!(draw_state.outcome_reason, MillOutcomeReason::DrawFiftyMove);
}

#[test]
fn search_priority_lists_match_master_without_shuffle() {
    let standard = MillVariantOptions::default();
    let ctx = tgf_core::MoveOrderContext {
        skill_level: 30,
        shuffling: false,
        ..Default::default()
    };
    assert_eq!(
        move_priority_list_for_search(&standard, &ctx),
        PRIORITY_NO_DIAGONAL
    );

    let diagonal = MillVariantOptions {
        has_diagonal_lines: true,
        ..Default::default()
    };
    assert_eq!(
        move_priority_list_for_search(&diagonal, &ctx),
        PRIORITY_DIAGONAL
    );

    let skill_one = tgf_core::MoveOrderContext {
        skill_level: 1,
        shuffling: false,
        ..Default::default()
    };
    assert_eq!(
        move_priority_list_for_search(&standard, &skill_one),
        PRIORITY_SKILL_1
    );
}

#[test]
fn generate_legal_ctx_uses_place_priority_order() {
    use tgf_core::Game;

    let rules = MillRules::default();
    let game = MillGame::default();
    let snap = rules.initial_state(&[]);
    let wb = game.build_workbench(&snap);
    let ctx = tgf_core::MoveOrderContext {
        skill_level: 30,
        shuffling: false,
        ..Default::default()
    };
    let mut actions = ActionList::<256>::new();
    MillGame::generate_legal_ctx(&wb, &mut actions, &ctx);
    let order = actions
        .iter()
        .map(|action| action.to_node as usize)
        .collect::<Vec<_>>();
    assert_eq!(order, PRIORITY_NO_DIAGONAL);
}

#[test]
fn generate_legal_ctx_uses_reverse_priority_for_remove() {
    let rules = MillRules::default();
    let state = MillState {
        board: [2; 24],
        side_to_move: 0,
        phase: MillPhase::Moving,
        pending_removals: [1, 0],
        mill_available_at_removal: true,
        pieces_on_board: [0, 24],
        ..MillState::default()
    };
    let ctx = tgf_core::MoveOrderContext {
        skill_level: 30,
        shuffling: false,
        ..Default::default()
    };
    let mut actions = ActionList::<256>::new();
    rules.legal_actions_ctx(&state, &mut actions, &ctx);
    let order = actions
        .iter()
        .map(|action| action.to_node as usize)
        .collect::<Vec<_>>();
    let mut expected = PRIORITY_NO_DIAGONAL.to_vec();
    expected.reverse();
    assert_eq!(order, expected);
}

/// FEN trailing-extension parity: the trailing `c:/i:/l:/p:/s:` block
/// must round-trip through `set_from_fen` -> `export_fen`, marked
/// pieces ('X') must survive, and the signed pieceToRemoveCount must
/// flip the new `remove_own_piece` flag.
#[test]
fn set_from_fen_extensions_round_trip() {
    let rules = MillRules::default();
    let original = MillState {
        board: {
            let mut board = [0_i8; 24];
            board[17] = 1;
            board[18] = 2;
            board[0] = 1; // will be flagged as marked below
            board
        },
        side_to_move: 0,
        phase: MillPhase::Placing,
        move_number: 1,
        pieces_in_hand: [7, 8],
        pieces_on_board: [2, 1],
        pending_removals: [1, 1],
        remove_own_piece: [true, true],
        last_mill_from: [9, 17],
        last_mill_to: [11, 18],
        delayed_marked_pieces: 1u32 << 0,
        custodian_targets: [1u32 << 5, 0],
        custodian_count: [1, 0],
        stalemate_removing: true,
        ..MillState::default()
    };
    let exported = rules.export_fen(&original);
    // The signed pieceToRemoveCount fields must be `-1`, the marked
    // square must render as `X`, and the trailing extension tokens
    // (`c:` and `s:1`) must be present.
    assert!(
        exported.contains("-1 -1"),
        "signed remove counts: {exported}"
    );
    assert!(exported.contains('X'), "marked piece: {exported}");
    assert!(exported.contains("c:"), "custodian extension: {exported}");
    assert!(exported.contains("s:1"), "stalemate flag: {exported}");

    let parsed = rules
        .set_from_fen(&exported)
        .expect("export must round-trip");
    assert_eq!(parsed.pending_removals, original.pending_removals);
    assert_eq!(parsed.remove_own_piece, original.remove_own_piece);
    assert_eq!(parsed.last_mill_from, original.last_mill_from);
    assert_eq!(parsed.last_mill_to, original.last_mill_to);
    assert_eq!(parsed.delayed_marked_pieces, original.delayed_marked_pieces);
    assert_eq!(parsed.custodian_targets, original.custodian_targets);
    assert_eq!(parsed.custodian_count, original.custodian_count);
    assert!(parsed.stalemate_removing);
}

/// Master format `s:2` flips `both_stalemate_removing`.  `p:NN`
/// preserves the preferredRemoveTarget hint as a Rust dense node id.
#[test]
fn set_from_fen_extensions_supports_both_stalemate_and_preferred_remove() {
    let rules = MillRules::default();
    // Legacy Square id 21 == "b2"; the FEN_TO_NODE permutation maps
    // it to Rust dense node 14.
    let fen = concat!(
        "********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1",
        " p:21 s:2"
    );
    let state = rules.set_from_fen(fen).expect("valid trailing tokens");
    assert!(!state.stalemate_removing);
    assert!(state.both_stalemate_removing);
    assert_eq!(
        state.preferred_remove_target, 14,
        "p:21 (legacy Square 21 = b2) must map to Rust node 14"
    );
    // Round-trip: export must emit `p:21` again.
    let exported = rules.export_fen(&state);
    assert!(
        exported.contains("p:21"),
        "round-trip preferred-remove: {exported}"
    );
}

#[test]
fn set_from_fen_capture_extensions_keep_per_side_state() {
    let rules = MillRules::default();
    let fen = concat!(
        "********/********/******** b m r 0 0 0 0 0 0 0 0 0 0 0 0 1",
        " c:w-1-8|b-1-31 i:w-2-9.10|b-1-30 l:w-1-11|b-1-29"
    );
    let state = rules.set_from_fen(fen).expect("valid capture tokens");

    assert_eq!(state.custodian_targets[0], node_bit(17));
    assert_eq!(state.custodian_targets[1], node_bit(0));
    assert_eq!(state.custodian_count, [1, 1]);
    assert_eq!(state.intervention_targets[0], node_bit(18) | node_bit(19));
    assert_eq!(state.intervention_targets[1], node_bit(7));
    assert_eq!(state.intervention_count, [2, 1]);
    assert_eq!(state.leap_targets[0], node_bit(20));
    assert_eq!(state.leap_targets[1], node_bit(6));
    assert_eq!(state.leap_count, [1, 1]);

    let exported = rules.export_fen(&state);
    assert!(exported.contains("c:w-1-8|b-1-31"), "{exported}");
    assert!(exported.contains("i:w-2-9.10|b-1-30"), "{exported}");
    assert!(exported.contains("l:w-1-11|b-1-29"), "{exported}");
}

#[test]
fn set_from_fen_preserves_action_independently_from_phase() {
    let rules = MillRules::default();
    let remove_fen = "O@******/********/******** w p r 1 8 1 8 0 0 0 0 0 0 0 0 1";
    let place_fen = "O@******/********/******** w p p 1 8 1 8 0 0 0 0 0 0 0 0 1";

    let remove_state = rules
        .set_from_fen(remove_fen)
        .expect("remove-action FEN must parse");
    let place_state = rules
        .set_from_fen(place_fen)
        .expect("place-action FEN must parse");
    assert_eq!(remove_state.phase, MillPhase::Placing);
    assert_eq!(remove_state.action, MillActionState::Remove);
    assert_eq!(place_state.action, MillActionState::Place);

    let mut remove_actions = ActionList::<256>::new();
    rules.legal_actions(
        &rules.encode_state(remove_state.clone()),
        &mut remove_actions,
    );
    let mut place_actions = ActionList::<256>::new();
    rules.legal_actions(&rules.encode_state(place_state), &mut place_actions);

    assert!(
        remove_actions
            .iter()
            .all(|a| a.kind_tag == MillActionKind::Remove as i16),
        "phase=p action=r must route to remove generation"
    );
    assert!(
        place_actions
            .iter()
            .any(|a| a.kind_tag == MillActionKind::Place as i16),
        "phase=p action=p must route to placing generation"
    );
    assert_eq!(
        rules.export_fen(&remove_state).split_whitespace().nth(3),
        Some("r")
    );
}

/// `formed_mills_bb` is FEN field 14, encoded as
/// `((white_legacy_bb) << 32) | black_legacy_bb`.  Per-side bits set
/// by `note_mill_formation` (oneTimeUseMill semantics).  Test the
/// full round-trip and that the bitmask field becomes non-zero after
/// a real mill formation under one_time_use_mill.
#[test]
fn export_fen_carries_formed_mills_bb_round_trip() {
    let rules = MillRules::new(MillVariantOptions {
        one_time_use_mill: true,
        ..MillVariantOptions::default()
    });
    // White just placed at node 2 closing the mill 0/1/2.  `apply`
    // takes the place action; under one_time_use_mill,
    // note_mill_formation populates formed_mills_bb[0].
    let mut state = MillState {
        side_to_move: 0,
        phase: MillPhase::Placing,
        move_number: 0,
        pieces_in_hand: [9, 9],
        pieces_on_board: [0, 0],
        ..MillState::default()
    };
    state.board[0] = 1;
    state.board[1] = 1;
    let after = rules.apply(
        &rules.encode_state(state),
        Action {
            kind_tag: MillActionKind::Place as i16,
            from_node: -1,
            to_node: 2,
            aux: -1,
            payload_bits: 0,
        },
    );
    let after_state = MillRules::decode(&after);
    assert_ne!(
        after_state.formed_mills_bb[0], 0,
        "mill formation must populate formed_mills_bb[white]"
    );
    let expected_white_bb = (1u32 << 0) | (1u32 << 1) | (1u32 << 2);
    assert_eq!(after_state.formed_mills_bb[0], expected_white_bb);
    assert_eq!(after_state.formed_mills_bb[1], 0);

    // Now FEN export must contain a non-zero field 14 and round-trip
    // through set_from_fen back to the same per-side bitmaps.
    let exported = rules.export_fen(&after_state);
    let fields: Vec<&str> = exported.split_whitespace().collect();
    let formed_field: u64 = fields[14].parse().expect("field 14 must be a u64");
    assert_ne!(formed_field, 0, "FEN field 14 must be non-zero");
    let parsed = rules
        .set_from_fen(&exported)
        .expect("export must round-trip");
    assert_eq!(parsed.formed_mills_bb, after_state.formed_mills_bb);
}

/// Field 3 must mirror legacy `Position::fen()` action token:
///   - `'r'` iff a removal is pending,
///   - `'p'` while still placing (or in Ready phase),
///   - `'s'` for the moving-phase select-square step,
///   - `'?'` on game over.
///
/// The parser must round-trip every valid token.
#[test]
fn export_fen_action_token_matches_legacy_position_fen() {
    let rules = MillRules::default();

    // Initial position: white-to-move, placing, no pending removal.
    let initial = rules.encode_state(
        rules
            .set_from_fen("********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1")
            .unwrap(),
    );
    let state = MillRules::decode_snapshot(initial);
    let fen = rules.export_fen(&state);
    let action_field = fen.split_whitespace().nth(3).unwrap();
    assert_eq!(action_field, "p", "placing/no-remove must be 'p'");

    // Moving phase, no pending removal: action should be 's'.
    let moving = rules.no_mill_moving_phase_snapshot();
    let state = MillRules::decode_snapshot(moving);
    let fen = rules.export_fen(&state);
    let action_field = fen.split_whitespace().nth(3).unwrap();
    assert_eq!(action_field, "s", "moving phase must be 's'");

    // Re-parsing the action token must succeed without error.
    rules
        .set_from_fen(&fen)
        .expect("'s' action token must parse");
}

#[test]
fn set_from_fen_matches_apply_sequence_zobrist() {
    let rules = MillRules::default();

    // Load the no-mill moving-phase fixture via both paths:
    //   (a) apply the canonical placing sequence, then export + re-import.
    //   (b) export directly and compare the board bytes.
    let snap_applied = rules.no_mill_moving_phase_snapshot();
    let state_applied = MillRules::decode_snapshot(snap_applied);

    let fen_from_apply = rules.export_fen(&state_applied);
    let state_loaded = rules
        .set_from_fen(&fen_from_apply)
        .expect("FEN exported from applied state must be parseable");

    // The board layout must be identical; auxiliary fields (last-mill,
    // mills-bitmask) may differ because export_fen outputs defaults.
    assert_eq!(
        state_loaded.board, state_applied.board,
        "set_from_fen must reproduce the same board as apply sequence"
    );
    assert_eq!(state_loaded.side_to_move, state_applied.side_to_move);
    assert_eq!(state_loaded.phase, state_applied.phase);

    // Zobrist keys must match (board + side + phase + pieces_in_hand are
    // identical, and move_number is reconstructed from fullmove counter).
    let snap_loaded = rules.encode_state(state_loaded);
    assert_eq!(
        snap_applied.zobrist_key, snap_loaded.zobrist_key,
        "Zobrist key must match after FEN export+import round-trip"
    );
}

#[test]
fn setup_clear_piece_owner_zero_empties_square() {
    let rules = MillRules::default();
    let options = MillVariantOptions::default();

    let mut state = rules.setup_empty();
    state.set_piece(5, 1); // White on node 5
    state.set_piece(5, 0); // clear node 5
    state.recompute_aux(&options);

    assert_eq!(state.board[5], 0, "clearing owner=0 must empty the square");
    assert_eq!(state.pieces_on_board[0], 0);
}
