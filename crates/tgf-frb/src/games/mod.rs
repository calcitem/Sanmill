// SPDX-License-Identifier: GPL-3.0-or-later
// Per-game FRB adapter modules.  Each submodule exposes the DTOs,
// helpers, and search spawn functions the public FRB entry points
// (`crate::api::*`) delegate to.  Adding a new game is now a matter of
// dropping a new submodule here plus calling
// `crate::game_registry::register_game(...)` (or relying on the
// default seeding if the game crate ships with the framework).

pub(crate) mod mill;
pub(crate) mod othello;
