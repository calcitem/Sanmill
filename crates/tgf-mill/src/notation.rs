// SPDX-License-Identifier: AGPL-3.0-or-later
// Mill UCI-style notation codec.
//
// Mill encodes its moves as:
//
//   * Place  → bare label, e.g. `"a4"`
//   * Move   → `"<from>-<to>"`, e.g. `"a1-a4"`
//   * Remove → `"x<to>"`, e.g. `"xa4"`
//
// This file owns the canonical encoder / decoder so every consumer
// (CLI UCI adapter, FRB best-move events, transcripts) routes through
// the same code path.  The codec implements `tgf_core::NotationCodec`
// so generic tooling that needs to print a move can just call
// `codec.encode(snap, action)` without knowing about Mill at all.

use tgf_core::{Action, BoardTopology, GameStateSnapshot, NotationCodec};

use crate::rules::MillActionKind;
use crate::topology::shared_mill_topology;

/// Stateless Mill UCI codec singleton.
#[derive(Clone, Copy, Debug, Default)]
pub struct MillUciCodec;

impl MillUciCodec {
    /// Convenience: encode `action` without going through the trait
    /// (avoids the `&dyn` indirection at fixed call sites).
    pub fn encode_action(action: Action) -> String {
        let topo = shared_mill_topology(false);
        encode_with_topology(topo, action).unwrap_or_default()
    }

    /// Convenience: decode `text` against `snap` without going
    /// through the trait.  Mill's UCI format is position-independent,
    /// so `_snap` is unused but matches the trait signature.
    pub fn decode_action(_snap: &GameStateSnapshot, text: &str) -> Option<Action> {
        decode_with_topology(text)
    }
}

impl NotationCodec for MillUciCodec {
    fn dialect(&self) -> &str {
        "uci"
    }

    fn encode(&self, _snap: &GameStateSnapshot, action: Action) -> String {
        let topo = shared_mill_topology(false);
        encode_with_topology(topo, action).unwrap_or_default()
    }

    fn decode(&self, _snap: &GameStateSnapshot, text: &str) -> Option<Action> {
        decode_with_topology(text)
    }
}

fn encode_with_topology<T: BoardTopology>(topo: &T, action: Action) -> Option<String> {
    match action.kind_tag {
        x if x == MillActionKind::Place as i16 => {
            Some(topo.label_of(action.to_node as u16).to_owned())
        }
        x if x == MillActionKind::Move as i16 => Some(format!(
            "{}-{}",
            topo.label_of(action.from_node as u16),
            topo.label_of(action.to_node as u16)
        )),
        x if x == MillActionKind::Remove as i16 => {
            Some(format!("x{}", topo.label_of(action.to_node as u16)))
        }
        _ => None,
    }
}

fn decode_with_topology(text: &str) -> Option<Action> {
    let topo = shared_mill_topology(false);
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return None;
    }
    if let Some(rest) = trimmed
        .strip_prefix('x')
        .or_else(|| trimmed.strip_prefix('X'))
    {
        let to = topo.node_from_label(rest)?;
        return Some(Action {
            kind_tag: MillActionKind::Remove as i16,
            from_node: -1,
            to_node: to as i16,
            aux: -1,
            payload_bits: 0,
        });
    }
    if let Some((from, to)) = trimmed.split_once('-') {
        let f = topo.node_from_label(from)?;
        let t = topo.node_from_label(to)?;
        return Some(Action {
            kind_tag: MillActionKind::Move as i16,
            from_node: f as i16,
            to_node: t as i16,
            aux: -1,
            payload_bits: 0,
        });
    }
    let to = topo.node_from_label(trimmed)?;
    Some(Action {
        kind_tag: MillActionKind::Place as i16,
        from_node: -1,
        to_node: to as i16,
        aux: -1,
        payload_bits: 0,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use tgf_core::GameStateSnapshot;

    #[test]
    fn place_encodes_to_bare_label() {
        let topo = shared_mill_topology(false);
        let action = Action {
            kind_tag: MillActionKind::Place as i16,
            from_node: -1,
            to_node: topo.node_from_label("a7").unwrap() as i16,
            aux: -1,
            payload_bits: 0,
        };
        let snap = GameStateSnapshot::default();
        let text = MillUciCodec.encode(&snap, action);
        assert_eq!(text, "a7");
    }

    #[test]
    fn move_encodes_to_dash_separated_pair() {
        let topo = shared_mill_topology(false);
        let from = topo.node_from_label("a4").unwrap() as i16;
        let to = topo.node_from_label("a7").unwrap() as i16;
        let action = Action {
            kind_tag: MillActionKind::Move as i16,
            from_node: from,
            to_node: to,
            aux: -1,
            payload_bits: 0,
        };
        let snap = GameStateSnapshot::default();
        assert_eq!(MillUciCodec.encode(&snap, action), "a4-a7");
    }

    #[test]
    fn remove_encodes_to_x_prefixed_label() {
        let topo = shared_mill_topology(false);
        let to = topo.node_from_label("a4").unwrap() as i16;
        let action = Action {
            kind_tag: MillActionKind::Remove as i16,
            from_node: -1,
            to_node: to,
            aux: -1,
            payload_bits: 0,
        };
        let snap = GameStateSnapshot::default();
        assert_eq!(MillUciCodec.encode(&snap, action), "xa4");
    }

    #[test]
    fn decode_round_trips_each_kind() {
        let snap = GameStateSnapshot::default();
        // Place
        let a = MillUciCodec.decode(&snap, "a7").unwrap();
        assert_eq!(a.kind_tag, MillActionKind::Place as i16);
        // Move
        let b = MillUciCodec.decode(&snap, "a4-a7").unwrap();
        assert_eq!(b.kind_tag, MillActionKind::Move as i16);
        // Remove
        let c = MillUciCodec.decode(&snap, "xa4").unwrap();
        assert_eq!(c.kind_tag, MillActionKind::Remove as i16);
    }

    #[test]
    fn decode_rejects_unknown_labels() {
        let snap = GameStateSnapshot::default();
        assert!(MillUciCodec.decode(&snap, "zz").is_none());
        assert!(MillUciCodec.decode(&snap, "a4-").is_none());
        assert!(MillUciCodec.decode(&snap, "").is_none());
    }
}
