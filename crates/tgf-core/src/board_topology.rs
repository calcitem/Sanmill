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
///
/// `kind_tag` is a per-game edge classification used by games whose
/// movement rules depend on the edge type, e.g. 军棋's railroad vs
/// ordinary connections, or river/no-river edges in xiangqi-style
/// boards.  The default value `0` keeps every other game free from
/// having to populate or interpret the field.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct Edge {
    pub a: u16,
    pub b: u16,
    /// Per-game edge classification.  `0` = default / generic.
    pub kind_tag: u16,
}

impl Edge {
    /// `Edge` whose `kind_tag` defaults to `0`.  Use when callers do
    /// not care about edge classification.
    #[inline]
    pub const fn untyped(a: u16, b: u16) -> Self {
        Self { a, b, kind_tag: 0 }
    }
}

/// A named set of board nodes (hand, capture pile, scoring area, …).
///
/// `role` is an optional canonical tag the shell / engine can react to
/// without having to parse `id`.  Values come from
/// [`zone_role`](self::zone_role) (e.g. `"home_base"`, `"goal"`,
/// `"camp"`, `"headquarters"`, `"railroad"`, `"promotion"`,
/// `"hand"`).  The empty string keeps backwards compatibility for
/// games that have not classified their zones yet.
#[derive(Clone, Debug)]
pub struct Zone {
    /// Stable identifier, e.g. "hand_white", "capture_pile".
    pub id: String,
    pub node_ids: Vec<u16>,
    /// Canonical role token; empty string when not classified.
    pub role: String,
}

impl Zone {
    /// Construct a [`Zone`] without a canonical role token.
    #[inline]
    pub fn new(id: impl Into<String>, node_ids: Vec<u16>) -> Self {
        Self {
            id: id.into(),
            node_ids,
            role: String::new(),
        }
    }

    /// Construct a [`Zone`] tagged with a canonical role.  See
    /// [`zone_role`](self::zone_role) for the predefined token list.
    #[inline]
    pub fn with_role(id: impl Into<String>, node_ids: Vec<u16>, role: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            node_ids,
            role: role.into(),
        }
    }
}

/// Canonical [`Zone::role`] tokens shared across games so the shell
/// can render or filter zones uniformly.  Games may still emit custom
/// role strings; these constants merely document the framework's
/// recommended vocabulary.
pub mod zone_role {
    /// Empty / not classified.  Equivalent to `Zone::role.is_empty()`.
    pub const NONE: &str = "";
    /// Player starting / piece-bank area (Mill hand, Backgammon bar).
    pub const HAND: &str = "hand";
    /// Captured-piece pile / score column.
    pub const CAPTURE_PILE: &str = "capture_pile";
    /// Promotion zone (Chess back rank, Checkers king row).
    pub const PROMOTION: &str = "promotion";
    /// Player's home triangle in Halma / Chinese Checkers.
    pub const HOME_BASE: &str = "home_base";
    /// Opponent's triangle the player must reach (Halma / 中国跳棋).
    pub const GOAL: &str = "goal";
    /// 军棋 行营 — safe square that cannot be attacked.
    pub const CAMP: &str = "camp";
    /// 军棋 大本营 / 总部 — flag-carrying objective square.
    pub const HEADQUARTERS: &str = "headquarters";
    /// 军棋 铁路 line — fast straight-line movement zone.
    pub const RAILROAD: &str = "railroad";
    /// Geographic divider (xiangqi 河, Backgammon home/outer board).
    pub const RIVER: &str = "river";
}

/// Game-specific visual decoration rendered below the pieces.
#[derive(Clone, Debug)]
pub enum DecorationKind {
    Polyline { points: Vec<UnitPoint> },
    Polygon { points: Vec<UnitPoint> },
    Circle { center: UnitPoint, radius: f32 },
    Text { center: UnitPoint, text: String },
}

/// A visual element the Flutter shell draws before placing pieces.
#[derive(Clone, Debug)]
pub struct Decoration {
    pub kind: DecorationKind,
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
    /// Edge-typed adjacency list filtered by `kind_tag`.  Default
    /// implementation walks `edges()` and collects neighbours that
    /// share the requested kind.  Topologies with multi-modal edges
    /// (军棋: railroad vs ordinary) override this with a precomputed
    /// per-kind adjacency table for performance.
    ///
    /// The result is allocated on demand because typed adjacency is
    /// only consumed by movement-rule code (cold path); search hot
    /// paths use `neighbors` which returns a borrowed slice.
    fn neighbors_of_kind(&self, node: u16, kind_tag: u16) -> Vec<u16> {
        let mut out: Vec<u16> = self
            .edges()
            .iter()
            .filter(|e| e.kind_tag == kind_tag && (e.a == node || e.b == node))
            .map(|e| if e.a == node { e.b } else { e.a })
            .collect();
        out.sort_unstable();
        out.dedup();
        out
    }
    /// Complete edge list with a < b.
    fn edges(&self) -> &[Edge];
    /// Named groups of nodes forming "lines" (mill triples, Gomoku rows …).
    fn line_groups(&self) -> &[Vec<u16>];
    /// Named zones (hand area, promotion rank, …).
    fn zones(&self) -> &[Zone];
    /// Visual primitives drawn under the pieces.
    fn decorations(&self) -> &[Decoration];
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Toy three-node topology with one untyped and one typed edge so
    /// the default `neighbors_of_kind` filter has something to discriminate.
    struct ToyTyped;
    impl BoardTopology for ToyTyped {
        fn name(&self) -> &str {
            "toy.typed"
        }
        fn node_count(&self) -> u16 {
            3
        }
        fn coordinate_of(&self, _: u16) -> UnitPoint {
            UnitPoint { x: 0.0, y: 0.0 }
        }
        fn label_of(&self, _: u16) -> &str {
            ""
        }
        fn node_from_label(&self, _: &str) -> Option<u16> {
            None
        }
        fn neighbors(&self, node: u16) -> &[u16] {
            match node {
                0 => &[1, 2],
                1 => &[0, 2],
                2 => &[0, 1],
                _ => &[],
            }
        }
        fn edges(&self) -> &[Edge] {
            // Edge (0,1) ordinary (kind 0), edge (0,2) ordinary,
            // edge (1,2) typed as "rail" (kind 1).
            const EDGES: [Edge; 3] = [
                Edge {
                    a: 0,
                    b: 1,
                    kind_tag: 0,
                },
                Edge {
                    a: 0,
                    b: 2,
                    kind_tag: 0,
                },
                Edge {
                    a: 1,
                    b: 2,
                    kind_tag: 1,
                },
            ];
            &EDGES
        }
        fn line_groups(&self) -> &[Vec<u16>] {
            &[]
        }
        fn zones(&self) -> &[Zone] {
            &[]
        }
        fn decorations(&self) -> &[Decoration] {
            &[]
        }
    }

    #[test]
    fn neighbors_of_kind_filters_by_edge_classification() {
        let topo = ToyTyped;
        assert_eq!(topo.neighbors_of_kind(1, 0), vec![0]);
        assert_eq!(topo.neighbors_of_kind(1, 1), vec![2]);
        assert_eq!(topo.neighbors_of_kind(2, 0), vec![0]);
        assert_eq!(topo.neighbors_of_kind(2, 1), vec![1]);
        assert!(topo.neighbors_of_kind(0, 99).is_empty());
    }

    #[test]
    fn edge_untyped_helper_is_kind_zero() {
        let e = Edge::untyped(2, 5);
        assert_eq!(e.a, 2);
        assert_eq!(e.b, 5);
        assert_eq!(e.kind_tag, 0);
    }

    #[test]
    fn zone_new_has_no_role_and_with_role_round_trips() {
        let plain = Zone::new("hand_white", vec![1, 2, 3]);
        assert_eq!(plain.id, "hand_white");
        assert_eq!(plain.node_ids, vec![1, 2, 3]);
        assert_eq!(plain.role, zone_role::NONE);

        let tagged = Zone::with_role("home_north", vec![10, 11, 12], zone_role::HOME_BASE);
        assert_eq!(tagged.role, "home_base");
        assert_eq!(tagged.role, zone_role::HOME_BASE);
    }

    #[test]
    fn canonical_zone_role_tokens_are_distinct() {
        // Sanity-check the role vocabulary: every advertised constant
        // should be unique so role lookup tables in the shell never
        // collide.
        let tokens = [
            zone_role::HAND,
            zone_role::CAPTURE_PILE,
            zone_role::PROMOTION,
            zone_role::HOME_BASE,
            zone_role::GOAL,
            zone_role::CAMP,
            zone_role::HEADQUARTERS,
            zone_role::RAILROAD,
            zone_role::RIVER,
        ];
        let mut seen = std::collections::HashSet::new();
        for t in tokens {
            assert!(seen.insert(t), "duplicate canonical role token {t:?}");
        }
    }
}
