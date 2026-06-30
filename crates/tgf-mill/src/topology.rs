// SPDX-License-Identifier: AGPL-3.0-or-later
// Rust-native Mill board topology.
//
// This is the single source of truth for Mill board geometry.  Node ids use
// the master-compatible normalized layout: node `n` maps to legacy C++ square
// `SQ_(n + 8)`.  The layout keeps the mature engine's 3 files x 8 ranks
// bitboard geometry while avoiding the unused low eight bits in Rust arrays.

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

    #[inline]
    pub fn square_to_node(square: u16) -> Option<u16> {
        if (8..32).contains(&square) {
            Some(square - 8)
        } else {
            None
        }
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
        let bytes = label.as_bytes();
        if bytes.len() != 2 {
            return None;
        }
        // UCI labels are fixed ASCII coordinates.  The node values below are
        // `legacy SQ - 8`, preserving master's bitboard geometry directly.
        match (bytes[0].to_ascii_lowercase(), bytes[1]) {
            (b'd', b'5') => Some(0),
            (b'e', b'5') => Some(1),
            (b'e', b'4') => Some(2),
            (b'e', b'3') => Some(3),
            (b'd', b'3') => Some(4),
            (b'c', b'3') => Some(5),
            (b'c', b'4') => Some(6),
            (b'c', b'5') => Some(7),
            (b'd', b'6') => Some(8),
            (b'f', b'6') => Some(9),
            (b'f', b'4') => Some(10),
            (b'f', b'2') => Some(11),
            (b'd', b'2') => Some(12),
            (b'b', b'2') => Some(13),
            (b'b', b'4') => Some(14),
            (b'b', b'6') => Some(15),
            (b'd', b'7') => Some(16),
            (b'g', b'7') => Some(17),
            (b'g', b'4') => Some(18),
            (b'g', b'1') => Some(19),
            (b'd', b'1') => Some(20),
            (b'a', b'1') => Some(21),
            (b'a', b'4') => Some(22),
            (b'a', b'7') => Some(23),
            _ => None,
        }
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
// Node `n` is `SQ_(n + 8)`: inner, middle, outer files; each file starts at
// the 12 o'clock rank and proceeds clockwise.  This mirrors master's bitboard
// layout while keeping Rust arrays compact.
fn standard_nodes() -> Vec<MillNode> {
    vec![
        // inner ring, SQ_8..SQ_15
        node(0, 8, "d5", 0.5, 0.3),
        node(1, 9, "e5", 0.7, 0.3),
        node(2, 10, "e4", 0.7, 0.5),
        node(3, 11, "e3", 0.7, 0.7),
        node(4, 12, "d3", 0.5, 0.7),
        node(5, 13, "c3", 0.3, 0.7),
        node(6, 14, "c4", 0.3, 0.5),
        node(7, 15, "c5", 0.3, 0.3),
        // middle ring, SQ_16..SQ_23
        node(8, 16, "d6", 0.5, 0.2),
        node(9, 17, "f6", 0.8, 0.2),
        node(10, 18, "f4", 0.8, 0.5),
        node(11, 19, "f2", 0.8, 0.8),
        node(12, 20, "d2", 0.5, 0.8),
        node(13, 21, "b2", 0.2, 0.8),
        node(14, 22, "b4", 0.2, 0.5),
        node(15, 23, "b6", 0.2, 0.2),
        // outer ring, SQ_24..SQ_31
        node(16, 24, "d7", 0.5, 0.1),
        node(17, 25, "g7", 0.9, 0.1),
        node(18, 26, "g4", 0.9, 0.5),
        node(19, 27, "g1", 0.9, 0.9),
        node(20, 28, "d1", 0.5, 0.9),
        node(21, 29, "a1", 0.1, 0.9),
        node(22, 30, "a4", 0.1, 0.5),
        node(23, 31, "a7", 0.1, 0.1),
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
    // Spokes only at cardinal ranks.  In the master-compatible layout those
    // are even offsets within each 8-square ring: 12, 3, 6, and 9 o'clock.
    for i in [0_u16, 2, 4, 6] {
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
        vec![7, 0, 1],
        vec![1, 2, 3],
        vec![3, 4, 5],
        vec![5, 6, 7],
        vec![15, 8, 9],
        vec![9, 10, 11],
        vec![11, 12, 13],
        vec![13, 14, 15],
        vec![23, 16, 17],
        vec![17, 18, 19],
        vec![19, 20, 21],
        vec![21, 22, 23],
        // spokes
        vec![0, 8, 16],
        vec![2, 10, 18],
        vec![4, 12, 20],
        vec![6, 14, 22],
    ];
    if has_diagonal_lines {
        lines.extend(diagonal_line_groups().into_iter().map(Vec::from));
    }
    lines
}

fn diagonal_line_groups() -> [[u16; 3]; 4] {
    [
        [23, 15, 7], // a7-b6-c5
        [1, 9, 17],  // e5-f6-g7
        [21, 13, 5], // a1-b2-c3
        [3, 11, 19], // e3-f2-g1
    ]
}

// Translated from master `src/mills.cpp::adjacentSquares` by subtracting
// `SQ_BEGIN` (8) from each legacy square.  The order is the master direction
// order and therefore part of move-list parity.
const N0: &[u16] = &[8, 1, 7];
const N1: &[u16] = &[2, 0];
const N2: &[u16] = &[10, 3, 1];
const N3: &[u16] = &[4, 2];
const N4: &[u16] = &[12, 5, 3];
const N5: &[u16] = &[6, 4];
const N6: &[u16] = &[14, 7, 5];
const N7: &[u16] = &[0, 6];
const N8: &[u16] = &[0, 16, 9, 15];
const N9: &[u16] = &[10, 8];
const N10: &[u16] = &[2, 18, 11, 9];
const N11: &[u16] = &[12, 10];
const N12: &[u16] = &[4, 20, 13, 11];
const N13: &[u16] = &[14, 12];
const N14: &[u16] = &[6, 22, 15, 13];
const N15: &[u16] = &[8, 14];
const N16: &[u16] = &[8, 17, 23];
const N17: &[u16] = &[18, 16];
const N18: &[u16] = &[10, 19, 17];
const N19: &[u16] = &[20, 18];
const N20: &[u16] = &[12, 21, 19];
const N21: &[u16] = &[22, 20];
const N22: &[u16] = &[14, 23, 21];
const N23: &[u16] = &[16, 22];

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
    0x000182, 0x000005, 0x00040a, 0x000014, 0x001028, 0x000050, 0x0040a0, 0x000041, 0x018201,
    0x000500, 0x040a04, 0x001400, 0x102810, 0x005000, 0x40a040, 0x004100, 0x820100, 0x050000,
    0x0a0400, 0x140000, 0x281000, 0x500000, 0xa04000, 0x410000,
];

// Translated from `src/mills.cpp::adjacentSquares_diagonal` with the same
// master-normalized `SQ - 8` node layout.
const D0: &[u16] = &[1, 7, 8];
const D1: &[u16] = &[9, 0, 2];
const D2: &[u16] = &[1, 3, 10];
const D3: &[u16] = &[11, 2, 4];
const D4: &[u16] = &[3, 5, 12];
const D5: &[u16] = &[13, 4, 6];
const D6: &[u16] = &[5, 7, 14];
const D7: &[u16] = &[15, 0, 6];
const D8: &[u16] = &[9, 15, 0, 16];
const D9: &[u16] = &[1, 17, 8, 10];
const D10: &[u16] = &[9, 11, 2, 18];
const D11: &[u16] = &[3, 19, 10, 12];
const D12: &[u16] = &[11, 13, 4, 20];
const D13: &[u16] = &[5, 21, 12, 14];
const D14: &[u16] = &[13, 15, 6, 22];
const D15: &[u16] = &[7, 23, 8, 14];
const D16: &[u16] = &[8, 17, 23];
const D17: &[u16] = &[9, 16, 18];
const D18: &[u16] = &[17, 19, 10];
const D19: &[u16] = &[11, 18, 20];
const D20: &[u16] = &[19, 21, 12];
const D21: &[u16] = &[13, 20, 22];
const D22: &[u16] = &[21, 23, 14];
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
        assert_eq!(topo.node_from_label("d5"), Some(0));
        assert_eq!(topo.node_from_label("D5"), Some(0));
        assert_eq!(topo.node_from_label("a7"), Some(23));
        assert_eq!(topo.node_from_label("a70"), None);
        assert_eq!(topo.label_of(1), "e5");
        assert_eq!(MillTopology::square_to_node(8), Some(0));
        assert_eq!(MillTopology::square_to_node(31), Some(23));
        assert_eq!(MillTopology::square_to_node(7), None);
    }

    #[test]
    fn geometry_matches_existing_flutter_shape() {
        let topo = default_mill_topology();
        assert_eq!(topo.node_count(), 24);
        // P0-H: 24 ring edges + 8 midpoint spokes (4 inner-middle + 4 middle-outer)
        // = 32 total. Old count of 40 included 8 spurious corner cross-ring edges.
        assert_eq!(topo.edges().len(), 32);
        assert_eq!(topo.line_groups().len(), 16);
        assert_eq!(topo.coordinate_of(0), UnitPoint { x: 0.5, y: 0.3 });
        assert_eq!(topo.coordinate_of(23), UnitPoint { x: 0.1, y: 0.1 });
    }

    #[test]
    fn standard_neighbors_match_cxx_no_diagonal_rules() {
        let topo = default_mill_topology();
        assert_eq!(topo.neighbors(0), &[8, 1, 7]);
        assert_eq!(topo.neighbors(1), &[2, 0]);
        assert_eq!(topo.neighbors(8), &[0, 16, 9, 15]);
        assert_eq!(topo.neighbors(16), &[8, 17, 23]);
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
        assert!(topo.line_groups().contains(&vec![23, 15, 7]));
        assert!(topo.line_groups().contains(&vec![1, 9, 17]));
        assert!(topo.line_groups().contains(&vec![21, 13, 5]));
        assert!(topo.line_groups().contains(&vec![3, 11, 19]));
        for node in 0..24 {
            let expected = topo
                .neighbors(node)
                .iter()
                .fold(0_u32, |mask, neighbor| mask | (1_u32 << *neighbor));
            assert_eq!(diagonal_neighbor_mask_for(node as usize), expected);
        }
    }
}
