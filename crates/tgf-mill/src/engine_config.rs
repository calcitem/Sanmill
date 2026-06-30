// SPDX-License-Identifier: AGPL-3.0-or-later
// Mill engine runtime configuration types shared by every front-end
// (FRB, CLI, future REST/UCI proxies).
//
// `MillSearchAlgorithmKind` is the canonical algorithm enumeration —
// both the FRB-public `MillSearchAlgorithm` DTO and the CLI's `u8`
// `algorithm` field convert into this type so the dispatch loop
// (`crates/tgf-frb/src/games/mill/search.rs` and
// `crates/tgf-cli/src/mill_uci/mod.rs::run_algorithm_at_depth`) only
// has to handle one set of variants.
//
// `MillEngineRuntime` collects the per-search runtime knobs that are
// concept-shared across UI / FRB / CLI: skill level, algorithm, IDS
// toggle, time limit, lazy-SMP, etc.  Front-ends that only consume a
// subset (e.g. FRB has no `hash_mb`) ignore the unused fields.

/// Mill search algorithm enumeration.  Mirrors the legacy C++ `Algorithm`
/// enum in `src/types.h` and the Dart-facing `SearchAlgorithm` enum in
/// `general_settings.dart`.  The default is `Mtdf` to match master.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum MillSearchAlgorithmKind {
    /// Fail-soft alpha-beta (master Algorithm = 0 / 1).
    AlphaBeta,
    /// Principal Variation Search.
    Pvs,
    /// MTD(f) — Memory-enhanced Test Driver (master default).
    #[default]
    Mtdf,
    /// Monte Carlo Tree Search.
    Mcts,
    /// Pick a random legal action (testing / SkillLevel = 0).
    Random,
}

impl MillSearchAlgorithmKind {
    /// Decode a master-style `algorithm` byte (0..=4) into the typed
    /// variant, falling back to `Pvs` for unknown values so the engine
    /// still produces a deterministic move.
    pub fn from_legacy_byte(value: u8) -> Self {
        match value {
            0 | 1 => Self::AlphaBeta,
            2 => Self::Mtdf,
            3 => Self::Mcts,
            4 => Self::Random,
            _ => Self::Pvs,
        }
    }
}

/// Mill engine runtime configuration shared by every front-end.
///
/// Front-ends populate the fields they care about (the FRB DTO maps
/// only six of them; the CLI populates them all) and pass the result
/// down into `crates/tgf-frb::games::mill::search` /
/// `crates/tgf-cli::mill_uci`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MillEngineRuntime {
    /// SkillLevel in 0..=30.  Drives MCTS iteration count and the
    /// `Mills::get_search_depth` table dispatch.
    pub skill_level: u8,
    /// Search algorithm to dispatch.
    pub algorithm: MillSearchAlgorithmKind,
    /// Apply master's `AiIsLazy` depth adjustment from
    /// `search_engine.cpp`.
    pub ai_is_lazy: bool,
    /// Run iterative deepening when `move_time_ms > 0` or this flag is
    /// set explicitly.
    pub ids_enabled: bool,
    /// Allow single-move depth extension.
    pub depth_extension: bool,
    /// Last bestValue from the previous turn's search.  Used by
    /// `ai_is_lazy` to cap origin_depth.
    pub last_best_value: i32,
    /// Time budget for the entire search, in milliseconds.  `0` means
    /// unbounded — depth alone drives termination.
    pub move_time_ms: u32,
    /// Shuffle root move list.
    pub shuffling: bool,
    /// Draw on human experience tweak from master `Mills::get_search_depth`.
    pub draw_on_human_experience: bool,
    /// Developer-mode tables (more accurate but expensive at high depth).
    pub developer_mode: bool,
    /// Transposition-table size in megabytes.
    pub hash_mb: u32,
    /// Reserve UCI `ponder` flag for future use.
    pub ponder: bool,
    /// Run lazy-SMP fan-out instead of single-thread search.
    pub use_lazy_smp: bool,
}

impl Default for MillEngineRuntime {
    fn default() -> Self {
        Self {
            skill_level: 1,
            algorithm: MillSearchAlgorithmKind::default(),
            ai_is_lazy: false,
            ids_enabled: false,
            depth_extension: true,
            last_best_value: 0,
            move_time_ms: 0,
            shuffling: true,
            draw_on_human_experience: true,
            developer_mode: true,
            hash_mb: 16,
            ponder: false,
            use_lazy_smp: false,
        }
    }
}
