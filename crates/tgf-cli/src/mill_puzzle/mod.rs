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
//   --min-solver-pieces N  Override the lower bound for the side to move
//   --max-solver-pieces N  Override the upper bound for the side to move
//   --min-defender-pieces N Override the lower bound for the other side
//   --max-defender-pieces N Override the upper bound for the other side
//   --variant std|lask|mora  Rule variant to sample/query (default std)
//   --candidate-file PATH  Consume a Z3 candidate package instead of random
//                          sampling; the package declares its required motif
//   --mine-entry-file PATHS
//                          Consume comma-separated `tgf mill mine` JSONL
//                          files instead of random sampling. Inputs are
//                          streamed, ranked and balanced by material shape.
//   --mine-candidate-limit N
//                          Maximum ranked mine roots retained for exact
//                          certification (default 20000)
//   --mine-per-shape-limit N
//                          Bounded-memory shortlist per phase/material shape
//                          before global balancing (default 512)
//   --mine-min-severity N  Minimum source WDL drop, 1 or 2 (default 1)
//   --mine-min-mass F      Minimum source reach mass (default 0)
//   --mine-min-depth-used N
//                          Minimum mining-engine depth evidence (default 0)
//   --mine-min-placements N
//                          Require at least N primary placements to have
//                          occurred; 12 skips the first six full rounds
//                          under alternating placement (default 0)
//   --exclude-fens PATH    Ignore every root symmetry-equivalent to a
//                          non-comment FEN line in this file
//   --motif NAME           Require every shortest winning first turn to
//                          exhibit one exact Rust theme predicate. Useful
//                          names include allow-mill, mobility-squeeze,
//                          junction-release, mill-recovery,
//                          right-angle-threat and ring-transfer.
//
// Difficulty / shape:
//   --depth N             Exact "win in N moves" (overrides min/max depth)
//   --min-depth N          Minimum solver-move win distance (default 3)
//   --max-depth N          Maximum solver-move win distance (default 7)
//   --max-solutions N      Reject roots with more than N equally shortest
//                          winning first turns (default 2)
//   --max-exported-lines N Reject puzzles whose flattened shortest/slower
//                          strategy needs more than N replay lines
//                          (default 128, hard maximum 128)
//   --min-mistakes N       Require at least N complete legal first turns
//                          that fail to achieve the shortest forced win
//                          (default 2)
//   --max-piece-diff N     Maximum material advantage (board + hand) the
//                          solving side may start with; the opponent may
//                          always outnumber the solver (default 1)
//   --min-solve-depth D    Reject puzzles whose first move is already found
//                          by a heuristic search shallower than D plies;
//                          probes run at depths 2/4/6/8 with a deterministic
//                          node budget, so 4 rejects one-glance tactics and
//                          anything above 8 keeps only puzzles that defeat
//                          every bounded probe (default 4)
//   --require-trap         Only accept roots where a mill-closing capture
//                          exists that loses or draws -- the "tempting mill
//                          fails" motif (off by default)
//   --require-quiet-first-move
//                          Require every shortest first turn to begin without
//                          closing a mill (off by default)
//   --min-non-winning-turns N
//                          Require this many complete first turns to draw or
//                          lose, excluding merely slower wins (default 0)
//   --sacrifice include|exclude|only
//                          Filter on whether the solver must give up a
//                          piece somewhere in the line (default include)
// Output:
//   --out PATH            Output `.sanmill_puzzles` JSON path
//                          (default puzzles.sanmill_puzzles)
//   --pack-id ID           Emit a puzzle-pack `metadata` block with this id
//                          (needed when regenerating the built-in asset)
//   --pack-name NAME       Pack display name (defaults to the pack id)
//   --pack-description S   Pack description text
//   --review-pack          Mark emitted metadata as unofficial review material
//
// Misc:
//   --max-attempts N       Sampling attempt budget (default count * 6000;
//                          the challenge filters accept roughly one root in
//                          several thousand samples)
//   --seed HEX             xorshift64* seed; "0" means time-based (default 0)
//   --cache N              Perfect DB sector cache capacity (default 64)
//   --author STR           Author string written into each puzzle (default
//                          "Perfect DB Generator")
//
// A root position is accepted only when all of the following hold, which is
// what separates a *puzzle* from a mere winning position:
//
//   * it is a genuine forced win for the side to move (not mid-removal),
//     with the material-balance cap respected;
//   * at most `--max-solutions` complete first turns achieve the shortest
//     forced win and at least `--min-mistakes` turns are slower or
//     non-winning, so the solver has real choices and real ways to fail;
//   * a heuristic search probe (depths 2/4/6/8) standing in for a human
//     solver does NOT find a winning first move below `--min-solve-depth`
//     -- shallow, obvious tactics are rejected, and the shallowest solving
//     depth drives the exported difficulty rating;
//   * every shortest first turn plays out to an actual win under exact
//     database play: the solver minimises the win distance and a losing
//     defender delays defeat for as long as possible;
//   * the position is not a board symmetry of an already accepted puzzle.
//
// Along the way the generator fingerprints each puzzle's tactics (tempting
// mill traps, quiet first moves, only-move precision, swing mills,
// immobilization wins, sacrifices, wins against a flying defense) and turns
// that into the title, hint, completion message, tags, and rating.

mod analysis;
mod candidate_input;
mod mine_entry_input;
mod motifs;
mod puzzle_json;
mod sampler;
mod solver;

use std::collections::HashSet;
use std::time::{Instant, SystemTime, UNIX_EPOCH};

use perfect_db::database::{
    Database, DatabaseOptions, DatabaseProvider, DatabaseVariant, FileDatabaseProvider,
    PerfectQuery,
};
use perfect_db::{
    all_logical_turn_outcomes_with_database, evaluate_state_outcome_with_database,
    query_from_state, snapshot_from_perfect_query,
};
use tgf_core::{GameRules, OutcomeKind};
use tgf_mill::{MillGame, MillPhase, MillRules, MillVariantOptions};

use crate::cli_args::{flag_present, parse_flag};
use analysis::{canonical_symmetry_key, classify_root_turns, shallowest_solving_depth};
use candidate_input::{
    CandidateDiscovery, EngineBlunderEvidence, HumanReplayEvidence, LoadedCandidateSet,
    load_constraint_candidates,
};
use mine_entry_input::{MineEntryLoadConfig, load_mine_entry_candidates};
use motifs::{PuzzleMotif, matches_required_motif};
use puzzle_json::{
    ExportedByJson, PuzzleBuildInput, PuzzleInfoJson, PuzzlePackMetadataJson, PuzzlePackageJson,
    PuzzleTraits,
};
use sampler::{
    PhaseChoice, SampleSpec, SideChoice, next_u64, sample_bits_for_shape, sample_sector_shape,
};
use solver::{
    BuiltSolution, MAX_EXPORTED_SOLUTION_LINES, build_principal_solution_line, build_solution_lines,
};

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
    /// Non-empty selects deterministic Z3 package input over random sampling.
    candidate_file: String,
    /// Non-empty selects ranked `tgf mill mine` JSONL input.
    mine_entry_files: String,
    /// Optional newline-delimited FEN roots excluded under all symmetries.
    exclude_fens: String,
    required_motif: PuzzleMotif,
    candidate_discovery: Option<CandidateDiscovery>,
    count: usize,
    min_depth: i32,
    max_depth: i32,
    side: SideChoice,
    phase: PhaseChoice,
    min_solver_pieces: u8,
    max_solver_pieces: u8,
    min_defender_pieces: u8,
    max_defender_pieces: u8,
    max_solutions: usize,
    /// Maximum complete replay lines stored for one compact puzzle.
    max_exported_lines: usize,
    /// Minimum number of complete legal first turns that are not tied for
    /// the shortest forced win.
    min_mistakes: usize,
    /// Maximum material advantage (board + hand) of the solving side.
    max_piece_diff: i32,
    /// Reject candidates whose winning first move is found by a heuristic
    /// probe shallower than this depth. See [`analysis::PROBE_DEPTHS`].
    min_solve_depth: i32,
    /// Require a mill-closing first move that throws the win away.
    require_trap: bool,
    /// Require every shortest winning first turn to start quietly.
    require_quiet_first_move: bool,
    /// Complete first turns which draw or lose, excluding slower wins.
    min_non_winning_turns: usize,
    sacrifice_filter: SacrificeFilter,
    max_attempts: usize,
    seed: u64,
    cache_capacity: usize,
    author: String,
    rule_variant_id: &'static str,
    /// Non-empty enables the exported `metadata` pack block.
    pack_id: String,
    pack_name: String,
    pack_description: String,
    is_official: bool,
}

#[derive(Default)]
struct GenAudit {
    exact_wins: usize,
    exact_draws: usize,
    exact_losses: usize,
    exact_unavailable: usize,
    motif_matches: usize,
    human_missed_wins: usize,
    too_many_shortest: usize,
    too_few_mistakes: usize,
    too_few_non_winning: usize,
    trap_rejected: usize,
    quiet_first_rejected: usize,
    solution_unavailable: usize,
    solution_depth_rejected: usize,
    solution_line_cap: usize,
    public_distance_mismatch: usize,
    shallow_probe_rejected: usize,
    sacrifice_rejected: usize,
    published: usize,
}

/// Mutable generation state shared by one candidate attempt.
///
/// Keeping these related values together makes the state mutation explicit
/// without mixing them into the immutable [`GenEnv`].
struct GenAttemptContext<'a> {
    generated_at: &'a str,
    rng: &'a mut u64,
    seen_roots: &'a mut HashSet<u64>,
    audit: &'a mut GenAudit,
}

pub(crate) fn variant_options_for(name: &str) -> (MillVariantOptions, &'static str) {
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
    let min_solver_pieces: u8 = parse_flag(args, "--min-solver-pieces", min_pieces);
    let max_solver_pieces: u8 = parse_flag(args, "--max-solver-pieces", max_pieces);
    let min_defender_pieces: u8 = parse_flag(args, "--min-defender-pieces", min_pieces);
    let max_defender_pieces: u8 = parse_flag(args, "--max-defender-pieces", max_pieces);
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
    for (label, minimum, maximum) in [
        ("solver", min_solver_pieces, max_solver_pieces),
        ("defender", min_defender_pieces, max_defender_pieces),
    ] {
        if minimum > maximum {
            eprintln!(
                "[puzzle-gen] ERROR: --min-{label}-pieces ({minimum}) must be <= \
                 --max-{label}-pieces ({maximum})"
            );
            std::process::exit(1);
        }
    }

    let count: usize = parse_flag(args, "--count", 20usize);
    let variant_name: String = parse_flag(args, "--variant", "std".to_string());
    let (options, rule_variant_id) = variant_options_for(&variant_name);
    let rules = MillRules::new(options.clone());
    let game = MillGame::new(options.clone());
    let pack_id: String = parse_flag(args, "--pack-id", String::new());
    let candidate_file: String = parse_flag(args, "--candidate-file", String::new());
    let mine_entry_files: String = parse_flag(args, "--mine-entry-file", String::new());
    if !candidate_file.is_empty() && !mine_entry_files.is_empty() {
        eprintln!(
            "[puzzle-gen] ERROR: --candidate-file and --mine-entry-file are mutually exclusive"
        );
        std::process::exit(1);
    }
    if !mine_entry_files.is_empty() && rule_variant_id != "standard_9mm" {
        eprintln!("[puzzle-gen] ERROR: --mine-entry-file currently supports only --variant std");
        std::process::exit(1);
    }
    let phase = PhaseChoice::parse(&parse_flag(args, "--phase", "random".to_string()));
    let side = SideChoice::parse(&parse_flag(args, "--side", "random".to_string()));
    let seed = {
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
    };
    let requested_max_attempts: usize = parse_flag(args, "--max-attempts", 0usize);
    let spec = SampleSpec {
        phase,
        side,
        min_solver_pieces,
        max_solver_pieces,
        min_defender_pieces,
        max_defender_pieces,
    };
    let source_candidates: Option<LoadedCandidateSet> = if !candidate_file.is_empty() {
        Some(load_constraint_candidates(&candidate_file))
    } else if !mine_entry_files.is_empty() {
        Some(load_mine_entry_candidates(
            MineEntryLoadConfig {
                paths: &mine_entry_files,
                candidate_limit: parse_flag(args, "--mine-candidate-limit", 20_000usize).max(1),
                per_shape_limit: parse_flag(args, "--mine-per-shape-limit", 512usize).max(1),
                min_severity: parse_flag(args, "--mine-min-severity", 1i8),
                min_mass: parse_flag(args, "--mine-min-mass", 0.0f64),
                min_depth_used: parse_flag(args, "--mine-min-depth-used", 0i32),
                min_placements: parse_flag(args, "--mine-min-placements", 0u8),
                seed,
                spec,
            },
            &rules,
            &options,
        ))
    } else {
        None
    };
    let source_motif = source_candidates
        .as_ref()
        .map(|loaded| loaded.motif)
        .unwrap_or(PuzzleMotif::Any);
    let requested_motif_name: String = parse_flag(args, "--motif", String::new());
    let requested_motif = if requested_motif_name.is_empty() {
        None
    } else {
        let motif = PuzzleMotif::parse(&requested_motif_name);
        if motif == PuzzleMotif::Any {
            eprintln!("[puzzle-gen] ERROR: unsupported --motif `{requested_motif_name}`");
            std::process::exit(1);
        }
        Some(motif)
    };
    if let Some(requested_motif) = requested_motif
        && source_motif != PuzzleMotif::Any
        && source_motif != requested_motif
    {
        eprintln!(
            "[puzzle-gen] ERROR: --motif `{requested_motif_name}` conflicts with \
             candidate source motif `{}`",
            source_motif.tag().unwrap_or("unspecified")
        );
        std::process::exit(1);
    }
    let required_motif = requested_motif.unwrap_or(source_motif);
    let candidate_count = source_candidates
        .as_ref()
        .map(|loaded| loaded.candidates.len());

    let cfg = GenConfig {
        db_path,
        out_path: parse_flag(args, "--out", "puzzles.sanmill_puzzles".to_string()),
        candidate_file,
        mine_entry_files,
        exclude_fens: parse_flag(args, "--exclude-fens", String::new()),
        required_motif,
        candidate_discovery: source_candidates
            .as_ref()
            .map(|loaded| loaded.discovery.clone()),
        count,
        min_depth,
        max_depth,
        side,
        phase,
        min_solver_pieces,
        max_solver_pieces,
        min_defender_pieces,
        max_defender_pieces,
        max_solutions: parse_flag(args, "--max-solutions", 2usize).max(1),
        max_exported_lines: parse_flag(args, "--max-exported-lines", MAX_EXPORTED_SOLUTION_LINES)
            .clamp(1, MAX_EXPORTED_SOLUTION_LINES),
        min_mistakes: parse_flag(args, "--min-mistakes", 2usize),
        max_piece_diff: parse_flag(args, "--max-piece-diff", 1i32),
        min_solve_depth: parse_flag(args, "--min-solve-depth", 4i32),
        require_trap: flag_present(args, "--require-trap"),
        require_quiet_first_move: flag_present(args, "--require-quiet-first-move"),
        min_non_winning_turns: parse_flag(args, "--min-non-winning-turns", 0usize),
        sacrifice_filter: SacrificeFilter::parse(&parse_flag(
            args,
            "--sacrifice",
            "include".to_string(),
        )),
        max_attempts: {
            if requested_max_attempts > 0 {
                requested_max_attempts
            } else if let Some(candidate_count) = candidate_count {
                candidate_count
            } else {
                count.saturating_mul(6000).max(20000)
            }
        },
        seed,
        cache_capacity: parse_flag(args, "--cache", 64usize),
        author: parse_flag(args, "--author", "Perfect DB Generator".to_string()),
        rule_variant_id,
        pack_name: parse_flag(args, "--pack-name", pack_id.clone()),
        pack_description: parse_flag(args, "--pack-description", String::new()),
        is_official: !flag_present(args, "--review-pack"),
        pack_id,
    };

    eprintln!(
        "[puzzle-gen] db={} variant={variant_name} out={} count={} depth=[{},{}] \
         solver_pieces=[{},{}] defender_pieces=[{},{}] side={:?} phase={:?} \
         max_solutions={} min_mistakes={} min_non_winning_turns={} \
         max_exported_lines={} max_piece_diff={} min_solve_depth={} \
         require_trap={} require_quiet_first_move={} sacrifice={:?} motif={:?} \
         candidate_file={} mine_entry_file={} \
         exclude_fens={} seed={:#018x}",
        cfg.db_path,
        cfg.out_path,
        cfg.count,
        cfg.min_depth,
        cfg.max_depth,
        cfg.min_solver_pieces,
        cfg.max_solver_pieces,
        cfg.min_defender_pieces,
        cfg.max_defender_pieces,
        cfg.side,
        cfg.phase,
        cfg.max_solutions,
        cfg.min_mistakes,
        cfg.min_non_winning_turns,
        cfg.max_exported_lines,
        cfg.max_piece_diff,
        cfg.min_solve_depth,
        cfg.require_trap,
        cfg.require_quiet_first_move,
        cfg.sacrifice_filter,
        cfg.required_motif,
        if cfg.candidate_file.is_empty() {
            "-"
        } else {
            &cfg.candidate_file
        },
        if cfg.mine_entry_files.is_empty() {
            "-"
        } else {
            &cfg.mine_entry_files
        },
        if cfg.exclude_fens.is_empty() {
            "-"
        } else {
            &cfg.exclude_fens
        },
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
    let mut seen_roots = load_excluded_roots(&cfg.exclude_fens, &rules, &options);
    let mut audit = GenAudit::default();
    if !seen_roots.is_empty() {
        eprintln!(
            "[puzzle-gen] loaded {} exact/symmetry exclusion roots",
            seen_roots.len()
        );
    }
    let mut attempts = 0usize;
    let start = Instant::now();
    let progress_every = (cfg.max_attempts / 20).max(1);
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

    if let Some(loaded) = source_candidates {
        for candidate in loaded.candidates.into_iter().take(cfg.max_attempts) {
            if puzzles.len() >= cfg.count {
                break;
            }
            attempts += 1;
            let mut context = GenAttemptContext {
                generated_at: &generated_at,
                rng: &mut rng,
                seen_roots: &mut seen_roots,
                audit: &mut audit,
            };
            if let Some(info) = try_build_puzzle(
                &mut database,
                &env,
                candidate.query,
                candidate.replay.as_ref(),
                candidate.engine_blunder.as_ref(),
                &mut context,
            ) {
                eprintln!(
                    "[puzzle-gen] {}/{} generated: {} [{}] (attempt {attempts})",
                    puzzles.len() + 1,
                    cfg.count,
                    info.title,
                    info.difficulty,
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
    } else {
        'outer: while puzzles.len() < cfg.count && attempts < cfg.max_attempts {
            let shape = sample_sector_shape(&mut rng, &spec, &options);
            for _ in 0..ATTEMPTS_PER_SECTOR_SHAPE {
                if puzzles.len() >= cfg.count || attempts >= cfg.max_attempts {
                    break 'outer;
                }
                attempts += 1;
                let root_query = sample_bits_for_shape(&mut rng, &shape);

                let mut context = GenAttemptContext {
                    generated_at: &generated_at,
                    rng: &mut rng,
                    seen_roots: &mut seen_roots,
                    audit: &mut audit,
                };
                if let Some(info) =
                    try_build_puzzle(&mut database, &env, root_query, None, None, &mut context)
                {
                    eprintln!(
                        "[puzzle-gen] {}/{} generated: {} [{}] (attempt {attempts})",
                        puzzles.len() + 1,
                        cfg.count,
                        info.title,
                        info.difficulty,
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
    }

    if puzzles.len() < cfg.count {
        if cfg.candidate_file.is_empty() && cfg.mine_entry_files.is_empty() {
            eprintln!(
                "[puzzle-gen] WARNING: only found {}/{} puzzles within the {} attempt budget; \
                 consider widening --min-pieces/--max-pieces/--min-depth/--max-depth, relaxing \
                 --min-solve-depth/--min-mistakes/--require-trap, or raising --max-attempts",
                puzzles.len(),
                cfg.count,
                cfg.max_attempts,
            );
        } else {
            eprintln!(
                "[puzzle-gen] WARNING: only certified {}/{} puzzles from {}/{} inspected \
                 source candidates; widen the source shortlist or relax publication gates",
                puzzles.len(),
                cfg.count,
                attempts,
                cfg.max_attempts,
            );
        }
    }

    let package = PuzzlePackageJson {
        format_version: "1.0",
        exported_by: ExportedByJson {
            app_name: "Sanmill",
            platform: "tgf-cli",
        },
        export_date: generated_at,
        puzzle_count: puzzles.len(),
        metadata: build_pack_metadata(&cfg),
        puzzles,
    };
    let json_text =
        serde_json::to_string_pretty(&package).expect("puzzle package must serialize to JSON");
    std::fs::write(&cfg.out_path, json_text)
        .unwrap_or_else(|err| panic!("[puzzle-gen] cannot write {}: {err}", cfg.out_path));

    let elapsed = start.elapsed().as_secs_f64();
    eprintln!(
        "[puzzle-gen] audit: exact={}W/{}D/{}L unavailable={} motif-matches={} \
         human-missed-wins={} shortest-cap={} mistake-floor={} non-winning-floor={} \
         trap={} quiet-first={} solution-unavailable={} depth={} line-cap={} \
         distance-mismatch={} shallow={} sacrifice={} published={}",
        audit.exact_wins,
        audit.exact_draws,
        audit.exact_losses,
        audit.exact_unavailable,
        audit.motif_matches,
        audit.human_missed_wins,
        audit.too_many_shortest,
        audit.too_few_mistakes,
        audit.too_few_non_winning,
        audit.trap_rejected,
        audit.quiet_first_rejected,
        audit.solution_unavailable,
        audit.solution_depth_rejected,
        audit.solution_line_cap,
        audit.public_distance_mismatch,
        audit.shallow_probe_rejected,
        audit.sacrifice_rejected,
        audit.published,
    );
    eprintln!(
        "[puzzle-gen] done: {} puzzles written to {} in {elapsed:.1}s ({attempts} attempts)",
        package.puzzle_count, cfg.out_path,
    );
}

/// Build the optional pack `metadata` block. Only emitted when `--pack-id`
/// was given; packs produced this way are marked official because that is
/// exactly the path used to regenerate the committed built-in asset.
fn build_pack_metadata(cfg: &GenConfig) -> Option<PuzzlePackMetadataJson> {
    if cfg.pack_id.is_empty() {
        return None;
    }
    let description = if !cfg.pack_description.is_empty() {
        cfg.pack_description.clone()
    } else {
        match cfg.candidate_discovery.as_ref() {
            Some(CandidateDiscovery::SmtZ3 { solver_version }) => {
                let motif = cfg.required_motif.tag().unwrap_or("unspecified");
                format!(
                    "Constraint-directed composed positions whose geometry was synthesised with \
                     Z3 {solver_version}. Rust/TGF independently validates the requested {motif} \
                     theme and every legal transition; Perfect DB remains the sole authority for \
                     forced-win and distance claims. No legal replay witness is claimed."
                )
            }
            Some(CandidateDiscovery::HumanGameReplay {
                corpus,
                database_sha256,
                ..
            }) => format!(
                "Replay-backed positions extracted from {corpus}. Rust/TGF replays every \
                 anonymised source history, and Perfect DB proves that the recorded human turn \
                 threw away a forced win. Database snapshot {}.",
                &database_sha256[..12],
            ),
            Some(CandidateDiscovery::EngineBlunderCorpus {
                manifest_sha256,
                source_file_count,
                inspected_rows,
                eligible_rows,
            }) => format!(
                "Composed positions shortlisted from {source_file_count} reproducible engine-error \
                 mining files ({} rows inspected; {eligible_rows} passed source filters). Source \
                 manifest {}. Source severity, search depth and reach mass rank candidates only; \
                 Rust/TGF and Perfect DB independently certify every complete logical turn, \
                 shortest-win distance and published solution.",
                inspected_rows,
                &manifest_sha256[..12],
            ),
            None => "Forced-win puzzles generated from the Malom perfect-play database. Each \
                     position is selected for its challenge: few complete first turns achieve \
                     the shortest win, natural-looking alternatives are slower or throw it away, \
                     and a search probe filters out shallow tactics. Official lines use exact \
                     database defence that delays forced defeat. These are composed, \
                     rule-consistent positions; no legal replay witness is claimed."
                .to_string(),
        }
    };
    let mut tags = vec!["generated".to_string(), "malom-db".to_string()];
    match cfg.candidate_discovery.as_ref() {
        Some(CandidateDiscovery::SmtZ3 { .. }) => {
            tags.push("smt-z3".to_string());
            if let Some(tag) = cfg.required_motif.tag() {
                tags.push(format!("motif:{tag}"));
            }
        }
        Some(CandidateDiscovery::HumanGameReplay { .. }) => {
            tags.push("human-game".to_string());
            tags.push("replay-backed".to_string());
        }
        Some(CandidateDiscovery::EngineBlunderCorpus { .. }) => {
            tags.push("engine-blunder-corpus".to_string());
            tags.push("composed".to_string());
        }
        None => {}
    }
    Some(PuzzlePackMetadataJson {
        id: cfg.pack_id.clone(),
        name: cfg.pack_name.clone(),
        description,
        author: cfg.author.clone(),
        version: "1.0.0",
        tags,
        is_official: cfg.is_official,
        rule_variant_id: cfg.rule_variant_id.to_string(),
    })
}

/// Material advantage of the side to move in `query`, counting board and
/// hand together. Positive means the solver outnumbers the defender.
fn solver_material_advantage(query: &PerfectQuery) -> i32 {
    let white_total = query.white_bits.count_ones() as i32 + i32::from(query.white_in_hand);
    let black_total = query.black_bits.count_ones() as i32 + i32::from(query.black_in_hand);
    if query.side_to_move == 0 {
        white_total - black_total
    } else {
        black_total - white_total
    }
}

fn load_excluded_roots(
    path: &str,
    rules: &MillRules,
    options: &MillVariantOptions,
) -> HashSet<u64> {
    if path.is_empty() {
        return HashSet::new();
    }
    let text = std::fs::read_to_string(path)
        .unwrap_or_else(|err| panic!("[puzzle-gen] cannot read exclusion FENs {path}: {err}"));
    let mut roots = HashSet::new();
    for (index, raw_line) in text.lines().enumerate() {
        let line = raw_line.trim().trim_start_matches('\u{feff}');
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let state = rules.set_from_fen(line).unwrap_or_else(|err| {
            panic!(
                "[puzzle-gen] invalid exclusion FEN at {path}:{}: {err}",
                index + 1
            )
        });
        let side = state.side_to_move();
        let query = query_from_state(&state, options, side).unwrap_or_else(|| {
            panic!(
                "[puzzle-gen] exclusion FEN at {path}:{} is outside the selected Perfect DB \
                 variant",
                index + 1
            )
        });
        roots.insert(canonical_symmetry_key(&query));
    }
    roots
}

/// Evaluate one sampled root position and, if it makes a good puzzle,
/// return the fully rendered [`PuzzleInfoJson`].
///
/// Every rejection path is an ordinary, expected sampling miss (wrong WDL,
/// wrong depth, too many shortest or too few non-shortest replies, no trap when
/// one is required, a shallow probe solving it, a symmetry duplicate,
/// database does not cover a position the line reaches) and simply returns
/// `None` so the caller tries another sample. Only genuine internal
/// inconsistencies (an enumerated move count mismatch, a database variant
/// mismatch after it already opened successfully) panic.
fn try_build_puzzle<P: DatabaseProvider>(
    database: &mut Database<P>,
    env: &GenEnv<'_>,
    root_query: PerfectQuery,
    replay: Option<&HumanReplayEvidence>,
    engine_blunder: Option<&EngineBlunderEvidence>,
    context: &mut GenAttemptContext<'_>,
) -> Option<PuzzleInfoJson> {
    let generated_at = context.generated_at;
    let rng = &mut *context.rng;
    let seen_roots = &mut *context.seen_roots;
    let audit = &mut *context.audit;
    let GenEnv {
        rules,
        game,
        options,
        cfg,
    } = *env;
    if solver_material_advantage(&root_query) > cfg.max_piece_diff {
        // Steamroller positions (e.g. five pieces against three) win no
        // matter what the solver plays; they are never good puzzles.
        return None;
    }

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

    let dedup_key = canonical_symmetry_key(&root_query);
    if seen_roots.contains(&dedup_key) {
        return None;
    }

    let root_outcome =
        match evaluate_state_outcome_with_database(database, &root_state, options, root_side) {
            Ok(Some(outcome)) => outcome,
            Ok(None) => {
                audit.exact_unavailable += 1;
                return None;
            }
            Err(err) if err.is_missing_asset() => {
                audit.exact_unavailable += 1;
                return None;
            }
            Err(err) => {
                panic!("[puzzle-gen] Perfect DB error while evaluating a sampled root: {err}")
            }
        };
    match root_outcome.wdl() {
        1 => audit.exact_wins += 1,
        0 => audit.exact_draws += 1,
        -1 => audit.exact_losses += 1,
        unexpected => panic!("[puzzle-gen] unexpected Perfect DB WDL value {unexpected}"),
    }
    if root_outcome.wdl() != 1 {
        return None;
    }
    if root_outcome.steps() <= 0 {
        return None;
    }

    let all_turns =
        match all_logical_turn_outcomes_with_database(database, rules, &root_snap, &[], options) {
            Ok(Some(turns)) => turns,
            Ok(None) => return None,
            Err(err) if err.is_missing_asset() => return None,
            Err(err) => {
                panic!("[puzzle-gen] Perfect DB error while enumerating complete root turns: {err}")
            }
        };

    let breakdown = classify_root_turns(rules, &root_snap, &all_turns, root_side);
    assert!(
        !breakdown.shortest_winning.is_empty(),
        "a forced-win root must have at least one shortest winning logical turn"
    );
    if let Some(replay) = replay {
        let recorded = all_turns
            .iter()
            .find(|choice| choice.actions == replay.recorded_actions)
            .unwrap_or_else(|| {
                panic!(
                    "[puzzle-gen] replay-validated recorded turn `{}` is absent from the \
                     complete root-turn enumeration",
                    replay.recorded_turn
                )
            });
        if recorded.outcome.wdl() == 1 {
            // Chess-like reverse extraction needs a real evaluation swing:
            // the human turn must throw away the win, not merely choose a
            // different or slower winning continuation.
            return None;
        }
        audit.human_missed_wins += 1;
        eprintln!(
            "[puzzle-gen] human swing: source={} ply={} transform={} root-steps={} \
             recorded={} recorded-wdl={} shortest-turns={}",
            &replay.source_game_sha256[..12],
            replay.source_logical_ply,
            replay.presentation_transform,
            root_outcome.steps(),
            replay.recorded_turn,
            recorded.outcome.wdl(),
            breakdown.shortest_winning.len(),
        );
    }
    if !matches_required_motif(
        cfg.required_motif,
        rules,
        &root_snap,
        root_side,
        &all_turns,
        &breakdown,
    ) {
        return None;
    }
    audit.motif_matches += 1;
    if breakdown.shortest_winning.len() > cfg.max_solutions {
        audit.too_many_shortest += 1;
        return None;
    }
    if breakdown.non_shortest_count() < cfg.min_mistakes {
        // With (almost) every legal turn tied for shortest, the puzzle
        // solves itself.
        audit.too_few_mistakes += 1;
        return None;
    }
    if breakdown.non_winning_count < cfg.min_non_winning_turns {
        audit.too_few_non_winning += 1;
        return None;
    }
    if cfg.require_trap && !breakdown.tempting_mill_mistake {
        audit.trap_rejected += 1;
        return None;
    }
    if cfg.require_quiet_first_move && !breakdown.quiet_first_move {
        audit.quiet_first_rejected += 1;
        return None;
    }

    let mut solutions: Vec<BuiltSolution> = Vec::new();
    for first_turn in &breakdown.shortest_winning {
        let replay_backed = replay.is_some();
        let built = if replay_backed {
            build_principal_solution_line(
                database, rules, options, root_snap, root_side, first_turn,
            )
            .map(|line| vec![line])
        } else {
            build_solution_lines(
                database,
                rules,
                options,
                root_snap,
                root_side,
                first_turn,
                cfg.max_exported_lines,
            )
        };
        let mut lines = match built {
            Ok(lines) => lines,
            Err(failure) => {
                if replay.is_some() {
                    eprintln!("[puzzle-gen] human strategy rejected: {failure:?}");
                }
                audit.solution_unavailable += 1;
                return None;
            }
        };
        if lines.iter().any(|line| {
            line.solver_move_count < cfg.min_depth || line.solver_move_count > cfg.max_depth
        }) {
            audit.solution_depth_rejected += 1;
            return None;
        }
        solutions.append(&mut lines);
        if solutions.len() > cfg.max_exported_lines {
            audit.solution_line_cap += 1;
            return None;
        }
    }
    let target_moves = solutions
        .iter()
        .map(|solution| solution.solver_move_count)
        .min()
        .expect("every shortest first turn must produce a solution line");
    if solutions
        .iter()
        .any(|solution| solution.solver_move_count != target_moves)
    {
        // Raw StrictSteps ties must agree with the public logical-turn
        // distance before this candidate can be published.
        audit.public_distance_mismatch += 1;
        return None;
    }

    if replay.is_none() {
        for first_turn in &breakdown.slower_winning {
            let mut lines = match build_solution_lines(
                database,
                rules,
                options,
                root_snap,
                root_side,
                first_turn,
                cfg.max_exported_lines,
            ) {
                Ok(lines) => lines,
                Err(_) => {
                    audit.solution_unavailable += 1;
                    return None;
                }
            };
            if lines
                .iter()
                .any(|line| line.solver_move_count <= target_moves)
            {
                // Do not silently call an equal public-distance line "slower"
                // merely because the database's raw representation differs.
                audit.public_distance_mismatch += 1;
                return None;
            }
            solutions.append(&mut lines);
            if solutions.len() > cfg.max_exported_lines {
                audit.solution_line_cap += 1;
                return None;
            }
        }
    }
    solutions.sort_by_key(|solution| solution.solver_move_count);

    // Run the comparatively expensive human-search probe only after exact
    // database certification and compact-line filtering have accepted the
    // candidate. Most sampled roots fail those cheaper publication gates.
    let shortest_turns = breakdown
        .shortest_winning
        .iter()
        .map(|turn| turn.actions.clone())
        .collect::<Vec<_>>();
    let solve_depth =
        shallowest_solving_depth(rules, game, &root_snap, &shortest_turns, next_u64(rng));
    if let Some(depth) = solve_depth
        && depth < cfg.min_solve_depth
    {
        audit.shallow_probe_rejected += 1;
        return None;
    }

    let has_sacrifice = solutions
        .iter()
        .filter(|solution| solution.solver_move_count == target_moves)
        .any(|solution| solution.sacrifice);
    if !cfg.sacrifice_filter.accepts(has_sacrifice) {
        audit.sacrifice_rejected += 1;
        return None;
    }

    let fen = rules.export_fen(&root_state);
    let input = PuzzleBuildInput {
        fen: &fen,
        solver_side: root_side,
        is_moving_phase: root_state.phase() == MillPhase::Moving,
        solutions: &solutions,
        traits: PuzzleTraits {
            motif: cfg.required_motif,
            shortest_winning_count: breakdown.shortest_winning.len(),
            non_shortest_count: breakdown.non_shortest_count(),
            slower_winning_count: breakdown.slower_winning.len(),
            non_winning_count: breakdown.non_winning_count,
            tempting_mill_mistake: breakdown.tempting_mill_mistake,
            quiet_first_move: breakdown.quiet_first_move,
            solve_depth,
        },
        author: &cfg.author,
        rule_variant_id: cfg.rule_variant_id,
        generated_at,
        discovery_tag: match cfg.candidate_discovery.as_ref() {
            Some(CandidateDiscovery::SmtZ3 { .. }) => Some("discovery:smt-z3"),
            Some(CandidateDiscovery::HumanGameReplay { .. }) => Some("discovery:human-game"),
            Some(CandidateDiscovery::EngineBlunderCorpus { .. }) => {
                Some("discovery:engine-blunder-corpus")
            }
            None => None,
        },
        replay_provenance: replay,
        engine_blunder,
    };
    let info = puzzle_json::build_puzzle_info(&input);
    seen_roots.insert(dedup_key);
    audit.published += 1;
    Some(info)
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
