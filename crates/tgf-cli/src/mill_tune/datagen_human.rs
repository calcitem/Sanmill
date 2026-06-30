// SPDX-License-Identifier: AGPL-3.0-or-later
// tune gen-human: sample positions from an NMM_LLM human_db.sqlite file.

use std::collections::HashSet;
use std::fs::File;
use std::io::{BufWriter, Write};
use std::time::Instant;

use rusqlite::{Connection, OpenFlags, params};
use tgf_mill::{MillRules, MillVariantOptions};

use super::{PositionRecord, parse_flag};

const NMM_POSITION_ORDER_NODES: [usize; 24] = [
    23, 16, 17, 18, 19, 20, 21, 22, // outer ring
    15, 8, 9, 10, 11, 12, 13, 14, // middle ring
    7, 0, 1, 2, 3, 4, 5, 6, // inner ring
];

pub(crate) fn run_gen_human(args: &[String]) {
    let db_path: String = parse_flag(
        args,
        "--db",
        "D:/Repo/NMM_LLM/data/human_db.sqlite".to_string(),
    );
    let out_path: String = parse_flag(args, "--out", "tune_positions_human.dat".to_string());
    let positions: usize = parse_flag(args, "--positions", 50_000usize);
    let min_games: usize = parse_flag(args, "--min-games", 1usize);
    // Deterministic seed for the equal-weight random sample.  We deliberately
    // sample uniformly over distinct positions instead of taking the top-N by
    // game frequency: top-N is almost entirely openings (placing), which
    // starves the moving/flying phases.  Uniform sampling covers more midgame
    // and endgame structure, which is what the evaluator needs to learn.
    let seed: u64 = parse_flag(args, "--seed", 0x1234_5678_9ABC_DEF0_u64);

    eprintln!(
        "[tune gen-human] db={db_path} out={out_path} positions={positions} \
         min_games={min_games} seed={seed:#018x}"
    );

    let conn = Connection::open_with_flags(&db_path, OpenFlags::SQLITE_OPEN_READ_ONLY)
        .unwrap_or_else(|e| panic!("[tune gen-human] cannot open {db_path}: {e}"));
    let rules = MillRules::new(MillVariantOptions::default());
    let mut stmt = conn
        .prepare("SELECT state_key FROM positions WHERE total_games >= ?1")
        .expect("human DB must contain a positions table");
    // Pull every eligible state_key, then uniformly shuffle and truncate so the
    // sample is not biased toward high-frequency openings.
    let mut all_rows: Vec<String> = stmt
        .query_map(params![min_games as i64], |row| row.get::<_, String>(0))
        .expect("failed to query human DB positions")
        .map(|r| r.expect("failed to read human DB row"))
        .collect();
    let candidate_count = all_rows.len();
    shuffle_keys(&mut all_rows, seed);
    all_rows.truncate(positions);
    let total_rows = all_rows.len();
    eprintln!("[tune gen-human] {candidate_count} eligible positions, sampling {total_rows}");

    let file = File::create(&out_path)
        .unwrap_or_else(|e| panic!("[tune gen-human] cannot create {out_path}: {e}"));
    let mut writer = BufWriter::new(file);
    let mut seen = HashSet::new();
    let mut written = 0usize;
    let mut skipped = 0usize;
    let start_time = Instant::now();
    let progress_every = (total_rows / 20).max(1);

    for (processed, state_key) in all_rows.into_iter().enumerate() {
        let Some(fen) = fen_from_state_key(&state_key) else {
            skipped += 1;
            continue;
        };
        let Ok(state) = rules.set_from_fen(&fen) else {
            skipped += 1;
            continue;
        };
        let key = stable_hash(&state_key);
        if !seen.insert(key) {
            continue;
        }
        let in_hand = state.pieces_in_hand();
        let on_board = state.pieces_on_board();
        let phase = if state.phase() == tgf_mill::MillPhase::Placing {
            0
        } else {
            1
        };
        let rec = PositionRecord {
            key,
            phase,
            in_hand_diff: i32::from(in_hand[0]) - i32::from(in_hand[1]),
            on_board_diff: i32::from(on_board[0]) - i32::from(on_board[1]),
            mobility_diff: state.mobility_diff(),
            wdl: None,
            steps: None,
            fen,
        };
        writeln!(writer, "{}", rec.to_record_line()).expect("write failed");
        written += 1;

        if (processed + 1).is_multiple_of(progress_every) {
            let elapsed = start_time.elapsed().as_secs_f64();
            let pct = (processed + 1) as f64 * 100.0 / total_rows as f64;
            let eta_str = if elapsed > 0.1 {
                let rate = (processed + 1) as f64 / elapsed;
                let remaining = (total_rows.saturating_sub(processed + 1)) as f64 / rate;
                format!("  ETA {}", fmt_secs(remaining))
            } else {
                String::new()
            };
            eprintln!(
                "[tune gen-human] {}/{total_rows} ({pct:.0}%) \
                 written={written} skipped={skipped} elapsed={}{eta_str}",
                processed + 1,
                fmt_secs(elapsed),
            );
        }
    }
    writer.flush().expect("flush failed");
    let elapsed = start_time.elapsed().as_secs_f64();
    eprintln!(
        "[tune gen-human] done in {}: {written} positions written, {skipped} skipped",
        fmt_secs(elapsed),
    );
}

/// Deterministic Fisher-Yates shuffle (xorshift64* RNG) for uniform sampling.
fn shuffle_keys(keys: &mut [String], seed: u64) {
    let mut state = seed | 1;
    for i in (1..keys.len()).rev() {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        let j = (state % (i as u64 + 1)) as usize;
        keys.swap(i, j);
    }
}

fn fmt_secs(secs: f64) -> String {
    let secs = secs.max(0.0) as u64;
    let h = secs / 3600;
    let m = (secs % 3600) / 60;
    let s = secs % 60;
    if h > 0 {
        format!("{h}h{m:02}m{s:02}s")
    } else if m > 0 {
        format!("{m}m{s:02}s")
    } else {
        format!("{s}s")
    }
}

fn fen_from_state_key(state_key: &str) -> Option<String> {
    let fields = state_key.split('|').collect::<Vec<_>>();
    if fields.len() < 7 {
        return None;
    }
    let canonical = fields[0];
    if canonical.len() != 24 {
        return None;
    }
    let side = match fields[1] {
        "W" => "w",
        "B" => "b",
        _ => return None,
    };
    let phase = match fields[2] {
        "place" => "p",
        "move" | "fly" => "m",
        _ => return None,
    };
    let action = if phase == "p" { "p" } else { "s" };
    let placed_w = fields[3].parse::<u8>().ok()?;
    let placed_b = fields[4].parse::<u8>().ok()?;
    let on_w = fields[5].parse::<u8>().ok()?;
    let on_b = fields[6].parse::<u8>().ok()?;
    let hand_w = 9_u8.checked_sub(placed_w)?;
    let hand_b = 9_u8.checked_sub(placed_b)?;

    let mut board = ['*'; 24];
    for (nmm_idx, ch) in canonical.chars().enumerate() {
        let node = NMM_POSITION_ORDER_NODES[nmm_idx];
        board[node] = match ch {
            'W' => 'O',
            'B' => '@',
            '.' => '*',
            _ => return None,
        };
    }
    let inner: String = board[0..8].iter().collect();
    let middle: String = board[8..16].iter().collect();
    let outer: String = board[16..24].iter().collect();
    Some(format!(
        "{inner}/{middle}/{outer} {side} {phase} {action} \
         {on_w} {hand_w} {on_b} {hand_b} 0 0 -1 -1 -1 -1 0 0 1 ids:nodes"
    ))
}

fn stable_hash(value: &str) -> u64 {
    let mut hash = 0xcbf2_9ce4_8422_2325_u64;
    for byte in value.as_bytes() {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
    }
    hash
}
