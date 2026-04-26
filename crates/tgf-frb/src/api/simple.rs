// SPDX-License-Identifier: GPL-3.0-or-later
// tgf-frb – Phase 1 API surface.
//
// Conventions:
//   - `#[flutter_rust_bridge::frb(sync)]` makes the call synchronous on the
//     Dart side (no Future wrapping); use only for cheap, non-blocking calls.
//   - All public functions in this module are auto-exported to Dart by codegen.

use once_cell::sync::Lazy;
use std::sync::Mutex;
use std::thread;

use crate::frb_generated::StreamSink;
use tgf_core::{Action, ActionList, BoardTopology, Game, GameRules};
use tgf_legacy_cxx::LegacyKernel;
use tgf_mill::{
    default_mill_topology, MillActionKind, MillGame, MillRules,
    MillVariantOptions as NativeMillVariantOptions,
};
use tgf_search::{SearchAbortHandle, Searcher, SearchOptions};
#[cfg(test)]
use tgf_search::perft;

static LEGACY_KERNEL: Lazy<Mutex<Option<LegacyKernel>>> =
    Lazy::new(|| Mutex::new(None));
static ACTIVE_SEARCH: Lazy<Mutex<Option<SearchAbortHandle>>> =
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

/// Public FRB DTO for the subset of Mill variant options already supported by
/// the Rust-native rules scaffold.  It intentionally mirrors the field names
/// that will later replace the C++ Rule struct.
#[derive(Clone, Debug)]
pub struct MillVariantOptions {
    pub piece_count: u8,
    pub fly_piece_count: u8,
    pub pieces_at_least_count: u8,
    pub may_fly: bool,
    pub has_diagonal_lines: bool,
}

impl From<MillVariantOptions> for NativeMillVariantOptions {
    fn from(value: MillVariantOptions) -> Self {
        Self {
            piece_count: value.piece_count,
            fly_piece_count: value.fly_piece_count,
            pieces_at_least_count: value.pieces_at_least_count,
            may_fly: value.may_fly,
            has_diagonal_lines: value.has_diagonal_lines,
        }
    }
}

/// Default Nine Men's Morris variant options.
#[flutter_rust_bridge::frb(sync)]
pub fn native_mill_default_variant_options() -> MillVariantOptions {
    let defaults = NativeMillVariantOptions::default();
    MillVariantOptions {
        piece_count: defaults.piece_count,
        fly_piece_count: defaults.fly_piece_count,
        pieces_at_least_count: defaults.pieces_at_least_count,
        may_fly: defaults.may_fly,
        has_diagonal_lines: defaults.has_diagonal_lines,
    }
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

#[derive(Clone, Debug)]
pub struct EngineEvent {
    pub kind: String,
    pub depth: i32,
    pub score: i32,
    pub nodes: u64,
    pub to_node: i32,
    pub reason: String,
}

impl EngineEvent {
    fn ready() -> Self {
        Self::new("ready")
    }

    fn stopped() -> Self {
        Self::new("stopped")
    }

    fn info(depth: i32, score: i32, nodes: u64) -> Self {
        Self {
            kind: "info".to_owned(),
            depth,
            score,
            nodes,
            to_node: -1,
            reason: String::new(),
        }
    }

    fn best_move(to_node: i32, score: i32) -> Self {
        Self {
            kind: "bestMove".to_owned(),
            depth: 0,
            score,
            nodes: 0,
            to_node,
            reason: String::new(),
        }
    }

    fn new(kind: &str) -> Self {
        Self {
            kind: kind.to_owned(),
            depth: 0,
            score: 0,
            nodes: 0,
            to_node: -1,
            reason: String::new(),
        }
    }
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

/// Opening legal action count for an explicit variant option set.
#[flutter_rust_bridge::frb(sync)]
pub fn native_mill_initial_legal_count_for_variant(
    variant: MillVariantOptions,
) -> u32 {
    let rules = MillRules::new(variant.into());
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

/// Run the Rust generic Searcher<MillGame> for one ply and return the best
/// destination node.  This is a Phase 5 smoke-check for the monomorphised
/// search path.
#[flutter_rust_bridge::frb(sync)]
pub fn native_mill_search_depth_one_best_to_node() -> i32 {
    let rules = MillRules::default();
    let game = MillGame::default();
    let snap = rules.initial_state(&[]);
    let mut wb = game.build_workbench(&snap);
    let mut searcher = Searcher::<MillGame>::new();
    searcher.search(&mut wb, 1).best_action.to_node as i32
}

/// Run the Rust generic PVS path for one ply and return the best destination.
#[flutter_rust_bridge::frb(sync)]
pub fn native_mill_pvs_depth_one_best_to_node() -> i32 {
    let rules = MillRules::default();
    let game = MillGame::default();
    let snap = rules.initial_state(&[]);
    let mut wb = game.build_workbench(&snap);
    let mut searcher = Searcher::<MillGame>::new();
    searcher.search_pvs(&mut wb, 1).best_action.to_node as i32
}

/// Run deterministic random-search with a caller-supplied seed.
#[flutter_rust_bridge::frb(sync)]
pub fn native_mill_random_best_to_node(seed: u64) -> i32 {
    let rules = MillRules::default();
    let game = MillGame::default();
    let snap = rules.initial_state(&[]);
    let mut wb = game.build_workbench(&snap);
    let mut searcher = Searcher::<MillGame>::new();
    searcher.set_random_seed(seed);
    searcher.random_search(&mut wb).best_action.to_node as i32
}

/// Differential perft check: returns true when the Rust-native MillRules and
/// the legacy C++ engine produce identical perft counts at the given depth.
#[flutter_rust_bridge::frb(sync)]
pub fn native_and_legacy_perft_match(depth: i32) -> bool {
    let legacy = LegacyKernel::new(0);
    let rules = MillRules::default();
    let game = MillGame::default();
    let snap = rules.initial_state(&[]);
    let mut wb = game.build_workbench(&snap);
    let native = tgf_search::perft::<MillGame>(&mut wb, depth);
    legacy.perft(depth) == native
}

/// Differential perft check from the canonical pending-remove state after
/// W d7, B a1, W g7, B d1, W a7.
#[flutter_rust_bridge::frb(sync)]
pub fn native_and_legacy_pending_remove_perft_match(depth: i32) -> bool {
    let mut legacy = LegacyKernel::new(0);
    for mv in ["d7", "a1", "g7", "d1", "a7"] {
        if !legacy.apply_uci(mv) {
            return false;
        }
    }

    let rules = MillRules::default();
    let game = MillGame::default();
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
    let mut wb = game.build_workbench(&snap);
    legacy.perft(depth) == tgf_search::perft::<MillGame>(&mut wb, depth)
}

/// Smoke-check that the Rust searcher honours a zero-millisecond time limit.
#[flutter_rust_bridge::frb(sync)]
pub fn native_mill_search_zero_time_limit_aborts() -> bool {
    let rules = MillRules::default();
    let game = MillGame::default();
    let snap = rules.initial_state(&[]);
    let mut wb = game.build_workbench(&snap);
    let mut searcher = Searcher::<MillGame>::new();
    searcher.set_options(SearchOptions {
        depth_extension: false,
        node_limit: None,
        time_limit_ms: Some(0),
    });
    let _ = searcher.search(&mut wb, 3);
    searcher.was_aborted()
}

/// Phase 5 async search event stream.
///
/// This is intentionally minimal: it spawns a worker thread, runs the native
/// Rust Searcher<MillGame>, and emits Ready / Info / BestMove / Stopped.
/// Later work replaces this with a cancellable long-lived search worker.
pub fn native_mill_search_events(depth: i32, sink: StreamSink<EngineEvent>) {
    thread::spawn(move || {
        if sink.add(EngineEvent::ready()).is_err() {
            return;
        }

        let rules = MillRules::default();
        let game = MillGame::default();
        let snap = rules.initial_state(&[]);
        let mut wb = game.build_workbench(&snap);
        let mut searcher = Searcher::<MillGame>::new();
        {
            let mut active = ACTIVE_SEARCH
                .lock()
                .expect("active search mutex poisoned");
            *active = Some(searcher.abort_handle());
        }

        let result = searcher.search_pvs(&mut wb, depth.max(1));
        let _ = sink.add(EngineEvent::info(depth.max(1), result.score, result.nodes));
        let _ = sink.add(EngineEvent::best_move(
            result.best_action.to_node as i32,
            result.score,
        ));
        let _ = sink.add(EngineEvent::stopped());
        let mut active = ACTIVE_SEARCH
            .lock()
            .expect("active search mutex poisoned");
        *active = None;
    });
}

/// Request that the currently running native Rust search stops.
///
/// Returns false when no native search worker is active.
#[flutter_rust_bridge::frb(sync)]
pub fn native_mill_search_stop() -> bool {
    let active = ACTIVE_SEARCH
        .lock()
        .expect("active search mutex poisoned");
    if let Some(handle) = active.as_ref() {
        handle.request_abort();
        true
    } else {
        false
    }
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
    fn native_and_legacy_perft_depth_one_match() {
        let legacy = LegacyKernel::new(0);
        let legacy_count = legacy.legal_actions().len() as u64;
        let legacy_perft = legacy.perft(1);

        let rules = MillRules::default();
        let game = MillGame::default();
        let snap = rules.initial_state(&[]);
        let mut wb = game.build_workbench(&snap);
        let native_perft = perft::<MillGame>(&mut wb, 1);

        assert_eq!(legacy_count, native_perft);
        assert_eq!(legacy_perft, native_perft);
        assert_eq!(native_perft, 24);
    }

    #[test]
    fn native_and_legacy_perft_depth_two_match() {
        let legacy = LegacyKernel::new(0);
        let legacy_perft = legacy.perft(2);

        let rules = MillRules::default();
        let game = MillGame::default();
        let snap = rules.initial_state(&[]);
        let mut wb = game.build_workbench(&snap);
        let native_perft = perft::<MillGame>(&mut wb, 2);

        // 24 * 23 = 552 from 9MM opening (no mills possible after 2 plies).
        assert_eq!(native_perft, 24 * 23);
        assert_eq!(legacy_perft, native_perft);
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

    #[test]
    fn native_and_legacy_pending_remove_perft_match() {
        let mut legacy = LegacyKernel::new(0);
        for mv in ["d7", "a1", "g7", "d1", "a7"] {
            assert!(legacy.apply_uci(mv), "legacy C++ move should be legal: {mv}");
        }

        let rules = MillRules::default();
        let game = MillGame::default();
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
        let mut wb = game.build_workbench(&snap);

        assert_eq!(legacy.perft(1), perft::<MillGame>(&mut wb, 1));

        let mut wb = game.build_workbench(&snap);
        assert_eq!(legacy.perft(2), perft::<MillGame>(&mut wb, 2));
    }
}
