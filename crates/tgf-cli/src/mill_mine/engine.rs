// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

//! Deterministic `Searcher<MillGame>` configuration for the mining
//! pipeline's tier-3 (expensive) criticality judgment.
//!
//! Mirrors the AI play-style toggles requested for the mining opponent:
//! algorithm MTD(f), "draw on human experience" on (via
//! `recommended_search_depth`), "consider mobility" on / "focus on blocking
//! paths" off (the `MillVariantOptions` defaults already match this),
//! "passive" off (no `ai_is_lazy` depth cap -- see the comment on
//! `recommended_search_depth`'s call site in `mill_uci/mod.rs`, which only
//! applies that cap when `ai_is_lazy` is set), and multi-threaded search
//! off (one single-threaded `Searcher` per worker). "AI plays randomly" is
//! emulated deterministically by widening the accepted root-move set to a
//! score margin instead of actually shuffling -- see [`CriticalityVerdict`].
//!
//! The search itself is always deterministic (fixed seed, cleared TT,
//! `shuffling: false`) so a mined verdict for a given engine fingerprint is
//! reproducible and safely cacheable across worker threads / resumed runs.

use tgf_core::{Action, Game, GameStateSnapshot, MoveOrderAlgorithm, MoveOrderContext};
use tgf_mill::search_depth::{EngineRuntimeOptions, recommended_search_depth};
use tgf_mill::{MillActionKind, MillGame, MillRules, MillVariantOptions};
use tgf_search::{SearchOptions, SearchPolicy, Searcher};

/// Fixed seed for the searcher's xorshift PRNG. Mining never wants
/// randomised play (see module docs); a non-zero constant just avoids the
/// xorshift all-zero attractor, mirroring `tgf-cli selfplay`.
const MINING_SEARCH_SEED: u64 = 0xA1B2_C3D4_5566_7788;

#[derive(Clone, Copy, Debug)]
pub(crate) struct EngineConfig {
    /// Fixed search depth override; `0` means "derive per-position from
    /// [`recommended_search_depth`]" (the default, matching real gameplay).
    pub depth_override: i32,
    pub skill_level: u8,
    /// Root moves within this many score units of the best move are
    /// treated as "the engine might actually play any of these" -- the
    /// deterministic stand-in for the runtime's "AI random move" switch
    /// (see module docs). `0` keeps only the single best-scored action(s).
    pub near_optimal_margin: i32,
}

impl Default for EngineConfig {
    fn default() -> Self {
        Self {
            depth_override: 0,
            skill_level: 30,
            near_optimal_margin: 0,
        }
    }
}

/// The engine's plausible root choices at one mined position.
pub(crate) struct CriticalityVerdict {
    /// Near-optimal actions, most-preferred (highest search value) first.
    /// Always non-empty for a non-terminal position with legal moves.
    pub near_optimal: Vec<Action>,
    pub depth_used: i32,
}

/// One worker's private, reusable search state. Not `Send`-shared: each
/// mining worker thread owns exactly one.
pub(crate) struct MiningEngine {
    game: MillGame,
    searcher: Searcher<MillGame>,
    options: MillVariantOptions,
    config: EngineConfig,
}

impl MiningEngine {
    pub(crate) fn new(options: MillVariantOptions, config: EngineConfig) -> Self {
        let game = MillGame::new(options.clone());
        let mut searcher = Searcher::<MillGame>::new();
        searcher.set_policy(SearchPolicy {
            quiescence_kind_tag: Some(MillActionKind::Remove as i16),
            ..Default::default()
        });
        searcher.set_root_move_summaries_enabled(true);
        Self {
            game,
            searcher,
            options,
            config,
        }
    }

    /// Run the deterministic tier-3 search at `snap` and return the
    /// near-optimal root move set.
    ///
    /// `snap` must be a non-terminal position with at least one legal
    /// action (callers are expected to have already filtered terminal /
    /// no-legal-move positions out via the cheap tier-1/tier-2 checks).
    pub(crate) fn evaluate(&mut self, snap: &GameStateSnapshot) -> CriticalityVerdict {
        let state = MillRules::decode_snapshot(*snap);
        let depth = if self.config.depth_override > 0 {
            self.config.depth_override
        } else {
            let runtime = EngineRuntimeOptions {
                skill_level: self.config.skill_level,
                draw_on_human_experience: true,
                developer_mode: true,
            };
            recommended_search_depth(&state, &self.options, &runtime).max(1)
        };

        self.searcher.clear_tt();
        self.searcher.set_random_seed(MINING_SEARCH_SEED);
        self.searcher.set_options(SearchOptions {
            depth_extension: true,
            node_limit: None,
            time_limit_ms: None,
            allow_null_move: false,
            shuffle_root: false,
            enable_prefetch: false,
            prefetch_all: false,
            enable_aspiration_window: false,
            move_order_context: MoveOrderContext {
                algorithm: MoveOrderAlgorithm::Mtdf,
                skill_level: self.config.skill_level,
                shuffling: false,
                hash_move: None,
                shuffle_seed: 0,
            },
        });

        let mut workbench = self.game.build_workbench(snap);
        let result = self.searcher.search_mtdf(&mut workbench, depth);

        // `search_mtdf`'s recorded root-move values come from the final
        // zero-window probe and can be alpha/beta-bounded rather than exact
        // (see `iterative_mtdf.rs`); the returned `result.score` is the
        // authoritative converged value, so it anchors the margin even if no
        // recorded summary happens to equal it exactly.
        let mut summaries = self.searcher.root_moves().to_vec();
        let top_value = summaries
            .iter()
            .map(|m| m.value)
            .fold(result.score, i32::max);
        let margin = self.config.near_optimal_margin.max(0);
        summaries.retain(|m| m.value >= top_value - margin);
        summaries.sort_by_key(|m| std::cmp::Reverse(m.value));

        let mut near_optimal: Vec<Action> = summaries.into_iter().map(|m| m.action).collect();
        if !result.best_action.is_none() && !near_optimal.contains(&result.best_action) {
            near_optimal.insert(0, result.best_action);
        }
        assert!(
            !near_optimal.is_empty(),
            "MiningEngine::evaluate must be called on a position with a legal move"
        );
        CriticalityVerdict {
            near_optimal,
            depth_used: depth,
        }
    }

    /// Raw root-move summaries from the most recent [`Self::evaluate`] call,
    /// for diagnostics / manual audits.
    #[cfg(test)]
    pub(crate) fn debug_root_moves(&self) -> &[tgf_search::RootMoveSummary] {
        self.searcher.root_moves()
    }
}
