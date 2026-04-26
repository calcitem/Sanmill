// SPDX-License-Identifier: GPL-3.0-or-later
// Phase 1 scaffold – BoardTopology trait.
// Full implementation (MillTopology) introduced in Phase 3.

/// A point on the board in unit-square coordinates [0,1]×[0,1].
#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct UnitPoint {
    pub x: f32,
    pub y: f32,
}

/// An undirected edge between two node ids.
#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct Edge {
    pub a: u16,
    pub b: u16,
}

/// A named set of board nodes (hand, capture pile, scoring area, …).
#[derive(Clone, Debug)]
pub struct Zone {
    /// Stable identifier, e.g. "hand_white", "capture_pile".
    pub id:       String,
    pub node_ids: Vec<u16>,
}

/// Game-specific visual decoration rendered below the pieces.
#[derive(Clone, Debug)]
pub enum DecorationKind {
    Polyline { points: Vec<UnitPoint> },
    Polygon  { points: Vec<UnitPoint> },
    Circle   { center: UnitPoint, radius: f32 },
    Text     { center: UnitPoint, text: String },
}

/// A visual element the Flutter shell draws before placing pieces.
#[derive(Clone, Debug)]
pub struct Decoration {
    pub kind:  DecorationKind,
    /// Stable token the shell maps to its active theme, e.g. "outer_ring".
    pub style: String,
}

/// Read-only board topology.  The single source of truth for board geometry;
/// the Flutter shell consumes this once via FRB at session start and never
/// hard-codes coordinates again.
///
/// Implementations are pure value objects with no dependency on rules or
/// game state.  They must be `Send + Sync` because the FRB layer hands out
/// an `Arc<dyn BoardTopology>`.
pub trait BoardTopology: Send + Sync {
    /// Stable id, e.g. "mill.24" or "mill.24.diagonal".
    fn name(&self) -> &str;
    /// Dense node count; ids are [0, node_count()).
    fn node_count(&self) -> u16;
    /// Unit-square rendering coordinate.  NaN = abstract/off-board slot.
    fn coordinate_of(&self, node: u16) -> UnitPoint;
    /// Human-readable node label, e.g. "d5", "a1", "h8".
    fn label_of(&self, node: u16) -> &str;
    /// Reverse lookup; returns None if no node carries that label.
    fn node_from_label(&self, label: &str) -> Option<u16>;
    /// Adjacency list: sorted, no duplicates, deterministic.
    fn neighbors(&self, node: u16) -> &[u16];
    /// Complete edge list with a < b.
    fn edges(&self) -> &[Edge];
    /// Named groups of nodes forming "lines" (mill triples, Gomoku rows …).
    fn line_groups(&self) -> &[Vec<u16>];
    /// Named zones (hand area, promotion rank, …).
    fn zones(&self) -> &[Zone];
    /// Visual primitives drawn under the pieces.
    fn decorations(&self) -> &[Decoration];
}
