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

/// Verify a captured H2H patchtrap trace (TGF_PATCH_TRACE_DIR output)
/// against the full external database: for every traced switch, BOTH the
/// baseline and the steering move must be tied-best in the parent
/// position. A steering move below best is the blocking-bug signature; a
/// baseline below best would mean the packed optimal_mask carries a false
/// positive. Fail-fast with the offending rows.
///
///   SANMILL_STRONG_DB=... SANMILL_TRACE_DIR=... \
///   cargo test -p tgf-cli --release mill_mine::tests::patchtrap_trace_rows_stay_tied_best -- --ignored --nocapture
#[test]
#[ignore = "requires the external strong DB and a captured trace directory"]
fn patchtrap_trace_rows_stay_tied_best() {
    use tgf_mill::MillUciCodec;

    let env_or = |name: &str, default: &str| std::env::var(name).unwrap_or_else(|_| default.into());
    let db_root = env_or("SANMILL_STRONG_DB", "D:/user/Documents/strong");
    // Tests run with the crate directory as cwd; resolve workspace
    // -relative defaults against the workspace root.
    let workspace = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let trace_dir = {
        let raw = env_or("SANMILL_TRACE_DIR", "target/steering_run/trace");
        let candidate = std::path::PathBuf::from(&raw);
        if candidate.is_dir() {
            candidate
        } else {
            workspace.join(&raw)
        }
    };

    let options = MillVariantOptions::default();
    let rules = MillRules::new(options.clone());
    let provider =
        perfect_db::database::FileDatabaseProvider::new(std::path::PathBuf::from(&db_root));
    let mut planes = perfect_db::wdl_plane::WdlPlaneCache::new(provider, DatabaseVariant::STANDARD)
        .expect("strong DB plane cache");

    let mut rows = 0_usize;
    let mut failures: Vec<String> = Vec::new();
    let mut unresolved = 0_usize;
    for entry in std::fs::read_dir(&trace_dir).expect("trace dir must exist") {
        let path = entry.expect("dir entry").path();
        if path.extension().and_then(|e| e.to_str()) != Some("jsonl") {
            continue;
        }
        for line in std::fs::read_to_string(&path)
            .expect("trace file readable")
            .lines()
            .filter(|l| !l.trim().is_empty())
        {
            let row: serde_json::Value = serde_json::from_str(line).expect("valid trace JSONL");
            rows += 1;
            let fen = row["parent_fen"].as_str().expect("parent_fen");
            let state = rules.set_from_fen(fen).expect("trace FEN must parse");
            let snap = rules.encode_state(state);
            let Ok(Some(move_wdl)) = all_move_wdl_fast(&mut planes, &rules, &snap, &options) else {
                unresolved += 1;
                continue;
            };
            let best = move_wdl.iter().map(|&(_, v)| v).max().expect("non-empty");
            let value_of = |token: &str| -> Option<i8> {
                move_wdl
                    .iter()
                    .find(|(a, _)| MillUciCodec::encode_action(*a) == token)
                    .map(|&(_, v)| v)
            };
            for field in ["baseline_action", "steering_action"] {
                let token = row[field].as_str().expect("action token");
                match value_of(token) {
                    Some(value) if value == best => {}
                    Some(value) => failures.push(format!(
                        "{field} {token} has value {value} < best {best} (tag {}, fen {fen})",
                        row["trace_tag"]
                    )),
                    None => failures.push(format!(
                        "{field} {token} is not legal in the traced parent (tag {}, fen {fen})",
                        row["trace_tag"]
                    )),
                }
            }
        }
    }
    eprintln!(
        "[trace-verify] rows={rows} unresolved={unresolved} failures={}",
        failures.len()
    );
    assert!(rows > 0, "the trace directory must contain rows to verify");
    assert_eq!(
        unresolved, 0,
        "every traced position must be DB-resolvable for the verdict to count"
    );
    assert!(
        failures.is_empty(),
        "traced switches broke value preservation:\n{}",
        failures.join("\n")
    );
}

/// Self-risk probe over a captured patchtrap trace, joined against the
/// H2H game log: emits `enhanced_switch_metrics.jsonl`, one row per
/// traced make-traps switch.
///
/// Layering rules (fixed by review):
/// * baseline/steering WDL and steps come from the PARENT's
///   `all_move_outcomes_with_ordering` row (never a direct precise-DB
///   probe of the child, which has no entry for mid-removal children);
///   a traced move missing from the parent's outcome list is fail-fast.
/// * A child that keeps the mover on turn is flagged `same_side_child`
///   and excluded from trap/self-risk aggregation (reported separately;
///   a same-side STEERING child would mean the packer's perspective
///   filter leaked and fails the probe).
/// * Trap payoff uses the packer's uniform density formula
///   `sum(max(0, best_reply - reply)) / (2 * reply_count)` on
///   side-flipped children only.
/// * `naive_grandchild_density` (formerly misnamed `own_risk`) walks the
///   opponent's value-preserving replies, applies each, and measures the
///   same density formula at whatever node that lands on -- WITHOUT
///   checking whose turn it is there (a mill-forming preserving reply
///   leaves the OPPONENT on turn, so the measured density is theirs, not
///   ours). It stays here as a diagnostic only; the packer's risk gate
///   uses the corrected own-TURN risk
///   (`mill_pack::recompute::RiskMemo::own_turn_risk`), which resolves
///   the pending-removal layer before measuring. Zero preserving replies
///   yields `null` fields plus a separate counter -- never a fake-safe 0.
///
///   SANMILL_STRONG_DB=... SANMILL_TRACE_DIR=... SANMILL_GAME_LOG=...
///   SANMILL_SELF_RISK_OUT=...
///   cargo test -p tgf-cli --release mill_mine::tests::self_risk_probe_over_trace -- --ignored --nocapture
#[test]
#[ignore = "requires the external strong DB, a captured trace, and the H2H game log"]
fn self_risk_probe_over_trace() {
    use tgf_mill::MillUciCodec;

    let env_or = |name: &str, default: &str| std::env::var(name).unwrap_or_else(|_| default.into());
    let db_root = env_or("SANMILL_STRONG_DB", "D:/user/Documents/strong");
    let workspace = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let resolve = |raw: String| -> std::path::PathBuf {
        let candidate = std::path::PathBuf::from(&raw);
        if candidate.is_absolute() {
            candidate
        } else {
            workspace.join(&raw)
        }
    };
    let trace_dir = resolve(env_or("SANMILL_TRACE_DIR", "target/steering_run/trace"));
    let game_log_path = resolve(env_or(
        "SANMILL_GAME_LOG",
        "target/steering_run/paired_c_avoidmake_games.jsonl",
    ));
    let out_path = resolve(env_or(
        "SANMILL_SELF_RISK_OUT",
        "target/steering_run/enhanced_switch_metrics.jsonl",
    ));

    // game_index -> full game-log row (current_white/result/opening/moves).
    let mut games: std::collections::HashMap<u64, serde_json::Value> =
        std::collections::HashMap::new();
    for line in std::fs::read_to_string(&game_log_path)
        .expect("game log readable")
        .lines()
        .filter(|l| !l.trim().is_empty())
    {
        let g: serde_json::Value = serde_json::from_str(line).expect("valid game log JSONL");
        games.insert(g["game_index"].as_u64().expect("game_index"), g);
    }

    let options = MillVariantOptions::default();
    let rules = MillRules::new(options.clone());
    let provider =
        perfect_db::database::FileDatabaseProvider::new(std::path::PathBuf::from(&db_root));
    let mut db = Database::open_variant_with_options(
        provider.clone(),
        DatabaseVariant::STANDARD,
        DatabaseOptions::with_sector_cache_capacity(128),
    )
    .expect("strong DB");
    let mut planes = perfect_db::wdl_plane::WdlPlaneCache::new(provider, DatabaseVariant::STANDARD)
        .expect("strong DB plane cache");

    fn percentile_90(sorted: &[f64]) -> f64 {
        if sorted.is_empty() {
            return 0.0;
        }
        let rank = ((sorted.len() as f64) * 0.9).ceil() as usize;
        sorted[rank.saturating_sub(1).min(sorted.len() - 1)]
    }

    /// The packer's uniform density formula over one reply list.
    fn density(replies: &[(tgf_core::Action, i8)]) -> f64 {
        if replies.is_empty() {
            return 0.0;
        }
        let best = replies.iter().map(|&(_, v)| v).max().expect("non-empty");
        let severity_sum: f64 = replies
            .iter()
            .map(|&(_, v)| f64::from((i32::from(best) - i32::from(v)).max(0) as u8))
            .sum();
        severity_sum / (2.0 * replies.len() as f64)
    }

    /// Side-flipped child probe: trap payoff + the naive one-reply-deep
    /// density (mean, max, p90, samples; `None` when the opponent has no
    /// value-preserving reply). See the test doc: this is a diagnostic,
    /// NOT the packer gate's own-turn risk.
    struct FlippedChildMetrics {
        legal_reply_count: usize,
        preserving_reply_count: usize,
        trap_density: f64,
        naive_grandchild_density: Option<(f64, f64, f64, usize)>,
    }

    fn flipped_child_metrics(
        rules: &MillRules,
        options: &MillVariantOptions,
        planes: &mut perfect_db::wdl_plane::WdlPlaneCache<FileDatabaseProvider>,
        child_snap: &tgf_core::GameStateSnapshot,
    ) -> FlippedChildMetrics {
        let replies = all_move_wdl_fast(planes, rules, child_snap, options)
            .expect("plane read")
            .unwrap_or_default();
        if replies.is_empty() {
            return FlippedChildMetrics {
                legal_reply_count: 0,
                preserving_reply_count: 0,
                trap_density: 0.0,
                naive_grandchild_density: None,
            };
        }
        let best_reply = replies.iter().map(|&(_, v)| v).max().expect("non-empty");
        let preserving: Vec<tgf_core::Action> = replies
            .iter()
            .filter(|&&(_, v)| v == best_reply)
            .map(|&(a, _)| a)
            .collect();
        let trap_density = density(&replies);
        let mut risks: Vec<f64> = Vec::with_capacity(preserving.len());
        for &reply in &preserving {
            let grand_snap = rules.apply(child_snap, reply);
            let Ok(Some(ours)) = all_move_wdl_fast(planes, rules, &grand_snap, options) else {
                continue;
            };
            if ours.is_empty() {
                continue;
            }
            risks.push(density(&ours));
        }
        risks.sort_by(|a, b| a.partial_cmp(b).expect("finite"));
        let naive_grandchild_density = (!risks.is_empty()).then(|| {
            let mean = risks.iter().sum::<f64>() / risks.len() as f64;
            let max = *risks.last().expect("non-empty");
            (mean, max, percentile_90(&risks), risks.len())
        });
        FlippedChildMetrics {
            legal_reply_count: replies.len(),
            preserving_reply_count: preserving.len(),
            trap_density,
            naive_grandchild_density,
        }
    }

    fn side_metrics_json(metrics: &Option<FlippedChildMetrics>) -> serde_json::Value {
        match metrics {
            None => serde_json::Value::Null,
            Some(m) => {
                let (mean, max, p90, samples) = match m.naive_grandchild_density {
                    Some((mean, max, p90, samples)) => (
                        serde_json::json!(mean),
                        serde_json::json!(max),
                        serde_json::json!(p90),
                        serde_json::json!(samples),
                    ),
                    None => (
                        serde_json::Value::Null,
                        serde_json::Value::Null,
                        serde_json::Value::Null,
                        serde_json::json!(0),
                    ),
                };
                serde_json::json!({
                    "legal_reply_count": m.legal_reply_count,
                    "preserving_reply_count": m.preserving_reply_count,
                    "preserving_reply_ratio": if m.legal_reply_count == 0 {
                        0.0
                    } else {
                        m.preserving_reply_count as f64 / m.legal_reply_count as f64
                    },
                    "trap_density": m.trap_density,
                    "naive_grandchild_density_mean": mean,
                    "naive_grandchild_density_max": max,
                    "naive_grandchild_density_p90": p90,
                    "naive_grandchild_density_samples": samples,
                })
            }
        }
    }

    let mut out = std::io::BufWriter::new(
        std::fs::File::create(&out_path).expect("self-risk output must be creatable"),
    );
    let mut rows = 0_usize;
    let mut baseline_same_side = 0_usize;
    let mut no_preserving_replies = 0_usize;
    for entry in std::fs::read_dir(&trace_dir).expect("trace dir must exist") {
        let path = entry.expect("dir entry").path();
        if path.extension().and_then(|e| e.to_str()) != Some("jsonl") {
            continue;
        }
        for line in std::fs::read_to_string(&path)
            .expect("trace file readable")
            .lines()
            .filter(|l| !l.trim().is_empty())
        {
            let row: serde_json::Value = serde_json::from_str(line).expect("valid trace JSONL");
            let fen = row["parent_fen"].as_str().expect("parent_fen");
            let tag = row["trace_tag"].as_str().expect("trace_tag");
            let (game_index, current_white_tag) = {
                let caps = tag
                    .strip_prefix("gi")
                    .and_then(|rest| rest.split_once("cw"))
                    .expect("tag must be gi<index>cw<0|1>");
                (caps.0.parse::<u64>().expect("game index"), caps.1 == "1")
            };
            let game = games
                .get(&game_index)
                .unwrap_or_else(|| panic!("trace tag {tag} has no game log row"));
            assert_eq!(
                game["current_white"].as_bool().expect("current_white"),
                current_white_tag,
                "tag colour must agree with the game log (tag {tag})"
            );

            let state = rules.set_from_fen(fen).expect("trace FEN must parse");
            let parent_side = state.side_to_move();
            let snap = rules.encode_state(state);
            let mut legal = tgf_core::ActionList::<256>::new();
            rules.legal_actions(&snap, &mut legal);
            let action_by_token = |token: &str| -> tgf_core::Action {
                legal
                    .as_slice()
                    .iter()
                    .copied()
                    .find(|&a| MillUciCodec::encode_action(a) == token)
                    .unwrap_or_else(|| panic!("traced action {token} must be legal (fen {fen})"))
            };
            let baseline_token = row["baseline_action"].as_str().expect("baseline");
            let steering_token = row["steering_action"].as_str().expect("steering");
            let baseline_action = action_by_token(baseline_token);
            let steering_action = action_by_token(steering_token);

            // WDL/steps strictly from the parent's per-move outcome list.
            let per_move = perfect_db::all_move_outcomes_with_ordering(
                &mut db,
                &rules,
                &snap,
                &options,
                perfect_db::PerfectMoveOrdering::StrictSteps,
            )
            .expect("DB read")
            .expect("traced parents must be covered");
            let parent_best_wdl = per_move
                .iter()
                .map(|choice| choice.outcome.wdl())
                .max()
                .expect("non-empty");
            let outcome_of = |token: &str| -> (i32, i32) {
                let choice = per_move
                    .iter()
                    .find(|choice| choice.token == token)
                    .unwrap_or_else(|| {
                        panic!("traced action {token} missing from parent DB outcomes (fen {fen})")
                    });
                (choice.outcome.wdl(), choice.outcome.steps())
            };
            let (baseline_wdl, baseline_steps) = outcome_of(baseline_token);
            let (steering_wdl, steering_steps) = outcome_of(steering_token);
            let baseline_is_tied_best = baseline_wdl == parent_best_wdl;
            let steering_is_tied_best = steering_wdl == parent_best_wdl;
            assert!(
                baseline_is_tied_best && steering_is_tied_best,
                "non-tied-best traced move (tag {tag}, fen {fen}): baseline {baseline_wdl} steering {steering_wdl} best {parent_best_wdl}"
            );

            // Child layering: same-side children are excluded from
            // trap/self-risk metrics (reported separately).
            let child_of = |action: tgf_core::Action| -> (tgf_core::GameStateSnapshot, bool) {
                let child_snap = rules.apply(&snap, action);
                let child_state = MillRules::decode_snapshot(child_snap);
                let same_side = child_state.side_to_move() == parent_side;
                (child_snap, same_side)
            };
            let (baseline_child, baseline_same) = child_of(baseline_action);
            let (steering_child, steering_same) = child_of(steering_action);
            if baseline_same {
                baseline_same_side += 1;
            }
            // A same-side steering child can only come from a leaked
            // perspective filter: fail fast with the offending row.
            assert!(
                !steering_same,
                "same-side STEERING child (perspective filter leak): trace_tag={tag} \
                 fen={fen} baseline={baseline_token} steering={steering_token}"
            );
            let baseline_metrics = (!baseline_same)
                .then(|| flipped_child_metrics(&rules, &options, &mut planes, &baseline_child));
            let steering_metrics = (!steering_same)
                .then(|| flipped_child_metrics(&rules, &options, &mut planes, &steering_child));
            if let Some(m) = steering_metrics.as_ref()
                && m.preserving_reply_count == 0
            {
                no_preserving_replies += 1;
            }

            let baseline_nibble = row["baseline_nibble"].as_u64().expect("nibble");
            let steering_nibble = row["steering_nibble"].as_u64().expect("nibble");
            let trap_density_delta = match (&baseline_metrics, &steering_metrics) {
                (Some(b), Some(s)) => serde_json::json!(s.trap_density - b.trap_density),
                _ => serde_json::Value::Null,
            };
            let naive_grandchild_density_delta = match (&baseline_metrics, &steering_metrics) {
                (Some(b), Some(s)) => {
                    match (b.naive_grandchild_density, s.naive_grandchild_density) {
                        (Some((bm, ..)), Some((sm, ..))) => serde_json::json!(sm - bm),
                        _ => serde_json::Value::Null,
                    }
                }
                _ => serde_json::Value::Null,
            };

            let enriched = serde_json::json!({
                "trace_tag": tag,
                "game_index": game_index,
                "current_white": current_white_tag,
                "result": game["result"],
                "opening_moves": game["opening_moves"],
                "ply": row["ply"],
                "parent_fen": fen,
                "parent_key": row["parent_key"],
                "baseline_action": baseline_token,
                "steering_action": steering_token,
                "baseline_nibble": baseline_nibble,
                "steering_nibble": steering_nibble,
                "trap_gain": steering_nibble as i64 - baseline_nibble as i64,
                "parent_best_wdl": parent_best_wdl,
                "baseline_wdl": baseline_wdl,
                "baseline_steps": baseline_steps,
                "steering_wdl": steering_wdl,
                "steering_steps": steering_steps,
                "baseline_is_tied_best": baseline_is_tied_best,
                "steering_is_tied_best": steering_is_tied_best,
                "baseline_same_side_child": baseline_same,
                "steering_same_side_child": steering_same,
                "baseline_metrics": side_metrics_json(&baseline_metrics),
                "steering_metrics": side_metrics_json(&steering_metrics),
                "trap_density_delta": trap_density_delta,
                "naive_grandchild_density_delta": naive_grandchild_density_delta,
            });
            use std::io::Write;
            writeln!(out, "{enriched}").expect("self-risk row write");
            rows += 1;
        }
    }
    use std::io::Write;
    out.flush().expect("flush self-risk output");
    eprintln!(
        "[self-risk] rows={rows} baseline_same_side_bucket={baseline_same_side} steering_no_preserving={no_preserving_replies} -> {}",
        out_path.display()
    );
    assert!(rows > 0, "the probe needs trace rows to analyze");
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
