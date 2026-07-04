// SPDX-License-Identifier: AGPL-3.0-or-later
// Head-to-head strength match: the current-branch engine vs the master C++
// engine.  Both engines are driven as UCI subprocesses; `tgf-mill` is the
// authoritative referee (move application + outcome adjudication), so neither
// engine's internal rules can bias the result.
//
// Configuration matches the requested scenario: Skill 14, MoveTime 0 (fixed
// depth), Shuffling on (random tie-break -> varied games), MTD(f) (Algorithm
// 2), DeveloperMode off, DrawOnHumanExperience on, Perfect DB off.  Colours
// ALTERNATE every game (W, B, W, B, ...) for GAMES games per colour, and an
// aligned standings table (White / Black / total Win% and Score%, completed /
// remaining / progress) is printed from the current engine's perspective after
// every game.
//
// Ignored by default (needs both built engines).  Run with:
//   H2H_GAMES=20 cargo test -p tgf-cli --release --test head_to_head \
//     head_to_head_vs_master -- --ignored --nocapture
//
// Env vars:
//   H2H_CURRENT    path to the current-branch UCI engine (default tgf.exe)
//   H2H_CURRENT_ARGS extra args for current engine (default "uci")
//   H2H_CURRENT_ENV  env assignments for current engine, KEY=VALUE separated
//                    by whitespace (default empty)
//   H2H_MASTER     path to the master C++ UCI engine
//   H2H_MASTER_ARGS extra args for master/opponent engine (default empty)
//   H2H_MASTER_ENV   env assignments for master/opponent engine, KEY=VALUE
//                    separated by whitespace (default empty)
//   H2H_CURRENT_USE_PERFECT_DB  true/false, enable DB override for current
//   H2H_MASTER_USE_PERFECT_DB   true/false, enable DB override for opponent
//   H2H_CURRENT_PERFECT_DB_PATH DB path for current when enabled
//   H2H_MASTER_PERFECT_DB_PATH  DB path for opponent when enabled
//   H2H_CURRENT_PERFECT_DB_ORDERING auto|legacy|strict tie-break policy
//   H2H_MASTER_PERFECT_DB_ORDERING  (strict = convert wins by steps)
//   H2H_CURRENT_PATCH_PATH     error-patch file for current (Sanmill only)
//   H2H_MASTER_PATCH_PATH      error-patch file for opponent (Sanmill only)
//   H2H_CURRENT_PATCH_AVOID_TRAPS  true/false for current PatchAvoidTraps
//   H2H_MASTER_PATCH_AVOID_TRAPS   true/false for opponent PatchAvoidTraps
//   H2H_CURRENT_PATCH_MAKE_TRAPS   true/false for current PatchMakeTraps
//   H2H_MASTER_PATCH_MAKE_TRAPS    true/false for opponent PatchMakeTraps
//                  (with H2H_*_USE_PERFECT_DB the tie-break runs over the
//                  database's tied-best moves; without it, over the patch
//                  entry's own mask-proven value-preserving moves)
//   H2H_GAMES      games per color (default 20)
//   H2H_SKILL      skill level (default 14)
//   H2H_ENGINE_THREADS UCI Threads option for both engines (default 1)
//   H2H_MAX_PLIES  ply cap -> over-cap counted as a maneuvering draw (default 200)
//   H2H_N_MOVE_RULE regular no-capture draw threshold (default 100)
//   H2H_ENDGAME_N_MOVE_RULE endgame no-capture draw threshold (default 100)
//   H2H_OPENING_PLIES paired Perfect DB random opening plies (default 0)
//   H2H_OPENING_DB_PATH Perfect DB asset dir (default Flutter DB assets)
//   H2H_OPENING_SEED deterministic seed for paired Perfect DB openings
//   H2H_GO_CURRENT go command for the current engine (default "go depth 0")
//   H2H_GO_MASTER  go command for the master engine     (default "go")
//   H2H_MOVETIME   per-move thinking time in SECONDS via MoveTime setoption
//                  (range 0..=60; default 0 = fixed depth).  Sanmill-vs-
//                  Sanmill matches should prefer H2H_MOVETIME_MS instead.
//   H2H_MOVETIME_MS per-move thinking time in MILLISECONDS (Sanmill only,
//                  0..=60000; takes priority over H2H_MOVETIME).  Sent via
//                  the MoveTimeMs setoption; master C++ ignores it and falls
//                  back to the rounded MoveTime (seconds) value.
//                  Typical fast-match value: 200 (0.2 s per move).
//   H2H_MODE       "vs" (current vs master, default), "self-current" or
//                  "self-master": the named engine plays ITSELF (two
//                  independent instances), and the White / Black rows then show
//                  the game's first/second-player colour bias rather than a
//                  current-vs-master result.
//
// Feasibility note: at Skill 14 / Time 0 (pure depth 14) quiet middlegame
// positions can take ~a minute per move, so a drawn game can run for hours.
// For a statistically meaningful multi-game match, cap per-move time equally
// for BOTH engines (see H2H_MOVETIME / H2H_MOVETIME_MS above).  The MoveTime
// setoption drives a timed iterative-deepening search up to depth = skill.
// Note: `go movetime N` collapses to a depth-1 search; only the setoption
// path gives a correct timed search.  For Sanmill-vs-Sanmill matches use
// H2H_MOVETIME_MS (milliseconds); for matches against master C++ use
// H2H_MOVETIME (seconds) because master ignores MoveTimeMs.

use std::env;
use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};
use std::sync::mpsc::{self, RecvTimeoutError};
use std::thread;
use std::time::Duration;

use perfect_db::database::{Database, FileDatabaseProvider};
use tgf_core::{Action, ActionList, Game, GameRules, GameStateSnapshot, OutcomeKind, Workbench};
use tgf_mill::{MillActionKind, MillGame, MillPhase, MillRules, MillUciCodec, MillVariantOptions};

/// One UCI engine subprocess.
struct Engine {
    child: Child,
    stdin: ChildStdin,
    out: BufReader<ChildStdout>,
    go: String,
    name: String,
}

#[derive(Clone, Copy)]
struct EngineOptions {
    skill: u32,
    threads: u32,
    /// Per-move thinking time in milliseconds.  Both MoveTime (seconds,
    /// rounded down) and MoveTimeMs (milliseconds, Sanmill-only) are sent
    /// so master C++ engines fall back to the rounded second value while
    /// Sanmill engines use the full millisecond precision.
    move_time_ms: u32,
    n_move_rule: u32,
    endgame_n_move_rule: u32,
}

#[derive(Clone, Debug, Default)]
struct EnginePerfectDbOptions {
    enabled: bool,
    path: Option<PathBuf>,
    cache_sectors: Option<usize>,
    /// `auto` / `legacy` / `strict`; sent as the Sanmill-only
    /// `PerfectDatabaseOrdering` setoption when set.  `strict` makes the
    /// DB opponent actually convert won positions (prefer faster wins)
    /// instead of shuffling among equally-"winning" moves until the
    /// n-move rule adjudicates a draw.
    ordering: Option<String>,
}

#[derive(Clone, Debug, Default)]
struct EnginePatchOptions {
    path: Option<PathBuf>,
    avoid_traps: bool,
    make_traps: bool,
}

#[derive(Clone)]
struct EngineSpawnConfig<'a> {
    program: &'a str,
    args: &'a [String],
    env_vars: &'a [(String, String)],
    go: &'a str,
    name: &'a str,
    options: &'a EngineOptions,
    perfect_db: &'a EnginePerfectDbOptions,
    patch: &'a EnginePatchOptions,
}

impl Engine {
    fn spawn(config: EngineSpawnConfig<'_>) -> Engine {
        let EngineSpawnConfig {
            program,
            args,
            env_vars,
            go,
            name,
            options,
            perfect_db,
            patch,
        } = config;
        let mut command = Command::new(program);
        command
            .args(args)
            .envs(env_vars.iter().map(|(key, value)| (key, value)))
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null());
        let mut child = command
            .spawn()
            .unwrap_or_else(|e| panic!("failed to spawn {name} engine `{program}`: {e}"));
        let stdin = child.stdin.take().expect("engine stdin");
        let out = BufReader::new(child.stdout.take().expect("engine stdout"));
        let mut e = Engine {
            child,
            stdin,
            out,
            go: go.to_string(),
            name: name.to_string(),
        };
        e.cmd("uci");
        assert!(e.wait("uciok").is_some(), "{name}: no uciok");
        for (k, v) in [
            ("Threads", options.threads.to_string()),
            ("SkillLevel", options.skill.to_string()),
            ("DeveloperMode", "false".to_string()),
            ("DrawOnHumanExperience", "true".to_string()),
            ("Shuffling", "true".to_string()),
            ("Algorithm", "2".to_string()),
            // Send the legacy seconds value first so master C++ engines
            // (which do not recognise MoveTimeMs) get the rounded fallback.
            ("MoveTime", (options.move_time_ms / 1000).to_string()),
            // Send the millisecond value second; Sanmill engines override
            // the seconds value with full sub-second precision.  Master C++
            // engines silently ignore unknown setoption names.
            ("MoveTimeMs", options.move_time_ms.to_string()),
            ("NMoveRule", options.n_move_rule.to_string()),
            ("EndgameNMoveRule", options.endgame_n_move_rule.to_string()),
        ] {
            e.cmd(&format!("setoption name {k} value {v}"));
        }
        if let Some(path) = perfect_db.path.as_ref() {
            e.cmd(&format!(
                "setoption name PerfectDatabasePath value {}",
                path.display()
            ));
        }
        if let Some(cache) = perfect_db.cache_sectors {
            e.cmd(&format!(
                "setoption name PerfectDatabaseCacheSectors value {cache}"
            ));
        }
        if let Some(ordering) = perfect_db.ordering.as_ref() {
            e.cmd(&format!(
                "setoption name PerfectDatabaseOrdering value {ordering}"
            ));
        }
        e.cmd(&format!(
            "setoption name UsePerfectDatabase value {}",
            if perfect_db.enabled { "true" } else { "false" }
        ));
        if let Some(path) = patch.path.as_ref() {
            e.cmd(&format!(
                "setoption name PatchPath value {}",
                path.display()
            ));
        }
        e.cmd(&format!(
            "setoption name PatchAvoidTraps value {}",
            if patch.avoid_traps { "true" } else { "false" }
        ));
        e.cmd(&format!(
            "setoption name PatchMakeTraps value {}",
            if patch.make_traps { "true" } else { "false" }
        ));
        e.cmd("isready");
        assert!(e.wait("readyok").is_some(), "{name}: no readyok");
        e
    }

    fn cmd(&mut self, s: &str) {
        writeln!(self.stdin, "{s}").expect("write to engine");
        self.stdin.flush().expect("flush engine");
    }

    /// Read engine output until a line contains `token`; None on EOF.
    fn wait(&mut self, token: &str) -> Option<String> {
        let mut line = String::new();
        loop {
            line.clear();
            match self.out.read_line(&mut line) {
                Ok(0) | Err(_) => return None,
                Ok(_) => {
                    if line.contains(token) {
                        return Some(line.trim().to_string());
                    }
                }
            }
        }
    }

    fn new_game(&mut self) {
        self.cmd("ucinewgame");
    }

    /// Ask the engine for its best move given the move history (UCI tokens).
    fn best_move(&mut self, moves: &[String]) -> Option<String> {
        let pos = if moves.is_empty() {
            "position startpos".to_string()
        } else {
            format!("position startpos moves {}", moves.join(" "))
        };
        self.cmd(&pos);
        let go = self.go.clone();
        self.cmd(&go);
        let line = self.wait("bestmove")?;
        let toks: Vec<&str> = line.split_whitespace().collect();
        let idx = toks.iter().position(|t| *t == "bestmove")?;
        let mv = toks.get(idx + 1)?.to_string();
        if matches!(mv.as_str(), "(none)" | "none" | "0000") {
            None
        } else {
            Some(mv)
        }
    }
}

impl Drop for Engine {
    fn drop(&mut self) {
        let _ = writeln!(self.stdin, "quit");
        let _ = self.stdin.flush();
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

/// Outcome of a game by board colour (independent of which engine played it).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum GameResult {
    WhiteWin,
    BlackWin,
    Draw,
    Unfinished,
}

/// Match-level repetition adjudicator. `GameStateSnapshot` persists only a
/// compact key window for FRB compatibility, while the master console engine
/// rebuilds a full 256-entry `posKeyHistory` from the UCI move list.
#[derive(Default)]
struct RepetitionReferee {
    key_history: Vec<u64>,
}

impl RepetitionReferee {
    const MAX_KEYS: usize = 256;

    fn is_root_threefold_draw(&self, snap: &GameStateSnapshot) -> bool {
        if snap.phase_tag != MillPhase::Moving as i16 {
            return false;
        }
        let key = snap.zobrist_key;
        debug_assert_ne!(key, 0, "Mill snapshots must carry a non-zero key");
        self.key_history
            .iter()
            .filter(|stored| **stored == key)
            .count()
            >= 3
    }

    fn record_after_apply(&mut self, action: Action, snap: &GameStateSnapshot) {
        match action.kind_tag {
            x if x == MillActionKind::Move as i16 => {
                let key = snap.zobrist_key;
                debug_assert_ne!(key, 0, "Mill snapshots must carry a non-zero key");
                if self.key_history.len() >= Self::MAX_KEYS {
                    self.key_history.remove(0);
                }
                debug_assert!(self.key_history.len() < Self::MAX_KEYS);
                self.key_history.push(key);
            }
            x if x == MillActionKind::Place as i16 || x == MillActionKind::Remove as i16 => {
                self.key_history.clear();
            }
            other => panic!("unknown Mill action kind_tag {other}"),
        }
    }
}

fn action(kind: MillActionKind) -> Action {
    Action {
        kind_tag: kind as i16,
        from_node: -1,
        to_node: 0,
        aux: -1,
        payload_bits: 0,
    }
}

fn moving_snapshot_with_key(key: u64) -> GameStateSnapshot {
    GameStateSnapshot {
        phase_tag: MillPhase::Moving as i16,
        zobrist_key: key,
        ..GameStateSnapshot::default()
    }
}

fn splitmix64(mut value: u64) -> u64 {
    value = value.wrapping_add(0x9E37_79B9_7F4A_7C15);
    let mut z = value;
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    z ^ (z >> 31)
}

fn paired_opening_seed(base_seed: u64, game_index: usize) -> u64 {
    let pair_index = game_index / 2;
    splitmix64(base_seed ^ (pair_index as u64).wrapping_mul(0xD1B5_4A32_D192_ED03))
}

fn workspace_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .canonicalize()
        .unwrap_or_else(|_| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../.."))
}

fn workspace_asset_path(relative: &str) -> PathBuf {
    canonicalize_path(workspace_root().join(relative))
}

fn canonicalize_path(path: PathBuf) -> PathBuf {
    path.canonicalize().unwrap_or(path)
}

/// Resolve a possibly-relative engine executable path.  `cargo test` runs
/// integration tests with the crate directory as cwd, so `target/release/tgf`
/// only exists relative to the workspace root, not `crates/tgf-cli`.
fn resolve_engine_program(path: &str) -> String {
    let path = path.trim();
    let candidate = PathBuf::from(path);
    if candidate.is_absolute() {
        return path.to_string();
    }
    for base in [std::env::current_dir().ok(), Some(workspace_root())]
        .into_iter()
        .flatten()
    {
        let joined = base.join(&candidate);
        if joined.is_file() {
            return joined.to_string_lossy().into_owned();
        }
    }
    workspace_root()
        .join(&candidate)
        .to_string_lossy()
        .into_owned()
}

fn is_tgf_program(path: &str) -> bool {
    PathBuf::from(path)
        .file_stem()
        .and_then(|stem| stem.to_str())
        .is_some_and(|stem| stem.eq_ignore_ascii_case("tgf"))
}

fn default_perfect_db_path() -> PathBuf {
    workspace_asset_path("src/ui/flutter_app/assets/databases")
}

fn default_patch_path() -> PathBuf {
    workspace_asset_path("src/ui/flutter_app/assets/patches/std.mill_patch")
}

fn patch_options_from_env(path_var: &str, avoid_var: &str, make_var: &str) -> EnginePatchOptions {
    let avoid_traps = env_bool(avoid_var, false);
    let make_traps = env_bool(make_var, false);
    let path = env_path(path_var).or_else(|| {
        if avoid_traps || make_traps {
            Some(default_patch_path())
        } else {
            None
        }
    });
    EnginePatchOptions {
        path,
        avoid_traps,
        make_traps,
    }
}

type OpeningDatabase = Database<FileDatabaseProvider>;

struct PerfectOpening {
    plies: usize,
    seed: u64,
    db_path: Option<PathBuf>,
    db: Option<OpeningDatabase>,
}

impl PerfectOpening {
    fn new(plies: usize, seed: u64, db_path: Option<PathBuf>) -> Self {
        let db_path = if plies == 0 {
            db_path
        } else {
            Some(db_path.unwrap_or_else(default_perfect_db_path))
        };
        let db = db_path.as_ref().filter(|_| plies > 0).map(|path| {
            assert!(
                path.is_dir(),
                "Perfect DB opening path must be an existing directory: {}",
                path.display()
            );
            Database::open(FileDatabaseProvider::new(path.clone())).unwrap_or_else(|e| {
                panic!(
                    "failed to open Perfect DB opening path `{}`: {e}",
                    path.display()
                )
            })
        });
        Self {
            plies,
            seed,
            db_path,
            db,
        }
    }

    fn describe(&self) -> String {
        match (self.plies, self.db_path.as_ref()) {
            (0, _) => "opening_plies=0".to_string(),
            (_, Some(path)) => format!(
                "opening_plies={} opening_db=`{}`",
                self.plies,
                path.display()
            ),
            _ => unreachable!("positive Perfect DB opening plies require a database path"),
        }
    }
}

struct Referee {
    rules: MillRules,
    game: MillGame,
    options: MillVariantOptions,
    opening: PerfectOpening,
}

impl Referee {
    fn new(options: MillVariantOptions, opening: PerfectOpening) -> Self {
        Self {
            rules: MillRules::new(options.clone()),
            game: MillGame::new(options.clone()),
            options,
            opening,
        }
    }

    fn legal_action_for_token(&self, snap: &GameStateSnapshot, token: &str) -> Option<Action> {
        let mut legal = ActionList::<256>::new();
        self.rules.legal_actions(snap, &mut legal);
        legal
            .as_slice()
            .iter()
            .copied()
            .find(|action| MillUciCodec::encode_action(*action) == token)
    }

    fn append_perfect_opening_prefix(
        &mut self,
        snap: &mut GameStateSnapshot,
        moves: &mut Vec<String>,
        repetition: &mut RepetitionReferee,
        game_index: usize,
    ) -> Vec<String> {
        let opening_plies = self.opening.plies;
        if opening_plies == 0 {
            return Vec::new();
        }

        let mut seed = paired_opening_seed(self.opening.seed, game_index);
        let mut opening_moves = Vec::with_capacity(opening_plies);

        for _ in 0..opening_plies {
            if !matches!(self.rules.outcome(snap).kind, OutcomeKind::Ongoing)
                || repetition.is_root_threefold_draw(snap)
            {
                break;
            }

            let db = self
                .opening
                .db
                .as_mut()
                .expect("positive Perfect DB opening plies require an open database");
            let mut choices = perfect_db::best_move_choices_with_ordering(
                db,
                &self.rules,
                snap,
                &self.options,
                perfect_db::PerfectMoveOrdering::StrictSteps,
            )
            .unwrap_or_else(|e| panic!("Perfect DB opening lookup failed: {e}"))
            .unwrap_or_else(|| {
                panic!("Perfect DB has no opening move after `{}`", moves.join(" "))
            });
            assert!(
                !choices.is_empty(),
                "Perfect DB opening lookup returned an empty choice list"
            );

            // Match master PerfectPlayer's Algorithm=Random branch: first keep
            // only strict best database moves, then choose a random tie.
            choices.sort_by(|a, b| a.token.cmp(&b.token));
            seed = splitmix64(seed);
            let choice = choices[(seed as usize) % choices.len()].clone();
            let action = self
                .legal_action_for_token(snap, &choice.token)
                .unwrap_or_else(|| {
                    panic!(
                        "Perfect DB returned illegal opening token `{}` after `{}`",
                        choice.token,
                        moves.join(" ")
                    )
                });
            *snap = self.rules.apply(snap, action);
            repetition.record_after_apply(action, snap);
            moves.push(choice.token.clone());
            opening_moves.push(choice.token);
        }

        opening_moves
    }

    /// Play one full game between the `white` and `black` engines; returns the
    /// outcome by board colour (`tgf-mill` is the referee).
    fn play_game(
        &mut self,
        white: &mut Engine,
        black: &mut Engine,
        max_plies: usize,
        game_index: usize,
    ) -> (GameResult, usize, Vec<String>, Vec<String>) {
        let mut snap = self.rules.initial_state(&[]);
        let mut moves: Vec<String> = Vec::new();
        let mut repetition = RepetitionReferee::default();
        white.new_game();
        black.new_game();
        let opening_moves =
            self.append_perfect_opening_prefix(&mut snap, &mut moves, &mut repetition, game_index);

        for ply in moves.len()..max_plies {
            match self.rules.outcome(&snap).kind {
                OutcomeKind::Ongoing => {}
                OutcomeKind::Win(0) => return (GameResult::WhiteWin, ply, opening_moves, moves),
                OutcomeKind::Win(1) => return (GameResult::BlackWin, ply, opening_moves, moves),
                OutcomeKind::Draw => return (GameResult::Draw, ply, opening_moves, moves),
                _ => return (GameResult::Unfinished, ply, opening_moves, moves),
            }
            if repetition.is_root_threefold_draw(&snap) {
                return (GameResult::Draw, ply, opening_moves, moves);
            }

            let stm = self.game.build_workbench(&snap).side_to_move();
            let engine = if stm == 0 { &mut *white } else { &mut *black };
            let Some(mv) = engine.best_move(&moves) else {
                eprintln!("  ! {} returned no move at ply {ply}", engine.name);
                return (GameResult::Unfinished, ply, opening_moves, moves);
            };
            let Some(action) = MillUciCodec::decode_action(&snap, &mv) else {
                eprintln!(
                    "  ! undecodable move `{mv}` from {} at ply {ply}",
                    engine.name
                );
                return (GameResult::Unfinished, ply, opening_moves, moves);
            };
            snap = self.rules.apply(&snap, action);
            repetition.record_after_apply(action, &snap);
            moves.push(mv);
        }
        // Ply cap reached: both sides maneuvering -> score as a draw.
        (GameResult::Draw, max_plies, opening_moves, moves)
    }
}

#[test]
fn repetition_referee_preserves_long_reversible_history() {
    let mut referee = RepetitionReferee::default();
    let repeated = moving_snapshot_with_key(42);

    referee.record_after_apply(action(MillActionKind::Move), &repeated);
    for key in 1_000..1_030 {
        referee.record_after_apply(action(MillActionKind::Move), &moving_snapshot_with_key(key));
    }
    referee.record_after_apply(action(MillActionKind::Move), &repeated);
    for key in 2_000..2_030 {
        referee.record_after_apply(action(MillActionKind::Move), &moving_snapshot_with_key(key));
    }
    referee.record_after_apply(action(MillActionKind::Move), &repeated);

    assert!(referee.key_history.len() > 24);
    assert!(referee.is_root_threefold_draw(&repeated));

    referee.record_after_apply(action(MillActionKind::Remove), &repeated);
    assert!(!referee.is_root_threefold_draw(&repeated));
}

/// Percentage of `num` out of `den` (0 when `den == 0`).
fn pct(num: f64, den: usize) -> f64 {
    if den == 0 {
        0.0
    } else {
        100.0 * num / den as f64
    }
}

/// Two-sided normal critical value for 99.9% confidence (alpha = 0.001).
const Z_99_9: f64 = 3.290_526_731_491_925;
const SCORE_SUPERIORITY_THRESHOLD: f64 = 0.50;
const INV_SQRT_2PI: f64 = 0.398_942_280_401_432_7;

/// Observed Score proportion `(W + 0.5*D) / decided` and the decided-game count.
fn score_proportion(s: &[usize; 4]) -> (f64, usize) {
    let decided = s[0] + s[1] + s[2];
    if decided == 0 {
        return (0.0, 0);
    }
    let score = s[0] as f64 + 0.5 * s[2] as f64;
    (score / decided as f64, decided)
}

/// Wald margin of error for a proportion at 99.9% confidence, in percentage
/// points (e.g. 2.1 means ±2.1%).
fn margin_of_error_pct(p: f64, n: usize) -> f64 {
    if n == 0 {
        return 0.0;
    }
    100.0 * Z_99_9 * (p * (1.0 - p) / n as f64).sqrt()
}

/// Standard normal CDF approximation (Abramowitz-Stegun 26.2.17).
fn standard_normal_cdf(z: f64) -> f64 {
    let x = z.abs();
    let t = 1.0 / (1.0 + 0.231_641_9 * x);
    let polynomial =
        ((((1.330_274_429 * t - 1.821_255_978) * t + 1.781_477_937) * t - 0.356_563_782) * t
            + 0.319_381_530)
            * t;
    let tail = INV_SQRT_2PI * (-0.5 * x * x).exp() * polynomial;
    if z >= 0.0 { 1.0 - tail } else { tail }
}

/// Probability that the true total Score% is above 50%, using the same
/// normal approximation as the sampling-error footer.
fn superiority_probability(p: f64, n: usize) -> Option<f64> {
    if n == 0 {
        return None;
    }
    let se = (p * (1.0 - p) / n as f64).sqrt();
    if se == 0.0 {
        return Some(if p > SCORE_SUPERIORITY_THRESHOLD {
            1.0
        } else if p < SCORE_SUPERIORITY_THRESHOLD {
            0.0
        } else {
            0.5
        });
    }
    let z = (SCORE_SUPERIORITY_THRESHOLD - p) / se;
    Some(1.0 - standard_normal_cdf(z))
}

fn format_superiority_probability(s: &[usize; 4]) -> String {
    let (p, n) = score_proportion(s);
    superiority_probability(p, n)
        .map(|probability| {
            format!(
                "{:.2}% (Total true Score% > 50.0%, normal approximation, n={n})",
                probability * 100.0
            )
        })
        .unwrap_or_else(|| "N/A".to_string())
}

/// Format `Score% ± margin` with sample size for one standings row.
fn format_score_with_margin(s: &[usize; 4]) -> String {
    let (p, n) = score_proportion(s);
    if n == 0 {
        return "N/A".to_string();
    }
    let score_pct = pct(p * n as f64, n);
    let me = margin_of_error_pct(p, n);
    format!("{score_pct:.1}% ± {me:.1}% (n={n})")
}

/// Row/separator template for the live standings table.
const TABLE_SEP: &str =
    "+--------+-------+------+------+------+--------+--------+--------+--------+";

/// Print one standings row for a side.  `s` is its `[Win, Loss, Draw,
/// Unfinished]` tally; the row shows decided games (W+D+L), the Win/Draw/Loss
/// split, and the Win% / Draw% / Loss% / Score% rates, where
/// Score% = `(W + 0.5*D) / decided`.
fn standings_row(side: &str, s: &[usize; 4]) {
    let (win, loss, draw) = (s[0], s[1], s[2]);
    let decided = win + loss + draw;
    let score = win as f64 + 0.5 * draw as f64;
    let rate = |n: f64| format!("{:.1}%", pct(n, decided));
    eprintln!(
        "| {:<6} | {:>5} | {:>4} | {:>4} | {:>4} | {:>6} | {:>6} | {:>6} | {:>6} |",
        side,
        decided,
        win,
        draw,
        loss,
        rate(win as f64),
        rate(draw as f64),
        rate(loss as f64),
        rate(score),
    );
}

/// Print the live standings table (White / Black / total rows) plus a footer
/// noting the Skill Level and Thinking Time and the completed / remaining /
/// progress counts.
fn print_standings(
    done: usize,
    total: usize,
    white: &[usize; 4],
    black: &[usize; 4],
    skill: u32,
    move_time_ms: u32,
) {
    let tot = [
        white[0] + black[0],
        white[1] + black[1],
        white[2] + black[2],
        white[3] + black[3],
    ];
    eprintln!("{TABLE_SEP}");
    eprintln!(
        "| {:<6} | {:>5} | {:>4} | {:>4} | {:>4} | {:>6} | {:>6} | {:>6} | {:>6} |",
        "Side", "Games", "Win", "Draw", "Loss", "Win%", "Draw%", "Loss%", "Score%"
    );
    eprintln!("{TABLE_SEP}");
    standings_row("White", white);
    standings_row("Black", black);
    standings_row("TOTAL", &tot);
    eprintln!("{TABLE_SEP}");
    let time_display = if move_time_ms == 0 {
        " (fixed depth)".to_string()
    } else if move_time_ms.is_multiple_of(1000) {
        format!(" ({}s)", move_time_ms / 1000)
    } else {
        format!(" ({}ms)", move_time_ms)
    };
    eprintln!("Skill Level: {skill}   Thinking Time: {move_time_ms}ms{time_display}");
    eprintln!(
        "Completed: {done}/{total} ({:.1}%)   Remaining: {}",
        pct(done as f64, total),
        total - done
    );
    eprintln!("99.9% confidence sampling error (Score%):");
    eprintln!("  White: {}", format_score_with_margin(white));
    eprintln!("  Black: {}", format_score_with_margin(black));
    eprintln!("  Total: {}", format_score_with_margin(&tot));
    eprintln!(
        "  P(true Score% > 50.0%): {}",
        format_superiority_probability(&tot)
    );
    if tot[3] > 0 {
        eprintln!(
            "(note: {} game(s) unfinished/aborted, excluded from rates)",
            tot[3]
        );
    }
}

#[test]
fn superiority_probability_matches_normal_approximation_example() {
    let probability = superiority_probability(0.494, 10_000)
        .expect("positive sample count should produce a probability");

    assert!(
        (probability - 0.115).abs() < 0.001,
        "expected about 11.5%, got {:.4}%",
        probability * 100.0
    );
}

#[test]
fn h2h_superiority_probability_uses_total_score() {
    let total = [2266, 2386, 5348, 0];
    let formatted = format_superiority_probability(&total);

    assert!(formatted.starts_with("11.5"));
    assert!(formatted.contains("n=10000"));
}

#[test]
fn resolve_engine_program_finds_workspace_target_from_relative_path() {
    let root = workspace_root();
    let relative = "target/release/tgf.exe";
    let resolved = resolve_engine_program(relative);
    let resolved_path = PathBuf::from(&resolved);
    assert!(
        resolved_path.is_file(),
        "expected `{resolved}` to exist (workspace root = {})",
        root.display()
    );
    assert!(
        resolved_path.starts_with(&root),
        "resolved engine should live under the workspace root"
    );
}

fn engine_args_from_env(name: &str, default: &str) -> Vec<String> {
    env::var(name)
        .unwrap_or_else(|_| default.to_string())
        .split_whitespace()
        .map(str::to_string)
        .collect()
}

fn engine_env_from_env(name: &str) -> Vec<(String, String)> {
    env::var(name)
        .unwrap_or_default()
        .split_whitespace()
        .filter(|assignment| !assignment.is_empty())
        .map(|assignment| {
            let (key, value) = assignment
                .split_once('=')
                .unwrap_or_else(|| panic!("{name} item must be KEY=VALUE, got `{assignment}`"));
            assert!(
                !key.is_empty(),
                "{name} item has an empty key: `{assignment}`"
            );
            (key.to_string(), value.to_string())
        })
        .collect()
}

fn env_usize(name: &str, default: usize) -> usize {
    env::var(name)
        .map(|s| {
            s.parse::<usize>()
                .unwrap_or_else(|e| panic!("{name} must be a usize, got `{s}`: {e}"))
        })
        .unwrap_or(default)
}

fn env_u32(name: &str, default: u32) -> u32 {
    env::var(name)
        .map(|s| {
            s.parse::<u32>()
                .unwrap_or_else(|e| panic!("{name} must be a u32, got `{s}`: {e}"))
        })
        .unwrap_or(default)
}

fn env_bool(name: &str, default: bool) -> bool {
    env::var(name)
        .map(|s| match s.trim().to_ascii_lowercase().as_str() {
            "" => default,
            "1" | "true" | "on" | "yes" => true,
            "0" | "false" | "off" | "no" => false,
            _ => panic!("{name} must be a boolean, got `{s}`"),
        })
        .unwrap_or(default)
}

fn parse_u64_env_value(name: &str, value: &str) -> u64 {
    let trimmed = value.trim();
    if let Some(hex) = trimmed
        .strip_prefix("0x")
        .or_else(|| trimmed.strip_prefix("0X"))
    {
        u64::from_str_radix(hex, 16)
            .unwrap_or_else(|e| panic!("{name} must be a u64, got `{value}`: {e}"))
    } else {
        trimmed
            .parse::<u64>()
            .unwrap_or_else(|e| panic!("{name} must be a u64, got `{value}`: {e}"))
    }
}

fn env_u64(name: &str, default: u64) -> u64 {
    env::var(name)
        .map(|s| parse_u64_env_value(name, &s))
        .unwrap_or(default)
}

fn env_path(name: &str) -> Option<PathBuf> {
    env::var(name)
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .map(|s| {
            let path = PathBuf::from(&s);
            if path.is_absolute() {
                canonicalize_path(path)
            } else {
                canonicalize_path(workspace_root().join(path))
            }
        })
}

fn opening_desc(opening_moves: &[String]) -> String {
    if opening_moves.is_empty() {
        String::new()
    } else {
        format!(" opening=[{}]", opening_moves.join(" "))
    }
}

#[derive(Clone)]
struct MatchConfig {
    current: String,
    current_args: Vec<String>,
    current_env: Vec<(String, String)>,
    master: String,
    master_args: Vec<String>,
    master_env: Vec<(String, String)>,
    go_current: String,
    go_master: String,
    engine_options: EngineOptions,
    current_perfect_db: EnginePerfectDbOptions,
    master_perfect_db: EnginePerfectDbOptions,
    current_patch: EnginePatchOptions,
    master_patch: EnginePatchOptions,
    variant_options: MillVariantOptions,
    total_games: usize,
    jobs: usize,
    max_plies: usize,
    skill: u32,
    move_time_ms: u32,
    opening_plies: usize,
    opening_seed: u64,
    opening_db_path: Option<PathBuf>,
}

#[derive(Debug)]
struct GameReport {
    worker_id: usize,
    game_index: usize,
    result: GameResult,
    plies: usize,
    opening_moves: Vec<String>,
    /// Full move list (opening prefix included), for joining engine-side
    /// patchtrap traces (H2H_GAME_LOG consumers).
    moves: Vec<String>,
    current_white: Option<bool>,
}

fn build_referee(config: &MatchConfig) -> Referee {
    Referee::new(
        config.variant_options.clone(),
        PerfectOpening::new(
            config.opening_plies,
            config.opening_seed,
            config.opening_db_path.clone(),
        ),
    )
}

fn jobs_for_total(total: usize) -> usize {
    let jobs = env_usize("H2H_JOBS", 1).max(1);
    jobs.min(total.max(1))
}

fn progress_interval() -> Duration {
    Duration::from_secs(env_u64("H2H_PROGRESS_SECS", 30).max(1))
}

fn apply_self_report(report: &GameReport, white: &mut [usize; 4], black: &mut [usize; 4]) {
    match report.result {
        GameResult::WhiteWin => {
            white[0] += 1;
            black[1] += 1;
        }
        GameResult::BlackWin => {
            white[1] += 1;
            black[0] += 1;
        }
        GameResult::Draw => {
            white[2] += 1;
            black[2] += 1;
        }
        GameResult::Unfinished => {
            white[3] += 1;
            black[3] += 1;
        }
    }
}

fn apply_vs_report(report: &GameReport, white: &mut [usize; 4], black: &mut [usize; 4]) -> usize {
    let current_white = report
        .current_white
        .expect("vs report must identify current engine colour");
    let idx = match (report.result, current_white) {
        (GameResult::WhiteWin, true) | (GameResult::BlackWin, false) => 0,
        (GameResult::BlackWin, true) | (GameResult::WhiteWin, false) => 1,
        (GameResult::Draw, _) => 2,
        (GameResult::Unfinished, _) => 3,
    };
    if current_white {
        white[idx] += 1;
    } else {
        black[idx] += 1;
    }
    idx
}

fn worker_game_indices(worker_id: usize, total: usize, jobs: usize) -> impl Iterator<Item = usize> {
    (worker_id..total).step_by(jobs)
}

fn run_self_play_parallel(config: MatchConfig, is_master: bool, label: &str) {
    let total = config.total_games;
    let jobs = config.jobs;
    let (tx, rx) = mpsc::channel::<GameReport>();
    let mut handles = Vec::with_capacity(jobs);

    for worker_id in 0..jobs {
        let tx = tx.clone();
        let config = config.clone();
        handles.push(thread::spawn(move || {
            let mut referee = build_referee(&config);
            let (mut ew, mut eb) = if is_master {
                (
                    Engine::spawn(EngineSpawnConfig {
                        program: &config.master,
                        args: &config.master_args,
                        env_vars: &config.master_env,
                        go: &config.go_master,
                        name: &format!("worker-{worker_id}-white"),
                        options: &config.engine_options,
                        perfect_db: &config.master_perfect_db,
                        patch: &config.master_patch,
                    }),
                    Engine::spawn(EngineSpawnConfig {
                        program: &config.master,
                        args: &config.master_args,
                        env_vars: &config.master_env,
                        go: &config.go_master,
                        name: &format!("worker-{worker_id}-black"),
                        options: &config.engine_options,
                        perfect_db: &config.master_perfect_db,
                        patch: &config.master_patch,
                    }),
                )
            } else {
                (
                    Engine::spawn(EngineSpawnConfig {
                        program: &config.current,
                        args: &config.current_args,
                        env_vars: &config.current_env,
                        go: &config.go_current,
                        name: &format!("worker-{worker_id}-white"),
                        options: &config.engine_options,
                        perfect_db: &config.current_perfect_db,
                        patch: &config.current_patch,
                    }),
                    Engine::spawn(EngineSpawnConfig {
                        program: &config.current,
                        args: &config.current_args,
                        env_vars: &config.current_env,
                        go: &config.go_current,
                        name: &format!("worker-{worker_id}-black"),
                        options: &config.engine_options,
                        perfect_db: &config.current_perfect_db,
                        patch: &config.current_patch,
                    }),
                )
            };

            for game_index in worker_game_indices(worker_id, config.total_games, config.jobs) {
                let (result, plies, opening_moves, moves) =
                    referee.play_game(&mut ew, &mut eb, config.max_plies, game_index);
                tx.send(GameReport {
                    worker_id,
                    game_index,
                    result,
                    plies,
                    opening_moves,
                    moves,
                    current_white: None,
                })
                .expect("main H2H collector should stay alive");
            }
        }));
    }
    drop(tx);

    let mut white = [0usize; 4];
    let mut black = [0usize; 4];
    let mut done = 0usize;
    let interval = progress_interval();
    while done < total {
        match rx.recv_timeout(interval) {
            Ok(report) => {
                done += 1;
                apply_self_report(&report, &mut white, &mut black);
                eprintln!();
                eprintln!(
                    "Game {}/{total}: White vs Black -> {:?} ({} plies){}  [worker {} game-index {}]",
                    done,
                    report.result,
                    report.plies,
                    opening_desc(&report.opening_moves),
                    report.worker_id,
                    report.game_index + 1
                );
                print_standings(
                    done,
                    total,
                    &white,
                    &black,
                    config.skill,
                    config.move_time_ms,
                );
            }
            Err(RecvTimeoutError::Timeout) => {
                eprintln!();
                eprintln!(
                    "Progress heartbeat: completed {done}/{total}; jobs={jobs}; waiting for workers..."
                );
                print_standings(
                    done,
                    total,
                    &white,
                    &black,
                    config.skill,
                    config.move_time_ms,
                );
            }
            Err(RecvTimeoutError::Disconnected) => break,
        }
    }

    for handle in handles {
        handle.join().expect("H2H worker should not panic");
    }
    assert_eq!(done, total, "all scheduled self-play games must finish");

    let (ww, bw) = (white[0], black[0]);
    let net = ww as i64 - bw as i64;
    let verdict = if net > 0 {
        "White is favoured"
    } else if net < 0 {
        "Black is favoured"
    } else {
        "colours are even"
    };
    eprintln!();
    eprintln!(
        "FINAL: {label} self-play  White {ww} wins vs Black {bw} wins  net {net:+}  =>  {verdict}"
    );
}

fn run_vs_parallel(config: MatchConfig) {
    let total = config.total_games;
    let jobs = config.jobs;
    let (tx, rx) = mpsc::channel::<GameReport>();
    let mut handles = Vec::with_capacity(jobs);

    for worker_id in 0..jobs {
        let tx = tx.clone();
        let config = config.clone();
        handles.push(thread::spawn(move || {
            let mut referee = build_referee(&config);
            let mut cur = Engine::spawn(EngineSpawnConfig {
                program: &config.current,
                args: &config.current_args,
                env_vars: &config.current_env,
                go: &config.go_current,
                name: &format!("worker-{worker_id}-current"),
                options: &config.engine_options,
                perfect_db: &config.current_perfect_db,
                patch: &config.current_patch,
            });
            let mut mas = Engine::spawn(EngineSpawnConfig {
                program: &config.master,
                args: &config.master_args,
                env_vars: &config.master_env,
                go: &config.go_master,
                name: &format!("worker-{worker_id}-master"),
                options: &config.engine_options,
                perfect_db: &config.master_perfect_db,
                patch: &config.master_patch,
            });

            for game_index in worker_game_indices(worker_id, config.total_games, config.jobs) {
                let current_white = game_index % 2 == 0;
                let (result, plies, opening_moves, moves) = if current_white {
                    referee.play_game(&mut cur, &mut mas, config.max_plies, game_index)
                } else {
                    referee.play_game(&mut mas, &mut cur, config.max_plies, game_index)
                };
                tx.send(GameReport {
                    worker_id,
                    game_index,
                    result,
                    plies,
                    opening_moves,
                    moves,
                    current_white: Some(current_white),
                })
                .expect("main H2H collector should stay alive");
            }
        }));
    }
    drop(tx);

    let mut white = [0usize; 4];
    let mut black = [0usize; 4];
    let mut done = 0usize;
    // H2H_GAME_LOG: per-game JSONL for pair-level (paired-opening) score
    // analysis and for joining engine-side patchtrap traces against final
    // results. One row per game: game_index (pairs are (2k, 2k+1) sharing
    // one opening prefix with colours swapped), current colour, result
    // from current's perspective, plies, and the opening prefix itself.
    let mut game_log = std::env::var("H2H_GAME_LOG")
        .ok()
        .filter(|path| !path.trim().is_empty())
        .map(|path| {
            std::io::BufWriter::new(
                std::fs::File::create(&path)
                    .unwrap_or_else(|e| panic!("cannot create H2H_GAME_LOG {path}: {e}")),
            )
        });
    let interval = progress_interval();
    while done < total {
        match rx.recv_timeout(interval) {
            Ok(report) => {
                done += 1;
                let idx = apply_vs_report(&report, &mut white, &mut black);
                let current_white = report
                    .current_white
                    .expect("vs report must identify current engine colour");
                if let Some(log) = game_log.as_mut() {
                    let row = serde_json::json!({
                        "game_index": report.game_index,
                        "current_white": current_white,
                        "result": match idx {
                            0 => "win",
                            1 => "loss",
                            2 => "draw",
                            _ => "unfinished",
                        },
                        "plies": report.plies,
                        "opening_moves": report.opening_moves,
                        "moves": report.moves,
                    });
                    writeln!(log, "{row}").expect("H2H_GAME_LOG write failed");
                    log.flush().ok();
                }
                eprintln!();
                eprintln!(
                    "Game {}/{total}: current={} -> {} ({} plies){}  [worker {} game-index {}]",
                    done,
                    if current_white { "White" } else { "Black" },
                    match idx {
                        0 => "current win",
                        1 => "current loss",
                        2 => "draw",
                        _ => "unfinished",
                    },
                    report.plies,
                    opening_desc(&report.opening_moves),
                    report.worker_id,
                    report.game_index + 1
                );
                print_standings(
                    done,
                    total,
                    &white,
                    &black,
                    config.skill,
                    config.move_time_ms,
                );
            }
            Err(RecvTimeoutError::Timeout) => {
                eprintln!();
                eprintln!(
                    "Progress heartbeat: completed {done}/{total}; jobs={jobs}; waiting for workers..."
                );
                print_standings(
                    done,
                    total,
                    &white,
                    &black,
                    config.skill,
                    config.move_time_ms,
                );
            }
            Err(RecvTimeoutError::Disconnected) => break,
        }
    }

    for handle in handles {
        handle.join().expect("H2H worker should not panic");
    }
    assert_eq!(done, total, "all scheduled head-to-head games must finish");

    let cwin = white[0] + black[0];
    let closs = white[1] + black[1];
    let cdraw = white[2] + black[2];
    let decided = cwin + closs + cdraw;
    let net = cwin as i64 - closs as i64;
    let verdict = if net > 0 {
        "current is STRONGER than master"
    } else if net < 0 {
        "current is WEAKER than master"
    } else {
        "current and master are EVEN"
    };
    eprintln!();
    eprintln!(
        "FINAL: current {cwin}W-{closs}L-{cdraw}D / {decided} decided  Score {:.1}%  net {net:+}  =>  {verdict}",
        pct(cwin as f64 + 0.5 * cdraw as f64, decided)
    );
}

#[test]
#[ignore = "head-to-head match vs master C++; set H2H_* and run with --ignored --nocapture"]
fn head_to_head_vs_master() {
    let current = resolve_engine_program(&env::var("H2H_CURRENT").unwrap_or_else(|_| {
        workspace_root()
            .join("target/release/tgf.exe")
            .to_string_lossy()
            .into_owned()
    }));
    let current_args = engine_args_from_env("H2H_CURRENT_ARGS", "uci");
    let current_env = engine_env_from_env("H2H_CURRENT_ENV");
    let master = resolve_engine_program(
        &env::var("H2H_MASTER")
            .unwrap_or_else(|_| "D:/Repo/Sanmill-master/Sanmill/master_engine.exe".to_string()),
    );
    let master_args = {
        let args = engine_args_from_env("H2H_MASTER_ARGS", "");
        if args.is_empty() && is_tgf_program(&master) {
            vec!["uci".to_string()]
        } else {
            args
        }
    };
    let master_env = engine_env_from_env("H2H_MASTER_ENV");
    let games: usize = env::var("H2H_GAMES")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(20);
    let skill: u32 = env::var("H2H_SKILL")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(14);
    let threads = env_u32("H2H_ENGINE_THREADS", 1).clamp(1, 512);
    let max_plies: usize = env::var("H2H_MAX_PLIES")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(200);
    let go_current = env::var("H2H_GO_CURRENT").unwrap_or_else(|_| "go depth 0".to_string());
    let go_master = env::var("H2H_GO_MASTER").unwrap_or_else(|_| "go".to_string());
    // H2H_MOVETIME_MS (milliseconds, Sanmill-only) takes priority over the
    // legacy H2H_MOVETIME (whole seconds).  When only H2H_MOVETIME is set,
    // convert to ms.  Default 0 = fixed depth.
    let move_time_ms: u32 = if let Ok(ms) = env::var("H2H_MOVETIME_MS") {
        ms.parse().unwrap_or(0)
    } else {
        env::var("H2H_MOVETIME")
            .ok()
            .and_then(|s| s.parse::<u32>().ok())
            .unwrap_or(0)
            .saturating_mul(1000)
    };
    let n_move_rule = env_u32("H2H_N_MOVE_RULE", 100);
    let endgame_n_move_rule = env_u32("H2H_ENDGAME_N_MOVE_RULE", 100);
    let opening_plies = env_usize("H2H_OPENING_PLIES", 0);
    let opening_seed = env_u64("H2H_OPENING_SEED", 0x9E37_79B9_7F4A_7C15);
    let opening_db_path = env_path("H2H_OPENING_DB_PATH");
    let total = games * 2;
    assert!(total > 0, "H2H_GAMES must schedule at least one game");
    let jobs = jobs_for_total(total);
    let engine_options = EngineOptions {
        skill,
        threads,
        move_time_ms,
        n_move_rule,
        endgame_n_move_rule,
    };
    let current_perfect_db = EnginePerfectDbOptions {
        enabled: env_bool("H2H_CURRENT_USE_PERFECT_DB", false),
        path: env_path("H2H_CURRENT_PERFECT_DB_PATH"),
        cache_sectors: env::var("H2H_CURRENT_PERFECT_DB_CACHE")
            .ok()
            .and_then(|s| s.parse::<usize>().ok()),
        ordering: env::var("H2H_CURRENT_PERFECT_DB_ORDERING")
            .ok()
            .filter(|s| !s.trim().is_empty()),
    };
    let master_perfect_db = EnginePerfectDbOptions {
        enabled: env_bool("H2H_MASTER_USE_PERFECT_DB", false),
        path: env_path("H2H_MASTER_PERFECT_DB_PATH"),
        cache_sectors: env::var("H2H_MASTER_PERFECT_DB_CACHE")
            .ok()
            .and_then(|s| s.parse::<usize>().ok()),
        ordering: env::var("H2H_MASTER_PERFECT_DB_ORDERING")
            .ok()
            .filter(|s| !s.trim().is_empty()),
    };
    let current_patch = patch_options_from_env(
        "H2H_CURRENT_PATCH_PATH",
        "H2H_CURRENT_PATCH_AVOID_TRAPS",
        "H2H_CURRENT_PATCH_MAKE_TRAPS",
    );
    let master_patch = patch_options_from_env(
        "H2H_MASTER_PATCH_PATH",
        "H2H_MASTER_PATCH_AVOID_TRAPS",
        "H2H_MASTER_PATCH_MAKE_TRAPS",
    );

    let options = MillVariantOptions {
        n_move_rule,
        endgame_n_move_rule,
        ..MillVariantOptions::default()
    };
    let opening = PerfectOpening::new(opening_plies, opening_seed, opening_db_path);
    let opening_config = opening.describe();
    drop(opening);

    // Mode: "vs" (current vs master, default), "self-current", "self-master".
    let mode = env::var("H2H_MODE").unwrap_or_else(|_| "vs".to_string());
    let config = MatchConfig {
        current: current.clone(),
        current_args: current_args.clone(),
        current_env: current_env.clone(),
        master: master.clone(),
        master_args: master_args.clone(),
        master_env: master_env.clone(),
        go_current: go_current.clone(),
        go_master: go_master.clone(),
        engine_options,
        current_perfect_db: current_perfect_db.clone(),
        master_perfect_db: master_perfect_db.clone(),
        current_patch: current_patch.clone(),
        master_patch: master_patch.clone(),
        variant_options: options,
        total_games: total,
        jobs,
        max_plies,
        skill,
        move_time_ms,
        opening_plies,
        opening_seed,
        opening_db_path: env_path("H2H_OPENING_DB_PATH"),
    };

    if mode == "self-current" || mode == "self-master" {
        let is_master = mode == "self-master";
        let label = if is_master { "master" } else { "current" };
        eprintln!(
            "Self-play: {label} vs {label}  (rows = board side)\n  skill={skill} movetime_ms={move_time_ms} shuffling=on algo=MTD(f) games={total} jobs={jobs} ply_cap={max_plies} n_move={n_move_rule} endgame_n_move={endgame_n_move_rule} {opening_config}\n  current_env={current_env:?} master_env={master_env:?}\n  current_db={current_perfect_db:?} master_db={master_perfect_db:?}\n  current_patch={current_patch:?} master_patch={master_patch:?}"
        );
        run_self_play_parallel(config, is_master, label);
    } else {
        // vs mode: current vs master, alternating colours each game so the live
        // rates are not skewed by Black's structural edge until colours balance.
        eprintln!(
            "Head-to-head: current=`{current}` vs master=`{master}`  (rows = current's colour)\n  skill={skill} movetime_ms={move_time_ms} shuffling=on algo=MTD(f) games/color={games} jobs={jobs} ply_cap={max_plies} n_move={n_move_rule} endgame_n_move={endgame_n_move_rule} {opening_config}\n  current_args={current_args:?} master_args={master_args:?}\n  current_env={current_env:?} master_env={master_env:?}\n  current_db={current_perfect_db:?} master_db={master_perfect_db:?}\n  current_patch={current_patch:?} master_patch={master_patch:?}\n  go_current=`{go_current}` go_master=`{go_master}`"
        );
        run_vs_parallel(config);
    }
}
