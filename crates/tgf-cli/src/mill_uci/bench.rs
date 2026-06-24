// SPDX-License-Identifier: GPL-3.0-or-later
// `tgf bench` subcommand: emits a perf_baseline-compatible TOML block
// covering perft, search NPS, TT hit-rate, lazy-SMP scale and an MCTS
// self-play snapshot.

use std::time::{Duration, Instant};

use tgf_core::{Game, GameRules, MoveOrderAlgorithm, MoveOrderContext};
use tgf_mill::{MillActionKind, MillGame, MillRules};
use tgf_search::{
    LazySmpWorker, MctsOptions, MctsSearcher, SearchOptions, SearchPolicy, SharedTt,
    lazy_smp_search, perft,
};

use super::{
    mill_searcher, prefetch_mode_from_env, tt_cluster_bits_from_env, tt_move_enabled_from_env,
};

fn mill_benchmark_search_options() -> SearchOptions {
    let (enable_prefetch, prefetch_all) = prefetch_mode_from_env();
    SearchOptions {
        enable_prefetch,
        prefetch_all,
        ..SearchOptions::default()
    }
}

pub fn print_benchmark_toml() {
    let git_commit = option_env!("GIT_COMMIT").unwrap_or("");
    let platform = format!("{}-{}", std::env::consts::OS, std::env::consts::ARCH);

    let rules = MillRules::default();
    let game = MillGame::default();
    let snap = rules.initial_state(&[]);

    let mut wb = game.build_workbench(&snap);
    let start_d1 = perft::<MillGame>(&mut wb, 1);
    let mut wb = game.build_workbench(&snap);
    let start_d2 = perft::<MillGame>(&mut wb, 2);
    let mid_snap = rules.no_mill_moving_phase_snapshot();
    let mut wb = game.build_workbench(&mid_snap);
    let mid_d3 = perft::<MillGame>(&mut wb, 3);

    let search_options = mill_benchmark_search_options();

    let mut searcher = mill_searcher();
    searcher.set_options(search_options);
    let mut warmup_wb = game.build_workbench(&snap);
    let _ = searcher.search(&mut warmup_wb, 4);
    let mut wb = game.build_workbench(&snap);
    let start = Instant::now();
    let result = searcher.search(&mut wb, 4);
    let elapsed = start.elapsed().max(Duration::from_micros(1));
    let depth_ms = elapsed.as_millis() as u64;
    let nps = (result.nodes as f64 / elapsed.as_secs_f64()).round() as u64;
    let tt_hit_rate_pct = searcher.tt_hit_rate_pct();
    let tt_age_bumps = searcher.tt_age_bumps();
    let tt_current_age = searcher.tt_current_age();
    let tt_stats = searcher.tt_stats();

    let cold_start_begin = Instant::now();
    let mut wb = game.build_workbench(&snap);
    let mut searcher = mill_searcher();
    searcher.set_options(search_options);
    let _ = searcher.search(&mut wb, 1);
    let first_move_ms = cold_start_begin.elapsed().as_millis() as u64;

    let smp_workers = vec![
        LazySmpWorker { extra_depth: 0 },
        LazySmpWorker { extra_depth: 1 },
    ];
    let smp_shared_tt =
        SharedTt::new_with_tt_move(tt_cluster_bits_from_env(), tt_move_enabled_from_env());
    let smp_start = Instant::now();
    let smp_result = lazy_smp_search::<MillGame>(
        game.clone(),
        snap,
        4,
        &smp_workers,
        search_options,
        smp_shared_tt,
        None,
    );
    let smp_elapsed = smp_start.elapsed().max(Duration::from_micros(1));
    let smp_ms = smp_elapsed.as_millis() as u64;
    let smp_nps = (smp_result.nodes as f64 / smp_elapsed.as_secs_f64()).round() as u64;

    println!("[meta]");
    println!("locked_at   = \"\"");
    println!("git_commit  = \"{}\"", git_commit);
    println!("platform    = \"{}\"", platform);
    println!("search_depth = 4");
    println!("search_warmup_runs = 1");
    println!(
        "tt_cluster_bits = {}  # set TGF_TT_CLUSTER_BITS to override",
        tt_cluster_bits_from_env()
    );
    println!("enable_prefetch = {}", search_options.enable_prefetch);
    println!("prefetch_all = {}", search_options.prefetch_all);
    println!("enable_tt_move = {}", searcher.tt_move_enabled());
    println!("build_flags = \"cargo bench scaffold\"");
    println!("tt_age_bumps   = {}", tt_age_bumps);
    println!("tt_current_age = {}", tt_current_age);
    println!();
    println!("[baseline]");
    println!("nps = {}", nps);
    println!("depth10_ms = {}", depth_ms);
    println!();
    println!("[baseline.perft]");
    println!("start_d1 = {}", start_d1);
    println!("start_d2 = {}", start_d2);
    println!("mid_d3 = {}", mid_d3);
    println!();
    println!("[baseline.tt]");
    println!("hit_rate_pct = {:.3}", tt_hit_rate_pct);
    println!("age_bumps = {}", tt_age_bumps);
    println!("current_age = {}", tt_current_age);
    println!("slots = {}", tt_stats.slots);
    println!("occupied = {}", tt_stats.occupied);
    println!("current_age_occupied = {}", tt_stats.current_age_occupied);
    println!("stale = {}", tt_stats.stale);
    println!("load_pct = {:.3}", tt_stats.load_pct());
    println!(
        "current_age_load_pct = {:.3}",
        tt_stats.current_age_load_pct()
    );
    println!(
        "stale_pct_of_occupied = {:.3}",
        tt_stats.stale_pct_of_occupied()
    );
    println!("exact = {}", tt_stats.exact);
    println!("lower = {}", tt_stats.lower);
    println!("upper = {}", tt_stats.upper);
    println!("average_depth = {:.3}", tt_stats.average_depth());
    println!("max_depth = {}", tt_stats.max_depth);
    println!();
    println!("[baseline.startup]");
    println!("first_move_ms = {}", first_move_ms);
    println!();
    println!("[baseline.smp]");
    println!("workers = {}", smp_workers.len());
    println!("base_depth = 4");
    println!("nps = {}", smp_nps);
    println!("depth_ms = {}", smp_ms);

    // MCTS baseline: 50 self-play games, fixed seed, compare random rollout
    // vs α-β-assisted simulation at depth 1.
    const MCTS_GAMES: u32 = 50;
    const MCTS_SEED: u64 = 0xBEEF_CAFE_0123_4567;
    let mcts_ab0_wins = run_mcts_self_play(MCTS_GAMES, MCTS_SEED, 0);
    let mcts_ab1_wins = run_mcts_self_play(MCTS_GAMES, MCTS_SEED, 1);
    println!();
    println!("[baseline.mcts]");
    println!("games = {}", MCTS_GAMES);
    println!("iterations_per_move = 32");
    println!("ab_assist_depth_0_wins = {}", mcts_ab0_wins);
    println!("ab_assist_depth_1_wins = {}", mcts_ab1_wins);
}

/// Play `games` self-play games using MCTS where both sides use
/// `ab_assist_depth`.  Returns the number of wins for side 0 (White).
/// Both sides share the same options; the AB-assist advantage is symmetric
/// so the win-rate measures absolute quality vs random rollout (ab_depth=0).
fn run_mcts_self_play(games: u32, seed: u64, ab_assist_depth: i32) -> u32 {
    let rules = MillRules::default();
    let game = MillGame::default();
    let policy = SearchPolicy {
        quiescence_kind_tag: Some(MillActionKind::Remove as i16),
        ..Default::default()
    };
    let mut wins = 0u32;
    for g in 0..games {
        let mut snap = rules.initial_state(&[]);
        let mut mcts = MctsSearcher::<MillGame>::new();
        mcts.set_random_seed(seed.wrapping_add(u64::from(g)));
        mcts.set_policy(policy);
        let options = MctsOptions {
            iterations: 32,
            playout_depth: 4,
            time_limit_ms: None,
            exploration: 0.5,
            ab_assist_depth,
            // Bench is sequential; force single-threaded MCTS so the
            // perf-baseline TOML stays deterministic.
            num_threads: Some(1),
            move_order_context: MoveOrderContext {
                algorithm: MoveOrderAlgorithm::Mcts,
                skill_level: 1,
                shuffling: false,
                hash_move: None,
                shuffle_seed: 0,
            },
        };
        for _ in 0..120 {
            use tgf_core::GameRules;
            let outcome = rules.outcome(&snap);
            if matches!(
                outcome.kind,
                tgf_core::OutcomeKind::Win(_) | tgf_core::OutcomeKind::Draw
            ) {
                if let tgf_core::OutcomeKind::Win(w) = outcome.kind
                    && w == 0
                {
                    wins += 1;
                }
                break;
            }
            let mut wb = game.build_workbench(&snap);
            let result = mcts.search_with_options(&mut wb, options);
            if result.best_action.is_none() {
                break;
            }
            snap = rules.apply(&snap, result.best_action);
        }
    }
    wins
}
