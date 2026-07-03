// SPDX-License-Identifier: AGPL-3.0-or-later
// Mill command registration for tgf-cli.

use crate::game_adapter::{CliGame, CommandId, CommandSpec};

pub(super) struct MillCli;

pub(super) static MILL_GAME: MillCli = MillCli;

const CMD_UCI: CommandId = CommandId::new("uci");
const CMD_BENCH: CommandId = CommandId::new("bench");
const CMD_SELFPLAY: CommandId = CommandId::new("selfplay");
const CMD_TUNE_GEN: CommandId = CommandId::new("tune-gen");
const CMD_TUNE_GEN_HUMAN: CommandId = CommandId::new("tune-gen-human");
const CMD_TUNE_LABEL: CommandId = CommandId::new("tune-label");
const CMD_TUNE_STATS: CommandId = CommandId::new("tune-stats");
const CMD_TUNE_FIT: CommandId = CommandId::new("tune-fit");
const CMD_PUZZLE_GEN: CommandId = CommandId::new("puzzle-gen");
const CMD_MINE: CommandId = CommandId::new("mine");
const CMD_MINE_ENDGAME: CommandId = CommandId::new("mine-endgame");
const CMD_PATCH_PACK: CommandId = CommandId::new("patch-pack");
const CMD_ARENA: CommandId = CommandId::new("arena");

const MILL_COMMANDS: &[CommandSpec] = &[
    CommandSpec {
        id: CMD_UCI,
        name: "uci",
        aliases: &[],
        description: "run a UCI-like loop backed by Rust Mill",
    },
    CommandSpec {
        id: CMD_BENCH,
        name: "bench",
        aliases: &["benchmark"],
        description: "emit perf_baseline-compatible TOML",
    },
    CommandSpec {
        id: CMD_SELFPLAY,
        name: "selfplay",
        aliases: &["self-play"],
        description: "run a deterministic self-play regression harness",
    },
    CommandSpec {
        id: CMD_TUNE_GEN,
        name: "tune-gen",
        aliases: &["tune gen"],
        description: "sample quiet positions from self-play for eval tuning",
    },
    CommandSpec {
        id: CMD_TUNE_GEN_HUMAN,
        name: "tune-gen-human",
        aliases: &["tune gen-human"],
        description: "sample positions from an NMM_LLM human game database",
    },
    CommandSpec {
        id: CMD_TUNE_LABEL,
        name: "tune-label",
        aliases: &["tune label"],
        description: "annotate positions with Perfect DB WDL labels",
    },
    CommandSpec {
        id: CMD_TUNE_STATS,
        name: "tune-stats",
        aliases: &["tune stats"],
        description: "summarize tuning labels by phase",
    },
    CommandSpec {
        id: CMD_TUNE_FIT,
        name: "tune-fit",
        aliases: &["tune fit"],
        description: "fit eval weights via Texel logistic regression",
    },
    CommandSpec {
        id: CMD_PUZZLE_GEN,
        name: "puzzle-gen",
        aliases: &["puzzle gen"],
        description: "generate forced-win puzzles from a Perfect DB",
    },
    CommandSpec {
        id: CMD_MINE,
        name: "mine",
        aliases: &[],
        description: "mine engine-blunder positions against a Perfect DB",
    },
    CommandSpec {
        id: CMD_MINE_ENDGAME,
        name: "mine-endgame",
        aliases: &["mine endgame"],
        description: "exhaustively mine every position in small endgame sectors",
    },
    CommandSpec {
        id: CMD_PATCH_PACK,
        name: "patch-pack",
        aliases: &["patch pack"],
        description: "pack mined JSONL entries into a compact patch file",
    },
    CommandSpec {
        id: CMD_ARENA,
        name: "arena",
        aliases: &[],
        description: "play full-rules engine-vs-Perfect-DB games (patched vs unpatched KPI)",
    },
];

impl CliGame for MillCli {
    fn id(&self) -> &'static str {
        "mill"
    }

    fn display_name(&self) -> &'static str {
        "Mill"
    }

    fn aliases(&self) -> &'static [&'static str] {
        &["nine-mens-morris", "sanmill"]
    }

    fn commands(&self) -> &'static [CommandSpec] {
        MILL_COMMANDS
    }

    fn run(&self, command: CommandId, args: &[String]) {
        match command {
            CMD_BENCH => {
                warn_unused_args("bench", args);
                crate::mill_uci::print_benchmark_toml();
            }
            CMD_SELFPLAY => crate::selfplay::run_selfplay(args),
            CMD_TUNE_GEN => crate::mill_tune::run_gen(args),
            CMD_TUNE_GEN_HUMAN => crate::mill_tune::run_gen_human(args),
            CMD_TUNE_LABEL => crate::mill_tune::run_label(args),
            CMD_TUNE_STATS => crate::mill_tune::run_stats(args),
            CMD_TUNE_FIT => crate::mill_tune::run_fit(args),
            CMD_PUZZLE_GEN => crate::mill_puzzle::run_puzzle_gen(args),
            CMD_MINE => crate::mill_mine::run_mill_mine(args),
            CMD_MINE_ENDGAME => crate::mill_endgame::run_mill_endgame(args),
            CMD_PATCH_PACK => crate::mill_pack::run_patch_pack(args),
            CMD_ARENA => crate::mill_arena::run_mill_arena(args),
            CMD_UCI => {
                warn_unused_args("uci", args);
                crate::mill_uci::run_uci_loop();
            }
            _ => unreachable!(
                "command `{}` must come from MillCli::commands",
                command.as_str()
            ),
        }
    }
}

fn warn_unused_args(command: &str, args: &[String]) {
    if !args.is_empty() {
        eprintln!(
            "# warning: ignoring extra {command} args: {}",
            args.join(" ")
        );
    }
}
