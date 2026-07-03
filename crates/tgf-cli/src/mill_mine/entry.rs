// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

//! The mining pipeline's per-position verdict and JSONL entry record.

use serde::{Deserialize, Serialize};

/// What tier-2/tier-3 concluded about one visited position.
#[derive(Clone, Copy, Debug, Serialize, Deserialize)]
pub(crate) enum Verdict {
    /// Every legal move stays at or above the position's own game-theoretic
    /// value (tier-2 safe), or the engine's near-optimal picks all did
    /// (tier-3 safe) -- no patch entry needed here.
    Safe,
    /// The engine's near-optimal root moves include at least one that drops
    /// below the position's value; `best_child` is the corrective reply.
    Blunder { best_child: u64, severity: i8 },
}

/// One row of the mining pipeline's JSONL output: a position where the
/// configured engine is liable to blunder, plus enough context for the
/// packer, the audit sampler, and human debugging.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub(crate) struct MineEntry {
    /// Canonical `(sector, symmetry-slot)` key, see
    /// `perfect_db::wdl_plane::pack_canonical_key`.
    pub key: u64,
    /// Canonical key of the corrective (DB-optimal) reply.
    pub best_child: u64,
    /// WDL units lost by the engine's actual pick relative to the
    /// position's true value (1 = win/draw or draw/loss confusion, 2 = a
    /// full win/loss reversal).
    pub severity: i8,
    /// 0..=255 heuristic priority for the "make traps" runtime mode, see
    /// `scoring::trap_score`.
    pub trap_score: u8,
    /// Accumulated reach-mass at the time this entry was emitted; the
    /// packer sorts/truncates on this to fit an assets size budget.
    pub mass: f64,
    /// Root position FEN, for human debugging and the packer's audit
    /// sampler. Stripped by the packer's compact on-disk format.
    pub fen: String,
    /// Search depth the tier-3 engine used when it produced this verdict,
    /// for diagnostics (not part of the engine fingerprint contract, which
    /// the packer's file header owns).
    pub depth_used: i32,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mine_entry_round_trips_through_json() {
        let entry = MineEntry {
            key: 0x1234_5678_9abc_def0,
            best_child: 0x0fed_cba9_8765_4321,
            severity: 2,
            trap_score: 200,
            mass: 12345.5,
            fen: "********/********/******** w p p 0 9 0 9 0 0 -1 -1 -1 -1 0 0 1".to_string(),
            depth_used: 12,
        };
        let line = serde_json::to_string(&entry).unwrap();
        let restored: MineEntry = serde_json::from_str(&line).unwrap();
        assert_eq!(restored.key, entry.key);
        assert_eq!(restored.best_child, entry.best_child);
        assert_eq!(restored.severity, entry.severity);
        assert_eq!(restored.trap_score, entry.trap_score);
        assert_eq!(restored.mass, entry.mass);
        assert_eq!(restored.fen, entry.fen);
    }
}
