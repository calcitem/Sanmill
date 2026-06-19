// SPDX-License-Identifier: GPL-3.0-or-later
// Rust-native Mill board topology.
//
// This is the single source of truth for Mill board geometry.  Node ids are
// dense (0..23) and match the existing Flutter BoardGeometry ids.  The
// `square` field maps back to the mature C++ engine's SQ_8..SQ_31 ids and
// `label` matches UCI::square().

use std::sync::OnceLock;

use tgf_core::board_topology::{BoardTopology, Decoration, Edge, UnitPoint, Zone};

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
    has_diagonal_lines: bool,
}

impl MillTopology {
    pub fn standard() -> Self {
        Self::new(false)
    }

    pub fn with_diagonals() -> Self {
        Self::new(true)
    }

    pub fn new(has_diagonal_lines: bool) -> Self {
        let nodes = standard_nodes();
        let edges = standard_edges(has_diagonal_lines);
        let line_groups = standard_line_groups(has_diagonal_lines);
        Self {
            nodes,
            edges,
            line_groups,
            zones: Vec::new(),
            decorations: Vec::new(),
            has_diagonal_lines,
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
        if self.has_diagonal_lines {
            "mill.24.diagonal"
        } else {
            "mill.24.standard"
        }
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
        if self.has_diagonal_lines {
            NEIGHBORS_DIAGONAL[node as usize]
        } else {
            NEIGHBORS[node as usize]
        }
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

pub(crate) fn shared_mill_topology(has_diagonal_lines: bool) -> &'static MillTopology {
    static STANDARD: OnceLock<MillTopology> = OnceLock::new();
    static DIAGONAL: OnceLock<MillTopology> = OnceLock::new();

    if has_diagonal_lines {
        DIAGONAL.get_or_init(MillTopology::with_diagonals)
    } else {
        STANDARD.get_or_init(MillTopology::standard)
    }
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

fn standard_edges(has_diagonal_lines: bool) -> Vec<Edge> {
    // 24 ring edges (3 rings × 8) + 8 spoke edges (midpoints only, not corners).
    // P0-H: the original code iterated i in 0..8 for both inner→middle and
    // middle→outer spokes, producing 16 spoke edges total, but 8 of those
    // (corner positions 0,2,4,6 / 8,10,12,14 / etc.) are not actual game
    // connections in standard Nine Men's Morris. Only the 4 midpoint spokes per
    // layer are real; odd-indexed nodes (1,3,5,7) in Rust dense numbering are
    // midpoints and the only ones that carry cross-ring spokes.
    let mut edges = Vec::with_capacity(if has_diagonal_lines { 48 } else { 32 });
    for start in [0_u16, 8, 16] {
        for i in 0..8_u16 {
            edges.push(Edge::untyped(start + i, start + ((i + 1) % 8)));
        }
    }
    // Spokes only at midpoint positions (odd dense-node indices within each ring).
    // NEIGHBORS confirms: inner node 1 → middle node 9, middle node 9 → outer node 17, etc.
    for i in [1_u16, 3, 5, 7] {
        edges.push(Edge::untyped(i, 8 + i));
        edges.push(Edge::untyped(8 + i, 16 + i));
    }
    if has_diagonal_lines {
        for a in 0_u16..24 {
            for &b in NEIGHBORS_DIAGONAL[a as usize] {
                if a < b {
                    edges.push(Edge::untyped(a, b));
                }
            }
        }
    }
    // Diagonal neighbor exports include the standard ring/spoke neighbors too.
    // Deduplicate `(min, max)` edge pairs here while preserving `neighbors()`
    // exactly as translated from the C++ adjacency tables.
    edges.sort_by_key(|edge| {
        let a = edge.a.min(edge.b);
        let b = edge.a.max(edge.b);
        (a, b)
    });
    edges.dedup_by_key(|edge| {
        let a = edge.a.min(edge.b);
        let b = edge.a.max(edge.b);
        (a, b)
    });
    edges
}

fn standard_line_groups(has_diagonal_lines: bool) -> Vec<Vec<u16>> {
    let mut lines = vec![
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
    ];
    if has_diagonal_lines {
        lines.extend(diagonal_line_groups().into_iter().map(Vec::from));
    }
    lines
}

fn diagonal_line_groups() -> [[u16; 3]; 4] {
    [
        [0, 8, 16],  // a7-b6-c5
        [18, 10, 2], // e5-f6-g7
        [6, 14, 22], // a1-b2-c3
        [20, 12, 4], // e3-f2-g1
    ]
}

const SQUARE_TO_NODE: &[(u16, u16)] = &[
    (31, 0),
    (24, 1),
    (25, 2),
    (26, 3),
    (27, 4),
    (28, 5),
    (29, 6),
    (30, 7),
    (23, 8),
    (16, 9),
    (17, 10),
    (18, 11),
    (19, 12),
    (20, 13),
    (21, 14),
    (22, 15),
    (15, 16),
    (8, 17),
    (9, 18),
    (10, 19),
    (11, 20),
    (12, 21),
    (13, 22),
    (14, 23),
];

const N0: &[u16] = &[1, 7];
const N1: &[u16] = &[9, 2, 0];
const N2: &[u16] = &[3, 1];
const N3: &[u16] = &[11, 4, 2];
const N4: &[u16] = &[5, 3];
const N5: &[u16] = &[13, 6, 4];
const N6: &[u16] = &[7, 5];
const N7: &[u16] = &[15, 0, 6];
const N8: &[u16] = &[9, 15];
const N9: &[u16] = &[17, 1, 10, 8];
const N10: &[u16] = &[11, 9];
const N11: &[u16] = &[19, 3, 12, 10];
const N12: &[u16] = &[13, 11];
const N13: &[u16] = &[21, 5, 14, 12];
const N14: &[u16] = &[15, 13];
const N15: &[u16] = &[23, 7, 8, 14];
const N16: &[u16] = &[17, 23];
const N17: &[u16] = &[9, 18, 16];
const N18: &[u16] = &[19, 17];
const N19: &[u16] = &[11, 20, 18];
const N20: &[u16] = &[21, 19];
const N21: &[u16] = &[13, 22, 20];
const N22: &[u16] = &[23, 21];
const N23: &[u16] = &[15, 16, 22];

const NEIGHBORS: [&[u16]; 24] = [
    N0, N1, N2, N3, N4, N5, N6, N7, N8, N9, N10, N11, N12, N13, N14, N15, N16, N17, N18, N19, N20,
    N21, N22, N23,
];
// Same adjacency as `NEIGHBORS`, encoded as bitboards for hot-path
// membership tests and popcounts.  Bit `1 << n` means dense node `n` is
// adjacent to the array index node.  Keep these masks next to the ordered
// slice tables: the masks are faster for set algebra, while the slices are
// still the source of move-generation order whenever order can affect the
// emitted move list.
//
// These constants mirror master's `MoveList<LEGAL>::adjacentSquaresBB`
// shape.  The topology tests below recompute the expected masks from the
// ordered slices so hand-edited hex values cannot silently drift.
const NEIGHBOR_MASKS: [u32; 24] = [
    0x000082, 0x000205, 0x00000a, 0x000814, 0x000028, 0x002050, 0x0000a0, 0x008041, 0x008200,
    0x020502, 0x000a00, 0x081408, 0x002800, 0x205020, 0x00a000, 0x804180, 0x820000, 0x050200,
    0x0a0000, 0x140800, 0x280000, 0x502000, 0xa00000, 0x418000,
];

// Translated from `src/mills.cpp` `adjacentSquares_diagonal` (dense node ids 0..23).
const D0: &[u16] = &[1, 7, 8];
const D1: &[u16] = &[0, 2, 9];
const D2: &[u16] = &[1, 3, 10];
const D3: &[u16] = &[2, 4, 11];
const D4: &[u16] = &[3, 5, 12];
const D5: &[u16] = &[4, 6, 13];
const D6: &[u16] = &[5, 7, 14];
const D7: &[u16] = &[0, 6, 15];
const D8: &[u16] = &[0, 9, 15, 16];
const D9: &[u16] = &[1, 8, 10, 17];
const D10: &[u16] = &[2, 9, 11, 18];
const D11: &[u16] = &[3, 10, 12, 19];
const D12: &[u16] = &[4, 11, 13, 20];
const D13: &[u16] = &[5, 12, 14, 21];
const D14: &[u16] = &[6, 13, 15, 22];
const D15: &[u16] = &[7, 8, 14, 23];
const D16: &[u16] = &[8, 17, 23];
const D17: &[u16] = &[9, 16, 18];
const D18: &[u16] = &[10, 17, 19];
const D19: &[u16] = &[11, 18, 20];
const D20: &[u16] = &[12, 19, 21];
const D21: &[u16] = &[13, 20, 22];
const D22: &[u16] = &[14, 21, 23];
const D23: &[u16] = &[15, 16, 22];

const NEIGHBORS_DIAGONAL: [&[u16]; 24] = [
    D0, D1, D2, D3, D4, D5, D6, D7, D8, D9, D10, D11, D12, D13, D14, D15, D16, D17, D18, D19, D20,
    D21, D22, D23,
];
// Diagonal-rule variant of `NEIGHBOR_MASKS`.  It has the same dense-node
// bit encoding and the same "mask for speed, slice for order" split.
const NEIGHBOR_MASKS_DIAGONAL: [u32; 24] = [
    0x000182, 0x000205, 0x00040a, 0x000814, 0x001028, 0x002050, 0x0040a0, 0x008041, 0x018201,
    0x020502, 0x040a04, 0x081408, 0x102810, 0x205020, 0x40a040, 0x804180, 0x820100, 0x050200,
    0x0a0400, 0x140800, 0x281000, 0x502000, 0xa04000, 0x418000,
];

#[inline]
pub(crate) fn neighbor_mask_for(node: usize, has_diagonal_lines: bool) -> u32 {
    if has_diagonal_lines {
        diagonal_neighbor_mask_for(node)
    } else {
        standard_neighbor_mask_for(node)
    }
}

#[inline]
pub(crate) fn standard_neighbors_for(node: usize) -> &'static [u16] {
    debug_assert!(node < 24);
    NEIGHBORS[node]
}

#[inline]
pub(crate) fn standard_neighbor_mask_for(node: usize) -> u32 {
    debug_assert!(node < 24);
    NEIGHBOR_MASKS[node]
}

#[inline]
pub(crate) fn diagonal_neighbors_for(node: usize) -> &'static [u16] {
    debug_assert!(node < 24);
    NEIGHBORS_DIAGONAL[node]
}

#[inline]
pub(crate) fn diagonal_neighbor_mask_for(node: usize) -> u32 {
    debug_assert!(node < 24);
    NEIGHBOR_MASKS_DIAGONAL[node]
}

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
        // P0-H: 24 ring edges + 8 midpoint spokes (4 inner-middle + 4 middle-outer)
        // = 32 total. Old count of 40 included 8 spurious corner cross-ring edges.
        assert_eq!(topo.edges().len(), 32);
        assert_eq!(topo.line_groups().len(), 16);
        assert_eq!(topo.coordinate_of(0), UnitPoint { x: 0.1, y: 0.1 });
        assert_eq!(topo.coordinate_of(23), UnitPoint { x: 0.3, y: 0.5 });
    }

    #[test]
    fn standard_neighbors_match_cxx_no_diagonal_rules() {
        let topo = default_mill_topology();
        assert_eq!(topo.neighbors(0), &[1, 7]);
        assert_eq!(topo.neighbors(1), &[9, 2, 0]);
        assert_eq!(topo.neighbors(9), &[17, 1, 10, 8]);
        assert_eq!(topo.neighbors(17), &[9, 18, 16]);
        for node in 0..24 {
            let expected = topo
                .neighbors(node)
                .iter()
                .fold(0_u32, |mask, neighbor| mask | (1_u32 << *neighbor));
            assert_eq!(standard_neighbor_mask_for(node as usize), expected);
        }
    }

    #[test]
    fn diagonal_topology_matches_cxx_diagonal_rules() {
        let topo = MillTopology::with_diagonals();
        assert_eq!(topo.name(), "mill.24.diagonal");
        assert_eq!(topo.edges().len(), 40);
        assert_eq!(topo.line_groups().len(), 20);
        assert_eq!(topo.neighbors(0), &[1, 7, 8]);
        assert_eq!(topo.neighbors(2), &[1, 3, 10]);
        assert!(topo.line_groups().contains(&vec![0, 8, 16]));
        assert!(topo.line_groups().contains(&vec![18, 10, 2]));
        assert!(topo.line_groups().contains(&vec![6, 14, 22]));
        assert!(topo.line_groups().contains(&vec![20, 12, 4]));
        for node in 0..24 {
            let expected = topo
                .neighbors(node)
                .iter()
                .fold(0_u32, |mask, neighbor| mask | (1_u32 << *neighbor));
            assert_eq!(diagonal_neighbor_mask_for(node as usize), expected);
        }
    }
}
