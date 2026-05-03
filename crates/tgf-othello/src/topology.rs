// SPDX-License-Identifier: GPL-3.0-or-later
// 8x8 Othello board geometry plus tiny `idx` / `in_bounds` helpers
// shared with `state.rs`.

use tgf_core::board_topology::{BoardTopology, Decoration, Edge, UnitPoint, Zone};

#[derive(Clone, Debug)]
pub struct OthelloTopology {
    points: Vec<UnitPoint>,
    edges: Vec<Edge>,
    zones: Vec<Zone>,
    labels: [&'static str; 64],
    neighbors: Vec<Vec<u16>>,
    /// Rank/file lines (8 + 8) for generic topology consumers (debugging, tooling).
    line_groups: Vec<Vec<u16>>,
}

impl Default for OthelloTopology {
    fn default() -> Self {
        let points = (0..64)
            .map(|i| UnitPoint {
                x: (i % 8) as f32 / 7.0,
                y: (i / 8) as f32 / 7.0,
            })
            .collect::<Vec<_>>();
        let mut edges = Vec::new();
        for r in 0..8 {
            for c in 0..8 {
                if c < 7 {
                    edges.push(Edge::untyped(idx(c, r) as u16, idx(c + 1, r) as u16));
                }
                if r < 7 {
                    edges.push(Edge::untyped(idx(c, r) as u16, idx(c, r + 1) as u16));
                }
            }
        }
        let mut labels: [&'static str; 64] = [""; 64];
        for r in 0..8 {
            for c in 0..8 {
                let i = idx(c, r);
                let file = (b'a' + c as u8) as char;
                let rank = 8 - r;
                labels[i] = leak_label(format!("{file}{rank}"));
            }
        }
        let mut neighbors = vec![Vec::new(); 64];
        for r in 0..8 {
            for c in 0..8 {
                let i = idx(c, r);
                let mut nbr = Vec::new();
                for dy in -1..=1 {
                    for dx in -1..=1 {
                        if dx == 0 && dy == 0 {
                            continue;
                        }
                        let nc = c as i32 + dx;
                        let nr = r as i32 + dy;
                        if in_bounds(nc, nr) {
                            nbr.push(idx(nc as usize, nr as usize) as u16);
                        }
                    }
                }
                nbr.sort_unstable();
                neighbors[i] = nbr;
            }
        }
        let mut line_groups: Vec<Vec<u16>> = Vec::new();
        for r in 0..8 {
            line_groups.push((0..8).map(|c| idx(c, r) as u16).collect());
        }
        for c in 0..8 {
            line_groups.push((0..8).map(|r| idx(c, r) as u16).collect());
        }
        Self {
            points,
            edges,
            zones: Vec::new(),
            labels,
            neighbors,
            line_groups,
        }
    }
}

fn leak_label(s: String) -> &'static str {
    Box::leak(s.into_boxed_str())
}

impl BoardTopology for OthelloTopology {
    fn name(&self) -> &str {
        "othello.8x8"
    }

    fn node_count(&self) -> u16 {
        64
    }

    fn coordinate_of(&self, node: u16) -> UnitPoint {
        self.points[node as usize]
    }

    fn label_of(&self, node: u16) -> &str {
        self.labels.get(node as usize).copied().unwrap_or("")
    }

    fn node_from_label(&self, label: &str) -> Option<u16> {
        let b = label.as_bytes();
        if b.len() != 2 {
            return None;
        }
        let file = b[0].to_ascii_lowercase();
        let rank = b[1];
        if !(b'a'..=b'h').contains(&file) || !(b'1'..=b'8').contains(&rank) {
            return None;
        }
        let c = usize::from(file - b'a');
        let r = 8 - usize::from(rank - b'0');
        Some(idx(c, r) as u16)
    }

    fn neighbors(&self, node: u16) -> &[u16] {
        self.neighbors
            .get(node as usize)
            .map(|v| v.as_slice())
            .unwrap_or(&[])
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

#[inline]
pub(crate) fn idx(c: usize, r: usize) -> usize {
    r * 8 + c
}

#[inline]
pub(crate) fn in_bounds(c: i32, r: i32) -> bool {
    (0..8).contains(&c) && (0..8).contains(&r)
}
