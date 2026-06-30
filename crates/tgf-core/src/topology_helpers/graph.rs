// SPDX-License-Identifier: AGPL-3.0-or-later
// Generic node/edge `BoardTopology` builder for irregular boards
// (军棋, Patolli, Game of Goose, …).
//
// Unlike `grid` / `hex` / `star`, this builder makes no assumptions
// about the board's underlying lattice — every node and every edge is
// supplied explicitly, allowing games to model railroads, river
// crossings, sanctuary squares and other features that carry custom
// rule semantics on a per-edge or per-zone basis.
//
// All bookkeeping happens at construction time so the resulting
// `GraphTopology` is a pure value object on the IPC / FRB boundary.
// No part of this module is reachable from `Searcher<G>`'s
// monomorphised hot path.

use std::collections::BTreeSet;

use crate::board_topology::{BoardTopology, Decoration, Edge, UnitPoint, Zone};

/// Per-node specification used by [`GraphTopologyBuilder`].
#[derive(Clone, Debug)]
pub struct GraphNode {
    pub label: String,
    pub coordinate: UnitPoint,
}

impl GraphNode {
    #[inline]
    pub fn new(label: impl Into<String>, coordinate: UnitPoint) -> Self {
        Self {
            label: label.into(),
            coordinate,
        }
    }
}

/// Per-edge specification used by [`GraphTopologyBuilder`].
#[derive(Clone, Copy, Debug)]
pub struct GraphEdge {
    pub a: u16,
    pub b: u16,
    pub kind_tag: u16,
}

impl GraphEdge {
    /// Edge with the default (kind_tag = 0) classification.
    #[inline]
    pub const fn untyped(a: u16, b: u16) -> Self {
        Self { a, b, kind_tag: 0 }
    }

    /// Edge tagged with a per-game classification.
    #[inline]
    pub const fn typed(a: u16, b: u16, kind_tag: u16) -> Self {
        Self { a, b, kind_tag }
    }
}

/// Per-zone specification used by [`GraphTopologyBuilder`].
#[derive(Clone, Debug)]
pub struct GraphZone {
    pub id: String,
    pub node_ids: Vec<u16>,
    pub role: String,
}

impl GraphZone {
    pub fn new(id: impl Into<String>, node_ids: Vec<u16>) -> Self {
        Self {
            id: id.into(),
            node_ids,
            role: String::new(),
        }
    }
    pub fn with_role(id: impl Into<String>, node_ids: Vec<u16>, role: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            node_ids,
            role: role.into(),
        }
    }
}

/// Fluent builder for [`GraphTopology`].  Call sites push nodes,
/// edges, zones and an optional name and finally invoke `build()` to
/// materialise the topology.
#[derive(Clone, Debug, Default)]
pub struct GraphTopologyBuilder {
    name: String,
    nodes: Vec<GraphNode>,
    edges: Vec<GraphEdge>,
    zones: Vec<GraphZone>,
    /// Optional named line groups (rails, rivers, scoring rows).
    line_groups: Vec<Vec<u16>>,
}

/// Concrete [`BoardTopology`] over an arbitrary node/edge graph.
#[derive(Clone, Debug)]
pub struct GraphTopology {
    name: String,
    points: Vec<UnitPoint>,
    edges: Vec<Edge>,
    line_groups: Vec<Vec<u16>>,
    labels: Vec<String>,
    /// Cached untyped adjacency: list of all neighbours regardless of
    /// edge kind, sorted and deduplicated.  Used by the default
    /// `BoardTopology::neighbors` accessor.
    neighbors: Vec<Vec<u16>>,
    zones: Vec<Zone>,
}

impl GraphTopologyBuilder {
    #[inline]
    pub fn new(name: impl Into<String>) -> Self {
        Self {
            name: name.into(),
            ..Default::default()
        }
    }

    /// Add a node and return its dense id.  Ids are issued in insertion
    /// order, starting at `0`, matching the `BoardTopology` contract.
    pub fn add_node(&mut self, node: GraphNode) -> u16 {
        let id = self.nodes.len() as u16;
        self.nodes.push(node);
        id
    }

    /// Reserve `count` empty nodes positioned at the origin.  Useful
    /// when callers prefer to populate nodes by id later rather than in
    /// stream order.
    pub fn reserve_nodes(&mut self, count: u16) {
        self.nodes.resize(
            self.nodes.len() + count as usize,
            GraphNode::new("", UnitPoint { x: 0.0, y: 0.0 }),
        );
    }

    /// Replace an already-added node, e.g. after `reserve_nodes`.
    pub fn set_node(&mut self, id: u16, node: GraphNode) {
        self.nodes[id as usize] = node;
    }

    pub fn add_edge(&mut self, edge: GraphEdge) {
        self.edges.push(edge);
    }

    pub fn add_zone(&mut self, zone: GraphZone) {
        self.zones.push(zone);
    }

    pub fn add_line_group(&mut self, line: Vec<u16>) {
        self.line_groups.push(line);
    }

    /// Materialise the topology, asserting on duplicated edges and
    /// out-of-range node ids.
    pub fn build(self) -> GraphTopology {
        let GraphTopologyBuilder {
            name,
            nodes,
            edges,
            zones,
            line_groups,
        } = self;
        assert!(
            !nodes.is_empty(),
            "graph topology requires at least one node"
        );
        assert!(
            nodes.len() <= u16::MAX as usize,
            "graph topology too large for u16 node ids",
        );

        let total = nodes.len();
        let labels: Vec<String> = nodes.iter().map(|n| n.label.clone()).collect();
        let points: Vec<UnitPoint> = nodes.iter().map(|n| n.coordinate).collect();

        // Zone validation + conversion.
        let zones: Vec<Zone> = zones
            .into_iter()
            .map(|gz| {
                for &id in &gz.node_ids {
                    assert!(
                        (id as usize) < total,
                        "zone {:?} references unknown node id {id}",
                        gz.id,
                    );
                }
                Zone {
                    id: gz.id,
                    node_ids: gz.node_ids,
                    role: gz.role,
                }
            })
            .collect();

        // Line-group validation.
        for line in &line_groups {
            for &id in line {
                assert!(
                    (id as usize) < total,
                    "line group references unknown node id {id}",
                );
            }
        }

        // Edge canonicalisation: store (min, max) ordered pairs and
        // deduplicate per (a, b, kind_tag) triple.  Multiple edges
        // between the same nodes with different kind_tags are allowed
        // (military rail + ordinary edge between the same junction is a
        // legitimate use case).
        let mut seen = BTreeSet::<(u16, u16, u16)>::new();
        let mut canonical_edges: Vec<Edge> = Vec::with_capacity(edges.len());
        let mut neighbors: Vec<Vec<u16>> = vec![Vec::new(); total];
        for ge in edges {
            assert!(
                (ge.a as usize) < total && (ge.b as usize) < total,
                "edge references unknown node id ({}, {})",
                ge.a,
                ge.b,
            );
            assert!(ge.a != ge.b, "self-loops are not allowed");
            let (lo, hi) = if ge.a < ge.b {
                (ge.a, ge.b)
            } else {
                (ge.b, ge.a)
            };
            if !seen.insert((lo, hi, ge.kind_tag)) {
                continue;
            }
            canonical_edges.push(Edge {
                a: lo,
                b: hi,
                kind_tag: ge.kind_tag,
            });
            neighbors[lo as usize].push(hi);
            neighbors[hi as usize].push(lo);
        }

        for slot in &mut neighbors {
            slot.sort_unstable();
            slot.dedup();
        }

        // Edges sorted by (a, b, kind_tag) for stable iteration.
        canonical_edges.sort_by_key(|e| (e.a, e.b, e.kind_tag));

        GraphTopology {
            name,
            points,
            edges: canonical_edges,
            line_groups,
            labels,
            neighbors,
            zones,
        }
    }
}

impl GraphTopology {
    #[inline]
    pub fn builder(name: impl Into<String>) -> GraphTopologyBuilder {
        GraphTopologyBuilder::new(name)
    }
}

impl BoardTopology for GraphTopology {
    fn name(&self) -> &str {
        &self.name
    }
    fn node_count(&self) -> u16 {
        self.points.len() as u16
    }
    fn coordinate_of(&self, node: u16) -> UnitPoint {
        self.points[node as usize]
    }
    fn label_of(&self, node: u16) -> &str {
        &self.labels[node as usize]
    }
    fn node_from_label(&self, label: &str) -> Option<u16> {
        self.labels
            .iter()
            .position(|l| l.eq_ignore_ascii_case(label))
            .map(|i| i as u16)
    }
    fn neighbors(&self, node: u16) -> &[u16] {
        &self.neighbors[node as usize]
    }
    fn edges(&self) -> &[Edge] {
        &self.edges
    }
    fn line_groups(&self) -> &[Vec<u16>] {
        &self.line_groups
    }
    fn zones(&self) -> &[Zone] {
        &self.zones
    }
    fn decorations(&self) -> &[Decoration] {
        &[]
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::board_topology::zone_role;

    /// Small "junqi-flavoured" graph: 4 cells where cells 0-1-2 sit on
    /// a railroad (kind_tag = 1) and cell 3 hangs off cell 2 via an
    /// ordinary edge.  Cell 1 is a camp; cells 2-3 form a headquarters
    /// zone.
    fn build_sample() -> GraphTopology {
        let mut b = GraphTopology::builder("junqi.toy");
        let n0 = b.add_node(GraphNode::new("a", UnitPoint { x: 0.0, y: 0.0 }));
        let n1 = b.add_node(GraphNode::new("b", UnitPoint { x: 0.5, y: 0.0 }));
        let n2 = b.add_node(GraphNode::new("c", UnitPoint { x: 1.0, y: 0.0 }));
        let n3 = b.add_node(GraphNode::new("d", UnitPoint { x: 1.0, y: 0.5 }));
        b.add_edge(GraphEdge::typed(n0, n1, 1));
        b.add_edge(GraphEdge::typed(n1, n2, 1));
        b.add_edge(GraphEdge::untyped(n2, n3));
        b.add_zone(GraphZone::with_role("camp_b", vec![n1], zone_role::CAMP));
        b.add_zone(GraphZone::with_role(
            "hq",
            vec![n2, n3],
            zone_role::HEADQUARTERS,
        ));
        b.add_line_group(vec![n0, n1, n2]);
        b.build()
    }

    #[test]
    fn nodes_edges_zones_round_trip() {
        let topo = build_sample();
        assert_eq!(topo.node_count(), 4);
        assert_eq!(topo.edges().len(), 3);
        assert_eq!(topo.zones().len(), 2);
        assert_eq!(topo.line_groups().len(), 1);
        assert_eq!(topo.label_of(0), "a");
        assert_eq!(topo.node_from_label("D"), Some(3));
    }

    #[test]
    fn neighbors_default_returns_all_kinds() {
        let topo = build_sample();
        assert_eq!(topo.neighbors(1), &[0_u16, 2]);
        assert_eq!(topo.neighbors(2), &[1_u16, 3]);
    }

    #[test]
    fn neighbors_of_kind_filters_railroad_vs_ordinary() {
        let topo = build_sample();
        assert_eq!(topo.neighbors_of_kind(2, 1), vec![1]); // railroad neighbour
        assert_eq!(topo.neighbors_of_kind(2, 0), vec![3]); // ordinary neighbour
        assert!(topo.neighbors_of_kind(0, 0).is_empty());
    }

    #[test]
    fn neighbour_relation_is_symmetric() {
        let topo = build_sample();
        for node in 0..topo.node_count() {
            for &n in topo.neighbors(node) {
                assert!(topo.neighbors(n).contains(&node));
            }
        }
    }

    #[test]
    fn edges_are_sorted_and_deduplicated() {
        let mut b = GraphTopology::builder("dup");
        b.add_node(GraphNode::new("a", UnitPoint { x: 0.0, y: 0.0 }));
        b.add_node(GraphNode::new("b", UnitPoint { x: 1.0, y: 0.0 }));
        b.add_edge(GraphEdge::untyped(0, 1));
        b.add_edge(GraphEdge::untyped(1, 0)); // duplicate, just reversed
        b.add_edge(GraphEdge::typed(0, 1, 7)); // distinct kind, kept
        let topo = b.build();
        assert_eq!(topo.edges().len(), 2);
        assert!(topo.edges().iter().all(|e| e.a < e.b));
    }

    #[test]
    #[should_panic(expected = "self-loops")]
    fn self_loops_are_rejected() {
        let mut b = GraphTopology::builder("loopy");
        b.add_node(GraphNode::new("a", UnitPoint { x: 0.0, y: 0.0 }));
        b.add_edge(GraphEdge::untyped(0, 0));
        b.build();
    }

    #[test]
    #[should_panic(expected = "unknown node id")]
    fn out_of_range_zone_panics() {
        let mut b = GraphTopology::builder("oob");
        b.add_node(GraphNode::new("a", UnitPoint { x: 0.0, y: 0.0 }));
        b.add_zone(GraphZone::new("bad", vec![5]));
        b.build();
    }
}
