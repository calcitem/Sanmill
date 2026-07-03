// SPDX-License-Identifier: AGPL-3.0-or-later
// mill-mine: mine engine-blunder positions against a Perfect (Malom) DB by
// crawling the position graph (not simulating games), so symmetric/
// transposed positions and repeated lines cost nothing beyond a hash
// lookup. See `docs/` conversation history / the plan this implements for
// the full design rationale; this module docs summarize the mechanism.
//
// Usage:
//   tgf mill mine --db PATH [options]
//
// Required:
//   --db PATH              Perfect DB root directory (full external copy;
//                          the small bundled subset works for smoke tests).
//
// Frontier seeding:
//   --human-db PATH        Optional NMM_LLM human_db.sqlite: every distinct
//                          recorded position seeds the frontier with mass
//                          equal to its recorded game count.
//   --seed-phase placing|moving|all  Restrict --human-db seeding to one
//                          phase (`state_key`'s `place`/`move`/`fly` field;
//                          `moving` covers both move and fly). Default all.
//                          Use `moving` to target endgame/middlegame
//                          coverage without the mass-priority frontier
//                          re-spending its budget on the (much higher game
//                          count) placing-phase seeds first.
//   --seed-fen-file PATH   Optional file of explicit FEN seeds, one per
//                          line (blank lines and lines starting with `#`
//                          ignored). For closed-loop mining: feed it the
//                          `first_uncovered_blunder_fen` values `mill
//                          arena --out` reports for its losing games, to
//                          dig specifically into the positions actually
//                          driving today's losses instead of a broad
//                          resample.
//   --seed-fen-mass F      Mass for every --seed-fen-file entry (default
//                          1e5 -- deliberately below --root-mass's 1e6 so
//                          the opening is still explored first if both
//                          are given, but well above a typical human
//                          position's recorded game count).
//   --root-mass F          Mass to seed the empty starting position with
//                          (default 1e6; deliberately larger than typical
//                          human position counts so the opening is explored
//                          first regardless of --human-db).
//
// Exploration bounds (at least one should usually be set; unbounded mining
// against the full ~28 billion-record database is not a realistic default):
//   --max-depth-plies N    Stop expanding a line N plies past its seed
//                          (0 = unbounded, default 0).
//   --placing-only         Stop expanding once a position leaves the
//                          placing phase (moving/flying positions are still
//                          judged if visited, just not expanded further).
//   --budget-seconds N     Wall-clock budget (0 = unbounded, default 0).
//   --budget-engine-calls N  Cap on tier-3 (engine) invocations
//                          (0 = unbounded, default 0).
//
// Engine (tier-3) configuration -- mirrors the requested AI play-style
// toggles; see `engine.rs` module docs for the exact mapping:
//   --depth N              Fixed search depth (0 = derive per-position from
//                          `recommended_search_depth`, default 0).
//   --skill-level N        Feeds `recommended_search_depth` (default 30).
//   --near-optimal-margin N  Root moves within N score units of the best
//                          are all treated as "the engine might play this"
//                          (default 0: only the exact best).
//
// Adversary / expansion policy (see `adversary.rs`):
//   --top-k N              Optimal replies followed per position (default 3)
//   --epsilon F            Mass fraction routed to the single most
//                          plausible non-optimal reply (default 0.15)
//
// Concurrency / output:
//   --workers N            Worker thread count (default
//                          min(20, available_parallelism)).
//   --out PATH             JSONL output path (default mine_entries.jsonl).
//   --checkpoint PATH      Checkpoint path (default mine_checkpoint.json).
//   --resume               Load --checkpoint if it exists.
//   --checkpoint-every N   Save a checkpoint every N processed nodes
//                          (default 5000).
//   --variant std|lask|mora  Rule variant (default std).

// `pub(crate)` so sibling tools can reuse the graph-crawling pipeline's
// building blocks without re-running (or re-implementing) the expensive
// tier-3-search-backed judgment: `mill_pack::recompute` re-derives
// `best_child` from `rank_children`, and `mill_endgame`'s exhaustive
// sector sweep reuses `MiningEngine` + `trap_score` for the same
// tier-2/tier-3 criticality check over a flat enumeration instead of a
// frontier.
pub(crate) mod adversary;
pub(crate) mod engine;
pub(crate) mod entry;
mod frontier;
mod human_seed;
pub(crate) mod scoring;

use std::collections::HashMap;
use std::sync::{Arc, Mutex, mpsc};
use std::thread;
use std::time::{Duration, Instant};

use perfect_db::all_move_wdl_fast;
use perfect_db::database::{
    Database, DatabaseOptions, DatabaseProvider, DatabaseVariant, FileDatabaseProvider,
};
use perfect_db::wdl_plane::WdlPlaneCache;
use tgf_core::{GameRules, OutcomeKind};
use tgf_mill::rules::MillState;
use tgf_mill::{MillPhase, MillRules, MillVariantOptions};

use crate::cli_args::{flag_present, parse_flag};
use adversary::{AdversaryPolicy, expansion_edges, rank_children};
use engine::{EngineConfig, MiningEngine};
use entry::{MineEntry, Verdict};
use frontier::{Frontier, FrontierItem};
use scoring::trap_score;

struct SharedDb {
    db: Database<FileDatabaseProvider>,
    planes: WdlPlaneCache<FileDatabaseProvider>,
}

/// Canonical mining/runtime key for a decoded state (settled or
/// mid-removal), or `None` when the variant/side is not one the perfect
/// database supports (never expected for the standard-variant states this
/// tool produces, but the underlying helpers are defensive so this stays
/// defensive too). Thin re-export of [`perfect_db::canonical_key`] so every
/// call site in this module goes through one name.
fn canonical_key_for_state<P: DatabaseProvider>(
    state: &MillState,
    options: &MillVariantOptions,
    planes: &mut WdlPlaneCache<P>,
) -> Option<u64> {
    perfect_db::canonical_key(planes, state, options)
}

#[derive(Clone, Copy, Debug)]
struct MineLimits {
    max_depth_plies: u32,
    placing_only: bool,
    budget: Option<Duration>,
    budget_engine_calls: u64,
}

struct WorkItem {
    item: FrontierItem,
    key: u64,
}

struct WorkResult {
    key: u64,
    verdict: Verdict,
    mass: f64,
    fen: String,
    engine_calls: u64,
    depth_used: i32,
    expansions: Vec<FrontierItem>,
}

/// Process one popped, not-yet-visited frontier item: tier-2 pre-filter,
/// tier-3 engine judgment when critical, and the (criticality-independent)
/// expansion edges.
#[allow(clippy::too_many_arguments)]
fn process_item(
    work: WorkItem,
    rules: &MillRules,
    options: &MillVariantOptions,
    shared: &Arc<Mutex<SharedDb>>,
    mining_engine: &mut MiningEngine,
    policy: AdversaryPolicy,
    limits: MineLimits,
) -> WorkResult {
    let WorkItem { item, key } = work;
    let state = rules
        .set_from_fen(&item.fen)
        .unwrap_or_else(|e| panic!("[mill-mine] frontier FEN must decode: {e} ({})", item.fen));
    let snap = rules.encode_state(state.clone());

    let no_result = |verdict: Verdict, engine_calls: u64| WorkResult {
        key,
        verdict,
        mass: item.mass,
        fen: item.fen.clone(),
        engine_calls,
        depth_used: 0,
        expansions: Vec::new(),
    };

    if rules.outcome(&snap).kind != OutcomeKind::Ongoing {
        return no_result(Verdict::Safe, 0);
    }

    let move_wdl = {
        let mut guard = shared.lock().expect("SharedDb mutex must not be poisoned");
        all_move_wdl_fast(&mut guard.planes, rules, &snap, options)
    };
    let move_wdl = match move_wdl {
        Ok(Some(move_wdl)) if !move_wdl.is_empty() => move_wdl,
        // No legal moves (shouldn't happen given the outcome check above,
        // but the DB-compatible ruleset's removal continuations make this
        // cheap to double-guard) or the DB does not cover this line
        // (missing sector / unsupported variant): nothing more to learn
        // here, treat as a leaf.
        _ => return no_result(Verdict::Safe, 0),
    };
    let best_value = move_wdl.iter().map(|&(_, v)| v).max().expect("non-empty");
    let critical = move_wdl.iter().any(|&(_, v)| v < best_value);

    let will_expand = (limits.max_depth_plies == 0 || item.depth < limits.max_depth_plies)
        && (!limits.placing_only || state.phase() == MillPhase::Placing);

    let mut verdict = Verdict::Safe;
    let mut engine_calls = 0_u64;
    let mut ranked_cache = None;
    let mut depth_used = 0_i32;

    if critical {
        let verdict_result = mining_engine.evaluate(&snap);
        engine_calls += 1;
        depth_used = verdict_result.depth_used;
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
        if min_engine_value < best_value {
            let ranked = ranked_cache.get_or_insert_with(|| {
                let mut guard = shared.lock().expect("SharedDb mutex must not be poisoned");
                let SharedDb { db, planes } = &mut *guard;
                rank_children(rules, options, db, planes, &snap, &move_wdl)
            });
            let best_child = ranked
                .optimal
                .first()
                .expect("critical position must have at least one optimal reply")
                .key;
            verdict = Verdict::Blunder {
                best_child,
                severity: ranked.best_value - min_engine_value,
            };
        }
    }

    let expansions = if will_expand {
        let ranked = ranked_cache.get_or_insert_with(|| {
            let mut guard = shared.lock().expect("SharedDb mutex must not be poisoned");
            let SharedDb { db, planes } = &mut *guard;
            rank_children(rules, options, db, planes, &snap, &move_wdl)
        });
        expansion_edges(ranked, policy, item.mass, item.depth + 1)
    } else {
        Vec::new()
    };

    WorkResult {
        key,
        verdict,
        mass: item.mass,
        fen: item.fen,
        engine_calls,
        depth_used,
        expansions,
    }
}

#[derive(Default)]
struct Stats {
    visited: u64,
    entries: u64,
    engine_calls: u64,
    dedup_hits: u64,
}

pub(crate) fn run_mill_mine(args: &[String]) {
    let db_path: String = parse_flag(args, "--db", String::new());
    if db_path.is_empty() {
        eprintln!("[mill-mine] ERROR: --db PATH is required");
        eprintln!("  Example: tgf mill mine --db D:/user/Documents/strong --max-depth-plies 10");
        std::process::exit(1);
    }
    let human_db_path: String = parse_flag(args, "--human-db", String::new());
    let seed_phase =
        human_seed::SeedPhase::parse(&parse_flag(args, "--seed-phase", "all".to_string()));
    let seed_fen_file: String = parse_flag(args, "--seed-fen-file", String::new());
    let seed_fen_mass: f64 = parse_flag(args, "--seed-fen-mass", 1.0e5_f64);
    let root_mass: f64 = parse_flag(args, "--root-mass", 1.0e6_f64);
    let max_depth_plies: u32 = parse_flag(args, "--max-depth-plies", 0u32);
    let placing_only = flag_present(args, "--placing-only");
    let budget_seconds: u64 = parse_flag(args, "--budget-seconds", 0u64);
    let budget_engine_calls: u64 = parse_flag(args, "--budget-engine-calls", 0u64);
    let depth_override: i32 = parse_flag(args, "--depth", 0i32);
    let skill_level: u8 = parse_flag(args, "--skill-level", 30u8);
    let near_optimal_margin: i32 = parse_flag(args, "--near-optimal-margin", 0i32);
    let top_k: usize = parse_flag(args, "--top-k", 3usize);
    let epsilon: f64 = parse_flag(args, "--epsilon", 0.15_f64);
    let workers: usize = {
        let requested: usize = parse_flag(args, "--workers", 0usize);
        let available = thread::available_parallelism().map_or(4, |n| n.get());
        if requested > 0 { requested } else { available }.clamp(1, 20)
    };
    let out_path: String = parse_flag(args, "--out", "mine_entries.jsonl".to_string());
    let checkpoint_path: String =
        parse_flag(args, "--checkpoint", "mine_checkpoint.json".to_string());
    let resume = flag_present(args, "--resume");
    let checkpoint_every: u64 = parse_flag(args, "--checkpoint-every", 5000u64);
    let variant_name: String = parse_flag(args, "--variant", "std".to_string());
    let cache_dir: String = parse_flag(args, "--wdl-cache-dir", String::new());

    let (options, _rule_variant_id) = crate::mill_puzzle::variant_options_for(&variant_name);
    let variant = DatabaseVariant::match_mill_options(&options).unwrap_or_else(|err| {
        panic!("[mill-mine] --variant {variant_name} is not a Perfect DB variant: {err}")
    });

    eprintln!(
        "[mill-mine] db={db_path} variant={variant_name} workers={workers} \
         max_depth_plies={max_depth_plies} placing_only={placing_only} \
         seed_phase={seed_phase:?} top_k={top_k} epsilon={epsilon} \
         depth_override={depth_override} skill_level={skill_level} \
         near_optimal_margin={near_optimal_margin} out={out_path} \
         checkpoint={checkpoint_path} resume={resume}"
    );

    let rules = MillRules::new(options.clone());
    let limits = MineLimits {
        max_depth_plies,
        placing_only,
        budget: (budget_seconds > 0).then(|| Duration::from_secs(budget_seconds)),
        budget_engine_calls,
    };
    let policy = AdversaryPolicy { top_k, epsilon };
    let engine_cfg = EngineConfig {
        depth_override,
        skill_level,
        near_optimal_margin,
    };

    let provider = FileDatabaseProvider::new(std::path::PathBuf::from(&db_path));
    let db = Database::open_variant_with_options(
        provider.clone(),
        variant,
        DatabaseOptions::with_sector_cache_capacity(64),
    )
    .unwrap_or_else(|e| panic!("[mill-mine] failed to open DB at {db_path}: {e}"));
    let plane_options = perfect_db::wdl_plane::WdlPlaneCacheOptions {
        plane_cache_capacity: Some(64),
        cache_dir: (!cache_dir.is_empty()).then(|| std::path::PathBuf::from(&cache_dir)),
    };
    let planes =
        WdlPlaneCache::with_options(provider, variant, plane_options).unwrap_or_else(|e| {
            panic!("[mill-mine] failed to open DB (plane cache) at {db_path}: {e}")
        });
    let shared = Arc::new(Mutex::new(SharedDb { db, planes }));

    let mut visited: HashMap<u64, Verdict> = HashMap::new();
    let mut frontier = Frontier::new();

    if resume && std::path::Path::new(&checkpoint_path).exists() {
        let (loaded_visited, loaded_frontier) = load_checkpoint(&checkpoint_path);
        eprintln!(
            "[mill-mine] resumed checkpoint: {} visited, {} frontier items",
            loaded_visited.len(),
            loaded_frontier.len()
        );
        visited = loaded_visited;
        frontier.extend(loaded_frontier);
    } else {
        let root_fen = rules.export_fen(&MillRules::decode_snapshot(rules.initial_state(&[])));
        frontier.push(FrontierItem {
            mass: root_mass,
            fen: root_fen,
            depth: 0,
        });
        if !human_db_path.is_empty() {
            let seeds = human_seed::load_seeds(&human_db_path, &rules, seed_phase);
            frontier.extend(seeds.into_iter().map(|s| FrontierItem {
                mass: s.mass,
                fen: s.fen,
                depth: 0,
            }));
        }
        if !seed_fen_file.is_empty() {
            let fens = load_seed_fen_file(&seed_fen_file, &rules);
            eprintln!(
                "[mill-mine] seed-fen-file: {} positions loaded from {seed_fen_file}",
                fens.len()
            );
            frontier.extend(fens.into_iter().map(|fen| FrontierItem {
                mass: seed_fen_mass,
                fen,
                depth: 0,
            }));
        }
    }

    let out_file = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&out_path)
        .unwrap_or_else(|e| panic!("[mill-mine] cannot open output {out_path}: {e}"));
    let mut out_writer = std::io::BufWriter::new(out_file);

    let mut stats = Stats::default();
    let started_at = Instant::now();
    let mut last_checkpoint_at_visited = 0_u64;
    let mut budget_exhausted = false;

    let (task_tx, task_rx) = mpsc::channel::<WorkItem>();
    let task_rx = Arc::new(Mutex::new(task_rx));
    let (result_tx, result_rx) = mpsc::channel::<WorkResult>();

    thread::scope(|scope| {
        for _ in 0..workers {
            let task_rx = Arc::clone(&task_rx);
            let result_tx = result_tx.clone();
            let shared = Arc::clone(&shared);
            let options = options.clone();
            let worker_rules = MillRules::new(options.clone());
            let mut mining_engine = MiningEngine::new(options.clone(), engine_cfg);
            scope.spawn(move || {
                loop {
                    let work = {
                        let rx = task_rx.lock().expect("task receiver mutex poisoned");
                        rx.recv()
                    };
                    let Ok(work) = work else { break };
                    let result = process_item(
                        work,
                        &worker_rules,
                        &options,
                        &shared,
                        &mut mining_engine,
                        policy,
                        limits,
                    );
                    if result_tx.send(result).is_err() {
                        break;
                    }
                }
            });
        }
        drop(result_tx);

        let mut in_flight = 0_usize;
        loop {
            while in_flight < workers && !budget_exhausted {
                let Some(item) = frontier.pop() else { break };
                let key = {
                    let state = rules
                        .set_from_fen(&item.fen)
                        .unwrap_or_else(|e| panic!("[mill-mine] frontier FEN must decode: {e}"));
                    let mut guard = shared.lock().expect("SharedDb mutex must not be poisoned");
                    canonical_key_for_state(&state, &options, &mut guard.planes)
                };
                let Some(key) = key else { continue };
                if visited.contains_key(&key) {
                    stats.dedup_hits += 1;
                    continue;
                }
                task_tx
                    .send(WorkItem { item, key })
                    .expect("worker task channel must accept work while workers are alive");
                in_flight += 1;
            }
            if in_flight == 0 {
                break;
            }
            let result = result_rx
                .recv()
                .expect("worker result channel closed unexpectedly");
            in_flight -= 1;
            stats.visited += 1;
            stats.engine_calls += result.engine_calls;

            if let Verdict::Blunder {
                best_child,
                severity,
            } = result.verdict
            {
                let entry = MineEntry {
                    key: result.key,
                    best_child,
                    severity,
                    trap_score: trap_score(severity, result.mass),
                    mass: result.mass,
                    fen: result.fen,
                    depth_used: result.depth_used,
                };
                use std::io::Write;
                serde_json::to_writer(&mut out_writer, &entry).expect("entry must serialize");
                out_writer.write_all(b"\n").expect("write failed");
                stats.entries += 1;
            }
            visited.insert(result.key, result.verdict);
            frontier.extend(result.expansions);

            if let Some(budget) = limits.budget
                && started_at.elapsed() >= budget
            {
                budget_exhausted = true;
            }
            if limits.budget_engine_calls > 0 && stats.engine_calls >= limits.budget_engine_calls {
                budget_exhausted = true;
            }
            if budget_exhausted && in_flight == 0 {
                break;
            }

            if stats.visited % 1000 == 0 {
                use std::io::Write;
                out_writer.flush().ok();
                eprintln!(
                    "[mill-mine] visited={} entries={} engine_calls={} dedup_hits={} \
                     frontier={} elapsed={:.1}s",
                    stats.visited,
                    stats.entries,
                    stats.engine_calls,
                    stats.dedup_hits,
                    frontier.len(),
                    started_at.elapsed().as_secs_f64()
                );
            }
            if stats.visited.saturating_sub(last_checkpoint_at_visited) >= checkpoint_every {
                save_checkpoint(&checkpoint_path, &visited, &frontier);
                last_checkpoint_at_visited = stats.visited;
            }
        }

        drop(task_tx);
    });

    {
        use std::io::Write;
        out_writer.flush().expect("final flush failed");
    }
    save_checkpoint(&checkpoint_path, &visited, &frontier);

    let elapsed = started_at.elapsed().as_secs_f64();
    let density_pct = if stats.visited > 0 {
        stats.entries as f64 * 100.0 / stats.visited as f64
    } else {
        0.0
    };
    eprintln!(
        "[mill-mine] done in {elapsed:.1}s: visited={} entries={} ({density_pct:.3}% density) \
         engine_calls={} dedup_hits={} remaining_frontier={}",
        stats.visited,
        stats.entries,
        stats.engine_calls,
        stats.dedup_hits,
        frontier.len(),
    );
}

#[derive(serde::Serialize, serde::Deserialize, Default)]
struct Checkpoint {
    visited: Vec<(u64, Verdict)>,
    frontier: Vec<FrontierItem>,
}

fn save_checkpoint(path: &str, visited: &HashMap<u64, Verdict>, frontier: &Frontier) {
    let checkpoint = Checkpoint {
        visited: visited.iter().map(|(&k, &v)| (k, v)).collect(),
        frontier: frontier.snapshot(),
    };
    let json = serde_json::to_string(&checkpoint).expect("checkpoint must serialize");
    let tmp_path = format!("{path}.tmp");
    std::fs::write(&tmp_path, json)
        .unwrap_or_else(|e| panic!("[mill-mine] cannot write checkpoint {tmp_path}: {e}"));
    std::fs::rename(&tmp_path, path)
        .unwrap_or_else(|e| panic!("[mill-mine] cannot finalize checkpoint {path}: {e}"));
}

/// Parse `--seed-fen-file`: one FEN per non-blank, non-`#`-prefixed line.
/// Lines that fail to decode under `rules` are skipped with a warning
/// (this file is typically hand-curated from `mill arena --out`'s
/// diagnostic JSONL, so a copy/paste slip should not abort the run) --
/// mirrors `human_seed::load_seeds`'s tolerance for a bad row in an
/// external, user-supplied input.
fn load_seed_fen_file(path: &str, rules: &MillRules) -> Vec<String> {
    let text = std::fs::read_to_string(path)
        .unwrap_or_else(|e| panic!("[mill-mine] cannot read --seed-fen-file {path}: {e}"));
    let mut fens = Vec::new();
    for (line_no, line) in text.lines().enumerate() {
        let fen = line.trim();
        if fen.is_empty() || fen.starts_with('#') {
            continue;
        }
        if rules.set_from_fen(fen).is_err() {
            eprintln!(
                "[mill-mine] seed-fen-file: skipping unparseable line {} in {path}",
                line_no + 1
            );
            continue;
        }
        fens.push(fen.to_string());
    }
    fens
}

fn load_checkpoint(path: &str) -> (HashMap<u64, Verdict>, Vec<FrontierItem>) {
    let bytes = std::fs::read(path)
        .unwrap_or_else(|e| panic!("[mill-mine] cannot read checkpoint {path}: {e}"));
    let checkpoint: Checkpoint = serde_json::from_slice(&bytes)
        .unwrap_or_else(|e| panic!("[mill-mine] cannot parse checkpoint {path}: {e}"));
    (
        checkpoint.visited.into_iter().collect(),
        checkpoint.frontier,
    )
}

#[cfg(test)]
mod tests;
