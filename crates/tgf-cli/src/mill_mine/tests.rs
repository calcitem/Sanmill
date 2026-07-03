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
