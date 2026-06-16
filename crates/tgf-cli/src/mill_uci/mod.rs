// SPDX-License-Identifier: GPL-3.0-or-later
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
    Action, ActionList, Game, GameRules, GameStateSnapshot, MoveOrderAlgorithm, MoveOrderContext,
};
use tgf_mill::{
    EngineRuntimeOptions, MillActionKind, MillGame, MillRules, MillVariantOptions,
    recommended_search_depth,
};
use tgf_search::{
    LazySmpWorker, MctsOptions, MctsSearcher, SearchAbortHandle, SearchOptions, SearchPolicy,
    SearchResult, Searcher, SharedTt, lazy_smp_search,
};

mod bench;
mod board;
mod setoption;

pub(crate) use bench::print_benchmark_toml;
#[cfg(test)]
use board::board_ascii_lines;
use board::{
    GoOptions, ParsedPosition, action_to_uci, parse_go_options, parse_position_command,
    print_board_ascii, print_uci_options,
};
use setoption::{SetoptionResult, apply_setoption};

/// `TGF_TT_CLUSTER_BITS` (10–26) selects `2^(bits+1)` TT slots; see
/// `tgf_search::Searcher::new_with_tt_cluster_bits`.  Default 23 to
/// match master `TRANSPOSITION_TABLE_SIZE = 0x1000000` (16 Mi slots).
fn tt_cluster_bits_from_env() -> u32 {
    std::env::var("TGF_TT_CLUSTER_BITS")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(23)
        .clamp(10, 26)
}

fn mill_searcher() -> Searcher<MillGame> {
    let mut s = Searcher::new_with_tt_cluster_bits(tt_cluster_bits_from_env());
    s.set_policy(SearchPolicy {
        quiescence_kind_tag: Some(MillActionKind::Remove as i16),
        ..Default::default()
    });
    s
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
    move_time_secs: u32,
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
            move_time_secs: 1,
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

pub(crate) fn run_uci_loop() {
    let mut options = MillVariantOptions::default();
    let mut rules = MillRules::new(options.clone());
    let mut state = rules.initial_state(&[]);
    let mut state_history: Vec<GameStateSnapshot> = Vec::new();
    let mut threads: usize = 1;
    let mut qsearch_max_depth: i32 = 0;
    let mut engine_cfg = EngineConfig::default();
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
                    rules = MillRules::new(options.clone());
                    state = rules.initial_state(&[]);
                    state_history.clear();
                    sync_perfect_db(&mut engine_cfg, &options);
                }
                SetoptionResult::ClearHash => {
                    // Mirror master src/ucioption.cpp:357 Clear Hash button.
                    // The CLI creates a fresh searcher per `go`, so there is
                    // no live TT handle outside an active search.  Treat the
                    // button as an acknowledged hard-clear request; the next
                    // search starts from a fresh table.
                }
                SetoptionResult::SearchConfig => {
                    // A search/engine parameter changed; the perfect-database
                    // toggle and path live here, so reconcile the global handle.
                    sync_perfect_db(&mut engine_cfg, &options);
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
                engine_cfg.hash_mb,
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
}

fn spawn_search(
    options: MillVariantOptions,
    position: ParsedPosition,
    go: GoOptions,
    threads: usize,
    qsearch_max_depth: i32,
    hash_mb: u32,
    cfg: EngineConfig,
) -> ActiveSearch {
    let state = position.state;
    let root_repetition_history =
        MillRules::repetition_history_from_snapshots(&state, &position.history);
    let search_options = SearchOptions {
        depth_extension: cfg.depth_extension,
        node_limit: go.node_limit,
        time_limit_ms: go.movetime_ms,
        allow_null_move: false,
        // Master shuffles the global movePriorityList before generation.
        // Mill's generate_legal_ctx already mirrors that list, so do not
        // additionally shuffle the root action list here.
        shuffle_root: false,
        // Empirical A/B regression (selfplay depth 5 / 6 / 7 x 24
        // openings, three runs each) shows TT prefetch is neutral to
        // slightly negative for Mill: 0.1-1.7% slower with prefetch
        // ON.  Reasons: the 16 Mi-cluster TT (~256 MiB) far exceeds
        // typical L3 (~16-64 MiB) so most probes miss anyway, while
        // the prefetch instruction + key_after computation add ~5 ns
        // per move that the CPU hardware prefetcher and TT signature
        // re-validation cannot recover.  The infrastructure remains
        // (see SearchOptions::enable_prefetch + Workbench::key_after);
        // games whose TT fits in cache or whose key_after is cheaper
        // than Mill's may still benefit.  See
        // /opt/cursor/artifacts/PREFETCH_EVALUATION_REPORT.md.
        enable_prefetch: false,
        // Master executeSearch uses full windows for every IDS pass.
        enable_aspiration_window: false,
        // Master MovePicker has no killer / history tables.
        enable_killers: false,
        enable_history: false,
        move_order_context: move_order_context(&cfg),
    };
    let depth = effective_search_depth(&options, &state, go.depth, &cfg);
    let root_side_to_move = state.side_to_move;
    let (tx, rx) = mpsc::channel();
    let abort = Arc::new(AtomicBool::new(false));
    let abort_handle = SearchAbortHandle::from_arc(Arc::clone(&abort));

    // NOTE: master C++ keeps `Threads` for the engine commander pool only.
    // Mill search itself stays single-threaded. We mirror that default here;
    // set `UseLazySmp = true` (or TGF_USE_LAZY_SMP=1) to opt into Rust's
    // lazy-SMP variant for higher NPS.
    let use_lazy_smp = cfg.use_lazy_smp && threads > 1;

    let handle = if !use_lazy_smp {
        let abort_for_worker = Arc::clone(&abort);
        thread::spawn(move || {
            let mut searcher = mill_searcher();
            // P2-L plan-C: resize TT when Hash setoption specifies a size.
            if hash_mb > 0 {
                searcher.resize_tt_by_mb(hash_mb);
            }
            searcher.set_abort_flag(abort_for_worker);
            searcher.set_options(search_options);
            searcher.set_qsearch_max_depth(qsearch_max_depth);
            let result = run_configured_search(
                options,
                state,
                root_repetition_history,
                depth,
                &cfg,
                &mut searcher,
            );
            let spawn = SpawnResult {
                depth,
                result,
                root_side_to_move,
            };
            println!("{}", format_spawn_result(&spawn));
            let _ = tx.send(spawn);
        })
    } else {
        let abort_for_workers = Arc::clone(&abort);
        thread::spawn(move || {
            let workers: Vec<LazySmpWorker> = (0..threads)
                .map(|i| LazySmpWorker {
                    extra_depth: (i % 2) as i32,
                })
                .collect();
            let shared_tt = SharedTt::with_capacity_mb(hash_mb, tt_cluster_bits_from_env());
            let game = MillGame::new_with_repetition_history(options, root_repetition_history);
            let result = lazy_smp_search::<MillGame>(
                game,
                state,
                depth,
                &workers,
                search_options,
                shared_tt,
                Some(abort_for_workers),
            );
            let spawn = SpawnResult {
                depth,
                result,
                root_side_to_move,
            };
            println!("{}", format_spawn_result(&spawn));
            let _ = tx.send(spawn);
        })
    };

    ActiveSearch {
        handle,
        abort_handle,
        receiver: rx,
    }
}

fn run_configured_search(
    options: MillVariantOptions,
    state: GameStateSnapshot,
    root_repetition_history: Vec<u64>,
    depth: i32,
    cfg: &EngineConfig,
    searcher: &mut Searcher<MillGame>,
) -> SearchResult {
    // Mirror master src/search_engine.cpp:381 executeSearch: route the
    // user-visible Algorithm option into the actual search implementation.
    let game = MillGame::new_with_repetition_history(options.clone(), root_repetition_history);
    let mut wb = game.build_workbench(&state);
    let mut value = 0;
    let mut best_so_far = SearchResult::default_none();
    let run_ids = cfg.move_time_secs > 0 || cfg.ids_enabled;
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
    let mut result = if !searcher.was_aborted() || best_so_far.best_action.is_none() {
        run_algorithm_at_depth(searcher, &mut wb, cfg, depth, value)
    } else {
        best_so_far
    };

    // Perfect-database consultation (P-DB): when enabled and the active rule
    // variant has matching database assets, prefer the database move over the
    // search result.  Emits an `aimovetype` info line mirroring the Flutter
    // shell: `consensus` when search and DB agree, `perfect` when the DB
    // overrides.
    if cfg.use_perfect_database
        && let Some(pd_action) =
            try_perfect_best_action(&options, &state, perfect_move_ordering(cfg))
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
            time_limit_ms: cfg.move_time_secs.checked_mul(1000).map(u64::from),
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

fn update_last_best_value(cfg: &mut EngineConfig, spawn: &SpawnResult) {
    cfg.last_best_value = spawn.result.score;
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
    let uci = action_to_uci(spawn.result.best_action).unwrap_or_else(|| "none".to_owned());
    format!(
        "info depth {} {} nodes {} bestmove {}",
        spawn.depth, score_str, spawn.result.nodes, uci
    )
}

#[cfg(test)]
mod tests;
