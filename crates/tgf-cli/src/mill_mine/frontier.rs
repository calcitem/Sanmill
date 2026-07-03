// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

//! Mass-ordered frontier: the mining loop always expands the position with
//! the highest accumulated "how likely is a real game to reach this"
//! weight, so an interrupted/budget-limited run's output is exactly the
//! highest-value prefix rather than an arbitrary partial traversal order.

use std::cmp::Ordering;
use std::collections::BinaryHeap;

use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize)]
pub(crate) struct FrontierItem {
    pub mass: f64,
    pub fen: String,
    pub depth: u32,
}

impl PartialEq for FrontierItem {
    fn eq(&self, other: &Self) -> bool {
        self.mass == other.mass
    }
}
impl Eq for FrontierItem {}
impl PartialOrd for FrontierItem {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}
impl Ord for FrontierItem {
    fn cmp(&self, other: &Self) -> Ordering {
        // Mass is always constructed finite and non-negative (see `push`),
        // so a total order via `partial_cmp` never actually falls through
        // to the `Equal` fallback.
        self.mass
            .partial_cmp(&other.mass)
            .unwrap_or(Ordering::Equal)
    }
}

#[derive(Default)]
pub(crate) struct Frontier {
    heap: BinaryHeap<FrontierItem>,
}

impl Frontier {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn push(&mut self, item: FrontierItem) {
        assert!(
            item.mass.is_finite() && item.mass >= 0.0,
            "frontier mass must be finite and non-negative, got {}",
            item.mass
        );
        self.heap.push(item);
    }

    pub fn pop(&mut self) -> Option<FrontierItem> {
        self.heap.pop()
    }

    pub fn len(&self) -> usize {
        self.heap.len()
    }

    /// Snapshot the current contents (checkpoint save); does not drain.
    pub fn snapshot(&self) -> Vec<FrontierItem> {
        self.heap.iter().cloned().collect()
    }

    pub fn extend(&mut self, items: impl IntoIterator<Item = FrontierItem>) {
        for item in items {
            self.push(item);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pops_highest_mass_first() {
        let mut frontier = Frontier::new();
        frontier.push(FrontierItem {
            mass: 1.0,
            fen: "a".to_string(),
            depth: 0,
        });
        frontier.push(FrontierItem {
            mass: 5.0,
            fen: "b".to_string(),
            depth: 0,
        });
        frontier.push(FrontierItem {
            mass: 3.0,
            fen: "c".to_string(),
            depth: 0,
        });
        assert_eq!(frontier.pop().unwrap().fen, "b");
        assert_eq!(frontier.pop().unwrap().fen, "c");
        assert_eq!(frontier.pop().unwrap().fen, "a");
        assert!(frontier.pop().is_none());
    }

    #[test]
    #[should_panic(expected = "finite and non-negative")]
    fn rejects_negative_mass() {
        let mut frontier = Frontier::new();
        frontier.push(FrontierItem {
            mass: -1.0,
            fen: "a".to_string(),
            depth: 0,
        });
    }
}
