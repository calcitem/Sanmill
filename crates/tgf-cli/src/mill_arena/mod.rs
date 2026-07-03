// SPDX-License-Identifier: AGPL-3.0-or-later
// tgf mill arena: full-rules engine-vs-Perfect-DB match harness, used to
// measure the mined error patch's actual effect on the engine's loss rate
// (the KPI the whole mining pipeline exists to move).
//
// Unlike `mill mine` (which crawls the position graph) this plays complete,
// rule-accurate games (N-move rule, threefold repetition, the lot) via the
// same `tgf_mill::MillRules::outcome` used by real play, because the patch's
// value proposition is about *actual games*, not abstract positions.
//
// Usage:
//   tgf mill arena --db PATH [--patch PATH] [options]
//
// Required:
//   --db PATH           Perfect DB root (the opponent plays optimally from
//                       here; also the ground truth for "the game started a
//                       theoretical draw").
//
// Optional:
//   --patch PATH        Apply this patch file's corrections to the
//                       engine's moves. Omit to measure the *unpatched*
//                       engine (compare two `arena` runs, with and without
//                       --patch, for the before/after KPI).
//   --games N            Games per opening slot (default 1; total games =
//                       N * min(24, available openings) * 2 colors).
//   --depth N            Fixed engine search depth (0 = derive
//                       per-position via `recommended_search_depth`,
//                       matching real play; default 0).
//   --skill-level N      default 30.
//   --db-ordering strict|legacy  DB opponent's tie-break policy; `strict`
//                       (default) mirrors the ultra-strong "hardest test"
//                       behavior; `legacy` mirrors the plain WDL branch.
//   --max-plies N        Safety cap on game length (default 400).
//   --out PATH           Optional per-game JSONL log.

use std::io::Write;

use serde::Serialize;

use perfect_db::PerfectMoveOrdering;
use perfect_db::database::{Database, DatabaseOptions, DatabaseVariant, FileDatabaseProvider};
use perfect_db::patch::PatchLookup;
use tgf_core::{
    Action, ActionList, Game, GameRules, GameStateSnapshot, MoveOrderAlgorithm, MoveOrderContext,
    OutcomeKind,
};
use tgf_mill::search_depth::{EngineRuntimeOptions, recommended_search_depth};
use tgf_mill::{MillActionKind, MillGame, MillRules, MillUciCodec, MillVariantOptions};
use tgf_search::{SearchOptions, SearchPolicy, Searcher};

use crate::cli_args::parse_flag;

/// One `--out` JSONL row. `first_uncovered_blunder_fen` (present only on
/// games where `UncoveredBlunder` fired, see `play_one_game`) is the seed
/// list for closed-loop mining: run `mill mine --seed-fen-file` against
/// exactly the positions where this benchmark's own games actually went
/// wrong and the patch did not catch it.
#[derive(Serialize)]
struct GameLogEntry<'a> {
    opening: String,
    engine_is_white: bool,
    result: String,
    plies: u32,
    engine_blunders: u32,
    corrections_applied: u32,
    first_uncovered_blunder_ply: Option<u32>,
    first_uncovered_blunder_fen: Option<&'a str>,
    first_uncovered_blunder_is_mid_removal: Option<bool>,
}

#[derive(Clone, Copy, Debug, Default)]
struct BatchResult {
    games: u32,
    engine_wins: u32,
    engine_draws: u32,
    engine_losses: u32,
    unfinished: u32,
    /// Games where the engine played at least one move that dropped the
    /// database's assessed value for the engine (a "should not have
    /// happened" event on a theoretically-safe path), regardless of the
    /// final result -- catches "got away with it" blunders a short game
    /// wouldn't otherwise surface as a loss.
    games_with_a_blunder: u32,
    total_engine_blunders: u32,
    total_corrections_applied: u32,
}

impl BatchResult {
    fn print(&self, label: &str) {
        let pct = |n: u32| {
            if self.games == 0 {
                0.0
            } else {
                f64::from(n) * 100.0 / f64::from(self.games)
            }
        };
        eprintln!(
            "[mill-arena] {label}: games={} wins={} ({:.1}%) draws={} ({:.1}%) losses={} ({:.1}%) \
             unfinished={} games_with_blunder={} ({:.1}%) total_blunders={} corrections_applied={}",
            self.games,
            self.engine_wins,
            pct(self.engine_wins),
            self.engine_draws,
            pct(self.engine_draws),
            self.engine_losses,
            pct(self.engine_losses),
            self.unfinished,
            self.games_with_a_blunder,
            pct(self.games_with_a_blunder),
            self.total_engine_blunders,
            self.total_corrections_applied,
        );
    }
}

pub(crate) fn run_mill_arena(args: &[String]) {
    let db_path: String = parse_flag(args, "--db", String::new());
    if db_path.is_empty() {
        eprintln!("[mill-arena] ERROR: --db PATH is required");
        std::process::exit(1);
    }
    let patch_path: String = parse_flag(args, "--patch", String::new());
    let games_per_opening: u32 = parse_flag(args, "--games", 1u32);
    let depth_override: i32 = parse_flag(args, "--depth", 0i32);
    let skill_level: u8 = parse_flag(args, "--skill-level", 30u8);
    let db_ordering_name: String = parse_flag(args, "--db-ordering", "strict".to_string());
    let db_ordering = match db_ordering_name.as_str() {
        "legacy" => PerfectMoveOrdering::LegacyWdl,
        _ => PerfectMoveOrdering::StrictSteps,
    };
    let max_plies: u32 = parse_flag(args, "--max-plies", 400u32);
    let out_path: String = parse_flag(args, "--out", String::new());

    let options = MillVariantOptions::default();
    let variant = DatabaseVariant::match_mill_options(&options)
        .expect("default MillVariantOptions must match the standard Perfect DB variant");
    let rules = MillRules::new(options.clone());
    let game = MillGame::new(options.clone());

    let mut db = Database::open_variant_with_options(
        FileDatabaseProvider::new(std::path::PathBuf::from(&db_path)),
        variant,
        DatabaseOptions::with_sector_cache_capacity(64),
    )
    .unwrap_or_else(|e| panic!("[mill-arena] failed to open DB at {db_path}: {e}"));

    let mut patch = if patch_path.is_empty() {
        None
    } else {
        let bytes = std::fs::read(&patch_path)
            .unwrap_or_else(|e| panic!("[mill-arena] cannot read patch {patch_path}: {e}"));
        Some(
            PatchLookup::open(&bytes)
                .unwrap_or_else(|e| panic!("[mill-arena] cannot parse patch {patch_path}: {e}")),
        )
    };

    eprintln!(
        "[mill-arena] db={db_path} patch={} games_per_opening={games_per_opening} \
         depth_override={depth_override} skill_level={skill_level} db_ordering={db_ordering_name} \
         max_plies={max_plies}",
        if patch_path.is_empty() {
            "<none>"
        } else {
            &patch_path
        }
    );

    let mut out_writer = (!out_path.is_empty()).then(|| {
        std::io::BufWriter::new(
            std::fs::File::create(&out_path)
                .unwrap_or_else(|e| panic!("[mill-arena] cannot create {out_path}: {e}")),
        )
    });

    let initial = rules.initial_state(&[]);
    let mut openings = ActionList::<256>::new();
    rules.legal_actions(&initial, &mut openings);
    let opening_list: Vec<Action> = openings.as_slice().to_vec();

    let mut batch = BatchResult::default();
    for &opening in &opening_list {
        for engine_is_white in [true, false] {
            for _ in 0..games_per_opening {
                let outcome = play_one_game(
                    &rules,
                    &game,
                    &initial,
                    opening,
                    engine_is_white,
                    &mut db,
                    db_ordering,
                    patch.as_mut(),
                    &options,
                    depth_override,
                    skill_level,
                    max_plies,
                );
                batch.games += 1;
                match outcome.result {
                    GameResult::EngineWin => batch.engine_wins += 1,
                    GameResult::Draw => batch.engine_draws += 1,
                    GameResult::EngineLoss => batch.engine_losses += 1,
                    GameResult::Unfinished => batch.unfinished += 1,
                }
                if outcome.engine_blunders > 0 {
                    batch.games_with_a_blunder += 1;
                }
                batch.total_engine_blunders += outcome.engine_blunders;
                batch.total_corrections_applied += outcome.corrections_applied;

                if let Some(writer) = out_writer.as_mut() {
                    let blunder = outcome.first_uncovered_blunder.as_ref();
                    let log_entry = GameLogEntry {
                        opening: MillUciCodec::encode_action(opening),
                        engine_is_white,
                        result: format!("{:?}", outcome.result),
                        plies: outcome.plies,
                        engine_blunders: outcome.engine_blunders,
                        corrections_applied: outcome.corrections_applied,
                        first_uncovered_blunder_ply: blunder.map(|b| b.ply),
                        first_uncovered_blunder_fen: blunder.map(|b| b.fen.as_str()),
                        first_uncovered_blunder_is_mid_removal: blunder.map(|b| b.is_mid_removal),
                    };
                    serde_json::to_writer(&mut *writer, &log_entry).ok();
                    writeln!(writer).ok();
                }
            }
        }
    }
    if let Some(writer) = out_writer.as_mut() {
        writer.flush().ok();
    }

    batch.print(if patch.is_some() {
        "patched"
    } else {
        "unpatched"
    });
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum GameResult {
    EngineWin,
    Draw,
    EngineLoss,
    Unfinished,
}

/// The first engine-to-move ply in a game where the ground-truth database
/// says the chosen action drops value *and* the patch (if any) did not
/// override it -- i.e. the root cause of whatever the game's final result
/// turns out to be, for feeding a closed-loop mining pass (see
/// `--out`'s `first_uncovered_blunder_fen`).
struct UncoveredBlunder {
    ply: u32,
    fen: String,
    is_mid_removal: bool,
}

struct GameOutcome {
    result: GameResult,
    plies: u32,
    engine_blunders: u32,
    corrections_applied: u32,
    first_uncovered_blunder: Option<UncoveredBlunder>,
}

#[allow(clippy::too_many_arguments)]
fn play_one_game<P: perfect_db::database::DatabaseProvider>(
    rules: &MillRules,
    game: &MillGame,
    initial: &GameStateSnapshot,
    opening: Action,
    engine_is_white: bool,
    db: &mut Database<P>,
    db_ordering: PerfectMoveOrdering,
    mut patch: Option<&mut PatchLookup>,
    options: &MillVariantOptions,
    depth_override: i32,
    skill_level: u8,
    max_plies: u32,
) -> GameOutcome {
    let mut snapshot = *initial;
    let mut plies = 0_u32;
    let mut engine_blunders = 0_u32;
    let mut corrections_applied = 0_u32;
    let mut first_uncovered_blunder: Option<UncoveredBlunder> = None;
    let mut searcher = Searcher::<MillGame>::new();
    searcher.set_policy(SearchPolicy {
        quiescence_kind_tag: Some(MillActionKind::Remove as i16),
        ..Default::default()
    });

    // Apply the forced opening move first (matches `selfplay.rs`'s
    // systematic per-opening coverage), attributed to whichever side moves
    // first (White always opens in Mill).
    snapshot = rules.apply(&snapshot, opening);
    plies += 1;

    while plies < max_plies {
        if std::env::var("MILL_ARENA_DEBUG").is_ok() {
            eprintln!(
                "[arena-debug] ply={plies} side_to_move={}",
                snapshot.side_to_move
            );
        }
        let outcome = rules.outcome(&snapshot);
        match outcome.kind {
            OutcomeKind::Ongoing => {}
            OutcomeKind::Win(side) => {
                let engine_side = i8::from(!engine_is_white);
                let result = if side == engine_side {
                    GameResult::EngineWin
                } else {
                    GameResult::EngineLoss
                };
                return GameOutcome {
                    result,
                    plies,
                    engine_blunders,
                    corrections_applied,
                    first_uncovered_blunder,
                };
            }
            OutcomeKind::Draw => {
                return GameOutcome {
                    result: GameResult::Draw,
                    plies,
                    engine_blunders,
                    corrections_applied,
                    first_uncovered_blunder,
                };
            }
            OutcomeKind::Abandoned | OutcomeKind::WinTeam(_) => {
                return GameOutcome {
                    result: GameResult::Unfinished,
                    plies,
                    engine_blunders,
                    corrections_applied,
                    first_uncovered_blunder,
                };
            }
        }

        let side_to_move = snapshot.side_to_move;
        let engine_to_move = (side_to_move == 0) == engine_is_white;

        let chosen_action = if engine_to_move {
            let state = MillRules::decode_snapshot(snapshot);
            let depth = if depth_override > 0 {
                depth_override
            } else {
                let runtime = EngineRuntimeOptions {
                    skill_level,
                    draw_on_human_experience: true,
                    developer_mode: true,
                };
                recommended_search_depth(&state, options, &runtime).max(1)
            };
            searcher.clear_tt();
            searcher.set_random_seed(0xA1B2_C3D4_5566_7788);
            searcher.set_options(SearchOptions {
                depth_extension: true,
                node_limit: None,
                time_limit_ms: None,
                allow_null_move: false,
                shuffle_root: false,
                enable_prefetch: false,
                prefetch_all: false,
                enable_aspiration_window: false,
                move_order_context: MoveOrderContext {
                    algorithm: MoveOrderAlgorithm::Mtdf,
                    skill_level,
                    shuffling: false,
                    hash_move: None,
                    shuffle_seed: 0,
                },
            });
            let mut workbench = game.build_workbench(&snapshot);
            let result = searcher.search_mtdf(&mut workbench, depth);
            let mut action = result.best_action;
            if action.is_none() {
                let mut legal = ActionList::<256>::new();
                rules.legal_actions(&snapshot, &mut legal);
                action = *legal
                    .as_slice()
                    .first()
                    .expect("engine to move must have a legal move here");
            }

            // Database ground truth for the blunder counter, independent of
            // whether a patch is applied: did the engine's own choice drop
            // the position's true value?
            let is_blunder =
                engine_action_drops_value(rules, db, options, &snapshot, action) == Some(true);
            if is_blunder {
                engine_blunders += 1;
            }

            let mut patch_fixed_it = false;
            if let Some(patch) = patch.as_deref_mut()
                && let Some(corrected) = patch.correct_action(rules, options, &snapshot, action)
            {
                action = corrected;
                corrections_applied += 1;
                patch_fixed_it = true;
            }

            // Root cause of the game's eventual result, for closed-loop
            // mining: the first point where the ground truth says the
            // engine chose wrong and nothing put it back on track. Only
            // the first one is kept -- once the game has left the
            // database-optimal line, later "blunders" are just it digging
            // in further, not independent gaps to mine.
            if is_blunder && !patch_fixed_it && first_uncovered_blunder.is_none() {
                if std::env::var("MILL_ARENA_DEBUG").is_ok() {
                    let has_entry = patch
                        .as_deref_mut()
                        .and_then(|p| p.trap_score_for_state(&state, options))
                        .is_some();
                    eprintln!(
                        "[arena-debug] UNCOVERED ply={plies} chose={} patch_entry_exists={has_entry} fen={:?}",
                        MillUciCodec::encode_action(action),
                        rules.export_fen(&state)
                    );
                }
                first_uncovered_blunder = Some(UncoveredBlunder {
                    ply: plies,
                    fen: rules.export_fen(&state),
                    is_mid_removal: state.pending_removals().iter().any(|&r| r > 0),
                });
            }
            action
        } else {
            db_action(rules, db, options, &snapshot, db_ordering)
        };

        snapshot = rules.apply(&snapshot, chosen_action);
        plies += 1;
    }

    GameOutcome {
        result: GameResult::Unfinished,
        plies,
        engine_blunders,
        corrections_applied,
        first_uncovered_blunder,
    }
}

/// `true` when `action` leaves the mover strictly worse off than the best
/// legal reply, per the live database. `None` when the database does not
/// cover this position (outside the mined/bundled range).
fn engine_action_drops_value<P: perfect_db::database::DatabaseProvider>(
    rules: &MillRules,
    db: &mut Database<P>,
    options: &MillVariantOptions,
    snap: &GameStateSnapshot,
    action: Action,
) -> Option<bool> {
    let all = perfect_db::all_move_outcomes_with_ordering(
        db,
        rules,
        snap,
        options,
        PerfectMoveOrdering::StrictSteps,
    )
    .ok()??;
    let best = all.iter().map(|choice| choice.outcome.wdl()).max()?;
    let chosen_token = MillUciCodec::encode_action(action);
    let chosen = all.iter().find(|choice| choice.token == chosen_token)?;
    Some(chosen.outcome.wdl() < best)
}

fn db_action<P: perfect_db::database::DatabaseProvider>(
    rules: &MillRules,
    db: &mut Database<P>,
    options: &MillVariantOptions,
    snap: &GameStateSnapshot,
    ordering: PerfectMoveOrdering,
) -> Action {
    let mut legal = ActionList::<256>::new();
    rules.legal_actions(snap, &mut legal);
    if let Ok(Some(choice)) =
        perfect_db::best_move_choice_with_ordering(db, rules, snap, options, ordering)
        && let Some(&action) = legal
            .as_slice()
            .iter()
            .find(|&&a| MillUciCodec::encode_action(a) == choice.token)
    {
        return action;
    }
    *legal
        .as_slice()
        .first()
        .expect("db_action requires at least one legal move")
}
