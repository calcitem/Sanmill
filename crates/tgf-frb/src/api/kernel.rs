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

use std::collections::HashMap;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::Arc;

use once_cell::sync::Lazy;
use std::sync::Mutex;

use tgf_core::{
    Action, ActionList, GameKernel, GameRules, GameStateSnapshot, KernelError, OutcomeKind,
};
use tgf_mill::{MillRules, MillVariantOptions as NativeMillVariantOptions};
use tgf_othello::OthelloRules;

use super::simple::MillVariantOptions;

// ---------------------------------------------------------------------------
// Session registry
// ---------------------------------------------------------------------------

static KERNELS: Lazy<Mutex<HashMap<u32, GameKernel>>> = Lazy::new(|| Mutex::new(HashMap::new()));
static NEXT_KERNEL_ID: AtomicU32 = AtomicU32::new(1);

fn insert_kernel(kernel: GameKernel) -> u32 {
    let id = NEXT_KERNEL_ID.fetch_add(1, Ordering::SeqCst);
    KERNELS
        .lock()
        .expect("kernel registry poisoned")
        .insert(id, kernel);
    id
}

/// Run `f` against the kernel with the given `handle`.  Returns
/// `KernelError::Internal("invalid handle")` when the registry no longer
/// contains the requested session (already disposed or never created).
fn with_kernel<R>(handle: u32, f: impl FnOnce(&mut GameKernel) -> R) -> Result<R, String> {
    let mut guard = KERNELS.lock().expect("kernel registry poisoned");
    let kernel = guard
        .get_mut(&handle)
        .ok_or_else(|| format!("invalid kernel handle: {handle}"))?;
    Ok(f(kernel))
}

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
    Ok(insert_kernel(kernel))
}

/// Create a Mill kernel with explicit variant options.  Use this once
/// the Flutter `RuleSettings` model is mapped through
/// `MillVariantOptionsMapper`.
#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_create_mill(variant: MillVariantOptions) -> Result<u32, String> {
    let native: NativeMillVariantOptions = variant.into();
    let rules: Arc<dyn GameRules> = Arc::new(MillRules::new(native));
    let kernel = GameKernel::new(rules, &[]);
    Ok(insert_kernel(kernel))
}

/// Drop the session associated with `handle`.  Idempotent: invoking
/// twice is a no-op.
#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_dispose(handle: u32) {
    KERNELS
        .lock()
        .expect("kernel registry poisoned")
        .remove(&handle);
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
    let mut guard = KERNELS.lock().expect("kernel registry poisoned");
    let kernel = guard
        .get_mut(&handle)
        .ok_or_else(|| format!("invalid kernel handle: {handle}"))?;
    let next = kernel
        .apply(action.into_action())
        .map_err(map_kernel_error)?;
    Ok(TgfSnapshot::from_snap(next))
}

#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_undo(handle: u32) -> Result<TgfSnapshot, String> {
    let mut guard = KERNELS.lock().expect("kernel registry poisoned");
    let kernel = guard
        .get_mut(&handle)
        .ok_or_else(|| format!("invalid kernel handle: {handle}"))?;
    let next = kernel.undo().map_err(map_kernel_error)?;
    Ok(TgfSnapshot::from_snap(next))
}

#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_redo(handle: u32) -> Result<TgfSnapshot, String> {
    let mut guard = KERNELS.lock().expect("kernel registry poisoned");
    let kernel = guard
        .get_mut(&handle)
        .ok_or_else(|| format!("invalid kernel handle: {handle}"))?;
    let next = kernel.redo().map_err(map_kernel_error)?;
    Ok(TgfSnapshot::from_snap(next))
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::simple::{CaptureRuleConfig, MillBoardFullAction};

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
    fn typed_create_mill_with_variant_options_round_trips() {
        let variant = MillVariantOptions {
            piece_count: 9,
            fly_piece_count: 3,
            pieces_at_least_count: 3,
            may_fly: true,
            has_diagonal_lines: false,
            may_remove_from_mills_always: false,
            may_remove_multiple: false,
            n_move_rule: 100,
            endgame_n_move_rule: 100,
            may_move_in_placing_phase: false,
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
        };
        let handle = tgf_kernel_create_mill(variant).unwrap();
        assert_eq!(tgf_kernel_legal_actions(handle).unwrap().len(), 24);
        tgf_kernel_dispose(handle);
    }
}
