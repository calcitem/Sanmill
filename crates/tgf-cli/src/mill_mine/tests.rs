// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

use std::io::BufRead;

use super::*;

fn bundled_asset_root() -> String {
    std::path::Path::new(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../src/ui/flutter_app/assets/databases"
    ))
    .to_string_lossy()
    .into_owned()
}

fn args(pairs: &[(&str, &str)], flags: &[&str]) -> Vec<String> {
    let mut out = Vec::new();
    for (flag, value) in pairs {
        out.push((*flag).to_string());
        out.push((*value).to_string());
    }
    for flag in flags {
        out.push((*flag).to_string());
    }
    out
}

/// End-to-end smoke test against the bundled small asset subset: a tiny,
/// tightly budgeted run must complete without panicking, must produce a
/// checkpoint, and (since the run is single-threaded and deterministic)
/// must produce byte-identical JSONL output across two independent runs.
#[test]
fn mine_runs_deterministically_against_bundled_assets() {
    let dir = std::env::temp_dir().join(format!("sanmill_mill_mine_test_{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let db = bundled_asset_root();

    let run = |suffix: &str| {
        let out = dir.join(format!("entries_{suffix}.jsonl"));
        let checkpoint = dir.join(format!("checkpoint_{suffix}.json"));
        let argv = args(
            &[
                ("--db", db.as_str()),
                ("--out", out.to_str().unwrap()),
                ("--checkpoint", checkpoint.to_str().unwrap()),
                ("--max-depth-plies", "2"),
                ("--budget-engine-calls", "20"),
                ("--workers", "1"),
                ("--depth", "3"),
            ],
            &[],
        );
        run_mill_mine(&argv);
        std::fs::read_to_string(&out).unwrap_or_default()
    };

    let first = run("a");
    let second = run("b");
    assert_eq!(
        first, second,
        "deterministic single-worker mining must produce identical JSONL across runs"
    );

    // Every emitted line must be a well-formed MineEntry with a plausible
    // shape (non-zero key, severity 1 or 2, mass carried through from the
    // root seed).
    for line in first.lines() {
        let entry: MineEntry = serde_json::from_str(line).expect("entry must be valid JSON");
        assert!((1..=2).contains(&entry.severity));
        assert!(entry.mass > 0.0);
        assert_ne!(entry.key, entry.best_child);
    }

    let _ = std::fs::remove_dir_all(&dir);
}

/// A resumed run (checkpoint from a first, budget-limited run) must not
/// re-emit entries already found, and must make further progress.
#[test]
fn mine_resumes_from_checkpoint() {
    let dir = std::env::temp_dir().join(format!("sanmill_mill_mine_resume_{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let db = bundled_asset_root();
    let out = dir.join("entries.jsonl");
    let checkpoint = dir.join("checkpoint.json");

    let base_argv = |budget: &str| {
        args(
            &[
                ("--db", db.as_str()),
                ("--out", out.to_str().unwrap()),
                ("--checkpoint", checkpoint.to_str().unwrap()),
                ("--max-depth-plies", "2"),
                ("--budget-engine-calls", budget),
                ("--workers", "1"),
                ("--depth", "3"),
            ],
            &[],
        )
    };

    run_mill_mine(&base_argv("5"));
    let visited_after_first = {
        let bytes = std::fs::read(&checkpoint).unwrap();
        let checkpoint: Checkpoint = serde_json::from_slice(&bytes).unwrap();
        checkpoint.visited.len()
    };

    let mut resumed_argv = base_argv("10");
    resumed_argv.push("--resume".to_string());
    run_mill_mine(&resumed_argv);
    let visited_after_second = {
        let bytes = std::fs::read(&checkpoint).unwrap();
        let checkpoint: Checkpoint = serde_json::from_slice(&bytes).unwrap();
        checkpoint.visited.len()
    };

    assert!(
        visited_after_second >= visited_after_first,
        "resuming must not lose already-visited nodes"
    );

    let _ = std::fs::remove_dir_all(&dir);
}

/// `--seed-fen-file` parsing: valid FENs are kept verbatim, comments and
/// blank lines are skipped for readability, and an unparseable line is
/// skipped (not fatal) since this file is typically hand-curated from
/// `mill arena --out`'s diagnostic JSONL.
#[test]
fn load_seed_fen_file_skips_comments_blanks_and_bad_lines() {
    let path = std::env::temp_dir().join(format!(
        "sanmill_mill_mine_seed_fen_{}.txt",
        std::process::id()
    ));
    let good = "OO***@**/********/******** b p p 2 7 1 8 0 0 -1 -1 -1 -1 0 0 2 ids:nodes";
    std::fs::write(
        &path,
        format!("# a comment\n\n{good}\nnot a valid fen at all\n"),
    )
    .unwrap();

    let rules = MillRules::new(MillVariantOptions::default());
    let fens = load_seed_fen_file(path.to_str().unwrap(), &rules);
    assert_eq!(fens, vec![good.to_string()]);

    let _ = std::fs::remove_file(&path);
}

/// Manual audit helper: cross-check one FEN's claimed blunder against the
/// real external database directly (bypassing the mining pipeline's
/// internals), independent of `process_item`'s own logic. Ignored by
/// default (needs the external DB); run with:
///   cargo test -p tgf-cli --release mill_mine::tests::audit_one_entry -- --ignored --nocapture
#[test]
#[ignore = "requires the external D:/user/Documents/strong database"]
fn audit_one_entry() {
    use perfect_db::database::{Database, DatabaseOptions, DatabaseVariant, FileDatabaseProvider};
    use perfect_db::evaluate_state_outcome_with_database;
    use tgf_core::ActionList;
    use tgf_mill::{MillUciCodec, MillVariantOptions};

    // Fill in a FEN copied from a real `mill mine` JSONL entry to audit it.
    let fen = "OO***@**/********/******** b p p 2 7 1 8 0 0 -1 -1 -1 -1 0 0 2 ids:nodes";
    let db_path = "D:/user/Documents/strong";

    let options = MillVariantOptions::default();
    let rules = MillRules::new(options.clone());
    let mut db = Database::open_variant_with_options(
        FileDatabaseProvider::new(db_path),
        DatabaseVariant::STANDARD,
        DatabaseOptions::with_sector_cache_capacity(8),
    )
    .unwrap();

    let state = rules.set_from_fen(fen).unwrap();
    let side = state.side_to_move();
    let root_outcome = evaluate_state_outcome_with_database(&mut db, &state, &options, side)
        .unwrap()
        .expect("root position must be covered by the full database");
    eprintln!(
        "[audit] root: wdl={} steps={}",
        root_outcome.wdl(),
        root_outcome.steps()
    );

    let snap = rules.encode_state(state.clone());
    let mut actions = ActionList::<256>::new();
    rules.legal_actions(&snap, &mut actions);
    for &action in actions.as_slice() {
        let child_snap = rules.apply(&snap, action);
        let child_state = MillRules::decode_snapshot(child_snap);
        let child_side = child_state.side_to_move();
        let outcome =
            evaluate_state_outcome_with_database(&mut db, &child_state, &options, child_side)
                .unwrap();
        let from_root_perspective = outcome.map(|o| {
            if child_side == side {
                o.wdl()
            } else {
                -o.wdl()
            }
        });
        eprintln!(
            "[audit] move {} -> child wdl (root perspective)={from_root_perspective:?}",
            MillUciCodec::encode_action(action)
        );
    }

    // depth_override left at 0 (the default) so this reproduces exactly what
    // the real `mill mine` run derived per-position via
    // `recommended_search_depth`, instead of guessing a fixed depth.
    let engine_cfg = engine::EngineConfig::default();
    let mut mining_engine = MiningEngine::new(options, engine_cfg);
    let verdict = mining_engine.evaluate(&snap);
    eprintln!("[audit] depth used: {}", verdict.depth_used);
    for action in &verdict.near_optimal {
        eprintln!(
            "[audit] engine near-optimal pick: {}",
            MillUciCodec::encode_action(*action)
        );
    }
    eprintln!("[audit] raw root move scores:");
    for summary in mining_engine.debug_root_moves() {
        eprintln!(
            "  {} value={} nodes={} cutoff={}",
            MillUciCodec::encode_action(summary.action),
            summary.value,
            summary.nodes,
            summary.cutoff
        );
    }
}

/// `--emit-steering` smoke: against the bundled subset the (Safe, drawn)
/// opening positions have many distinct value-preserving children, so a
/// tiny budgeted run must emit severity-0 steering candidates with the
/// placeholder trap_score of 0 -- and must NOT have routed them through
/// `scoring::trap_score`, whose severity assert would have panicked the
/// run outright on severity 0.
#[test]
fn emit_steering_produces_severity_zero_candidates() {
    let dir =
        std::env::temp_dir().join(format!("sanmill_mill_mine_steering_{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let db = bundled_asset_root();
    let out = dir.join("entries.jsonl");
    let checkpoint = dir.join("checkpoint.json");
    let argv = args(
        &[
            ("--db", db.as_str()),
            ("--out", out.to_str().unwrap()),
            ("--checkpoint", checkpoint.to_str().unwrap()),
            ("--max-depth-plies", "2"),
            ("--budget-engine-calls", "20"),
            ("--workers", "1"),
            ("--depth", "3"),
            ("--steering-min-mass", "1"),
        ],
        &["--emit-steering"],
    );
    run_mill_mine(&argv);

    let text = std::fs::read_to_string(&out).unwrap();
    let entries: Vec<MineEntry> = text
        .lines()
        .map(|line| serde_json::from_str(line).expect("valid JSONL"))
        .collect();
    let steering: Vec<&MineEntry> = entries.iter().filter(|e| e.severity == 0).collect();
    assert!(
        !steering.is_empty(),
        "the drawn opening must yield at least one steering candidate"
    );
    for entry in &steering {
        assert_eq!(
            entry.trap_score, 0,
            "steering trap_score is a 0 placeholder"
        );
        assert_ne!(entry.key, entry.best_child);
        assert!(entry.mass >= 1.0, "the --steering-min-mass gate applies");
    }
    for entry in &entries {
        assert!((0..=2).contains(&entry.severity));
    }

    // The checkpoint written by a steering run carries a fingerprint that
    // records the steering configuration, plus the running emission total.
    let (fingerprint, emitted, _, _) = load_checkpoint(checkpoint.to_str().unwrap());
    let fingerprint = fingerprint.expect("new checkpoints must carry a fingerprint");
    assert!(fingerprint.emit_steering);
    assert_eq!(fingerprint.steering_min_mass, 1.0);
    assert_eq!(
        fingerprint.checkpoint_schema_version,
        CHECKPOINT_SCHEMA_VERSION
    );
    assert_eq!(
        emitted as usize,
        steering.len(),
        "the checkpoint must persist the emission total"
    );

    let _ = std::fs::remove_dir_all(&dir);
}

/// `--steering-max-entries` caps settled and mid-removal steering globally
/// while leaving blunder emission untouched: an identically-budgeted,
/// single-worker (deterministic) run with the cap must produce exactly the
/// same severity>0 lines and at most the capped number of severity-0
/// lines.
#[test]
fn steering_max_entries_caps_candidates_but_not_blunders() {
    let dir = std::env::temp_dir().join(format!(
        "sanmill_mill_mine_steering_cap_{}",
        std::process::id()
    ));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let db = bundled_asset_root();

    let run = |suffix: &str, cap: Option<&str>| {
        let out = dir.join(format!("entries_{suffix}.jsonl"));
        let checkpoint = dir.join(format!("checkpoint_{suffix}.json"));
        let mut pairs = vec![
            ("--db", db.to_string()),
            ("--out", out.to_str().unwrap().to_string()),
            ("--checkpoint", checkpoint.to_str().unwrap().to_string()),
            ("--max-depth-plies", "3".to_string()),
            ("--budget-engine-calls", "20".to_string()),
            ("--workers", "1".to_string()),
            ("--depth", "3".to_string()),
            ("--steering-min-mass", "1".to_string()),
        ];
        if let Some(cap) = cap {
            pairs.push(("--steering-max-entries", cap.to_string()));
        }
        let mut argv: Vec<String> = Vec::new();
        for (flag, value) in &pairs {
            argv.push((*flag).to_string());
            argv.push(value.clone());
        }
        argv.push("--emit-steering".to_string());
        run_mill_mine(&argv);
        std::fs::read_to_string(&out).unwrap_or_default()
    };

    let uncapped = run("uncapped", None);
    let capped = run("capped", Some("1"));

    let parse = |text: &str| -> (Vec<String>, usize) {
        let mut blunder_lines = Vec::new();
        let mut steering_count = 0_usize;
        for line in text.lines() {
            let entry: MineEntry = serde_json::from_str(line).expect("valid JSONL");
            if entry.severity == 0 {
                steering_count += 1;
            } else {
                blunder_lines.push(line.to_string());
            }
        }
        (blunder_lines, steering_count)
    };
    let (uncapped_blunders, uncapped_steering) = parse(&uncapped);
    let (capped_blunders, capped_steering) = parse(&capped);

    assert!(
        uncapped_steering > 1,
        "the uncapped run must emit multiple steering candidates for the cap to bite \
         (got {uncapped_steering})"
    );
    assert_eq!(
        capped_steering, 1,
        "the cap must stop steering emission at 1"
    );
    assert_eq!(
        uncapped_blunders, capped_blunders,
        "blunder emission must be unaffected by the steering cap"
    );

    let _ = std::fs::remove_dir_all(&dir);
}

/// `--steering-max-entries` is a *global* cap: a resumed run restores the
/// persisted emission total from the checkpoint, so the combined output of
/// the original run plus every resume never exceeds the cap (regression:
/// the counter used to reset per process, letting each resume emit a full
/// cap's worth again).
#[test]
fn steering_cap_holds_across_resume() {
    let dir = std::env::temp_dir().join(format!(
        "sanmill_mill_mine_steering_resume_{}",
        std::process::id()
    ));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let db = bundled_asset_root();
    let out = dir.join("entries.jsonl");
    let checkpoint = dir.join("checkpoint.json");

    // Identical configuration (fingerprint-relevant flags) across both
    // runs; only the engine-call budget grows, which is a legitimate
    // resume. The cap is 1 and the first run already exhausts it.
    let base_argv = |budget: &str| {
        args(
            &[
                ("--db", db.as_str()),
                ("--out", out.to_str().unwrap()),
                ("--checkpoint", checkpoint.to_str().unwrap()),
                ("--max-depth-plies", "3"),
                ("--budget-engine-calls", budget),
                ("--workers", "1"),
                ("--depth", "3"),
                ("--steering-min-mass", "1"),
                ("--steering-max-entries", "1"),
            ],
            &["--emit-steering"],
        )
    };

    run_mill_mine(&base_argv("5"));
    let count_steering = || -> usize {
        std::fs::read_to_string(&out)
            .unwrap_or_default()
            .lines()
            .map(|line| serde_json::from_str::<MineEntry>(line).expect("valid JSONL"))
            .filter(|entry| entry.severity == 0)
            .count()
    };
    assert_eq!(
        count_steering(),
        1,
        "the first run must already exhaust the cap"
    );

    let mut resumed = base_argv("15");
    resumed.push("--resume".to_string());
    run_mill_mine(&resumed);
    assert_eq!(
        count_steering(),
        1,
        "a resumed run must not emit past the global cap"
    );

    let (_, emitted, _, _) = load_checkpoint(checkpoint.to_str().unwrap());
    assert_eq!(emitted, 1, "the persisted total must survive the resume");

    let _ = std::fs::remove_dir_all(&dir);
}

/// The resume gate: a missing fingerprint (pre-fingerprint checkpoint) and
/// every mismatched field must be rejected. Field-by-field coverage is
/// spot-checked here; the exhaustive guarantee comes from
/// `#[derive(PartialEq)]` on the struct, which compares every field.
#[test]
fn checkpoint_fingerprint_gate_rejects_absence_and_mismatch() {
    let current = CheckpointFingerprint {
        checkpoint_schema_version: CHECKPOINT_SCHEMA_VERSION,
        emit_steering: true,
        variant: "std".to_string(),
        engine_algorithm: "mtdf".to_string(),
        skill_level: 30,
        depth_override: 3,
        near_optimal_margin: 0,
        top_k: 3,
        epsilon: 0.15,
        seed_phase: "All".to_string(),
        placing_only: false,
        max_depth_plies: 2,
        root_mass: 1.0e6,
        human_db_path: String::new(),
        human_db_sha256: String::new(),
        seed_fen_file_path: String::new(),
        seed_fen_file_sha256: String::new(),
        seed_fen_mass: 1.0e5,
        steering_min_mass: 1.0,
        steering_max_entries: 0,
    };

    assert!(
        validate_checkpoint_fingerprint(None, &current)
            .expect_err("missing fingerprint must be rejected")
            .contains("no fingerprint"),
    );
    validate_checkpoint_fingerprint(Some(&current.clone()), &current)
        .expect("an identical fingerprint must resume");

    let mutations: Vec<CheckpointFingerprint> = vec![
        CheckpointFingerprint {
            checkpoint_schema_version: CHECKPOINT_SCHEMA_VERSION + 1,
            ..current.clone()
        },
        CheckpointFingerprint {
            emit_steering: false,
            ..current.clone()
        },
        CheckpointFingerprint {
            variant: "lask".to_string(),
            ..current.clone()
        },
        CheckpointFingerprint {
            skill_level: 15,
            ..current.clone()
        },
        CheckpointFingerprint {
            depth_override: 5,
            ..current.clone()
        },
        CheckpointFingerprint {
            epsilon: 0.2,
            ..current.clone()
        },
        CheckpointFingerprint {
            seed_phase: "Placing".to_string(),
            ..current.clone()
        },
        CheckpointFingerprint {
            root_mass: 2.0e6,
            ..current.clone()
        },
        CheckpointFingerprint {
            human_db_sha256: "deadbeef".to_string(),
            ..current.clone()
        },
        CheckpointFingerprint {
            seed_fen_file_path: "seeds.txt".to_string(),
            ..current.clone()
        },
        CheckpointFingerprint {
            steering_min_mass: 5.0,
            ..current.clone()
        },
        CheckpointFingerprint {
            steering_max_entries: 100,
            ..current.clone()
        },
    ];
    for stale in mutations {
        assert!(
            validate_checkpoint_fingerprint(Some(&stale), &current)
                .expect_err("any field mismatch must be rejected")
                .contains("does not match"),
        );
    }
}

/// A checkpoint from before the fingerprint schema (bare visited/frontier
/// JSON) must still parse -- and must then be rejected by the resume gate.
#[test]
fn pre_fingerprint_checkpoint_parses_but_cannot_resume() {
    let path = std::env::temp_dir().join(format!(
        "sanmill_mill_mine_old_checkpoint_{}.json",
        std::process::id()
    ));
    std::fs::write(&path, r#"{"visited":[[42,"Safe"]],"frontier":[]}"#).unwrap();

    let (fingerprint, emitted, visited, frontier) = load_checkpoint(path.to_str().unwrap());
    assert!(fingerprint.is_none());
    assert_eq!(emitted, 0, "pre-schema checkpoints default the counter");
    assert_eq!(visited.len(), 1);
    assert!(frontier.is_empty());

    let current = CheckpointFingerprint {
        checkpoint_schema_version: CHECKPOINT_SCHEMA_VERSION,
        emit_steering: false,
        variant: "std".to_string(),
        engine_algorithm: "mtdf".to_string(),
        skill_level: 30,
        depth_override: 0,
        near_optimal_margin: 0,
        top_k: 3,
        epsilon: 0.15,
        seed_phase: "All".to_string(),
        placing_only: false,
        max_depth_plies: 0,
        root_mass: 1.0e6,
        human_db_path: String::new(),
        human_db_sha256: String::new(),
        seed_fen_file_path: String::new(),
        seed_fen_file_sha256: String::new(),
        seed_fen_mass: 1.0e5,
        steering_min_mass: 0.0,
        steering_max_entries: 0,
    };
    assert!(validate_checkpoint_fingerprint(fingerprint.as_ref(), &current).is_err());

    let _ = std::fs::remove_file(&path);
}

/// The content hash must be a real SHA-256 over the full file bytes (the
/// known test vectors), never an mtime/size stand-in.
#[test]
fn sha256_file_hex_matches_known_vectors() {
    let dir = std::env::temp_dir();
    let empty = dir.join(format!("sanmill_sha_empty_{}.bin", std::process::id()));
    let abc = dir.join(format!("sanmill_sha_abc_{}.bin", std::process::id()));
    std::fs::write(&empty, b"").unwrap();
    std::fs::write(&abc, b"abc").unwrap();

    assert_eq!(
        sha256_file_hex(empty.to_str().unwrap()),
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    );
    assert_eq!(
        sha256_file_hex(abc.to_str().unwrap()),
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    );

    let _ = std::fs::remove_file(&empty);
    let _ = std::fs::remove_file(&abc);
}

/// Blocker-bug sweep for the H2H color-split investigation: replay
/// `trap_aware_action` on thousands of real mined positions (their FENs)
/// against the packed steering asset, and verify with the full external
/// database that EVERY switched-to move is still DB-optimal -- i.e. the
/// runtime child indexing, canonicalization, and mask orientation agree
/// with the packer on live data, not just on constructed fixtures. A
/// single value-dropping switch is a blocking bug.
///
/// Ignored by default (needs the external strong DB and a packed steering
/// patch); run with:
///   cargo test -p tgf-cli --release mill_mine::tests::steering_switches_never_drop_value -- --ignored --nocapture
#[test]
#[ignore = "requires the external strong DB and packed steering artifacts (see env vars)"]
fn steering_switches_never_drop_value() {
    use perfect_db::patch::PatchLookup;
    use tgf_core::ActionList;
    use tgf_mill::MillUciCodec;

    // Paths are env-overridable so the probe runs on any machine hosting
    // the artifacts (defaults match this repo's Windows dev box).
    let env_or = |name: &str, default: &str| std::env::var(name).unwrap_or_else(|_| default.into());
    let db_root = env_or("SANMILL_STRONG_DB", "D:/user/Documents/strong");
    let patch_path = env_or(
        "SANMILL_STEERING_PATCH",
        "target/steering_run/std_v4_steering.mill_patch",
    );
    let jsonl_path = env_or(
        "SANMILL_STEERING_JSONL",
        "target/steering_run/steering_entries_clean.jsonl",
    );
    let sample_cap = 4000_usize;

    let options = MillVariantOptions::default();
    let rules = MillRules::new(options.clone());
    let bytes = std::fs::read(&patch_path).expect("packed steering patch present");
    let mut lookup = PatchLookup::open(&bytes).expect("patch must open");

    let provider =
        perfect_db::database::FileDatabaseProvider::new(std::path::PathBuf::from(&db_root));
    let mut planes = perfect_db::wdl_plane::WdlPlaneCache::new(provider, DatabaseVariant::STANDARD)
        .expect("strong DB plane cache");

    let text = std::fs::read_to_string(&jsonl_path).expect("steering JSONL present");
    // Seeded random sample over the WHOLE file (not a first-N prefix,
    // which would only ever exercise the earliest-mined region). This is
    // still a smoke-strength argument, not an exhaustive proof.
    let lines: Vec<&str> = text.lines().filter(|l| !l.trim().is_empty()).collect();
    let picked: Vec<&str> = {
        let mut state = 0x5EED_CAFE_u64 | 1;
        let mut indices = std::collections::BTreeSet::new();
        while indices.len() < sample_cap.min(lines.len()) {
            state ^= state << 13;
            state ^= state >> 7;
            state ^= state << 17;
            indices.insert((state % lines.len() as u64) as usize);
        }
        indices.into_iter().map(|i| lines[i]).collect()
    };
    let mut checked = 0_usize;
    let mut switched = 0_usize;
    let mut failures: Vec<String> = Vec::new();

    for line in picked {
        let entry: MineEntry = serde_json::from_str(line).expect("valid JSONL");
        let Ok(mut state) = rules.set_from_fen(&entry.fen) else {
            continue;
        };
        state.reset_ply_since_capture();
        let snap = rules.encode_state(state);
        let Ok(Some(move_wdl)) = all_move_wdl_fast(&mut planes, &rules, &snap, &options) else {
            continue;
        };
        if move_wdl.is_empty() {
            continue;
        }
        let best_value = move_wdl.iter().map(|&(_, v)| v).max().expect("non-empty");
        checked += 1;

        let mut legal = ActionList::<256>::new();
        rules.legal_actions(&snap, &mut legal);
        // Drive the exact runtime path from every optimal baseline the
        // engine could have chosen.
        for &(action, value) in &move_wdl {
            if value != best_value {
                continue;
            }
            let Some(better) = lookup.trap_aware_action(&rules, &options, &snap, action) else {
                continue;
            };
            switched += 1;
            let switched_value = move_wdl
                .iter()
                .find(|(a, _)| *a == better)
                .map(|&(_, v)| v)
                .unwrap_or_else(|| panic!("switched-to action must be legal (fen {})", entry.fen));
            if switched_value != best_value {
                failures.push(format!(
                    "fen {:?}: switch {:?} -> {:?} dropped value {} -> {}",
                    entry.fen,
                    MillUciCodec::encode_action(action),
                    MillUciCodec::encode_action(better),
                    best_value,
                    switched_value
                ));
            }
        }
    }

    eprintln!(
        "[probe] positions_checked={checked} switches_verified={switched} failures={}",
        failures.len()
    );
    assert!(
        failures.is_empty(),
        "make-traps switched to value-dropping moves:\n{}",
        failures.join("\n")
    );
    assert!(
        switched > 0,
        "the sweep must actually exercise switches to prove anything"
    );
}

#[test]
fn output_file_lines_are_all_parseable_jsonl() {
    let dir = std::env::temp_dir().join(format!("sanmill_mill_mine_jsonl_{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let db = bundled_asset_root();
    let out = dir.join("entries.jsonl");
    let checkpoint = dir.join("checkpoint.json");
    let argv = args(
        &[
            ("--db", db.as_str()),
            ("--out", out.to_str().unwrap()),
            ("--checkpoint", checkpoint.to_str().unwrap()),
            ("--max-depth-plies", "3"),
            ("--budget-engine-calls", "40"),
            ("--workers", "3"),
            ("--depth", "3"),
        ],
        &[],
    );
    run_mill_mine(&argv);

    let file = std::fs::File::open(&out).unwrap();
    let mut count = 0;
    for line in std::io::BufReader::new(file).lines() {
        let line = line.unwrap();
        let _entry: MineEntry =
            serde_json::from_str(&line).expect("every line must be one JSON object");
        count += 1;
    }
    eprintln!("[test] {count} entries emitted with 3 workers");

    let _ = std::fs::remove_dir_all(&dir);
}
