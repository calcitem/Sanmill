// SPDX-License-Identifier: GPL-3.0-or-later
// Rust-native Mill board topology.
//
// This is the Phase 3 single source of truth for Mill board geometry.  Node ids
// are dense (0..23) and match the existing Flutter BoardGeometry ids so the UI
// can switch over without repaint changes.  The `square` field maps back to the
// mature C++ engine's SQ_8..SQ_31 ids and `label` matches UCI::square().

use tgf_core::board_topology::{
    BoardTopology, Decoration, Edge, UnitPoint, Zone,
};

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct MillNode {
    pub id: u16,
    pub square: u16,
    pub label: &'static str,
    pub point: UnitPoint,
}

#[derive(Clone, Debug)]
pub struct MillTopology {
    nodes: Vec<MillNode>,
    edges: Vec<Edge>,
    line_groups: Vec<Vec<u16>>,
    zones: Vec<Zone>,
    decorations: Vec<Decoration>,
}

impl MillTopology {
    pub fn standard() -> Self {
        let nodes = standard_nodes();
        let edges = standard_edges();
        let line_groups = standard_line_groups();
        Self {
            nodes,
            edges,
            line_groups,
            zones: Vec::new(),
            decorations: Vec::new(),
        }
    }

    pub fn nodes(&self) -> &[MillNode] {
        &self.nodes
    }

    pub fn square_to_node(square: u16) -> Option<u16> {
        SQUARE_TO_NODE
            .iter()
            .find_map(|(sq, node)| (*sq == square).then_some(*node))
    }
}

impl Default for MillTopology {
    fn default() -> Self {
        Self::standard()
    }
}

impl BoardTopology for MillTopology {
    fn name(&self) -> &str {
        "mill.24.standard"
    }

    fn node_count(&self) -> u16 {
        self.nodes.len() as u16
    }

    fn coordinate_of(&self, node: u16) -> UnitPoint {
        self.nodes[node as usize].point
    }

    fn label_of(&self, node: u16) -> &str {
        self.nodes[node as usize].label
    }

    fn node_from_label(&self, label: &str) -> Option<u16> {
        self.nodes
            .iter()
            .find_map(|n| n.label.eq_ignore_ascii_case(label).then_some(n.id))
    }

    fn neighbors(&self, node: u16) -> &[u16] {
        NEIGHBORS[node as usize]
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
        &self.decorations
    }
}

pub fn default_mill_topology() -> MillTopology {
    MillTopology::standard()
}

// Dense node id -> C++ square id + UCI label + Flutter unit coordinate.
fn standard_nodes() -> Vec<MillNode> {
    vec![
        // outer ring
        node(0, 31, "a7", 0.1, 0.1),
        node(1, 24, "d7", 0.5, 0.1),
        node(2, 25, "g7", 0.9, 0.1),
        node(3, 26, "g4", 0.9, 0.5),
        node(4, 27, "g1", 0.9, 0.9),
        node(5, 28, "d1", 0.5, 0.9),
        node(6, 29, "a1", 0.1, 0.9),
        node(7, 30, "a4", 0.1, 0.5),
        // middle ring
        node(8, 23, "b6", 0.2, 0.2),
        node(9, 16, "d6", 0.5, 0.2),
        node(10, 17, "f6", 0.8, 0.2),
        node(11, 18, "f4", 0.8, 0.5),
        node(12, 19, "f2", 0.8, 0.8),
        node(13, 20, "d2", 0.5, 0.8),
        node(14, 21, "b2", 0.2, 0.8),
        node(15, 22, "b4", 0.2, 0.5),
        // inner ring
        node(16, 15, "c5", 0.3, 0.3),
        node(17, 8, "d5", 0.5, 0.3),
        node(18, 9, "e5", 0.7, 0.3),
        node(19, 10, "e4", 0.7, 0.5),
        node(20, 11, "e3", 0.7, 0.7),
        node(21, 12, "d3", 0.5, 0.7),
        node(22, 13, "c3", 0.3, 0.7),
        node(23, 14, "c4", 0.3, 0.5),
    ]
}

fn node(id: u16, square: u16, label: &'static str, x: f32, y: f32) -> MillNode {
    MillNode {
        id,
        square,
        label,
        point: UnitPoint { x, y },
    }
}

fn standard_edges() -> Vec<Edge> {
    let mut edges = Vec::with_capacity(32);
    for start in [0_u16, 8, 16] {
        for i in 0..8_u16 {
            edges.push(Edge {
                a: start + i,
                b: start + ((i + 1) % 8),
            });
        }
    }
    for i in 0..8_u16 {
        edges.push(Edge { a: i, b: 8 + i });
        edges.push(Edge {
            a: 8 + i,
            b: 16 + i,
        });
    }
    edges
}

fn standard_line_groups() -> Vec<Vec<u16>> {
    vec![
        // ring sides
        vec![0, 1, 2],
        vec![2, 3, 4],
        vec![4, 5, 6],
        vec![6, 7, 0],
        vec![8, 9, 10],
        vec![10, 11, 12],
        vec![12, 13, 14],
        vec![14, 15, 8],
        vec![16, 17, 18],
        vec![18, 19, 20],
        vec![20, 21, 22],
        vec![22, 23, 16],
        // spokes
        vec![1, 9, 17],
        vec![3, 11, 19],
        vec![5, 13, 21],
        vec![7, 15, 23],
    ]
}

const SQUARE_TO_NODE: &[(u16, u16)] = &[
    (31, 0), (24, 1), (25, 2), (26, 3), (27, 4), (28, 5), (29, 6), (30, 7),
    (23, 8), (16, 9), (17, 10), (18, 11), (19, 12), (20, 13), (21, 14),
    (22, 15), (15, 16), (8, 17), (9, 18), (10, 19), (11, 20), (12, 21),
    (13, 22), (14, 23),
];

const N0: &[u16] = &[1, 7, 8];
const N1: &[u16] = &[0, 2, 9];
const N2: &[u16] = &[1, 3, 10];
const N3: &[u16] = &[2, 4, 11];
const N4: &[u16] = &[3, 5, 12];
const N5: &[u16] = &[4, 6, 13];
const N6: &[u16] = &[5, 7, 14];
const N7: &[u16] = &[6, 0, 15];
const N8: &[u16] = &[9, 15, 0, 16];
const N9: &[u16] = &[8, 10, 1, 17];
const N10: &[u16] = &[9, 11, 2, 18];
const N11: &[u16] = &[10, 12, 3, 19];
const N12: &[u16] = &[11, 13, 4, 20];
const N13: &[u16] = &[12, 14, 5, 21];
const N14: &[u16] = &[13, 15, 6, 22];
const N15: &[u16] = &[14, 8, 7, 23];
const N16: &[u16] = &[17, 23, 8];
const N17: &[u16] = &[16, 18, 9];
const N18: &[u16] = &[17, 19, 10];
const N19: &[u16] = &[18, 20, 11];
const N20: &[u16] = &[19, 21, 12];
const N21: &[u16] = &[20, 22, 13];
const N22: &[u16] = &[21, 23, 14];
const N23: &[u16] = &[22, 16, 15];

const NEIGHBORS: [&[u16]; 24] = [
    N0, N1, N2, N3, N4, N5, N6, N7, N8, N9, N10, N11, N12, N13, N14, N15, N16,
    N17, N18, N19, N20, N21, N22, N23,
];

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn labels_match_cxx_square_table() {
        let topo = default_mill_topology();
        assert_eq!(topo.node_from_label("d5"), Some(17));
        assert_eq!(topo.node_from_label("a7"), Some(0));
        assert_eq!(topo.label_of(18), "e5");
        assert_eq!(MillTopology::square_to_node(8), Some(17));
        assert_eq!(MillTopology::square_to_node(31), Some(0));
    }

    #[test]
    fn geometry_matches_existing_flutter_shape() {
        let topo = default_mill_topology();
        assert_eq!(topo.node_count(), 24);
        assert_eq!(topo.edges().len(), 40);
        assert_eq!(topo.line_groups().len(), 16);
        assert_eq!(topo.coordinate_of(0), UnitPoint { x: 0.1, y: 0.1 });
        assert_eq!(topo.coordinate_of(23), UnitPoint { x: 0.3, y: 0.5 });
    }
}
