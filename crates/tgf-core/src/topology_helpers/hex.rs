// SPDX-License-Identifier: GPL-3.0-or-later
// Hexagonal `BoardTopology` builder shared by hex-grid games (Hex,
// Reversi-on-hex, Honeycomb, …).
//
// Coordinates use the *axial* convention (q, r) where the third cubic
// coordinate is implicit: `s = -q - r`.  Each hexagon has six neighbours
// in axial space at offsets
//
//     ( 1,  0)  ( 1, -1)  ( 0, -1)
//     (-1,  0)  (-1,  1)  ( 0,  1)
//
// The builder lays the hexagons out in flat-top orientation, projecting
// them into the unit square so the FRB layer can hand them straight to
// the Flutter renderer.  No part of this module is reachable from the
// search hot path.

use crate::board_topology::{BoardTopology, Decoration, Edge, UnitPoint, Zone};

/// Connectivity model for hex grids.  Currently only six-neighbour adjacency
/// is supported; future variants (e.g. cube-distance > 1) can extend this
/// enum without breaking call sites.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum HexConnectivity {
    /// Standard 6-neighbour adjacency.
    Hex6,
}

/// Fluent builder for [`HexTopology`].
#[derive(Clone, Debug)]
pub struct HexTopologyBuilder {
    radius: u16,
    connectivity: HexConnectivity,
    name: String,
}

/// Concrete [`BoardTopology`] over a hexagonal cluster of `radius`
/// hexes (axial distance `<= radius` from the centre).  `radius=0`
/// is a single hex; `radius=1` is 7 hexes; `radius=2` is 19; in
/// general `1 + 3 * radius * (radius + 1)` cells.
#[derive(Clone, Debug)]
pub struct HexTopology {
    name: String,
    /// Axial coordinates per node id.
    coords: Vec<(i16, i16)>,
    points: Vec<UnitPoint>,
    edges: Vec<Edge>,
    line_groups: Vec<Vec<u16>>,
    labels: Vec<String>,
    neighbors: Vec<Vec<u16>>,
}

impl HexTopologyBuilder {
    /// Create a new builder.  `radius` is the number of rings around
    /// the centre hex (inclusive); see [`HexTopology`].
    #[inline]
    pub fn new(radius: u16) -> Self {
        Self {
            radius,
            connectivity: HexConnectivity::Hex6,
            name: format!("hex.r{radius}"),
        }
    }

    pub fn with_connectivity(mut self, connectivity: HexConnectivity) -> Self {
        self.connectivity = connectivity;
        self
    }

    pub fn with_name(mut self, name: impl Into<String>) -> Self {
        self.name = name.into();
        self
    }

    pub fn build(self) -> HexTopology {
        let HexTopologyBuilder {
            radius,
            connectivity,
            name,
        } = self;
        let r = radius as i32;
        // Enumerate hex coordinates with cube distance <= radius.
        let mut coords = Vec::new();
        for q in -r..=r {
            let lo = (-r).max(-q - r);
            let hi = r.min(-q + r);
            for rr in lo..=hi {
                coords.push((q as i16, rr as i16));
            }
        }
        let total = coords.len();

        // Project axial -> unit-square cartesian.  Flat-top layout:
        //   x = sqrt(3) * (q + r/2)
        //   y = 1.5 * r
        let mut min_x = f32::INFINITY;
        let mut max_x = f32::NEG_INFINITY;
        let mut min_y = f32::INFINITY;
        let mut max_y = f32::NEG_INFINITY;
        let raw: Vec<(f32, f32)> = coords
            .iter()
            .map(|&(q, rr)| {
                let q = q as f32;
                let r = rr as f32;
                let x = 3.0_f32.sqrt() * (q + r * 0.5);
                let y = 1.5 * r;
                if x < min_x {
                    min_x = x;
                }
                if x > max_x {
                    max_x = x;
                }
                if y < min_y {
                    min_y = y;
                }
                if y > max_y {
                    max_y = y;
                }
                (x, y)
            })
            .collect();
        let span_x = (max_x - min_x).max(f32::EPSILON);
        let span_y = (max_y - min_y).max(f32::EPSILON);
        let points: Vec<UnitPoint> = raw
            .into_iter()
            .map(|(x, y)| UnitPoint {
                x: (x - min_x) / span_x,
                y: (y - min_y) / span_y,
            })
            .collect();

        // Labels: "q<q>r<r>" with sign-preserving formatting.
        let labels: Vec<String> = coords.iter().map(|&(q, rr)| format!("q{q}r{rr}")).collect();

        // Neighbour offsets in axial space.
        let offsets: &[(i16, i16)] = match connectivity {
            HexConnectivity::Hex6 => &[(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)],
        };

        let mut neighbors: Vec<Vec<u16>> = vec![Vec::new(); total];
        let mut edge_set = std::collections::BTreeSet::<(u16, u16)>::new();
        let coord_index: std::collections::HashMap<(i16, i16), u16> = coords
            .iter()
            .enumerate()
            .map(|(i, c)| (*c, i as u16))
            .collect();
        for (i, &(q, rr)) in coords.iter().enumerate() {
            let me = i as u16;
            let mut nbr = Vec::with_capacity(offsets.len());
            for (dq, dr) in offsets {
                let coord = (q + dq, rr + dr);
                if let Some(&other) = coord_index.get(&coord) {
                    nbr.push(other);
                    let pair = if me < other { (me, other) } else { (other, me) };
                    edge_set.insert(pair);
                }
            }
            nbr.sort_unstable();
            nbr.dedup();
            neighbors[i] = nbr;
        }
        let edges: Vec<Edge> = edge_set
            .into_iter()
            .map(|(a, b)| Edge::untyped(a, b))
            .collect();

        // Line groups: rows of constant `r` (axial), columns of
        // constant `q`, and diagonals of constant `s = -q - r`.
        let mut line_groups: Vec<Vec<u16>> = Vec::new();
        let group_by =
            |coords: &[(i16, i16)], extract: &dyn Fn((i16, i16)) -> i16| -> Vec<Vec<u16>> {
                let mut buckets: std::collections::BTreeMap<i16, Vec<u16>> =
                    std::collections::BTreeMap::new();
                for (i, c) in coords.iter().enumerate() {
                    buckets.entry(extract(*c)).or_default().push(i as u16);
                }
                buckets.into_values().collect()
            };
        line_groups.extend(group_by(&coords, &|(_, rr)| rr));
        line_groups.extend(group_by(&coords, &|(q, _)| q));
        line_groups.extend(group_by(&coords, &|(q, rr)| -(q + rr)));

        HexTopology {
            name,
            coords,
            points,
            edges,
            line_groups,
            labels,
            neighbors,
        }
    }
}

impl HexTopology {
    /// Convenience: empty `HexTopologyBuilder` with the given radius.
    #[inline]
    pub fn builder(radius: u16) -> HexTopologyBuilder {
        HexTopologyBuilder::new(radius)
    }

    pub fn axial_of(&self, node: u16) -> (i16, i16) {
        self.coords[node as usize]
    }
}

impl BoardTopology for HexTopology {
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
    fn radius_zero_is_a_single_hex() {
        let topo = HexTopology::builder(0).build();
        assert_eq!(topo.node_count(), 1);
        assert!(topo.neighbors(0).is_empty());
    }

    #[test]
    fn radius_one_has_seven_hexes_and_six_neighbours_in_centre() {
        let topo = HexTopology::builder(1).build();
        assert_eq!(topo.node_count(), 7);
        let centre = topo.node_from_label("q0r0").expect("centre exists");
        assert_eq!(topo.neighbors(centre).len(), 6);
    }

    #[test]
    fn cell_count_matches_1_plus_3r_r_plus_1() {
        for r in 0..=4_u16 {
            let topo = HexTopology::builder(r).build();
            let expected = 1 + 3 * (r as u32) * (r as u32 + 1);
            assert_eq!(topo.node_count() as u32, expected);
        }
    }

    #[test]
    fn neighbour_relation_is_symmetric_and_unique() {
        let topo = HexTopology::builder(3).build();
        for node in 0..topo.node_count() {
            for &n in topo.neighbors(node) {
                assert!(topo.neighbors(n).contains(&node));
            }
        }
        for e in topo.edges() {
            assert!(e.a < e.b);
        }
    }

    #[test]
    fn line_groups_split_into_rows_columns_and_diagonals() {
        let topo = HexTopology::builder(2).build();
        // 5 r-values + 5 q-values + 5 s-values for radius=2.
        assert_eq!(topo.line_groups().len(), 15);
    }
}
