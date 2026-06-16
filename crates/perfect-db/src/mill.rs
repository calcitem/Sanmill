// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

//! Mill-specific adapter that maps a `tgf-mill` board state onto the perfect
//! database's bitboard encoding and returns the best-move notation token.
//!
//! Both the Flutter bridge (`tgf-frb`) and the headless CLI (`tgf-cli`)
//! consume this helper so the node-to-perfect-index mapping lives in exactly
//! one place.  Each caller matches the returned token against its own legal
//! action list (using the shared `tgf_mill::MillUciCodec`).

use std::sync::OnceLock;

use crate::database::{
    Database, DatabaseError, DatabaseProvider, DatabaseVariant, PerfectOutcome, PerfectQuery,
};
use tgf_core::{Action, ActionList, GameRules, GameStateSnapshot, OutcomeKind};
use tgf_mill::rules::MillState;
use tgf_mill::{MillPhase, MillRules, MillUciCodec, MillVariantOptions, default_mill_topology};

const MAX_REMOVAL_CONTINUATION_DEPTH: u8 = 4;

/// C++ `Square` ids returned by Malom's `from_perfect_square` for perfect
/// indices 0..24.  The mapping itself is recovered from the Mill topology at
/// runtime (see [`node_to_perfect_index`]); this table only encodes the
/// fixed perfect-index → C++ Square relationship from the original engine.
const PERFECT_TO_SQUARE: [u16; 24] = [
    30, 31, 24, 25, 26, 27, 28, 29, 22, 23, 16, 17, 18, 19, 20, 21, 14, 15, 8, 9, 10, 11, 12, 13,
];

static NODE_TO_PERFECT: OnceLock<[u8; 24]> = OnceLock::new();
static PERFECT_TO_NODE: OnceLock<[u8; 24]> = OnceLock::new();

/// Build (and cache) the `node_id -> perfect_index` lookup by reverse-mapping
/// the canonical Mill topology's `square` field through [`PERFECT_TO_SQUARE`].
fn node_to_perfect_index() -> &'static [u8; 24] {
    NODE_TO_PERFECT.get_or_init(|| {
        let topo = default_mill_topology();
        let mut map = [0u8; 24];
        for (perfect_idx, &square) in PERFECT_TO_SQUARE.iter().enumerate() {
            let node = topo
                .nodes()
                .iter()
                .find(|n| n.square == square)
                .map(|n| n.id as u8)
                .unwrap_or_else(|| {
                    panic!("topology missing square {square} for perfect index {perfect_idx}")
                });
            map[node as usize] = perfect_idx as u8;
        }
        map
    })
}

fn perfect_to_node_index() -> &'static [u8; 24] {
    PERFECT_TO_NODE.get_or_init(|| {
        let node_map = node_to_perfect_index();
        let mut map = [0u8; 24];
        for (node, &perfect_idx) in node_map.iter().enumerate() {
            map[perfect_idx as usize] = node as u8;
        }
        map
    })
}

fn bitboards_from_state(state: &MillState) -> (u32, u32) {
    let node_map = node_to_perfect_index();
    let mut white_bits = 0u32;
    let mut black_bits = 0u32;
    for (node, &occupant) in state.board().iter().enumerate() {
        let perfect_idx = node_map[node];
        let mask = 1u32 << perfect_idx;
        match occupant {
            1 => white_bits |= mask,
            2 => black_bits |= mask,
            _ => {}
        }
    }
    (white_bits, black_bits)
}

/// Build a TGF Mill snapshot from a perfect-database bitboard query.
///
/// The coordinate conversion is intentionally confined to this database
/// boundary. After this point callers use the normal `tgf-mill` state,
/// legal-action, and apply machinery.
pub fn snapshot_from_perfect_query(
    rules: &MillRules,
    options: &MillVariantOptions,
    query: PerfectQuery,
) -> GameStateSnapshot {
    let mut state = rules.setup_empty();
    let node_map = perfect_to_node_index();
    for (perfect_idx, &node) in node_map.iter().enumerate() {
        let mask = 1u32 << perfect_idx;
        let node = u16::from(node);
        if query.white_bits & mask != 0 {
            state.set_piece(node, 1);
        } else if query.black_bits & mask != 0 {
            state.set_piece(node, 2);
        }
    }

    state.recompute_aux(options);
    state.set_pieces_in_hand([query.white_in_hand, query.black_in_hand], options);
    state.set_side_to_move(query.side_to_move as i8);

    if query.white_in_hand > 0 || query.black_in_hand > 0 {
        state.set_phase(MillPhase::Placing);
    } else if !query.only_stone_taking
        && let Some(winner) = state.check_pieces_at_least(options)
    {
        state.set_phase(MillPhase::GameOver);
        state.set_winner(winner);
        state.set_outcome_reason_fewer_than_threshold();
    } else {
        state.set_phase(MillPhase::Moving);
    }

    if query.only_stone_taking {
        state.set_pending_removal(query.side_to_move as usize, 1);
    }

    rules.encode_state(state)
}

fn query_from_state(
    state: &MillState,
    options: &MillVariantOptions,
    side_to_move: i8,
) -> Option<PerfectQuery> {
    if !DatabaseVariant::from_piece_count(options.piece_count)?.is_standard() {
        return None;
    }
    assert!(
        side_to_move == 0 || side_to_move == 1,
        "Perfect DB side_to_move must be 0 or 1"
    );

    let (white_bits, black_bits) = bitboards_from_state(state);
    let in_hand = state.pieces_in_hand();
    let pending = state.pending_removals();
    let only_stone_taking = pending[side_to_move as usize] > 0;

    Some(PerfectQuery::new(
        white_bits,
        black_bits,
        in_hand[0],
        in_hand[1],
        side_to_move as u8,
        only_stone_taking,
    ))
}

/// Query the perfect database for the best move in `state`, returned as a Mill
/// UCI notation token (`"a4"`, `"a1-a4"`, `"xg7"`).
///
/// Returns `None` when the database is not initialized, the variant is not the
/// standard 9-piece game (the only bundled dataset), the side to move is
/// invalid, or the database has no entry for the position.  Callers match the
/// token against their own legal action list.
pub fn best_move_token_for_state(
    state: &MillState,
    options: &MillVariantOptions,
    side_to_move: i8,
) -> Option<String> {
    if !crate::is_initialized() {
        return None;
    }
    if side_to_move != 0 && side_to_move != 1 {
        return None;
    }
    let query = query_from_state(state, options, side_to_move)?;

    crate::best_move_token(
        query.white_bits,
        query.black_bits,
        query.white_in_hand,
        query.black_in_hand,
        query.side_to_move,
        query.only_stone_taking,
    )
}

/// Evaluate `state` through the perfect database, returning `(wdl, steps)`
/// from the perspective of `side_to_move` (`wdl`: 1 = win, 0 = draw,
/// -1 = loss; `steps`: distance-to-conversion, or a negative value when the
/// database does not expose a step count).
///
/// Returns `None` under the same conditions as [`best_move_token_for_state`]:
/// the database is not initialized, the variant is not the standard 9-piece
/// game, the side to move is invalid, or the position has no entry.  This is
/// the per-move primitive consumed by the analysis overlay, which evaluates
/// the position that results from each candidate move.
pub fn evaluate_state_for(
    state: &MillState,
    options: &MillVariantOptions,
    side_to_move: i8,
) -> Option<(i32, i32)> {
    if !crate::is_initialized() {
        return None;
    }
    if side_to_move != 0 && side_to_move != 1 {
        return None;
    }
    let query = query_from_state(state, options, side_to_move)?;

    crate::evaluate(
        query.white_bits,
        query.black_bits,
        query.white_in_hand,
        query.black_in_hand,
        query.side_to_move,
        query.only_stone_taking,
    )
}

/// Evaluate `state` through a Rust-native database instance.
///
/// This is the migration bridge used by tests and future callers that need an
/// explicit Rust database instance instead of the process-global API.
pub fn evaluate_state_with_database<P: DatabaseProvider>(
    database: &mut Database<P>,
    state: &MillState,
    options: &MillVariantOptions,
    side_to_move: i8,
) -> Result<Option<(i32, i32)>, DatabaseError> {
    let Some(query) = query_from_state(state, options, side_to_move) else {
        return Ok(None);
    };
    database.evaluate(query)
}

pub fn evaluate_state_outcome_with_database<P: DatabaseProvider>(
    database: &mut Database<P>,
    state: &MillState,
    options: &MillVariantOptions,
    side_to_move: i8,
) -> Result<Option<PerfectOutcome>, DatabaseError> {
    let Some(query) = query_from_state(state, options, side_to_move) else {
        return Ok(None);
    };
    database.evaluate_outcome(query)
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PerfectMoveChoice {
    pub token: String,
    pub outcome: PerfectOutcome,
}

/// Select a deterministic best legal action using the Rust-native database.
///
/// This intentionally reuses `tgf-mill` legal action generation and apply.
/// Compound mill-closing candidates are represented as ordinary TGF action
/// continuations instead of copying C++ `AdvancedMove`.
pub fn best_move_choice_with_database<P: DatabaseProvider>(
    database: &mut Database<P>,
    rules: &MillRules,
    snap: &GameStateSnapshot,
    options: &MillVariantOptions,
) -> Result<Option<PerfectMoveChoice>, DatabaseError> {
    let root_side = snap.side_to_move;
    if !DatabaseVariant::from_piece_count(options.piece_count)
        .is_some_and(DatabaseVariant::is_standard)
    {
        return Ok(None);
    }
    if root_side != 0 && root_side != 1 {
        return Ok(None);
    }

    let mut actions = ActionList::<256>::new();
    rules.legal_actions(snap, &mut actions);

    let mut best: Option<(Action, PerfectOutcome)> = None;
    for &action in actions.as_slice() {
        let child_snap = rules.apply(snap, action);
        let Some(outcome) =
            child_outcome_for_root(database, rules, &child_snap, options, root_side)?
        else {
            continue;
        };
        if best.is_none_or(|(_, best_outcome)| outcome.default_rank() > best_outcome.default_rank())
        {
            best = Some((action, outcome));
        }
    }

    Ok(best.map(|(action, outcome)| PerfectMoveChoice {
        token: MillUciCodec::encode_action(action),
        outcome,
    }))
}

pub fn best_move_choice_for_query_with_database<P: DatabaseProvider>(
    database: &mut Database<P>,
    rules: &MillRules,
    options: &MillVariantOptions,
    query: PerfectQuery,
) -> Result<Option<PerfectMoveChoice>, DatabaseError> {
    let snap = snapshot_from_perfect_query(rules, options, query);
    best_move_choice_with_database(database, rules, &snap, options)
}

pub fn best_move_token_with_database<P: DatabaseProvider>(
    database: &mut Database<P>,
    rules: &MillRules,
    snap: &GameStateSnapshot,
    options: &MillVariantOptions,
) -> Result<Option<String>, DatabaseError> {
    Ok(best_move_choice_with_database(database, rules, snap, options)?.map(|choice| choice.token))
}

fn child_outcome_for_root<P: DatabaseProvider>(
    database: &mut Database<P>,
    rules: &MillRules,
    child_snap: &GameStateSnapshot,
    options: &MillVariantOptions,
    root_side: i8,
) -> Result<Option<PerfectOutcome>, DatabaseError> {
    continuation_outcome_for_root(database, rules, child_snap, options, root_side, 0)
}

fn continuation_outcome_for_root<P: DatabaseProvider>(
    database: &mut Database<P>,
    rules: &MillRules,
    snap: &GameStateSnapshot,
    options: &MillVariantOptions,
    root_side: i8,
    depth: u8,
) -> Result<Option<PerfectOutcome>, DatabaseError> {
    assert!(
        depth <= MAX_REMOVAL_CONTINUATION_DEPTH,
        "Perfect DB removal continuation exceeded the expected Mill bound"
    );

    if let Some(outcome) = terminal_outcome_for_root(rules, snap, root_side) {
        return Ok(Some(outcome));
    }

    let side_to_move = snap.side_to_move;
    if side_to_move != 0 && side_to_move != 1 {
        return Ok(None);
    }

    let state = MillRules::decode_snapshot(*snap);
    if state.pending_removals()[side_to_move as usize] > 0 {
        assert!(
            depth < MAX_REMOVAL_CONTINUATION_DEPTH,
            "Perfect DB removal continuation must finish before the depth cap"
        );
        let mut actions = ActionList::<256>::new();
        rules.legal_actions(snap, &mut actions);
        let mut best: Option<PerfectOutcome> = None;
        for &action in actions.as_slice() {
            let next = rules.apply(snap, action);
            let Some(outcome) = continuation_outcome_for_root(
                database,
                rules,
                &next,
                options,
                root_side,
                depth + 1,
            )?
            else {
                continue;
            };
            if best.is_none_or(|best_outcome| outcome.default_rank() > best_outcome.default_rank())
            {
                best = Some(outcome);
            }
        }
        return Ok(best);
    }

    let Some(outcome) =
        evaluate_state_outcome_with_database(database, &state, options, side_to_move)?
    else {
        return Ok(None);
    };

    Ok(Some(if side_to_move == root_side {
        outcome
    } else {
        outcome.negate()
    }))
}

fn terminal_outcome_for_root(
    rules: &MillRules,
    snap: &GameStateSnapshot,
    root_side: i8,
) -> Option<PerfectOutcome> {
    match rules.outcome(snap).kind {
        OutcomeKind::Ongoing => None,
        OutcomeKind::Draw => Some(PerfectOutcome::Draw { steps: 0 }),
        OutcomeKind::Win(side) => Some(if side == root_side {
            PerfectOutcome::Win { steps: 0 }
        } else {
            PerfectOutcome::Loss { steps: 0 }
        }),
        OutcomeKind::Abandoned | OutcomeKind::WinTeam(_) => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn perfect_index_labels_match_topology() {
        let expected = [
            "a4", "a7", "d7", "g7", "g4", "g1", "d1", "a1", "b4", "b6", "d6", "f6", "f4", "f2",
            "d2", "b2", "c4", "c5", "d5", "e5", "e4", "e3", "d3", "c3",
        ];
        let topo = default_mill_topology();
        for (perfect_idx, &square) in PERFECT_TO_SQUARE.iter().enumerate() {
            let node = topo
                .nodes()
                .iter()
                .find(|n| n.square == square)
                .unwrap_or_else(|| panic!("missing square {square}"));
            assert_eq!(
                node.label, expected[perfect_idx],
                "perfect index {perfect_idx}"
            );
        }
    }
}
