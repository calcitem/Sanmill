// SPDX-License-Identifier: AGPL-3.0-or-later
// Top-level command parser for tgf-cli.

use crate::game_adapter::{CliGame, CommandId};
use crate::games;

pub(crate) fn run(args: impl IntoIterator<Item = String>) {
    let args = args.into_iter().collect::<Vec<_>>();
    if args.is_empty() || is_help(&args[0]) {
        print_help();
        return;
    }

    let Some(dispatch) = resolve(&args) else {
        eprintln!("unknown command or game: {}", args[0]);
        print_help();
        return;
    };

    dispatch.game.run(dispatch.command, dispatch.args);
}

struct Dispatch<'a> {
    game: &'static dyn CliGame,
    command: CommandId,
    args: &'a [String],
}

fn resolve(args: &[String]) -> Option<Dispatch<'_>> {
    if args.first().map(String::as_str) == Some("--game") {
        let game = games::find(args.get(1)?.as_str())?;
        let command = game.command_for(args.get(2)?.as_str())?;
        return Some(Dispatch {
            game,
            command,
            args: &args[3..],
        });
    }

    if let Some(game) = games::find(args[0].as_str()) {
        let command = game.command_for(args.get(1)?.as_str())?;
        return Some(Dispatch {
            game,
            command,
            args: &args[2..],
        });
    }

    let game = games::default_game();
    let command = game.command_for(args[0].as_str())?;
    Some(Dispatch {
        game,
        command,
        args: &args[1..],
    })
}

fn print_help() {
    let default_game = games::default_game();

    eprintln!("Usage:");
    for command in default_game.commands() {
        eprintln!(
            "  tgf {:<10} # {} ({})",
            command.name,
            command.description,
            default_game.display_name()
        );
    }
    eprintln!("  tgf <game> <command> [args]");
    eprintln!("  tgf --game <game> <command> [args]");
    eprintln!();
    eprintln!("Games:");
    for game in games::all() {
        let aliases = game.aliases();
        if aliases.is_empty() {
            eprintln!("  {:<10} {}", game.id(), game.display_name());
        } else {
            eprintln!(
                "  {:<10} {} (aliases: {})",
                game.id(),
                game.display_name(),
                aliases.join(", ")
            );
        }
        for command in game.commands() {
            eprintln!("    {:<10} {}", command.name, command.description);
        }
    }
}

fn is_help(token: &str) -> bool {
    matches!(token, "--help" | "-h" | "help")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(values: &[&str]) -> Vec<String> {
        values.iter().map(|value| value.to_string()).collect()
    }

    #[test]
    fn default_game_commands_remain_backward_compatible() {
        let argv = args(&["uci"]);
        let dispatch = resolve(&argv).expect("dispatch");

        assert_eq!(dispatch.game.id(), "mill");
        assert_eq!(dispatch.command.as_str(), "uci");
        assert!(dispatch.args.is_empty());
    }

    #[test]
    fn explicit_game_command_routes_to_registered_game() {
        let argv = args(&["mill", "selfplay", "--depth", "2"]);
        let dispatch = resolve(&argv).expect("dispatch");

        assert_eq!(dispatch.game.id(), "mill");
        assert_eq!(dispatch.command.as_str(), "selfplay");
        let expected = args(&["--depth", "2"]);
        assert_eq!(dispatch.args, expected.as_slice());
    }

    #[test]
    fn game_flag_routes_to_registered_game() {
        let argv = args(&["--game", "sanmill", "bench"]);
        let dispatch = resolve(&argv).expect("dispatch");

        assert_eq!(dispatch.game.id(), "mill");
        assert_eq!(dispatch.command.as_str(), "bench");
    }
}
