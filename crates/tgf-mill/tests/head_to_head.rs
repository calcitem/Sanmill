// SPDX-License-Identifier: GPL-3.0-or-later
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
//   H2H_GAMES=20 cargo test -p tgf-mill --release --test head_to_head \
//     head_to_head_vs_master -- --ignored --nocapture
//
// Env vars:
//   H2H_CURRENT    path to the current-branch UCI engine (default tgf.exe)
//   H2H_MASTER     path to the master C++ UCI engine
//   H2H_GAMES      games per color (default 20)
//   H2H_SKILL      skill level (default 14)
//   H2H_MAX_PLIES  ply cap -> over-cap counted as a maneuvering draw (default 200)
//   H2H_GO_CURRENT go command for the current engine (default "go depth 0")
//   H2H_GO_MASTER  go command for the master engine     (default "go")
//   H2H_MOVETIME   per-move thinking time in SECONDS via the MoveTime option
//                  (range 0..=60; default 0 = pure fixed depth / Time 0)
//   H2H_MODE       "vs" (current vs master, default), "self-current" or
//                  "self-master": the named engine plays ITSELF (two
//                  independent instances), and the White / Black rows then show
//                  the game's first/second-player colour bias rather than a
//                  current-vs-master result.
//
// Feasibility note: at Skill 14 / Time 0 (pure depth 14) quiet middlegame
// positions can take ~a minute per move, so a drawn game can run for hours.
// For a statistically meaningful multi-game match, cap per-move time equally
// for BOTH engines with H2H_MOVETIME seconds (the MoveTime option drives a
// timed iterative-deepening search up to depth = skill, so fast positions
// still reach full depth while slow ones are bounded).  Both engines treat the
// MoveTime option as whole seconds.  Note: the current engine's `go movetime N`
// path is NOT used for this -- only the MoveTime option gives it a correct
// timed search; `go movetime` collapses to a depth-1 search.

use std::env;
use std::io::{BufRead, BufReader, Write};
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};

use tgf_core::{Game, GameRules, OutcomeKind, Workbench};
use tgf_mill::{MillGame, MillRules, MillUciCodec, MillVariantOptions};

/// One UCI engine subprocess.
struct Engine {
    child: Child,
    stdin: ChildStdin,
    out: BufReader<ChildStdout>,
    go: String,
    name: String,
}

impl Engine {
    fn spawn(
        program: &str,
        args: &[&str],
        go: &str,
        name: &str,
        skill: u32,
        move_time_secs: u32,
    ) -> Engine {
        let mut child = Command::new(program)
            .args(args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
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
            ("SkillLevel", skill.to_string()),
            ("DeveloperMode", "false".to_string()),
            ("DrawOnHumanExperience", "true".to_string()),
            ("Shuffling", "true".to_string()),
            ("Algorithm", "2".to_string()),
            ("MoveTime", move_time_secs.to_string()),
            ("UsePerfectDatabase", "false".to_string()),
        ] {
            e.cmd(&format!("setoption name {k} value {v}"));
        }
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

/// Play one full game between the `white` and `black` engines; returns the
/// outcome by board colour (`tgf-mill` is the referee).
fn play_game(white: &mut Engine, black: &mut Engine, max_plies: usize) -> (GameResult, usize) {
    let rules = MillRules::default();
    let game = MillGame::new(MillVariantOptions::default());
    let mut snap = rules.initial_state(&[]);
    let mut moves: Vec<String> = Vec::new();
    white.new_game();
    black.new_game();

    for ply in 0..max_plies {
        match rules.outcome(&snap).kind {
            OutcomeKind::Ongoing => {}
            OutcomeKind::Win(0) => return (GameResult::WhiteWin, ply),
            OutcomeKind::Win(1) => return (GameResult::BlackWin, ply),
            OutcomeKind::Draw => return (GameResult::Draw, ply),
            _ => return (GameResult::Unfinished, ply),
        }

        let stm = game.build_workbench(&snap).side_to_move();
        let engine = if stm == 0 { &mut *white } else { &mut *black };
        let Some(mv) = engine.best_move(&moves) else {
            eprintln!("  ! {} returned no move at ply {ply}", engine.name);
            return (GameResult::Unfinished, ply);
        };
        let Some(action) = MillUciCodec::decode_action(&snap, &mv) else {
            eprintln!(
                "  ! undecodable move `{mv}` from {} at ply {ply}",
                engine.name
            );
            return (GameResult::Unfinished, ply);
        };
        snap = rules.apply(&snap, action);
        moves.push(mv);
    }
    // Ply cap reached: both sides maneuvering -> score as a draw.
    (GameResult::Draw, max_plies)
}

/// Percentage of `num` out of `den` (0 when `den == 0`).
fn pct(num: f64, den: usize) -> f64 {
    if den == 0 {
        0.0
    } else {
        100.0 * num / den as f64
    }
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

/// Print the live standings table (White / Black / total rows) plus the
/// completed / remaining / progress footer.
fn print_standings(done: usize, total: usize, white: &[usize; 4], black: &[usize; 4]) {
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
    eprintln!(
        "Completed: {done}/{total} ({:.1}%)   Remaining: {}",
        pct(done as f64, total),
        total - done
    );
    if tot[3] > 0 {
        eprintln!(
            "(note: {} game(s) unfinished/aborted, excluded from rates)",
            tot[3]
        );
    }
}

#[test]
#[ignore = "head-to-head match vs master C++; set H2H_* and run with --ignored --nocapture"]
fn head_to_head_vs_master() {
    let current = env::var("H2H_CURRENT")
        .unwrap_or_else(|_| "D:/Repo/Sanmill/target/release/tgf.exe".to_string());
    let master = env::var("H2H_MASTER")
        .unwrap_or_else(|_| "D:/Repo/Sanmill-master/Sanmill/master_engine.exe".to_string());
    let games: usize = env::var("H2H_GAMES")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(20);
    let skill: u32 = env::var("H2H_SKILL")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(14);
    let max_plies: usize = env::var("H2H_MAX_PLIES")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(200);
    let go_current = env::var("H2H_GO_CURRENT").unwrap_or_else(|_| "go depth 0".to_string());
    let go_master = env::var("H2H_GO_MASTER").unwrap_or_else(|_| "go".to_string());
    let move_time: u32 = env::var("H2H_MOVETIME")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(0);

    // Mode: "vs" (current vs master, default), "self-current", "self-master".
    let mode = env::var("H2H_MODE").unwrap_or_else(|_| "vs".to_string());
    let total = games * 2;

    // Per-row tally [Win, Loss, Draw, Unfinished].  In "vs" mode the rows are
    // the current engine playing White / Black; in self-play they are the
    // White / Black side of the single engine under test.
    let mut white = [0usize; 4];
    let mut black = [0usize; 4];

    if mode == "self-current" || mode == "self-master" {
        let is_master = mode == "self-master";
        let label = if is_master { "master" } else { "current" };
        eprintln!(
            "Self-play: {label} vs {label}  (rows = board side)\n  skill={skill} movetime_s={move_time} shuffling=on algo=MTD(f) games={total} ply_cap={max_plies}"
        );
        // Two independent instances of the SAME engine (separate TTs), one
        // permanently White and one permanently Black, so the table directly
        // measures the game's first/second-player (White/Black) bias.
        let (mut ew, mut eb) = if is_master {
            (
                Engine::spawn(&master, &[], &go_master, "white", skill, move_time),
                Engine::spawn(&master, &[], &go_master, "black", skill, move_time),
            )
        } else {
            (
                Engine::spawn(&current, &["uci"], &go_current, "white", skill, move_time),
                Engine::spawn(&current, &["uci"], &go_current, "black", skill, move_time),
            )
        };
        for i in 0..total {
            let (res, plies) = play_game(&mut ew, &mut eb, max_plies);
            // A White win is a Black loss and vice versa, so every game updates
            // both rows; the White/Black Score% gap is the colour bias.
            match res {
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
            eprintln!();
            eprintln!(
                "Game {}/{total}: White vs Black -> {res:?} ({plies} plies)",
                i + 1
            );
            print_standings(i + 1, total, &white, &black);
        }
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
    } else {
        // vs mode: current vs master, alternating colours each game so the live
        // rates are not skewed by Black's structural edge until colours balance.
        eprintln!(
            "Head-to-head: current=`{current}` vs master=`{master}`  (rows = current's colour)\n  skill={skill} movetime_s={move_time} shuffling=on algo=MTD(f) games/color={games} ply_cap={max_plies}\n  go_current=`{go_current}` go_master=`{go_master}`"
        );
        let mut cur = Engine::spawn(&current, &["uci"], &go_current, "current", skill, move_time);
        let mut mas = Engine::spawn(&master, &[], &go_master, "master", skill, move_time);
        for i in 0..total {
            let current_white = i % 2 == 0;
            let (res, plies) = if current_white {
                play_game(&mut cur, &mut mas, max_plies)
            } else {
                play_game(&mut mas, &mut cur, max_plies)
            };
            // Map the board outcome to the current engine's row for its colour.
            let idx = match (res, current_white) {
                (GameResult::WhiteWin, true) | (GameResult::BlackWin, false) => 0, // current win
                (GameResult::BlackWin, true) | (GameResult::WhiteWin, false) => 1, // current loss
                (GameResult::Draw, _) => 2,
                (GameResult::Unfinished, _) => 3,
            };
            if current_white {
                white[idx] += 1;
            } else {
                black[idx] += 1;
            }
            eprintln!();
            eprintln!(
                "Game {}/{total}: current={} -> {} ({plies} plies)",
                i + 1,
                if current_white { "White" } else { "Black" },
                match idx {
                    0 => "current win",
                    1 => "current loss",
                    2 => "draw",
                    _ => "unfinished",
                }
            );
            print_standings(i + 1, total, &white, &black);
        }
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
}
