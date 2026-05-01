// SPDX-License-Identifier: GPL-3.0-or-later
// Oracle snapshot generator for the tgf-mill oracle replay tests.
//
// Usage:
//   cargo run -p xtask-legacy-oracle
//
// Writes one JSON file per rule_idx to
//   crates/tgf-mill/testdata/legacy_oracle/<rule_idx>.json
//
// The three determinism invariants (see docs/FRAMEWORK_API.md and the plan):
//   1. Shuffling is disabled: asserted via legacy_get_shuffling_enabled().
//   2. Move selection is sorted(legal_uci) + xorshift64* + fixed seed.
//   3. rule_idx are processed strictly serially (C++ has global Rule state).

use serde::{Deserialize, Serialize};
use std::path::Path;
use tgf_legacy_cxx::{shuffling_enabled, LegacyKernel};
use tgf_mill::{
    MillBoardFullAction, MillFormationActionInPlacingPhase, MillVariantOptions, StalemateAction,
};

// ---------------------------------------------------------------------------
// Oracle data structures (serialized to JSON)
// ---------------------------------------------------------------------------

#[derive(Serialize, Deserialize)]
struct OracleStep {
    ply: u32,
    fen: String,
    /// Sorted legal UCI strings at this position.
    legal_uci: Vec<String>,
    /// C++ Phase tag: ready=1, placing=2, moving=3, gameOver=4.
    phase_tag: i32,
    /// C++ Color tag: WHITE=1, BLACK=2, NOBODY=0.
    side_to_move: i32,
    /// The UCI move chosen by the PRNG for this step.
    picked_uci: String,
}

#[derive(Serialize, Deserialize)]
struct OracleTrajectory {
    seed: u64,
    steps: Vec<OracleStep>,
    /// Phase tag after the last step (or after game-over).
    final_phase_tag: i32,
    /// Side to move after the last step.
    final_side_to_move: i32,
}

#[derive(Serialize, Deserialize)]
struct OracleFile {
    version: u32,
    /// Git SHA at generation time (empty string if not in a git repo).
    generator_git_sha: String,
    rule_idx: i32,
    rule_name: String,
    /// [(depth, node_count), ...] starting at depth 1.
    perft: Vec<(u32, u64)>,
    trajectories: Vec<OracleTrajectory>,
}

// ---------------------------------------------------------------------------
// PRNG — identical to the one in crates/tgf-frb/src/api/simple.rs
// ---------------------------------------------------------------------------

fn xorshift64(state: &mut u64, len: usize) -> usize {
    debug_assert!(len > 0);
    let mut x = *state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    *state = x;
    let scrambled = x.wrapping_mul(0x2545_F491_4F6C_DD1D);
    (scrambled as usize) % len
}

// ---------------------------------------------------------------------------
// rule_idx → (name, MillVariantOptions)
// Must mirror RULES[] in src/rule.cpp exactly.
// ---------------------------------------------------------------------------

fn rule_for_idx(idx: i32) -> (&'static str, MillVariantOptions) {
    let d = MillVariantOptions::default();
    match idx {
        0 => ("Nine Men's Morris", d),
        1 => (
            "Twelve Men's Morris",
            MillVariantOptions {
                piece_count: 12,
                has_diagonal_lines: true,
                ..d
            },
        ),
        2 => (
            "Dooz",
            MillVariantOptions {
                piece_count: 12,
                has_diagonal_lines: true,
                mill_formation_action_in_placing_phase:
                    MillFormationActionInPlacingPhase::RemoveOpponentsPieceFromHandThenOpponentsTurn,
                ..d
            },
        ),
        3 => (
            "Morabaraba",
            MillVariantOptions {
                piece_count: 12,
                has_diagonal_lines: true,
                may_remove_multiple: true,
                ..d
            },
        ),
        4 => (
            "Russian Mill",
            MillVariantOptions {
                one_time_use_mill: true,
                ..d
            },
        ),
        5 => (
            "Lasker Morris",
            MillVariantOptions {
                piece_count: 10,
                may_move_in_placing_phase: true,
                ..d
            },
        ),
        6 => (
            "Cheng San Qi",
            MillVariantOptions {
                may_fly: false,
                ..d
            },
        ),
        7 => (
            "Da San Qi",
            MillVariantOptions {
                piece_count: 12,
                has_diagonal_lines: true,
                mill_formation_action_in_placing_phase:
                    MillFormationActionInPlacingPhase::MarkAndDelayRemovingPieces,
                is_defender_move_first: true,
                may_remove_from_mills_always: true,
                may_fly: false,
                ..d
            },
        ),
        8 => (
            "Zhi Qi",
            MillVariantOptions {
                piece_count: 12,
                has_diagonal_lines: true,
                board_full_action: MillBoardFullAction::FirstAndSecondPlayerRemovePiece,
                stalemate_action: StalemateAction::RemoveOpponentsPieceAndMakeNextMove,
                ..d
            },
        ),
        9 => (
            "El Filja",
            MillVariantOptions {
                piece_count: 12,
                mill_formation_action_in_placing_phase:
                    MillFormationActionInPlacingPhase::RemovalBasedOnMillCounts,
                may_remove_from_mills_always: true,
                board_full_action: MillBoardFullAction::FirstAndSecondPlayerRemovePiece,
                may_fly: false,
                ..d
            },
        ),
        10 => (
            "Experimental",
            MillVariantOptions {
                piece_count: 12,
                has_diagonal_lines: true,
                is_defender_move_first: true,
                may_remove_from_mills_always: true,
                board_full_action: MillBoardFullAction::SecondAndFirstPlayerRemovePiece,
                may_fly: false,
                ..d
            },
        ),
        _ => panic!("unknown rule_idx {idx}"),
    }
}

/// Maximum perft depth per rule_idx (conservative to keep run time fast).
fn max_perft_depth(idx: i32) -> u32 {
    match idx {
        0 => 5,     // 9MM — fast up to 5
        1..=3 => 4, // 12-piece diagonal — slower
        _ => 3,     // all others
    }
}

// ---------------------------------------------------------------------------
// Seeds for the 8 random-walk trajectories per rule_idx
// ---------------------------------------------------------------------------

const TRAJECTORY_SEEDS: [u64; 8] = [
    0xA5A5_A5A5_A5A5_A501,
    0xA5A5_A5A5_A5A5_A502,
    0xA5A5_A5A5_A5A5_A503,
    0xA5A5_A5A5_A5A5_A504,
    0xA5A5_A5A5_A5A5_A505,
    0xA5A5_A5A5_A5A5_A506,
    0xA5A5_A5A5_A5A5_A507,
    0xA5A5_A5A5_A5A5_A508,
];

const MAX_PLIES: usize = 200;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn legacy_legal_sorted(kernel: &LegacyKernel) -> Vec<String> {
    let mut v: Vec<String> = kernel.legal_actions();
    v.sort();
    v
}

fn git_sha() -> String {
    std::process::Command::new("git")
        .args(["rev-parse", "--short", "HEAD"])
        .output()
        .ok()
        .and_then(|o| {
            if o.status.success() {
                String::from_utf8(o.stdout)
                    .ok()
                    .map(|s| s.trim().to_owned())
            } else {
                None
            }
        })
        .unwrap_or_default()
}

// ---------------------------------------------------------------------------
// Generation
// ---------------------------------------------------------------------------

fn generate_rule(rule_idx: i32) -> OracleFile {
    let (rule_name, _opts) = rule_for_idx(rule_idx);
    println!("  rule_idx={rule_idx} ({rule_name})");

    // --- perft ---
    let perft_depth = max_perft_depth(rule_idx);
    let kernel_for_perft = LegacyKernel::new(rule_idx);
    let mut perft_table: Vec<(u32, u64)> = Vec::new();
    for depth in 1..=perft_depth {
        let nodes = kernel_for_perft.perft(depth as i32);
        println!("    perft({depth}) = {nodes}");
        perft_table.push((depth, nodes));
    }
    drop(kernel_for_perft);

    // --- random-walk trajectories ---
    let mut trajectories: Vec<OracleTrajectory> = Vec::new();
    for seed in &TRAJECTORY_SEEDS {
        let mut kernel = LegacyKernel::new(rule_idx);
        let mut rng = *seed;
        let mut steps: Vec<OracleStep> = Vec::new();

        for ply in 0..MAX_PLIES {
            // Check for game-over BEFORE we record (legacy phase 4 = gameOver)
            let phase = kernel.phase_tag();
            if phase == 4 {
                break;
            }

            let legal_sorted = legacy_legal_sorted(&kernel);
            if legal_sorted.is_empty() {
                break;
            }

            let fen = kernel.fen();
            let side = kernel.side_to_move();

            let pick_idx = xorshift64(&mut rng, legal_sorted.len());
            let picked = legal_sorted[pick_idx].clone();

            steps.push(OracleStep {
                ply: ply as u32,
                fen,
                legal_uci: legal_sorted,
                phase_tag: phase,
                side_to_move: side,
                picked_uci: picked.clone(),
            });

            let ok = kernel.apply_uci(&picked);
            assert!(
                ok,
                "rule_idx={rule_idx} seed={seed:#x} ply={ply}: C++ rejected legal UCI {picked}"
            );
        }

        let final_phase = kernel.phase_tag();
        let final_side = kernel.side_to_move();
        println!("    seed={seed:#x} steps={}", steps.len());
        trajectories.push(OracleTrajectory {
            seed: *seed,
            steps,
            final_phase_tag: final_phase,
            final_side_to_move: final_side,
        });
    }

    OracleFile {
        version: 1,
        generator_git_sha: git_sha(),
        rule_idx,
        rule_name: rule_name.to_owned(),
        perft: perft_table,
        trajectories,
    }
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

fn main() {
    // Trigger C++ global initialization and immediately assert the invariant.
    let _dummy = LegacyKernel::new(0);
    assert!(
        !shuffling_enabled(),
        "shuffling must be disabled after legacy_initialize_once(); \
         the oracle would be non-deterministic"
    );
    drop(_dummy);

    let out_dir = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent() // up from crates/xtask-legacy-oracle/ to crates/
        .expect("crates/ dir")
        .join("tgf-mill/testdata/legacy_oracle");

    std::fs::create_dir_all(&out_dir).expect("create oracle dir");

    let sha = git_sha();
    println!("Generating oracle snapshots (git={sha})");
    println!("Output directory: {}", out_dir.display());

    // rule_idx MUST be processed strictly serially — C++ has global Rule state.
    for idx in 0..=10_i32 {
        println!("Processing rule_idx={idx}...");
        let oracle = generate_rule(idx);
        let path = out_dir.join(format!("{idx}.json"));
        let json = serde_json::to_string_pretty(&oracle).expect("serialize oracle");
        std::fs::write(&path, &json).expect("write oracle file");
        println!("  wrote {} bytes -> {}", json.len(), path.display());
    }

    // Also write a machine-readable index for tooling.
    #[derive(Serialize)]
    struct OracleIndex {
        version: u32,
        generator_git_sha: String,
        rules: Vec<(i32, &'static str)>,
    }
    let index = OracleIndex {
        version: 1,
        generator_git_sha: sha,
        rules: (0..=10).map(|idx| (idx, rule_for_idx(idx).0)).collect(),
    };
    let index_path = out_dir.join("index.json");
    std::fs::write(
        &index_path,
        serde_json::to_string_pretty(&index).expect("serialize index"),
    )
    .expect("write index");

    println!("\nDone. Commit crates/tgf-mill/testdata/legacy_oracle/ to the repository.");
    println!("Re-run this tool after X1 rule fixes to regenerate updated snapshots.");
}
