// SPDX-License-Identifier: GPL-3.0-or-later
// Rectangular grid topology builder shared by every "row × column"
// board game (Chess, Checkers, Othello, Gomoku, Go, …).
//
// The implementation deliberately allocates once at construction time
// and never again — the resulting `GridTopology` is a value object the
// FRB layer can hand to `Arc<dyn BoardTopology>` for the lifetime of a
// kernel session.  No part of this module is reachable from
// `Searcher<G>`'s hot loop.

use crate::board_topology::{BoardTopology, Decoration, Edge, UnitPoint, Zone};

/// Adjacency model used when building a `GridTopology`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GridConnectivity {
    /// 4-neighbour orthogonal (Go, Checkers movement, Gomoku captures).
    Orthogonal4,
    /// 8-neighbour king moves (Chess king, Othello flip rays).
    King8,
    /// L-shaped knight moves (Chess knight).
    Knight,
}

/// Coordinate-label scheme used when building a `GridTopology`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GridLabelScheme {
    /// Chess-style `a1`..`h8` labels.  File `a` is the leftmost column,
    /// rank `1` is the bottom row.  Suitable for any rectangle whose
    /// columns fit into the 26-letter alphabet.
    Chess,
    /// Gomoku / generic `(col, row)` labels formatted as `c<col>r<row>`
    /// where indices are 0-based.  Suitable for boards larger than 26
    /// columns (e.g. a hypothetical 40×40 Gomoku variant).
    ColRow,
}

/// Fluent builder for [`GridTopology`].  Picks reasonable defaults so
/// most call sites can write
/// `GridTopologyBuilder::new(8, 8).build()`.
#[derive(Clone, Debug)]
pub struct GridTopologyBuilder {
    rows: u16,
    cols: u16,
    connectivity: GridConnectivity,
    labels: GridLabelScheme,
    name: String,
}

/// Concrete [`BoardTopology`] over a rectangular `rows × cols` grid.
#[derive(Clone, Debug)]
pub struct GridTopology {
    rows: u16,
    cols: u16,
    name: String,
    points: Vec<UnitPoint>,
    edges: Vec<Edge>,
    line_groups: Vec<Vec<u16>>,
    labels: Vec<String>,
    neighbors: Vec<Vec<u16>>,
}

impl GridTopology {
    /// Start a new builder with `Orthogonal4` connectivity and chess-style
    /// labels.  The default name is `grid.<cols>x<rows>`.
    #[inline]
    pub fn builder(rows: u16, cols: u16) -> GridTopologyBuilder {
        GridTopologyBuilder::new(rows, cols)
    }
}

impl GridTopologyBuilder {
    /// Start a new builder with `Orthogonal4` connectivity and chess-style
    /// labels.  The default name is `grid.<cols>x<rows>`.
    #[inline]
    pub fn new(rows: u16, cols: u16) -> Self {
        Self {
            rows,
            cols,
            connectivity: GridConnectivity::Orthogonal4,
            labels: GridLabelScheme::Chess,
            name: format!("grid.{cols}x{rows}"),
        }
    }
}

impl GridTopologyBuilder {
    /// Override the adjacency model.
    pub fn with_connectivity(mut self, conn: GridConnectivity) -> Self {
        self.connectivity = conn;
        self
    }

    /// Override the label scheme.
    pub fn with_labels(mut self, labels: GridLabelScheme) -> Self {
        self.labels = labels;
        self
    }

    /// Override the topology name (default: `grid.<cols>x<rows>`).
    pub fn with_name(mut self, name: impl Into<String>) -> Self {
        self.name = name.into();
        self
    }

    /// Materialise the [`GridTopology`].  Allocates the geometry tables
    /// up-front so subsequent `BoardTopology` queries are pure lookups.
    pub fn build(self) -> GridTopology {
        let GridTopologyBuilder {
            rows,
            cols,
            connectivity,
            labels,
            name,
        } = self;
        assert!(rows >= 1 && cols >= 1, "grid must have at least one cell");
        assert!(
            (rows as usize) * (cols as usize) <= u16::MAX as usize,
            "grid too large for u16 node ids",
        );

        let total = (rows as usize) * (cols as usize);

        // Coordinates: lay the grid out in [0,1]² with a small margin so
        // pieces drawn at unit radius do not clip the canvas border.
        let mut points = Vec::with_capacity(total);
        for r in 0..rows {
            for c in 0..cols {
                let x = if cols == 1 {
                    0.5
                } else {
                    (c as f32) / ((cols - 1) as f32)
                };
                let y = if rows == 1 {
                    0.5
                } else {
                    (r as f32) / ((rows - 1) as f32)
                };
                points.push(UnitPoint { x, y });
            }
        }

        // Labels.
        let labels_vec: Vec<String> = match labels {
            GridLabelScheme::Chess => {
                assert!(
                    cols <= 26,
                    "chess label scheme only supports up to 26 columns",
                );
                let mut out = Vec::with_capacity(total);
                for r in 0..rows {
                    for c in 0..cols {
                        let file = (b'a' + c as u8) as char;
                        let rank = rows - r;
                        out.push(format!("{file}{rank}"));
                    }
                }
                out
            }
            GridLabelScheme::ColRow => {
                let mut out = Vec::with_capacity(total);
                for r in 0..rows {
                    for c in 0..cols {
                        out.push(format!("c{c}r{r}"));
                    }
                }
                out
            }
        };

        // Neighbours per connectivity model.
        let offsets: &[(i32, i32)] = match connectivity {
            GridConnectivity::Orthogonal4 => &[(-1, 0), (1, 0), (0, -1), (0, 1)],
            GridConnectivity::King8 => &[
                (-1, -1),
                (-1, 0),
                (-1, 1),
                (0, -1),
                (0, 1),
                (1, -1),
                (1, 0),
                (1, 1),
            ],
            GridConnectivity::Knight => &[
                (-2, -1),
                (-2, 1),
                (-1, -2),
                (-1, 2),
                (1, -2),
                (1, 2),
                (2, -1),
                (2, 1),
            ],
        };

        let idx = |r: i32, c: i32| -> Option<u16> {
            if r >= 0 && r < rows as i32 && c >= 0 && c < cols as i32 {
                Some((r as u16) * cols + (c as u16))
            } else {
                None
            }
        };

        let mut neighbors: Vec<Vec<u16>> = vec![Vec::new(); total];
        let mut edge_set = std::collections::BTreeSet::<(u16, u16)>::new();
        for r in 0..rows as i32 {
            for c in 0..cols as i32 {
                let me = idx(r, c).unwrap();
                let mut nbr = Vec::with_capacity(offsets.len());
                for &(dr, dc) in offsets {
                    if let Some(other) = idx(r + dr, c + dc) {
                        nbr.push(other);
                        let pair = if me < other { (me, other) } else { (other, me) };
                        edge_set.insert(pair);
                    }
                }
                nbr.sort_unstable();
                nbr.dedup();
                neighbors[me as usize] = nbr;
            }
        }
        let edges: Vec<Edge> = edge_set
            .into_iter()
            .map(|(a, b)| Edge::untyped(a, b))
            .collect();

        // Line groups: rows + columns.  These let UIs draw rank/file
        // gridlines without re-deriving the geometry.
        let mut line_groups: Vec<Vec<u16>> = Vec::with_capacity((rows as usize) + (cols as usize));
        for r in 0..rows {
            line_groups.push((0..cols).map(|c| r * cols + c).collect());
        }
        for c in 0..cols {
            line_groups.push((0..rows).map(|r| r * cols + c).collect());
        }

        GridTopology {
            rows,
            cols,
            name,
            points,
            edges,
            line_groups,
            labels: labels_vec,
            neighbors,
        }
    }
}

impl GridTopology {
    pub fn rows(&self) -> u16 {
        self.rows
    }
    pub fn cols(&self) -> u16 {
        self.cols
    }
}

impl BoardTopology for GridTopology {
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
        &[]
    }

    fn decorations(&self) -> &[Decoration] {
        &[]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_8x8_grid_has_64_nodes_and_orthogonal_neighbours() {
        let topo = GridTopology::builder(8, 8).build();
        assert_eq!(topo.node_count(), 64);
        assert_eq!(topo.neighbors(0).len(), 2); // corner: right + down
        assert_eq!(topo.neighbors(1).len(), 3); // edge: 3 neighbours
                                                // Centre cell at (3,3) -> id 27 has 4 orthogonal neighbours.
        assert_eq!(topo.neighbors(27).len(), 4);
    }

    #[test]
    fn king8_connectivity_has_8_neighbours_in_centre() {
        let topo = GridTopology::builder(8, 8)
            .with_connectivity(GridConnectivity::King8)
            .build();
        assert_eq!(topo.neighbors(27).len(), 8);
        assert_eq!(topo.neighbors(0).len(), 3); // corner: 3 king neighbours
    }

    #[test]
    fn knight_connectivity_in_centre_is_eight_jumps() {
        let topo = GridTopology::builder(8, 8)
            .with_connectivity(GridConnectivity::Knight)
            .build();
        assert_eq!(topo.neighbors(27).len(), 8);
        assert_eq!(topo.neighbors(0).len(), 2); // a1 knight: 2 jumps
    }

    #[test]
    fn chess_labels_are_a1_through_h8() {
        let topo = GridTopology::builder(8, 8).build();
        // Row 0 in storage order is the topmost row, but chess labels
        // count rank from the bottom, so node id 0 is "a8".
        assert_eq!(topo.label_of(0), "a8");
        assert_eq!(topo.label_of(7), "h8");
        assert_eq!(topo.label_of(56), "a1");
        assert_eq!(topo.label_of(63), "h1");
        assert_eq!(topo.node_from_label("a1"), Some(56));
        assert_eq!(topo.node_from_label("H8"), Some(7));
    }

    #[test]
    fn col_row_labels_are_index_based() {
        let topo = GridTopology::builder(3, 3)
            .with_labels(GridLabelScheme::ColRow)
            .build();
        assert_eq!(topo.label_of(0), "c0r0");
        assert_eq!(topo.label_of(8), "c2r2");
        assert_eq!(topo.node_from_label("c1r1"), Some(4));
    }

    #[test]
    fn line_groups_cover_every_rank_and_file() {
        let topo = GridTopology::builder(3, 4).build();
        // 3 rows + 4 cols = 7 line groups.
        assert_eq!(topo.line_groups().len(), 7);
        // Every line covers either 4 (row) or 3 (col) cells.
        for line in topo.line_groups() {
            assert!(line.len() == 3 || line.len() == 4);
        }
    }

    #[test]
    fn neighbour_relation_is_symmetric_for_all_connectivity_modes() {
        for &conn in &[
            GridConnectivity::Orthogonal4,
            GridConnectivity::King8,
            GridConnectivity::Knight,
        ] {
            let topo = GridTopology::builder(5, 5).with_connectivity(conn).build();
            for node in 0..topo.node_count() {
                for &n in topo.neighbors(node) {
                    assert!(
                        topo.neighbors(n).contains(&node),
                        "asymmetric edge {node} -> {n} under {conn:?}",
                    );
                }
            }
        }
    }

    #[test]
    fn edges_are_ordered_and_unique() {
        let topo = GridTopology::builder(4, 4).build();
        let edges = topo.edges();
        for e in edges {
            assert!(e.a < e.b, "edge {:?} not stored with a < b", e);
        }
        let mut sorted = edges.to_vec();
        sorted.sort_by_key(|e| (e.a, e.b));
        sorted.dedup();
        assert_eq!(sorted.len(), edges.len(), "duplicate edges in builder");
    }
}
