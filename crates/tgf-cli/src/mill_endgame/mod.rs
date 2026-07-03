// SPDX-License-Identifier: AGPL-3.0-or-later
// tgf mill mine-endgame: exhaustively evaluate every position in every
// small (white_on_board, black_on_board, 0, 0) sector, instead of crawling
// a sampled graph from human/synthetic seeds like `mill mine`.
//
// Sectors this small are enumerable in full (`PerfectHasher::hash_count`
// is exact, symmetry-reduced), so unlike the rest of the mining pipeline
// -- necessarily a sample of an ~28-billion-position database -- this
// sub-space gets a genuine completeness guarantee: every reachable
// position with this many pieces on board and nobody's hand, not just the
// ones a seed happened to walk through.
//
// Usage:
//   tgf mill mine-endgame --db PATH --out PATH --max-total-pieces N [options]
//
// Required:
//   --db PATH              Perfect DB root directory.
//   --out PATH             JSONL output path, same `MineEntry` schema as
//                          `mill mine` (append mode, so raising
//                          --max-total-pieces later only mines the newly
//                          added sectors).
//   --max-total-pieces N   Stop at this combined on-board piece count.
//                          The whole point of this mode is a completeness
//                          guarantee rather than a sample, so sector size
//                          grows combinatorially with this -- start low,
//                          check the reported entry count/bytes, and
//                          raise it incrementally instead of guessing a
//                          large value up front. See `tgf mill patch-pack
//                          --budget-bytes` for a hard backstop on the
//                          final asset size regardless.
//
// Sector range (both sides always start with an empty hand -- "endgame"
// here specifically means "everybody has finished placing"):
//   --min-total-pieces N   Skip sectors with fewer combined on-board
//                          pieces (default 6: `mill mine`'s graph-crawling
//                          from opening/placing seeds already reaches
//                          smaller endgames densely on its own).
//   --min-side-pieces N    Skip sectors where either side has fewer than
//                          this many on-board pieces (default 3: with
//                          fewer, that side has already lost under
//                          standard rules, so every position in the
//                          sector is trivially terminal and not worth the
//                          enumeration pass).
//
// Engine (tier-3) configuration -- same meaning as `mill mine`:
//   --depth N, --skill-level N, --near-optimal-margin N
//
// Entry priority:
//   --mass F               Flat `mass` stamped on every entry this run
//                          finds (default 1.0, matching `mill mine`'s
//                          floor for a human position with no recorded
//                          games). These positions have no game-frequency
//                          signal of their own -- completeness is the
//                          value proposition, not reach probability --
//                          so a flat value lets `patch-pack`'s mass-sorted
//                          --budget-bytes truncation fall back to
//                          proven-relevant (higher-mass) entries first if
//                          the combined patch ever has to be trimmed.
//
// Concurrency / output:
//   --workers N            Worker thread count (default
//                          min(20, available_parallelism)).
//   --checkpoint PATH      Completed-sector tracking (default
//                          "<out>.sectors.json"); a sector is checkpointed
//                          as a whole. Re-running with the same --out
//                          simply skips sectors already completed.
//   --max-slots-per-sector N  Stop each sector after this many slots
//                          instead of its full `hash_count` (0 =
//                          unbounded, default 0). For smoke-testing this
//                          tool against a large sector before committing
//                          to the full run, or for CI: a truncated sector
//                          is intentionally *not* checkpointed as done,
//                          since it was not actually completed. Leave at
//                          0 for a real mining run -- this flag exists to
//                          preview/spot-check, not to replace the
//                          completeness guarantee that is this mode's
//                          whole point.
//   --variant std|lask|mora  Rule variant (default std).

use std::collections::HashSet;
use std::io::Write;
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Instant;

use perfect_db::all_move_wdl_fast;
use perfect_db::database::{
    Database, DatabaseOptions, DatabaseVariant, FileDatabaseProvider, PerfectQuery,
};
use perfect_db::file_format::SectorId;
use perfect_db::index::PerfectHasher;
use perfect_db::wdl_plane::{WdlPlaneCache, WdlPlaneCacheOptions, pack_canonical_key};
use tgf_core::{GameRules, OutcomeKind};
use tgf_mill::{MillRules, MillVariantOptions};

use crate::cli_args::parse_flag;
use crate::mill_mine::adversary::rank_children;
use crate::mill_mine::engine::{EngineConfig, MiningEngine};
use crate::mill_mine::entry::MineEntry;
use crate::mill_mine::scoring::trap_score;

const BOARD_BITS_MASK: u32 = 0x00ff_ffff;

pub(crate) fn run_mill_endgame(args: &[String]) {
    let db_path: String = parse_flag(args, "--db", String::new());
    let out_path: String = parse_flag(args, "--out", String::new());
    if db_path.is_empty() || out_path.is_empty() {
        eprintln!("[mill-endgame] ERROR: --db and --out are required");
        eprintln!(
            "  Example: tgf mill mine-endgame --db D:/user/Documents/strong \\\n    --out endgame.jsonl --max-total-pieces 6"
        );
        std::process::exit(1);
    }
    let max_total_pieces: u8 = parse_flag(args, "--max-total-pieces", 0u8);
    if max_total_pieces == 0 {
        eprintln!("[mill-endgame] ERROR: --max-total-pieces is required (see module docs)");
        std::process::exit(1);
    }
    let min_total_pieces: u8 = parse_flag(args, "--min-total-pieces", 6u8);
    let min_side_pieces: u8 = parse_flag(args, "--min-side-pieces", 3u8);
    let depth_override: i32 = parse_flag(args, "--depth", 0i32);
    let skill_level: u8 = parse_flag(args, "--skill-level", 30u8);
    let near_optimal_margin: i32 = parse_flag(args, "--near-optimal-margin", 0i32);
    let mass: f64 = parse_flag(args, "--mass", 1.0f64);
    let max_slots_per_sector: usize = parse_flag(args, "--max-slots-per-sector", 0usize);
    let workers: usize = {
        let requested: usize = parse_flag(args, "--workers", 0usize);
        let available = thread::available_parallelism().map_or(4, |n| n.get());
        if requested > 0 { requested } else { available }.clamp(1, 20)
    };
    let checkpoint_path: String =
        parse_flag(args, "--checkpoint", format!("{out_path}.sectors.json"));
    let variant_name: String = parse_flag(args, "--variant", "std".to_string());

    let (options, _rule_variant_id) = crate::mill_puzzle::variant_options_for(&variant_name);
    let variant = DatabaseVariant::match_mill_options(&options).unwrap_or_else(|err| {
        panic!("[mill-endgame] --variant {variant_name} is not a Perfect DB variant: {err}")
    });
    let max_side_pieces = options.piece_count;

    // Fail fast if the DB root itself is wrong; individual missing sector
    // files within it are a normal, expected occurrence for a directory
    // that (unlike the full ~28GB Malom drop) only carries a subset, and
    // are skipped per-position below instead (see `all_move_wdl_fast`'s
    // `Ok(None)` contract for "not covered").
    WdlPlaneCache::new(
        FileDatabaseProvider::new(std::path::PathBuf::from(&db_path)),
        variant,
    )
    .unwrap_or_else(|e| panic!("[mill-endgame] failed to open DB at {db_path}: {e}"));

    let mut done = load_checkpoint(&checkpoint_path);

    eprintln!(
        "[mill-endgame] db={db_path} variant={variant_name} workers={workers} \
         min_total_pieces={min_total_pieces} max_total_pieces={max_total_pieces} \
         min_side_pieces={min_side_pieces} depth_override={depth_override} \
         skill_level={skill_level} near_optimal_margin={near_optimal_margin} mass={mass} \
         max_slots_per_sector={max_slots_per_sector} out={out_path} \
         checkpoint={checkpoint_path} already_done={}",
        done.len()
    );

    let sector_list = queued_sectors(
        min_total_pieces,
        max_total_pieces,
        min_side_pieces,
        max_side_pieces,
        &done,
    );
    eprintln!("[mill-endgame] {} sectors queued", sector_list.len());

    let out_file = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&out_path)
        .unwrap_or_else(|e| panic!("[mill-endgame] cannot open output {out_path}: {e}"));
    let out_writer = Arc::new(Mutex::new(std::io::BufWriter::new(out_file)));

    let engine_cfg = EngineConfig {
        depth_override,
        skill_level,
        near_optimal_margin,
    };

    let started_at = Instant::now();
    let mut grand_visited = 0_u64;
    let mut grand_entries = 0_u64;
    let mut grand_engine_calls = 0_u64;

    for (w, b) in sector_list {
        let sector_started = Instant::now();
        let hasher = Arc::new(PerfectHasher::new(w, b));
        let full_hash_count = hasher.hash_count();
        let truncated = max_slots_per_sector > 0 && max_slots_per_sector < full_hash_count;
        let hash_count = if truncated {
            max_slots_per_sector
        } else {
            full_hash_count
        };

        let cursor = AtomicUsize::new(0);
        let sector_visited = AtomicU64::new(0);
        let sector_entries = AtomicU64::new(0);
        let sector_engine_calls = AtomicU64::new(0);
        let sector_uncovered = AtomicU64::new(0);

        thread::scope(|scope| {
            let handles: Vec<_> = (0..workers)
                .map(|_| {
                    let hasher = Arc::clone(&hasher);
                    let cursor = &cursor;
                    let sector_visited = &sector_visited;
                    let sector_entries = &sector_entries;
                    let sector_engine_calls = &sector_engine_calls;
                    let sector_uncovered = &sector_uncovered;
                    let out_writer = Arc::clone(&out_writer);
                    let options = options.clone();
                    let worker_rules = MillRules::new(options.clone());
                    let provider = FileDatabaseProvider::new(std::path::PathBuf::from(&db_path));
                    let mut db = Database::open_variant_with_options(
                        provider.clone(),
                        variant,
                        DatabaseOptions::with_sector_cache_capacity(16),
                    )
                    .unwrap_or_else(|e| panic!("[mill-endgame] failed to open DB: {e}"));
                    let mut planes = WdlPlaneCache::with_options(
                        provider,
                        variant,
                        WdlPlaneCacheOptions {
                            plane_cache_capacity: Some(16),
                            cache_dir: None,
                        },
                    )
                    .unwrap_or_else(|e| panic!("[mill-endgame] failed to open DB (planes): {e}"));
                    let mut mining_engine = MiningEngine::new(options.clone(), engine_cfg);

                    scope.spawn(move || {
                        const CHUNK: usize = 128;
                        loop {
                            let start = cursor.fetch_add(CHUNK, Ordering::Relaxed);
                            if start >= hash_count {
                                break;
                            }
                            let end = (start + CHUNK).min(hash_count);
                            for slot in start..end {
                                evaluate_slot(
                                    slot,
                                    &hasher,
                                    w,
                                    b,
                                    &worker_rules,
                                    &options,
                                    &mut db,
                                    &mut planes,
                                    &mut mining_engine,
                                    mass,
                                    &out_writer,
                                    sector_visited,
                                    sector_entries,
                                    sector_engine_calls,
                                    sector_uncovered,
                                );
                            }
                        }
                    })
                })
                .collect();
            for handle in handles {
                handle.join().expect("mill-endgame worker thread panicked");
            }
        });

        out_writer
            .lock()
            .expect("output writer mutex must not be poisoned")
            .flush()
            .ok();

        let visited = sector_visited.load(Ordering::Relaxed);
        let entries = sector_entries.load(Ordering::Relaxed);
        let engine_calls = sector_engine_calls.load(Ordering::Relaxed);
        let uncovered = sector_uncovered.load(Ordering::Relaxed);
        eprintln!(
            "[mill-endgame] W={w} B={b} hash_count={hash_count}/{full_hash_count}{} \
             visited={visited} entries={entries} ({:.1}% density) engine_calls={engine_calls} \
             uncovered={uncovered} elapsed={:.1}s",
            if truncated {
                " (TRUNCATED, not checkpointed)"
            } else {
                ""
            },
            if visited > 0 {
                entries as f64 * 100.0 / visited as f64
            } else {
                0.0
            },
            sector_started.elapsed().as_secs_f64()
        );
        grand_visited += visited;
        grand_entries += entries;
        grand_engine_calls += engine_calls;

        if !truncated {
            done.insert((w, b));
            save_checkpoint(&checkpoint_path, &done);
        }
    }

    eprintln!(
        "[mill-endgame] done in {:.1}s: sectors={} visited={grand_visited} \
         entries={grand_entries} engine_calls={grand_engine_calls}",
        started_at.elapsed().as_secs_f64(),
        done.len()
    );
}

#[allow(clippy::too_many_arguments)]
fn evaluate_slot<P: perfect_db::database::DatabaseProvider>(
    slot: usize,
    hasher: &PerfectHasher,
    white_on_board: u8,
    black_on_board: u8,
    rules: &MillRules,
    options: &MillVariantOptions,
    db: &mut Database<P>,
    planes: &mut WdlPlaneCache<P>,
    mining_engine: &mut MiningEngine,
    mass: f64,
    out_writer: &Arc<Mutex<std::io::BufWriter<std::fs::File>>>,
    sector_visited: &AtomicU64,
    sector_entries: &AtomicU64,
    sector_engine_calls: &AtomicU64,
    sector_uncovered: &AtomicU64,
) {
    let board = hasher.inverse_board(slot);
    // The grid enumerated by `inverse_board` contains every
    // seed-white x collapsed-black combination, which is a superset of
    // `hash_probe`'s canonical representatives: when the white orbit seed
    // has a nontrivial stabilizer, several grid slots are just symmetric
    // re-presentations of one abstract position (the on-disk format stores
    // `Symmetry` redirects in them). Only process fold fixed points --
    // each abstract position exactly once, under the same key the runtime
    // probe will derive for any of its presentations.
    if hasher.hash_probe(board).index != slot {
        return;
    }
    let query = PerfectQuery::new(
        (board as u32) & BOARD_BITS_MASK,
        ((board >> 24) as u32) & BOARD_BITS_MASK,
        0,
        0,
        0,
        false,
    );
    let snap = perfect_db::snapshot_from_perfect_query(rules, options, query);
    if rules.outcome(&snap).kind != OutcomeKind::Ongoing {
        return;
    }
    sector_visited.fetch_add(1, Ordering::Relaxed);

    let move_wdl = match all_move_wdl_fast(planes, rules, &snap, options) {
        Ok(Some(v)) if !v.is_empty() => v,
        Ok(_) => {
            sector_uncovered.fetch_add(1, Ordering::Relaxed);
            return;
        }
        Err(e) => panic!(
            "[mill-endgame] plane error at W={white_on_board} B={black_on_board} slot={slot}: {e}"
        ),
    };
    let best_value = move_wdl
        .iter()
        .map(|&(_, v)| v)
        .max()
        .expect("non-empty move_wdl");
    if !move_wdl.iter().any(|&(_, v)| v < best_value) {
        return;
    }

    let verdict_result = mining_engine.evaluate(&snap);
    sector_engine_calls.fetch_add(1, Ordering::Relaxed);
    let min_engine_value = verdict_result
        .near_optimal
        .iter()
        .map(|action| {
            move_wdl
                .iter()
                .find(|(a, _)| a == action)
                .map(|&(_, v)| v)
                .unwrap_or(best_value)
        })
        .min()
        .expect("near_optimal is non-empty");
    if min_engine_value >= best_value {
        return;
    }

    let ranked = rank_children(rules, options, db, planes, &snap, &move_wdl);
    let Some(best_child) = ranked.optimal.first() else {
        return;
    };
    let severity = ranked.best_value - min_engine_value;
    let key = pack_canonical_key(SectorId::new(white_on_board, black_on_board, 0, 0), slot);
    let state = MillRules::decode_snapshot(snap);
    let fen = rules.export_fen(&state);
    let entry = MineEntry {
        key,
        best_child: best_child.key,
        severity,
        trap_score: trap_score(severity, mass),
        mass,
        fen,
        depth_used: verdict_result.depth_used,
    };
    {
        let mut writer = out_writer
            .lock()
            .expect("output writer mutex must not be poisoned");
        serde_json::to_writer(&mut *writer, &entry).expect("entry must serialize");
        writer.write_all(b"\n").expect("write failed");
    }
    sector_entries.fetch_add(1, Ordering::Relaxed);
}

/// Every `(white_on_board, black_on_board)` sector (with in-hand always
/// `0, 0`) in `[min_total, max_total]` combined on-board pieces, both
/// sides having at least `min_side` and at most `max_side` pieces, that
/// is not already in `done`. Pure and independent of I/O so the range
/// logic is unit-testable without an expensive enumeration pass.
fn queued_sectors(
    min_total: u8,
    max_total: u8,
    min_side: u8,
    max_side: u8,
    done: &HashSet<(u8, u8)>,
) -> Vec<(u8, u8)> {
    let mut sectors = Vec::new();
    for total in min_total..=max_total {
        for w in 0..=total {
            let b = total - w;
            if w > max_side || b > max_side {
                continue;
            }
            if w < min_side || b < min_side {
                continue;
            }
            if done.contains(&(w, b)) {
                continue;
            }
            sectors.push((w, b));
        }
    }
    sectors
}

fn load_checkpoint(path: &str) -> HashSet<(u8, u8)> {
    let Ok(bytes) = std::fs::read(path) else {
        return HashSet::new();
    };
    let pairs: Vec<(u8, u8)> = serde_json::from_slice(&bytes)
        .unwrap_or_else(|e| panic!("[mill-endgame] cannot parse checkpoint {path}: {e}"));
    pairs.into_iter().collect()
}

fn save_checkpoint(path: &str, done: &HashSet<(u8, u8)>) {
    let mut pairs: Vec<(u8, u8)> = done.iter().copied().collect();
    pairs.sort_unstable();
    let json = serde_json::to_string(&pairs).expect("checkpoint must serialize");
    let tmp_path = format!("{path}.tmp");
    std::fs::write(&tmp_path, json)
        .unwrap_or_else(|e| panic!("[mill-endgame] cannot write checkpoint {tmp_path}: {e}"));
    std::fs::rename(&tmp_path, path)
        .unwrap_or_else(|e| panic!("[mill-endgame] cannot finalize checkpoint {path}: {e}"));
}

#[cfg(test)]
#[path = "tests.rs"]
mod tests;
