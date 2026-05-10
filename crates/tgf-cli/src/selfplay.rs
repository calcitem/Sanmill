// SPDX-License-Identifier: GPL-3.0-or-later
// Self-play harness used to capture deterministic baselines for
// search-behaviour regressions.
//
// The driver intentionally wires the searcher with all randomness
// disabled so a given (game-mode, depth, opening-move) tuple yields
// the same game every run.  Outputs a perf-baseline-flavoured TOML
// file describing per-game move sequences plus aggregate
// statistics; downstream `selfplay_baseline_*.toml` files live next
// to this binary's bench output.
//
// Determinism is achieved by:
//   * `SearchOptions::shuffle_root = false`
//   * `MoveOrderContext::shuffling = false`
//   * `MoveOrderContext::shuffle_seed = 0`
//   * Searcher PRNG seed pinned via `set_random_seed(0xA1B2_C3D4_5566_7788)`
//   * MCTS / aspiration / lazy / null-move not used (PVS at fixed depth)
//
// Each "round" launches one game per legal first-place opening (24
// games per fully-empty Mill board) and prints a TOML block.

use std::time::Instant;

use tgf_core::{Action, ActionList, Game, GameRules, GameStateSnapshot, MoveOrderContext};
use tgf_mill::{MillActionKind, MillGame, MillRules};
use tgf_search::{MctsOptions, MctsSearcher, SearchOptions, SearchPolicy, Searcher};

/// Fixed random seed for the searcher's xorshift PRNG.  Selected
/// arbitrarily; only required to be non-zero so xorshift does not
/// collapse to the all-zero attractor.
const SELFPLAY_SEED: u64 = 0xA1B2_C3D4_5566_7788;

/// Maximum plies per game.  Mill games rarely exceed ~200 plies
/// without triggering the N-move-rule draw or running out of pieces.
/// The cap prevents pathological non-terminating games when the
/// searcher returns no progress.
const MAX_PLIES: u32 = 400;

/// `tgf selfplay` entry point.  Args (after the selected command):
///   --depth N          fixed search depth (default 5); for MCTS this
///                      is multiplied by 200 to derive iteration count
///   --max-games N      cap the number of games (default 24)
///   --algorithm pvs|alphabeta|mtdf|mcts|random  (default pvs)
pub(crate) fn run_selfplay(command_args: &[String]) {
    let mut depth: i32 = 5;
    let mut max_games: usize = 24;
    let mut algorithm: SelfplayAlgorithm = SelfplayAlgorithm::Pvs;
    // Default off after empirical A/B testing showed prefetch is
    // neutral to slightly negative for Mill at depths 5-7 (the TT
    // does not fit in L3 and the prefetch overhead exceeds the
    // savings).  Pass --prefetch true to A/B-test changes.
    let mut enable_prefetch: bool = false;

    let mut args = command_args.iter();
    while let Some(token) = args.next() {
        match token.as_str() {
            "--depth" => {
                if let Some(value) = args.next() {
                    if let Ok(parsed) = value.parse::<i32>() {
                        depth = parsed.max(1);
                    }
                }
            }
            "--max-games" => {
                if let Some(value) = args.next() {
                    if let Ok(parsed) = value.parse::<usize>() {
                        max_games = parsed.max(1);
                    }
                }
            }
            "--algorithm" => {
                if let Some(value) = args.next() {
                    algorithm = match value.as_str() {
                        "alphabeta" | "alpha-beta" | "ab" => SelfplayAlgorithm::AlphaBeta,
                        "mtdf" | "mtd-f" | "mtd_f" => SelfplayAlgorithm::Mtdf,
                        "mcts" => SelfplayAlgorithm::Mcts,
                        "random" | "rand" => SelfplayAlgorithm::Random,
                        _ => SelfplayAlgorithm::Pvs,
                    };
                }
            }
            "--prefetch" => {
                if let Some(value) = args.next() {
                    enable_prefetch = matches!(value.as_str(), "1" | "true" | "on" | "yes");
                }
            }
            other => {
                eprintln!("# warning: ignoring unknown selfplay arg `{other}`");
            }
        }
    }

    let rules = MillRules::default();
    let game = MillGame::default();
    let initial = rules.initial_state(&[]);

    // Enumerate first-ply openings.
    let mut openings = ActionList::<256>::new();
    rules.legal_actions(&initial, &mut openings);

    let total = openings.len().min(max_games);
    let started_at = Instant::now();

    println!("# tgf selfplay (deterministic, no randomness)");
    println!("[meta]");
    println!("depth = {depth}");
    println!("openings = {total}");
    println!("algorithm = \"{}\"", algorithm.label());
    println!("seed = \"{SELFPLAY_SEED:#018x}\"");
    println!("enable_prefetch = {enable_prefetch}");

    let mut total_plies: u64 = 0;
    let mut total_nodes: u64 = 0;
    let mut white_wins: u32 = 0;
    let mut black_wins: u32 = 0;
    let mut draws: u32 = 0;
    let mut unfinished: u32 = 0;

    for (i, &opening) in openings.iter().take(total).enumerate() {
        let game_started = Instant::now();
        let game_result = play_one_game(
            &rules,
            &game,
            &initial,
            opening,
            depth,
            algorithm,
            enable_prefetch,
        );
        let elapsed_ms = game_started.elapsed().as_millis() as u64;

        total_plies += game_result.plies as u64;
        total_nodes += game_result.nodes;
        match game_result.outcome {
            GameOutcome::WhiteWin => white_wins += 1,
            GameOutcome::BlackWin => black_wins += 1,
            GameOutcome::Draw => draws += 1,
            GameOutcome::Unfinished => unfinished += 1,
        }

        println!();
        println!("[[games]]");
        println!("index = {i}");
        println!("opening = \"{}\"", action_label(opening));
        println!("plies = {}", game_result.plies);
        println!("nodes = {}", game_result.nodes);
        println!("elapsed_ms = {}", elapsed_ms);
        println!("outcome = \"{}\"", game_result.outcome.label());
        println!("reason = \"{}\"", game_result.reason);
        println!("moves = [");
        for chunk in game_result.move_log.chunks(8) {
            let line: Vec<String> = chunk.iter().map(|s| format!("\"{}\"", s)).collect();
            println!("    {},", line.join(", "));
        }
        println!("]");
    }

    let total_elapsed_ms = started_at.elapsed().as_millis() as u64;
    println!();
    println!("[summary]");
    println!("games = {total}");
    println!("white_wins = {white_wins}");
    println!("black_wins = {black_wins}");
    println!("draws = {draws}");
    println!("unfinished = {unfinished}");
    println!("total_plies = {total_plies}");
    println!("total_nodes = {total_nodes}");
    println!("total_elapsed_ms = {total_elapsed_ms}");
}

#[derive(Clone, Copy, Debug)]
enum SelfplayAlgorithm {
    AlphaBeta,
    Pvs,
    Mtdf,
    Mcts,
    Random,
}

impl SelfplayAlgorithm {
    fn label(self) -> &'static str {
        match self {
            SelfplayAlgorithm::AlphaBeta => "alphabeta",
            SelfplayAlgorithm::Pvs => "pvs",
            SelfplayAlgorithm::Mtdf => "mtdf",
            SelfplayAlgorithm::Mcts => "mcts",
            SelfplayAlgorithm::Random => "random",
        }
    }
}

#[derive(Clone, Copy, Debug)]
enum GameOutcome {
    WhiteWin,
    BlackWin,
    Draw,
    Unfinished,
}

impl GameOutcome {
    fn label(self) -> &'static str {
        match self {
            GameOutcome::WhiteWin => "white_win",
            GameOutcome::BlackWin => "black_win",
            GameOutcome::Draw => "draw",
            GameOutcome::Unfinished => "unfinished",
        }
    }
}

struct PlayResult {
    plies: u32,
    nodes: u64,
    outcome: GameOutcome,
    reason: String,
    move_log: Vec<String>,
}

fn play_one_game(
    rules: &MillRules,
    game: &MillGame,
    initial: &GameStateSnapshot,
    opening: Action,
    depth: i32,
    algorithm: SelfplayAlgorithm,
    enable_prefetch: bool,
) -> PlayResult {
    use tgf_core::OutcomeKind;

    let mut snapshot = rules.apply(initial, opening);
    let mut move_log: Vec<String> = vec![action_label(opening)];
    let mut total_nodes: u64 = 0;
    let mut plies: u32 = 1;

    let move_order_context = MoveOrderContext {
        algorithm: match algorithm {
            SelfplayAlgorithm::AlphaBeta => tgf_core::MoveOrderAlgorithm::AlphaBeta,
            SelfplayAlgorithm::Pvs => tgf_core::MoveOrderAlgorithm::Pvs,
            SelfplayAlgorithm::Mtdf => tgf_core::MoveOrderAlgorithm::Mtdf,
            SelfplayAlgorithm::Mcts => tgf_core::MoveOrderAlgorithm::Mcts,
            SelfplayAlgorithm::Random => tgf_core::MoveOrderAlgorithm::Random,
        },
        skill_level: 30,
        shuffling: false,
        hash_move: None,
        shuffle_seed: 0,
    };
    let search_options = SearchOptions {
        depth_extension: true,
        node_limit: None,
        time_limit_ms: None,
        allow_null_move: false,
        shuffle_root: false,
        // Driven by the --prefetch CLI flag for empirical A/B testing.
        enable_prefetch,
        enable_aspiration_window: false,
        enable_killers: false,
        enable_history: false,
        move_order_context,
    };

    // MCTS iteration count derived from depth: depth * 200 gives a
    // rough equivalence to the FRB skill_level * 2048 formula at
    // skill_level ~30 while keeping selfplay runtimes manageable.
    let mcts_iterations = (depth as u32).saturating_mul(200).max(1);

    while plies < MAX_PLIES {
        // Outcome check before searching.
        let outcome = rules.outcome(&snapshot);
        match outcome.kind {
            OutcomeKind::Ongoing => {}
            OutcomeKind::Win(0) => {
                return PlayResult {
                    plies,
                    nodes: total_nodes,
                    outcome: GameOutcome::WhiteWin,
                    reason: outcome.reason,
                    move_log,
                };
            }
            OutcomeKind::Win(1) => {
                return PlayResult {
                    plies,
                    nodes: total_nodes,
                    outcome: GameOutcome::BlackWin,
                    reason: outcome.reason,
                    move_log,
                };
            }
            OutcomeKind::Win(_) | OutcomeKind::WinTeam(_) => {
                return PlayResult {
                    plies,
                    nodes: total_nodes,
                    outcome: GameOutcome::Unfinished,
                    reason: outcome.reason,
                    move_log,
                };
            }
            OutcomeKind::Draw => {
                return PlayResult {
                    plies,
                    nodes: total_nodes,
                    outcome: GameOutcome::Draw,
                    reason: outcome.reason,
                    move_log,
                };
            }
            OutcomeKind::Abandoned => {
                return PlayResult {
                    plies,
                    nodes: total_nodes,
                    outcome: GameOutcome::Unfinished,
                    reason: outcome.reason,
                    move_log,
                };
            }
        }

        let mut workbench = game.build_workbench(&snapshot);

        // MCTS uses a separate searcher type; all other algorithms use
        // the shared Searcher<MillGame> with fixed options.
        let result = if let SelfplayAlgorithm::Mcts = algorithm {
            let mut mcts = MctsSearcher::<MillGame>::new();
            let mcts_result = mcts.search_with_options(
                &mut workbench,
                MctsOptions {
                    iterations: mcts_iterations,
                    playout_depth: 6,
                    time_limit_ms: None,
                    exploration: 0.5,
                    ab_assist_depth: 6,
                    num_threads: Some(1),
                    move_order_context,
                },
            );
            tgf_search::SearchResult {
                best_action: mcts_result.best_action,
                score: mcts_result.score,
                // MCTS counts tree node visits rather than alpha-beta
                // evaluations; use visits as the node-count analogue so
                // the summary statistics remain meaningful.
                nodes: mcts_result.visits as u64,
                draw_reason: None,
            }
        } else {
            let mut searcher = Searcher::<MillGame>::new();
            searcher.set_options(search_options);
            searcher.set_policy(SearchPolicy {
                quiescence_kind_tag: Some(MillActionKind::Remove as i16),
                ..Default::default()
            });
            searcher.set_random_seed(SELFPLAY_SEED);
            match algorithm {
                SelfplayAlgorithm::AlphaBeta => searcher.search(&mut workbench, depth),
                SelfplayAlgorithm::Pvs => searcher.search_pvs(&mut workbench, depth),
                SelfplayAlgorithm::Mtdf => searcher.search_mtdf(&mut workbench, depth),
                SelfplayAlgorithm::Random => searcher.random_search(&mut workbench),
                SelfplayAlgorithm::Mcts => unreachable!("handled above"),
            }
        };

        total_nodes = total_nodes.saturating_add(result.nodes);

        if result.best_action.is_none() {
            return PlayResult {
                plies,
                nodes: total_nodes,
                outcome: GameOutcome::Unfinished,
                reason: "no_best_action".to_owned(),
                move_log,
            };
        }

        snapshot = rules.apply(&snapshot, result.best_action);
        move_log.push(action_label(result.best_action));
        plies += 1;
    }

    PlayResult {
        plies,
        nodes: total_nodes,
        outcome: GameOutcome::Unfinished,
        reason: "max_plies_reached".to_owned(),
        move_log,
    }
}

fn action_label(action: Action) -> String {
    let s = tgf_mill::MillUciCodec::encode_action(action);
    if s.is_empty() {
        format!(
            "kind{}from{}to{}",
            action.kind_tag, action.from_node, action.to_node
        )
    } else {
        s
    }
}
