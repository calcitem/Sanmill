// SPDX-License-Identifier: GPL-3.0-or-later
// tgf-frb – Phase 1 API surface.
//
// Conventions:
//   - `#[flutter_rust_bridge::frb(sync)]` makes the call synchronous on the
//     Dart side (no Future wrapping); use only for cheap, non-blocking calls.
//   - All public functions in this module are auto-exported to Dart by codegen.

use once_cell::sync::Lazy;
use std::sync::Mutex;
use tgf_core::{Action, ActionList, BoardTopology, GameRules};
use tgf_legacy_cxx::LegacyKernel;
use tgf_mill::{default_mill_topology, MillActionKind, MillRules};

static LEGACY_KERNEL: Lazy<Mutex<Option<LegacyKernel>>> =
    Lazy::new(|| Mutex::new(None));

/// FRB required initialisation.  Called once at Flutter app startup before
/// any other TGF function.  Do not remove.
#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

// ---------------------------------------------------------------------------
// Phase 1 smoke-check
// ---------------------------------------------------------------------------

/// Returns a greeting string confirming that the Rust → Dart bridge works.
/// Called from Dart as `tgfHelloWorld()` after `await RustLib.init()`.
#[flutter_rust_bridge::frb(sync)]
pub fn tgf_hello_world() -> String {
    format!(
        "hello from TGF (TabletopGameFramework) v{}",
        env!("CARGO_PKG_VERSION")
    )
}

/// Returns the TGF Rust crate version string.
#[flutter_rust_bridge::frb(sync)]
pub fn tgf_version() -> String {
    env!("CARGO_PKG_VERSION").to_owned()
}

// ---------------------------------------------------------------------------
// Phase 2 temporary kernel API: Rust → cxx → mature C++ engine.
// ---------------------------------------------------------------------------

/// Create/reset a global legacy C++ kernel.
///
/// This is intentionally a temporary singleton for Phase 2.  Phase 3+ replaces
/// it with real per-session handles once the Rust GameKernel is introduced.
#[flutter_rust_bridge::frb(sync)]
pub fn legacy_kernel_reset(rule_idx: i32) -> String {
    let mut guard = LEGACY_KERNEL.lock().expect("legacy kernel mutex poisoned");
    let kernel = LegacyKernel::new(rule_idx);
    let fen = kernel.fen();
    *guard = Some(kernel);
    fen
}

/// Current legacy C++ FEN string.
#[flutter_rust_bridge::frb(sync)]
pub fn legacy_kernel_fen() -> String {
    let guard = LEGACY_KERNEL.lock().expect("legacy kernel mutex poisoned");
    guard.as_ref().map(LegacyKernel::fen).unwrap_or_default()
}

/// Current legal actions in UCI notation.
#[flutter_rust_bridge::frb(sync)]
pub fn legacy_kernel_legal_actions() -> Vec<String> {
    let guard = LEGACY_KERNEL.lock().expect("legacy kernel mutex poisoned");
    guard
        .as_ref()
        .map(LegacyKernel::legal_actions)
        .unwrap_or_default()
}

/// Apply one UCI action (`d7`, `d7-g7`, `xa1`, ...).
#[flutter_rust_bridge::frb(sync)]
pub fn legacy_kernel_apply_uci(move_uci: String) -> bool {
    let mut guard = LEGACY_KERNEL.lock().expect("legacy kernel mutex poisoned");
    match guard.as_mut() {
        Some(kernel) => kernel.apply_uci(&move_uci),
        None => false,
    }
}

/// Raw C++ Phase enum tag.
#[flutter_rust_bridge::frb(sync)]
pub fn legacy_kernel_phase_tag() -> i32 {
    let guard = LEGACY_KERNEL.lock().expect("legacy kernel mutex poisoned");
    guard.as_ref().map(LegacyKernel::phase_tag).unwrap_or_default()
}

/// Raw C++ Color enum tag for side to move.
#[flutter_rust_bridge::frb(sync)]
pub fn legacy_kernel_side_to_move() -> i32 {
    let guard = LEGACY_KERNEL.lock().expect("legacy kernel mutex poisoned");
    guard
        .as_ref()
        .map(LegacyKernel::side_to_move)
        .unwrap_or_default()
}

// ---------------------------------------------------------------------------
// Phase 3 topology API: Rust-native Mill topology exposed through FRB.
// ---------------------------------------------------------------------------

#[derive(Clone, Debug)]
pub struct TopologyPoint {
    pub id: u16,
    pub square: u16,
    pub label: String,
    pub x: f32,
    pub y: f32,
}

#[derive(Clone, Debug)]
pub struct TopologyEdge {
    pub a: u16,
    pub b: u16,
}

#[derive(Clone, Debug)]
pub struct TopologyBlob {
    pub name: String,
    pub points: Vec<TopologyPoint>,
    pub edges: Vec<TopologyEdge>,
    pub line_groups: Vec<Vec<u16>>,
}

/// Return the Rust-native standard 24-point Mill topology.
///
/// This is the Phase 3 single source of truth for board geometry.  The Dart
/// shell converts this blob into its existing BoardGeometry value object.
#[flutter_rust_bridge::frb(sync)]
pub fn kernel_topology() -> TopologyBlob {
    let topo = default_mill_topology();
    let points = topo
        .nodes()
        .iter()
        .map(|node| TopologyPoint {
            id: node.id,
            square: node.square,
            label: node.label.to_owned(),
            x: node.point.x,
            y: node.point.y,
        })
        .collect();
    let edges = topo
        .edges()
        .iter()
        .map(|edge| TopologyEdge {
            a: edge.a,
            b: edge.b,
        })
        .collect();
    TopologyBlob {
        name: topo.name().to_owned(),
        points,
        edges,
        line_groups: topo.line_groups().to_vec(),
    }
}

// ---------------------------------------------------------------------------
// Phase 4 native Rust Mill rules scaffold API.
// ---------------------------------------------------------------------------

/// Number of legal actions from a fresh Rust-native Mill initial position.
/// This should match the mature C++ engine at depth 1: 24 placing moves.
#[flutter_rust_bridge::frb(sync)]
pub fn native_mill_initial_legal_count() -> u32 {
    let rules = MillRules::default();
    let snap = rules.initial_state(&[]);
    let mut actions = ActionList::<256>::new();
    rules.legal_actions(&snap, &mut actions);
    actions.len() as u32
}

/// Apply the first Rust-native place action and return the side-to-move tag.
/// This is a small typed smoke-check for the native MillRules scaffold.
#[flutter_rust_bridge::frb(sync)]
pub fn native_mill_apply_first_place_side_to_move() -> i32 {
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
    next.side_to_move as i32
}

/// Play the canonical a7-d7-g7 mill formation sequence and return how many
/// native Rust remove actions are generated.
#[flutter_rust_bridge::frb(sync)]
pub fn native_mill_mill_sequence_remove_count() -> u32 {
    let rules = MillRules::default();
    let mut snap = rules.initial_state(&[]);
    for node in [1_i16, 6, 2, 5, 0] {
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
    let mut actions = ActionList::<256>::new();
    rules.legal_actions(&snap, &mut actions);
    actions
        .iter()
        .filter(|a| a.kind_tag == MillActionKind::Remove as i16)
        .count() as u32
}

/// Smoke-check: moving-phase move that forms a mill generates remove actions.
#[flutter_rust_bridge::frb(sync)]
pub fn native_mill_moving_mill_remove_count() -> u32 {
    MillRules::moving_mill_remove_count_smoke()
}

/// Smoke-check: removing below three pieces ends the game with White as winner.
#[flutter_rust_bridge::frb(sync)]
pub fn native_mill_removal_below_three_winner() -> i32 {
    MillRules::removal_below_three_winner_smoke()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn native_and_legacy_initial_legal_count_match() {
        let legacy = LegacyKernel::new(0);
        assert_eq!(legacy.legal_actions().len(), native_mill_initial_legal_count() as usize);
        assert_eq!(native_mill_initial_legal_count(), 24);
    }

    #[test]
    fn native_and_legacy_mill_sequence_remove_count_match() {
        let mut legacy = LegacyKernel::new(0);
        for mv in ["d7", "a1", "g7", "d1", "a7"] {
            assert!(legacy.apply_uci(mv), "legacy C++ move should be legal: {mv}");
        }
        let remove_count = legacy
            .legal_actions()
            .iter()
            .filter(|mv| mv.starts_with('x'))
            .count();
        assert_eq!(remove_count, 2);
        assert_eq!(native_mill_mill_sequence_remove_count(), 2);
        assert_eq!(remove_count, native_mill_mill_sequence_remove_count() as usize);
    }
}
