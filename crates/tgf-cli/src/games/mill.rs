// SPDX-License-Identifier: GPL-3.0-or-later
// Mill command registration for tgf-cli.

use crate::game_adapter::{CliGame, CommandId, CommandSpec};

pub(crate) struct MillCli;

pub(crate) static MILL_GAME: MillCli = MillCli;

const CMD_UCI: CommandId = CommandId::new("uci");
const CMD_BENCH: CommandId = CommandId::new("bench");
const CMD_SELFPLAY: CommandId = CommandId::new("selfplay");

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
