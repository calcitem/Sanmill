// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

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

/// End-to-end smoke test against the bundled `3v3` endgame sector (the
/// smallest full sector shipped for tests, `hash_count` in the low
/// hundred-thousands -- too slow to sweep exhaustively in a debug-mode
/// unit test, hence `--max-slots-per-sector` for a fast spot-check of the
/// exact same code path). Must produce well-formed entries, and a
/// truncated run must *not* checkpoint the sector as done.
#[test]
fn endgame_spot_checks_the_bundled_3v3_sector() {
    let dir =
        std::env::temp_dir().join(format!("sanmill_mill_endgame_test_{}", std::process::id()));
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
            ("--min-total-pieces", "6"),
            ("--max-total-pieces", "6"),
            ("--min-side-pieces", "3"),
            ("--workers", "4"),
            ("--depth", "3"),
            ("--max-slots-per-sector", "500"),
        ],
        &[],
    );
    run_mill_endgame(&argv);

    let text = std::fs::read_to_string(&out).unwrap_or_default();
    assert!(
        !text.is_empty(),
        "the first 500 slots of the bundled 3v3 sector must yield at least one blunder entry"
    );
    let mut count = 0_usize;
    for line in text.lines() {
        let entry: MineEntry = serde_json::from_str(line).expect("entry must be valid JSON");
        assert!((1..=2).contains(&entry.severity));
        assert_eq!(entry.mass, 1.0, "default --mass must be stamped verbatim");
        assert_ne!(entry.key, entry.best_child);
        assert!(!entry.fen.is_empty());
        count += 1;
    }
    assert!(count > 0);

    // A truncated (spot-check) sweep must not claim the sector is done.
    let done = load_checkpoint(checkpoint.to_str().unwrap());
    assert!(
        done.is_empty(),
        "a --max-slots-per-sector run must never checkpoint a sector as complete"
    );

    run_mill_endgame(&argv);
    let text_after_rerun = std::fs::read_to_string(&out).unwrap();
    assert_eq!(
        text.lines().count() * 2,
        text_after_rerun.lines().count(),
        "an uncheckpointed sector must be fully re-processed (and re-appended) next run"
    );

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn queued_sectors_respects_total_and_side_bounds() {
    let done = std::collections::HashSet::new();
    // total in {5,6}, both sides in [2,4]: (2,3),(3,2) for total=5 (2,4
    // excluded: 2+4=6 not 5)... enumerate directly for clarity instead.
    let sectors = queued_sectors(5, 6, 2, 4, &done);
    assert_eq!(
        sectors,
        vec![(2, 3), (3, 2), (2, 4), (3, 3), (4, 2)],
        "must enumerate every (w,b) with w+b in [5,6] and both sides in [2,4]"
    );
}

#[test]
fn queued_sectors_skips_sides_below_the_terminal_floor() {
    let done = std::collections::HashSet::new();
    // total=6, min_side=3: (0,6)/(1,5)/(2,4) and their mirrors are
    // excluded because one side would already have lost.
    let sectors = queued_sectors(6, 6, 3, 9, &done);
    assert_eq!(sectors, vec![(3, 3)]);
}

#[test]
fn queued_sectors_skips_already_completed_pairs() {
    let done = std::collections::HashSet::from([(3_u8, 3_u8)]);
    let sectors = queued_sectors(6, 6, 3, 9, &done);
    assert!(sectors.is_empty());
}

#[test]
fn checkpoint_round_trips_through_disk() {
    let path = std::env::temp_dir().join(format!(
        "sanmill_mill_endgame_checkpoint_{}.json",
        std::process::id()
    ));
    let _ = std::fs::remove_file(&path);
    let path_str = path.to_str().unwrap();

    assert!(load_checkpoint(path_str).is_empty());

    let done = std::collections::HashSet::from([(3_u8, 3_u8), (4_u8, 3_u8)]);
    save_checkpoint(path_str, &done);
    assert_eq!(load_checkpoint(path_str), done);

    let _ = std::fs::remove_file(&path);
}
