// SPDX-License-Identifier: AGPL-3.0-or-later
// Ignored audit harness for comparing named Mill rule-set self-play against
// the legacy master engine. This intentionally spawns UCI binaries so the
// regular test suite stays hermetic and fast.

use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::mpsc::{Receiver, channel};
use std::time::Duration;

#[derive(Clone, Copy)]
struct AuditCase {
    name: &'static str,
    options: &'static [(&'static str, &'static str)],
}

struct UciEngine {
    command: String,
    child: Child,
    stdin: ChildStdin,
    stdout: Receiver<String>,
    terminal_phase: i32,
}

impl UciEngine {
    fn spawn(command: String, terminal_phase: i32) -> Self {
        let mut parts = command.split_whitespace();
        let executable = parts.next().expect("UCI command must not be empty");
        let args = parts.collect::<Vec<_>>();
        let mut child = Command::new(executable)
            .args(args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap_or_else(|err| panic!("failed to spawn {command}: {err}"));
        let stdin = child.stdin.take().expect("UCI child must expose stdin");
        let stdout = child.stdout.take().expect("UCI child must expose stdout");
        let (tx, rx) = channel();
        std::thread::spawn(move || {
            let reader = BufReader::new(stdout);
            for line in reader.lines() {
                if tx.send(line.expect("UCI stdout line must decode")).is_err() {
                    break;
                }
            }
        });
        Self {
            command,
            child,
            stdin,
            stdout: rx,
            terminal_phase,
        }
    }

    fn send(&mut self, line: &str) {
        writeln!(self.stdin, "{line}").expect("UCI stdin write must succeed");
        self.stdin.flush().expect("UCI stdin flush must succeed");
    }

    fn read_until(&self, token: &str) -> String {
        let timeout = Duration::from_secs(180);
        loop {
            let line = self.stdout.recv_timeout(timeout).unwrap_or_else(|err| {
                panic!("{} timed out waiting for {token}: {err}", self.command)
            });
            if line.contains(token) {
                return line;
            }
        }
    }

    fn initialize(&mut self, options: &[(&str, &str)]) {
        self.send("uci");
        self.read_until("uciok");
        for (name, value) in BASE_OPTIONS.iter().chain(options.iter()) {
            self.send(&format!("setoption name {name} value {value}"));
        }
        self.send("isready");
        self.read_until("readyok");
        self.send("ucinewgame");
    }

    fn bestmove(&mut self, moves: &[String]) -> (String, String) {
        let mut position = String::from("position startpos");
        if !moves.is_empty() {
            position.push_str(" moves ");
            position.push_str(&moves.join(" "));
        }
        self.send(&position);
        self.send("go");
        let raw = self.read_until("bestmove");
        let tokens = raw.split_whitespace().collect::<Vec<_>>();
        let Some(bestmove_idx) = tokens.iter().position(|token| *token == "bestmove") else {
            return (String::new(), raw);
        };
        let Some(bestmove) = tokens.get(bestmove_idx + 1) else {
            return (String::new(), raw);
        };
        if bestmove.is_empty() || matches!(*bestmove, "(none)" | "none" | "0000") {
            return (String::new(), raw);
        }
        ((*bestmove).to_owned(), raw)
    }

    fn is_terminal(&mut self, moves: &[String]) -> (bool, String) {
        let mut position = String::from("position startpos");
        if !moves.is_empty() {
            position.push_str(" moves ");
            position.push_str(&moves.join(" "));
        }
        self.send(&position);
        self.send("evaldecomp");
        let raw = self.read_until("evaldecomp");
        let terminal = raw
            .split_whitespace()
            .find_map(|token| token.strip_prefix("phase="))
            .map(|phase| {
                phase
                    .parse::<i32>()
                    .expect("evaldecomp phase must be numeric")
                    == self.terminal_phase
            })
            .unwrap_or(false);
        (terminal, raw)
    }
}

impl Drop for UciEngine {
    fn drop(&mut self) {
        self.send("quit");
        let _ = self.child.wait();
    }
}

const BASE_OPTIONS: &[(&str, &str)] = &[
    ("SkillLevel", "2"),
    ("MoveTime", "0"),
    ("AiIsLazy", "false"),
    ("IDSEnabled", "false"),
    ("DepthExtension", "true"),
    ("Shuffling", "false"),
    ("UseLazySmp", "false"),
    ("Algorithm", "2"),
    ("DrawOnHumanExperience", "true"),
    ("UsePerfectDatabase", "false"),
    ("DeveloperMode", "false"),
    ("MaxQuiescenceDepth", "0"),
    ("NMoveRule", "20"),
    ("EndgameNMoveRule", "20"),
];

const CANONICAL_PRESETS: &[AuditCase] = &[
    AuditCase {
        name: "preset_0_nine_mens_morris",
        options: &[],
    },
    AuditCase {
        name: "preset_1_twelve_mens_morris",
        options: &[("PiecesCount", "12"), ("HasDiagonalLines", "true")],
    },
    AuditCase {
        name: "preset_2_dooz",
        options: &[
            ("PiecesCount", "12"),
            ("HasDiagonalLines", "true"),
            ("MillFormationActionInPlacingPhase", "1"),
        ],
    },
    AuditCase {
        name: "preset_3_morabaraba",
        options: &[
            ("PiecesCount", "12"),
            ("HasDiagonalLines", "true"),
            ("MayRemoveMultiple", "true"),
        ],
    },
    AuditCase {
        name: "preset_4_russian_mill",
        options: &[("OneTimeUseMill", "true")],
    },
    AuditCase {
        name: "preset_5_lasker_morris",
        options: &[("PiecesCount", "10"), ("MayMoveInPlacingPhase", "true")],
    },
    AuditCase {
        name: "preset_6_cheng_san_qi",
        options: &[("MayFly", "false")],
    },
    AuditCase {
        name: "preset_7_da_san_qi",
        options: &[
            ("PiecesCount", "12"),
            ("HasDiagonalLines", "true"),
            ("MillFormationActionInPlacingPhase", "4"),
            ("IsDefenderMoveFirst", "true"),
            ("MayRemoveFromMillsAlways", "true"),
            ("MayFly", "false"),
        ],
    },
    AuditCase {
        name: "preset_8_zhi_qi",
        options: &[
            ("PiecesCount", "12"),
            ("HasDiagonalLines", "true"),
            ("BoardFullAction", "1"),
            ("StalemateAction", "2"),
        ],
    },
    AuditCase {
        name: "preset_9_el_filja",
        options: &[
            ("PiecesCount", "12"),
            ("MillFormationActionInPlacingPhase", "5"),
            ("MayRemoveFromMillsAlways", "true"),
            ("BoardFullAction", "1"),
            ("MayFly", "false"),
        ],
    },
    AuditCase {
        name: "preset_10_experimental",
        options: &[
            ("PiecesCount", "12"),
            ("HasDiagonalLines", "true"),
            ("IsDefenderMoveFirst", "true"),
            ("MayRemoveFromMillsAlways", "true"),
            ("BoardFullAction", "2"),
            ("MayFly", "false"),
        ],
    },
];

const FLUTTER_RULE_SETS: &[AuditCase] = &[
    AuditCase {
        name: "ruleset_nine_mens_morris",
        options: &[],
    },
    AuditCase {
        name: "ruleset_twelve_mens_morris",
        options: &[("PiecesCount", "12"), ("HasDiagonalLines", "true")],
    },
    AuditCase {
        name: "ruleset_morabaraba",
        options: &[
            ("PiecesCount", "12"),
            ("HasDiagonalLines", "true"),
            ("BoardFullAction", "4"),
            ("EndgameNMoveRule", "10"),
            ("RestrictRepeatedMillsFormation", "true"),
        ],
    },
    AuditCase {
        name: "ruleset_dooz",
        options: &[
            ("PiecesCount", "12"),
            ("HasDiagonalLines", "true"),
            ("MillFormationActionInPlacingPhase", "1"),
            ("BoardFullAction", "3"),
            ("MayRemoveFromMillsAlways", "true"),
        ],
    },
    AuditCase {
        name: "ruleset_lasker_morris",
        options: &[("PiecesCount", "10"), ("MayMoveInPlacingPhase", "true")],
    },
    AuditCase {
        name: "ruleset_one_time_mill",
        options: &[
            ("OneTimeUseMill", "true"),
            ("MayRemoveFromMillsAlways", "true"),
        ],
    },
    AuditCase {
        name: "ruleset_cham_gonu",
        options: &[
            ("PiecesCount", "12"),
            ("HasDiagonalLines", "true"),
            ("MillFormationActionInPlacingPhase", "4"),
            ("MayFly", "false"),
            ("MayRemoveFromMillsAlways", "true"),
        ],
    },
    AuditCase {
        name: "ruleset_zhi_qi",
        options: &[
            ("PiecesCount", "12"),
            ("HasDiagonalLines", "true"),
            ("MillFormationActionInPlacingPhase", "4"),
            ("BoardFullAction", "1"),
            ("MayFly", "false"),
            ("MayRemoveFromMillsAlways", "true"),
        ],
    },
    AuditCase {
        name: "ruleset_cheng_san_qi",
        options: &[
            ("MillFormationActionInPlacingPhase", "4"),
            ("MayFly", "false"),
        ],
    },
    AuditCase {
        name: "ruleset_da_san_qi",
        options: &[
            ("PiecesCount", "12"),
            ("HasDiagonalLines", "true"),
            ("MillFormationActionInPlacingPhase", "4"),
            ("BoardFullAction", "0"),
            ("IsDefenderMoveFirst", "true"),
            ("MayFly", "false"),
            ("MayRemoveFromMillsAlways", "true"),
            ("MayRemoveMultiple", "true"),
        ],
    },
    AuditCase {
        name: "ruleset_mul_mulan",
        options: &[
            ("PiecesCount", "9"),
            ("HasDiagonalLines", "true"),
            ("MayFly", "false"),
            ("MayRemoveFromMillsAlways", "true"),
            ("InterventionCaptureEnabled", "true"),
        ],
    },
    AuditCase {
        name: "ruleset_nerenchi",
        options: &[
            ("PiecesCount", "12"),
            ("HasDiagonalLines", "true"),
            ("IsDefenderMoveFirst", "true"),
            ("MayRemoveFromMillsAlways", "true"),
        ],
    },
    AuditCase {
        name: "ruleset_el_filja",
        options: &[
            ("PiecesCount", "12"),
            ("MillFormationActionInPlacingPhase", "5"),
            ("BoardFullAction", "1"),
            ("MayFly", "false"),
            ("MayRemoveFromMillsAlways", "true"),
        ],
    },
];

fn default_current_command() -> String {
    let binary = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../target/release/tgf")
        .canonicalize()
        .expect("build target/release/tgf before running this ignored audit");
    format!("{} uci", binary.display())
}

fn default_master_command() -> String {
    let home = std::env::var("HOME").expect("HOME must be set");
    format!("{home}/Sanmill-master/master_engine")
}

fn compare_case(case: &AuditCase) {
    let current_cmd =
        std::env::var("SANMILL_CURRENT_UCI").unwrap_or_else(|_| default_current_command());
    let master_cmd =
        std::env::var("SANMILL_MASTER_UCI").unwrap_or_else(|_| default_master_command());
    let mut current = UciEngine::spawn(current_cmd, 3);
    let mut master = UciEngine::spawn(master_cmd, 4);
    current.initialize(case.options);
    master.initialize(case.options);

    let mut current_moves = Vec::new();
    let mut master_moves = Vec::new();
    for ply in 0..60 {
        let (current_move, current_raw) = current.bestmove(&current_moves);
        let (master_move, master_raw) = master.bestmove(&master_moves);
        if current_move != master_move {
            let (current_terminal, current_eval) = current.is_terminal(&current_moves);
            let (master_terminal, master_eval) = master.is_terminal(&master_moves);
            assert!(
                current_terminal && master_terminal,
                "{} diverged at ply {ply}: current={current_move:?} master={master_move:?}; \
                 current_raw={current_raw:?}; master_raw={master_raw:?}; \
                 current_eval={current_eval:?}; master_eval={master_eval:?}; \
                 current_moves={}; master_moves={}",
                case.name,
                current_moves.join(" "),
                master_moves.join(" ")
            );
            eprintln!("{} terminal parity after {ply} plies", case.name);
            return;
        }
        if current_move.is_empty() {
            eprintln!("{} no-move parity after {ply} plies", case.name);
            return;
        }
        if current_move == "draw" {
            eprintln!("{} draw parity after {ply} plies", case.name);
            return;
        }
        current_moves.push(current_move);
        master_moves.push(master_move);
    }
    eprintln!("{} matched 60 plies", case.name);
}

#[test]
#[ignore = "requires target/release/tgf and ~/Sanmill-master/master_engine"]
fn canonical_rule_presets_match_master_selfplay() {
    for case in CANONICAL_PRESETS {
        compare_case(case);
    }
}

#[test]
#[ignore = "requires target/release/tgf and ~/Sanmill-master/master_engine"]
fn flutter_rule_sets_match_master_selfplay() {
    for case in FLUTTER_RULE_SETS {
        compare_case(case);
    }
}
