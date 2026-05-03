// SPDX-License-Identifier: GPL-3.0-or-later
// Typed FRB session API backed by the Rust `tgf_core::GameKernel`.
//
// Each `tgf_kernel_create_*` call inserts a fresh kernel into a global
// session registry and returns a numeric handle that the Dart side can
// pass into subsequent `tgf_kernel_*` calls.  Using an integer handle
// instead of an FRB opaque type keeps the bridge generation simple and
// gives Dart the same ergonomics as the existing legacy kernel API
// (`legacy_kernel_*`) — which `MillRulesPort` already wraps.
//
// Concurrency: the registry is wrapped in a `Mutex` so multiple Dart
// isolates / FFI threads can hold sessions at the same time.  Each
// individual function takes the lock only for the duration of one call,
// so there is no risk of long-held mutexes blocking the Flutter UI.

use std::sync::Arc;

use tgf_core::{
    Action, ActionList, GameKernel, GameRules, GameStateSnapshot, KernelError, OutcomeKind,
};
use tgf_mill::{MillPhase, MillRules, MillVariantOptions as NativeMillVariantOptions};
use tgf_othello::OthelloRules;

use super::simple::{
    spawn_kernel_search_error, spawn_mill_engine_config_event_stream, spawn_mill_pvs_event_stream,
    EngineEvent, MillEngineConfig, MillVariantOptions,
};
use crate::frb_generated::StreamSink;
use crate::games::mill::variant_extras;
use crate::session_registry::{insert_kernel, remove_kernel, with_kernel};

// ---------------------------------------------------------------------------
// FRB DTOs
// ---------------------------------------------------------------------------

/// Mirror of `tgf_core::Action` with i32 fields so FRB can ship it as
/// trivial dart `int` types.  Conversion is `From`-symmetric.
#[derive(Clone, Debug)]
pub struct TgfAction {
    pub kind_tag: i32,
    pub from_node: i32,
    pub to_node: i32,
    pub aux: i32,
    pub payload_bits: u64,
}

impl TgfAction {
    fn into_action(self) -> Action {
        Action {
            kind_tag: self.kind_tag as i16,
            from_node: self.from_node as i16,
            to_node: self.to_node as i16,
            aux: self.aux as i16,
            payload_bits: self.payload_bits,
        }
    }

    fn from_action(a: Action) -> Self {
        Self {
            kind_tag: a.kind_tag as i32,
            from_node: a.from_node as i32,
            to_node: a.to_node as i32,
            aux: a.aux as i32,
            payload_bits: a.payload_bits,
        }
    }
}

/// FRB-friendly mirror of `GameStateSnapshot`.  The opaque payload is
/// emitted as a `Vec<u8>` (Dart `Uint8List`) so the Flutter side can
/// inspect game-specific blobs without knowing the C `[u8; 256]` layout.
#[derive(Clone, Debug)]
pub struct TgfSnapshot {
    pub side_to_move: i32,
    pub phase_tag: i32,
    pub move_number: i32,
    pub zobrist_key: u64,
    pub opaque_payload: Vec<u8>,
}

impl TgfSnapshot {
    fn from_snap(snap: GameStateSnapshot) -> Self {
        Self {
            side_to_move: snap.side_to_move as i32,
            phase_tag: snap.phase_tag as i32,
            move_number: snap.move_number as i32,
            zobrist_key: snap.zobrist_key,
            opaque_payload: snap.opaque_payload.to_vec(),
        }
    }
}

/// FRB-friendly outcome.  The framework deliberately returns string
/// kind/reason tokens instead of an enum so the Dart side can map them
/// to localized strings without needing an FRB sealed class.
#[derive(Clone, Debug)]
pub struct TgfOutcome {
    /// One of "ongoing", "win", "draw", "abandoned".
    pub kind: String,
    /// Winner index when `kind == "win"`; -1 otherwise.
    pub winner: i32,
    /// Stable English token, e.g. "loseFewerThanThree".
    pub reason: String,
}

impl TgfOutcome {
    fn from_outcome(o: tgf_core::Outcome) -> Self {
        let (kind, winner) = match o.kind {
            OutcomeKind::Ongoing => ("ongoing", -1),
            OutcomeKind::Win(w) => ("win", w as i32),
            OutcomeKind::Draw => ("draw", -1),
            OutcomeKind::Abandoned => ("abandoned", -1),
        };
        Self {
            kind: kind.to_owned(),
            winner,
            reason: o.reason,
        }
    }
}

fn map_kernel_error(err: KernelError) -> String {
    err.to_string()
}

// ---------------------------------------------------------------------------
// Game registry — extend this when wiring in a new game crate
// ---------------------------------------------------------------------------

fn build_rules_default(game_id: &str) -> Result<Arc<dyn GameRules>, String> {
    match game_id {
        "mill" => Ok(Arc::new(MillRules::default())),
        "othello" => Ok(Arc::new(OthelloRules::default())),
        other => Err(format!("unknown game id: {other}")),
    }
}

// ---------------------------------------------------------------------------
// Public FRB surface
// ---------------------------------------------------------------------------

/// Create a kernel for one of the built-in games using its default
/// variant options (`mill` ⇒ Nine Men's Morris, `othello` ⇒ standard
/// 8x8).  Returns the new session handle on success.
#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_create(game_id: String) -> Result<u32, String> {
    let rules = build_rules_default(&game_id)?;
    let kernel = GameKernel::new(rules, &[]);
    let id = insert_kernel(kernel);
    if game_id == "mill" {
        variant_extras::attach(id, NativeMillVariantOptions::default());
    }
    Ok(id)
}

/// Create a Mill kernel with explicit variant options.  Use this once
/// the Flutter `RuleSettings` model is mapped through
/// `MillVariantOptionsMapper`.
#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_create_mill(variant: MillVariantOptions) -> Result<u32, String> {
    let native: NativeMillVariantOptions = variant.into();
    let rules: Arc<dyn GameRules> = Arc::new(MillRules::new(native.clone()));
    let kernel = GameKernel::new(rules, &[]);
    let id = insert_kernel(kernel);
    variant_extras::attach(id, native);
    Ok(id)
}

/// Drop the session associated with `handle`.  Idempotent: invoking
/// twice is a no-op.
#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_dispose(handle: u32) {
    remove_kernel(handle);
}

#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_game_id(handle: u32) -> Result<String, String> {
    with_kernel(handle, |k| k.game_id().to_owned())
}

#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_snapshot(handle: u32) -> Result<TgfSnapshot, String> {
    with_kernel(handle, |k| TgfSnapshot::from_snap(k.snapshot()))
}

#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_legal_actions(handle: u32) -> Result<Vec<TgfAction>, String> {
    with_kernel(handle, |k| {
        // Use the kernel's `Vec<Action>` accessor; we re-pack into the
        // FRB DTO instead of an `ActionList` because the Dart side wants
        // an owned, dynamically sized list.
        let _ = ActionList::<256>::new(); // silence "unused import" lints
        k.legal_actions()
            .into_iter()
            .map(TgfAction::from_action)
            .collect()
    })
}

#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_apply(handle: u32, action: TgfAction) -> Result<TgfSnapshot, String> {
    // NOTE: intentional deviation from master src/position.cpp:do_move.
    // master assumes the move is legal and mutates directly.  The public FRB
    // entry point remains checked for UI safety; replay/debug callers that
    // need master-equivalent unchecked application must use
    // `tgf_kernel_apply_unchecked`.
    with_kernel(handle, |kernel| {
        kernel
            .apply(action.into_action())
            .map(TgfSnapshot::from_snap)
            .map_err(map_kernel_error)
    })?
}

#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_apply_unchecked(handle: u32, action: TgfAction) -> Result<TgfSnapshot, String> {
    with_kernel(handle, |kernel| {
        TgfSnapshot::from_snap(kernel.apply_unchecked(action.into_action()))
    })
}

#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_undo(handle: u32) -> Result<TgfSnapshot, String> {
    with_kernel(handle, |kernel| {
        kernel
            .undo()
            .map(TgfSnapshot::from_snap)
            .map_err(map_kernel_error)
    })?
}

#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_redo(handle: u32) -> Result<TgfSnapshot, String> {
    with_kernel(handle, |kernel| {
        kernel
            .redo()
            .map(TgfSnapshot::from_snap)
            .map_err(map_kernel_error)
    })?
}

#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_outcome(handle: u32) -> Result<TgfOutcome, String> {
    with_kernel(handle, |k| TgfOutcome::from_outcome(k.outcome()))
}

#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_is_terminal(handle: u32) -> Result<bool, String> {
    with_kernel(handle, |k| k.is_terminal())
}

#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_undo_depth(handle: u32) -> Result<u32, String> {
    with_kernel(handle, |k| k.undo_depth() as u32)
}

#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_redo_depth(handle: u32) -> Result<u32, String> {
    with_kernel(handle, |k| k.redo_depth() as u32)
}

/// PVS search over the kernel's **current** Mill position, using the same
/// variant options as [tgf_kernel_create_mill].
///
/// Streams the same [EngineEvent] sequence as [crate::api::simple::native_mill_search_events]:
/// one `info` event per IDS depth, then `bestMove` + `stopped`.
pub fn tgf_kernel_mill_search_events(handle: u32, depth: i32, sink: StreamSink<EngineEvent>) {
    let game_id = match with_kernel(handle, |k| k.game_id().to_owned()) {
        Ok(id) => id,
        Err(e) => {
            spawn_kernel_search_error(e, sink);
            return;
        }
    };
    if game_id != "mill" {
        spawn_kernel_search_error(format!("kernel game_id is {game_id}, expected mill"), sink);
        return;
    }

    let snapshot = match with_kernel(handle, |k| k.snapshot()) {
        Ok(s) => s,
        Err(e) => {
            spawn_kernel_search_error(e, sink);
            return;
        }
    };

    let options = variant_extras::options_for(handle);
    spawn_mill_pvs_event_stream(snapshot, options, depth, sink);
}

/// Full-config search over the kernel's **current** Mill position.
///
/// Accepts a [`MillEngineConfig`] that controls algorithm, depth, time limit
/// and lazy-search behaviour.  Preferred over [tgf_kernel_mill_search_events]
/// for production use once the Flutter side has migrated to the typed config.
pub fn tgf_kernel_mill_search_events_with_config(
    handle: u32,
    config: MillEngineConfig,
    sink: StreamSink<EngineEvent>,
) {
    let game_id = match with_kernel(handle, |k| k.game_id().to_owned()) {
        Ok(id) => id,
        Err(e) => {
            spawn_kernel_search_error(e, sink);
            return;
        }
    };
    if game_id != "mill" {
        spawn_kernel_search_error(format!("kernel game_id is {game_id}, expected mill"), sink);
        return;
    }
    let snapshot = match with_kernel(handle, |k| k.snapshot()) {
        Ok(s) => s,
        Err(e) => {
            spawn_kernel_search_error(e, sink);
            return;
        }
    };
    let options = variant_extras::options_for(handle);
    spawn_mill_engine_config_event_stream(snapshot, options, config, sink);
}

// ---------------------------------------------------------------------------
// Setup-position editing API (Phase 6.A.1)
//
// Design note: the legacy C++/Dart Position::action tri-state (place / select
// / remove) is intentionally absent here.  The native board editor cycles the
// owner value on each tap via setup_set_piece(node, owner) — one call covers
// all edit intents.  A tgf_kernel_setup_set_action function is not needed and
// is not planned (see docs/FRAMEWORK_API.md §"Setup-position editing API").
// ---------------------------------------------------------------------------

/// Clear the board associated with a Mill kernel handle and reset all pieces,
/// returning the fresh empty snapshot.  History and redo stacks are cleared.
///
/// This is the entry point for the Flutter setup-position flow: call
/// `tgf_kernel_setup_clear` first, then `tgf_kernel_setup_set_piece` for each
/// piece, then `tgf_kernel_setup_finish` to transition to a playable state.
#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_setup_clear(handle: u32) -> Result<TgfSnapshot, String> {
    let options = variant_extras::options_for(handle);
    with_kernel(handle, |kernel| {
        if kernel.game_id() != "mill" {
            return Err("setup is only supported for Mill kernels".to_owned());
        }
        let rules = MillRules::new(options.clone());
        let empty_state = rules.setup_empty();
        let snapshot = rules.encode_state(empty_state);
        kernel.replace_state(snapshot);
        Ok(TgfSnapshot::from_snap(kernel.snapshot()))
    })?
}

/// Set or clear a single piece at `node` for a Mill kernel in setup mode.
///
/// `owner`: `1` = first player (White), `2` = second player (Black),
/// any other value = clear the square.
///
/// Call `tgf_kernel_setup_clear` before the first `set_piece` to start with
/// a blank board, then `tgf_kernel_setup_finish` when editing is complete.
#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_setup_set_piece(
    handle: u32,
    node: i32,
    owner: i32,
) -> Result<TgfSnapshot, String> {
    if !(0..24).contains(&node) {
        return Err(format!(
            "setup_set_piece node out of range: {node}; expected Rust node 0..23"
        ));
    }
    let options = variant_extras::options_for(handle);
    with_kernel(handle, |kernel| {
        if kernel.game_id() != "mill" {
            return Err("setup is only supported for Mill kernels".to_owned());
        }
        let rules = MillRules::new(options.clone());
        let mut state = tgf_mill::MillRules::decode_snapshot(kernel.snapshot());
        state.set_piece(node as u16, owner as i8);
        state.recompute_aux(&options);
        let new_snap = rules.encode_state(state);
        kernel.replace_state(new_snap);
        Ok(TgfSnapshot::from_snap(new_snap))
    })?
}

/// Set the side to move for a Mill kernel in setup mode.
///
/// `side`: `0` = first player (White), `1` = second player (Black).
#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_setup_set_side(handle: u32, side: i32) -> Result<TgfSnapshot, String> {
    let options = variant_extras::options_for(handle);
    with_kernel(handle, |kernel| {
        if kernel.game_id() != "mill" {
            return Err("setup is only supported for Mill kernels".to_owned());
        }
        let rules = MillRules::new(options.clone());
        let mut state = tgf_mill::MillRules::decode_snapshot(kernel.snapshot());
        state.set_side_to_move(side.clamp(0, 1) as i8);
        let new_snap = rules.encode_state(state);
        kernel.replace_state(new_snap);
        Ok(TgfSnapshot::from_snap(new_snap))
    })?
}

/// Finish the setup-position editing flow.
///
/// Determines whether the resulting board is in placing or moving phase
/// based on whether any pieces remain in hand, recomputes auxiliary fields,
/// and replaces the kernel state.  After this call the kernel can be used
/// for normal play (legal actions, apply, search).
#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_setup_finish(handle: u32) -> Result<TgfSnapshot, String> {
    let options = variant_extras::options_for(handle);
    with_kernel(handle, |kernel| {
        if kernel.game_id() != "mill" {
            return Err("setup is only supported for Mill kernels".to_owned());
        }
        let rules = MillRules::new(options.clone());
        let mut state = tgf_mill::MillRules::decode_snapshot(kernel.snapshot());
        state.recompute_aux(&options);
        // Determine phase: placing if either side still has pieces in
        // hand, moving otherwise — but check for an immediate GameOver
        // when either side would have fewer than pieces_at_least_count
        // pieces on board (mirrors C++ `check_if_game_is_over` at
        // position-setup boundaries).
        if state.pieces_in_hand[0] > 0 || state.pieces_in_hand[1] > 0 {
            state.set_phase(MillPhase::Placing);
        } else if let Some(winner) = state.check_pieces_at_least(&options) {
            state.set_phase(MillPhase::GameOver);
            state.set_winner(winner);
            state.set_outcome_reason_fewer_than_threshold();
        } else {
            state.set_phase(MillPhase::Moving);
        }
        let new_snap = rules.encode_state(state);
        kernel.replace_state(new_snap);
        Ok(TgfSnapshot::from_snap(new_snap))
    })?
}

/// Load a Mill board position from a FEN string (Phase 6.A.3.B).
///
/// The FEN must follow the legacy Dart/C++ engine format.  Returns the
/// new snapshot on success, or an error string on parse failure.
#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_set_from_fen(handle: u32, fen: String) -> Result<TgfSnapshot, String> {
    let options = variant_extras::options_for(handle);
    with_kernel(handle, |kernel| {
        if kernel.game_id() != "mill" {
            return Err("set_from_fen is only supported for Mill kernels".to_owned());
        }
        let rules = MillRules::new(options);
        let state = rules.set_from_fen(&fen)?;
        let new_snap = rules.encode_state(state);
        kernel.replace_state(new_snap);
        Ok(TgfSnapshot::from_snap(new_snap))
    })?
}

/// Export the current Mill kernel state as a FEN string (Phase 6.A.3.B).
#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_export_fen(handle: u32) -> Result<String, String> {
    let options = variant_extras::options_for(handle);
    with_kernel(handle, |kernel| {
        if kernel.game_id() != "mill" {
            return Err("export_fen is only supported for Mill kernels".to_owned());
        }
        let rules = MillRules::new(options);
        let state = tgf_mill::MillRules::decode_snapshot(kernel.snapshot());
        Ok(rules.export_fen(&state))
    })?
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::simple::{
        CaptureRuleConfig, MillBoardFullAction, MillFormationActionInPlacingPhase, StalemateAction,
    };

    #[test]
    fn mill_kernel_session_round_trip() {
        let handle = tgf_kernel_create("mill".to_owned()).unwrap();
        let snap = tgf_kernel_snapshot(handle).unwrap();
        assert_eq!(snap.side_to_move, 0);
        assert_eq!(snap.move_number, 0);

        let legal = tgf_kernel_legal_actions(handle).unwrap();
        assert_eq!(legal.len(), 24);

        let after_apply = tgf_kernel_apply(handle, legal[0].clone()).unwrap();
        assert_ne!(after_apply.opaque_payload[..24], snap.opaque_payload[..24]);
        assert_eq!(tgf_kernel_undo_depth(handle).unwrap(), 1);

        let undone = tgf_kernel_undo(handle).unwrap();
        assert_eq!(undone.opaque_payload, snap.opaque_payload);
        assert_eq!(tgf_kernel_redo_depth(handle).unwrap(), 1);

        let redone = tgf_kernel_redo(handle).unwrap();
        assert_eq!(redone.opaque_payload, after_apply.opaque_payload);

        tgf_kernel_dispose(handle);
        assert!(tgf_kernel_snapshot(handle).is_err());
    }

    #[test]
    fn othello_kernel_session_works_too() {
        let handle = tgf_kernel_create("othello".to_owned()).unwrap();
        assert_eq!(tgf_kernel_game_id(handle).unwrap(), "othello");
        assert_eq!(tgf_kernel_legal_actions(handle).unwrap().len(), 4);
        tgf_kernel_dispose(handle);
    }

    #[test]
    fn unknown_game_id_returns_error_string() {
        let err = tgf_kernel_create("checkers".to_owned()).unwrap_err();
        assert!(err.contains("unknown game id"));
    }

    #[test]
    fn illegal_action_surfaces_kernel_error_string() {
        let handle = tgf_kernel_create("mill".to_owned()).unwrap();
        let bogus = TgfAction {
            kind_tag: 0,
            from_node: -1,
            to_node: 99,
            aux: -1,
            payload_bits: 0,
        };
        let err = tgf_kernel_apply(handle, bogus).unwrap_err();
        assert!(err.contains("illegal"));
        tgf_kernel_dispose(handle);
    }

    #[test]
    fn unchecked_apply_bypasses_legality_validation() {
        let handle = tgf_kernel_create("mill".to_owned()).unwrap();
        let bogus = TgfAction {
            kind_tag: 0,
            from_node: -1,
            to_node: 99,
            aux: -1,
            payload_bits: 0,
        };

        assert!(tgf_kernel_apply(handle, bogus.clone()).is_err());
        let _ = tgf_kernel_apply_unchecked(handle, bogus);
        tgf_kernel_dispose(handle);
    }

    #[test]
    fn setup_set_piece_rejects_out_of_range_node() {
        let handle = tgf_kernel_create("mill".to_owned()).unwrap();

        let err = tgf_kernel_setup_set_piece(handle, 31, 1).unwrap_err();
        assert!(
            err.contains("node out of range"),
            "legacy square ids must not be silently clamped: {err}"
        );

        let err = tgf_kernel_setup_set_piece(handle, -1, 1).unwrap_err();
        assert!(err.contains("node out of range"));

        tgf_kernel_dispose(handle);
    }

    #[test]
    fn typed_create_mill_with_variant_options_round_trips() {
        let variant = MillVariantOptions {
            piece_count: 9,
            fly_piece_count: 3,
            pieces_at_least_count: 3,
            may_fly: true,
            has_diagonal_lines: false,
            mill_formation_action_in_placing_phase:
                MillFormationActionInPlacingPhase::RemoveOpponentsPieceFromBoard,
            may_remove_from_mills_always: false,
            may_remove_multiple: false,
            n_move_rule: 100,
            endgame_n_move_rule: 100,
            may_move_in_placing_phase: false,
            is_defender_move_first: false,
            restrict_repeated_mills_formation: false,
            one_time_use_mill: false,
            stop_placing_when_two_empty_squares: false,
            board_full_action: MillBoardFullAction::FirstPlayerLose,
            threefold_repetition_rule: true,
            custodian_capture: CaptureRuleConfig {
                enabled: false,
                on_square_edges: true,
                on_cross_lines: true,
                on_diagonal_lines: true,
                in_placing_phase: true,
                in_moving_phase: true,
                only_available_when_own_pieces_leq3: false,
            },
            intervention_capture: CaptureRuleConfig {
                enabled: false,
                on_square_edges: true,
                on_cross_lines: true,
                on_diagonal_lines: true,
                in_placing_phase: true,
                in_moving_phase: true,
                only_available_when_own_pieces_leq3: false,
            },
            leap_capture: CaptureRuleConfig {
                enabled: false,
                on_square_edges: true,
                on_cross_lines: true,
                on_diagonal_lines: true,
                in_placing_phase: true,
                in_moving_phase: true,
                only_available_when_own_pieces_leq3: false,
            },
            stalemate_action: StalemateAction::EndWithStalemateLoss,
            consider_mobility: true,
            focus_on_blocking_paths: false,
        };
        let handle = tgf_kernel_create_mill(variant).unwrap();
        assert_eq!(tgf_kernel_legal_actions(handle).unwrap().len(), 24);
        tgf_kernel_dispose(handle);
    }
}
