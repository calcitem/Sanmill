// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

//! Frontier expansion policy: which children of a visited position keep
//! getting explored, and with how much of its mass.
//!
//! A DB-optimal move is, by construction, the single hardest continuation
//! for whoever is about to face it -- "ranking moves by how testing they
//! are for the mover" and "ranking replies by how testing they are for the
//! opponent" are the same ranking viewed from opposite ends of the same
//! edge. So there is exactly one ranking here, not a separate
//! "engine policy" vs. "adversary policy": most of the mass (`1 - epsilon`)
//! follows the `top_k` optimal replies ranked hardest-to-convert-against
//! first (longest precise distance-to-conversion, since a defender forced
//! to survive longer sees more of the tree and is more likely to slip), and
//! a small `epsilon` slice follows the single least-bad *non*-optimal reply
//! -- the most plausible realistic mistake -- so mining also reaches won
//! positions that need to be *converted*, which a perfect opponent would
//! otherwise never allow.

use perfect_db::database::{Database, DatabaseProvider};
use perfect_db::evaluate_state_outcome_with_database;
use tgf_core::{Action, GameRules, GameStateSnapshot};
use tgf_mill::{MillRules, MillVariantOptions};

use super::canonical_key_for_state;
use crate::mill_mine::frontier::FrontierItem;

pub(crate) struct RankedChild {
    /// Kept for debugging / future audit tooling even though the runtime
    /// protocol only ever needs `key` (see the module docs on why patch
    /// entries reference canonical child keys instead of concrete actions).
    #[allow(dead_code)]
    pub action: Action,
    pub key: u64,
    pub fen: String,
    pub value: i8,
}

pub(crate) struct RankedChildren {
    /// Optimal (`value == best_value`) children, hardest first. Non-empty
    /// whenever `move_wdl` is non-empty. `.first()` is what both the
    /// mining-exploration policy (see `expansion_edges`) *and* the patch's
    /// `best_child` correction use.
    ///
    /// This looks backwards for the correction use at first glance --
    /// wouldn't the fastest conversion (fewest steps) be the safer
    /// real-game recommendation, since it minimizes how many further,
    /// unpatched engine moves must still be got right? Measured head-to-head
    /// in `mill-arena` it is not: preferring fewest-steps for the
    /// correction measurably *increased* the patched engine's loss rate
    /// over 48 full games versus preferring most-steps (this module's
    /// original, "hardest to convert" choice), even with substantially more
    /// mined coverage. The most-steps reply is typically the less
    /// tactically-sharp one (more mobility, fewer only-moves), which is
    /// more forgiving of the engine's own imperfect, un-patched follow-up
    /// than a narrow fast conversion would be. Keep this ranking as the
    /// single source for both uses unless a future change is validated the
    /// same way (`mill arena --patch` before/after, not just the packer's
    /// per-entry WDL audit, which cannot see this multi-move effect at
    /// all).
    pub optimal: Vec<RankedChild>,
    /// The least-bad non-optimal child, if any legal move actually throws
    /// value away.
    pub epsilon_pick: Option<RankedChild>,
    pub best_value: i8,
}

/// Rank every legal child of `snap` (already evaluated by the tier-2
/// pre-filter as `move_wdl`) into the optimal set (steps-ranked, hardest
/// first) and the single best "plausible mistake" pick.
pub(crate) fn rank_children<P: DatabaseProvider>(
    rules: &MillRules,
    options: &MillVariantOptions,
    db: &mut Database<P>,
    planes: &mut perfect_db::wdl_plane::WdlPlaneCache<P>,
    snap: &GameStateSnapshot,
    move_wdl: &[(Action, i8)],
) -> RankedChildren {
    let best_value = move_wdl
        .iter()
        .map(|&(_, value)| value)
        .max()
        .expect("rank_children requires at least one legal move");

    let mut optimal_with_steps: Vec<(RankedChild, i32)> = Vec::new();
    let mut epsilon_pick: Option<RankedChild> = None;

    for &(action, value) in move_wdl {
        let child_snap = rules.apply(snap, action);
        let child_state = MillRules::decode_snapshot(child_snap);
        let Some(key) = canonical_key_for_state(&child_state, options, planes) else {
            // Unsupported variant/side for this child; cannot be a
            // meaningful expansion target or replacement action.
            continue;
        };
        let fen = rules.export_fen(&child_state);

        if value == best_value {
            let side = child_state.side_to_move();
            let steps = match evaluate_state_outcome_with_database(db, &child_state, options, side)
            {
                Ok(Some(outcome)) => outcome.steps(),
                _ => 0,
            };
            optimal_with_steps.push((
                RankedChild {
                    action,
                    key,
                    fen,
                    value,
                },
                steps,
            ));
        } else if epsilon_pick.as_ref().is_none_or(|best| value > best.value) {
            epsilon_pick = Some(RankedChild {
                action,
                key,
                fen,
                value,
            });
        }
    }

    // Longest distance-to-conversion first: the position stays "alive"
    // (and thus keeps generating fresh mining coverage) the longest, and
    // for a mover who is ahead this is also the most testing choice for
    // the opponent to survive.
    optimal_with_steps.sort_by_key(|(_, steps)| std::cmp::Reverse(*steps));
    let optimal = optimal_with_steps
        .into_iter()
        .map(|(child, _)| child)
        .collect();

    RankedChildren {
        optimal,
        epsilon_pick,
        best_value,
    }
}

#[derive(Clone, Copy, Debug)]
pub(crate) struct AdversaryPolicy {
    pub top_k: usize,
    pub epsilon: f64,
}

impl Default for AdversaryPolicy {
    fn default() -> Self {
        Self {
            top_k: 3,
            epsilon: 0.15,
        }
    }
}

/// Turn a ranking into frontier items, splitting `mass` per the policy.
pub(crate) fn expansion_edges(
    ranked: &RankedChildren,
    policy: AdversaryPolicy,
    mass: f64,
    depth: u32,
) -> Vec<FrontierItem> {
    let mut edges = Vec::new();
    let top_k = policy.top_k.max(1).min(ranked.optimal.len().max(1));
    let has_epsilon_target = ranked.epsilon_pick.is_some();
    let optimal_mass_share = if ranked.optimal.is_empty() {
        0.0
    } else if has_epsilon_target {
        (1.0 - policy.epsilon) * mass / top_k as f64
    } else {
        mass / top_k as f64
    };

    for child in ranked.optimal.iter().take(top_k) {
        edges.push(FrontierItem {
            mass: optimal_mass_share,
            fen: child.fen.clone(),
            depth,
        });
    }

    if let Some(child) = &ranked.epsilon_pick {
        edges.push(FrontierItem {
            mass: policy.epsilon * mass,
            fen: child.fen.clone(),
            depth,
        });
    }

    edges
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn expansion_edges_split_mass_between_optimal_and_epsilon() {
        let ranked = RankedChildren {
            optimal: vec![
                RankedChild {
                    action: Action::NONE,
                    key: 1,
                    fen: "opt1".to_string(),
                    value: 1,
                },
                RankedChild {
                    action: Action::NONE,
                    key: 2,
                    fen: "opt2".to_string(),
                    value: 1,
                },
            ],
            epsilon_pick: Some(RankedChild {
                action: Action::NONE,
                key: 3,
                fen: "mistake".to_string(),
                value: 0,
            }),
            best_value: 1,
        };
        let policy = AdversaryPolicy {
            top_k: 2,
            epsilon: 0.2,
        };
        let edges = expansion_edges(&ranked, policy, 100.0, 1);
        assert_eq!(edges.len(), 3);
        let total_mass: f64 = edges.iter().map(|e| e.mass).sum();
        assert!((total_mass - 100.0).abs() < 1e-9);
        let mistake_edge = edges.iter().find(|e| e.fen == "mistake").unwrap();
        assert!((mistake_edge.mass - 20.0).abs() < 1e-9);
    }

    #[test]
    fn expansion_edges_without_mistake_uses_full_mass_on_optimal() {
        let ranked = RankedChildren {
            optimal: vec![RankedChild {
                action: Action::NONE,
                key: 1,
                fen: "only".to_string(),
                value: 1,
            }],
            epsilon_pick: None,
            best_value: 1,
        };
        let edges = expansion_edges(&ranked, AdversaryPolicy::default(), 50.0, 0);
        assert_eq!(edges.len(), 1);
        assert!((edges[0].mass - 50.0).abs() < 1e-9);
    }
}
