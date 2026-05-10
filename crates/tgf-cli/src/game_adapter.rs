// SPDX-License-Identifier: GPL-3.0-or-later
// Shared CLI registration contract for game-specific front-ends.
//
// Each concrete game owns its UCI dialect, benchmark shape, and optional
// maintenance commands.  The top-level binary only knows how to discover a
// registered game and route a command to it.

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct CommandId(&'static str);

impl CommandId {
    pub(crate) const fn new(value: &'static str) -> Self {
        Self(value)
    }

    pub(crate) fn as_str(self) -> &'static str {
        self.0
    }
}

#[derive(Clone, Copy, Debug)]
pub(crate) struct CommandSpec {
    pub(crate) id: CommandId,
    pub(crate) name: &'static str,
    pub(crate) aliases: &'static [&'static str],
    pub(crate) description: &'static str,
}

impl CommandSpec {
    pub(crate) fn matches(self, token: &str) -> bool {
        self.name.eq_ignore_ascii_case(token)
            || self
                .aliases
                .iter()
                .any(|alias| alias.eq_ignore_ascii_case(token))
    }
}

pub(crate) trait CliGame: Sync {
    fn id(&self) -> &'static str;

    fn display_name(&self) -> &'static str;

    fn aliases(&self) -> &'static [&'static str] {
        &[]
    }

    fn commands(&self) -> &'static [CommandSpec];

    fn run(&self, command: CommandId, args: &[String]);

    fn matches_game(&self, token: &str) -> bool {
        self.id().eq_ignore_ascii_case(token)
            || self
                .aliases()
                .iter()
                .any(|alias| alias.eq_ignore_ascii_case(token))
    }

    fn command_for(&self, token: &str) -> Option<CommandId> {
        self.commands()
            .iter()
            .find(|spec| spec.matches(token))
            .map(|spec| spec.id)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct ToyGame;

    const CMD_UCI: CommandId = CommandId::new("uci");

    const TOY_COMMANDS: &[CommandSpec] = &[CommandSpec {
        id: CMD_UCI,
        name: "uci",
        aliases: &["xboard"],
        description: "run protocol loop",
    }];

    impl CliGame for ToyGame {
        fn id(&self) -> &'static str {
            "toy"
        }

        fn display_name(&self) -> &'static str {
            "Toy"
        }

        fn aliases(&self) -> &'static [&'static str] {
            &["sample"]
        }

        fn commands(&self) -> &'static [CommandSpec] {
            TOY_COMMANDS
        }

        fn run(&self, _command: CommandId, _args: &[String]) {}
    }

    #[test]
    fn game_aliases_are_case_insensitive() {
        let game = ToyGame;

        assert!(game.matches_game("TOY"));
        assert!(game.matches_game("Sample"));
        assert!(!game.matches_game("other"));
    }

    #[test]
    fn command_aliases_are_case_insensitive() {
        let game = ToyGame;

        assert_eq!(game.command_for("UCI"), Some(CMD_UCI));
        assert_eq!(game.command_for("xBoard"), Some(CMD_UCI));
        assert_eq!(game.command_for("bench"), None);
    }
}
