// SPDX-License-Identifier: GPL-3.0-or-later
// Head-to-head strength match: the current-branch engine vs the master C++
// engine.  Both engines are driven as UCI subprocesses; `tgf-mill` is the
// authoritative referee (move application + outcome adjudication), so neither
// engine's internal rules can bias the result.
//
// Configuration matches the requested scenario: Skill 14, MoveTime 0 (fixed
// depth), Shuffling on (random tie-break -> varied games), MTD(f) (Algorithm
// 2), DeveloperMode off, DrawOnHumanExperience on, Perfect DB off.  The current
// engine plays GAMES games as White and GAMES games as Black; results are
// tallied from the current engine's perspective.
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
//
// Feasibility note: at Skill 14 / Time 0 (pure depth 14) quiet middlegame
// positions can take ~minute per move, so a drawn game can run for hours.  For
// a statistically meaningful multi-game match, add an equal per-move cap to
// BOTH engines, e.g. a 3 s/move time control:
//   H2H_GO_CURRENT="go movetime 3000" H2H_GO_MASTER="go movetime 3000"
// (both engines are capped identically, so the comparison stays fair).

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
    fn spawn(program: &str, args: &[&str], go: &str, name: &str, skill: u32) -> Engine {
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
            ("MoveTime", "0".to_string()),
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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Res {
    CurrentWin,
    MasterWin,
    Draw,
    Unfinished,
}

/// Play one full game; `white`/`black` are the engines for each side and
/// `current_is_white` says which role the current-branch engine holds.
fn play_game(
    white: &mut Engine,
    black: &mut Engine,
    current_is_white: bool,
    max_plies: usize,
) -> (Res, usize) {
    let rules = MillRules::default();
    let game = MillGame::new(MillVariantOptions::default());
    let mut snap = rules.initial_state(&[]);
    let mut moves: Vec<String> = Vec::new();
    white.new_game();
    black.new_game();

    for ply in 0..max_plies {
        match rules.outcome(&snap).kind {
            OutcomeKind::Ongoing => {}
            OutcomeKind::Win(0) => {
                return (
                    if current_is_white {
                        Res::CurrentWin
                    } else {
                        Res::MasterWin
                    },
                    ply,
                );
            }
            OutcomeKind::Win(1) => {
                return (
                    if current_is_white {
                        Res::MasterWin
                    } else {
                        Res::CurrentWin
                    },
                    ply,
                );
            }
            OutcomeKind::Draw => return (Res::Draw, ply),
            _ => return (Res::Unfinished, ply),
        }

        let stm = game.build_workbench(&snap).side_to_move();
        let engine = if stm == 0 { &mut *white } else { &mut *black };
        let Some(mv) = engine.best_move(&moves) else {
            eprintln!("  ! {} returned no move at ply {ply}", engine.name);
            return (Res::Unfinished, ply);
        };
        let Some(action) = MillUciCodec::decode_action(&snap, &mv) else {
            eprintln!(
                "  ! undecodable move `{mv}` from {} at ply {ply}",
                engine.name
            );
            return (Res::Unfinished, ply);
        };
        snap = rules.apply(&snap, action);
        moves.push(mv);
    }
    // Ply cap reached: both sides maneuvering -> score as a draw.
    (Res::Draw, max_plies)
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

    eprintln!(
        "Head-to-head: current=`{current}` vs master=`{master}`\n  skill={skill} shuffling=on algo=MTD(f) games/color={games} ply_cap={max_plies}\n  go_current=`{go_current}` go_master=`{go_master}`"
    );

    let mut cur = Engine::spawn(&current, &["uci"], &go_current, "current", skill);
    let mut mas = Engine::spawn(&master, &[], &go_master, "master", skill);

    // [CurrentWin, MasterWin, Draw, Unfinished]
    let mut white = [0usize; 4];
    let mut black = [0usize; 4];
    let bucket = |r: Res| match r {
        Res::CurrentWin => 0,
        Res::MasterWin => 1,
        Res::Draw => 2,
        Res::Unfinished => 3,
    };

    eprintln!("--- current as WHITE ---");
    for g in 0..games {
        let (res, plies) = play_game(&mut cur, &mut mas, true, max_plies);
        white[bucket(res)] += 1;
        eprintln!("  W g{g}: {res:?} ({plies} plies)");
    }
    eprintln!("--- current as BLACK ---");
    for g in 0..games {
        let (res, plies) = play_game(&mut mas, &mut cur, false, max_plies);
        black[bucket(res)] += 1;
        eprintln!("  B g{g}: {res:?} ({plies} plies)");
    }

    let report = |tag: &str, s: &[usize; 4]| {
        let total = (s[0] + s[1] + s[2] + s[3]).max(1);
        eprintln!(
            "{tag}: current_win={} loss={} draw={} unfinished={}  draw_rate={:.1}%  current_score={:.1}/{}",
            s[0],
            s[1],
            s[2],
            s[3],
            100.0 * s[2] as f64 / total as f64,
            s[0] as f64 + 0.5 * s[2] as f64,
            total
        );
    };
    eprintln!("================ RESULTS ================");
    report("current WHITE", &white);
    report("current BLACK", &black);
    let tot = [
        white[0] + black[0],
        white[1] + black[1],
        white[2] + black[2],
        white[3] + black[3],
    ];
    report("TOTAL        ", &tot);
    let net = tot[0] as i64 - tot[1] as i64;
    eprintln!(
        "NET (current_wins - current_losses) = {net:+}  (positive => current stronger than master)"
    );
}
