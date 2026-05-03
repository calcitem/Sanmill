// SPDX-License-Identifier: GPL-3.0-or-later
// Mill-specific notation codec for the FRB layer.
//
// Mill bestMove events ship the full UCI move string ("a4", "a1-a4",
// "xa4") through `EngineEvent::reason`.  Keeping the codec here means
// `crate::api::core` / `engine_event` never need to know about
// Mill topology or action kinds.

use tgf_core::{Action, BoardTopology};
use tgf_mill::{default_mill_topology, MillActionKind};

/// Convert a Mill `Action` to its UCI move string.
///
/// * Place  → bare label, e.g. `"a4"`
/// * Move   → `"<from>-<to>"`, e.g. `"a1-a4"`
/// * Remove → `"x<to>"`, e.g. `"xa4"`
///
/// Returns an empty string for `Action::NONE` or any unknown kind so the
/// caller can splice the result directly into log messages without
/// branching.
pub(crate) fn action_to_uci_str(action: Action) -> String {
    let topo = default_mill_topology();
    match action.kind_tag {
        x if x == MillActionKind::Place as i16 => topo.label_of(action.to_node as u16).to_owned(),
        x if x == MillActionKind::Move as i16 => format!(
            "{}-{}",
            topo.label_of(action.from_node as u16),
            topo.label_of(action.to_node as u16)
        ),
        x if x == MillActionKind::Remove as i16 => {
            format!("x{}", topo.label_of(action.to_node as u16))
        }
        _ => String::new(),
    }
}
