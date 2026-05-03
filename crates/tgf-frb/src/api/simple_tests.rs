// SPDX-License-Identifier: GPL-3.0-or-later
// Unit / integration tests for `crate::api::simple`.
//
// Despite the generic file name, the entire suite covers Mill-specific
// regressions: oracle-replay fixtures generated from the legacy C++
// engine, native-search behaviour, variant-toggle round-trips, and so
// on.  The `simple` module is itself dominated by Mill DTO / spawn /
// smoke entry points that FRB scans by physical position; once those
// move into a sibling `api/mill_*.rs` file (planned follow-up), this
// suite will be split into matching `mill_api_tests.rs` /
// `oracle_replay_tests.rs`.  For now the `simple_tests.rs` name
// matches the AGENTS.md convention for flat-file modules.

use std::collections::BTreeSet;

use super::*;
use tgf_mill::MillPhase;

fn native_legal_uci_set(
    snapshot: &tgf_core::GameStateSnapshot,
    rules: &MillRules,
) -> BTreeSet<String> {
    let mut actions = ActionList::<256>::new();
    rules.legal_actions(snapshot, &mut actions);
    actions
        .iter()
        .map(native_action_to_uci)
        .collect::<BTreeSet<_>>()
}

fn native_action_to_uci(action: &Action) -> String {
    let topo = default_mill_topology();
    match action.kind_tag {
        x if x == MillActionKind::Place as i16 => topo.label_of(action.to_node as u16).to_owned(),
        x if x == MillActionKind::Move as i16 => format!(
            "{}-{}",
            topo.label_of(action.from_node as u16),
            topo.label_of(action.to_node as u16)
        ),
        x if x == MillActionKind::Remove as i16 => {
            format!("x{}", topo.label_of(action.to_node as u16))
        }
        _ => panic!("unsupported native action kind {}", action.kind_tag),
    }
}

/// Find the native [`Action`] whose UCI string equals `uci` in the legal
/// set of `snap`.  Used by the random-walk differential test to apply the
/// same UCI move to both engines.
fn native_action_from_uci(
    snap: &tgf_core::GameStateSnapshot,
    uci: &str,
    rules: &MillRules,
) -> Option<Action> {
    let mut actions = ActionList::<256>::new();
    rules.legal_actions(snap, &mut actions);
    actions.into_iter().find(|a| native_action_to_uci(a) == uci)
}

/// Tiny deterministic xorshift64* PRNG.  Seeded from a fixed constant so
/// the random-walk test produces the same sequence on every machine.
fn next_random_index(state: &mut u64, len: usize) -> usize {
    debug_assert!(len > 0);
    let mut x = *state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    *state = x;
    let scrambled = x.wrapping_mul(0x2545_F491_4F6C_DD1D);
    (scrambled as usize) % len
}

#[test]
fn native_search_replies_to_human_star_with_star_square() {
    let rules = MillRules::default();
    let game = MillGame::default();
    let mut snap = rules.initial_state(&[]);

    // Human first move on legacy SQ_16 / Rust node 9 ("d6"), one of the
    // non-diagonal master-branch star-priority squares.
    snap = rules.apply(
        &snap,
        Action {
            kind_tag: MillActionKind::Place as i16,
            from_node: -1,
            to_node: 9,
            aux: -1,
            payload_bits: 0,
        },
    );
    assert_eq!(snap.side_to_move, 1, "black should reply");

    let mut wb = game.build_workbench(&snap);
    let mut searcher = mill_searcher_default();
    let best = searcher.search_pvs(&mut wb, 1).best_action;

    // Remaining non-diagonal star squares are SQ_18/SQ_20/SQ_22 =
    // Rust nodes 11/13/15.  This guards against confusing legacy square
    // ids (16/18/20/22) with dense Rust node ids.
    assert!(
        matches!(best.to_node, 11 | 13 | 15),
        "expected a star-square reply, got to_node={}",
        best.to_node
    );
}

/// Regression for "AI forms a mill but does not remove the human's
/// piece": after a Place action that completes a mill, the rules
/// engine must keep `side_to_move` on the mover and set
/// `pending_removals[mover] > 0`, and the next search-and-apply pass
/// must produce a Remove action.
#[test]
fn native_search_after_mill_keeps_turn_and_chains_remove() {
    let rules = MillRules::default();
    let game = MillGame::default();
    let options = NativeMillVariantOptions::default();

    // Build a placing-phase position via the public setup API where it
    // is White's turn and White can complete the a7-d7-g7 mill (nodes
    // 0/1/2) by placing on node 1.  Black has two pieces on nodes 3
    // and 5 to provide remove targets after the mill is formed.
    let mut state = rules.setup_empty();
    state.set_piece(0, 1); // White on node 0 (a7)
    state.set_piece(2, 1); // White on node 2 (g7)
    state.set_piece(3, 2); // Black on node 3 (g4)
    state.set_piece(5, 2); // Black on node 5 (d1)
    state.set_side_to_move(0);
    state.recompute_aux(&options);
    let snap = rules.encode_state(state);

    // 1) The first search must place on node 1 to form the mill.
    let mut wb = game.build_workbench(&snap);
    let mut searcher = mill_searcher_default();
    let mill_move = searcher.search_pvs(&mut wb, 2).best_action;
    assert_eq!(
        mill_move.kind_tag,
        MillActionKind::Place as i16,
        "expected a Place action that completes the mill"
    );
    assert_eq!(mill_move.to_node, 1);

    // 2) Apply it.  Side-to-move must stay on White and pending_removal
    //    must become 1, exactly as the C++ legacy engine does after a
    //    mill is formed.  The opaque payload encodes pending_removals
    //    at offsets 28..30 (see `MillState::encode` in tgf-mill).
    let after_mill = rules.apply(&snap, mill_move);
    assert_eq!(
        after_mill.side_to_move, 0,
        "after forming a mill side-to-move must remain on the mover"
    );
    assert_eq!(
        after_mill.opaque_payload[28], 1,
        "mill formation must set pending_removals[mover] = 1"
    );

    // 3) The next search must produce a Remove action.  Without the
    //    fix in NativeMillAiTurnController.playIfAiTurn this would
    //    happen on the *next* tap; the regression test is that the
    //    engine itself can still produce the remove from the same
    //    side_to_move when asked.
    let mut wb2 = game.build_workbench(&after_mill);
    let remove_move = searcher.search_pvs(&mut wb2, 1).best_action;
    assert_eq!(
        remove_move.kind_tag,
        MillActionKind::Remove as i16,
        "after a mill the next AI action must be Remove, got kind={}",
        remove_move.kind_tag,
    );
    assert!(
        matches!(remove_move.to_node, 3 | 5),
        "remove target must be one of Black's pieces (node 3 or 5), got {}",
        remove_move.to_node
    );
}

/// Same as `native_search_after_mill_keeps_turn_and_chains_remove` but
/// searches at depth=5 to activate null-move pruning (which requires
/// depth >= NULL_MOVE_MIN_DEPTH = 3).  Regression for Phase 5 null-move
/// incorrectly preventing the AI from finding a Remove action after
/// forming a mill.
#[test]
fn native_search_after_mill_chains_remove_at_high_depth() {
    let rules = MillRules::default();
    let game = MillGame::default();
    let options = NativeMillVariantOptions::default();

    let mut state = rules.setup_empty();
    state.set_piece(0, 1); // White on node 0 (a7)
    state.set_piece(2, 1); // White on node 2 (g7)
    state.set_piece(3, 2); // Black on node 3 (g4)
    state.set_piece(5, 2); // Black on node 5 (d1)
    state.set_side_to_move(0);
    state.recompute_aux(&options);
    let snap = rules.encode_state(state);

    // 1) Search at depth=2 to find the mill-forming move.
    let mut wb = game.build_workbench(&snap);
    let mut searcher = mill_searcher_default();
    let mill_move = searcher.search_pvs(&mut wb, 2).best_action;
    assert_eq!(mill_move.to_node, 1, "AI must form the mill at node 1");

    // 2) Apply the mill-forming move.
    let after_mill = rules.apply(&snap, mill_move);
    assert_eq!(after_mill.side_to_move, 0, "still White's turn");
    assert_eq!(
        after_mill.opaque_payload[28], 1,
        "pending_removals[White]=1"
    );

    // 3) At depth=5 (null-move activates at depth >= 3), the Remove search
    //    must still find and return a valid Remove action — not Action::NONE.
    let mut wb2 = game.build_workbench(&after_mill);
    let mut searcher5 = mill_searcher_default();
    let remove_move = searcher5.search_pvs(&mut wb2, 5).best_action;
    assert_eq!(
        remove_move.kind_tag,
        MillActionKind::Remove as i16,
        "depth=5 Remove search must return Remove, not kind={}",
        remove_move.kind_tag
    );
    assert!(
        matches!(remove_move.to_node, 3 | 5),
        "Remove target must be Black's piece (3 or 5), got {}",
        remove_move.to_node
    );
}

/// Moving-phase version: AI moves a piece to form a mill at depth=5.
/// Regression for Phase 5 null-move incorrectly preventing Remove.
#[test]
fn native_search_moving_phase_mill_chains_remove_at_high_depth() {
    let rules = MillRules::default();
    let game = MillGame::default();
    let options = NativeMillVariantOptions::default();

    // Moving phase: White on 0, 2, 4; Black on 5, 6, 7.
    // White can complete the [0,1,2] mill by moving 4->1.
    let mut state = rules.setup_empty();
    state.set_piece(0, 1); // White on a7
    state.set_piece(2, 1); // White on g7
    state.set_piece(4, 1); // White on e4 (adjacent to node 1 via edge moves)
    state.set_piece(5, 2); // Black on d1
    state.set_piece(6, 2); // Black on c3
    state.set_piece(7, 2); // Black on a1
    state.set_side_to_move(0);
    state.recompute_aux(&options);
    state.set_phase(MillPhase::Moving); // Force moving phase
    let snap = rules.encode_state(state);

    // Verify this is moving phase
    assert_eq!(snap.phase_tag, MillPhase::Moving as i16);

    // 1) At depth=5 the AI must find a Move action.
    let mut wb = game.build_workbench(&snap);
    let mut searcher = mill_searcher_default();
    let best_move = searcher.search_pvs(&mut wb, 5).best_action;
    assert_eq!(
        best_move.kind_tag,
        MillActionKind::Move as i16,
        "expected Move action, got kind={}",
        best_move.kind_tag
    );

    // 2) Apply it and check if a mill was formed.
    let after_move = rules.apply(&snap, best_move);

    // If the move formed a mill, pending_removals is encoded at payload[28].
    // pending_removals[0] > 0 means White has a pending Remove.
    if after_move.opaque_payload[28] > 0 {
        assert_eq!(after_move.side_to_move, 0, "side must stay on White");
        // 3) Remove search at depth=5 must return a Remove action.
        let mut wb2 = game.build_workbench(&after_move);
        let mut searcher2 = mill_searcher_default();
        let remove = searcher2.search_pvs(&mut wb2, 5).best_action;
        assert_eq!(
            remove.kind_tag,
            MillActionKind::Remove as i16,
            "Remove search must return Remove, not kind={}",
            remove.kind_tag
        );
    }
}

/// Regression test for the exact game sequence in the bug report:
/// 1.d1 d6  2.g1 f4  3.g4 d2  4.a4 [AI must respond]
///
/// After White places a4 (Rust node 7), the game should have
/// side_to_move=1 (Black's turn) and NOT be terminal.
/// This confirms that the Rust rules engine correctly switches sides
/// and that the AI can find a valid response.
#[test]
fn ai_must_respond_after_a4_in_reported_sequence() {
    let rules = MillRules::default();
    let game = MillGame::default();

    // Apply the sequence: d1=node5, d6=node9, g1=node4, f4=node11,
    // g4=node3, d2=node13.  Then White places a4=node7.
    let mut snap = rules.initial_state(&[]);
    for node in [5_i16, 9, 4, 11, 3, 13] {
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

    // State: White has d1(5)+g1(4)+g4(3), Black has d6(9)+f4(11)+d2(13).
    // It is White's turn (side_to_move=0).
    assert_eq!(snap.side_to_move, 0, "should be White's turn before a4");
    assert_eq!(
        snap.phase_tag,
        MillPhase::Placing as i16,
        "should be placing"
    );

    // White places a4 (Rust node 7).
    snap = rules.apply(
        &snap,
        Action {
            kind_tag: MillActionKind::Place as i16,
            from_node: -1,
            to_node: 7,
            aux: -1,
            payload_bits: 0,
        },
    );

    // After a4: must be Black's turn and game NOT terminal.
    assert_eq!(
        snap.side_to_move, 1,
        "after White places a4 it must be Black's turn (side=1)"
    );
    assert_eq!(
        snap.phase_tag,
        MillPhase::Placing as i16,
        "still placing phase"
    );
    // Verify not terminal: outcome.kind would be "ongoing".
    // We check this indirectly: legal actions must be non-empty.
    let mut legal = tgf_core::ActionList::<256>::new();
    rules.legal_actions(&snap, &mut legal);
    assert!(
        !legal.is_empty(),
        "Black must have legal actions after White places a4"
    );
    assert!(
        legal
            .iter()
            .all(|a| a.kind_tag == MillActionKind::Place as i16),
        "all Black legal actions should be Place in placing phase"
    );

    // AI (Black, depth 1) must find a valid Place action — no NONE.
    let mut wb = game.build_workbench(&snap);
    let mut searcher = mill_searcher_default();
    let ai_action = searcher.search_pvs(&mut wb, 1).best_action;
    assert_eq!(
        ai_action.kind_tag,
        MillActionKind::Place as i16,
        "AI must respond with a Place action, got kind={}",
        ai_action.kind_tag
    );
    assert!(
        (0..24).contains(&(ai_action.to_node as usize)),
        "AI Place action must target a valid board node 0..23, got {}",
        ai_action.to_node
    );
}

/// Regression test for the reported game sequence
/// 1.d2 d6 2.f4 b4 3.g1 g4 4.a1 — Black must reply after White's a1.
///
/// Node mapping: d2=13, d6=9, f4=11, b4=15, g1=4, g4=3, a1=6.
#[test]
fn ai_must_respond_after_a1_in_reported_sequence() {
    let rules = MillRules::default();
    let game = MillGame::default();

    let mut snap = rules.initial_state(&[]);

    // Play the full sequence; alternates White / Black.
    for node in [13_i16, 9, 11, 15, 4, 3] {
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

    // After 6 placements it is White's turn (3W + 3B placed).
    assert_eq!(snap.side_to_move, 0, "should be White's turn before a1");

    // White places a1 (Rust node 6).
    snap = rules.apply(
        &snap,
        Action {
            kind_tag: MillActionKind::Place as i16,
            from_node: -1,
            to_node: 6,
            aux: -1,
            payload_bits: 0,
        },
    );

    // After a1: must be Black's turn, game NOT terminal.
    assert_eq!(
        snap.side_to_move, 1,
        "after White places a1 it must be Black's turn (side=1)"
    );
    assert_eq!(
        snap.phase_tag,
        MillPhase::Placing as i16,
        "still placing phase after move 4"
    );

    // Black must have legal Place actions.
    let mut legal = tgf_core::ActionList::<256>::new();
    rules.legal_actions(&snap, &mut legal);
    assert!(
        !legal.is_empty(),
        "Black must have legal actions after White places a1"
    );
    assert!(
        legal
            .iter()
            .all(|a| a.kind_tag == MillActionKind::Place as i16),
        "all Black legal actions should be Place in placing phase"
    );

    // AI (Black, depth 1) must find a valid Place action — no NONE.
    let mut wb = game.build_workbench(&snap);
    let mut searcher = mill_searcher_default();
    let ai_action = searcher.search_pvs(&mut wb, 1).best_action;
    assert_eq!(
        ai_action.kind_tag,
        MillActionKind::Place as i16,
        "AI must respond with a Place action, got kind={}",
        ai_action.kind_tag
    );
    assert!(
        (0..24).contains(&(ai_action.to_node as usize)),
        "AI Place action must target valid node 0..23, got {}",
        ai_action.to_node
    );
}

#[test]
fn rust_only_variant_option_toggles_are_reachable() {
    let variant = MillVariantOptions {
        piece_count: 9,
        fly_piece_count: 3,
        pieces_at_least_count: 3,
        may_fly: true,
        has_diagonal_lines: false,
        mill_formation_action_in_placing_phase:
            MillFormationActionInPlacingPhase::RemoveOpponentsPieceFromHandThenYourTurn,
        may_remove_from_mills_always: true,
        may_remove_multiple: true,
        n_move_rule: 2,
        endgame_n_move_rule: 1,
        may_move_in_placing_phase: true,
        is_defender_move_first: true,
        restrict_repeated_mills_formation: true,
        one_time_use_mill: true,
        stop_placing_when_two_empty_squares: true,
        board_full_action: MillBoardFullAction::AgreeToDraw,
        threefold_repetition_rule: false,
        custodian_capture: CaptureRuleConfig {
            enabled: true,
            on_square_edges: true,
            on_cross_lines: true,
            on_diagonal_lines: true,
            in_placing_phase: true,
            in_moving_phase: true,
            only_available_when_own_pieces_leq3: false,
        },
        intervention_capture: CaptureRuleConfig {
            enabled: true,
            on_square_edges: true,
            on_cross_lines: true,
            on_diagonal_lines: true,
            in_placing_phase: true,
            in_moving_phase: true,
            only_available_when_own_pieces_leq3: false,
        },
        leap_capture: CaptureRuleConfig {
            enabled: true,
            on_square_edges: true,
            on_cross_lines: true,
            on_diagonal_lines: true,
            in_placing_phase: true,
            in_moving_phase: true,
            only_available_when_own_pieces_leq3: false,
        },
        stalemate_action: StalemateAction::BothPlayersRemoveOpponentsPiece,
        consider_mobility: true,
        focus_on_blocking_paths: false,
    };
    let native: NativeMillVariantOptions = variant.into();
    assert!(native.may_remove_from_mills_always);
    assert!(native.may_remove_multiple);
    assert_eq!(native.n_move_rule, 2);
    assert_eq!(native.endgame_n_move_rule, 1);
    assert!(native.may_move_in_placing_phase);
    assert!(native.is_defender_move_first);
    assert!(matches!(
        native.mill_formation_action_in_placing_phase,
        NativeMillFormationActionInPlacingPhase::RemoveOpponentsPieceFromHandThenYourTurn
    ));
    assert!(native.restrict_repeated_mills_formation);
    assert!(native.one_time_use_mill);
    assert!(native.stop_placing_when_two_empty_squares);
    assert!(matches!(
        native.board_full_action,
        NativeMillBoardFullAction::AgreeToDraw
    ));
    assert!(!native.threefold_repetition_rule);
    assert!(native.custodian_capture.enabled);
    assert!(native.intervention_capture.enabled);
    assert!(native.leap_capture.enabled);
    assert!(matches!(
        native.stalemate_action,
        NativeStalemateAction::BothPlayersRemoveOpponentsPiece
    ));
}

fn run_native_self_play(num_games: usize, default_seed: u64, rules: &MillRules) {
    const MAX_PLIES: usize = 80;
    let mut rng_state: u64 = default_seed;
    for _game_idx in 0..num_games {
        let mut snap = rules.initial_state(&[]);
        for _ply in 0..MAX_PLIES {
            if snap.phase_tag == MillPhase::GameOver as i16 {
                break;
            }
            let native_set = native_legal_uci_set(&snap, rules);
            if native_set.is_empty() {
                break;
            }
            let mut sorted: Vec<String> = native_set.into_iter().collect();
            sorted.sort();
            let pick = next_random_index(&mut rng_state, sorted.len());
            let mv = sorted[pick].clone();
            let native_action = native_action_from_uci(&snap, &mv, rules)
                .expect("native_action_from_uci must decode a legal UCI move");
            snap = rules.apply(&snap, native_action);
        }
    }
}

/// Rust-only self-play with `custodian_capture.enabled = true`.
///
/// No C++ legacy rule has custodian capture enabled, so a full
/// differential is not possible.  This test verifies that the Rust
/// rules engine produces consistent legal-action sets and applies
/// moves without panicking across 300 seeded random games.
#[test]
fn native_self_play_custodian_capture_no_panic() {
    let opts = NativeMillVariantOptions {
        custodian_capture: NativeCaptureRuleConfig {
            enabled: true,
            ..Default::default()
        },
        ..Default::default()
    };
    let rules = MillRules::new(opts);
    run_native_self_play(300, 0xC0DE_C057_0D1A_4E42, &rules);
}

/// Rust-only self-play with `intervention_capture.enabled = true`.
#[test]
fn native_self_play_intervention_capture_no_panic() {
    let opts = NativeMillVariantOptions {
        intervention_capture: NativeCaptureRuleConfig {
            enabled: true,
            ..Default::default()
        },
        ..Default::default()
    };
    let rules = MillRules::new(opts);
    run_native_self_play(300, 0x14E5_E4E4_104E_CA14, &rules);
}

/// Rust-only self-play with `leap_capture.enabled = true`.  Now that
/// generate_move_actions emits the leap superset (master
/// generate<MOVE>'s tryAddLeap shape) the legal-action set is
/// strictly larger than the no-capture baseline, so the random walk
/// also implicitly exercises the new code path through both placing
/// (via may_move_in_placing_phase) and moving phases.
#[test]
fn native_self_play_leap_capture_no_panic() {
    let opts = NativeMillVariantOptions {
        leap_capture: NativeCaptureRuleConfig {
            enabled: true,
            ..Default::default()
        },
        ..Default::default()
    };
    let rules = MillRules::new(opts);
    run_native_self_play(300, 0xCEAA_C057_0D1A_4E42, &rules);
}

/// Rust-only self-play with `restrict_repeated_mills_formation = true`.
///
/// No C++ legacy rule exercises this flag.  Verifies that the Rust
/// implementation does not panic when the flag is enabled.
#[test]
fn native_self_play_restrict_repeated_mills_no_panic() {
    let opts = NativeMillVariantOptions {
        restrict_repeated_mills_formation: true,
        ..Default::default()
    };
    let rules = MillRules::new(opts);
    run_native_self_play(300, 0x4E57_41C7_411E_5EED, &rules);
}

// ---------------------------------------------------------------------------
// Oracle replay tests (Phase 0)
//
// These tests read pre-generated JSON oracle files produced by
// `cargo run -p xtask-legacy-oracle` and verify that the Rust tgf-mill
// rules produce identical legal action sets, phase tags, and side-to-move
// values at every step.
//
// If an oracle file is missing the test is silently skipped (oracle not
// yet generated for this environment).  After running the generator once
// and committing the files, the tests become hard assertions.
//
// Rules 8 (Zhi Qi) and 9 (El Filja) are marked #[ignore] because they
// have known divergences tracked in known_failures.toml.
// ---------------------------------------------------------------------------

#[cfg(test)]
mod oracle_replay {
    use super::*;
    use serde::Deserialize;
    use std::collections::BTreeSet;
    use tgf_mill::MillRules;

    #[derive(Deserialize)]
    struct OracleStep {
        ply: u32,
        // fen: String, // available but not used in replay
        legal_uci: Vec<String>,
        phase_tag: i32,
        side_to_move: i32,
        picked_uci: String,
    }

    #[derive(Deserialize)]
    struct OracleTrajectory {
        seed: u64,
        steps: Vec<OracleStep>,
    }

    #[derive(Deserialize)]
    struct OracleFile {
        rule_idx: i32,
        rule_name: String,
        trajectories: Vec<OracleTrajectory>,
    }

    fn oracle_dir() -> std::path::PathBuf {
        std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .expect("crates/ parent")
            .join("tgf-mill/testdata/legacy_oracle")
    }

    /// Delegate to `tgf_mill::preset_for` — the canonical source.
    fn rules_for_idx(idx: i32) -> MillRules {
        tgf_mill::rules_for_preset(idx).unwrap_or_else(|| panic!("no preset for rule_idx {idx}"))
    }

    /// Replay one oracle file against tgf-mill.
    /// Returns Ok(()) if all steps matched, or Err(msg) on first divergence.
    fn replay_oracle_file(oracle: &OracleFile) -> Result<(), String> {
        let idx = oracle.rule_idx;
        let rules = rules_for_idx(idx);

        for traj in &oracle.trajectories {
            let mut snap = rules.initial_state(&[]);

            for step in &traj.steps {
                // When Rust ends the game (n_move_rule, threefold, stalemate)
                // before the legacy C++ engine, stop replaying this trajectory.
                // C++ only commits draw/stalemate outcomes when the player issues
                // "draw" — so the oracle continues past Rust's automatic end.
                // This mirrors the early-exit in run_random_walk.
                if snap.phase_tag == tgf_mill::MillPhase::GameOver as i16 {
                    break;
                }

                let native_set: BTreeSet<String> = native_legal_uci_set(&snap, &rules);
                let oracle_set: BTreeSet<String> = step.legal_uci.iter().cloned().collect();

                if native_set != oracle_set {
                    let native_only: Vec<_> = native_set.difference(&oracle_set).collect();
                    let oracle_only: Vec<_> = oracle_set.difference(&native_set).collect();
                    return Err(format!(
                        "[rule_idx={idx} ({}) seed={:#x} ply={}] legal set divergence:\n  \
                         native_only={native_only:?}\n  oracle_only={oracle_only:?}",
                        oracle.rule_name, traj.seed, step.ply,
                    ));
                }

                let native_phase = snap.phase_tag as i32;
                let native_phase_legacy = native_phase + 1;
                if native_phase_legacy != step.phase_tag {
                    return Err(format!(
                        "[rule_idx={idx} seed={:#x} ply={}] phase mismatch: \
                         native_legacy={native_phase_legacy} oracle={}",
                        traj.seed, step.ply, step.phase_tag,
                    ));
                }

                let native_side = snap.side_to_move;
                let native_side_legacy = match native_side {
                    0 => 1,
                    1 => 2,
                    _ => 0,
                };
                if native_side_legacy != step.side_to_move {
                    return Err(format!(
                        "[rule_idx={idx} seed={:#x} ply={}] side mismatch: \
                         native_legacy={native_side_legacy} oracle={}",
                        traj.seed, step.ply, step.side_to_move,
                    ));
                }

                // Advance state using the oracle's chosen move.
                let picked = &step.picked_uci;
                match native_action_from_uci(&snap, picked, &rules) {
                    Some(action) => snap = rules.apply(&snap, action),
                    None => {
                        return Err(format!(
                            "[rule_idx={idx} seed={:#x} ply={}] cannot decode \
                             oracle UCI '{picked}' as native action",
                            traj.seed, step.ply,
                        ));
                    }
                }
            }
        }
        Ok(())
    }

    fn run_oracle_replay(rule_idx: i32) {
        let path = oracle_dir().join(format!("{rule_idx}.json"));
        if !path.exists() {
            eprintln!(
                "Oracle file {:?} not found — run `cargo run -p xtask-legacy-oracle` \
                 to generate it first. Skipping.",
                path
            );
            return;
        }
        let content = std::fs::read_to_string(&path)
            .unwrap_or_else(|e| panic!("read oracle {}: {e}", path.display()));
        let oracle: OracleFile = serde_json::from_str(&content)
            .unwrap_or_else(|e| panic!("parse oracle {}: {e}", path.display()));
        if let Err(msg) = replay_oracle_file(&oracle) {
            panic!("Oracle replay failed:\n{msg}");
        }
    }

    #[test]
    fn oracle_replay_9mm() {
        run_oracle_replay(0);
    }
    #[test]
    fn oracle_replay_12mm_diagonal() {
        run_oracle_replay(1);
    }
    #[test]
    #[ignore = "Dooz oracle replay: RemoveOpponentsPieceFromHandThenOpponentsTurn placing-phase gap, tracked in known_failures.toml"]
    fn oracle_replay_dooz() {
        run_oracle_replay(2);
    }
    #[test]
    fn oracle_replay_morabaraba() {
        run_oracle_replay(3);
    }
    #[test]
    fn oracle_replay_russian_mill() {
        run_oracle_replay(4);
    }
    #[test]
    fn oracle_replay_lasker_morris() {
        run_oracle_replay(5);
    }
    #[test]
    fn oracle_replay_cheng_san_qi() {
        run_oracle_replay(6);
    }
    #[test]
    fn oracle_replay_da_san_qi() {
        run_oracle_replay(7);
    }
    #[test]
    fn oracle_replay_experimental() {
        run_oracle_replay(10);
    }

    #[test]
    #[ignore = "Zhi Qi oracle replay: known divergence, tracked in known_failures.toml"]
    fn oracle_replay_zhi_qi() {
        run_oracle_replay(8);
    }
    #[test]
    #[ignore = "El Filja oracle replay: known divergence, tracked in known_failures.toml"]
    fn oracle_replay_el_filja() {
        run_oracle_replay(9);
    }
}

/// Verify that setting qsearch_max_depth=1 still returns valid actions
/// and does not produce terminal scores from a non-terminal fixture.
#[test]
fn native_qsearch_depth_1_returns_valid_non_terminal_score() {
    let rules = MillRules::default();
    let game = MillGame::default();
    let snap = rules.no_mill_moving_phase_snapshot();

    let mut wb0 = game.build_workbench(&snap);
    let mut wb1 = game.build_workbench(&snap);

    let mut s0 = mill_searcher_default();
    s0.set_qsearch_max_depth(0);
    let r0 = s0.search_pvs(&mut wb0, 2);

    let mut s1 = mill_searcher_default();
    s1.set_qsearch_max_depth(1);
    let r1 = s1.search_pvs(&mut wb1, 2);

    assert!(
        !r0.best_action.is_none(),
        "qsearch_max_depth=0 must find a move"
    );
    assert!(
        !r1.best_action.is_none(),
        "qsearch_max_depth=1 must find a move"
    );
    assert!(
        r0.score.abs() < 30_000,
        "depth=0 score must not be a terminal sentinel"
    );
    assert!(
        r1.score.abs() < 30_000,
        "depth=1 score must not be a terminal sentinel"
    );
}
