// SPDX-License-Identifier: AGPL-3.0-or-later
// puzzle-gen: generate forced-win Mill puzzles from a Perfect (Malom) DB.
//
// Usage:
//   tgf puzzle-gen --db PATH [options]
//   tgf mill puzzle-gen --db PATH [options]
//
// Required:
//   --db PATH            Perfect DB root directory (contains `std.secval`,
//                         `std_*.sec2`, and/or the Lasker/Morabaraba
//                         equivalents). The small subset bundled with the
//                         app at `src/ui/flutter_app/assets/databases` works
//                         for quick smoke tests; a full external copy (e.g.
//                         the "Malom Standard Ultra-strong" release) is
//                         needed for broad coverage.
//
// Sampling:
//   --count N            Target number of puzzles to produce (default 20)
//   --side w|b|random     Side to move at the root (default random)
//   --phase placing|moving|random  Root position phase (default random)
//   --min-pieces N        Lower bound on on-board pieces per side (default 3)
//   --max-pieces N        Upper bound on on-board pieces per side (default 7)
//   --variant std|lask|mora  Rule variant to sample/query (default std)
//
// Difficulty / shape:
//   --depth N             Exact "win in N moves" (overrides min/max depth)
//   --min-depth N          Minimum solver-move win distance (default 3)
//   --max-depth N          Maximum solver-move win distance (default 7)
//   --max-solutions N      Reject roots with more than N winning first
//                          moves; keeps puzzles unambiguous (default 2)
//   --sacrifice include|exclude|only
//                          Filter on whether the solver must give up a
//                          piece somewhere in the line (default include)
//   --opponent-depth N     Heuristic search depth used for the opponent's
//                          replies (default 6)
//
// Misc:
//   --out PATH            Output `.sanmill_puzzles` JSON path
//                          (default puzzles.sanmill_puzzles)
//   --max-attempts N       Sampling attempt budget (default count * 500)
//   --seed HEX             xorshift64* seed; "0" means time-based (default 0)
//   --cache N              Perfect DB sector cache capacity (default 64)
//   --author STR           Author string written into each puzzle (default
//                          "Perfect DB Generator")
//
// A puzzle is accepted only when: the root is a genuine forced win for the
// side to move (not already mid-removal), the number of legal first moves
// that keep the win alive is within `--max-solutions`, and every one of
// those first moves can be played out to an actual win -- with the *solver*
// always playing the Perfect DB's fastest move and the *opponent* always
// playing a heuristic engine's best reply (never the DB's best defense) --
// within the requested depth window. This is what makes a puzzle solvable
// against a realistic opponent rather than only against a defense that
// deliberately prolongs the loss.

mod puzzle_json;
mod sampler;
mod solver;

use std::time::{Instant, SystemTime, UNIX_EPOCH};

use perfect_db::database::{
    Database, DatabaseOptions, DatabaseProvider, DatabaseVariant, FileDatabaseProvider,
    PerfectQuery,
};
use perfect_db::{
    PerfectMoveOrdering, all_move_outcomes_with_ordering, evaluate_state_outcome_with_database,
    snapshot_from_perfect_query,
};
use tgf_core::{Action, ActionList, GameRules, OutcomeKind};
use tgf_mill::{MillGame, MillPhase, MillRules, MillVariantOptions};

use crate::cli_args::parse_flag;
use puzzle_json::{ExportedByJson, PuzzleBuildInput, PuzzleInfoJson, PuzzlePackageJson};
use sampler::{
    PhaseChoice, SampleSpec, SideChoice, next_u64, sample_bits_for_shape, sample_sector_shape,
};
use solver::{BuiltSolution, build_solution_line};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum SacrificeFilter {
    Include,
    Exclude,
    Only,
}

impl SacrificeFilter {
    fn parse(value: &str) -> Self {
        match value {
            "exclude" | "no" | "none" => Self::Exclude,
            "only" => Self::Only,
            _ => Self::Include,
        }
    }

    fn accepts(self, sacrifice: bool) -> bool {
        match self {
            Self::Include => true,
            Self::Exclude => !sacrifice,
            Self::Only => sacrifice,
        }
    }
}

/// Immutable generation environment shared by every sampling attempt.
/// Bundled into one struct purely to keep `try_build_puzzle`'s argument
/// list readable; `database` stays separate because it needs `&mut`.
#[derive(Clone, Copy)]
struct GenEnv<'a> {
    rules: &'a MillRules,
    game: &'a MillGame,
    options: &'a MillVariantOptions,
    cfg: &'a GenConfig,
}

struct GenConfig {
    db_path: String,
    out_path: String,
    count: usize,
    min_depth: i32,
    max_depth: i32,
    side: SideChoice,
    phase: PhaseChoice,
    min_pieces: u8,
    max_pieces: u8,
    max_solutions: usize,
    sacrifice_filter: SacrificeFilter,
    opponent_depth: i32,
    max_attempts: usize,
    seed: u64,
    cache_capacity: usize,
    author: String,
    rule_variant_id: &'static str,
}

fn variant_options_for(name: &str) -> (MillVariantOptions, &'static str) {
    match name {
        "lask" | "lasker" => (
            MillVariantOptions {
                piece_count: 10,
                may_move_in_placing_phase: true,
                ..MillVariantOptions::default()
            },
            "lasker_10mm",
        ),
        "mora" | "morabaraba" => (
            MillVariantOptions {
                piece_count: 12,
                has_diagonal_lines: true,
                ..MillVariantOptions::default()
            },
            "morabaraba_12mm",
        ),
        _ => (MillVariantOptions::default(), "standard_9mm"),
    }
}

pub(crate) fn run_puzzle_gen(args: &[String]) {
    let db_path: String = parse_flag(args, "--db", String::new());
    if db_path.is_empty() {
        eprintln!("[puzzle-gen] ERROR: --db PATH is required");
        eprintln!("  Example: tgf puzzle-gen --db D:/user/Documents/strong --count 50");
        std::process::exit(1);
    }

    let depth_override: i32 = parse_flag(args, "--depth", 0);
    let mut min_depth: i32 = parse_flag(args, "--min-depth", 3);
    let mut max_depth: i32 = parse_flag(args, "--max-depth", 7);
    if depth_override > 0 {
        min_depth = depth_override;
        max_depth = depth_override;
    }
    let min_pieces: u8 = parse_flag(args, "--min-pieces", 3);
    let max_pieces: u8 = parse_flag(args, "--max-pieces", 7);
    if min_depth > max_depth {
        eprintln!(
            "[puzzle-gen] ERROR: --min-depth ({min_depth}) must be <= --max-depth ({max_depth})"
        );
        std::process::exit(1);
    }
    if min_pieces > max_pieces {
        eprintln!(
            "[puzzle-gen] ERROR: --min-pieces ({min_pieces}) must be <= --max-pieces ({max_pieces})"
        );
        std::process::exit(1);
    }

    let count: usize = parse_flag(args, "--count", 20usize);
    let variant_name: String = parse_flag(args, "--variant", "std".to_string());
    let (options, rule_variant_id) = variant_options_for(&variant_name);

    let cfg = GenConfig {
        db_path,
        out_path: parse_flag(args, "--out", "puzzles.sanmill_puzzles".to_string()),
        count,
        min_depth,
        max_depth,
        side: SideChoice::parse(&parse_flag(args, "--side", "random".to_string())),
        phase: PhaseChoice::parse(&parse_flag(args, "--phase", "random".to_string())),
        min_pieces,
        max_pieces,
        max_solutions: parse_flag(args, "--max-solutions", 2usize).max(1),
        sacrifice_filter: SacrificeFilter::parse(&parse_flag(
            args,
            "--sacrifice",
            "include".to_string(),
        )),
        opponent_depth: parse_flag(args, "--opponent-depth", 6i32).max(1),
        max_attempts: {
            let requested: usize = parse_flag(args, "--max-attempts", 0usize);
            if requested > 0 {
                requested
            } else {
                count.saturating_mul(500).max(2000)
            }
        },
        seed: {
            let seed_hex: String = parse_flag(args, "--seed", "0".to_string());
            if seed_hex == "0" {
                SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_nanos() as u64
                    ^ 0x9E37_79B9_7F4A_7C15
            } else {
                u64::from_str_radix(seed_hex.trim_start_matches("0x"), 16).unwrap_or(1)
            }
        },
        cache_capacity: parse_flag(args, "--cache", 64usize),
        author: parse_flag(args, "--author", "Perfect DB Generator".to_string()),
        rule_variant_id,
    };

    eprintln!(
        "[puzzle-gen] db={} variant={variant_name} out={} count={} depth=[{},{}] \
         pieces=[{},{}] side={:?} phase={:?} max_solutions={} sacrifice={:?} \
         opponent_depth={} seed={:#018x}",
        cfg.db_path,
        cfg.out_path,
        cfg.count,
        cfg.min_depth,
        cfg.max_depth,
        cfg.min_pieces,
        cfg.max_pieces,
        cfg.side,
        cfg.phase,
        cfg.max_solutions,
        cfg.sacrifice_filter,
        cfg.opponent_depth,
        cfg.seed,
    );

    let variant = DatabaseVariant::match_mill_options(&options).unwrap_or_else(|err| {
        panic!(
            "[puzzle-gen] --variant {variant_name} does not resolve to a Perfect DB variant: {err}"
        )
    });
    let mut database = Database::open_variant_with_options(
        FileDatabaseProvider::new(std::path::PathBuf::from(&cfg.db_path)),
        variant,
        DatabaseOptions::with_sector_cache_capacity(cfg.cache_capacity),
    )
    .unwrap_or_else(|err| panic!("[puzzle-gen] failed to open DB at {}: {err}", cfg.db_path));

    let rules = MillRules::new(options.clone());
    let game = MillGame::new(options.clone());
    let generated_at = unix_timestamp_to_iso8601(
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs(),
    );

    let env = GenEnv {
        rules: &rules,
        game: &game,
        options: &options,
        cfg: &cfg,
    };
    let mut rng = cfg.seed;
    let mut puzzles: Vec<PuzzleInfoJson> = Vec::with_capacity(cfg.count);
    let mut attempts = 0usize;
    let start = Instant::now();
    let progress_every = (cfg.max_attempts / 20).max(1);
    let spec = SampleSpec {
        phase: cfg.phase,
        side: cfg.side,
        min_pieces: cfg.min_pieces,
        max_pieces: cfg.max_pieces,
    };

    // Every sampling attempt that misses at the very first Perfect DB
    // lookup only ever touches the *root's own* `.sec2` sector. Re-rolling
    // the sector shape (on-board/in-hand counts) on every single attempt
    // therefore thrashes the database's LRU sector cache -- each `.sec2`
    // file is many megabytes, so a cold read dominates the attempt's cost.
    // Reusing one sector shape across a batch of attempts (varying only
    // *which* squares are occupied) keeps most attempts served from the
    // already-cached sector, which is what makes "hundreds of puzzles in a
    // few minutes" achievable against a full external database.
    const ATTEMPTS_PER_SECTOR_SHAPE: usize = 400;

    'outer: while puzzles.len() < cfg.count && attempts < cfg.max_attempts {
        let shape = sample_sector_shape(&mut rng, &spec, &options);
        for _ in 0..ATTEMPTS_PER_SECTOR_SHAPE {
            if puzzles.len() >= cfg.count || attempts >= cfg.max_attempts {
                break 'outer;
            }
            attempts += 1;
            let root_query = sample_bits_for_shape(&mut rng, &shape);

            if let Some(info) =
                try_build_puzzle(&mut database, &env, root_query, &generated_at, &mut rng)
            {
                eprintln!(
                    "[puzzle-gen] {}/{} generated: {} (attempt {attempts})",
                    puzzles.len() + 1,
                    cfg.count,
                    info.title
                );
                puzzles.push(info);
            }

            if attempts.is_multiple_of(progress_every) {
                let elapsed = start.elapsed().as_secs_f64();
                eprintln!(
                    "[puzzle-gen] progress: {}/{} puzzles after {attempts}/{} attempts \
                     ({elapsed:.1}s)",
                    puzzles.len(),
                    cfg.count,
                    cfg.max_attempts,
                );
            }
        }
    }

    if puzzles.len() < cfg.count {
        eprintln!(
            "[puzzle-gen] WARNING: only found {}/{} puzzles within the {} attempt budget; \
             consider widening --min-pieces/--max-pieces/--min-depth/--max-depth or raising \
             --max-attempts",
            puzzles.len(),
            cfg.count,
            cfg.max_attempts,
        );
    }

    let package = PuzzlePackageJson {
        format_version: "1.0",
        exported_by: ExportedByJson {
            app_name: "Sanmill",
            platform: "tgf-cli",
        },
        export_date: generated_at,
        puzzle_count: puzzles.len(),
        puzzles,
    };
    let json_text =
        serde_json::to_string_pretty(&package).expect("puzzle package must serialize to JSON");
    std::fs::write(&cfg.out_path, json_text)
        .unwrap_or_else(|err| panic!("[puzzle-gen] cannot write {}: {err}", cfg.out_path));

    let elapsed = start.elapsed().as_secs_f64();
    eprintln!(
        "[puzzle-gen] done: {} puzzles written to {} in {elapsed:.1}s ({attempts} attempts)",
        package.puzzle_count, cfg.out_path,
    );
}

/// Evaluate one sampled root position and, if it makes a good puzzle,
/// return the fully rendered [`PuzzleInfoJson`].
///
/// Every rejection path is an ordinary, expected sampling miss (wrong WDL,
/// wrong depth, too many/few winning replies, sacrifice filter mismatch,
/// database does not cover a position the line reaches) and simply returns
/// `None` so the caller tries another sample. Only genuine internal
/// inconsistencies (an enumerated move count mismatch, a database variant
/// mismatch after it already opened successfully) panic.
fn try_build_puzzle<P: DatabaseProvider>(
    database: &mut Database<P>,
    env: &GenEnv<'_>,
    root_query: PerfectQuery,
    generated_at: &str,
    rng: &mut u64,
) -> Option<PuzzleInfoJson> {
    let GenEnv {
        rules,
        game,
        options,
        cfg,
    } = *env;
    let root_snap = snapshot_from_perfect_query(rules, options, root_query);
    let root_side = root_snap.side_to_move;
    if root_side != 0 && root_side != 1 {
        return None;
    }
    if rules.outcome(&root_snap).kind != OutcomeKind::Ongoing {
        return None;
    }

    let root_state = MillRules::decode_snapshot(root_snap);
    if root_state.pending_removals()[root_side as usize] > 0 {
        // Mid-removal is not a clean puzzle starting point.
        return None;
    }

    let root_outcome =
        match evaluate_state_outcome_with_database(database, &root_state, options, root_side) {
            Ok(Some(outcome)) => outcome,
            Ok(None) => return None,
            Err(err) if err.is_missing_asset() => return None,
            Err(err) => {
                panic!("[puzzle-gen] Perfect DB error while evaluating a sampled root: {err}")
            }
        };
    if root_outcome.wdl() != 1 {
        return None;
    }
    let steps = root_outcome.steps();
    if steps <= 0 {
        return None;
    }
    // Cheap pre-filter on the DB's raw step count before paying for full
    // line simulation. Generous slack absorbs the difference between DTW
    // plies (perfect defense) and the app's own solver-move counting
    // convention (heuristic defense, which can resolve sooner).
    let approx_moves = (steps + 1) / 2;
    if approx_moves > cfg.max_depth + 4 {
        return None;
    }

    let all_outcomes = match all_move_outcomes_with_ordering(
        database,
        rules,
        &root_snap,
        options,
        PerfectMoveOrdering::StrictSteps,
    ) {
        Ok(Some(outcomes)) => outcomes,
        Ok(None) => return None,
        Err(err) if err.is_missing_asset() => return None,
        Err(err) => panic!("[puzzle-gen] Perfect DB error while enumerating root moves: {err}"),
    };

    let mut legal = ActionList::<256>::new();
    rules.legal_actions(&root_snap, &mut legal);
    assert_eq!(
        legal.as_slice().len(),
        all_outcomes.len(),
        "move outcome enumeration must align 1:1 with legal_actions"
    );

    let winning: Vec<Action> = legal
        .as_slice()
        .iter()
        .zip(all_outcomes.iter())
        .filter(|(_, choice)| choice.outcome.wdl() == 1)
        .map(|(&action, _)| action)
        .collect();
    assert!(
        !winning.is_empty(),
        "a forced-win root must have at least one winning legal move"
    );
    if winning.len() > cfg.max_solutions {
        return None;
    }

    let mut solutions: Vec<BuiltSolution> = Vec::with_capacity(winning.len());
    for &first_action in &winning {
        let opponent_seed = next_u64(rng);
        let built = build_solution_line(
            database,
            rules,
            game,
            options,
            cfg.opponent_depth,
            opponent_seed,
            root_snap,
            root_side,
            first_action,
        )?;
        if built.solver_move_count < cfg.min_depth || built.solver_move_count > cfg.max_depth {
            return None;
        }
        solutions.push(built);
    }

    let has_sacrifice = solutions.iter().any(|s| s.sacrifice);
    if !cfg.sacrifice_filter.accepts(has_sacrifice) {
        return None;
    }

    let fen = rules.export_fen(&root_state);
    let input = PuzzleBuildInput {
        fen: &fen,
        solver_side: root_side,
        is_moving_phase: root_state.phase() == MillPhase::Moving,
        solutions: &solutions,
        author: &cfg.author,
        rule_variant_id: cfg.rule_variant_id,
        generated_at,
    };
    Some(puzzle_json::build_puzzle_info(&input))
}

/// Convert a Unix timestamp (seconds since 1970-01-01T00:00:00Z) to an
/// ISO-8601 UTC string, e.g. `2026-07-02T03:04:05.000Z`.
///
/// Implements the standard `civil_from_days` algorithm (Howard Hinnant's
/// public-domain date algorithms) so this crate does not need a `chrono`
/// dependency just to stamp puzzle export files.
fn unix_timestamp_to_iso8601(total_secs: u64) -> String {
    let days = (total_secs / 86_400) as i64;
    let secs_of_day = total_secs % 86_400;
    let (year, month, day) = civil_from_days(days);
    let hour = secs_of_day / 3600;
    let minute = (secs_of_day % 3600) / 60;
    let second = secs_of_day % 60;
    format!("{year:04}-{month:02}-{day:02}T{hour:02}:{minute:02}:{second:02}.000Z")
}

fn civil_from_days(z: i64) -> (i64, u32, u32) {
    let z = z + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as u64;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365;
    let y = yoe as i64 + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    let y = if m <= 2 { y + 1 } else { y };
    (y, m, d)
}

#[cfg(test)]
mod tests;
