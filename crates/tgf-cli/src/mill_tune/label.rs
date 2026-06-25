// SPDX-License-Identifier: GPL-3.0-or-later
// tune label: annotate a position dataset with Perfect DB WDL labels.
//
// Usage:
//   tgf tune label --db PATH [--in PATH] [--out PATH] [--cache N] [--resume]
//
// --db PATH       Path to perfect DB directory (e.g. D:/user/Documents/strong)
// --in PATH       Input dataset (unlabeled or partially labeled).
//                 Default: tune_positions.dat
// --out PATH      Output dataset (labeled).  Default: tune_labeled.dat
//                 When --out equals --in the file is updated in-place via
//                 an atomic rename.
// --cache N       Sector cache capacity (LRU, default 32).
// --resume        Skip lines that already have a WDL label (not "?").
//
// Output: same pipe-delimited format with WDL/STEPS fields filled in.
// Positions not found in the DB (only-stone-taking states, unsupported
// variants, missing sectors) keep wdl=? in the output — they are skipped
// by tune-fit.

use std::fs::{self, File};
use std::io::{BufRead, BufReader, BufWriter, Write};
use std::time::Instant;

use perfect_db::database::{Database, DatabaseOptions, DatabaseVariant, FileDatabaseProvider};
use perfect_db::evaluate_state_with_database;
use tgf_mill::{MillRules, MillVariantOptions};

use super::{PositionRecord, flag_present, parse_flag};

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
    let in_place = in_path == out_path;

    eprintln!(
        "[tune label] db={db_path} in={in_path} out={out_path} cache={cache_cap} resume={resume}"
    );

    // Open DB.
    let options = MillVariantOptions::default();
    let variant = DatabaseVariant::match_mill_options(&options)
        .expect("default MillVariantOptions must match a known DB variant");
    let db_options = DatabaseOptions::with_sector_cache_capacity(cache_cap);
    let mut db = Database::open_variant_with_options(
        FileDatabaseProvider::new(std::path::PathBuf::from(&db_path)),
        variant,
        db_options,
    )
    .unwrap_or_else(|e| panic!("[tune label] failed to open DB at {db_path}: {e}"));

    let rules = MillRules::new(options.clone());

    // Pre-scan to count data lines so we can show a progress percentage.
    let n_data_lines: usize = {
        let f = File::open(&in_path)
            .unwrap_or_else(|e| panic!("[tune label] cannot open input {in_path}: {e}"));
        BufReader::new(f)
            .lines()
            .map_while(Result::ok)
            .filter(|l| {
                let t = l.trim();
                !t.is_empty() && !t.starts_with('#')
            })
            .count()
    };
    eprintln!("[tune label] {n_data_lines} positions to process");

    // Decide output file.
    let tmp_path = if in_place {
        format!("{out_path}.tmp")
    } else {
        out_path.clone()
    };
    let in_file = File::open(&in_path)
        .unwrap_or_else(|e| panic!("[tune label] cannot open input {in_path}: {e}"));
    let out_file = File::create(&tmp_path)
        .unwrap_or_else(|e| panic!("[tune label] cannot create output {tmp_path}: {e}"));
    let reader = BufReader::new(in_file);
    let mut writer = BufWriter::new(out_file);

    let mut total = 0usize;
    let mut labeled = 0usize;
    let mut skipped_resume = 0usize;
    let mut not_found = 0usize;
    let flush_every = 1000usize;
    let start_time = Instant::now();

    for line in reader.lines().map_while(Result::ok) {
        if line.trim().is_empty() || line.starts_with('#') {
            writeln!(writer, "{line}").expect("write failed");
            continue;
        }
        let Some(mut rec) = PositionRecord::from_record_line(&line) else {
            // Pass through malformed lines.
            writeln!(writer, "{line}").expect("write failed");
            continue;
        };
        total += 1;

        if resume && rec.wdl.is_some() {
            // Already labeled — write as-is.
            writeln!(writer, "{}", rec.to_record_line()).expect("write failed");
            skipped_resume += 1;
            continue;
        }

        // Decode FEN to MillState for the DB query.
        // perfect_db::evaluate_state_with_database takes &MillState +
        // side_to_move directly, so no GameStateSnapshot needed.
        let (state, side) = if rec.fen.is_empty() {
            let initial_state = rules
                .set_from_fen("********/********/******** w p p 0 9 0 9 0 0 -1 -1 -1 -1 0 0 1");
            match initial_state {
                Ok(ms) => (ms, 0i8),
                Err(_) => {
                    writeln!(writer, "{}", rec.to_record_line()).expect("write failed");
                    not_found += 1;
                    continue;
                }
            }
        } else {
            match rules.set_from_fen(&rec.fen) {
                Ok(ms) => {
                    let side = ms.side_to_move();
                    (ms, side)
                }
                Err(_) => {
                    writeln!(writer, "{}", rec.to_record_line()).expect("write failed");
                    not_found += 1;
                    continue;
                }
            }
        };

        match evaluate_state_with_database(&mut db, &state, &options, side) {
            Ok(Some((wdl, steps))) => {
                // DB returns WDL from the perspective of `side` (side-to-move).
                // The eval function uses White-perspective scores (positive = White
                // ahead), so we must convert to White perspective before storing:
                // if Black is to move and wins, wdl=+1 from Black's view but the
                // position is bad for White, so White-perspective wdl = -1.
                let white_wdl = if side == 1 { -wdl } else { wdl };
                rec.wdl = Some(white_wdl);
                rec.steps = if steps < 0 { None } else { Some(steps) };
                labeled += 1;
            }
            Ok(None) => {
                not_found += 1;
            }
            Err(e) => {
                eprintln!("[tune label] DB error for key {:#018x}: {e}", rec.key);
                not_found += 1;
            }
        }

        writeln!(writer, "{}", rec.to_record_line()).expect("write failed");

        if total.is_multiple_of(flush_every) {
            writer.flush().expect("flush failed");
            let pct = total as f64 * 100.0 / n_data_lines.max(1) as f64;
            let elapsed = start_time.elapsed().as_secs_f64();
            let eta_str = if total > 0 && elapsed > 0.1 {
                let rate = total as f64 / elapsed; // positions/s
                let remaining = (n_data_lines.saturating_sub(total)) as f64 / rate;
                format!("  ETA {:.0}s", remaining)
            } else {
                String::new()
            };
            eprintln!(
                "[tune label] {total}/{n_data_lines} ({pct:.1}%): \
                 {labeled} labeled, {not_found} not-found, \
                 {skipped_resume} resumed{eta_str}"
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
        "[tune label] done: {total}/{n_data_lines} total, \
         {labeled} labeled ({label_rate:.1}%), \
         {not_found} not-found, {skipped_resume} resumed  \
         ({elapsed:.1}s, {rate:.0} pos/s)"
    );
}
