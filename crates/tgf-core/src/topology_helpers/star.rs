// SPDX-License-Identifier: GPL-3.0-or-later
// Six-pointed star `BoardTopology` builder used by Halma / Chinese
// Checkers (中国跳棋).  The star consists of a central hexagon plus
// six triangular points; every cell uses the same axial (q, r)
// coordinate system as `topology_helpers::hex` so adjacency falls
// straight out of the underlying hex grid.
//
// The classic 121-hole Chinese-Checkers board has central side-length
// 5 (so the centre hex has 5*4-3 = 17 rows... in practice the canonical
// "side-length 4" parameterisation uses a 5x5 centre cluster surrounded
// by four-cell triangular arms).  We expose `side_length` directly
// since reference materials disagree on the natural unit; helper
// constructors `halma_121()` / `halma_73()` / `halma_49()` fix the
// classic sizes.
//
// All construction is up-front; `BoardTopology` queries on the
// resulting object are pure indexing.

use std::collections::{BTreeMap, BTreeSet, HashMap};

use crate::board_topology::zone_role;
use crate::board_topology::{BoardTopology, Decoration, Edge, UnitPoint, Zone};

/// Connectivity model for star-of-david grids.  Currently only the
/// six-neighbour hex adjacency is meaningful.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum StarConnectivity {
    Hex6,
}

/// Fluent builder for [`StarTopology`].
#[derive(Clone, Debug)]
pub struct StarTopologyBuilder {
    /// Side length of one of the six star points (number of cells along
    /// the outer triangle's edge).  `side=4` gives the classical
    /// 121-hole Chinese-Checkers board.
    side: u16,
    connectivity: StarConnectivity,
    name: String,
    /// True when the builder should emit one home-base zone per star
    /// arm (six total) so games can label each player's starting / goal
    /// triangles.
    emit_home_zones: bool,
}

/// Concrete [`BoardTopology`] over a six-pointed star with `side`
/// cells along each triangular edge.
#[derive(Clone, Debug)]
pub struct StarTopology {
    name: String,
    coords: Vec<(i16, i16)>,
    points: Vec<UnitPoint>,
    edges: Vec<Edge>,
    line_groups: Vec<Vec<u16>>,
    labels: Vec<String>,
    neighbors: Vec<Vec<u16>>,
    zones: Vec<Zone>,
}

impl StarTopologyBuilder {
    /// Construct a builder with `side`-length triangular arms.  `side`
    /// must be `>= 1`.  For Chinese Checkers use `side = 4`.
    #[inline]
    pub fn new(side: u16) -> Self {
        Self {
            side,
            connectivity: StarConnectivity::Hex6,
            name: format!("star.s{side}"),
            emit_home_zones: true,
        }
    }

    pub fn with_connectivity(mut self, connectivity: StarConnectivity) -> Self {
        self.connectivity = connectivity;
        self
    }

    pub fn with_name(mut self, name: impl Into<String>) -> Self {
        self.name = name.into();
        self
    }

    pub fn without_home_zones(mut self) -> Self {
        self.emit_home_zones = false;
        self
    }

    pub fn build(self) -> StarTopology {
        assert!(self.side >= 1, "star topology requires side >= 1");
        let StarTopologyBuilder {
            side,
            connectivity: _,
            name,
            emit_home_zones,
        } = self;
        let s = side as i32;
        // Cube coordinate criterion for "in-star": a cell at axial (q, r)
        // (cube (q, r, -q-r)) is part of the star iff at least two of
        // |q|, |r|, |q+r| are <= s.  This carves the central hexagon
        // (max == s) plus the six arms (one coordinate up to 2s).
        let limit = 2 * s;
        let mut coords: Vec<(i16, i16)> = Vec::new();
        for q in -limit..=limit {
            for r in -limit..=limit {
                let abs_q = q.abs();
                let abs_r = r.abs();
                let abs_s = (q + r).abs();
                let small = (abs_q <= s) as u8 + (abs_r <= s) as u8 + (abs_s <= s) as u8;
                if small >= 2 {
                    coords.push((q as i16, r as i16));
                }
            }
        }
        let total = coords.len();

        // Project axial -> unit-square (flat-top hex layout).
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

        // Labels: signed axial.
        let labels: Vec<String> = coords.iter().map(|&(q, rr)| format!("q{q}r{rr}")).collect();

        // Six-neighbour adjacency in axial space.
        let offsets: &[(i16, i16)] = &[(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)];

        let mut neighbors: Vec<Vec<u16>> = vec![Vec::new(); total];
        let mut edge_set = BTreeSet::<(u16, u16)>::new();
        let coord_index: HashMap<(i16, i16), u16> = coords
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

        // Line groups: rows of constant `r`, columns of constant `q`,
        // diagonals of constant `s = -q - r`.
        let group_by = |extract: &dyn Fn((i16, i16)) -> i16| -> Vec<Vec<u16>> {
            let mut buckets: BTreeMap<i16, Vec<u16>> = BTreeMap::new();
            for (i, c) in coords.iter().enumerate() {
                buckets.entry(extract(*c)).or_default().push(i as u16);
            }
            buckets.into_values().collect()
        };
        let mut line_groups: Vec<Vec<u16>> = Vec::new();
        line_groups.extend(group_by(&|(_, rr)| rr));
        line_groups.extend(group_by(&|(q, _)| q));
        line_groups.extend(group_by(&|(q, rr)| -(q + rr)));

        // Optional home-base zones — one per star arm.  An arm is the
        // set of cells whose dominant cube axis is `> s` in absolute
        // value.  Using cube coords (q, r, t = -q-r) the six arms are:
        //   north:  r < -s
        //   south:  r >  s
        //   ne:     t > s   (q + r > s, mirrored across origin from sw)
        //   sw:     t < -s  (q + r < -s)
        //   nw:     q < -s
        //   se:     q >  s
        type ArmPredicate = fn((i16, i16), i16) -> bool;
        let zones: Vec<Zone> = if emit_home_zones {
            let arms: [(&str, ArmPredicate); 6] = [
                ("home_north", |(_, r), s| (r as i32) < -s as i32),
                ("home_south", |(_, r), s| (r as i32) > s as i32),
                ("home_ne", |(q, r), s| (q as i32 + r as i32) > s as i32),
                ("home_sw", |(q, r), s| (q as i32 + r as i32) < -s as i32),
                ("home_nw", |(q, _), s| (q as i32) < -s as i32),
                ("home_se", |(q, _), s| (q as i32) > s as i32),
            ];
            arms.iter()
                .map(|(id, predicate)| {
                    let node_ids: Vec<u16> = coords
                        .iter()
                        .enumerate()
                        .filter(|&(_, &c)| predicate(c, s as i16))
                        .map(|(i, _)| i as u16)
                        .collect();
                    Zone::with_role(*id, node_ids, zone_role::HOME_BASE)
                })
                .collect()
        } else {
            Vec::new()
        };

        StarTopology {
            name,
            coords,
            points,
            edges,
            line_groups,
            labels,
            neighbors,
            zones,
        }
    }
}

impl StarTopology {
    /// Convenience builder.
    #[inline]
    pub fn builder(side: u16) -> StarTopologyBuilder {
        StarTopologyBuilder::new(side)
    }

    /// 121-hole Chinese-Checkers board (`side = 4`).  The most common
    /// commercial variant.
    ///
    /// Total = 1 + 6 * side * (side + 1).
    #[inline]
    pub fn halma_121() -> Self {
        StarTopologyBuilder::new(4)
            .with_name("star.halma_121")
            .build()
    }

    /// 73-hole Chinese-Checkers compact variant (`side = 3`).
    #[inline]
    pub fn halma_73() -> Self {
        StarTopologyBuilder::new(3)
            .with_name("star.halma_73")
            .build()
    }

    /// 37-hole Chinese-Checkers small variant (`side = 2`).
    #[inline]
    pub fn halma_37() -> Self {
        StarTopologyBuilder::new(2)
            .with_name("star.halma_37")
            .build()
    }

    pub fn axial_of(&self, node: u16) -> (i16, i16) {
        self.coords[node as usize]
    }
}

impl BoardTopology for StarTopology {
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

    #[test]
    fn halma_121_has_121_holes() {
        let topo = StarTopology::halma_121();
        assert_eq!(topo.node_count(), 121);
        assert_eq!(topo.name(), "star.halma_121");
    }

    #[test]
    fn halma_73_and_37_match_canonical_counts() {
        // 1 + 6*s*(s+1): s=3 -> 73, s=2 -> 37.
        assert_eq!(StarTopology::halma_73().node_count(), 73);
        assert_eq!(StarTopology::halma_37().node_count(), 37);
    }

    #[test]
    fn centre_cell_has_six_neighbours() {
        let topo = StarTopology::halma_121();
        let centre = topo.node_from_label("q0r0").expect("centre exists");
        assert_eq!(topo.neighbors(centre).len(), 6);
    }

    #[test]
    fn neighbour_relation_is_symmetric() {
        let topo = StarTopology::halma_121();
        for node in 0..topo.node_count() {
            for &n in topo.neighbors(node) {
                assert!(topo.neighbors(n).contains(&node));
            }
        }
    }

    #[test]
    fn six_home_zones_partition_the_arms() {
        let topo = StarTopology::halma_121();
        let mut total = 0;
        let mut seen_ids = std::collections::HashSet::new();
        for zone in topo.zones() {
            assert!(zone.id.starts_with("home_"));
            assert!(seen_ids.insert(zone.id.clone()));
            total += zone.node_ids.len();
        }
        assert_eq!(seen_ids.len(), 6);
        // Each arm contains the triangular cells outside the central
        // hexagon, i.e. 1+2+3+...+(s-1) = s(s-1)/2 = 4*3/2 = 6 wait —
        // the arm size for side `s` is sum_{k=1..s} k = s(s+1)/2.
        // For s=4 that is 10 holes, times six arms = 60 outer holes.
        assert_eq!(total, 60);
    }

    #[test]
    fn home_zones_are_disjoint() {
        let topo = StarTopology::halma_121();
        let mut seen = std::collections::HashSet::new();
        for zone in topo.zones() {
            for &node in &zone.node_ids {
                assert!(
                    seen.insert(node),
                    "node {node} appears in multiple home zones"
                );
            }
        }
    }
}
