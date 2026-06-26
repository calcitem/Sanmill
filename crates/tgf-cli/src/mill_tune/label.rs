// SPDX-License-Identifier: GPL-3.0-or-later
// tune label: annotate a position dataset with Perfect DB WDL labels.

use std::fs::{self, File};
use std::io::{BufRead, BufReader, BufWriter, Write};
use std::time::Instant;

use perfect_db::database::{Database, DatabaseOptions, DatabaseVariant, FileDatabaseProvider};
use perfect_db::evaluate_state_with_database;
use tgf_mill::{MillRules, MillState, MillVariantOptions};

use super::{PositionRecord, flag_present, parse_flag};

struct InputRecord {
    rec: PositionRecord,
    seq: usize,
}

pub(crate) fn run_label(args: &[String]) {
    let db_path: String = parse_flag(args, "--db", String::new());
    if db_path.is_empty() {
        eprintln!("[tune label] ERROR: --db PATH is required");
        eprintln!("  Example: tgf tune label --db D:/user/Documents/strong");
        std::process::exit(1);
    }
    let in_path: String = parse_flag(args, "--in", "tune_positions.dat".to_string());
    let out_path: String = parse_flag(args, "--out", "tune_labeled.dat".to_string());
    let cache_cap: usize = parse_flag(args, "--cache", 32usize);
    let resume = flag_present(args, "--resume");
    let sector_sort = !flag_present(args, "--no-sector-sort");
    let in_place = in_path == out_path;

    eprintln!(
        "[tune label] db={db_path} in={in_path} out={out_path} cache={cache_cap} \
         resume={resume} sector_sort={sector_sort}"
    );

    let options = MillVariantOptions::default();
    let rules = MillRules::new(options.clone());
    let mut records = read_records(&in_path);
    let n_data_lines = records.len();
    eprintln!("[tune label] {n_data_lines} positions to process");

    if sector_sort {
        records.sort_by_key(|record| (sector_key(&rules, &record.rec), record.seq));
        eprintln!("[tune label] records sorted by Perfect DB sector");
    }

    let variant = DatabaseVariant::match_mill_options(&options)
        .expect("default MillVariantOptions must match a known DB variant");
    let db_options = DatabaseOptions::with_sector_cache_capacity(cache_cap);
    let mut db = Database::open_variant_with_options(
        FileDatabaseProvider::new(std::path::PathBuf::from(&db_path)),
        variant,
        db_options,
    )
    .unwrap_or_else(|e| panic!("[tune label] failed to open DB at {db_path}: {e}"));

    let tmp_path = if in_place {
        format!("{out_path}.tmp")
    } else {
        out_path.clone()
    };
    let out_file = File::create(&tmp_path)
        .unwrap_or_else(|e| panic!("[tune label] cannot create output {tmp_path}: {e}"));
    let mut writer = BufWriter::new(out_file);

    let mut total = 0usize;
    let mut labeled = 0usize;
    let mut skipped_resume = 0usize;
    let mut not_found = 0usize;
    let flush_every = 1000usize;
    let start_time = Instant::now();

    for mut input in records {
        total += 1;
        if resume && input.rec.wdl.is_some() {
            writeln!(writer, "{}", input.rec.to_record_line()).expect("write failed");
            skipped_resume += 1;
            continue;
        }

        let (state, side) = match decode_record_state(&rules, &input.rec) {
            Some(value) => value,
            None => {
                writeln!(writer, "{}", input.rec.to_record_line()).expect("write failed");
                not_found += 1;
                continue;
            }
        };

        match evaluate_state_with_database(&mut db, &state, &options, side) {
            Ok(Some((wdl, steps))) => {
                // DB WDL is side-to-move perspective; store White perspective
                // to match the static evaluator's positive-is-White convention.
                let white_wdl = if side == 1 { -wdl } else { wdl };
                input.rec.wdl = Some(white_wdl);
                input.rec.steps = if steps < 0 { None } else { Some(steps) };
                labeled += 1;
            }
            Ok(None) => {
                not_found += 1;
            }
            Err(e) => {
                eprintln!("[tune label] DB error for key {:#018x}: {e}", input.rec.key);
                not_found += 1;
            }
        }

        writeln!(writer, "{}", input.rec.to_record_line()).expect("write failed");
        if total.is_multiple_of(flush_every) {
            writer.flush().expect("flush failed");
            print_progress(
                total,
                n_data_lines,
                labeled,
                not_found,
                skipped_resume,
                start_time,
            );
        }
    }

    writer.flush().expect("final flush failed");
    if in_place {
        fs::rename(&tmp_path, &out_path)
            .unwrap_or_else(|e| panic!("[tune label] rename {tmp_path} -> {out_path}: {e}"));
    }

    let label_rate = if total > 0 {
        labeled as f64 * 100.0 / total as f64
    } else {
        0.0
    };
    let elapsed = start_time.elapsed().as_secs_f64();
    let rate = if elapsed > 0.0 {
        total as f64 / elapsed
    } else {
        0.0
    };
    eprintln!(
        "[tune label] done: {total}/{n_data_lines} total, {labeled} labeled \
         ({label_rate:.1}%), {not_found} not-found, {skipped_resume} resumed \
         ({elapsed:.1}s, {rate:.0} pos/s)"
    );
}

fn read_records(path: &str) -> Vec<InputRecord> {
    let f =
        File::open(path).unwrap_or_else(|e| panic!("[tune label] cannot open input {path}: {e}"));
    let mut records = Vec::new();
    for (seq, line) in BufReader::new(f).lines().map_while(Result::ok).enumerate() {
        if line.trim().is_empty() || line.starts_with('#') {
            continue;
        }
        if let Some(rec) = PositionRecord::from_record_line(&line) {
            records.push(InputRecord { rec, seq });
        }
    }
    records
}

fn decode_record_state(rules: &MillRules, rec: &PositionRecord) -> Option<(MillState, i8)> {
    let fen = if rec.fen.is_empty() {
        "********/********/******** w p p 0 9 0 9 0 0 -1 -1 -1 -1 0 0 1"
    } else {
        &rec.fen
    };
    let state = rules.set_from_fen(fen).ok()?;
    let side = state.side_to_move();
    Some((state, side))
}

fn sector_key(rules: &MillRules, rec: &PositionRecord) -> (u8, u8, u8, u8, u8) {
    let Some((state, _side)) = decode_record_state(rules, rec) else {
        return (u8::MAX, u8::MAX, u8::MAX, u8::MAX, rec.phase);
    };
    let on_board = state.pieces_on_board();
    let in_hand = state.pieces_in_hand();
    (on_board[0], on_board[1], in_hand[0], in_hand[1], rec.phase)
}

fn print_progress(
    total: usize,
    n_data_lines: usize,
    labeled: usize,
    not_found: usize,
    skipped_resume: usize,
    start_time: Instant,
) {
    let pct = total as f64 * 100.0 / n_data_lines.max(1) as f64;
    let elapsed = start_time.elapsed().as_secs_f64();
    let eta_str = if total > 0 && elapsed > 0.1 {
        let rate = total as f64 / elapsed;
        let remaining = (n_data_lines.saturating_sub(total)) as f64 / rate;
        format!("  ETA {:.0}s", remaining)
    } else {
        String::new()
    };
    eprintln!(
        "[tune label] {total}/{n_data_lines} ({pct:.1}%): {labeled} labeled, \
         {not_found} not-found, {skipped_resume} resumed{eta_str}"
    );
}
