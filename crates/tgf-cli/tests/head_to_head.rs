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
//   H2H_CURRENT    path to the current-branch UCI engine (default platform tgf)
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
//   H2H_CURRENT_PATCH_PATH     correction patch file for current (Sanmill only)
//   H2H_MASTER_PATCH_PATH      correction patch file for opponent (Sanmill only)
//   H2H_CURRENT_TRAPS_PATH     trap-library file for current (Sanmill only)
//   H2H_MASTER_TRAPS_PATH      trap-library file for opponent (Sanmill only)
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
//   H2H_SEARCH_SHUFFLE_SEED  decimal or 0x-hex base seed; when set, every
//                  game gets a deterministic `SearchShuffleSeed` sent to
//                  BOTH engines, derived from (base seed, game_index,
//                  board side) -- so the exact same (game_index, side) in
//                  every comparison run (e.g. avoid-only vs avoid+make)
//                  shares one tie-break stream regardless of which engine
//                  plays which colour, making paired diffs comparable.
//                  Unset (default): no SearchShuffleSeed is sent and
//                  engines keep their historical wall-clock stream --
//                  paired diffs are then subject to unpaired tie-break
//                  noise on top of the paired opening. White/black seeds
//                  are recorded in H2H_GAME_LOG for offline verification.
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

use std::collections::BTreeMap;
use std::env;
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};
use std::sync::mpsc::{self, RecvTimeoutError};
use std::thread;
use std::time::{Duration, Instant};

use perfect_db::database::{Database, FileDatabaseProvider};
use sha2::{Digest, Sha256};
use tgf_cli::h2h_trace::{
    H2H_RAW_UCI_LIMIT_BYTES, H2H_TRACE_SCHEMA_VERSION, H2hActor, H2hArtifactIdentity,
    H2hDecisionTraceV2, H2hEngineIdentity, H2hGameEndKind, H2hGameTraceV2, H2hMatchConfig,
    H2hReproducibility, H2hSetOption, H2hTraceManifestV2, fingerprint_environment,
    fingerprint_file, fingerprint_perfect_database, manifest_path_for_log, mill_rules_identity,
    new_run_id, sha256_file,
};
use tgf_core::{Action, ActionList, Game, GameRules, GameStateSnapshot, OutcomeKind, Workbench};
use tgf_mill::{
    MillActionKind, MillGame, MillPhase, MillPlyCount, MillRules, MillUciCodec, MillVariantOptions,
};

/// Engine-only environment switches whose values are known not to contain
/// credentials or machine-local paths. Everything else remains hash-only in
/// Trace v2 and therefore deliberately cannot be replayed automatically.
const SAFE_REPLAY_ENVIRONMENT: &[&str] = &[
    "TGF_ENABLE_PREFETCH",
    "TGF_ENABLE_TT_MOVE",
    "TGF_EVAL_WEIGHTS",
    "TGF_PREFETCH_MODE",
    "TGF_TT_CLUSTER_BITS",
];

/// One UCI engine subprocess.
struct Engine {
    child: Child,
    stdin: ChildStdin,
    out: BufReader<ChildStdout>,
    go: String,
    name: String,
    role: String,
    instance_id: String,
    uci_id: Vec<String>,
    search_ordinal: u64,
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
    /// `None` preserves the historical engine default. For forensic profiles
    /// this is explicitly pinned to `Some(false)`.
    ai_is_lazy: Option<bool>,
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
    traps_path: Option<PathBuf>,
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
    role: &'a str,
    instance_id: &'a str,
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
            role,
            instance_id,
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
            role: role.to_string(),
            instance_id: instance_id.to_string(),
            uci_id: Vec::new(),
            search_ordinal: 0,
        };
        e.cmd("uci");
        let (_, handshake) = e
            .wait_with_capture("uciok")
            .unwrap_or_else(|| panic!("{name}: no uciok"));
        e.uci_id = handshake
            .lines()
            .filter(|line| line.trim_start().starts_with("id "))
            .map(str::to_string)
            .collect();
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
        if let Some(value) = options.ai_is_lazy {
            e.cmd(&format!(
                "setoption name AiIsLazy value {}",
                if value { "true" } else { "false" }
            ));
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
        if let Some(path) = patch.traps_path.as_ref() {
            e.cmd(&format!("setoption name TrapPath value {}", path.display()));
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
        assert!(
            e.wait_with_capture("readyok").is_some(),
            "{name}: no readyok"
        );
        e
    }

    fn cmd(&mut self, s: &str) {
        writeln!(self.stdin, "{s}").expect("write to engine");
        self.stdin.flush().expect("flush engine");
    }

    /// Read engine output until a line contains `token`; retain every line so
    /// UCI identity and forensic search output are not silently discarded.
    fn wait_with_capture(&mut self, token: &str) -> Option<(String, String)> {
        let mut line = String::new();
        let mut output = String::new();
        loop {
            line.clear();
            match self.out.read_line(&mut line) {
                Ok(0) | Err(_) => return None,
                Ok(_) => {
                    output.push_str(&line);
                    if line.contains(token) {
                        return Some((line.trim().to_string(), output));
                    }
                }
            }
        }
    }

    fn new_game(&mut self) {
        self.cmd("ucinewgame");
    }

    /// Ask the engine for its best move and retain the complete UCI stream
    /// from `go` through `bestmove`.
    fn search(
        &mut self,
        moves: &[String],
        actor: H2hActor,
        action_index: usize,
        logical_ply_index: u32,
    ) -> H2hDecisionTraceV2 {
        let pos = if moves.is_empty() {
            "position startpos".to_string()
        } else {
            format!("position startpos moves {}", moves.join(" "))
        };
        self.cmd(&pos);
        let go = self.go.clone();
        self.search_ordinal = self.search_ordinal.saturating_add(1);
        let ordinal = self.search_ordinal;
        let started = Instant::now();
        self.cmd(&go);

        let mut raw = String::new();
        let mut full_hash = Sha256::new();
        let mut truncated = false;
        let mut telemetry = ParsedUciTelemetry::default();
        let mut protocol_error = None;
        let bestmove = loop {
            let mut line = String::new();
            match self.out.read_line(&mut line) {
                Ok(0) => {
                    protocol_error = Some("engine_stdout_eof_before_bestmove".to_string());
                    break None;
                }
                Err(error) => {
                    protocol_error = Some(format!("engine_stdout_error: {error}"));
                    break None;
                }
                Ok(_) => {
                    full_hash.update(line.as_bytes());
                    append_capped_utf8(&mut raw, &line, H2H_RAW_UCI_LIMIT_BYTES, &mut truncated);
                    telemetry.observe(&line);
                    if let Some(token) = parse_bestmove(&line) {
                        if matches!(token.as_str(), "(none)" | "none" | "0000") {
                            protocol_error = Some("engine_returned_no_bestmove".to_string());
                            break None;
                        }
                        break Some(token);
                    }
                }
            }
        };
        let score_value = telemetry.white_score(actor);
        H2hDecisionTraceV2 {
            actor,
            engine_role: self.role.clone(),
            engine_instance_id: self.instance_id.clone(),
            instance_search_ordinal: ordinal,
            action_index,
            logical_ply_index,
            go_command: go,
            elapsed_ms: started.elapsed().as_millis(),
            bestmove,
            depth: telemetry.depth,
            score_kind: telemetry.score_kind,
            score_value,
            nodes: telemetry.nodes,
            raw_uci_output: raw,
            raw_uci_sha256: full_hash
                .finalize()
                .iter()
                .map(|byte| format!("{byte:02x}"))
                .collect(),
            raw_uci_truncated: truncated,
            protocol_error,
        }
    }
}

#[derive(Default)]
struct ParsedUciTelemetry {
    depth: Option<u32>,
    score_kind: Option<String>,
    score_value: Option<i32>,
    score_is_side_to_move: bool,
    nodes: Option<u64>,
}

impl ParsedUciTelemetry {
    fn observe(&mut self, line: &str) {
        let tokens = line.split_whitespace().collect::<Vec<_>>();
        let mut index = 0;
        while index < tokens.len() {
            match tokens[index] {
                "depth" => {
                    if let Some(value) = tokens.get(index + 1).and_then(|v| v.parse().ok()) {
                        self.depth = Some(value);
                    }
                    index += 2;
                }
                "nodes" => {
                    if let Some(value) = tokens.get(index + 1).and_then(|v| v.parse().ok()) {
                        self.nodes = Some(value);
                    }
                    index += 2;
                }
                "score" => {
                    let Some(next) = tokens.get(index + 1) else {
                        break;
                    };
                    if matches!(*next, "cp" | "mate") {
                        if let Some(value) = tokens.get(index + 2).and_then(|v| v.parse().ok()) {
                            self.score_kind = Some((*next).to_string());
                            self.score_value = Some(value);
                            // Sanmill's historical single-line result carries
                            // `bestmove` and is already White-relative.
                            // Standard multi-line UCI info is side-to-move
                            // relative and needs actor normalization.
                            self.score_is_side_to_move = !tokens.contains(&"bestmove");
                        }
                        index += 3;
                    } else {
                        // Legacy C++: `info score N ... bestmove M`.
                        if let Ok(value) = next.parse::<i32>() {
                            self.score_kind = Some("cp".to_string());
                            self.score_value = Some(value);
                            self.score_is_side_to_move = false;
                        }
                        index += 2;
                    }
                }
                _ => index += 1,
            }
        }
    }

    fn white_score(&self, actor: H2hActor) -> Option<i32> {
        self.score_value.map(|score| {
            if self.score_is_side_to_move && actor == H2hActor::Black {
                -score
            } else {
                score
            }
        })
    }
}

fn parse_bestmove(line: &str) -> Option<String> {
    let tokens = line.split_whitespace().collect::<Vec<_>>();
    let index = tokens.iter().position(|token| *token == "bestmove")?;
    tokens.get(index + 1).map(|token| (*token).to_string())
}

fn append_capped_utf8(output: &mut String, line: &str, limit: usize, truncated: &mut bool) {
    let remaining = limit.saturating_sub(output.len());
    if line.len() <= remaining {
        output.push_str(line);
        return;
    }
    let mut boundary = remaining.min(line.len());
    while boundary > 0 && !line.is_char_boundary(boundary) {
        boundary -= 1;
    }
    output.push_str(&line[..boundary]);
    *truncated = true;
}

#[test]
fn forensic_uci_parser_accepts_sanmill_standard_and_legacy_shapes() {
    let mut sanmill = ParsedUciTelemetry::default();
    let sanmill_line = "info depth 13 score cp -4 nodes 99 bestmove a4-d7\n";
    sanmill.observe(sanmill_line);
    assert_eq!(sanmill.depth, Some(13));
    assert_eq!(sanmill.score_kind.as_deref(), Some("cp"));
    assert_eq!(sanmill.score_value, Some(-4));
    assert_eq!(sanmill.white_score(H2hActor::Black), Some(-4));
    assert_eq!(sanmill.nodes, Some(99));
    assert_eq!(parse_bestmove(sanmill_line).as_deref(), Some("a4-d7"));

    let mut standard = ParsedUciTelemetry::default();
    standard.observe("info depth 9 score mate 3 nodes 123 pv d7\n");
    standard.observe("bestmove d7 ponder a1\n");
    assert_eq!(standard.depth, Some(9));
    assert_eq!(standard.score_kind.as_deref(), Some("mate"));
    assert_eq!(standard.score_value, Some(3));
    assert_eq!(standard.white_score(H2hActor::Black), Some(-3));
    assert_eq!(standard.nodes, Some(123));
    assert_eq!(
        parse_bestmove("bestmove d7 ponder a1").as_deref(),
        Some("d7")
    );

    let mut legacy = ParsedUciTelemetry::default();
    let legacy_line = "info score -7 bestmove xf4";
    legacy.observe(legacy_line);
    assert_eq!(legacy.score_kind.as_deref(), Some("cp"));
    assert_eq!(legacy.score_value, Some(-7));
    assert_eq!(parse_bestmove(legacy_line).as_deref(), Some("xf4"));
}

#[test]
fn forensic_uci_capture_truncates_on_utf8_boundary() {
    let mut output = String::new();
    let mut truncated = false;
    append_capped_utf8(&mut output, "info πππ bestmove d7\n", 9, &mut truncated);
    assert!(truncated);
    assert!(output.len() <= 9);
    assert!(std::str::from_utf8(output.as_bytes()).is_ok());

    append_capped_utf8(&mut output, "ignored", 9, &mut truncated);
    assert!(output.len() <= 9);
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

struct PlayedGame {
    result: GameResult,
    plies: usize,
    opening_moves: Vec<String>,
    moves: Vec<String>,
    white_seed: Option<u64>,
    black_seed: Option<u64>,
    winner: Option<H2hActor>,
    outcome_reason: String,
    end_kind: H2hGameEndKind,
    decisions: Vec<H2hDecisionTraceV2>,
    white_engine_instance_id: String,
    black_engine_instance_id: String,
    white_engine_role: String,
    black_engine_role: String,
    white_uci_id: Vec<String>,
    black_uci_id: Vec<String>,
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

/// Deterministic per-(game, board-side) `SearchShuffleSeed` value, derived
/// independently of [`paired_opening_seed`] (disjoint salts, so the two
/// streams can never alias). `board_side` is the physical board side (0 =
/// White, 1 = Black) -- NEVER which engine (current/master) occupies it --
/// so the exact same `(game_index, board_side)` pair gets the exact same
/// tie-break stream in every comparison group (A/B/C/gated-C) regardless
/// of which engine plays which colour in that group's run. Keyed by the
/// literal `game_index` (not the opening's `pair_index`): the two games of
/// one paired-opening pair are still two distinct physical games and get
/// distinct seeds, exactly like every other game.
fn derive_shuffle_seed(base_seed: u64, game_index: usize, board_side: u8) -> u64 {
    splitmix64(
        base_seed
            ^ (game_index as u64).wrapping_mul(0x9E37_79B9_7F4A_7C15)
            ^ (board_side as u64).wrapping_mul(0xBF58_476D_1CE4_E5B9),
    )
}

fn workspace_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .canonicalize()
        .unwrap_or_else(|_| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../.."))
}

fn default_tgf_program() -> PathBuf {
    workspace_root()
        .join("target/release")
        .join(format!("tgf{}", std::env::consts::EXE_SUFFIX))
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

fn patch_options_from_env(
    path_var: &str,
    traps_path_var: &str,
    avoid_var: &str,
    make_var: &str,
) -> EnginePatchOptions {
    let avoid_traps = env_bool(avoid_var, false);
    let make_traps = env_bool(make_var, false);
    let path = env_path(path_var).or_else(|| {
        if avoid_traps {
            Some(default_patch_path())
        } else {
            None
        }
    });
    let traps_path = env_path(traps_path_var);
    EnginePatchOptions {
        path,
        traps_path,
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
    /// Base seed for `derive_shuffle_seed`, from `H2H_SEARCH_SHUFFLE_SEED`.
    /// `None` (the default) sends no `SearchShuffleSeed` at all, leaving
    /// engines on their historical wall-clock tie-break stream.
    shuffle_seed: Option<u64>,
}

impl Referee {
    fn new(
        options: MillVariantOptions,
        opening: PerfectOpening,
        shuffle_seed: Option<u64>,
    ) -> Self {
        Self {
            rules: MillRules::new(options.clone()),
            game: MillGame::new(options.clone()),
            options,
            opening,
            shuffle_seed,
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
        counts: &mut MillPlyCount,
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
            let before = *snap;
            *snap = self.rules.apply(snap, action);
            counts
                .record(&self.rules, &before, snap)
                .expect("Perfect DB opening must preserve a valid Mill side");
            repetition.record_after_apply(action, snap);
            moves.push(choice.token.clone());
            opening_moves.push(choice.token);
        }

        opening_moves
    }

    /// Play one full game between the `white` and `black` engines; returns
    /// the outcome by board colour (`tgf-mill` is the referee), plus the
    /// `SearchShuffleSeed` values sent this game (`None` when
    /// `H2H_SEARCH_SHUFFLE_SEED` is unset), for the game log.
    fn play_game(
        &mut self,
        white: &mut Engine,
        black: &mut Engine,
        max_plies: usize,
        game_index: usize,
    ) -> PlayedGame {
        let mut snap = self.rules.initial_state(&[]);
        let mut moves: Vec<String> = Vec::new();
        let mut repetition = RepetitionReferee::default();
        let mut counts = MillPlyCount::default();
        let mut decisions = Vec::new();
        white.new_game();
        black.new_game();
        // Deterministic per-(game, board-side) tie-break stream for BOTH
        // engines (whichever role -- current or master/opponent -- occupies
        // that colour this game): without pinning the opponent too, its
        // own shuffle noise would still pollute a paired diff. Sent after
        // `ucinewgame` (which does not reset engine options) and before
        // any `position`/`go`, so it is in effect for the whole game.
        let (white_seed, black_seed) = match self.shuffle_seed {
            Some(base) => {
                let w = derive_shuffle_seed(base, game_index, 0);
                let b = derive_shuffle_seed(base, game_index, 1);
                white.cmd(&format!(
                    "setoption name SearchShuffleSeed value 0x{w:016x}"
                ));
                black.cmd(&format!(
                    "setoption name SearchShuffleSeed value 0x{b:016x}"
                ));
                (Some(w), Some(b))
            }
            None => (None, None),
        };
        let opening_moves = self.append_perfect_opening_prefix(
            &mut snap,
            &mut moves,
            &mut repetition,
            &mut counts,
            game_index,
        );

        let mut adjudication = None;
        for ply in moves.len()..max_plies {
            let outcome = self.rules.outcome(&snap);
            match outcome.kind {
                OutcomeKind::Ongoing => {}
                OutcomeKind::Win(0) => {
                    adjudication = Some((
                        GameResult::WhiteWin,
                        ply,
                        Some(H2hActor::White),
                        outcome.reason,
                        H2hGameEndKind::Rule,
                    ));
                    break;
                }
                OutcomeKind::Win(1) => {
                    adjudication = Some((
                        GameResult::BlackWin,
                        ply,
                        Some(H2hActor::Black),
                        outcome.reason,
                        H2hGameEndKind::Rule,
                    ));
                    break;
                }
                OutcomeKind::Draw => {
                    adjudication = Some((
                        GameResult::Draw,
                        ply,
                        None,
                        outcome.reason,
                        H2hGameEndKind::Rule,
                    ));
                    break;
                }
                _ => {
                    adjudication = Some((
                        GameResult::Unfinished,
                        ply,
                        None,
                        format!("unsupported_outcome:{:?}", outcome.kind),
                        H2hGameEndKind::ProtocolError,
                    ));
                    break;
                }
            }
            if repetition.is_root_threefold_draw(&snap) {
                adjudication = Some((
                    GameResult::Draw,
                    ply,
                    None,
                    "drawThreefoldRepetition".to_string(),
                    H2hGameEndKind::Rule,
                ));
                break;
            }

            let stm = self.game.build_workbench(&snap).side_to_move();
            let actor = H2hActor::from_side(stm).expect("ongoing Mill state must have a side");
            let engine = if stm == 0 { &mut *white } else { &mut *black };
            let decision = engine.search(&moves, actor, moves.len(), counts.logical_plies);
            let bestmove = decision.bestmove.clone();
            decisions.push(decision);
            let Some(mv) = bestmove else {
                eprintln!("  ! {} returned no move at ply {ply}", engine.name);
                adjudication = Some((
                    GameResult::Unfinished,
                    ply,
                    None,
                    "protocol_missing_bestmove".to_string(),
                    H2hGameEndKind::ProtocolError,
                ));
                break;
            };
            let Some(action) = MillUciCodec::decode_action(&snap, &mv) else {
                eprintln!(
                    "  ! undecodable move `{mv}` from {} at ply {ply}",
                    engine.name
                );
                adjudication = Some((
                    GameResult::Unfinished,
                    ply,
                    None,
                    format!("protocol_undecodable_bestmove:{mv}"),
                    H2hGameEndKind::ProtocolError,
                ));
                break;
            };
            let mut legal = ActionList::<256>::new();
            self.rules.legal_actions(&snap, &mut legal);
            if !legal.as_slice().contains(&action) {
                eprintln!("  ! illegal move `{mv}` from {} at ply {ply}", engine.name);
                adjudication = Some((
                    GameResult::Unfinished,
                    ply,
                    None,
                    format!("protocol_illegal_bestmove:{mv}"),
                    H2hGameEndKind::ProtocolError,
                ));
                break;
            }
            let before = snap;
            snap = self.rules.apply(&snap, action);
            counts
                .record(&self.rules, &before, &snap)
                .expect("engine action must preserve a valid Mill side");
            repetition.record_after_apply(action, &snap);
            moves.push(mv);
        }

        let (result, plies, winner, outcome_reason, end_kind) = adjudication.unwrap_or((
            GameResult::Draw,
            max_plies,
            None,
            "ply_cap".to_string(),
            H2hGameEndKind::PlyCap,
        ));
        PlayedGame {
            result,
            plies,
            opening_moves,
            moves,
            white_seed,
            black_seed,
            winner,
            outcome_reason,
            end_kind,
            decisions,
            white_engine_instance_id: white.instance_id.clone(),
            black_engine_instance_id: black.instance_id.clone(),
            white_engine_role: white.role.clone(),
            black_engine_role: black.role.clone(),
            white_uci_id: white.uci_id.clone(),
            black_uci_id: black.uci_id.clone(),
        }
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

/// `derive_shuffle_seed` must be a pure, stable function of its inputs
/// (same base/game/side always reproduces the same seed -- the entire
/// point of pinning it), while varying either `game_index` or
/// `board_side` alone must change the result (otherwise two different
/// games, or the two colours of the same game, would silently share one
/// tie-break stream). It must also never collide with
/// `paired_opening_seed`'s stream for the same base seed.
#[test]
fn derive_shuffle_seed_is_stable_and_varies_with_game_and_side() {
    let base = 0x5EED_0001_u64;

    assert_eq!(
        derive_shuffle_seed(base, 7, 0),
        derive_shuffle_seed(base, 7, 0),
        "identical inputs must reproduce identically"
    );

    assert_ne!(
        derive_shuffle_seed(base, 7, 0),
        derive_shuffle_seed(base, 7, 1),
        "the two board sides of the same game must not share a seed"
    );
    assert_ne!(
        derive_shuffle_seed(base, 7, 0),
        derive_shuffle_seed(base, 8, 0),
        "two different games on the same side must not share a seed"
    );
    assert_ne!(
        derive_shuffle_seed(base, 7, 0),
        derive_shuffle_seed(base.wrapping_add(1), 7, 0),
        "a different base seed must change the derived seed"
    );

    // Every (game_index, side) pair across a realistic run must be unique
    // (no accidental collisions from the salt choice).
    let mut seen = std::collections::HashSet::new();
    for game_index in 0..64 {
        for side in [0u8, 1u8] {
            assert!(
                seen.insert(derive_shuffle_seed(base, game_index, side)),
                "collision at game_index={game_index} side={side}"
            );
        }
    }

    // Disjoint from the opening-prefix seed stream for the same base and
    // game_index (different salts by construction).
    assert_ne!(
        derive_shuffle_seed(base, 7, 0),
        paired_opening_seed(base, 7)
    );
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
fn resolve_engine_program_uses_workspace_target_for_relative_path() {
    let root = workspace_root();
    let relative = format!("target/release/tgf{}", std::env::consts::EXE_SUFFIX);
    let resolved = resolve_engine_program(&relative);
    let resolved_path = PathBuf::from(&resolved);
    assert_eq!(resolved_path, root.join(relative));
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

fn environment_names(values: &[(String, String)]) -> Vec<&str> {
    values.iter().map(|(name, _)| name.as_str()).collect()
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

fn env_bool_option(name: &str) -> Option<bool> {
    env::var(name)
        .ok()
        .filter(|value| !value.trim().is_empty())
        .map(|value| match value.trim().to_ascii_lowercase().as_str() {
            "1" | "true" | "on" | "yes" => true,
            "0" | "false" | "off" | "no" => false,
            _ => panic!("{name} must be a boolean, got `{value}`"),
        })
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

/// `Option<u64>` variant of [`env_u64`] for switches that must default to
/// "disabled" rather than to some numeric fallback (e.g.
/// `H2H_SEARCH_SHUFFLE_SEED`: unset must mean "send nothing", not "send a
/// baked-in seed").
fn env_u64_option(name: &str) -> Option<u64> {
    env::var(name).ok().map(|s| parse_u64_env_value(name, &s))
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
    run_id: String,
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
    /// Base seed for `derive_shuffle_seed`; `None` (default) sends no
    /// `SearchShuffleSeed`, preserving the historical wall-clock stream.
    shuffle_seed: Option<u64>,
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
    /// `SearchShuffleSeed` values sent this game (`None` when
    /// `H2H_SEARCH_SHUFFLE_SEED` is unset); written to the game log for
    /// offline reproduction / cross-group verification.
    white_seed: Option<u64>,
    black_seed: Option<u64>,
    winner: Option<H2hActor>,
    outcome_reason: String,
    end_kind: H2hGameEndKind,
    decisions: Vec<H2hDecisionTraceV2>,
    white_engine_instance_id: String,
    black_engine_instance_id: String,
    white_engine_role: String,
    black_engine_role: String,
    white_uci_id: Vec<String>,
    black_uci_id: Vec<String>,
}

fn make_game_report(
    worker_id: usize,
    game_index: usize,
    current_white: Option<bool>,
    played: PlayedGame,
) -> GameReport {
    GameReport {
        worker_id,
        game_index,
        result: played.result,
        plies: played.plies,
        opening_moves: played.opening_moves,
        moves: played.moves,
        current_white,
        white_seed: played.white_seed,
        black_seed: played.black_seed,
        winner: played.winner,
        outcome_reason: played.outcome_reason,
        end_kind: played.end_kind,
        decisions: played.decisions,
        white_engine_instance_id: played.white_engine_instance_id,
        black_engine_instance_id: played.black_engine_instance_id,
        white_engine_role: played.white_engine_role,
        black_engine_role: played.black_engine_role,
        white_uci_id: played.white_uci_id,
        black_uci_id: played.black_uci_id,
    }
}

struct TraceRecorder {
    log: std::io::BufWriter<std::fs::File>,
    manifest_path: PathBuf,
    manifest: H2hTraceManifestV2,
}

impl TraceRecorder {
    fn from_env(config: &MatchConfig, mode: &str) -> Option<Self> {
        let log_path = env::var("H2H_GAME_LOG")
            .ok()
            .map(PathBuf::from)
            .filter(|path| !path.as_os_str().is_empty())?;
        if let Some(parent) = log_path
            .parent()
            .filter(|path| !path.as_os_str().is_empty())
        {
            std::fs::create_dir_all(parent).unwrap_or_else(|error| {
                panic!(
                    "cannot create H2H_GAME_LOG parent {}: {error}",
                    parent.display()
                )
            });
        }

        let candidate_is_master = mode == "self-master";
        let candidate = if candidate_is_master {
            engine_identity(
                "candidate",
                &config.master,
                &config.master_args,
                &config.master_env,
                &config.go_master,
                &config.engine_options,
                &config.master_perfect_db,
                &config.master_patch,
                env::var("H2H_MASTER_GIT_REVISION").ok(),
            )
        } else {
            engine_identity(
                "candidate",
                &config.current,
                &config.current_args,
                &config.current_env,
                &config.go_current,
                &config.engine_options,
                &config.current_perfect_db,
                &config.current_patch,
                env::var("H2H_CURRENT_GIT_REVISION")
                    .ok()
                    .or_else(workspace_git_revision),
            )
        };
        let reference = (mode == "vs").then(|| {
            engine_identity(
                "reference",
                &config.master,
                &config.master_args,
                &config.master_env,
                &config.go_master,
                &config.engine_options,
                &config.master_perfect_db,
                &config.master_patch,
                env::var("H2H_MASTER_GIT_REVISION").ok(),
            )
        });
        let reproducibility = reproducibility(config, mode);
        let match_config = H2hMatchConfig {
            jobs: config.jobs,
            engine_threads: config.engine_options.threads,
            skill_level: config.skill,
            max_plies: config.max_plies,
            opening_plies: config.opening_plies,
            opening_seed: format!("0x{:016x}", config.opening_seed),
            search_seed: config.shuffle_seed.map(|seed| format!("0x{seed:016x}")),
            shuffling: true,
            algorithm: "mtdf".to_string(),
            draw_on_human_experience: true,
            ai_is_lazy: config.engine_options.ai_is_lazy,
        };
        let manifest = H2hTraceManifestV2::new(
            config.run_id.clone(),
            config.total_games,
            mode.to_string(),
            mill_rules_identity(&config.variant_options),
            candidate,
            reference,
            match_config,
            reproducibility,
            collect_artifacts(config, mode),
        );
        let manifest_path = env::var("H2H_MANIFEST")
            .ok()
            .map(PathBuf::from)
            .filter(|path| !path.as_os_str().is_empty())
            .unwrap_or_else(|| manifest_path_for_log(&log_path));
        let log =
            std::io::BufWriter::new(std::fs::File::create(&log_path).unwrap_or_else(|error| {
                panic!("cannot create H2H_GAME_LOG {}: {error}", log_path.display())
            }));
        let recorder = Self {
            log,
            manifest_path,
            manifest,
        };
        recorder.write_manifest();
        Some(recorder)
    }

    fn record(&mut self, report: &GameReport, legacy_result: &str) {
        self.observe_uci_id(&report.white_engine_role, &report.white_uci_id);
        self.observe_uci_id(&report.black_engine_role, &report.black_uci_id);
        let row = H2hGameTraceV2 {
            schema_version: H2H_TRACE_SCHEMA_VERSION,
            run_id: self.manifest.run_id.clone(),
            game_index: report.game_index,
            pair_index: report.game_index / 2,
            worker_id: report.worker_id,
            current_white: report.current_white,
            result: legacy_result.to_string(),
            plies: report.plies,
            opening_moves: report.opening_moves.clone(),
            moves: report.moves.clone(),
            atomic_actions: report.moves.clone(),
            white_seed: report.white_seed.map(|seed| format!("0x{seed:016x}")),
            black_seed: report.black_seed.map(|seed| format!("0x{seed:016x}")),
            white_engine_instance_id: report.white_engine_instance_id.clone(),
            black_engine_instance_id: report.black_engine_instance_id.clone(),
            winner: report.winner,
            outcome_reason: report.outcome_reason.clone(),
            end_kind: report.end_kind,
            decisions: report.decisions.clone(),
        };
        serde_json::to_writer(&mut self.log, &row).expect("H2H_GAME_LOG serialization failed");
        writeln!(self.log).expect("H2H_GAME_LOG write failed");
        self.log.flush().expect("H2H_GAME_LOG flush failed");
        self.manifest.completed_games = self.manifest.completed_games.saturating_add(1);
        self.write_manifest();
    }

    fn observe_uci_id(&mut self, role: &str, lines: &[String]) {
        let identity = if role == "candidate" {
            Some(&mut self.manifest.candidate)
        } else if role == "reference" {
            self.manifest.reference.as_mut()
        } else {
            None
        };
        if let Some(identity) = identity {
            for line in lines {
                if !identity.uci_id.contains(line) {
                    identity.uci_id.push(line.clone());
                }
            }
            identity.uci_id.sort();
        }
    }

    fn write_manifest(&self) {
        if let Some(parent) = self
            .manifest_path
            .parent()
            .filter(|path| !path.as_os_str().is_empty())
        {
            std::fs::create_dir_all(parent).unwrap_or_else(|error| {
                panic!(
                    "cannot create H2H manifest parent {}: {error}",
                    parent.display()
                )
            });
        }
        let file = std::fs::File::create(&self.manifest_path).unwrap_or_else(|error| {
            panic!(
                "cannot create H2H manifest {}: {error}",
                self.manifest_path.display()
            )
        });
        serde_json::to_writer_pretty(file, &self.manifest)
            .expect("H2H manifest serialization failed");
    }
}

#[allow(clippy::too_many_arguments)]
fn engine_identity(
    role: &str,
    program: &str,
    args: &[String],
    environment: &[(String, String)],
    go: &str,
    options: &EngineOptions,
    perfect_db: &EnginePerfectDbOptions,
    patch: &EnginePatchOptions,
    git_revision: Option<String>,
) -> H2hEngineIdentity {
    let program_path = Path::new(program);
    let effective_environment = effective_engine_environment(environment);
    H2hEngineIdentity {
        role: role.to_string(),
        path: program.to_string(),
        binary_sha256: program_path
            .is_file()
            .then(|| sha256_file(program_path).ok())
            .flatten(),
        git_revision: git_revision.or_else(|| git_revision_near(program_path)),
        arguments: args.to_vec(),
        uci_id: Vec::new(),
        setoptions: engine_setoptions(options, perfect_db, patch),
        go_command: go.to_string(),
        // Engine process environment is never copied into a trace in plain
        // text. Add names to this explicit list only for values proven safe.
        environment: fingerprint_environment(&effective_environment, SAFE_REPLAY_ENVIRONMENT),
    }
}

fn effective_engine_environment(explicit: &[(String, String)]) -> Vec<(String, String)> {
    let mut values = env::vars()
        .filter(|(name, _)| name.starts_with("TGF_"))
        .collect::<BTreeMap<_, _>>();
    for (name, value) in explicit {
        values.insert(name.clone(), value.clone());
    }
    values.into_iter().collect()
}

fn engine_setoptions(
    options: &EngineOptions,
    perfect_db: &EnginePerfectDbOptions,
    patch: &EnginePatchOptions,
) -> Vec<H2hSetOption> {
    let mut values = vec![
        ("Threads", options.threads.to_string()),
        ("SkillLevel", options.skill.to_string()),
        ("DeveloperMode", "false".to_string()),
        ("DrawOnHumanExperience", "true".to_string()),
        ("Shuffling", "true".to_string()),
        ("Algorithm", "2".to_string()),
        ("MoveTime", (options.move_time_ms / 1000).to_string()),
        ("MoveTimeMs", options.move_time_ms.to_string()),
        ("NMoveRule", options.n_move_rule.to_string()),
        ("EndgameNMoveRule", options.endgame_n_move_rule.to_string()),
    ];
    if let Some(value) = options.ai_is_lazy {
        values.push(("AiIsLazy", if value { "true" } else { "false" }.to_string()));
    }
    if let Some(path) = perfect_db.path.as_ref() {
        values.push(("PerfectDatabasePath", path.display().to_string()));
    }
    if let Some(cache) = perfect_db.cache_sectors {
        values.push(("PerfectDatabaseCacheSectors", cache.to_string()));
    }
    if let Some(ordering) = perfect_db.ordering.as_ref() {
        values.push(("PerfectDatabaseOrdering", ordering.clone()));
    }
    values.push((
        "UsePerfectDatabase",
        if perfect_db.enabled { "true" } else { "false" }.to_string(),
    ));
    if let Some(path) = patch.path.as_ref() {
        values.push(("PatchPath", path.display().to_string()));
    }
    if let Some(path) = patch.traps_path.as_ref() {
        values.push(("TrapPath", path.display().to_string()));
    }
    values.push((
        "PatchAvoidTraps",
        if patch.avoid_traps { "true" } else { "false" }.to_string(),
    ));
    values.push((
        "PatchMakeTraps",
        if patch.make_traps { "true" } else { "false" }.to_string(),
    ));
    values
        .into_iter()
        .map(|(name, value)| H2hSetOption {
            name: name.to_string(),
            value,
        })
        .collect()
}

fn reproducibility(config: &MatchConfig, mode: &str) -> H2hReproducibility {
    let go_commands = if mode == "vs" {
        vec![config.go_current.as_str(), config.go_master.as_str()]
    } else if mode == "self-master" {
        vec![config.go_master.as_str()]
    } else {
        vec![config.go_current.as_str()]
    };
    let fixed_nodes = go_commands
        .iter()
        .all(|command| go_has_fixed_nodes(command));
    let non_timed_search =
        config.move_time_ms == 0 && go_commands.iter().all(|command| !go_has_timing(command));
    let single_thread = config.engine_options.threads == 1;
    let fixed_search_seed = config.shuffle_seed.is_some();
    let mut reasons = Vec::new();
    if !fixed_nodes {
        reasons.push("go command is not fixed-node search".to_string());
    }
    if !single_thread {
        reasons.push("engine Threads is not 1".to_string());
    }
    if !fixed_search_seed {
        reasons.push("SearchShuffleSeed is not fixed".to_string());
    }
    if !non_timed_search {
        reasons.push("search uses a wall-clock limit".to_string());
    }
    if config.engine_options.ai_is_lazy != Some(false) {
        reasons.push("AiIsLazy is not explicitly disabled".to_string());
    }
    let active_environments = match mode {
        "self-current" => vec![effective_engine_environment(&config.current_env)],
        "self-master" => vec![effective_engine_environment(&config.master_env)],
        _ => vec![
            effective_engine_environment(&config.current_env),
            effective_engine_environment(&config.master_env),
        ],
    };
    if active_environments.iter().any(|environment| {
        environment.iter().any(|(name, value)| {
            name.eq_ignore_ascii_case("TGF_USE_LAZY_SMP")
                && matches!(
                    value.trim().to_ascii_lowercase().as_str(),
                    "1" | "true" | "yes" | "on"
                )
        })
    }) {
        reasons.push("TGF_USE_LAZY_SMP enables nondeterministic parallel search".to_string());
    }
    H2hReproducibility {
        fixed_nodes,
        single_thread,
        fixed_opening_seed: true,
        fixed_search_seed,
        non_timed_search,
        deterministic: reasons.is_empty(),
        nondeterministic_reasons: reasons,
    }
}

fn go_has_fixed_nodes(command: &str) -> bool {
    let tokens = command.split_whitespace().collect::<Vec<_>>();
    tokens
        .windows(2)
        .find(|pair| pair[0].eq_ignore_ascii_case("nodes"))
        .and_then(|pair| pair[1].parse::<u64>().ok())
        .is_some_and(|nodes| nodes > 0)
}

fn go_has_timing(command: &str) -> bool {
    command.split_whitespace().any(|token| {
        matches!(
            token.to_ascii_lowercase().as_str(),
            "movetime" | "wtime" | "btime" | "infinite"
        )
    })
}

fn workspace_git_revision() -> Option<String> {
    git_revision_near(&workspace_root())
}

fn git_revision_near(path: &Path) -> Option<String> {
    let directory = if path.is_dir() { path } else { path.parent()? };
    let output = Command::new("git")
        .args(["-C", &directory.display().to_string(), "rev-parse", "HEAD"])
        .output()
        .ok()?;
    output
        .status
        .success()
        .then(|| String::from_utf8_lossy(&output.stdout).trim().to_string())
}

fn collect_artifacts(config: &MatchConfig, mode: &str) -> Vec<H2hArtifactIdentity> {
    let mut artifacts = Vec::new();
    if config.opening_plies > 0
        && let Some(path) = config.opening_db_path.as_ref()
    {
        artifacts.push(
            fingerprint_perfect_database("opening_database", path)
                .unwrap_or_else(|_| fingerprint_file("opening_database", "perfect_database", path)),
        );
    }
    match mode {
        "self-master" => collect_engine_artifacts(
            &mut artifacts,
            "candidate",
            &config.master_perfect_db,
            &config.master_patch,
        ),
        "vs" => {
            collect_engine_artifacts(
                &mut artifacts,
                "candidate",
                &config.current_perfect_db,
                &config.current_patch,
            );
            collect_engine_artifacts(
                &mut artifacts,
                "reference",
                &config.master_perfect_db,
                &config.master_patch,
            );
        }
        _ => collect_engine_artifacts(
            &mut artifacts,
            "candidate",
            &config.current_perfect_db,
            &config.current_patch,
        ),
    }
    artifacts.sort_by(|left, right| {
        (left.role.as_str(), left.path.as_str()).cmp(&(right.role.as_str(), right.path.as_str()))
    });
    artifacts.dedup_by(|left, right| left.role == right.role && left.path == right.path);
    artifacts
}

fn collect_engine_artifacts(
    artifacts: &mut Vec<H2hArtifactIdentity>,
    role: &str,
    database: &EnginePerfectDbOptions,
    patch: &EnginePatchOptions,
) {
    if let Some(path) = database.path.as_ref() {
        let artifact_role = format!("{role}_database");
        artifacts.push(
            fingerprint_perfect_database(&artifact_role, path)
                .unwrap_or_else(|_| fingerprint_file(&artifact_role, "perfect_database", path)),
        );
    }
    if let Some(path) = patch.path.as_ref() {
        artifacts.push(fingerprint_file(
            &format!("{role}_patch"),
            "mill_patch",
            path,
        ));
    }
    if let Some(path) = patch.traps_path.as_ref() {
        artifacts.push(fingerprint_file(
            &format!("{role}_traps"),
            "mill_traps",
            path,
        ));
    }
}

fn self_legacy_result(result: GameResult) -> &'static str {
    match result {
        GameResult::WhiteWin => "white_win",
        GameResult::BlackWin => "black_win",
        GameResult::Draw => "draw",
        GameResult::Unfinished => "unfinished",
    }
}

fn build_referee(config: &MatchConfig) -> Referee {
    Referee::new(
        config.variant_options.clone(),
        PerfectOpening::new(
            config.opening_plies,
            config.opening_seed,
            config.opening_db_path.clone(),
        ),
        config.shuffle_seed,
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
    let mut trace = TraceRecorder::from_env(
        &config,
        if is_master {
            "self-master"
        } else {
            "self-current"
        },
    );
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
                        role: "candidate",
                        instance_id: &format!("worker-{worker_id}-white"),
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
                        role: "candidate",
                        instance_id: &format!("worker-{worker_id}-black"),
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
                        role: "candidate",
                        instance_id: &format!("worker-{worker_id}-white"),
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
                        role: "candidate",
                        instance_id: &format!("worker-{worker_id}-black"),
                        options: &config.engine_options,
                        perfect_db: &config.current_perfect_db,
                        patch: &config.current_patch,
                    }),
                )
            };

            for game_index in worker_game_indices(worker_id, config.total_games, config.jobs) {
                let played = referee.play_game(&mut ew, &mut eb, config.max_plies, game_index);
                tx.send(make_game_report(worker_id, game_index, None, played))
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
                if let Some(trace) = trace.as_mut() {
                    trace.record(&report, self_legacy_result(report.result));
                }
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
    let mut trace = TraceRecorder::from_env(&config, "vs");
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
                role: "candidate",
                instance_id: &format!("worker-{worker_id}-current"),
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
                role: "reference",
                instance_id: &format!("worker-{worker_id}-reference"),
                options: &config.engine_options,
                perfect_db: &config.master_perfect_db,
                patch: &config.master_patch,
            });

            for game_index in worker_game_indices(worker_id, config.total_games, config.jobs) {
                let current_white = game_index % 2 == 0;
                // Deterministic per-game tag for the engine-side patchtrap
                // trace (see TGF_PATCH_TRACE_DIR): joins each traced
                // switch to exactly one game log row via game_index,
                // instead of guessing by move prefix.
                cur.cmd(&format!(
                    "setoption name PatchTraceTag value gi{}cw{}",
                    game_index,
                    u8::from(current_white)
                ));
                let played = if current_white {
                    referee.play_game(&mut cur, &mut mas, config.max_plies, game_index)
                } else {
                    referee.play_game(&mut mas, &mut cur, config.max_plies, game_index)
                };
                tx.send(make_game_report(
                    worker_id,
                    game_index,
                    Some(current_white),
                    played,
                ))
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
                let idx = apply_vs_report(&report, &mut white, &mut black);
                let current_white = report
                    .current_white
                    .expect("vs report must identify current engine colour");
                if let Some(trace) = trace.as_mut() {
                    trace.record(
                        &report,
                        match idx {
                            0 => "win",
                            1 => "loss",
                            2 => "draw",
                            _ => "unfinished",
                        },
                    );
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
    let current = resolve_engine_program(
        &env::var("H2H_CURRENT")
            .unwrap_or_else(|_| default_tgf_program().to_string_lossy().into_owned()),
    );
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
    let shuffle_seed = env_u64_option("H2H_SEARCH_SHUFFLE_SEED");
    let total = games * 2;
    assert!(total > 0, "H2H_GAMES must schedule at least one game");
    let jobs = jobs_for_total(total);
    let engine_options = EngineOptions {
        skill,
        threads,
        move_time_ms,
        n_move_rule,
        endgame_n_move_rule,
        ai_is_lazy: env_bool_option("H2H_AI_IS_LAZY"),
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
        "H2H_CURRENT_TRAPS_PATH",
        "H2H_CURRENT_PATCH_AVOID_TRAPS",
        "H2H_CURRENT_PATCH_MAKE_TRAPS",
    );
    let master_patch = patch_options_from_env(
        "H2H_MASTER_PATCH_PATH",
        "H2H_MASTER_TRAPS_PATH",
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
    let current_env_names = environment_names(&current_env);
    let master_env_names = environment_names(&master_env);
    let config = MatchConfig {
        run_id: new_run_id(),
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
        shuffle_seed,
    };

    if mode == "self-current" || mode == "self-master" {
        let is_master = mode == "self-master";
        let label = if is_master { "master" } else { "current" };
        eprintln!(
            "Self-play: {label} vs {label}  (rows = board side)\n  skill={skill} movetime_ms={move_time_ms} shuffling=on algo=MTD(f) games={total} jobs={jobs} ply_cap={max_plies} n_move={n_move_rule} endgame_n_move={endgame_n_move_rule} {opening_config}\n  shuffle_seed={}\n  current_env_names={current_env_names:?} master_env_names={master_env_names:?}\n  current_db={current_perfect_db:?} master_db={master_perfect_db:?}\n  current_patch={current_patch:?} master_patch={master_patch:?}",
            match shuffle_seed {
                Some(seed) => format!("0x{seed:016x} (deterministic per game/side)"),
                None => "unset (wall-clock, unpaired)".to_string(),
            }
        );
        run_self_play_parallel(config, is_master, label);
    } else {
        // vs mode: current vs master, alternating colours each game so the live
        // rates are not skewed by Black's structural edge until colours balance.
        eprintln!(
            "Head-to-head: current=`{current}` vs master=`{master}`  (rows = current's colour)\n  skill={skill} movetime_ms={move_time_ms} shuffling=on algo=MTD(f) games/color={games} jobs={jobs} ply_cap={max_plies} n_move={n_move_rule} endgame_n_move={endgame_n_move_rule} {opening_config}\n  shuffle_seed={}\n  current_args={current_args:?} master_args={master_args:?}\n  current_env_names={current_env_names:?} master_env_names={master_env_names:?}\n  current_db={current_perfect_db:?} master_db={master_perfect_db:?}\n  current_patch={current_patch:?} master_patch={master_patch:?}\n  go_current=`{go_current}` go_master=`{go_master}`",
            match shuffle_seed {
                Some(seed) => format!("0x{seed:016x} (deterministic per game/side)"),
                None => "unset (wall-clock, unpaired)".to_string(),
            }
        );
        run_vs_parallel(config);
    }
}
