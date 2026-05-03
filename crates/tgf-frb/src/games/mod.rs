// SPDX-License-Identifier: GPL-3.0-or-later
// Per-game FRB adapter modules.  Each submodule exposes the DTOs,
// helpers, and search spawn functions the public FRB entry points
// (`crate::api::*`) delegate to.  Adding a new game is now a matter of
// dropping a new submodule here plus one entry in
// `crate::api::kernel::build_rules_default`.

pub(crate) mod mill;
pub(crate) mod othello;
