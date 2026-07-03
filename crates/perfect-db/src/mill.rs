// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

//! Mill-specific adapter that maps a `tgf-mill` board state onto the perfect
//! database's bitboard encoding and returns the best-move notation token.
//!
//! Both the Flutter bridge (`tgf-frb`) and the headless CLI (`tgf-cli`)
//! consume this helper so the node-to-perfect-index mapping lives in exactly
//! one place.  Each caller matches the returned token against its own legal
//! action list (using the shared `tgf_mill::MillUciCodec`).

use std::cmp::Ordering;
use std::sync::OnceLock;

use crate::database::{
    Database, DatabaseError, DatabaseProvider, DatabaseVariant, PerfectOutcome, PerfectQuery,
};
use crate::wdl_plane::WdlPlaneCache;
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

/// Build a [`PerfectQuery`] from a `tgf-mill` state, or `None` when the
/// variant/side is not one the perfect database supports.  Public because
/// mining and other tooling that needs the database's canonical
/// `(sector, bitboard)` view of a position (not just a WDL/best-move answer)
/// has no other way to reach it: the node<->perfect-index bitboard
/// conversion is otherwise private to this module.
pub fn query_from_state(
    state: &MillState,
    options: &MillVariantOptions,
    side_to_move: i8,
) -> Option<PerfectQuery> {
    variant_from_options(options)?;
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

fn variant_from_options(options: &MillVariantOptions) -> Option<DatabaseVariant> {
    DatabaseVariant::from_mill_options(options)
}

fn database_matches_options<P: DatabaseProvider>(
    database: &Database<P>,
    options: &MillVariantOptions,
) -> bool {
    variant_from_options(options) == Some(database.variant())
}

fn process_global_database_matches_options(options: &MillVariantOptions) -> bool {
    let Some(variant) = variant_from_options(options) else {
        return false;
    };
    if crate::is_rust_backend_enabled() {
        return crate::loaded_variant_rust_database() == Some(variant);
    }
    crate::loaded_variant_cpp_database() == Some(variant)
}

/// Query the perfect database for the best move in `state`, returned as a Mill
/// UCI notation token (`"a4"`, `"a1-a4"`, `"xg7"`).
///
/// Returns `None` when the database is not initialized, the loaded database
/// variant does not match the Mill options, the side to move is invalid, or the
/// database has no entry for the position.  Callers match the token against
/// their own legal action list.
pub fn best_move_token_for_state(
    state: &MillState,
    options: &MillVariantOptions,
    side_to_move: i8,
) -> Option<String> {
    best_move_token_for_state_with_ordering(
        state,
        options,
        side_to_move,
        PerfectMoveOrdering::LegacyWdl,
    )
}

/// Query the perfect database for the best move in `state` using an explicit
/// move ordering policy.
///
/// This is the runtime entry point for callers that mirror master C++'s
/// Random/non-lazy strict-step branch. See [`PerfectMoveOrdering`].
pub fn best_move_token_for_state_with_ordering(
    state: &MillState,
    options: &MillVariantOptions,
    side_to_move: i8,
    ordering: PerfectMoveOrdering,
) -> Option<String> {
    if !crate::is_initialized() {
        return None;
    }
    if side_to_move != 0 && side_to_move != 1 {
        return None;
    }
    if !process_global_database_matches_options(options) {
        return None;
    }
    let query = query_from_state(state, options, side_to_move)?;

    if crate::is_rust_backend_enabled() {
        return match crate::best_move_token_for_state_rust_database_with_ordering(
            state,
            options,
            side_to_move,
            ordering,
        ) {
            Ok(token) => token,
            Err(err) if err.is_missing_asset() => None,
            Err(err) => panic!("Rust Perfect DB state best move failed: {err}"),
        };
    }

    assert_eq!(
        ordering,
        PerfectMoveOrdering::LegacyWdl,
        "C++ Perfect DB oracle wrapper does not expose strict-step ordering"
    );
    crate::best_move_token_with_options(&query, options, ordering)
}

/// Every legal move tied for the best database outcome under `ordering`, as
/// Mill UCI tokens.  The caller is expected to apply the legacy `chooseRandom`
/// policy (prefer the search's pick among the tied moves, otherwise shuffle)
/// rather than always taking the first — see `perfect_player.h` in the C++
/// engine.  Returns `None` under the same conditions as
/// [`best_move_token_for_state_with_ordering`].
pub fn best_move_tokens_for_state_with_ordering(
    state: &MillState,
    options: &MillVariantOptions,
    side_to_move: i8,
    ordering: PerfectMoveOrdering,
) -> Option<Vec<String>> {
    if !crate::is_initialized() {
        return None;
    }
    if side_to_move != 0 && side_to_move != 1 {
        return None;
    }
    if !process_global_database_matches_options(options) {
        return None;
    }
    let query = query_from_state(state, options, side_to_move)?;

    if crate::is_rust_backend_enabled() {
        return match crate::best_move_tokens_for_state_rust_database_with_ordering(
            state,
            options,
            side_to_move,
            ordering,
        ) {
            Ok(tokens) => tokens,
            Err(err) if err.is_missing_asset() => None,
            Err(err) => panic!("Rust Perfect DB state best moves failed: {err}"),
        };
    }

    // The C++ oracle wrapper exposes only the single best token; fall back to
    // a one-element list so the caller's chooseRandom path still works.
    assert_eq!(
        ordering,
        PerfectMoveOrdering::LegacyWdl,
        "C++ Perfect DB oracle wrapper does not expose strict-step ordering"
    );
    crate::best_move_token_with_options(&query, options, ordering).map(|token| vec![token])
}

/// Evaluate `state` through the perfect database, returning `(wdl, steps)`
/// from the perspective of `side_to_move` (`wdl`: 1 = win, 0 = draw,
/// -1 = loss; `steps`: distance-to-conversion, or a negative value when the
/// database does not expose a step count).
///
/// Returns `None` under the same conditions as [`best_move_token_for_state`]:
/// the database is not initialized, the loaded database variant does not match
/// the Mill options, the side to move is invalid, or the position has no entry.
/// This is the per-move primitive consumed by the analysis overlay, which
/// evaluates the position that results from each candidate move.
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
    if !process_global_database_matches_options(options) {
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
    if !database_matches_options(database, options) {
        return Ok(None);
    }
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
    if !database_matches_options(database, options) {
        return Ok(None);
    }
    let Some(query) = query_from_state(state, options, side_to_move) else {
        return Ok(None);
    };
    database.evaluate_outcome(query)
}

/// Canonical key for a *mid-removal* position (`pending_removals[side] > 0`).
///
/// Mid-removal positions have no entry in the database's own sector
/// indexing at all: the sector-fold convention requires the mover to have
/// placed at most as many pieces as the opponent (verified empirically
/// against every shipped `.secval`), which a mover's own just-completed
/// placement/move momentarily violates until the forced removal resolves
/// it. [`crate::wdl_plane::WdlPlaneCache::canonical_key_for_query`]'s
/// `(sector, slot)` scheme is therefore not just unavailable but
/// *meaningless* here -- Malom's solver never represents these states
/// directly (see [`resolve_wdl_with_plane`]'s removal recursion, which
/// resolves values without ever querying a mid-removal sector).
///
/// This instead folds the raw board through the same 16 board symmetries
/// the database uses and hashes the canonical form directly, so two
/// concrete boards that are symmetric or color-mirror images still key
/// identically (matching the guarantee `pack_canonical_key` gives settled
/// positions). Bit 63 is always set to tag this key space; a
/// `pack_canonical_key` result never sets it (sector piece counts are
/// always `<= 12`), so the two key spaces can never collide.
pub fn mid_removal_key(state: &MillState) -> Option<u64> {
    let side = state.side_to_move();
    if side != 0 && side != 1 {
        return None;
    }
    let (white_bits, black_bits) = bitboards_from_state(state);
    let board = u64::from(white_bits) | (u64::from(black_bits) << 24);
    let canonical_board = (0..16_u8)
        .map(|op| crate::index::symmetry::transform48(op, board))
        .min()
        .expect("16 symmetry operations always yield at least one candidate");

    let hand = state.pieces_in_hand();
    let pending = state.pending_removals();
    let mut hash = 0xcbf2_9ce4_8422_2325_u64;
    let mut mix = |value: u64| {
        for byte in value.to_le_bytes() {
            hash ^= u64::from(byte);
            hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
        }
    };
    mix(canonical_board);
    mix(u64::from(hand[0]));
    mix(u64::from(hand[1]));
    mix(u64::from(pending[0]));
    mix(u64::from(pending[1]));
    mix(u64::from(side as u8));

    Some(crate::wdl_plane::MID_REMOVAL_KEY_TAG | (hash & !crate::wdl_plane::MID_REMOVAL_KEY_TAG))
}

/// Canonical mining/runtime key for any (settled or mid-removal) Mill
/// state: the database's own `(sector, slot)` key for settled positions
/// (see [`crate::wdl_plane::WdlPlaneCache::canonical_key_for_query`]), or
/// [`mid_removal_key`] for mid-removal ones. Every caller that needs a
/// stable position identity -- the mining pipeline's dedup keys and the
/// runtime patch lookup alike -- should go through this single entry point
/// rather than re-deriving the settled/mid-removal fork itself.
pub fn canonical_key<P: DatabaseProvider>(
    plane_cache: &mut WdlPlaneCache<P>,
    state: &MillState,
    options: &MillVariantOptions,
) -> Option<u64> {
    let side = state.side_to_move();
    if side != 0 && side != 1 {
        return None;
    }
    if state.pending_removals()[side as usize] > 0 {
        return mid_removal_key(state);
    }
    let query = query_from_state(state, options, side)?;
    Some(plane_cache.canonical_key_for_query(query))
}

/// Resolve `snap`'s WDL (`-1`/`0`/`1`) from its own side-to-move's
/// perspective using the fast [`WdlPlaneCache`] instead of the precise
/// (steps-carrying) database.
///
/// Mid-removal snapshots have no direct database entry (mirrors
/// [`Database::evaluate`], which returns `None` for `only_stone_taking`
/// queries): this resolves them by recursing one ply into each removal
/// choice and negating, exactly like the precise-database
/// `continuation_outcome_for_root` path below. The Perfect-DB-compatible
/// ruleset never chains more than one removal per turn
/// (`may_remove_multiple` is always false there), so the recursion is
/// shallow; [`MAX_REMOVAL_CONTINUATION_DEPTH`] is kept as a defensive bound
/// shared with the precise path rather than a expected depth.
///
/// This is the primitive the mining pipeline's cheap tier-2 pre-filter is
/// built on: it is cheap enough to call once per legal move at every
/// visited node (a handful of plane lookups), unlike a full engine search.
pub fn resolve_wdl_with_plane<P: DatabaseProvider>(
    plane_cache: &mut WdlPlaneCache<P>,
    rules: &MillRules,
    snap: &GameStateSnapshot,
    options: &MillVariantOptions,
) -> Result<Option<i8>, DatabaseError> {
    resolve_wdl_with_plane_inner(plane_cache, rules, snap, options, 0)
}

fn resolve_wdl_with_plane_inner<P: DatabaseProvider>(
    plane_cache: &mut WdlPlaneCache<P>,
    rules: &MillRules,
    snap: &GameStateSnapshot,
    options: &MillVariantOptions,
    depth: u8,
) -> Result<Option<i8>, DatabaseError> {
    assert!(
        depth <= MAX_REMOVAL_CONTINUATION_DEPTH,
        "Perfect DB plane removal continuation exceeded the expected Mill bound"
    );

    match rules.outcome(snap).kind {
        OutcomeKind::Ongoing => {}
        OutcomeKind::Draw => return Ok(Some(0)),
        OutcomeKind::Win(side) => {
            return Ok(Some(if side == snap.side_to_move { 1 } else { -1 }));
        }
        OutcomeKind::Abandoned | OutcomeKind::WinTeam(_) => return Ok(None),
    }

    let side_to_move = snap.side_to_move;
    if side_to_move != 0 && side_to_move != 1 {
        return Ok(None);
    }

    let state = MillRules::decode_snapshot(*snap);
    if state.pending_removals()[side_to_move as usize] > 0 {
        assert!(
            depth < MAX_REMOVAL_CONTINUATION_DEPTH,
            "Perfect DB plane removal continuation must finish before the depth cap"
        );
        let mut actions = ActionList::<256>::new();
        rules.legal_actions(snap, &mut actions);
        let mut best: Option<i8> = None;
        for &action in actions.as_slice() {
            let next = rules.apply(snap, action);
            let Some(child_wdl) =
                resolve_wdl_with_plane_inner(plane_cache, rules, &next, options, depth + 1)?
            else {
                return Ok(None);
            };
            let value = if next.side_to_move == side_to_move {
                child_wdl
            } else {
                -child_wdl
            };
            if best.is_none_or(|incumbent| value > incumbent) {
                best = Some(value);
            }
        }
        return Ok(best);
    }

    let Some(query) = query_from_state(&state, options, side_to_move) else {
        return Ok(None);
    };
    plane_cache.wdl_for_query(query)
}

/// Every legal action's fast-plane WDL from the root side's perspective, in
/// legal-action order.  The tier-2 pre-filter counterpart of
/// [`all_move_outcomes_with_ordering`]: cheaper (no step counts, no disk
/// symmetry probe once the sector's plane is cached) but otherwise the same
/// child-enumeration shape.
///
/// Returns `None` under the same conditions as
/// [`all_move_outcomes_with_ordering`]: an invalid side to move, or any
/// candidate line running into a position the plane cache cannot resolve
/// (unsupported variant, or the underlying provider is missing the sector).
pub fn all_move_wdl_fast<P: DatabaseProvider>(
    plane_cache: &mut WdlPlaneCache<P>,
    rules: &MillRules,
    snap: &GameStateSnapshot,
    options: &MillVariantOptions,
) -> Result<Option<Vec<(Action, i8)>>, DatabaseError> {
    let root_side = snap.side_to_move;
    if root_side != 0 && root_side != 1 {
        return Ok(None);
    }

    let mut actions = ActionList::<256>::new();
    rules.legal_actions(snap, &mut actions);

    let mut results = Vec::with_capacity(actions.as_slice().len());
    for &action in actions.as_slice() {
        let child_snap = rules.apply(snap, action);
        let Some(child_wdl) = resolve_wdl_with_plane(plane_cache, rules, &child_snap, options)?
        else {
            return Ok(None);
        };
        let value = if child_snap.side_to_move == root_side {
            child_wdl
        } else {
            -child_wdl
        };
        results.push((action, value));
    }
    Ok(Some(results))
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PerfectMoveChoice {
    pub token: String,
    pub outcome: PerfectOutcome,
}

/// Move ordering policy used when several legal actions have database values.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PerfectMoveOrdering {
    /// Match the legacy C++ default/lazy branch: any win beats any draw, any
    /// draw beats any loss, and step counts do not break ties.
    LegacyWdl,
    /// Use the full database comparison: faster wins and slower losses are
    /// preferred, while draws remain tied.
    StrictSteps,
}

impl PerfectMoveOrdering {
    pub fn compare(self, candidate: PerfectOutcome, incumbent: PerfectOutcome) -> Ordering {
        match self {
            Self::LegacyWdl => candidate.default_rank().cmp(&incumbent.default_rank()),
            Self::StrictSteps => candidate.strict_cmp(incumbent),
        }
    }

    fn is_better(self, candidate: PerfectOutcome, incumbent: PerfectOutcome) -> bool {
        self.compare(candidate, incumbent).is_gt()
    }
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
    best_move_choice_with_ordering(
        database,
        rules,
        snap,
        options,
        PerfectMoveOrdering::LegacyWdl,
    )
}

/// Select every legal action tied for the best database outcome.
pub fn best_move_choices_with_database<P: DatabaseProvider>(
    database: &mut Database<P>,
    rules: &MillRules,
    snap: &GameStateSnapshot,
    options: &MillVariantOptions,
) -> Result<Option<Vec<PerfectMoveChoice>>, DatabaseError> {
    best_move_choices_with_ordering(
        database,
        rules,
        snap,
        options,
        PerfectMoveOrdering::LegacyWdl,
    )
}

/// Select a deterministic best legal action using the requested database
/// comparison policy.
pub fn best_move_choice_with_ordering<P: DatabaseProvider>(
    database: &mut Database<P>,
    rules: &MillRules,
    snap: &GameStateSnapshot,
    options: &MillVariantOptions,
    ordering: PerfectMoveOrdering,
) -> Result<Option<PerfectMoveChoice>, DatabaseError> {
    Ok(
        best_move_choices_with_ordering(database, rules, snap, options, ordering)?
            .and_then(|choices| choices.into_iter().next()),
    )
}

/// Select every legal action tied for the best database outcome under the
/// requested comparison policy.
pub fn best_move_choices_with_ordering<P: DatabaseProvider>(
    database: &mut Database<P>,
    rules: &MillRules,
    snap: &GameStateSnapshot,
    options: &MillVariantOptions,
    ordering: PerfectMoveOrdering,
) -> Result<Option<Vec<PerfectMoveChoice>>, DatabaseError> {
    let root_side = snap.side_to_move;
    if !database_matches_options(database, options) {
        return Ok(None);
    }
    if root_side != 0 && root_side != 1 {
        return Ok(None);
    }

    let mut actions = ActionList::<256>::new();
    rules.legal_actions(snap, &mut actions);

    let mut best_outcome: Option<PerfectOutcome> = None;
    let mut best_choices = Vec::new();
    for &action in actions.as_slice() {
        let child_snap = rules.apply(snap, action);
        let outcome = match child_outcome_for_root(
            database,
            rules,
            &child_snap,
            options,
            root_side,
            ordering,
        )? {
            Some(outcome) => outcome,
            None => return Ok(None),
        };
        match best_outcome {
            None => {
                best_outcome = Some(outcome);
                best_choices.push(PerfectMoveChoice {
                    token: MillUciCodec::encode_action(action),
                    outcome,
                });
            }
            Some(incumbent) => match ordering.compare(outcome, incumbent) {
                Ordering::Greater => {
                    best_outcome = Some(outcome);
                    best_choices.clear();
                    best_choices.push(PerfectMoveChoice {
                        token: MillUciCodec::encode_action(action),
                        outcome,
                    });
                }
                Ordering::Equal => best_choices.push(PerfectMoveChoice {
                    token: MillUciCodec::encode_action(action),
                    outcome,
                }),
                Ordering::Less => {}
            },
        }
    }

    if best_choices.is_empty() {
        Ok(None)
    } else {
        Ok(Some(best_choices))
    }
}

pub fn best_move_choice_for_query_with_database<P: DatabaseProvider>(
    database: &mut Database<P>,
    rules: &MillRules,
    options: &MillVariantOptions,
    query: PerfectQuery,
) -> Result<Option<PerfectMoveChoice>, DatabaseError> {
    best_move_choice_for_query_with_ordering(
        database,
        rules,
        options,
        query,
        PerfectMoveOrdering::LegacyWdl,
    )
}

pub fn best_move_choice_for_query_with_ordering<P: DatabaseProvider>(
    database: &mut Database<P>,
    rules: &MillRules,
    options: &MillVariantOptions,
    query: PerfectQuery,
    ordering: PerfectMoveOrdering,
) -> Result<Option<PerfectMoveChoice>, DatabaseError> {
    let snap = snapshot_from_perfect_query(rules, options, query);
    best_move_choice_with_ordering(database, rules, &snap, options, ordering)
}

pub fn best_move_token_with_database<P: DatabaseProvider>(
    database: &mut Database<P>,
    rules: &MillRules,
    snap: &GameStateSnapshot,
    options: &MillVariantOptions,
) -> Result<Option<String>, DatabaseError> {
    Ok(best_move_choice_with_database(database, rules, snap, options)?.map(|choice| choice.token))
}

pub fn best_move_token_with_ordering<P: DatabaseProvider>(
    database: &mut Database<P>,
    rules: &MillRules,
    snap: &GameStateSnapshot,
    options: &MillVariantOptions,
    ordering: PerfectMoveOrdering,
) -> Result<Option<String>, DatabaseError> {
    Ok(
        best_move_choice_with_ordering(database, rules, snap, options, ordering)?
            .map(|choice| choice.token),
    )
}

/// Every legal action's database outcome from the root side's perspective, in
/// legal-action order (same order as [`GameRules::legal_actions`] would
/// produce for `snap`).
///
/// Unlike [`best_move_choices_with_ordering`], which only returns the moves
/// tied for the single best outcome, this returns *every* legal move's
/// outcome — wins, draws, and losses alike. Puzzle generation uses this to
/// classify how many legal replies keep a forced win alive (a low count
/// makes for a sharper, more instructive puzzle) and to distinguish "the"
/// winning move from moves that merely draw or lose.
///
/// Returns `None` under the same conditions as
/// [`best_move_choices_with_ordering`]: the database variant does not match
/// `options`, the side to move is invalid, or any candidate line runs into a
/// position the database does not cover.
pub fn all_move_outcomes_with_ordering<P: DatabaseProvider>(
    database: &mut Database<P>,
    rules: &MillRules,
    snap: &GameStateSnapshot,
    options: &MillVariantOptions,
    ordering: PerfectMoveOrdering,
) -> Result<Option<Vec<PerfectMoveChoice>>, DatabaseError> {
    let root_side = snap.side_to_move;
    if !database_matches_options(database, options) {
        return Ok(None);
    }
    if root_side != 0 && root_side != 1 {
        return Ok(None);
    }

    let mut actions = ActionList::<256>::new();
    rules.legal_actions(snap, &mut actions);

    let mut results = Vec::with_capacity(actions.as_slice().len());
    for &action in actions.as_slice() {
        let child_snap = rules.apply(snap, action);
        let outcome = match child_outcome_for_root(
            database,
            rules,
            &child_snap,
            options,
            root_side,
            ordering,
        )? {
            Some(outcome) => outcome,
            None => return Ok(None),
        };
        results.push(PerfectMoveChoice {
            token: MillUciCodec::encode_action(action),
            outcome,
        });
    }

    Ok(Some(results))
}

fn child_outcome_for_root<P: DatabaseProvider>(
    database: &mut Database<P>,
    rules: &MillRules,
    child_snap: &GameStateSnapshot,
    options: &MillVariantOptions,
    root_side: i8,
    ordering: PerfectMoveOrdering,
) -> Result<Option<PerfectOutcome>, DatabaseError> {
    continuation_outcome_for_root(database, rules, child_snap, options, root_side, ordering, 0)
}

fn continuation_outcome_for_root<P: DatabaseProvider>(
    database: &mut Database<P>,
    rules: &MillRules,
    snap: &GameStateSnapshot,
    options: &MillVariantOptions,
    root_side: i8,
    ordering: PerfectMoveOrdering,
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
            let outcome = match continuation_outcome_for_root(
                database,
                rules,
                &next,
                options,
                root_side,
                ordering,
                depth + 1,
            )? {
                Some(outcome) => outcome,
                None => return Ok(None),
            };
            if best.is_none_or(|best_outcome| ordering.is_better(outcome, best_outcome)) {
                best = Some(outcome);
            }
        }
        return Ok(best);
    }

    let outcome =
        match evaluate_state_outcome_with_database(database, &state, options, side_to_move) {
            Ok(Some(outcome)) => outcome,
            Ok(None) => return Ok(None),
            Err(err) if err.is_missing_asset() => return Ok(None),
            Err(err) => return Err(err),
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
    use crate::database::{DatabaseOptions, FileDatabaseProvider};
    use crate::wdl_plane::WdlPlaneCache;

    fn asset_root() -> std::path::PathBuf {
        std::path::Path::new(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../src/ui/flutter_app/assets/databases"
        ))
        .to_path_buf()
    }

    /// Play forward from the initial position, greedily preferring a
    /// mill-forming action, until we reach a genuine mid-removal state
    /// (`pending_removals[side_to_move] > 0`). Used to exercise
    /// [`mid_removal_key`] / [`canonical_key`] against a real reachable
    /// position instead of a hand-constructed one.
    fn find_mid_removal_state(rules: &MillRules, _options: &MillVariantOptions) -> MillState {
        let mut snap = rules.initial_state(&[]);
        for _ in 0..40 {
            let state = MillRules::decode_snapshot(snap);
            let side = state.side_to_move();
            if side >= 0 && state.pending_removals()[side as usize] > 0 {
                return state;
            }
            let mut actions = ActionList::<256>::new();
            rules.legal_actions(&snap, &mut actions);
            assert!(
                !actions.as_slice().is_empty(),
                "ran out of legal moves before a mill formed"
            );
            // Prefer whichever action creates a pending removal, else the
            // first legal action, to reach a mid-removal state quickly and
            // deterministically.
            let chosen = actions
                .as_slice()
                .iter()
                .copied()
                .find(|&a| {
                    let next = MillRules::decode_snapshot(rules.apply(&snap, a));
                    let s = next.side_to_move();
                    s >= 0 && next.pending_removals()[s as usize] > 0
                })
                .unwrap_or(actions.as_slice()[0]);
            snap = rules.apply(&snap, chosen);
        }
        panic!("did not reach a mid-removal state within 40 plies of greedy play");
    }

    /// End-to-end regression for the stabilizer canonicalization bug at
    /// the `canonical_key` level, using the real pair of positions the
    /// `mill arena` investigation surfaced: two FENs presenting the same
    /// abstract (4,3)-sector position (related by symmetry op 13 plus the
    /// mover/waiter color swap). Both the *parent* keys and the full
    /// per-move *child* key sets must coincide -- the child sets are what
    /// the old arbitrary-stabilizer fold silently broke (disjoint sets, so
    /// `PatchLookup::correct_action` could never match its recorded
    /// `best_child` from the other presentation).
    #[test]
    fn canonical_key_and_child_keys_are_presentation_invariant() {
        let options = MillVariantOptions::default();
        let rules = MillRules::new(options.clone());
        let provider = crate::database::FileDatabaseProvider::new(asset_root());
        let mut planes = WdlPlaneCache::new(provider, DatabaseVariant::STANDARD).unwrap();

        let fen_a = "OOO****@/@**@**@*/******** b m s 3 0 4 0 0 0 -1 -1 -1 -1 0 10 25 ids:nodes";
        let fen_b = "********/O**O**O*/****@@@O w m p 4 0 3 0 0 0 -1 -1 -1 -1 0 0 1 ids:nodes";

        let mut keysets = Vec::new();
        for fen in [fen_a, fen_b] {
            let state = rules.set_from_fen(fen).unwrap();
            let snap = rules.encode_state(state.clone());
            let parent = canonical_key(&mut planes, &state, &options).unwrap();

            let mut child_keys = std::collections::BTreeSet::new();
            let mut actions = ActionList::<256>::new();
            rules.legal_actions(&snap, &mut actions);
            for &action in actions.as_slice() {
                let child = MillRules::decode_snapshot(rules.apply(&snap, action));
                child_keys.insert(canonical_key(&mut planes, &child, &options).unwrap());
            }
            keysets.push((parent, child_keys));
        }

        assert_eq!(
            keysets[0].0, keysets[1].0,
            "symmetric presentations must share one parent canonical key"
        );
        assert_eq!(
            keysets[0].1, keysets[1].1,
            "symmetric presentations must produce identical child key sets"
        );
    }

    #[test]
    fn mid_removal_key_is_tagged_and_defined_only_for_valid_sides() {
        let options = MillVariantOptions::default();
        let rules = MillRules::new(options.clone());
        let state = find_mid_removal_state(&rules, &options);
        assert!(state.pending_removals()[state.side_to_move() as usize] > 0);

        let key = mid_removal_key(&state).expect("valid side must produce a key");
        assert_ne!(
            key & (1_u64 << 63),
            0,
            "mid-removal keys must always tag bit 63"
        );
    }

    #[test]
    fn mid_removal_key_is_invariant_under_board_symmetry() {
        let options = MillVariantOptions::default();
        let rules = MillRules::new(options.clone());
        let state = find_mid_removal_state(&rules, &options);
        let key = mid_removal_key(&state).unwrap();

        // Rotate the raw board through every symmetry op and rebuild an
        // equivalent state; every rotation must key identically.
        let (white_bits, black_bits) = bitboards_from_state(&state);
        let board = u64::from(white_bits) | (u64::from(black_bits) << 24);
        for op in 0_u8..16 {
            let transformed = crate::index::symmetry::transform48(op, board);
            let t_white = (transformed & 0x00ff_ffff) as u32;
            let t_black = ((transformed >> 24) & 0x00ff_ffff) as u32;
            let query = PerfectQuery::new(
                t_white,
                t_black,
                state.pieces_in_hand()[0],
                state.pieces_in_hand()[1],
                0,
                false,
            );
            let snap = snapshot_from_perfect_query(&rules, &options, query);
            let mut rotated = MillRules::decode_snapshot(snap);
            rotated.set_pending_removal(0, state.pending_removals()[0]);
            rotated.set_pending_removal(1, state.pending_removals()[1]);
            assert_eq!(
                mid_removal_key(&rotated),
                Some(key),
                "symmetry op {op} must not change the mid-removal key"
            );
        }
    }

    #[test]
    fn canonical_key_dispatches_to_mid_removal_key_only_when_pending() {
        let options = MillVariantOptions::default();
        let rules = MillRules::new(options.clone());
        let variant = DatabaseVariant::from_mill_options(&options).unwrap();
        let mut planes =
            WdlPlaneCache::new(FileDatabaseProvider::new(asset_root()), variant).unwrap();

        let mid_removal_state = find_mid_removal_state(&rules, &options);
        assert_eq!(
            canonical_key(&mut planes, &mid_removal_state, &options),
            mid_removal_key(&mid_removal_state)
        );

        let settled_snap = rules.initial_state(&[]);
        let settled_state = MillRules::decode_snapshot(settled_snap);
        let side = settled_state.side_to_move();
        let query = query_from_state(&settled_state, &options, side).unwrap();
        assert_eq!(
            canonical_key(&mut planes, &settled_state, &options),
            Some(planes.canonical_key_for_query(query))
        );
        // Settled keys must never collide with the mid-removal tag bit.
        assert_eq!(
            canonical_key(&mut planes, &settled_state, &options).unwrap() & (1 << 63),
            0
        );
    }

    #[test]
    fn all_move_outcomes_covers_every_legal_action_and_matches_best_choice() {
        let options = MillVariantOptions::default();
        let rules = MillRules::new(options.clone());
        let variant = DatabaseVariant::from_mill_options(&options).unwrap();
        let mut db = Database::open_variant_with_options(
            FileDatabaseProvider::new(asset_root()),
            variant,
            DatabaseOptions::with_sector_cache_capacity(8),
        )
        .expect("bundled Perfect DB assets must open");

        // `std_3_3_0_0.sec2` is bundled with the app, so a 3-vs-3 flying
        // position with both hands empty is guaranteed to be queryable.
        let query = PerfectQuery::new(0b0000_0111, 0b0011_1000_0000_0000_0000, 0, 0, 0, false);
        let snap = snapshot_from_perfect_query(&rules, &options, query);

        let Some(all_outcomes) = all_move_outcomes_with_ordering(
            &mut db,
            &rules,
            &snap,
            &options,
            PerfectMoveOrdering::StrictSteps,
        )
        .expect("database read must not fail") else {
            // The exact bitboard above may legitimately fall outside the
            // bundled subset on some builds; skip rather than assert a
            // brittle coverage guarantee about third-party asset files.
            return;
        };

        let mut legal = ActionList::<256>::new();
        rules.legal_actions(&snap, &mut legal);
        assert_eq!(
            all_outcomes.len(),
            legal.as_slice().len(),
            "every legal action must get exactly one outcome"
        );

        let best = best_move_choices_with_ordering(
            &mut db,
            &rules,
            &snap,
            &options,
            PerfectMoveOrdering::StrictSteps,
        )
        .expect("database read must not fail")
        .expect("bundled sector must resolve a best move for this position");

        let best_outcome_from_all = all_outcomes
            .iter()
            .filter(|choice| best.iter().any(|b| b.token == choice.token))
            .map(|choice| choice.outcome)
            .max_by(|a, b| PerfectMoveOrdering::StrictSteps.compare(*a, *b))
            .expect("best-move token must appear in the full enumeration");
        assert_eq!(
            best_outcome_from_all.wdl(),
            best[0].outcome.wdl(),
            "full enumeration must agree with best_move_choices on the winning WDL"
        );
    }

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

    #[test]
    fn perfect_move_ordering_preserves_legacy_and_strict_semantics() {
        assert_eq!(
            PerfectMoveOrdering::LegacyWdl.compare(
                PerfectOutcome::Win { steps: 1 },
                PerfectOutcome::Win { steps: 5 },
            ),
            Ordering::Equal,
            "legacy/lazy C++ mode treats all wins as tied"
        );
        assert_eq!(
            PerfectMoveOrdering::StrictSteps.compare(
                PerfectOutcome::Win { steps: 1 },
                PerfectOutcome::Win { steps: 5 },
            ),
            Ordering::Greater,
            "strict mode prefers faster wins"
        );
        assert_eq!(
            PerfectMoveOrdering::StrictSteps.compare(
                PerfectOutcome::Loss { steps: 5 },
                PerfectOutcome::Loss { steps: 2 },
            ),
            Ordering::Greater,
            "strict mode prefers slower losses"
        );
        assert_eq!(
            PerfectMoveOrdering::StrictSteps.compare(
                PerfectOutcome::Draw { steps: 1 },
                PerfectOutcome::Draw { steps: 9 },
            ),
            Ordering::Equal,
            "database draws remain tied"
        );
    }
}
