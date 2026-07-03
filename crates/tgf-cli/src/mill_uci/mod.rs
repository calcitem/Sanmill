// SPDX-License-Identifier: AGPL-3.0-or-later
// Mill UCI adapter for tgf-cli.
//
// Owns every Mill-specific piece of the CLI:
//   * the UCI main loop and `setoption` table for all Mill rule variants
//   * Mill FEN parsing and ASCII board printing
//   * Mill action ↔ UCI string codec
//   * `Searcher<MillGame>` factory tuned for Mill (Remove qsearch policy)
//   * the bench harness used by `tgf bench` and the perf-baseline pipeline
//
// The game registry calls this module through `games::mill`; nothing in this
// file is expected to generalise to another game.

use std::io::{self, BufRead};
use std::sync::atomic::AtomicBool;
use std::sync::{Arc, mpsc};
use std::thread::{self, JoinHandle};

use perfect_db::database::{DatabaseOptions, DatabaseVariant, PerfectDatabaseRuleMismatch};
use tgf_core::{
    Action, ActionList, Evaluator, Game, GameRules, GameStateSnapshot, MoveOrderAlgorithm,
    MoveOrderContext, SearchActionList, Workbench,
};
use tgf_mill::{
    EngineRuntimeOptions, MillActionKind, MillEvalWeights, MillEvaluator, MillGame, MillRules,
    MillVariantOptions, recommended_search_depth,
};
use tgf_search::{
    LazySmpWorker, MctsOptions, MctsSearcher, RootMoveSummary, SearchAbortHandle, SearchOptions,
    SearchPolicy, SearchResult, Searcher, SharedTt,
};

mod bench;
mod board;
mod patch;
mod setoption;

pub(crate) use bench::print_benchmark_toml;
#[cfg(test)]
use board::board_ascii_lines;
use board::{
    GoOptions, ParsedPosition, action_to_uci, parse_go_options, parse_position_command,
    print_board_ascii, print_uci_options,
};
use setoption::{SetoptionResult, apply_setoption};

/// `TGF_TT_CLUSTER_BITS` (10-26) selects `2^bits` direct TT slots; see
/// `tgf_search::Searcher::new_with_tt_cluster_bits`.  Default 24 to
/// match master `TRANSPOSITION_TABLE_SIZE = 0x1000000` (16 Mi slots).
fn tt_cluster_bits_from_env() -> u32 {
    std::env::var("TGF_TT_CLUSTER_BITS")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(24)
        .clamp(10, 26)
}

fn prefetch_enabled_from_env() -> bool {
    match std::env::var("TGF_ENABLE_PREFETCH") {
        Ok(value) => match value.to_ascii_lowercase().as_str() {
            "1" | "true" | "on" | "yes" => true,
            "0" | "false" | "off" | "no" => false,
            _ => panic!("invalid TGF_ENABLE_PREFETCH value: {value}"),
        },
        Err(_) => false,
    }
}

fn prefetch_mode_from_env() -> (bool, bool) {
    match std::env::var("TGF_PREFETCH_MODE") {
        Ok(value) => match value.to_ascii_lowercase().as_str() {
            "off" | "none" | "0" | "false" => (false, false),
            "first" | "1" | "true" | "on" | "yes" => (true, false),
            "all" | "full" | "master" => (true, true),
            _ => panic!("invalid TGF_PREFETCH_MODE value: {value}"),
        },
        // TGF_PREFETCH_MODE unset: default to full prefetch ("all"), mirroring
        // master `Search::search`/`qsearch`. This is a measured, node-preserving
        // win for Mill, whose `key_after` is an O(1) incremental-Zobrist hint —
        // exactly the precondition documented on `SearchOptions::enable_prefetch`.
        // AMD Zen `assess` profiling showed ~+50% IPC / ~-33% cycles at equal
        // retired instructions and identical node counts. The legacy
        // `TGF_ENABLE_PREFETCH` toggle, when explicitly set, still selects
        // first-only/off; `TGF_PREFETCH_MODE=off` forces prefetch off.
        Err(_) => match std::env::var("TGF_ENABLE_PREFETCH") {
            Ok(_) => (prefetch_enabled_from_env(), false),
            Err(_) => (true, true),
        },
    }
}

const DEFAULT_TT_MOVE_ENABLED: bool = true;

fn tt_move_enabled_from_env() -> bool {
    match std::env::var("TGF_ENABLE_TT_MOVE") {
        Ok(value) => parse_tt_move_enabled(&value),
        // TT move ordering is a measured Skill 30 / MoveTime 1s H2H win.
        // Keep it enabled by default, while preserving a cheap escape hatch:
        // `TGF_ENABLE_TT_MOVE=0`.
        Err(_) => DEFAULT_TT_MOVE_ENABLED,
    }
}

fn parse_tt_move_enabled(value: &str) -> bool {
    match value.to_ascii_lowercase().as_str() {
        "1" | "true" | "on" | "yes" => true,
        "0" | "false" | "off" | "no" => false,
        _ => panic!("invalid TGF_ENABLE_TT_MOVE value: {value}"),
    }
}

/// Delegate to `MillEvalWeights::from_env()`.  Re-exposed here so the
/// rest of this module can call `eval_weights_from_env()` without the
/// fully-qualified path.
fn eval_weights_from_env() -> Option<MillEvalWeights> {
    MillEvalWeights::from_env()
}

fn mill_searcher() -> Searcher<MillGame> {
    let mut s = Searcher::new_with_tt_cluster_bits_and_tt_move(
        tt_cluster_bits_from_env(),
        tt_move_enabled_from_env(),
    );
    s.set_policy(SearchPolicy {
        quiescence_kind_tag: Some(MillActionKind::Remove as i16),
        ..Default::default()
    });
    s
}

fn mill_searcher_with_shared_tt(shared_tt: SharedTt) -> Searcher<MillGame> {
    let mut s = Searcher::with_shared_tt(shared_tt);
    s.set_policy(SearchPolicy {
        quiescence_kind_tag: Some(MillActionKind::Remove as i16),
        ..Default::default()
    });
    s
}

fn allocate_shared_tt(hash_mb: u32) -> SharedTt {
    let tt = SharedTt::with_capacity_mb_and_tt_move(
        hash_mb,
        tt_cluster_bits_from_env(),
        tt_move_enabled_from_env(),
    );
    // Master physically initializes the process-global TT before search and
    // later uses fake-clean generation bumps. Touch the Rust shared TT once at
    // allocation time so first-search probe/save traffic does not pay both
    // demand-zero read faults and private-page write faults in the hot path.
    tt.clear();
    tt
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct PerfectDatabaseRuntimeConfig {
    path: String,
    variant: DatabaseVariant,
    options: DatabaseOptions,
}

/// Runtime engine configuration (non-variant search/difficulty parameters).
/// These mirror the master `GameOptions` fields that are set via UCI setoption.
#[derive(Clone, Debug)]
struct EngineConfig {
    skill_level: u8,
    algorithm: u8,
    ai_is_lazy: bool,
    ids_enabled: bool,
    depth_extension: bool,
    last_best_value: i32,
    /// Side-to-move that produced `last_best_value`.  MTD(f) may use the
    /// score as a cross-move first guess only when the next root is searched
    /// for the same side; otherwise the sign convention is ambiguous.
    last_best_value_side_to_move: i8,
    /// Per-move thinking time in milliseconds.  0 = fixed depth (no time
    /// limit).  Set via `setoption MoveTime` (seconds, stored as ms) or
    /// the new `setoption MoveTimeMs` (milliseconds direct).  Default
    /// 1000 ms matches the legacy 1-second default.
    move_time_ms: u32,
    shuffling: bool,
    draw_on_human_experience: bool,
    developer_mode: bool,
    hash_mb: u32,
    ponder: bool,
    use_lazy_smp: bool,
    /// When true, query the perfect database after search and prefer
    /// its move when the current Mill variant has matching database assets.
    use_perfect_database: bool,
    /// Filesystem directory holding the `std_*.sec2` / `std.secval` dataset.
    /// Set via the `PerfectDatabasePath` UCI option before enabling the DB.
    perfect_db_path: Option<String>,
    /// Maximum number of sector files kept loaded by the Rust Perfect DB.
    /// `None` preserves the historical unbounded native behavior.
    perfect_db_cache_sectors: Option<usize>,
    active_perfect_db: Option<PerfectDatabaseRuntimeConfig>,
    /// Filesystem path to a `*.mill_patch` asset.  Loaded when
    /// `patch_avoid_traps` is enabled or whenever the path changes.
    patch_path: Option<String>,
    /// When true, correct the chosen move using the loaded error patch
    /// (Flutter "Avoid known traps").
    patch_avoid_traps: bool,
}

impl Default for EngineConfig {
    fn default() -> Self {
        Self {
            skill_level: 1,
            algorithm: 2,
            ai_is_lazy: false,
            ids_enabled: false,
            depth_extension: true,
            last_best_value: 0,
            last_best_value_side_to_move: -1,
            move_time_ms: 1000,
            shuffling: true,
            draw_on_human_experience: true,
            developer_mode: true,
            hash_mb: 16,
            ponder: false,
            use_lazy_smp: std::env::var("TGF_USE_LAZY_SMP")
                .map(|value| value == "1" || value.eq_ignore_ascii_case("true"))
                .unwrap_or(false),
            use_perfect_database: false,
            perfect_db_path: None,
            perfect_db_cache_sectors: None,
            active_perfect_db: None,
            patch_path: None,
            patch_avoid_traps: false,
        }
    }
}

impl EngineConfig {
    fn desired_perfect_db_config(
        &self,
        options: &MillVariantOptions,
    ) -> Result<Option<PerfectDatabaseRuntimeConfig>, PerfectDatabaseRuleMismatch> {
        let Some(path) = self.perfect_db_path.as_ref() else {
            return Ok(None);
        };
        let variant = DatabaseVariant::match_mill_options(options)?;
        let options = self
            .perfect_db_cache_sectors
            .map(DatabaseOptions::with_sector_cache_capacity)
            .unwrap_or_default();
        Ok(Some(PerfectDatabaseRuntimeConfig {
            path: path.clone(),
            variant,
            options,
        }))
    }
}

fn perfect_move_ordering(cfg: &EngineConfig) -> perfect_db::PerfectMoveOrdering {
    if cfg.algorithm == 4 && !cfg.ai_is_lazy {
        perfect_db::PerfectMoveOrdering::StrictSteps
    } else {
        perfect_db::PerfectMoveOrdering::LegacyWdl
    }
}

/// Bring the process-wide perfect-database handle in line with [`EngineConfig`]:
/// initialize it (from `perfect_db_path`) when the option is enabled and a path
/// is known, and release it when the option is turned off.  Idempotent.
fn sync_perfect_db(cfg: &mut EngineConfig, options: &MillVariantOptions) {
    if cfg.use_perfect_database {
        let desired = match cfg.desired_perfect_db_config(options) {
            Ok(Some(desired)) => desired,
            Ok(None) => {
                println!("info string perfect database enabled but PerfectDatabasePath is unset");
                return;
            }
            Err(mismatch) => {
                if perfect_db::is_initialized() {
                    perfect_db::deinit();
                }
                cfg.active_perfect_db = None;
                println!("info string perfect database unsupported rule variant: {mismatch}");
                return;
            }
        };
        if cfg.active_perfect_db.as_ref() == Some(&desired) && perfect_db::is_initialized() {
            return;
        }
        if perfect_db::is_initialized() {
            perfect_db::deinit();
        }
        if perfect_db::init_variant_with_options(&desired.path, desired.variant, desired.options) {
            cfg.active_perfect_db = Some(desired);
        } else {
            println!(
                "info string perfect database init failed: {} ({})",
                desired.path, desired.variant.name
            );
            cfg.active_perfect_db = None;
        }
    } else if perfect_db::is_initialized() {
        perfect_db::deinit();
        cfg.active_perfect_db = None;
    } else {
        cfg.active_perfect_db = None;
    }
}

/// Build a `MillRules` and inject tunable eval weights from the environment
/// (`TGF_EVAL_WEIGHTS=piece_value,mobility,mill_count`).
/// When the variable is unset the returned rules use MillEvalWeights::LEGACY
/// and the search tree is bit-identical to the pre-tuning evaluator.
fn mill_rules_with_eval_weights(options: MillVariantOptions) -> MillRules {
    let mut rules = MillRules::new(options);
    if let Some(weights) = eval_weights_from_env() {
        rules.set_eval_weights(weights);
    }
    rules
}

fn apply_patch_env_defaults(cfg: &mut EngineConfig) {
    if let Ok(path) = std::env::var("TGF_PATCH_PATH") {
        let path = path.trim().to_owned();
        cfg.patch_path = (!path.is_empty()).then_some(path);
    }
    if let Ok(value) = std::env::var("TGF_PATCH_AVOID_TRAPS") {
        cfg.patch_avoid_traps = matches!(
            value.trim().to_ascii_lowercase().as_str(),
            "1" | "true" | "on" | "yes"
        );
    }
    patch::sync_runtime(&cfg.patch_path, cfg.patch_avoid_traps);
}

pub(crate) fn run_uci_loop() {
    let mut options = MillVariantOptions::default();
    let mut rules = mill_rules_with_eval_weights(options.clone());
    let mut state = rules.initial_state(&[]);
    let mut state_history: Vec<GameStateSnapshot> = Vec::new();
    let mut threads: usize = 1;
    let mut qsearch_max_depth: i32 = 0;
    let mut engine_cfg = EngineConfig::default();
    apply_patch_env_defaults(&mut engine_cfg);
    let mut shared_tt = allocate_shared_tt(engine_cfg.hash_mb);
    let mut active_search: Option<ActiveSearch> = None;
    let stdin = io::stdin();
    for line in stdin.lock().lines().map_while(Result::ok) {
        drain_finished_search(&mut active_search, &mut engine_cfg);
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        if line == "uci" {
            println!("id name TGF Mill Rust");
            println!("id author The Sanmill developers");
            print_uci_options();
            println!("uciok");
        } else if line == "isready" {
            println!("readyok");
        } else if line == "ucinewgame" {
            finish_active_search(&mut active_search, &mut engine_cfg);
            state = rules.initial_state(&[]);
            state_history.clear();
        } else if line == "compiler" {
            println!(
                "info string compiler Rust {} target {}",
                env!("CARGO_PKG_VERSION"),
                std::env::consts::ARCH
            );
        } else if line.starts_with("setoption") {
            finish_active_search(&mut active_search, &mut engine_cfg);
            let old_hash_mb = engine_cfg.hash_mb;
            match apply_setoption(
                line,
                &mut options,
                &mut threads,
                &mut qsearch_max_depth,
                &mut engine_cfg,
            ) {
                SetoptionResult::Variant => {
                    // NOTE: intentional deviation from master src/ucioption.cpp.
                    // master only updates the global rule table when a variant
                    // option changes.  Rust resets the position because a
                    // mid-game variant switch can invalidate MillState counts;
                    // callers can re-issue `position fen ...` afterwards.
                    rules = mill_rules_with_eval_weights(options.clone());
                    state = rules.initial_state(&[]);
                    state_history.clear();
                    shared_tt.bump_age();
                    sync_perfect_db(&mut engine_cfg, &options);
                    patch::sync_runtime(&engine_cfg.patch_path, engine_cfg.patch_avoid_traps);
                }
                SetoptionResult::ClearHash => {
                    // Mirror master src/ucioption.cpp:357 Clear Hash button.
                    // The shared TT uses fake-clean semantics, so this is an
                    // O(1) generation bump unless the age field wraps.
                    shared_tt.bump_age();
                }
                SetoptionResult::SearchConfig => {
                    if engine_cfg.hash_mb != old_hash_mb {
                        shared_tt = allocate_shared_tt(engine_cfg.hash_mb);
                    } else {
                        shared_tt.bump_age();
                    }
                    // A search/engine parameter changed; the perfect-database
                    // toggle and path live here, so reconcile the global handle.
                    sync_perfect_db(&mut engine_cfg, &options);
                    patch::sync_runtime(&engine_cfg.patch_path, engine_cfg.patch_avoid_traps);
                }
                SetoptionResult::Threads | SetoptionResult::Acknowledged => {}
                SetoptionResult::Unknown => {
                    println!("info string unsupported setoption: {line}");
                }
            }
        } else if line.starts_with("bench") {
            println!("info string bench is a separate subcommand; run: tgf bench");
        } else if line.starts_with("position") {
            finish_active_search(&mut active_search, &mut engine_cfg);
            let parsed = parse_position_command(&rules, line);
            state = parsed.state;
            state_history = parsed.history;
        } else if line == "d" {
            print_board_ascii(&state, &options);
        } else if line == "fen" {
            println!(
                "fen {}",
                rules.export_fen(&MillRules::decode_snapshot(state))
            );
        } else if line == "evaldecomp" {
            print_eval_decomp(&options, state);
        } else if line == "key" {
            let game = MillGame::new(options.clone());
            let wb = game.build_workbench(&state);
            println!("key {}", wb.key() as u32);
        } else if line == "hist" {
            print_repetition_history(&options, state, &state_history);
        } else if line == "moves" {
            print_legal_moves(&options, &state, &engine_cfg);
        } else if line.starts_with("gomtdf") {
            finish_active_search(&mut active_search, &mut engine_cfg);
            let (depth, first_guess) = parse_mtdf_debug_command(line);
            run_mtdf_debug_command(
                &options,
                state,
                &state_history,
                &engine_cfg,
                qsearch_max_depth,
                shared_tt.clone(),
                depth,
                first_guess,
            );
        } else if line.starts_with("goab") {
            finish_active_search(&mut active_search, &mut engine_cfg);
            let depth = parse_fixed_depth_debug_command(line, 15);
            run_alpha_beta_debug_command(
                &options,
                state,
                &state_history,
                &engine_cfg,
                qsearch_max_depth,
                shared_tt.clone(),
                depth,
            );
        } else if line.starts_with("rootprobe") {
            finish_active_search(&mut active_search, &mut engine_cfg);
            let (depth, betas) = parse_root_probe_debug_command(line);
            run_root_probe_debug_command(
                &options,
                state,
                &state_history,
                &engine_cfg,
                qsearch_max_depth,
                shared_tt.clone(),
                depth,
                &betas,
            );
        } else if line == "eval" {
            // Output the static evaluation of the current position.
            // Score is always from White's perspective (positive = White ahead),
            // matching the `info depth … score cp N` convention used by the
            // main search.  Useful for position analysis and bridge testing.
            let game = MillGame::new(options.clone());
            let wb = game.build_workbench(&state);
            let raw = MillEvaluator::score(&wb);
            let output_score = if state.side_to_move == 1 { -raw } else { raw };
            println!("info eval {}", format_score(output_score));
        } else if line.starts_with("go") {
            finish_active_search(&mut active_search, &mut engine_cfg);
            let go = parse_go_options(line, state.side_to_move, &engine_cfg);
            active_search = Some(spawn_search(
                options.clone(),
                ParsedPosition {
                    state,
                    history: state_history.clone(),
                },
                go,
                threads,
                qsearch_max_depth,
                shared_tt.clone(),
                engine_cfg.clone(),
            ));
        } else if line == "stop" {
            if let Some(active) = active_search.take() {
                active.abort_handle.request_abort();
                join_and_update(active, &mut engine_cfg);
            } else {
                // Match legacy single-line SearchEngine::print_bestmove output.
                println!("info score 0 bestmove none");
            }
        } else if line == "ponderhit" {
            // In ponder mode the engine switches from pondering to searching;
            // since tgf-cli doesn't implement ponder, silently ignore.
        } else if line == "quit" {
            finish_active_search(&mut active_search, &mut engine_cfg);
            break;
        } else {
            println!("info string unknown command: {line}");
        }
    }
    // Drain on EOF: join any in-flight search and emit its bestmove instead
    // of orphaning the spawned thread or losing the result entirely.
    finish_active_search(&mut active_search, &mut engine_cfg);
}

struct ActiveSearch {
    handle: JoinHandle<()>,
    abort_handle: SearchAbortHandle,
    receiver: mpsc::Receiver<SpawnResult>,
}

struct SpawnResult {
    depth: i32,
    result: SearchResult,
    /// Side to move at the root of the search tree (0=white, 1=black).
    /// Used by format_spawn_result to flip the score to White's perspective,
    /// matching master SearchEngine::emitCommand (P1-C.1).
    root_side_to_move: i8,
    /// If set, after printing the main search result the engine will score
    /// all legal moves at depth 2 and emit `info topn rank K move <m>
    /// score <s>` lines (best-first, up to this count) before bestmove.
    topn_request: Option<TopNRequest>,
}

/// Context needed to run per-move scoring for `go topn N`.
struct TopNRequest {
    topn: usize,
    options: MillVariantOptions,
    state: GameStateSnapshot,
    root_repetition_history: Vec<u64>,
    root_position_resets_repetition: bool,
}

fn spawn_search(
    options: MillVariantOptions,
    position: ParsedPosition,
    go: GoOptions,
    threads: usize,
    qsearch_max_depth: i32,
    shared_tt: SharedTt,
    cfg: EngineConfig,
) -> ActiveSearch {
    let state = position.state;
    let root_repetition_history =
        MillRules::repetition_history_from_snapshots(&state, &position.history);
    let root_position_resets_repetition =
        MillRules::root_position_resets_repetition_from_snapshots(&state, &position.history);
    let search_options = search_options_for_go(&cfg, &go);
    let depth = effective_search_depth(&options, &state, go.depth, &cfg);
    let root_side_to_move = state.side_to_move;
    let topn_request = go.topn.map(|topn| TopNRequest {
        topn,
        options: options.clone(),
        state,
        root_repetition_history: root_repetition_history.clone(),
        root_position_resets_repetition,
    });
    let (tx, rx) = mpsc::channel();
    let abort = Arc::new(AtomicBool::new(false));
    let abort_handle = SearchAbortHandle::from_arc(Arc::clone(&abort));

    // NOTE: master C++ keeps `Threads` for the engine commander pool only.
    // Mill search itself stays single-threaded. We mirror that default here;
    // set `UseLazySmp = true` (or TGF_USE_LAZY_SMP=1) to opt into Rust's
    // lazy-SMP variant for higher NPS.
    let use_lazy_smp = lazy_smp_is_allowed(&cfg, threads);

    let handle = if !use_lazy_smp {
        let abort_for_worker = Arc::clone(&abort);
        thread::spawn(move || {
            let mut searcher = mill_searcher_with_shared_tt(shared_tt);
            searcher.clear_tt();
            searcher.set_abort_flag(abort_for_worker);
            searcher.set_options(search_options);
            searcher.set_qsearch_max_depth(qsearch_max_depth);
            let result = run_configured_search(
                options,
                state,
                root_repetition_history,
                root_position_resets_repetition,
                depth,
                &cfg,
                &mut searcher,
            );
            let spawn = SpawnResult {
                depth,
                result,
                root_side_to_move,
                topn_request,
            };
            emit_topn_and_spawn_result(&spawn);
            let _ = tx.send(spawn);
        })
    } else {
        let abort_for_workers = Arc::clone(&abort);
        thread::spawn(move || {
            let workers =
                lazy_smp_workers_for_go(threads, &go, search_options.time_limit_ms.is_some());
            shared_tt.bump_age();
            let outcome = run_configured_lazy_smp_search(LazySmpSearchInput {
                options,
                state,
                root_repetition_history,
                root_position_resets_repetition,
                depth,
                cfg,
                qsearch_max_depth,
                search_options,
                shared_tt,
                abort: abort_for_workers,
                workers,
            });
            let spawn = SpawnResult {
                depth: outcome.depth,
                result: outcome.result,
                root_side_to_move,
                topn_request,
            };
            emit_topn_and_spawn_result(&spawn);
            let _ = tx.send(spawn);
        })
    };

    ActiveSearch {
        handle,
        abort_handle,
        receiver: rx,
    }
}

#[derive(Clone, Debug)]
struct LazySmpWorkerOutcome {
    depth: i32,
    result: SearchResult,
    root_moves: Vec<RootMoveSummary>,
}

struct LazySmpSearchInput {
    options: MillVariantOptions,
    state: GameStateSnapshot,
    root_repetition_history: Vec<u64>,
    root_position_resets_repetition: bool,
    depth: i32,
    cfg: EngineConfig,
    qsearch_max_depth: i32,
    search_options: SearchOptions,
    shared_tt: SharedTt,
    abort: Arc<AtomicBool>,
    workers: Vec<LazySmpWorker>,
}

fn lazy_smp_is_allowed(cfg: &EngineConfig, threads: usize) -> bool {
    // Shuffling is the UCI/Flutter "Move randomly" switch.  When it is off,
    // preserve same-position bestmove stability by avoiding shared-TT races.
    cfg.use_lazy_smp && threads > 1 && cfg.shuffling
}

fn lazy_smp_workers_for_go(
    threads: usize,
    go: &GoOptions,
    allow_depth_stagger: bool,
) -> Vec<LazySmpWorker> {
    assert!(threads > 1, "lazy SMP requires at least two UCI threads");
    let fixed_positive_depth = go.depth_is_explicit && go.depth > 0;
    let stagger_depth = allow_depth_stagger && !fixed_positive_depth;
    (0..threads)
        .map(|i| LazySmpWorker {
            extra_depth: if stagger_depth { (i % 2) as i32 } else { 0 },
        })
        .collect()
}

fn run_configured_lazy_smp_search(input: LazySmpSearchInput) -> LazySmpWorkerOutcome {
    let LazySmpSearchInput {
        options,
        state,
        root_repetition_history,
        root_position_resets_repetition,
        depth,
        cfg,
        qsearch_max_depth,
        search_options,
        shared_tt,
        abort,
        workers,
    } = input;
    assert!(!workers.is_empty(), "lazy SMP must run at least one worker");

    let mut handles = Vec::with_capacity(workers.len());
    for (worker_index, worker) in workers.iter().copied().enumerate() {
        let options_for_worker = options.clone();
        let root_repetition_history_for_worker = root_repetition_history.clone();
        let shared_tt_for_worker = shared_tt.clone();
        let abort_for_worker = Arc::clone(&abort);
        let mut cfg_for_worker = cfg.clone();
        cfg_for_worker.use_perfect_database = false;
        cfg_for_worker.active_perfect_db = None;
        let search_options_for_worker =
            lazy_smp_search_options_for_worker(search_options, worker_index);
        let worker_depth = (depth + worker.extra_depth).max(1);
        handles.push(thread::spawn(move || {
            let mut searcher = mill_searcher_with_shared_tt(shared_tt_for_worker);
            searcher.set_abort_flag(abort_for_worker);
            searcher.set_options(search_options_for_worker);
            searcher.set_qsearch_max_depth(qsearch_max_depth);
            let result = run_configured_search(
                options_for_worker,
                state,
                root_repetition_history_for_worker,
                root_position_resets_repetition,
                worker_depth,
                &cfg_for_worker,
                &mut searcher,
            );
            let root_moves = searcher.root_moves().to_vec();
            LazySmpWorkerOutcome {
                depth: worker_depth,
                result,
                root_moves,
            }
        }));
    }

    let mut outcomes = Vec::with_capacity(handles.len());
    let mut total_nodes = 0_u64;
    for handle in handles {
        let outcome = handle
            .join()
            .expect("lazy SMP worker should return a SearchResult");
        total_nodes = total_nodes.saturating_add(outcome.result.nodes);
        outcomes.push(outcome);
    }

    let mut best = select_lazy_smp_outcome(&outcomes);
    best.result.nodes = total_nodes;
    apply_perfect_database_result(&mut best.result, &options, &state, &cfg);
    patch::apply_patch_avoid_traps_result(&mut best.result, &options, &state);
    best
}

fn lazy_smp_search_options_for_worker(
    mut options: SearchOptions,
    worker_index: usize,
) -> SearchOptions {
    if worker_index > 0 {
        options.move_order_context.shuffle_seed =
            mix_lazy_smp_worker_seed(options.move_order_context.shuffle_seed, worker_index as u64);
    }
    options
}

fn mix_lazy_smp_worker_seed(seed: u64, worker_index: u64) -> u64 {
    let mut x = seed ^ worker_index.wrapping_mul(0x9E37_79B9_7F4A_7C15);
    x = (x ^ (x >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    x = (x ^ (x >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    x ^ (x >> 31)
}

fn select_lazy_smp_outcome(outcomes: &[LazySmpWorkerOutcome]) -> LazySmpWorkerOutcome {
    assert!(!outcomes.is_empty(), "lazy SMP must have worker outcomes");
    let mut best = outcomes[0].clone();
    for candidate in outcomes.iter().skip(1) {
        if lazy_smp_outcome_is_better_with_votes(candidate, &best, outcomes) {
            best = candidate.clone();
        }
    }
    best
}

fn lazy_smp_outcome_is_better_with_votes(
    candidate: &LazySmpWorkerOutcome,
    current: &LazySmpWorkerOutcome,
    outcomes: &[LazySmpWorkerOutcome],
) -> bool {
    let candidate_valid = lazy_smp_outcome_is_valid(candidate);
    let current_valid = lazy_smp_outcome_is_valid(current);
    if candidate_valid != current_valid {
        return candidate_valid;
    }
    if candidate_valid {
        let candidate_vote = lazy_smp_bestmove_vote(outcomes, candidate.result.best_action);
        let current_vote = lazy_smp_bestmove_vote(outcomes, current.result.best_action);
        if candidate_vote != current_vote {
            return candidate_vote > current_vote;
        }

        let candidate_weight = lazy_smp_thread_vote_weight(outcomes, candidate);
        let current_weight = lazy_smp_thread_vote_weight(outcomes, current);
        if candidate_weight != current_weight {
            return candidate_weight > current_weight;
        }
    }
    lazy_smp_outcome_is_better(candidate, current)
}

fn lazy_smp_bestmove_vote(outcomes: &[LazySmpWorkerOutcome], action: Action) -> i64 {
    outcomes
        .iter()
        .filter(|outcome| lazy_smp_outcome_is_valid(outcome))
        .filter(|outcome| lazy_smp_outcome_vote_action(outcome) == action)
        .map(|outcome| lazy_smp_thread_vote_weight(outcomes, outcome))
        .sum()
}

fn lazy_smp_outcome_vote_action(outcome: &LazySmpWorkerOutcome) -> Action {
    if let Some(root_move) = outcome.root_moves.first()
        && root_move.action == outcome.result.best_action
    {
        root_move.action
    } else {
        outcome.result.best_action
    }
}

fn lazy_smp_thread_vote_weight(
    outcomes: &[LazySmpWorkerOutcome],
    outcome: &LazySmpWorkerOutcome,
) -> i64 {
    const STOCKFISH_THREAD_VOTE_MARGIN: i64 = 14;
    assert!(!outcomes.is_empty(), "lazy SMP vote requires outcomes");
    let min_score = outcomes
        .iter()
        .filter(|outcome| lazy_smp_outcome_is_valid(outcome))
        .map(|outcome| i64::from(lazy_smp_vote_score(outcome)))
        .min()
        .unwrap_or(0);
    let score_delta =
        i64::from(lazy_smp_vote_score(outcome)) - min_score + STOCKFISH_THREAD_VOTE_MARGIN;
    score_delta.max(1) * i64::from(outcome.depth.max(1))
}

fn lazy_smp_vote_score(outcome: &LazySmpWorkerOutcome) -> i32 {
    outcome
        .root_moves
        .iter()
        .find(|root_move| root_move.action == outcome.result.best_action)
        .map(|root_move| root_move.value)
        .unwrap_or(outcome.result.score)
}

fn lazy_smp_outcome_is_better(
    candidate: &LazySmpWorkerOutcome,
    current: &LazySmpWorkerOutcome,
) -> bool {
    let candidate_valid = lazy_smp_outcome_is_valid(candidate);
    let current_valid = lazy_smp_outcome_is_valid(current);
    if candidate_valid != current_valid {
        return candidate_valid;
    }
    if candidate.depth != current.depth {
        return candidate.depth > current.depth;
    }
    candidate.result.score > current.result.score
}

fn lazy_smp_outcome_is_valid(outcome: &LazySmpWorkerOutcome) -> bool {
    !outcome.result.best_action.is_none() || outcome.result.draw_reason.is_some()
}

fn print_eval_decomp(options: &MillVariantOptions, state: GameStateSnapshot) {
    let game = MillGame::new(options.clone());
    let wb = game.build_workbench(&state);
    let decoded = MillRules::decode_snapshot(state);
    let remove_own = decoded.remove_own_pieces();
    println!(
        "evaldecomp phase={} mob={} onbW={} onbB={} inhW={} inhB={} \
rmW={} rmB={} ownW={} ownB={} stm={} eval={}",
        decoded.phase() as u8,
        decoded.mobility_diff(),
        decoded.pieces_on_board()[0],
        decoded.pieces_on_board()[1],
        decoded.pieces_in_hand()[0],
        decoded.pieces_in_hand()[1],
        decoded.pending_removals()[0],
        decoded.pending_removals()[1],
        remove_own[0],
        remove_own[1],
        decoded.side_to_move(),
        MillEvaluator::score(&wb)
    );
}

fn run_configured_search(
    options: MillVariantOptions,
    state: GameStateSnapshot,
    root_repetition_history: Vec<u64>,
    root_position_resets_repetition: bool,
    depth: i32,
    cfg: &EngineConfig,
    searcher: &mut Searcher<MillGame>,
) -> SearchResult {
    let root_outcome = MillRules::new(options.clone()).outcome(&state);
    if matches!(root_outcome.kind, tgf_core::OutcomeKind::Draw)
        && root_outcome.reason != "drawFullBoard"
    {
        return SearchResult::draw_short_circuit("draw");
    }

    // Mirror master src/search_engine.cpp:381 executeSearch: route the
    // user-visible Algorithm option into the actual search implementation.
    let mut game = MillGame::new_with_repetition_context(
        options.clone(),
        root_repetition_history,
        root_position_resets_repetition,
    );
    if let Some(weights) = eval_weights_from_env() {
        game.set_eval_weights(weights);
    }
    let mut wb = game.build_workbench(&state);
    let mut value = mtdf_initial_guess(cfg, state.side_to_move);
    let mut best_so_far = SearchResult::default_none();
    let run_ids = cfg.move_time_ms > 0 || cfg.ids_enabled;
    if run_ids {
        for d in 2..depth {
            let result = run_algorithm_at_depth(searcher, &mut wb, cfg, d, value);
            value = result.score;
            if !searcher.was_aborted() {
                best_so_far = result;
            }
            if searcher.was_aborted() {
                break;
            }
        }
    }
    let mut result = if searcher.was_aborted() && !best_so_far.best_action.is_none() {
        best_so_far
    } else {
        let final_result = run_algorithm_at_depth(searcher, &mut wb, cfg, depth, value);
        select_completed_search_result(final_result, best_so_far, searcher.was_aborted())
    };

    apply_perfect_database_result(&mut result, &options, &state, cfg);
    patch::apply_patch_avoid_traps_result(&mut result, &options, &state);

    // Fallback chain mirroring master SearchEngine::executeSearch
    // (src/search_engine.cpp:643-680).  When the main search returns
    // no best move, master tries a fixed depth=4 quick search; if that
    // still fails it calls Search::random_search.  In _DEBUG master
    // skips the random fallback to keep the bug surface obvious.  We
    // surface the same pattern: assert(false) in debug, depth-4 +
    // random in release.
    if result.best_action.is_none() {
        debug_assert!(
            false,
            "main search returned MOVE_NONE; bug must be diagnosed before \
             release-mode fallback masks it",
        );
        let mut quick_searcher = mill_searcher();
        quick_searcher.set_options(SearchOptions {
            depth_extension: cfg.depth_extension,
            ..SearchOptions::default()
        });
        // Fresh workbench: master rewinds via Sanmill::Stack<Position>;
        // here we just rebuild from the original snapshot.
        let mut quick_wb = MillGame::new(options.clone()).build_workbench(&state);
        let quick_result = quick_searcher.search(&mut quick_wb, 4);
        if !quick_result.best_action.is_none() {
            result = quick_result;
        } else {
            let mut rand_searcher = mill_searcher();
            rand_searcher.set_random_seed(search_shuffle_seed());
            let mut rand_wb = MillGame::new(options).build_workbench(&state);
            result = rand_searcher.random_search(&mut rand_wb);
        }
    }
    result
}

fn apply_perfect_database_result(
    result: &mut SearchResult,
    options: &MillVariantOptions,
    state: &GameStateSnapshot,
    cfg: &EngineConfig,
) {
    // Perfect-database consultation (P-DB): when enabled and the active rule
    // variant has matching database assets, prefer the database move over the
    // search result.  Emits an `aimovetype` info line mirroring the Flutter
    // shell: `consensus` when search and DB agree, `perfect` when the DB
    // overrides.
    if cfg.use_perfect_database
        && let Some(pd_action) = try_perfect_best_action(options, state, perfect_move_ordering(cfg))
    {
        let same =
            action_to_uci(result.best_action).as_deref() == action_to_uci(pd_action).as_deref();
        if !same {
            result.best_action = pd_action;
        }
        println!(
            "info string aimovetype={}",
            if same { "consensus" } else { "perfect" }
        );
    }
}

fn select_completed_search_result(
    result: SearchResult,
    best_so_far: SearchResult,
    aborted: bool,
) -> SearchResult {
    if aborted && !best_so_far.best_action.is_none() {
        best_so_far
    } else {
        result
    }
}

fn run_algorithm_at_depth(
    searcher: &mut Searcher<MillGame>,
    wb: &mut tgf_mill::MillWorkbench,
    cfg: &EngineConfig,
    depth: i32,
    first_guess: i32,
) -> SearchResult {
    match cfg.algorithm {
        // Master executeSearch currently routes both Algorithm 0 and 1 to
        // Search::search; Rust search_pvs remains available but is not the
        // master-equivalent route here.
        0 | 1 => searcher.search(wb, depth),
        2 => searcher.search_mtdf_with_guess(wb, depth, first_guess),
        3 => run_mcts_search(wb, cfg),
        4 => {
            searcher.set_random_seed(search_shuffle_seed());
            searcher.random_search(wb)
        }
        _ => searcher.search(wb, depth),
    }
}

fn search_options_for_go(cfg: &EngineConfig, go: &GoOptions) -> SearchOptions {
    let (enable_prefetch, prefetch_all) = prefetch_mode_from_env();
    SearchOptions {
        depth_extension: cfg.depth_extension,
        node_limit: go.node_limit,
        time_limit_ms: go.movetime_ms,
        allow_null_move: false,
        // Master shuffles the global movePriorityList before generation.
        // Mill's generate_legal_ctx already mirrors that list, so do not
        // additionally shuffle the root action list here.
        shuffle_root: false,
        // Master prefetches TT child entries before recursive search.
        // Rust keeps this opt-in because moving-entry measurements show
        // TT prefetch costs more than it saves on this implementation.
        // TGF_PREFETCH_MODE=first or all enables targeted diagnostics.
        enable_prefetch,
        prefetch_all,
        // Master executeSearch uses full windows for every IDS pass.
        enable_aspiration_window: false,
        move_order_context: move_order_context(cfg),
    }
}

fn debug_searcher(
    cfg: &EngineConfig,
    qsearch_max_depth: i32,
    shared_tt: SharedTt,
    depth: i32,
) -> Searcher<MillGame> {
    let mut searcher = mill_searcher_with_shared_tt(shared_tt);
    searcher.clear_tt();
    searcher.set_options(search_options_for_go(
        cfg,
        &GoOptions {
            depth,
            depth_is_explicit: true,
            movetime_ms: None,
            node_limit: None,
            topn: None,
        },
    ));
    searcher.set_qsearch_max_depth(qsearch_max_depth);
    searcher
}

fn debug_workbench(
    options: &MillVariantOptions,
    state: GameStateSnapshot,
    state_history: &[GameStateSnapshot],
) -> tgf_mill::MillWorkbench {
    let root_repetition_history =
        MillRules::repetition_history_from_snapshots(&state, state_history);
    let root_position_resets_repetition =
        MillRules::root_position_resets_repetition_from_snapshots(&state, state_history);
    MillGame::new_with_repetition_context(
        options.clone(),
        root_repetition_history,
        root_position_resets_repetition,
    )
    .build_workbench(&state)
}

fn print_repetition_history(
    options: &MillVariantOptions,
    state: GameStateSnapshot,
    state_history: &[GameStateSnapshot],
) {
    let root_repetition_history =
        MillRules::repetition_history_from_snapshots(&state, state_history);
    let root_position_resets_repetition =
        MillRules::root_position_resets_repetition_from_snapshots(&state, state_history);
    let game = MillGame::new_with_repetition_context(
        options.clone(),
        root_repetition_history.clone(),
        root_position_resets_repetition,
    );
    let wb = game.build_workbench(&state);
    let key = wb.key();
    let count_all = root_repetition_history
        .iter()
        .filter(|history_key| **history_key == key)
        .count();
    let current_count = root_repetition_history
        .iter()
        .take(root_repetition_history.len().saturating_sub(1))
        .filter(|history_key| **history_key == key)
        .count();
    let last_is_current = root_repetition_history.last().copied() == Some(key);
    println!(
        "hist key={} len={} current_count={} count_all={} last_is_current={} root_reset={} snapshots={}",
        key as u32,
        root_repetition_history.len(),
        current_count,
        count_all,
        last_is_current,
        root_position_resets_repetition,
        state_history.len()
    );
}

fn print_legal_moves(options: &MillVariantOptions, state: &GameStateSnapshot, cfg: &EngineConfig) {
    let game = MillGame::new(options.clone());
    let wb = game.build_workbench(state);
    let mut legal = SearchActionList::new();
    MillGame::generate_legal_ctx(&wb, &mut legal, &move_order_context(cfg));
    let mut line = String::from("moves");
    for action in legal.as_slice().iter().copied() {
        if let Some(token) = action_to_uci(action) {
            line.push(' ');
            line.push_str(&token);
        }
    }
    println!("{line}");
}

fn parse_fixed_depth_debug_command(line: &str, default_depth: i32) -> i32 {
    line.split_whitespace()
        .nth(1)
        .and_then(|token| token.parse::<i32>().ok())
        .unwrap_or(default_depth)
        .max(1)
}

fn parse_mtdf_debug_command(line: &str) -> (i32, i32) {
    let mut tokens = line.split_whitespace().skip(1);
    let depth = tokens
        .next()
        .and_then(|token| token.parse::<i32>().ok())
        .unwrap_or(15)
        .max(1);
    let first_guess = tokens
        .next()
        .and_then(|token| token.parse::<i32>().ok())
        .unwrap_or(0);
    (depth, first_guess)
}

fn parse_root_probe_debug_command(line: &str) -> (i32, Vec<i32>) {
    let mut tokens = line.split_whitespace().skip(1);
    let depth = tokens
        .next()
        .and_then(|token| token.parse::<i32>().ok())
        .unwrap_or(15)
        .max(1);
    let betas = tokens
        .filter_map(|token| token.parse::<i32>().ok())
        .collect::<Vec<_>>();
    let betas = if betas.is_empty() { vec![0] } else { betas };
    (depth, betas)
}

fn run_alpha_beta_debug_command(
    options: &MillVariantOptions,
    state: GameStateSnapshot,
    state_history: &[GameStateSnapshot],
    cfg: &EngineConfig,
    qsearch_max_depth: i32,
    shared_tt: SharedTt,
    depth: i32,
) {
    let mut wb = debug_workbench(options, state, state_history);
    let mut searcher = debug_searcher(cfg, qsearch_max_depth, shared_tt, depth);
    let result = searcher.search(&mut wb, depth);
    println!(
        "goab depth={} value={} bestmove {} nodes {}",
        depth,
        result.score,
        action_to_uci(result.best_action).unwrap_or_else(|| "none".to_owned()),
        result.nodes
    );
}

#[allow(clippy::too_many_arguments)]
fn run_root_probe_debug_command(
    options: &MillVariantOptions,
    state: GameStateSnapshot,
    state_history: &[GameStateSnapshot],
    cfg: &EngineConfig,
    qsearch_max_depth: i32,
    shared_tt: SharedTt,
    depth: i32,
    betas: &[i32],
) {
    let mut wb = debug_workbench(options, state, state_history);
    let mut searcher = debug_searcher(cfg, qsearch_max_depth, shared_tt, depth);
    for beta in betas {
        let (value, best_action, rows) = searcher.debug_root_probe(&mut wb, depth, beta - 1, *beta);
        println!(
            "rootprobe depth={} beta={} value={} bestmove {} nodes {} repcuts {}",
            depth,
            beta,
            value,
            action_to_uci(best_action).unwrap_or_else(|| "none".to_owned()),
            searcher.nodes(),
            searcher.repetition_cuts()
        );
        for row in rows {
            let child_tt = row
                .child_tt
                .map(|entry| format!("{}:{}:{}", entry.bound, entry.depth, entry.value))
                .unwrap_or_else(|| "miss".to_owned());
            println!(
                "  rootmove {} key={} value={} nodes={} cutoff={} prett={}",
                action_to_uci(row.action).unwrap_or_else(|| "none".to_owned()),
                row.child_key as u32,
                row.value,
                row.nodes,
                row.cutoff,
                child_tt
            );
        }
    }
}

#[allow(clippy::too_many_arguments)]
fn run_mtdf_debug_command(
    options: &MillVariantOptions,
    state: GameStateSnapshot,
    state_history: &[GameStateSnapshot],
    cfg: &EngineConfig,
    qsearch_max_depth: i32,
    shared_tt: SharedTt,
    depth: i32,
    first_guess: i32,
) {
    let mut wb = debug_workbench(options, state, state_history);
    let mut searcher = debug_searcher(cfg, qsearch_max_depth, shared_tt, depth);
    let mut iterations = 0usize;
    let result = searcher.search_mtdf_with_guess_trace_roots(
        &mut wb,
        depth,
        first_guess,
        &mut |iteration, beta, g, best_action, nodes, repetition_cuts| {
            iterations = iteration + 1;
            println!(
                "  mtdf-iter {} beta={} g={} best={} nodes={} repcuts={}",
                iteration,
                beta,
                g,
                action_to_uci(best_action).unwrap_or_else(|| "none".to_owned()),
                nodes,
                repetition_cuts,
            );
        },
        &mut |iteration, action, child_key, child_tt, value, nodes, cutoff| {
            let child_tt = child_tt
                .map(|entry| format!("{}:{}:{}", entry.bound, entry.depth, entry.value))
                .unwrap_or_else(|| "miss".to_owned());
            println!(
                "  mtdf-rootmove iter={} {} key={} value={} nodes={} cutoff={} prett={}",
                iteration,
                action_to_uci(action).unwrap_or_else(|| "none".to_owned()),
                child_key as u32,
                value,
                nodes,
                cutoff,
                child_tt,
            );
        },
    );
    println!(
        "gomtdf depth={} guess={} iterations={} value={} bestmove {} nodes {} repcuts {} tthits {} ttmisses {}",
        depth,
        first_guess,
        iterations,
        result.score,
        action_to_uci(result.best_action).unwrap_or_else(|| "none".to_owned()),
        result.nodes,
        searcher.repetition_cuts(),
        searcher.tt_hits(),
        searcher.tt_misses()
    );
}

/// Match the perfect-database best-move token against the current legal
/// actions.  Returns `None` when the DB is unavailable, the variant is not
/// covered by the loaded database, or no legal action matches (see
/// `perfect_db::best_move_token_for_state_with_ordering`).
fn try_perfect_best_action(
    options: &MillVariantOptions,
    state: &GameStateSnapshot,
    ordering: perfect_db::PerfectMoveOrdering,
) -> Option<Action> {
    let mill_state = MillRules::decode_snapshot(*state);
    let token = perfect_db::best_move_token_for_state_with_ordering(
        &mill_state,
        options,
        state.side_to_move,
        ordering,
    )?;
    let rules = MillRules::new(options.clone());
    let mut legal = ActionList::<256>::default();
    rules.legal_actions(state, &mut legal);
    legal
        .as_slice()
        .iter()
        .copied()
        .find(|action| action_to_uci(*action).as_deref() == Some(token.as_str()))
}

fn run_mcts_search(wb: &mut tgf_mill::MillWorkbench, cfg: &EngineConfig) -> SearchResult {
    let pieces_on_board = wb.pieces_on_board();
    let all_on_board = u32::from(pieces_on_board[0]) + u32::from(pieces_on_board[1]);
    let iterations = if all_on_board == 0 {
        1
    } else {
        u32::from(cfg.skill_level).saturating_mul(2048).max(1)
    };
    let mut mcts = MctsSearcher::<MillGame>::new();
    mcts.set_random_seed(search_shuffle_seed());
    mcts.set_policy(SearchPolicy {
        quiescence_kind_tag: Some(MillActionKind::Remove as i16),
        ..Default::default()
    });
    let mcts_result = mcts.search_with_options(
        wb,
        MctsOptions {
            iterations,
            playout_depth: 6,
            time_limit_ms: (cfg.move_time_ms > 0).then(|| u64::from(cfg.move_time_ms)),
            exploration: 0.5,
            ab_assist_depth: 6,
            // CLI go path runs in the foreground UCI loop; keep MCTS
            // single-threaded here.  Multi-thread MCTS is exposed via
            // tgf_search::mcts_search_parallel for callers that own
            // their own scheduling.
            num_threads: Some(1),
            move_order_context: move_order_context_with_algorithm(cfg, MoveOrderAlgorithm::Mcts),
        },
    );
    // mcts_result.score now mirrors master `monte_carlo_tree_search`
    // best_value (piece-count diff * VALUE_EACH_PIECE), so we no
    // longer need to recompute mill_material_score(wb) here.
    let _ = wb; // formerly fed mill_material_score
    SearchResult {
        best_action: mcts_result.best_action,
        score: mcts_result.score,
        nodes: mcts_result.visits as u64,
        draw_reason: None,
    }
}

fn effective_search_depth(
    options: &MillVariantOptions,
    state: &GameStateSnapshot,
    requested_depth: i32,
    cfg: &EngineConfig,
) -> i32 {
    let requested_depth = if requested_depth > 0 {
        requested_depth
    } else {
        let mill_state = MillRules::decode_snapshot(*state);
        let runtime = EngineRuntimeOptions {
            skill_level: cfg.skill_level,
            draw_on_human_experience: cfg.draw_on_human_experience,
            developer_mode: cfg.developer_mode,
        };
        recommended_search_depth(&mill_state, options, &runtime).max(1)
    };
    // ai_is_lazy mirrors master src/search_engine.cpp::executeSearch
    // (lines around 401-413): when the previous root score reports a
    // material advantage greater than 1 piece (np = last_best_value /
    // VALUE_EACH_PIECE), cap the originDepth to 1 (when requested < 4)
    // or 4 (otherwise) so the engine plays "lazy" winning moves.  We
    // intentionally use the signed previous score rather than abs(): a
    // losing position must keep its full search depth so the AI can
    // play the best defensive line.
    if cfg.ai_is_lazy {
        const VALUE_EACH_PIECE: i32 = 5;
        let np = cfg.last_best_value / VALUE_EACH_PIECE;
        if np > 1 {
            return if requested_depth < 4 { 1 } else { 4 };
        }
    }
    requested_depth.max(1)
}

fn move_order_context(cfg: &EngineConfig) -> MoveOrderContext {
    move_order_context_with_algorithm(
        cfg,
        match cfg.algorithm {
            0 => MoveOrderAlgorithm::AlphaBeta,
            2 => MoveOrderAlgorithm::Mtdf,
            3 => MoveOrderAlgorithm::Mcts,
            4 => MoveOrderAlgorithm::Random,
            _ => MoveOrderAlgorithm::Pvs,
        },
    )
}

fn move_order_context_with_algorithm(
    cfg: &EngineConfig,
    algorithm: MoveOrderAlgorithm,
) -> MoveOrderContext {
    MoveOrderContext {
        algorithm,
        skill_level: cfg.skill_level,
        shuffling: cfg.shuffling,
        hash_move: None,
        shuffle_seed: search_shuffle_seed(),
    }
}

fn mtdf_initial_guess(cfg: &EngineConfig, root_side_to_move: i8) -> i32 {
    if cfg.last_best_value_side_to_move == root_side_to_move {
        cfg.last_best_value
    } else {
        0
    }
}

fn search_shuffle_seed() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos() as u64)
        .unwrap_or(0)
}

fn finish_active_search(slot: &mut Option<ActiveSearch>, cfg: &mut EngineConfig) {
    if let Some(active) = slot.take() {
        join_and_update(active, cfg);
    }
}

fn take_finished_search(slot: &mut Option<ActiveSearch>) -> Option<SpawnResult> {
    let active = slot.as_ref()?;
    match active.receiver.try_recv() {
        Ok(spawn) => {
            let active = slot.take().expect("active search present");
            let _ = active.handle.join();
            Some(spawn)
        }
        Err(mpsc::TryRecvError::Empty) => None,
        Err(mpsc::TryRecvError::Disconnected) => {
            let active = slot.take().expect("active search present");
            let _ = active.handle.join();
            Some(SpawnResult {
                depth: 0,
                result: SearchResult::default_none(),
                root_side_to_move: 0,
                topn_request: None,
            })
        }
    }
}

fn drain_finished_search(slot: &mut Option<ActiveSearch>, cfg: &mut EngineConfig) {
    if let Some(spawn) = take_finished_search(slot) {
        update_last_best_value(cfg, &spawn);
    }
}

// NOTE: intentional deviation from master src/search_engine.cpp:64.
// Rust emits standard UCI ("info depth ... score cp|mate ... nodes ...
// bestmove ...") instead of the legacy "info score N bestmove M" string.
// Flutter's parser accepts both shapes.
/// Format the score as a UCI score string (P2-M).
/// Scores in the mate range (|score| > VALUE_MATE_IN_MAX_PLY) are
/// formatted as "score mate N" (positive = we win, negative = we lose).
/// Other scores are formatted as "score cp N" (centipawn-style).
/// VALUE_MATE = 80, MAX_PLY = 32 → VALUE_MATE_IN_MAX_PLY = 80 - 32 = 48.
fn format_score(output_score: i32) -> String {
    const VALUE_MATE: i32 = 80;
    const MAX_PLY: i32 = 32;
    const VALUE_MATE_IN_MAX_PLY: i32 = VALUE_MATE - MAX_PLY;
    if output_score.abs() > VALUE_MATE_IN_MAX_PLY {
        let mate_in = if output_score > 0 {
            (VALUE_MATE - output_score + 1) / 2
        } else {
            -(VALUE_MATE + output_score + 1) / 2
        };
        format!("score mate {mate_in}")
    } else {
        format!("score cp {output_score}")
    }
}

fn join_and_update(active: ActiveSearch, cfg: &mut EngineConfig) {
    let _ = active.handle.join();
    if let Ok(spawn) = active.receiver.recv() {
        update_last_best_value(cfg, &spawn);
    }
}

/// Emit `info topn` lines (if requested) then the main `bestmove` line.
/// Called from the search thread, where all stdout output for one `go`
/// command must be serialised.
fn emit_topn_and_spawn_result(spawn: &SpawnResult) {
    if let Some(ref req) = spawn.topn_request {
        // Score all legal moves at a fixed shallow depth and emit ranked lines
        // before the bestmove.  Depth 2 balances quality against speed: at
        // depth 2 each move is evaluated in O(branching²) which is < 24² ≈ 576
        // nodes per move — fast even for the max 24 legal placements.
        const TOPN_DEPTH: i32 = 2;
        let mut scored: Vec<(Action, i32)> = score_moves_at_depth(
            &req.options,
            req.state,
            req.root_repetition_history.clone(),
            req.root_position_resets_repetition,
            TOPN_DEPTH,
        );
        // Sort by score (best = highest from side-to-move perspective).
        scored.sort_by_key(|b| std::cmp::Reverse(b.1));
        let topn = req.topn.min(scored.len());
        for (rank, (action, score)) in scored.iter().take(topn).enumerate() {
            let move_str = action_to_uci(*action).unwrap_or_else(|| "none".to_owned());
            // Flip score to White perspective so callers do not need to know
            // which side is to move.
            let output_score = if req.state.side_to_move == 1 {
                -score
            } else {
                *score
            };
            println!(
                "info topn rank {} move {} {}",
                rank + 1,
                move_str,
                format_score(output_score)
            );
        }
    }
    println!("{}", format_spawn_result(spawn));
}

/// Score all legal moves from `state` at `depth` using independent searches
/// and return `(action, score)` pairs (score is side-to-move perspective).
fn score_moves_at_depth(
    options: &MillVariantOptions,
    state: GameStateSnapshot,
    root_repetition_history: Vec<u64>,
    root_position_resets_repetition: bool,
    depth: i32,
) -> Vec<(Action, i32)> {
    let rules = MillRules::new(options.clone());
    let mut legal = ActionList::<256>::new();
    rules.legal_actions(&state, &mut legal);
    let mut result = Vec::with_capacity(legal.len());
    for action in legal.iter().copied() {
        let next = rules.apply(&state, action);
        // Evaluate from the opponent's perspective at depth-1, then negate so
        // the score is from the current side's point of view.
        let game = MillGame::new_with_repetition_context(
            options.clone(),
            root_repetition_history.clone(),
            root_position_resets_repetition,
        );
        let mut wb = game.build_workbench(&next);
        let mut searcher = Searcher::<MillGame>::new();
        searcher.set_policy(SearchPolicy {
            quiescence_kind_tag: Some(MillActionKind::Remove as i16),
            ..Default::default()
        });
        let child_result = searcher.search(&mut wb, (depth - 1).max(0));
        result.push((action, -child_result.score));
    }
    result
}

fn update_last_best_value(cfg: &mut EngineConfig, spawn: &SpawnResult) {
    cfg.last_best_value = spawn.result.score;
    cfg.last_best_value_side_to_move = spawn.root_side_to_move;
}

fn format_spawn_result(spawn: &SpawnResult) -> String {
    // Mirror master SearchEngine::emitCommand
    // (src/search_engine.cpp:38-43, "outputValue = ... ? -bestvalue
    // : bestvalue"): the UCI score is always reported from White's
    // perspective.  When Black is to move the mover-relative search
    // score is negated on the way out, while the internal
    // `cfg.last_best_value` (used by ai_is_lazy depth capping) keeps
    // the side-to-move convention.  The FRB engine_event helper
    // applies the same swap independently for the Flutter shell --
    // see `crates/tgf-frb/src/engine_event.rs::best_move_with_notation`.
    let output_score = if spawn.root_side_to_move == 1 {
        -spawn.result.score
    } else {
        spawn.result.score
    };
    let score_str = format_score(output_score);
    let uci = if spawn.result.draw_reason.is_some() {
        "draw".to_owned()
    } else {
        action_to_uci(spawn.result.best_action).unwrap_or_else(|| "none".to_owned())
    };
    format!(
        "info depth {} {} nodes {} bestmove {}",
        spawn.depth, score_str, spawn.result.nodes, uci
    )
}

#[cfg(test)]
mod tests;
